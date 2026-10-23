import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Bot } from "./bot.mjs";
import { checkSetting, MAX_DOWNLOAD, operateTools, runOp, SETTINGS } from "./operate.mjs";

async function setup(over = {}) {
	const dir = await mkdtemp(join(tmpdir(), "look-operate-"));
	const bot = new Bot(dir);
	await bot.load();
	const calls = [];
	const lookd = {
		"GET /api/settings": { "download.video_parallel": 2, "asr.concurrency": 2 },
		"GET /api/jobs": [
			{ id: "j1", state: "running", title: "第 1 节", kind: "video" },
			{ id: "j2", state: "paused", title: "第 2 节", kind: "video" },
			{ id: "j3", state: "queued", title: "第 3 节", kind: "slides" },
		],
		"GET /api/courses": [{ id: "c1", title: "高等数学", alias: "", pinned: false, hidden: false, color: "" }],
		"GET /api/lectures/l1": { lecture: { id: "l1", title: "第 1 节", date: "2026-09-01" } },
		...over.lookd,
	};
	const api = async (method, path, body) => {
		calls.push({ method, path, body });
		const k = `${method} ${path}`;
		if (k in lookd) return lookd[k];
		if (method === "GET") throw Object.assign(new Error("not found"), { status: 404 });
		return { ok: true, changed: body?.ids?.length ?? 0 };
	};
	const prefs = { provider: "p", model: "m1", thinking: "medium" };
	const deps = {
		bot,
		api,
		appState: () => ({ textScale: 1, themeMode: "system" }),
		pipeline: {
			prefs,
			describe: async () => ({ providers: [{ id: "p", models: [{ id: "m1", available: true }, { id: "m2", available: true }, { id: "m3", available: false }] }] }),
			setPrefs: async (patch) => Object.assign(prefs, patch),
		},
		tasks: { create: async (t) => ({ id: "t1", ...t }), remove: async () => {} },
		plugins: { list: async () => [{ id: "demo", name: "Demo", enabled: true }], update: async () => {} },
	};
	const tools = Object.fromEntries(operateTools(deps).map((t) => [t.name, t]));
	return { bot, calls, deps, tools, prefs, done: () => rm(dir, { recursive: true, force: true }) };
}

test("the registry validates values and lists no secret", () => {
	assert.equal(checkSetting("textScale", 1.2), 1.2);
	assert.throws(() => checkSetting("textScale", 3), /0.8–1.5/);
	assert.throws(() => checkSetting("seekStepSec", 7.5), /整数/);
	assert.throws(() => checkSetting("themeMode", "blue"), /system/);
	assert.throws(() => checkSetting("mineru.token", "x"), /不能修改/);
	assert.throws(() => checkSetting("download.rate_limit", 3), /只能是/);
	for (const k of Object.keys(SETTINGS)) assert.doesNotMatch(k, /token|key|password|secret|auth|root/i);
});

test("low-risk settings apply at once with undo; the rest become a card", async () => {
	const { tools, bot, calls, done } = await setup();
	try {
		const r = await tools.change_settings.execute("1", {
			changes: [
				{ key: "textScale", value: 1.2 },
				{ key: "download.video_parallel", value: 3 },
				{ key: "model", value: "p/m2" },
			],
			reason: "用户想加快下载",
		});
		assert.deepEqual(r.details.app.set, { textScale: 1.2 });
		assert.equal(r.details.proposal.state, "pending");
		assert.equal(calls.filter((c) => c.method !== "GET").length, 0, "nothing reaches lookd before the card is applied");
		const immediate = bot.proposal(r.details.app.proposal_id);
		assert.deepEqual(immediate.undo, { type: "app", set: { textScale: 1 } });
		const pending = bot.proposal(r.details.proposal.id);
		assert.deepEqual(pending.op.lookd, { "download.video_parallel": 3 });
		assert.deepEqual(pending.op.agent, { model: "p/m2" });
		assert.deepEqual(pending.undo.lookd, { "download.video_parallel": 2 });
		await assert.rejects(tools.change_settings.execute("2", { changes: [{ key: "model", value: "p/m3" }], reason: "" }), /不可用/);
	} finally {
		await done();
	}
});

