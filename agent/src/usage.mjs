// Usage ledger: one JSON line per model call, kept apart from conversations so
// deleting a conversation never erases what it cost. Contract:
// docs/specs/0000-usage-ledger-and-cost-stats.md
import { appendFile, readdir, readFile, stat } from "node:fs/promises";
import { join } from "node:path";

export const PURPOSES = ["chat", "timeline", "vision", "title", "test", "task", "quiz"];
const DAY = /^\d{4}-\d{2}-\d{2}$/;
// A real calendar day: Date rolls 2026-02-31 over to March, so it must format back unchanged.
const isDay = (s) => DAY.test(s) && localDay(dayStart(s)) === s;

/** Ledger line for a finished Pi assistant message. */
export function entryFrom(message, { purpose, session_id, task_id, ttft_ms } = {}) {
	const u = message.usage ?? {};
	return {
		ts: message.timestamp ?? Date.now(),
		provider: message.provider ?? "",
		model: message.model ?? "",
		purpose: PURPOSES.includes(purpose) ? purpose : "chat",
		...(session_id ? { session_id } : {}),
		...(task_id ? { task_id } : {}),
		input: u.input ?? 0,
		output: u.output ?? 0,
		cache_read: u.cacheRead ?? 0,
		cache_write: u.cacheWrite ?? 0,
		cost: u.cost?.total ?? 0,
		ms: message.durationMs ?? 0,
		...(ttft_ms != null ? { ttft_ms } : {}),
		ok: message.stopReason !== "error",
	};
}

export const localDay = (ts) => new Date(ts).toLocaleDateString("sv-SE");

function dayStart(day) {
	const [y, m, d] = day.split("-").map(Number);
	return new Date(y, m - 1, d).getTime();
}

const shiftDay = (day, n) => {
	const [y, m, d] = day.split("-").map(Number);
	return localDay(new Date(y, m - 1, d + n).getTime());
};

function emptyTotals() {
	return { calls: 0, input: 0, output: 0, cache_read: 0, cache_write: 0, cost: 0, errors: 0 };
}

function add(t, e) {
	t.calls++;
	t.input += e.input;
	t.output += e.output;
	t.cache_read += e.cache_read;
	t.cache_write += e.cache_write;
	t.cost += e.cost;
	if (!e.ok) t.errors++;
	return t;
}

function ranked(map) {
	return [...map.entries()]
		.map(([key, t]) => ({ key, ...t }))
		.sort((a, b) => b.cost - a.cost || b.input + b.output - (a.input + a.output));
}

export class UsageLedger {
	constructor(dir) {
		this.path = join(dir, "usage.jsonl");
		this.lines = null; // parsed entries, loaded lazily and kept in sync with appends
		this.size = -1;
	}

	async record(entry) {
		try {
			await appendFile(this.path, `${JSON.stringify(entry)}\n`);
			if (this.lines) {
				this.lines.push(entry);
				this.size = (await stat(this.path)).size;
			}
		} catch (e) {
			console.error(`usage ledger: ${e.message}`);
		}
	}

	async entries() {
		let size = 0;
		try {
			size = (await stat(this.path)).size;
		} catch {
			return [];
		}
		if (this.lines && size === this.size) return this.lines;
		const text = await readFile(this.path, "utf8");
		this.lines = text
			.split("\n")
			.filter(Boolean)
			.map((l) => {
				try {
					return JSON.parse(l);
				} catch {
					return null;
				}
			})
			.filter((e) => e && typeof e.ts === "number" && !e.backfill);
		this.size = size;
		return this.lines;
	}

	/**
	 * One-time import of assistant messages from existing Pi session files.
	 * A marker line makes it idempotent; entries already in the ledger (same
	 * session and timestamp) are skipped.
	 */
	async backfill(sessionsDir) {
		let text = "";
		try {
			text = await readFile(this.path, "utf8");
		} catch {}
		if (text.includes('"backfill":true')) return 0;
		const seen = new Set(
			text
				.split("\n")
				.filter(Boolean)
				.map((l) => {
					try {
						const e = JSON.parse(l);
						return `${e.session_id}@${e.ts}`;
					} catch {
						return "";
					}
				}),
		);
		const found = [];
		for (const file of await listJsonl(sessionsDir)) {
			let sessionId = "";
			for (const line of (await readFile(file, "utf8")).split("\n")) {
				if (!line) continue;
				let rec;
				try {
					rec = JSON.parse(line);
				} catch {
					continue;
				}
				if (rec.type === "session") sessionId = rec.id ?? "";
				const m = rec.type === "message" ? rec.message : null;
				if (m?.role !== "assistant" || !m.usage) continue;
				const e = entryFrom(m, { purpose: "chat", session_id: sessionId });
				if (!seen.has(`${e.session_id}@${e.ts}`)) found.push(e);
			}
		}
		found.sort((a, b) => a.ts - b.ts);
		const out = [...found, { backfill: true, ts: Date.now(), count: found.length }];
		await appendFile(this.path, out.map((e) => JSON.stringify(e)).join("\n") + "\n");
		this.lines = null;
		return found.length;
	}

