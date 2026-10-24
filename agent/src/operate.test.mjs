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
		"GET /api/lectures/l1": { lecture: { id: "l1", title: "第 1 节", date: "2026-09-01", has_playback: true, assets: [] } },
		"GET /api/courses/c1/lectures": {
			course: { id: "c1", title: "高等数学" },
			lectures: [
				{ id: "l4", title: "第 4 节", date: "2026-09-22", has_playback: true, assets: [], segments: 0 },
				{ id: "l2", title: "第 2 节", date: "2026-09-08", has_playback: true, assets: ["video"], segments: 0 },
				{ id: "l1", title: "第 1 节", date: "2026-09-01", has_playback: true, assets: ["video"], segments: 120 },
				{ id: "l3", title: "第 3 节", date: "2026-09-15", has_playback: true, assets: [], segments: 0 },
				{ id: "l5", title: "第 5 节", date: "2026-09-29", has_playback: false, assets: [], segments: 0 },
			],
		},
		...over.lookd,
	};
	const api = async (method, path, body) => {
		calls.push({ method, path, body });
		const k = `${method} ${path}`;
		if (k in lookd) return lookd[k];
		if (k === "POST /api/jobs") return body.lecture_ids.flatMap((id) => body.kinds.map((kind) => ({ id: `${id}-${kind}`, lecture_id: id, kind, state: "queued" })));
		if (method === "GET") throw Object.assign(new Error("not found"), { status: 404 });
		return { ok: true, changed: body?.ids?.length ?? 0 };
	};
	const prefs = { provider: "p", model: "m1", thinking: "medium", approval: over.approval ?? "auto" };
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

test("settings apply at once with undo, across the app, lookd and the assistant", async () => {
	const { tools, bot, calls, prefs, done } = await setup();
	try {
		const r = await tools.change_settings.execute("1", {
			changes: [
				{ key: "textScale", value: 1.2 },
				{ key: "download.video_parallel", value: 3 },
				{ key: "model", value: "p/m2" },
			],
		});
		assert.equal(r.details.app.op, "prefs");
		assert.deepEqual(r.details.app.set, { textScale: 1.2 });
		assert.deepEqual(calls.at(-1), { method: "PUT", path: "/api/settings", body: { "download.video_parallel": 3 } });
		assert.equal(prefs.model, "m2");
		const p = bot.proposal(r.details.app.proposal_id);
		assert.equal(p.state, "applied");
		assert.deepEqual(p.undo, { type: "settings", app: { textScale: 1 }, lookd: { "download.video_parallel": 2 }, agent: { model: "p/m1" } });
		await assert.rejects(tools.change_settings.execute("2", { changes: [{ key: "model", value: "p/m3" }] }), /不可用/);
	} finally {
		await done();
	}
});