test("applying a settings card writes lookd and the assistant prefs", async () => {
	const { deps, calls, prefs, done } = await setup();
	try {
		const r = await runOp({ type: "settings", app: { contrast: "high" }, lookd: { "asr.concurrency": 3 }, agent: { model: "p/m2", thinking: "low" } }, deps);
		assert.deepEqual(r, { app: { contrast: "high" } });
		assert.deepEqual(calls.at(-1), { method: "PUT", path: "/api/settings", body: { "asr.concurrency": 3 } });
		assert.equal(prefs.provider, "p");
		assert.equal(prefs.model, "m2");
		assert.equal(prefs.thinking, "low");
	} finally {
		await done();
	}
});

test("download pause acts on matching jobs and records its undo", async () => {
	const { tools, bot, calls, done } = await setup();
	try {
		const r = await tools.manage_downloads.execute("1", { action: "pause" });
		assert.deepEqual(calls.at(-1), { method: "POST", path: "/api/jobs/bulk", body: { action: "pause", ids: ["j1", "j3"] } });
		const p = bot.proposal(r.details.app.proposal_id);
		assert.deepEqual(p.undo, { type: "jobs", action: "resume", ids: ["j1", "j3"] });
		const none = await tools.manage_downloads.execute("2", { action: "retry" });
		assert.match(none.content[0].text, /没有符合条件/);
	} finally {
		await done();
	}
});

test("downloads and deletions only make cards", async () => {
	const { tools, bot, calls, done } = await setup();
	try {
		const r = await tools.download.execute("1", { lecture_ids: ["l1", "l1"], kinds: ["video", "transcript"] });
		const p = bot.proposal(r.details.proposal.id);
		assert.deepEqual(p.op, { type: "download", lecture_ids: ["l1"], kinds: ["video", "transcript"] });
		assert.equal(calls.filter((c) => c.method !== "GET").length, 0);
		await assert.rejects(tools.download.execute("2", { lecture_ids: ["nope"], kinds: ["video"] }), /没有节次/);
		await assert.rejects(tools.download.execute("3", { lecture_ids: Array.from({ length: MAX_DOWNLOAD + 1 }, (_, i) => `x${i}`), kinds: ["video"] }), /最多/);
		const d = await tools.delete_files.execute("4", { lecture_id: "l1", kinds: ["video"] });
		assert.equal(d.details.proposal.state, "pending");
		assert.equal(calls.filter((c) => c.method === "DELETE").length, 0);
	} finally {
		await done();
	}
});

test("course changes apply at once and undo to the previous values", async () => {
	const { tools, bot, deps, calls, done } = await setup();
	try {
		const r = await tools.manage_course.execute("1", { course_id: "c1", pinned: true, color: "teal" });
		assert.deepEqual(calls.at(-1), { method: "PATCH", path: "/api/courses/c1", body: { pinned: true, color: "#2E6E6A" } });
		const p = bot.proposal(r.details.app.proposal_id);
		await runOp(p.undo, deps);
		assert.deepEqual(calls.at(-1).body, { pinned: false, color: "" });
		await assert.rejects(tools.manage_course.execute("2", { course_id: "c9", pinned: true }), /没有课程/);
	} finally {
		await done();
	}
});

test("task and plugin proposals are validated", async () => {
	const { tools, bot, deps, done } = await setup();
	try {
		await assert.rejects(tools.propose_task.execute("1", { name: "x", prompt: "y", schedule: { type: "daily", time: "25:00" } }), /HH:MM/);
		const r = await tools.propose_task.execute("2", { name: "周复习", prompt: "复习本周课程", schedule: { type: "weekly", days: [7], time: "20:00" }, writes: ["notes"] });
		const p = bot.proposal(r.details.proposal.id);
		assert.equal((await runOp(p.op, deps)).task_id, "t1");
		await assert.rejects(tools.toggle_plugin.execute("3", { id: "ghost", enabled: true }), /没有安装/);
		const same = await tools.toggle_plugin.execute("4", { id: "demo", enabled: true });
		assert.match(same.content[0].text, /已经是/);
		const off = await tools.toggle_plugin.execute("5", { id: "demo", enabled: false });
		assert.deepEqual(bot.proposal(off.details.proposal.id).undo, { type: "plugin", id: "demo", enabled: true });
	} finally {
		await done();
	}
});

test("open_page needs the id its target names", async () => {
	const { tools, done } = await setup();
	try {
		await assert.rejects(tools.open_page.execute("1", { target: "lecture" }), /lecture_id/);
		const r = await tools.open_page.execute("2", { target: "lecture", lecture_id: "l1", t: 90 });
		assert.deepEqual(r.details.app, { op: "open", target: "lecture", lecture_id: "l1", t: 90 });
	} finally {
		await done();
	}
});
