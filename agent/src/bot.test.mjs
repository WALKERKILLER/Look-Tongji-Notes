import assert from "node:assert/strict";
import { mkdtemp, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Bot, Consolidator, PROPOSAL_TTL_MS, transcriptOf, turnsOf, validateBotPatch } from "./bot.mjs";

async function fresh() {
	const dir = await mkdtemp(join(tmpdir(), "look-bot-"));
	const bot = new Bot(dir);
	await bot.load();
	return { bot, dir, done: () => rm(dir, { recursive: true, force: true }) };
}

test("identity patches are validated", () => {
	assert.deepEqual(validateBotPatch({ name: " 小 Look ", shape: "ghost", color: "teal", memory: { auto: false } }), { name: "小 Look", shape: "ghost", color: "teal", memory: { auto: false } });
	assert.throws(() => validateBotPatch({ name: "" }), /1–12/);
	assert.throws(() => validateBotPatch({ name: "一二三四五六七八九十一二三" }), /1–12/);
	assert.throws(() => validateBotPatch({ shape: "square" }), /形象/);
	assert.throws(() => validateBotPatch({ color: "#fff" }), /颜色/);
	assert.throws(() => validateBotPatch({ persona: "x".repeat(501) }), /500/);
	assert.throws(() => validateBotPatch({ memory: { auto: "yes" } }), /memory.auto/);
	assert.deepEqual(validateBotPatch({ session_id: "x", marks: {} }), {});
});

test("identity, kinds and marks persist privately", async () => {
	const { bot, dir, done } = await fresh();
	try {
		await bot.update({ name: "阿布", memory: { learn_from_courses: true } });
		await bot.setSession("s-bot");
		await bot.setKind("s-course", { kind: "course", course_id: 42 });
		await bot.setMarks({ "s-bot": 3 });
		const again = new Bot(dir);
		await again.load();
		assert.equal(again.identity().name, "阿布");
		assert.deepEqual(again.identity().memory, { auto: true, learn_from_courses: true });
		assert.deepEqual(again.kindOf("s-bot"), { kind: "bot" });
		assert.deepEqual(again.kindOf("s-course"), { kind: "course", course_id: "42" });
		assert.deepEqual(again.kindOf("unknown"), { kind: "chat" });
		assert.equal(again.mark("s-bot"), 3);
		assert.equal((await stat(join(dir, "bot", "bot.json"))).mode & 0o777, 0o600);
		assert.equal((await stat(join(dir, "sessions-meta.json"))).mode & 0o777, 0o600);
		await again.forget("s-bot");
		assert.equal(again.identity().session_id, null);
		assert.equal(again.mark("s-bot"), 0);
	} finally {
		await done();
	}
});

test("proposals apply once, undo once and expire", async () => {
	const { bot, done } = await fresh();
	try {
		const p = await bot.propose({ kind: "download", title: "下载", lines: ["a"], op: { type: "download" }, undo: { type: "x" } });
		assert.equal(p.state, "pending");
		const ran = [];
		const r = await bot.transition(p.id, ["pending"], "applied", async (x) => (ran.push(x.op.type), { jobs: 2 }), (s) => `refused ${s}`);
		assert.deepEqual(r, { state: "applied", result: { jobs: 2 } });
		await assert.rejects(bot.transition(p.id, ["pending"], "applied", async () => ran.push("again"), (s) => `refused ${s}`), (e) => e.status === 409 && /refused applied/.test(e.message));
		assert.deepEqual(ran, ["download"]);
		await bot.transition(p.id, ["applied"], "undone", async () => ({ ok: true }), (s) => s);
		await assert.rejects(bot.transition(p.id, ["applied"], "undone", null, (s) => s), (e) => e.status === 409);

		const failing = await bot.propose({ kind: "task", title: "t", op: { type: "task" } });
		await assert.rejects(bot.transition(failing.id, ["pending"], "applied", async () => {
			throw new Error("boom");
		}, (s) => s));
		assert.equal(bot.proposal(failing.id).state, "failed");

		const old = await bot.propose({ kind: "plugin", title: "p", op: { type: "plugin" } });
		assert.equal(bot.proposal(old.id, Date.now() + PROPOSAL_TTL_MS + 1).state, "expired");
		await assert.rejects(Promise.resolve().then(() => bot.proposal("nope")), (e) => e.status === 404);
		const applied = await bot.propose({ kind: "course", title: "c", op: { type: "course" }, undo: { type: "course" }, applied: true });
		assert.deepEqual(bot.view(applied).state, "applied");
		assert.equal(bot.view(applied).undoable, true);
		assert.equal("op" in bot.view(applied), false);
	} finally {
		await done();
	}
});

