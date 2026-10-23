// The bot operating the app: navigation, the player, settings, downloads,
// courses, scheduled tasks and plugins. Changes that cost bandwidth or disk,
// delete files or change how the app behaves become proposals the user
// applies on a card; the rest apply at once and can be undone.
// Contract: docs/specs/0007-resident-bot-and-course-agents.md
import { Type } from "typebox";
import { validateTask } from "./tasks.mjs";

const bad = (message, status = 400) => Object.assign(new Error(message), { status });
const text = (t, details = {}) => ({ content: [{ type: "text", text: t }], details });
const enc = encodeURIComponent;
const lit = (values) => Type.Union(values.map((v) => Type.Literal(v)));

const MB = 1 << 20;
// Hex values of the app's seed palette (kSeedPalette in app/lib/theme/prefs.dart).
export const COURSE_COLORS = {
	none: "",
	blue: "#3F6CB4",
	teal: "#2E6E6A",
	green: "#4F7A3A",
	amber: "#B0782A",
	red: "#B4443A",
	rose: "#B0507A",
	violet: "#6E5AA8",
	graphite: "#5D6670",
};
export const DOWNLOAD_KINDS = ["video", "slides", "transcript"];
const KIND_LABEL = { video: "视频", slides: "PPT 快照", transcript: "转写", courseware: "课件", parse: "课件解析" };
export const MAX_DOWNLOAD = 50;

/**
 * Settings the bot may read and change. where: app (UiPrefs JSON keys, applied
 * by the app), lookd (GET/PUT /api/settings) or agent (assistant prefs). No
 * secret is listed, so none is readable or writable.
 */
export const SETTINGS = {
	themeMode: { where: "app", label: "主题模式", enum: ["system", "light", "dark"], risk: "low" },
	contrast: { where: "app", label: "对比度", enum: ["standard", "medium", "high"], risk: "low" },
	textScale: { where: "app", label: "界面字号", min: 0.8, max: 1.5, risk: "low" },
	chatTextScale: { where: "app", label: "对话字号", min: 0.8, max: 1.5, risk: "low" },
	chatBubbles: { where: "app", label: "对话气泡", type: "boolean", risk: "low" },
	showThinking: { where: "app", label: "显示思考过程", type: "boolean", risk: "low" },
	reduceMotion: { where: "app", label: "减少动效", type: "boolean", risk: "low" },
	defaultSpeed: { where: "app", label: "默认倍速", min: 0.5, max: 3, risk: "low" },
	boostSpeed: { where: "app", label: "长按加速倍速", min: 1, max: 4, risk: "low" },
	seekStepSec: { where: "app", label: "快进快退步长（秒）", min: 5, max: 60, int: true, risk: "low" },
	showSubtitles: { where: "app", label: "显示字幕", type: "boolean", risk: "low" },
	subtitleScale: { where: "app", label: "字幕大小", min: 0.6, max: 2, risk: "low" },
	lecturesNewestFirst: { where: "app", label: "课程页最新一节在前", type: "boolean", risk: "low" },
	"download.video_parallel": { where: "lookd", label: "同时下载的视频数", min: 1, max: 4, int: true, fallback: 2 },
	"download.max_conns": { where: "lookd", label: "单个视频的并发连接", min: 1, max: 16, int: true, fallback: 8 },
	"download.rate_limit": { where: "lookd", label: "总速度上限（字节/秒，0 不限）", enum: [0, 2 * MB, 5 * MB, 10 * MB, 20 * MB], fallback: 0 },
	"download.stream": { where: "lookd", label: "下载哪个画面（空为自动）", enum: ["", "屏幕", "教师", "学生"], fallback: "" },
	"transcript.delete_video": { where: "lookd", label: "转写完成后删除视频", type: "boolean", fallback: false },
	"asr.strategy": { where: "lookd", label: "转写渠道分配（balance 或渠道 id）", type: "string", fallback: "balance" },
	"asr.concurrency": { where: "lookd", label: "同时识别的段数", min: 1, max: 4, int: true, fallback: 2 },
	model: { where: "agent", label: "助手默认模型（provider/model）", type: "string" },
	thinking: { where: "agent", label: "思考强度", enum: ["off", "minimal", "low", "medium", "high", "xhigh"] },
};

