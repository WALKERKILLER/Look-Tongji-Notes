import assert from "node:assert/strict";
import { appendFile, mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { entryFrom, KEEP_DAYS, localDay, UsageLedger } from "./usage.mjs";

const at = (day, h = 12) => {
	const [y, m, d] = day.split("-").map(Number);
	return new Date(y, m - 1, d, h).getTime();
};

const msg = (ts, extra = {}) => ({
	role: "assistant",
	provider: "deepseek",
	model: "deepseek-chat",
	timestamp: ts,
	durationMs: 900,
	stopReason: "stop",
	usage: { input: 100, output: 20, cacheRead: 300, cacheWrite: 0, totalTokens: 420, cost: { total: 0.002 } },
	...extra,
});

async function ledgerWith(entries) {
	const dir = await mkdtemp(join(tmpdir(), "usage-"));
	const l = new UsageLedger(dir);
	for (const e of entries) await l.record(e);
	return l;
}

test("entryFrom maps Pi usage and marks errors", () => {
	const e = entryFrom(msg(1, { stopReason: "error" }), { purpose: "nope", session_id: "s1", ttft_ms: 120 });
	assert.equal(e.purpose, "chat");
	assert.equal(e.cache_read, 300);
	assert.equal(e.cost, 0.002);
	assert.equal(e.ms, 900);
	assert.equal(e.ttft_ms, 120);
	assert.equal(e.ok, false);
	assert.equal(e.session_id, "s1");
});

test("summary fills zero days, groups and compares with the previous period", async () => {
	const l = await ledgerWith([
		entryFrom(msg(at("2026-10-03")), { purpose: "chat", session_id: "a" }), // previous period (10-02..10-04)
		entryFrom(msg(at("2026-10-01")), { purpose: "chat", session_id: "a" }), // before both periods
		entryFrom(msg(at("2026-10-05", 0)), { purpose: "chat", session_id: "a" }),
		entryFrom(msg(at("2026-10-05", 23)), { purpose: "timeline" }),
		entryFrom(msg(at("2026-10-07"), { provider: "openai", model: "gpt", usage: { input: 1, output: 1, cacheRead: 0, cacheWrite: 0, cost: { total: 0.5 } } }), {
			purpose: "chat",
			session_id: "b",
		}),
		entryFrom(msg(at("2026-10-08")), { purpose: "chat" }), // after range
	]);
	const s = await l.summary("2026-10-05", "2026-10-07", new Map([["a", "第一章"]]));
	assert.deepEqual(
		s.days.map((d) => [d.date, d.calls]),
		[
			["2026-10-05", 2],
			["2026-10-06", 0],
			["2026-10-07", 1],
		],
	);
	assert.equal(s.totals.calls, 3);
	assert.equal(s.totals.cache_read, 600);
	assert.equal(s.previous.calls, 1);
	assert.equal(s.by_model[0].key, "openai/gpt"); // highest cost first
	assert.deepEqual(s.by_purpose.map((r) => r.key).sort(), ["chat", "timeline"]);
	assert.equal(s.by_session.find((r) => r.key === "a").title, "第一章");
	await assert.rejects(l.summary("2026-10-07", "2026-10-05"), { status: 400 });
	await assert.rejects(l.summary("10/05", "2026-10-07"), { status: 400 });
	await assert.rejects(l.summary("2026-02-31", "2026-03-02"), { status: 400 }); // not a real day
	await assert.rejects(l.calls({ from: "2026-02-30" }), { status: 400 });
	assert.equal((await l.summary("2024-01-01", "2024-12-31")).days.length, 366); // 本年 in a leap year
	await assert.rejects(l.summary("2025-01-01", "2026-01-02"), { status: 400 }); // 367 days
	await assert.rejects(l.summary("1970-01-01", "9999-12-31"), { status: 400 });
});

test("prune keeps the retention window and the backfill marker, never losing a concurrent append", async () => {
	const dir = await mkdtemp(join(tmpdir(), "usage-"));
	const l = new UsageLedger(dir);
	const now = at("2026-10-18");
	const day = 86_400_000;
	await l.record({ backfill: true, ts: now - 900 * day, count: 0 });
	await l.record(entryFrom(msg(now - (KEEP_DAYS + 1) * day)));
	await l.record(entryFrom(msg(now - (KEEP_DAYS - 1) * day)));
	assert.equal((await l.entries()).length, 2);
	const [dropped] = await Promise.all([l.prune(now), l.record(entryFrom(msg(now)))]);
	assert.equal(dropped, 1);
	const lines = (await readFile(join(dir, "usage.jsonl"), "utf8")).trim().split("\n").map((x) => JSON.parse(x));
	assert.equal(lines.length, 3);
	assert.equal(lines[0].backfill, true);
	assert.deepEqual((await l.entries()).map((e) => e.ts), [now - (KEEP_DAYS - 1) * day, now]);
	assert.equal(await l.prune(now), 0);
});

test("entries reads only lines appended since the last load", async () => {
	const dir = await mkdtemp(join(tmpdir(), "usage-"));
	const l = new UsageLedger(dir);
	await l.record(entryFrom(msg(at("2026-10-05"))));
	assert.equal((await l.entries()).length, 1);
	await appendFile(join(dir, "usage.jsonl"), `${JSON.stringify(entryFrom(msg(at("2026-10-06"))))}\n`);
	const all = await l.entries();
	assert.deepEqual(all.map((e) => localDay(e.ts)), ["2026-10-05", "2026-10-06"]);
});

test("flush waits for appends still in flight", async () => {
	const dir = await mkdtemp(join(tmpdir(), "usage-"));
	const l = new UsageLedger(dir);
	for (let i = 0; i < 20; i++) l.record(entryFrom(msg(at("2026-10-05") + i)));
	await l.flush();
	assert.equal((await readFile(join(dir, "usage.jsonl"), "utf8")).trim().split("\n").length, 20);
	assert.equal(l.pending.size, 0);
});

test("calls pages newest first with filters", async () => {
	const l = await ledgerWith([1, 2, 3, 4].map((h) => entryFrom(msg(at("2026-10-05", h)), { purpose: h % 2 ? "chat" : "vision" })));
	const page = await l.calls({ limit: 2 });
	assert.deepEqual(page.map((c) => new Date(c.ts).getHours()), [4, 3]);
	const next = await l.calls({ before: page[1].ts, limit: 5 });
	assert.deepEqual(next.map((c) => new Date(c.ts).getHours()), [2, 1]);
	assert.equal((await l.calls({ purpose: "vision" })).length, 2);
	await assert.rejects(l.calls({ before: "x" }), { status: 400 });
	for (const limit of [-1, 0, 1.5, 201, Number.NaN]) await assert.rejects(l.calls({ limit }), { status: 400 });
});

test("calls sharing a millisecond are not skipped across pages", async () => {
	const same = at("2026-10-05", 9);
	const l = await ledgerWith([1, 2, 3, 4, 5].map((n) => ({ ...entryFrom(msg(same)), output: n })));
	const seen = [];
	let before;
	for (let i = 0; i < 5; i++) {
		const page = await l.calls({ before, limit: 2 });
		if (!page.length) break;
		seen.push(...page.map((c) => c.output));
		before = page.at(-1).cursor;
	}
	assert.deepEqual(seen, [5, 4, 3, 2, 1]);
});

test("backfill imports every assistant message once", async () => {
	const dir = await mkdtemp(join(tmpdir(), "usage-bf-"));
	const sessions = join(dir, "sessions", "nested");
	await mkdir(sessions, { recursive: true });
	const lines = [
		{ type: "session", id: "s1", version: 3 },
		{ type: "message", message: { role: "user", content: "hi", timestamp: 1 } },
		{ type: "message", message: msg(at("2026-10-05", 9)) }, // tool round trip
		{ type: "message", message: { role: "toolResult", content: [], timestamp: 2 } },
		{ type: "message", message: msg(at("2026-10-05", 10)) },
	];
	await writeFile(join(sessions, "x.jsonl"), lines.map((l) => JSON.stringify(l)).join("\n"));
	const l = new UsageLedger(dir);
	await l.record(entryFrom(msg(at("2026-10-05", 10)), { session_id: "s1" })); // already live-recorded
	assert.equal(await l.backfill(join(dir, "sessions")), 1);
	assert.equal(await l.backfill(join(dir, "sessions")), 0);
	const all = await l.entries();
	assert.equal(all.length, 2);
	assert.ok(all.every((e) => e.session_id === "s1"));
	assert.match(await readFile(l.path, "utf8"), /"backfill":true/);
	assert.equal(localDay(all[0].ts), "2026-10-05");
});