	/** Aggregates for local days [from, to]; `titles` maps session id → title. */
	async summary(from, to, titles = new Map()) {
		if (!isDay(from) || !isDay(to) || from > to) throw rangeError();
		const start = dayStart(from);
		const end = dayStart(shiftDay(to, 1));
		const span = Math.round((end - start) / 86_400_000);
		const prevStart = dayStart(shiftDay(from, -span));
		const totals = emptyTotals();
		const previous = emptyTotals();
		const days = new Map();
		for (let d = from; d <= to; d = shiftDay(d, 1)) days.set(d, { date: d, ...emptyTotals() });
		const byModel = new Map();
		const byPurpose = new Map();
		const bySession = new Map();
		const group = (map, key) => map.get(key) ?? map.set(key, emptyTotals()).get(key);
		for (const e of await this.entries()) {
			if (e.ts >= prevStart && e.ts < start) add(previous, e);
			if (e.ts < start || e.ts >= end) continue;
			add(totals, e);
			add(days.get(localDay(e.ts)), e);
			add(group(byModel, `${e.provider}/${e.model}`), e);
			add(group(byPurpose, e.purpose), e);
			if (e.session_id) add(group(bySession, e.session_id), e);
		}
		return {
			from,
			to,
			totals,
			previous,
			days: [...days.values()],
			by_model: ranked(byModel),
			by_purpose: ranked(byPurpose),
			by_session: ranked(bySession)
				.slice(0, 50)
				.map((r) => ({ ...r, title: titles.get(r.key) ?? null })),
		};
	}

	/**
	 * Newest-first page of calls, optionally filtered. Calls are ordered by
	 * (ts, position in the ledger), and each carries `cursor` "<ts>:<position>";
	 * pass the last one as `before` for the next page, so calls sharing a
	 * millisecond are never skipped. A bare "<ts>" still means "older than ts".
	 */
	async calls({ before, limit = 50, from, to, model, purpose, session_id } = {}) {
		if ((from && !isDay(from)) || (to && !isDay(to))) throw rangeError();
		const cursor = parseCursor(before);
		const start = from ? dayStart(from) : -Infinity;
		const end = to ? dayStart(shiftDay(to, 1)) : Infinity;
		const out = [];
		const all = await this.entries();
		for (let i = 0; i < all.length; i++) {
			const e = all[i];
			if (e.ts > cursor.ts || (e.ts === cursor.ts && i >= cursor.pos) || e.ts < start || e.ts >= end) continue;
			if (model && `${e.provider}/${e.model}` !== model) continue;
			if (purpose && e.purpose !== purpose) continue;
			if (session_id && e.session_id !== session_id) continue;
			out.push({ ...e, cursor: `${e.ts}:${i}` });
		}
		const pos = (c) => Number(c.cursor.split(":")[1]);
		return out.sort((a, b) => b.ts - a.ts || pos(b) - pos(a)).slice(0, limit);
	}
}

function parseCursor(before) {
	if (before == null || before === "") return { ts: Infinity, pos: Infinity };
	const m = /^(\d+)(?::(\d+))?$/.exec(String(before));
	if (!m) throw Object.assign(new Error("before 应为上一页最后一条的 cursor"), { status: 400 });
	return { ts: Number(m[1]), pos: m[2] === undefined ? -1 : Number(m[2]) };
}

function rangeError() {
	return Object.assign(new Error("日期范围无效，应为 YYYY-MM-DD"), { status: 400 });
}

async function listJsonl(dir) {
	const out = [];
	let ents = [];
	try {
		ents = await readdir(dir, { withFileTypes: true });
	} catch {
		return out;
	}
	for (const e of ents) {
		const p = join(dir, e.name);
		if (e.isDirectory()) out.push(...(await listJsonl(p)));
		else if (e.name.endsWith(".jsonl")) out.push(p);
	}
	return out;
}