/** The value checked against the registry entry; throws a message listing what is allowed. */
export function checkSetting(key, value) {
	const s = SETTINGS[key];
	if (!s) throw bad(`不能修改 ${key}。可修改的设置：${Object.keys(SETTINGS).join("、")}`);
	if (s.enum) {
		if (!s.enum.includes(value)) throw bad(`${key}（${s.label}）只能是 ${s.enum.map((v) => JSON.stringify(v)).join("、")}`);
		return value;
	}
	if (s.type === "boolean") {
		if (typeof value !== "boolean") throw bad(`${key}（${s.label}）应为 true 或 false`);
		return value;
	}
	if (s.type === "string") {
		if (typeof value !== "string" || !value.trim() || value.length > 120) throw bad(`${key}（${s.label}）应为非空字符串`);
		return value.trim();
	}
	const n = Number(value);
	if (typeof value !== "number" || !Number.isFinite(n) || n < s.min || n > s.max || (s.int && !Number.isInteger(n))) {
		throw bad(`${key}（${s.label}）应为 ${s.min}–${s.max} 之间的${s.int ? "整数" : "数"}`);
	}
	return Math.round(n * 100) / 100;
}

const show = (v) => (typeof v === "boolean" ? (v ? "开" : "关") : v === "" ? "（自动）" : String(v));

/**
 * Runs a proposal's op (built by the host, never by the model). deps: api,
 * tasks, plugins, pipeline, changed() after plugin or prefs changes. Returns a
 * result; app preferences come back as {app: {...}} for the app to apply.
 */
export async function runOp(op, deps) {
	switch (op.type) {
		case "app":
			return { app: op.set };
		case "settings": {
			if (op.lookd && Object.keys(op.lookd).length) await deps.api("PUT", "/api/settings", op.lookd);
			if (op.agent && Object.keys(op.agent).length) {
				const patch = { ...op.agent };
				if (patch.model) {
					const at = patch.model.indexOf("/");
					patch.provider = patch.model.slice(0, at);
					patch.model = patch.model.slice(at + 1);
				}
				await deps.pipeline.setPrefs(patch);
			}
			return op.app && Object.keys(op.app).length ? { app: op.app } : { ok: true };
		}
		case "jobs":
			return deps.api("POST", "/api/jobs/bulk", { action: op.action, ids: op.ids });
		case "download": {
			const jobs = await deps.api("POST", "/api/jobs", { lecture_ids: op.lecture_ids, kinds: op.kinds });
			return { jobs: (jobs ?? []).length };
		}
		case "delete_files": {
			let freed = 0;
			for (const kind of op.kinds) freed += (await deps.api("DELETE", `/api/lectures/${enc(op.lecture_id)}/assets/${kind}`))?.freed ?? 0;
			return { freed };
		}
		case "course":
			await deps.api("PATCH", `/api/courses/${enc(op.course_id)}`, op.patch);
			return { ok: true };
		case "task": {
			const t = await deps.tasks.create(op.task);
			return { task_id: t.id };
		}
		case "delete_task":
			await deps.tasks.remove(op.id);
			return { ok: true };
		case "plugin":
			await deps.plugins.update(op.id, { enabled: op.enabled });
			deps.changed?.();
			return { ok: true };
		default:
			throw bad(`未知操作 ${op.type}`);
	}
}

/**
 * Operate tools for the bot. deps: bot (proposals), api, appState() (the
 * app's last pushed preferences), pipeline, tasks, plugins, changed().
 */
