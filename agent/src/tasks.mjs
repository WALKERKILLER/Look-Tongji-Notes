// Scheduled assistant tasks (docs/specs/0003-scheduled-agent-tasks.md).
// Tasks run only while the app (and so this host) is running.
import { randomBytes } from "node:crypto";
import { appendFile, chmod, readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";

const bad = (message) => Object.assign(new Error(message), { status: 400 });

export const CATCH_UP_MS = 12 * 3600_000;
// Without catch-up a run still starts if the check comes a little late.
export const LATE_MS = 5 * 60_000;
export const RUNS_KEPT = 50;

const pad = (n) => String(n).padStart(2, "0");
const at = (day, time) => {
	const [h, m] = time.split(":").map(Number);
	return new Date(day.getFullYear(), day.getMonth(), day.getDate(), h, m);
};
// 1 = Monday … 7 = Sunday
const isoDay = (d) => d.getDay() || 7;

/** Validates input for a new task or a change to one; returns the stored shape. */
export function validateTask(input, old = {}) {
	const t = { ...old, ...input };
	const name = String(t.name ?? "").trim();
	const prompt = String(t.prompt ?? "").trim();
	if (!name || name.length > 40) throw bad("名称不能为空，最多 40 字");
	if (!prompt || prompt.length > 4000) throw bad("任务内容不能为空，最多 4000 字");
	const s = t.schedule ?? {};
	let schedule;
	const time = String(s.time ?? "");
	const validTime = /^([01]\d|2[0-3]):[0-5]\d$/.test(time);
	switch (s.type) {
		case "daily":
			if (!validTime) throw bad("时间格式应为 HH:MM");
			schedule = { type: "daily", time };
			break;
		case "weekly": {
			const days = [...new Set((s.days ?? []).map(Number))].filter((d) => Number.isInteger(d) && d >= 1 && d <= 7).sort();
			if (!validTime) throw bad("时间格式应为 HH:MM");
			if (!days.length) throw bad("每周任务至少选一天");
			schedule = { type: "weekly", days, time };
			break;
		}
		case "once": {
			const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(String(s.at ?? ""));
			if (!m) throw bad("一次性任务的时间格式应为 YYYY-MM-DDTHH:MM");
			const when = new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]);
			// Date rolls overflow over (02-30 → 03-02); the parts must survive as typed.
			const parts = [when.getFullYear(), when.getMonth() + 1, when.getDate(), when.getHours(), when.getMinutes()];
			if (parts.some((v, i) => v !== +m[i + 1])) throw bad("时间无效");
			if (s.at !== old.schedule?.at && when <= new Date()) throw bad("一次性任务的时间需要在将来");
			schedule = { type: "once", at: s.at };
			break;
		}
		default:
			throw bad("schedule.type 应为 daily、weekly 或 once");
	}
	const budget = t.budget_usd === undefined ? 0.2 : Number(t.budget_usd);
	if (!(budget >= 0.01 && budget <= 5)) throw bad("单次费用上限应在 $0.01–$5 之间");
	return {
		id: old.id ?? `${new Date().toLocaleDateString("sv-SE").replaceAll("-", "")}-${randomBytes(4).toString("hex")}`,
		name,
		prompt,
		schedule,
		enabled: t.enabled !== false,
		budget_usd: Math.round(budget * 100) / 100,
		catch_up: t.catch_up !== false,
		created_at: old.created_at ?? Date.now(),
		// The scheduled time last handled (ran or skipped), so a time runs once.
		handled: old.handled ?? 0,
	};
}

/** The latest scheduled time at or before now, or null. */
export function prevRun(schedule, now) {
	if (schedule.type === "once") {
		const [d, time] = schedule.at.split("T");
		const [y, mo, da] = d.split("-").map(Number);
		const t = at(new Date(y, mo - 1, da), time);
		return t <= now ? t : null;
	}
	for (let i = 0; i <= 7; i++) {
		const day = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
		const t = at(day, schedule.time);
		if (t > now) continue;
		if (schedule.type === "daily" || schedule.days.includes(isoDay(day))) return t;
	}
	return null;
}

