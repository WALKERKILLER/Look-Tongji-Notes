import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { due, nextRun, prevRun, TaskScheduler, validateTask } from "./tasks.mjs";

const D = (s) => new Date(s); // local time
const daily = { type: "daily", time: "21:30" };
const until = async (cond) => {
	for (let i = 0; i < 200 && !cond(); i++) await new Promise((r) => setTimeout(r, 5));
	assert.ok(cond(), "condition not reached");
};

test("next and previous runs across a month end and weekdays", () => {
	assert.deepEqual(prevRun(daily, D("2026-10-31T22:00")), D("2026-10-31T21:30"));
	assert.deepEqual(prevRun(daily, D("2026-11-01T08:00")), D("2026-10-31T21:30"));
	assert.deepEqual(nextRun(daily, D("2026-10-31T22:00")), D("2026-11-01T21:30"));
	const mon = { type: "weekly", days: [1, 5], time: "08:00" };
	// 2026-10-14 is a Wednesday.
	assert.deepEqual(prevRun(mon, D("2026-10-14T10:00")), D("2026-10-12T08:00"));
	assert.deepEqual(nextRun(mon, D("2026-10-14T10:00")), D("2026-10-16T08:00"));
	assert.deepEqual(nextRun({ type: "weekly", days: [7], time: "09:00" }, D("2026-12-27T10:00")), D("2027-01-03T09:00"));
	const once = { type: "once", at: "2026-10-15T07:00" };
	assert.equal(prevRun(once, D("2026-10-14T10:00")), null);
	assert.deepEqual(nextRun(once, D("2026-10-14T10:00")), D("2026-10-15T07:00"));
	assert.equal(nextRun(once, D("2026-10-16T00:00")), null);
});

test("due respects the catch-up window and runs a time once", () => {
	const t = { enabled: true, schedule: daily, catch_up: true, handled: 0, created_at: 0 };
	assert.equal(due(t, D("2026-10-15T00:30")).action, "run");
	assert.equal(due(t, D("2026-10-15T10:00")).action, "skip"); // 12.5 h late
	assert.equal(due({ ...t, catch_up: false }, D("2026-10-14T21:33")).action, "run");
	assert.equal(due({ ...t, catch_up: false }, D("2026-10-14T21:45")).action, "skip");
	const d = due(t, D("2026-10-14T21:31"));
	assert.equal(due({ ...t, handled: d.scheduled }, D("2026-10-14T21:59")), null);
	assert.equal(due({ ...t, enabled: false }, D("2026-10-14T21:31")), null);
});

test("validation", () => {
	const ok = { name: "每晚复盘", prompt: "复盘今天的课", schedule: daily };
	assert.equal(validateTask(ok).budget_usd, 0.2);
	assert.deepEqual(validateTask({ ...ok, schedule: { type: "weekly", days: [5, 1, 1, 9], time: "08:00" } }).schedule.days, [1, 5]);
	for (const [bad, msg] of [
		[{ ...ok, name: "" }, /名称/],
		[{ ...ok, schedule: { type: "daily", time: "25:00" } }, /HH:MM/],
		[{ ...ok, schedule: { type: "weekly", days: [], time: "08:00" } }, /至少选一天/],
		[{ ...ok, schedule: { type: "once", at: "2020-01-01T08:00" } }, /将来/],
		[{ ...ok, schedule: { type: "once", at: "2099-02-30T08:00" } }, /时间无效/],
		[{ ...ok, schedule: { type: "once", at: "2099-04-31T08:00" } }, /时间无效/],
		[{ ...ok, schedule: { type: "once", at: "2099-01-01T24:00" } }, /时间无效/],
		[{ ...ok, budget_usd: 10 }, /费用上限/],
		[{ ...ok, schedule: { type: "hourly" } }, /schedule.type/],
	]) {
		assert.throws(() => validateTask(bad), (e) => e.status === 400 && msg.test(e.message));
	}
});