export function operateTools(deps) {
	const { bot, api } = deps;
	const card = async (p) => {
		const saved = await bot.propose(p);
		return { proposal: bot.view(saved) };
	};
	const done = async (p, result) => {
		const saved = await bot.propose({ ...p, applied: true, result });
		return bot.view(saved);
	};

	const currentSettings = async () => {
		const app = deps.appState() ?? {};
		let server = {};
		try {
			server = (await api("GET", "/api/settings")) ?? {};
		} catch {
			// lookd unreachable: report app and agent settings only.
		}
		const agentPrefs = deps.pipeline.prefs;
		const out = {};
		for (const [key, s] of Object.entries(SETTINGS)) {
			if (s.where === "app") out[key] = app[key];
			else if (s.where === "lookd") out[key] = server[key] ?? s.fallback;
			else if (key === "model") out[key] = agentPrefs.provider && agentPrefs.model ? `${agentPrefs.provider}/${agentPrefs.model}` : "";
			else out[key] = agentPrefs[key];
		}
		return out;
	};

	return [
		{
			name: "open_page",
			label: "打开页面",
			description:
				"Navigate the app for the user. targets: home, courses, course (course_id), lecture (lecture_id, optional t seconds), note (note_id), schedule (optional day YYYY-MM-DD), downloads, library, tasks, plugins, settings (optional section), activity, usage, bot.",
			promptSnippet: "open_page(target, …): navigate the app (course, lecture, note, schedule, downloads, settings, …)",
			parameters: Type.Object({
				target: lit(["home", "courses", "course", "lecture", "note", "schedule", "downloads", "library", "tasks", "plugins", "settings", "activity", "usage", "bot"]),
				course_id: Type.Optional(Type.String()),
				lecture_id: Type.Optional(Type.String()),
				note_id: Type.Optional(Type.String()),
				t: Type.Optional(Type.Number({ description: "Seconds into the lecture" })),
				day: Type.Optional(Type.String({ description: "YYYY-MM-DD" })),
				section: Type.Optional(lit(["account", "canvas", "appearance", "player", "assistant", "models", "plugins", "downloads", "transcript", "courseware", "knowledge", "storage", "obsidian", "notion", "sync", "backup", "notifications", "diagnostics"])),
			}),
			execute: async (_id, p) => {
				const need = { course: "course_id", lecture: "lecture_id", note: "note_id" }[p.target];
				if (need && !p[need]) throw bad(`打开 ${p.target} 需要 ${need}`);
				if (p.day && !/^\d{4}-\d{2}-\d{2}$/.test(p.day)) throw bad("day 格式应为 YYYY-MM-DD");
				const app = { op: "open", ...p };
				return text(`已在应用里打开 ${p.target}。`, { app });
			},
		},
		{
			name: "player",
			label: "控制播放",
			description: "Control the open player: play, pause, seek (seconds) or speed (rate 0.5–3). Only when the context says a lecture is playing.",
			parameters: Type.Object({
				action: lit(["play", "pause", "seek", "speed"]),
				seconds: Type.Optional(Type.Number()),
				rate: Type.Optional(Type.Number()),
			}),
			execute: async (_id, p) => {
				if (p.action === "seek" && !(p.seconds >= 0)) throw bad("seek 需要 seconds");
				if (p.action === "speed" && !(p.rate >= 0.5 && p.rate <= 3)) throw bad("speed 需要 0.5–3 之间的 rate");
				return text(`已发送播放器指令 ${p.action}。`, { app: { op: "player", ...p } });
			},
		},
		{
			name: "read_settings",
			label: "读取设置",
			description: "Read the settings the bot can change, with their current values and allowed values.",
			parameters: Type.Object({}),
			execute: async () => {
				const cur = await currentSettings();
				const lines = Object.entries(SETTINGS).map(([k, s]) => {
					const allowed = s.enum ? s.enum.map((v) => JSON.stringify(v)).join("|") : s.type ?? `${s.min}–${s.max}`;
					return `- ${k}（${s.label}）= ${JSON.stringify(cur[k] ?? null)}；可选 ${allowed}${s.risk === "low" ? "；立即生效" : "；需用户在卡片上确认"}`;
				});
				return text(`当前设置：\n${lines.join("\n")}`);
			},
		},
		{
			name: "change_settings",
			label: "修改设置",
			description:
				"Change settings by registry key (see read_settings). Appearance and player keys apply at once with undo; download, transcription and model keys become a card the user applies.",
			parameters: Type.Object({
				changes: Type.Array(Type.Object({ key: Type.String(), value: Type.Any() }), { minItems: 1, maxItems: 10 }),
				reason: Type.String({ description: "One line shown to the user" }),
			}),
			execute: async (_id, { changes, reason }) => {
				const clean = changes.map(({ key, value }) => ({ key, value: checkSetting(key, value) }));
				const cur = await currentSettings();
				if (clean.some((c) => c.key === "model")) {
					const desc = await deps.pipeline.describe();
					const ok = new Set(desc.providers.flatMap((p) => p.models.filter((m) => m.available).map((m) => `${p.id}/${m.id}`)));
					for (const c of clean) if (c.key === "model" && !ok.has(c.value)) throw bad(`模型 ${c.value} 不可用。可用：${[...ok].slice(0, 20).join("、")}`);
				}
				const line = (c) => `${SETTINGS[c.key].label}：${show(cur[c.key])} → ${show(c.value)}`;
				const low = clean.filter((c) => SETTINGS[c.key].risk === "low");
				const rest = clean.filter((c) => SETTINGS[c.key].risk !== "low");
				const details = {};
				const said = [];
				if (low.length) {
					const set = Object.fromEntries(low.map((c) => [c.key, c.value]));
					const old = Object.fromEntries(low.map((c) => [c.key, cur[c.key]]).filter(([, v]) => v !== undefined));
					const view = await done({ kind: "settings", title: "已调整设置", lines: low.map(line), op: { type: "app", set }, undo: { type: "app", set: old } }, { app: set });
					details.app = { op: "prefs", set, proposal_id: view.id, label: `已调整 ${low.map((c) => SETTINGS[c.key].label).join("、")}` };
					said.push(`已调整 ${low.map(line).join("；")}（用户可撤销）`);
				}
				if (rest.length) {
					const op = { type: "settings", app: {}, lookd: {}, agent: {} };
					const undo = { type: "settings", app: {}, lookd: {}, agent: {} };
					for (const c of rest) {
						op[SETTINGS[c.key].where][c.key] = c.value;
						if (cur[c.key] !== undefined && cur[c.key] !== "") undo[SETTINGS[c.key].where][c.key] = cur[c.key];
					}
					Object.assign(details, await card({ kind: "settings", title: reason.slice(0, 60) || "修改设置", lines: rest.map(line), op, undo }));
					said.push(`已向用户展示确认卡片：${rest.map(line).join("；")}。用户点“应用”后才会生效，不要声称已修改`);
				}
				return text(said.join("\n"), details);
			},
		},
		{
			name: "manage_downloads",
			label: "管理下载",
			description: "Pause, resume or retry download jobs (all matching jobs without job_ids). Applies at once; the user can undo.",
			parameters: Type.Object({ action: lit(["pause", "resume", "retry"]), job_ids: Type.Optional(Type.Array(Type.String(), { maxItems: 200 })) }),
			execute: async (_id, { action, job_ids }) => {
				const from = { pause: ["queued", "running"], resume: ["paused"], retry: ["failed"] }[action];
				const jobs = ((await api("GET", "/api/jobs")) ?? []).filter((j) => from.includes(j.state) && (!job_ids?.length || job_ids.includes(j.id)));
				if (!jobs.length) return text("没有符合条件的下载任务。");
				const ids = jobs.map((j) => j.id);
				const result = await runOp({ type: "jobs", action, ids }, deps);
				const verb = { pause: "暂停", resume: "继续", retry: "重试" }[action];
				const view = await done(
					{ kind: "downloads", title: `已${verb} ${ids.length} 个下载`, lines: jobs.slice(0, 8).map((j) => `${j.title || j.lecture_id} · ${KIND_LABEL[j.kind] ?? j.kind}`), op: { type: "jobs", action, ids }, undo: { type: "jobs", action: action === "pause" ? "resume" : "pause", ids } },
					result,
				);
				return text(`已${verb} ${ids.length} 个下载任务（用户可撤销）。`, { app: { op: "done", label: view.title, proposal_id: view.id } });
			},
		},
		{
			name: "download",
			label: "下载",
			description: `Propose downloading lectures (≤ ${MAX_DOWNLOAD}) as a card; nothing starts until the user applies it. kinds: video, slides, transcript.`,
			parameters: Type.Object({
				lecture_ids: Type.Array(Type.String(), { minItems: 1, maxItems: MAX_DOWNLOAD }),
				kinds: Type.Array(lit(DOWNLOAD_KINDS), { minItems: 1 }),
			}),
			execute: async (_id, { lecture_ids, kinds }) => {
				const ids = [...new Set(lecture_ids)];
				if (ids.length > MAX_DOWNLOAD) throw bad(`一次最多 ${MAX_DOWNLOAD} 节`);
				const ks = [...new Set(kinds)].filter((k) => DOWNLOAD_KINDS.includes(k));
				if (!ks.length) throw bad(`kinds 只能是 ${DOWNLOAD_KINDS.join("、")}`);
				const lectures = [];
				for (const id of ids) {
					const l = (await api("GET", `/api/lectures/${enc(id)}`).catch(() => null))?.lecture;
					if (!l) throw bad(`没有节次 ${id}`);
					lectures.push(l);
				}
				const lines = lectures.slice(0, 12).map((l) => `${l.date ?? ""} ${l.title ?? l.id}`.trim());
				if (lectures.length > 12) lines.push(`…共 ${lectures.length} 节`);
				const title = `下载 ${lectures.length} 节的${ks.map((k) => KIND_LABEL[k]).join("、")}`;
				const details = await card({ kind: "download", title, lines, op: { type: "download", lecture_ids: ids, kinds: ks } });
				return text(`已向用户展示下载卡片「${title}」，用户点“应用”后才开始下载。不要声称已开始。`, details);
			},
		},
		{
			name: "delete_files",
			label: "删除本地文件",
			description: "Propose deleting a lecture's downloaded files of the given kinds as a card.",
			parameters: Type.Object({ lecture_id: Type.String(), kinds: Type.Array(lit(["video", "slides", "transcript", "courseware", "parse"]), { minItems: 1 }) }),
			execute: async (_id, { lecture_id, kinds }) => {
				const l = (await api("GET", `/api/lectures/${enc(lecture_id)}`).catch(() => null))?.lecture;
				if (!l) throw bad(`没有节次 ${lecture_id}`);
				const ks = [...new Set(kinds)];
				const title = `删除「${l.title ?? lecture_id}」的${ks.map((k) => KIND_LABEL[k]).join("、")}`;
				const details = await card({ kind: "delete_files", title, lines: ["删除后需要重新下载才能恢复"], op: { type: "delete_files", lecture_id, kinds: ks } });
				return text(`已向用户展示删除卡片「${title}」，用户确认后才会删除。`, details);
			},
		},
		{
			name: "manage_course",
			label: "管理课程",
			description: `Pin, hide, rename (alias, empty to clear) or colour a course. color: ${Object.keys(COURSE_COLORS).join(", ")}. Applies at once; the user can undo.`,
			parameters: Type.Object({
				course_id: Type.String(),
				pinned: Type.Optional(Type.Boolean()),
				hidden: Type.Optional(Type.Boolean()),
				alias: Type.Optional(Type.String({ maxLength: 40 })),
				color: Type.Optional(lit(Object.keys(COURSE_COLORS))),
			}),
			execute: async (_id, { course_id, ...p }) => {
				const course = ((await api("GET", "/api/courses")) ?? []).find((c) => c.id === course_id);
				if (!course) throw bad(`没有课程 ${course_id}`);
				const patch = {};
				if (p.pinned !== undefined) patch.pinned = p.pinned;
				if (p.hidden !== undefined) patch.hidden = p.hidden;
				if (p.alias !== undefined) patch.alias = p.alias.trim().slice(0, 40);
				if (p.color !== undefined) patch.color = COURSE_COLORS[p.color];
				if (!Object.keys(patch).length) throw bad("没有要修改的内容");
				const undo = Object.fromEntries(Object.keys(patch).map((k) => [k, course[k] ?? (k === "pinned" || k === "hidden" ? false : "")]));
				await runOp({ type: "course", course_id, patch }, deps);
				const label = { pinned: (v) => (v ? "置顶" : "取消置顶"), hidden: (v) => (v ? "隐藏" : "取消隐藏"), alias: (v) => (v ? `改名为「${v}」` : "恢复原名"), color: (v) => (v ? "换了颜色" : "恢复默认颜色") };
				const lines = Object.entries(patch).map(([k, v]) => label[k](v));
				const view = await done({ kind: "course", title: `${course.alias || course.title}：${lines.join("、")}`, lines, op: { type: "course", course_id, patch }, undo: { type: "course", course_id, patch: undo } }, { ok: true });
				return text(`已${lines.join("、")}（用户可撤销）。`, { app: { op: "done", label: view.title, proposal_id: view.id } });
			},
		},
		{
			name: "sync_courses",
			label: "同步课程",
			description: "Refresh the course list from the Look platform.",
			parameters: Type.Object({}),
			execute: async () => {
				const list = (await api("GET", "/api/courses?sync=1")) ?? [];
				return text(`已同步，共 ${list.length} 门课程。`);
			},
		},
		{
			name: "propose_task",
			label: "创建定时任务",
			description:
				"Propose a scheduled assistant task as a card. schedule: {type: daily, time: HH:MM} | {type: weekly, days: [1-7], time} | {type: once, at: YYYY-MM-DDTHH:MM}. writes ⊂ notes, schedule, quiz. budget_usd 0.01–5 (default 0.2).",
			parameters: Type.Object({
				name: Type.String(),
				prompt: Type.String(),
				schedule: Type.Object({ type: lit(["daily", "weekly", "once"]), time: Type.Optional(Type.String()), days: Type.Optional(Type.Array(Type.Number())), at: Type.Optional(Type.String()) }),
				writes: Type.Optional(Type.Array(lit(["notes", "schedule", "quiz"]))),
				budget_usd: Type.Optional(Type.Number()),
			}),
			execute: async (_id, p) => {
				const t = validateTask(p);
				const input = { name: t.name, prompt: t.prompt, schedule: t.schedule, writes: t.writes, budget_usd: t.budget_usd };
				const when = t.schedule.type === "daily" ? `每天 ${t.schedule.time}` : t.schedule.type === "weekly" ? `每周${t.schedule.days.map((d) => "一二三四五六日"[d - 1]).join("、")} ${t.schedule.time}` : t.schedule.at.replace("T", " ");
				const lines = [when, t.prompt.slice(0, 120), `可写入：${t.writes.length ? t.writes.join("、") : "无"} · 上限 $${t.budget_usd}`];
				const details = await card({ kind: "task", title: `定时任务「${t.name}」`, lines, op: { type: "task", task: input } });
				return text("已向用户展示定时任务卡片，用户确认后才会创建。", details);
			},
		},
		{
			name: "toggle_plugin",
			label: "开关插件",
			description: "Propose enabling or disabling an installed plugin as a card. Installing new plugins is done by the user on the plugins page (open_page target plugins).",
			parameters: Type.Object({ id: Type.String(), enabled: Type.Boolean() }),
			execute: async (_id, { id, enabled }) => {
				const p = (await deps.plugins.list()).find((x) => x.id === id);
				if (!p) throw bad(`没有安装插件 ${id}。安装请让用户在插件页完成。`);
				if (p.enabled === enabled) return text(`插件 ${p.name ?? id} 已经是${enabled ? "启用" : "停用"}状态。`);
				const details = await card({ kind: "plugin", title: `${enabled ? "启用" : "停用"}插件「${p.name ?? id}」`, lines: [p.description ?? ""].filter(Boolean), op: { type: "plugin", id, enabled }, undo: { type: "plugin", id, enabled: !enabled } });
				return text("已向用户展示插件开关卡片。", details);
			},
		},
	];
}

export const OPERATE_GROUP = {
	label: "操作应用",
	tools: ["player", "read_settings", "change_settings", "manage_downloads", "download", "delete_files", "manage_course", "sync_courses", "propose_task", "toggle_plugin"],
	words: "设置 字号 主题 深色 倍速 字幕 播放 暂停 下载 删除 置顶 隐藏 改名 颜色 同步 定时 任务 插件 打开 settings player download plugin",
};
export const MEMORY_GROUP = {
	label: "记忆",
	tools: ["memory_list", "memory_read", "memory_write", "memory_edit", "memory_append", "memory_delete"],
	words: "记住 记忆 忘记 偏好 习惯 以后 别再 memory remember forget",
};