/** The next scheduled time after now, or null. */
export function nextRun(schedule, now) {
	if (schedule.type === "once") {
		const t = prevRun(schedule, new Date(8.64e15));
		return t > now ? t : null;
	}
	for (let i = 0; i <= 7; i++) {
		const day = new Date(now.getFullYear(), now.getMonth(), now.getDate() + i);
		const t = at(day, schedule.time);
		if (t <= now) continue;
		if (schedule.type === "daily" || schedule.days.includes(isoDay(day))) return t;
	}
	return null;
}

/**
 * What to do about a task at `now`: "run", "skip" (missed beyond the window)
 * or null, with the scheduled time concerned.
 */
export function due(task, now) {
	if (!task.enabled) return null;
	const t = prevRun(task.schedule, now);
	if (!t || t.getTime() <= task.handled) return null;
	const late = now - t;
	return { action: late <= (task.catch_up ? CATCH_UP_MS : LATE_MS) ? "run" : "skip", scheduled: t.getTime() };
}

// Tasks and run history hold the user's prompts and assistant summaries.
const PRIVATE = 0o600;
const keepPrivate = (path) => chmod(path, PRIVATE).catch(() => {});

export const fmtStamp = (ms) => {
	const d = new Date(ms);
	return `${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

/**
 * Keeps tasks and their run history, decides what is due, and runs one task
 * at a time through `runner(task, signal) → {status, session_id, cost, summary}`.
 */
export class TaskScheduler {
	constructor(dir, runner, { now = () => new Date(), notify = () => {} } = {}) {
		this.file = join(dir, "tasks.json");
		this.runsFile = join(dir, "tasks-runs.jsonl");
		this.runner = runner;
		this.now = now;
		this.notify = notify;
		this.tasks = [];
		this.queue = []; // {task_id, scheduled, manual}
		this.running = null; // {task_id, run_id, ac, started}
		this.runs = [];
	}

	async load() {
		try {
			this.tasks = JSON.parse(await readFile(this.file, "utf8")).tasks ?? [];
		} catch {
			this.tasks = [];
		}
		try {
			this.runs = (await readFile(this.runsFile, "utf8"))
				.split("\n")
				.filter(Boolean)
				.map((l) => JSON.parse(l));
		} catch {
			this.runs = [];
		}
		// Files written before modes were set.
		await keepPrivate(this.file);
		await keepPrivate(this.runsFile);
	}

	async save() {
		const tmp = `${this.file}.tmp`;
		await writeFile(tmp, JSON.stringify({ schema: "look-studio/tasks@1", tasks: this.tasks }, null, 1), { mode: PRIVATE });
		await chmod(tmp, PRIVATE);
		await rename(tmp, this.file);
	}

	get(id) {
		const t = this.tasks.find((x) => x.id === id);
		if (!t) throw Object.assign(new Error("任务不存在"), { status: 404 });
		return t;
	}

	view(t) {
		const runs = this.runs.filter((r) => r.task_id === t.id);
		const next = t.enabled ? nextRun(t.schedule, this.now()) : null;
		const state = this.running?.task_id === t.id ? "running" : this.queue.some((q) => q.task_id === t.id) ? "queued" : "idle";
		const { handled: _, ...rest } = t;
		return { ...rest, next_run: next?.getTime() ?? null, last_run: runs.at(-1) ?? null, state };
	}

	list() {
		return this.tasks.map((t) => this.view(t));
	}

	async create(input) {
		const t = validateTask(input);
		// Times before creation never run.
		t.handled = prevRun(t.schedule, this.now())?.getTime() ?? 0;
		this.tasks.push(t);
		await this.save();
		return this.view(t);
	}

	async update(id, input) {
		const old = this.get(id);
		const t = validateTask(input, old);
		if (JSON.stringify(t.schedule) !== JSON.stringify(old.schedule)) t.handled = prevRun(t.schedule, this.now())?.getTime() ?? 0;
		this.tasks[this.tasks.indexOf(old)] = t;
		if (!t.enabled) this.cancel(id);
		await this.save();
		return this.view(t);
	}

	async remove(id) {
		this.get(id);
		this.cancel(id);
		this.tasks = this.tasks.filter((t) => t.id !== id);
		await this.save();
	}

	/** Drops a pending run and aborts a running one. */
	cancel(id) {
		this.queue = this.queue.filter((q) => q.task_id !== id);
		if (this.running?.task_id === id) {
			this.running.cancelled = true;
			this.running.ac.abort();
		}
	}

	runNow(id) {
		const t = this.get(id);
		if (this.running?.task_id === id || this.queue.some((q) => q.task_id === id)) throw Object.assign(new Error("这个任务已在运行或排队"), { status: 409 });
		this.queue.push({ task_id: t.id, scheduled: this.now().getTime(), manual: true });
		this.pump();
		return this.view(t);
	}

	runsOf(id) {
		return this.runs.filter((r) => r.task_id === id).reverse();
	}

	/** Runs of every task, newest first, optionally of one status. */
	allRuns({ status, limit = 100 } = {}) {
		const out = [];
		for (let i = this.runs.length - 1; i >= 0 && out.length < limit; i--) {
			const r = this.runs[i];
			if (status && r.status !== status) continue;
			const t = this.tasks.find((x) => x.id === r.task_id);
			// Runs outlive a deleted task; older records carry no name.
			out.push({ ...r, name: t?.name ?? r.name ?? null, deleted: !t });
		}
		return out;
	}

	/** Checks for due tasks; called every 30 s. */
	async tick() {
		const now = this.now();
		let changed = false;
		for (const t of this.tasks) {
			if (this.running?.task_id === t.id || this.queue.some((q) => q.task_id === t.id)) continue;
			const d = due(t, now);
			if (!d) continue;
			t.handled = d.scheduled;
			changed = true;
			if (d.action === "run") {
				this.queue.push({ task_id: t.id, scheduled: d.scheduled });
			} else {
				await this.record({ task_id: t.id, name: t.name, run_id: newRunId(), started: now.getTime(), finished: now.getTime(), status: "skipped", cost: 0, summary: `错过了 ${fmtStamp(d.scheduled)} 的运行（应用当时未运行）` });
			}
		}
		if (changed) await this.save();
		this.pump();
	}

	pump() {
		if (this.running || !this.queue.length) return;
		const q = this.queue.shift();
		const task = this.tasks.find((t) => t.id === q.task_id);
		if (!task) return this.pump();
		const run = { task_id: task.id, run_id: newRunId(), started: this.now().getTime(), ac: new AbortController() };
		this.running = run;
		this.notify({ phase: "started", task_id: task.id, name: task.name, run_id: run.run_id });
		(async () => {
			let r;
			try {
				r = await this.runner(task, run.ac.signal);
			} catch (e) {
				r = { status: "error", summary: String(e?.message ?? e) };
			}
			if (run.cancelled) r = { ...r, status: "aborted", summary: "任务被停用或删除，已中止" };
			const rec = {
				task_id: task.id,
				name: task.name,
				run_id: run.run_id,
				started: run.started,
				finished: this.now().getTime(),
				status: r.status ?? "ok",
				session_id: r.session_id ?? null,
				cost: r.cost ?? 0,
				summary: String(r.summary ?? "").slice(0, 300),
				manual: q.manual ?? false,
			};
			try {
				await this.record(rec);
			} catch (e) {
				console.error(`task run not recorded: ${e?.message ?? e}`);
			} finally {
				// A failed write must not leave the queue stuck behind this run.
				this.running = null;
				this.notify({ phase: "finished", ...rec });
				this.pump();
			}
		})();
	}

	async record(rec) {
		this.runs.push(rec);
		const perTask = this.runs.filter((r) => r.task_id === rec.task_id);
		if (perTask.length > RUNS_KEPT) {
			const drop = new Set(perTask.slice(0, perTask.length - RUNS_KEPT));
			this.runs = this.runs.filter((r) => !drop.has(r));
			await writeFile(this.runsFile, this.runs.map((r) => JSON.stringify(r)).join("\n") + "\n", { mode: PRIVATE });
		} else {
			await appendFile(this.runsFile, `${JSON.stringify(rec)}\n`, { mode: PRIVATE });
		}
		await keepPrivate(this.runsFile);
	}
}

const newRunId = () => randomBytes(6).toString("hex");