test("scheduler runs due tasks one at a time and records history", async () => {
	const dir = await mkdtemp(join(tmpdir(), "tasks-"));
	try {
		let now = D("2026-10-14T21:00");
		let active = 0;
		let peak = 0;
		const gates = [];
		const events = [];
		const s = new TaskScheduler(
			dir,
			async (task, signal) => {
				active++;
				peak = Math.max(peak, active);
				await new Promise((res) => {
					gates.push(res);
					signal.addEventListener("abort", res);
				});
				active--;
				return task.name === "贵" ? { status: "budget", cost: 0.25, summary: "超出预算" } : { status: "ok", session_id: "s1", cost: 0.01, summary: "完成" };
			},
			{ now: () => now, notify: (e) => events.push(e) },
		);
		await s.load();
		const a = await s.create({ name: "每晚复盘", prompt: "p", schedule: daily });
		const b = await s.create({ name: "贵", prompt: "p", schedule: daily });
		assert.equal(a.next_run, D("2026-10-14T21:30").getTime());

		now = D("2026-10-14T21:30:20");
		await s.tick();
		await s.tick(); // already queued or handled: no duplicates
		assert.equal(s.queue.length, 1);
		assert.equal(s.view(s.get(a.id)).state, "running");
		gates.shift()();
		await until(() => gates.length === 1);
		gates.shift()();
		await until(() => s.running === null && s.runsOf(b.id).length === 1);
		assert.equal(peak, 1);
		assert.deepEqual(s.runsOf(a.id).map((r) => r.status), ["ok"]);
		assert.deepEqual(s.runsOf(b.id).map((r) => r.status), ["budget"]);
		assert.deepEqual(events.filter((e) => e.phase === "finished").map((e) => e.name), ["每晚复盘", "贵"]);

		// Disabling a running task aborts it.
		s.runNow(a.id);
		await until(() => gates.length === 1);
		await s.update(a.id, { enabled: false });
		await until(() => s.runsOf(a.id).length === 2);
		assert.equal(s.runsOf(a.id)[0].status, "aborted");

		// Missed beyond the window: recorded as skipped, not run.
		now = D("2026-10-16T10:00");
		await s.tick();
		assert.equal(s.runsOf(b.id)[0].status, "skipped");
		assert.equal(s.running, null);

		// History survives a restart.
		const again = new TaskScheduler(dir, async () => ({}), { now: () => now });
		await again.load();
		assert.equal(again.list().length, 2);
		assert.equal(again.runsOf(b.id).length, 2);
		assert.match(await readFile(join(dir, "tasks.json"), "utf8"), /每晚复盘/);
		for (const f of ["tasks.json", "tasks-runs.jsonl"]) assert.equal((await stat(join(dir, f))).mode & 0o777, 0o600, f);

		// Runs of every task, newest first, filterable; deleted tasks keep theirs.
		await again.remove(b.id);
		assert.deepEqual(again.allRuns().map((r) => [r.name, r.status]), [["贵", "skipped"], ["每晚复盘", "aborted"], ["贵", "budget"], ["每晚复盘", "ok"]]);
		assert.deepEqual(again.allRuns({ status: "ok" }).map((r) => r.deleted), [false]);
		assert.equal(again.allRuns({ status: "skipped" })[0].deleted, true);
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});

test("existing files become private and a failed history write does not stall the queue", async () => {
	const dir = await mkdtemp(join(tmpdir(), "tasks-"));
	try {
		await writeFile(join(dir, "tasks.json"), JSON.stringify({ tasks: [] }), { mode: 0o644 });
		const s = new TaskScheduler(dir, async () => ({ status: "ok", summary: "完成" }), { now: () => D("2026-10-14T21:00") });
		await s.load();
		assert.equal((await stat(join(dir, "tasks.json"))).mode & 0o777, 0o600);
		const a = await s.create({ name: "甲", prompt: "p", schedule: daily });
		const b = await s.create({ name: "乙", prompt: "p", schedule: daily });
		// A directory where the history file goes makes every append fail.
		await mkdir(join(dir, "tasks-runs.jsonl"));
		s.runNow(a.id);
		s.runNow(b.id);
		await until(() => s.running === null && s.queue.length === 0 && s.runs.length === 2);
		assert.deepEqual(s.runs.map((r) => r.name), ["甲", "乙"]);
	} finally {
		await rm(dir, { recursive: true, force: true });
	}
});