test("ask mode turns a change into a card and sends nothing first", async () => {
	const { tools, bot, calls, done } = await setup({ approval: "ask" });
	try {
		const r = await tools.change_settings.execute("1", { changes: [{ key: "textScale", value: 1.2 }, { key: "asr.concurrency", value: 3 }] });
		assert.equal(r.details.proposal.state, "pending");
		assert.equal(r.details.app, undefined);
		assert.equal(calls.filter((c) => c.method !== "GET").length, 0);
		assert.deepEqual(bot.proposal(r.details.proposal.id).op, { type: "settings", app: { textScale: 1.2 }, lookd: { "asr.concurrency": 3 }, agent: {} });
		const d = await tools.download.execute("2", { course_id: "c1", latest: 1, kinds: ["video"] });
		assert.equal(d.details.proposal.state, "pending");
		assert.equal(calls.filter((c) => c.method === "POST").length, 0);
		assert.match(d.content[0].text, /不要声称/);
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

test("download jobs pause and cancel with their undo", async () => {
	const { tools, bot, deps, calls, done } = await setup();
	try {
		const r = await tools.manage_downloads.execute("1", { action: "pause" });
		assert.deepEqual(calls.at(-1), { method: "POST", path: "/api/jobs/bulk", body: { action: "pause", ids: ["j1", "j3"] } });
		assert.deepEqual(bot.proposal(r.details.app.proposal_id).undo, { type: "jobs", action: "resume", ids: ["j1", "j3"] });
		const none = await tools.manage_downloads.execute("2", { action: "retry" });
		assert.match(none.content[0].text, /没有符合条件/);
		const c = await tools.manage_downloads.execute("3", { action: "cancel", job_ids: ["j2"] });
		const undo = bot.proposal(c.details.app.proposal_id).undo;
		assert.equal(undo.type, "requeue");
		await runOp(undo, deps);
		assert.deepEqual(calls.at(-1), { method: "POST", path: "/api/jobs", body: { lecture_ids: [undefined], kinds: ["video"] } });
	} finally {
		await done();
	}
});

test("download picks a course's lectures by date or latest and skips what is local", async () => {
	const { tools, bot, calls, done } = await setup();
	try {
		const r = await tools.download.execute("1", { course_id: "c1", from: "2026-09-01", to: "2026-09-15", kinds: ["video", "transcript"] });
		const posts = calls.filter((c) => c.method === "POST");
		// l1 has both, l2 needs only the transcript, l3 needs both.
		assert.deepEqual(
			posts.map((c) => c.body),
			[
				{ lecture_ids: ["l2"], kinds: ["transcript"] },
				{ lecture_ids: ["l3"], kinds: ["video", "transcript"] },
			],
		);
		assert.match(r.content[0].text, /1 节已在本机/);
		const p = bot.proposal(r.details.app.proposal_id);
		assert.equal(p.state, "applied");
		assert.deepEqual(p.undo, { type: "jobs", action: "cancel", ids: ["l2-transcript", "l3-video", "l3-transcript"] });
		await tools.download.execute("2", { course_id: "c1", latest: 2, kinds: ["slides"] });
		assert.deepEqual(calls.at(-1).body, { lecture_ids: ["l3", "l4"], kinds: ["slides"] }, "latest counts recorded lectures only");
		const none = await tools.download.execute("3", { course_id: "c1", to: "2026-09-01", kinds: ["video", "transcript"] });
		assert.match(none.content[0].text, /不用下载/);
		await assert.rejects(tools.download.execute("4", { lecture_ids: ["nope"], kinds: ["video"] }), /没有节次/);
		await assert.rejects(tools.download.execute("5", { kinds: ["video"] }), /course_id/);
		await assert.rejects(tools.download.execute("6", { course_id: "c1", from: "9月1日", kinds: ["video"] }), /YYYY-MM-DD/);
	} finally {
		await done();
	}
});

test("download undo leaves jobs that were already running", async () => {
	const { tools, bot, done } = await setup({ lookd: { "GET /api/jobs": [{ id: "l3-video", state: "running", kind: "video" }] } });
	try {
		const r = await tools.download.execute("1", { lecture_ids: ["l1"], kinds: ["video"], redownload: true });
		assert.deepEqual(bot.proposal(r.details.app.proposal_id).undo, { type: "jobs", action: "cancel", ids: ["l1-video"] });
		assert.ok(MAX_DOWNLOAD >= 50);
	} finally {
		await done();
	}
});

test("deleting files always waits for a card", async () => {
	const { tools, bot, deps, calls, done } = await setup();
	try {
		const d = await tools.delete_files.execute("1", { lecture_ids: ["l1"], kinds: ["video"] });
		assert.equal(d.details.proposal.state, "pending");
		assert.equal(calls.filter((c) => c.method === "DELETE").length, 0);
		await runOp(bot.proposal(d.details.proposal.id).op, deps);
		assert.deepEqual(calls.at(-1), { method: "DELETE", path: "/api/lectures/l1/assets/video", body: undefined });
		await runOp({ type: "delete_files", lecture_id: "l1", kinds: ["slides"] }, deps);
		assert.equal(calls.at(-1).path, "/api/lectures/l1/assets/slides", "older cards still apply");
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

test("tasks and plugins are created and switched at once with undo", async () => {
	const { tools, bot, done } = await setup();
	try {
		await assert.rejects(tools.create_task.execute("1", { name: "x", prompt: "y", schedule: { type: "daily", time: "25:00" } }), /HH:MM/);
		const r = await tools.create_task.execute("2", { name: "周复习", prompt: "复习本周课程", schedule: { type: "weekly", days: [7], time: "20:00" }, writes: ["notes"] });
		assert.deepEqual(bot.proposal(r.details.app.proposal_id).undo, { type: "delete_task", id: "t1" });
		await assert.rejects(tools.toggle_plugin.execute("3", { id: "ghost", enabled: true }), /没有安装/);
		const same = await tools.toggle_plugin.execute("4", { id: "demo", enabled: true });
		assert.match(same.content[0].text, /已经是/);
		const off = await tools.toggle_plugin.execute("5", { id: "demo", enabled: false });
		assert.deepEqual(bot.proposal(off.details.app.proposal_id).undo, { type: "plugin", id: "demo", enabled: true });
	} finally {
		await done();
	}
});

test("list_downloads reports states, progress and errors", async () => {
	const { tools, done } = await setup({
		lookd: {
			"GET /api/jobs": [
				{ id: "a", state: "running", title: "第 1 节", kind: "video", progress: 0.426, course_id: "c1" },
				{ id: "b", state: "failed", title: "第 2 节", kind: "transcript", error: "网络中断", course_id: "c1" },
				{ id: "c", state: "done", title: "第 3 节", kind: "slides", course_id: "c2" },
			],
		},
	});
	try {
		const r = (await tools.list_downloads.execute("1", {})).content[0].text;
		assert.match(r, /下载中 1 · 失败 1 · 已完成 1/);
		assert.match(r, /第 1 节 · 视频 · 下载中 42%/);
		assert.match(r, /网络中断/);
		assert.doesNotMatch(r, /第 3 节/);
		assert.doesNotMatch((await tools.list_downloads.execute("2", { state: "all", course_id: "c1" })).content[0].text, /第 3 节/);
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