test("turns drop context blocks, thinking and tool results", () => {
	const turns = turnsOf([
		{ role: "user", content: [{ type: "text", text: "<context>\npage: course\n</context>\n\n以后回答短一点" }] },
		{ role: "assistant", content: [{ type: "thinking", thinking: "secret plan" }, { type: "toolCall", name: "x" }] },
		{ role: "toolResult", content: [{ type: "text", text: "tool output" }] },
		{ role: "assistant", content: [{ type: "text", text: "好的" }] },
		{ role: "user", content: "第二个问题" },
	]);
	assert.deepEqual(turns, [
		{ user: "以后回答短一点", assistant: "好的" },
		{ user: "第二个问题", assistant: "" },
	]);
	const t = transcriptOf([{ id: "a", title: "A", turns }]);
	assert.doesNotMatch(t, /secret plan|tool output|page: course/);
	const long = transcriptOf(
		Array.from({ length: 10 }, (_, i) => ({ id: `${i}`, title: `${i}`, turns: [{ user: "x".repeat(5000), assistant: "y" }] })),
		12_000,
	);
	assert.ok(long.length <= 12_000);
	assert.match(long, /截断/);
});

test("consolidation runs once at a time, moves marks only on success and logs", async () => {
	const { bot, done } = await fresh();
	try {
		let waiting = [{ id: "s1", title: "t", turns: [{ user: "我是土木的", assistant: "好" }] }];
		const events = [];
		let calls = 0;
		let fail = false;
		const c = new Consolidator(
			bot,
			{
				candidates: async () => waiting,
				run: async (transcript) => {
					calls++;
					assert.match(transcript, /我是土木的/);
					if (fail) throw new Error("model down");
					await new Promise((r) => setTimeout(r, 20));
					return { changes: [{ path: "profile.md", action: "created" }], cost: 0.01, summary: "记下了专业" };
				},
				notify: (d) => events.push(d.kind),
			},
			{ idleMs: 10_000, turns: 6 },
		);
		const [a, b] = [c.now(), c.now()];
		assert.equal(a, b);
		const run = await a;
		assert.equal(run.status, "ok");
		assert.equal(bot.mark("s1"), 1);
		await c.running;
		assert.equal(calls, 2, "a trigger during a run runs once more after it");
		fail = true;
		waiting = [{ id: "s1", title: "t", turns: [{ user: "我是土木的", assistant: "好" }] }];
		const bad = await c.now();
		assert.equal(bad.status, "error");
		assert.equal(bot.mark("s1"), 2, "marks stay after a failure");
		waiting = [];
		assert.equal((await c.now()).status, "empty");
		const runs = await bot.runs();
		assert.deepEqual(runs.map((r) => r.status), ["empty", "error", "ok", "ok"]);
		assert.ok(events.includes("consolidated") && events.includes("failed"));
		c.stop();
	} finally {
		await done();
	}
});

test("six waiting turns consolidate without the idle wait; auto off does nothing", async () => {
	const { bot, done } = await fresh();
	try {
		let runs = 0;
		const six = Array.from({ length: 6 }, () => ({ user: "u", assistant: "a" }));
		const c = new Consolidator(bot, { candidates: async () => [{ id: "s", title: "t", turns: six }], run: async () => (runs++, { changes: [] }), notify: () => {} }, { idleMs: 60_000, turns: 6 });
		await c.touch();
		await c.running;
		assert.equal(runs, 1);
		await bot.update({ memory: { auto: false } });
		await c.touch();
		assert.equal(c.running, null);
		assert.equal(runs, 1);
		c.stop();
	} finally {
		await done();
	}
});
