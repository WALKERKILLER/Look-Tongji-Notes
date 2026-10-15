// Look Studio agent host: a minimal Pi agent embedded through the SDK.
// lookd starts this process, reads "AGENT_READY <port>" and proxies /agent/*.
import { createServer } from "node:http";
import { mkdir, rm } from "node:fs/promises";
import { join } from "node:path";
import {
	createAgentSession,
	createExtensionRuntime,
	SessionManager,
	SettingsManager,
} from "@earendil-works/pi-coding-agent";
import { DATA_DIR, ModelPipeline } from "./models.mjs";
import { createTools, TURN_TOOL_BUDGET } from "./tools.mjs";
import { generateTimeline } from "./timeline.mjs";
import { entryFrom, UsageLedger } from "./usage.mjs";

const TOKEN = process.env.LOOKD_TOKEN ?? "";
const CWD = process.env.LIBRARY_ROOT ?? process.cwd();
const SESSIONS = join(DATA_DIR, "sessions");
await mkdir(SESSIONS, { recursive: true });

const pipeline = new ModelPipeline();
await pipeline.init();
const usage = new UsageLedger(DATA_DIR);
pipeline.usage = usage;
try {
	await usage.backfill(SESSIONS);
} catch (e) {
	console.error(`usage backfill: ${e.message}`);
}

const SYSTEM = `你是 Look Studio 的常驻助手，帮助同济大学学生使用 Look 录课平台的课程录像。
你能做的：介绍应用功能、查看课程与节次、阅读转写稿、看 PPT 与课件、全文搜索、整理与保存笔记、生成时间轴大纲、标记日程、出复习题。
工具：
- 起初只有核心工具（current_context、read_transcript、search_library、suggest_actions、find_tools）。需要别的能力时先调用 find_tools 加载工具组：course（课程与节次）、notes（笔记，会一并加载 PPT 与课件工具并给出写笔记流程）、schedule（日程）、outline（时间轴大纲）、materials（查看 PPT、搜索与阅读课件）、help（应用功能说明）。加载后在本对话中一直可用，不要重复加载。
- 每轮最多调用 ${TURN_TOOL_BUDGET} 次工具。长文字稿按需分页读取，先用 search_library 或大纲定位，不要一次读完整节课。
原则：
- 先用工具获取事实，不要编造课程内容；引用课堂内容时标注 [mm:ss] 或 [h:mm:ss] 时间戳，界面会把它们变成可点击的跳转。
- 时间戳默认指当前节次（播放器里的课或笔记所属的课）。引用其他节次时写成 [mm:ss](look://lecture/<lecture_id>?t=<秒>)。
- 下载、转写等操作由用户在界面里点击完成。需要时用 suggest_actions 给出按钮（例如“跳转到 12:03”“下载本节 PPT”），不要声称已经替用户执行。
- 用户正在看的页面可通过 current_context 获取；消息开头的 <context> 块也描述了当前页面。
- 日程：只有原话里出现明确日期或星期（如“10月20日前交”“下周三小测”“明天上机”）时，才用 mark_schedule 标记作业、考试、活动、截止。quote 逐字摘录原话；相对日期以这节课的日期换算（来自聊天时以今天换算）。没有日期的事项只在回复里提醒，不要标记，也不要猜日期。同一件事只标记一次；标记后在回复里一句话说明，用户可以在卡片上撤销。
- 大纲：用户要大纲、时间轴、章节时用 generate_timeline（它会自己读全文），不必先读文字稿；调整时用 save_timeline。
- 用户要整理/写一节课的笔记时，先 find_tools(groups:["notes"])，严格按返回的写笔记流程执行（字幕优先 → 重点与疑点 → 对照 PPT → 查课件 → 保存），完成后保存为笔记并在回复里简述。只是问答或讲解时不必保存。
- 公式用 LaTeX：行内 $...$，独立公式 $$...$$；引用课堂内容附时间戳。
- 回答简洁、中文为主；专有名词可保留英文。不要索要或复述密码。`;

const resourceLoader = {
	getExtensions: () => ({ extensions: [], errors: [], runtime: createExtensionRuntime() }),
	getSkills: () => ({ skills: [], diagnostics: [] }),
	getPrompts: () => ({ prompts: [], diagnostics: [] }),
	getThemes: () => ({ themes: [], diagnostics: [] }),
	getAgentsFiles: () => ({ agentsFiles: [] }),
	getSystemPrompt: () => (pipeline.prefs.persona ? `${SYSTEM}\n\n用户偏好：${pipeline.prefs.persona}` : SYSTEM),
	getSystemPromptSource: () => undefined,
	getAppendSystemPrompt: () => [],
	getAppendSystemPromptSources: () => [],
	extendResources: () => {},
	reload: async () => {},
};

// ---- conversations ----

/** @type {Map<string, {session: any, context: any, busy: boolean, used: number, calls: number, lastUser: string}>} */
const live = new Map();
const MAX_LIVE = 4;

async function openConversation(id) {
	if (id && live.has(id)) {
		const c = live.get(id);
		c.used = Date.now();
		return c;
	}
	let sessionManager;
	if (id) {
		const path = SessionManager.findById(CWD, id, SESSIONS);
		if (!path) throw httpError(404, "会话不存在");
		sessionManager = SessionManager.open(path, SESSIONS);
	} else {
		sessionManager = SessionManager.create(CWD, SESSIONS);
	}
	const model = await pipeline.currentModel();
	if (!model) throw httpError(409, "还没有可用的模型。请在 设置 → 模型 中添加 API Key 或导入 Pi CLI 配置。");
	const conv = {
		session: null,
		context: null,
		busy: false,
		used: Date.now(),
		calls: 0,
		lastUser: "",
		pipeline,
		// Ledger attribution; scheduled runs set purpose "task" and taskId.
		purpose: "chat",
		taskId: null,
		// find_tools: declare more tools from the next model call on.
		load(names) {
			const active = conv.session.getActiveToolNames();
			conv.session.setActiveToolsByName([...new Set([...active, ...names])]);
		},
	};
	const { session } = await createAgentSession({
		cwd: CWD,
		agentDir: DATA_DIR,
		modelRuntime: pipeline.runtime,
		model,
		thinkingLevel: model.reasoning ? pipeline.prefs.thinking : "off",
		resourceLoader,
		sessionManager,
		settingsManager: SettingsManager.inMemory({ compaction: { enabled: true }, retry: { enabled: true, maxRetries: 2 } }),
		noTools: "builtin",
		customTools: createTools(conv),
	});
	conv.session = session;
	recordUsage(conv);
	live.set(session.sessionId, conv);
	if (live.size > MAX_LIVE) {
		const idle = [...live.entries()].filter(([, c]) => !c.busy).sort((a, b) => a[1].used - b[1].used)[0];
		if (idle) {
			idle[1].session.dispose();
			live.delete(idle[0]);
		}
	}
	return conv;
}

// Every assistant message, including tool-loop round trips, is one ledger line.
function recordUsage(conv) {
	let started = 0;
	let ttft = null;
	conv.session.subscribe((ev) => {
		if (ev.type === "message_start" && ev.message?.role === "assistant") {
			started = Date.now();
			ttft = null;
		} else if (ev.type === "message_update" && ttft === null && started) {
			ttft = Date.now() - started;
		} else if (ev.type === "message_end" && ev.message?.role === "assistant") {
			usage.record(
				entryFrom(ev.message, { purpose: conv.purpose, session_id: conv.session.sessionId, task_id: conv.taskId, ttft_ms: ttft ?? undefined }),
			);
			started = 0;
		}
	});
}

// Model/prefs changes apply to idle conversations on next open.
pipeline.onChange(() => {
	for (const [id, c] of live) {
		if (!c.busy) {
			c.session.dispose();
			live.delete(id);
		}
	}
});

const WEEK = ["日", "一", "二", "三", "四", "五", "六"];

function contextBlock(ctx) {
	const now = new Date();
	const today = `${now.toLocaleDateString("sv-SE")} 周${WEEK[now.getDay()]}`;
	const parts = Object.entries({ today, ...(ctx && typeof ctx === "object" ? ctx : {}) })
		.filter(([, v]) => v !== undefined && v !== null && v !== "")
		.map(([k, v]) => `${k}: ${v}`);
	return parts.length ? `<context>\n${parts.join("\n")}\n</context>\n\n` : "";
}

function sessionStats(s) {
	try {
		const st = s.getSessionStats();
		const u = s.getContextUsage?.() ?? st.contextUsage;
		return {
			tokens: st.tokens,
			cost: st.cost,
			context: u ? { tokens: u.tokens, window: u.contextWindow, percent: u.percent } : null,
		};
	} catch {
		return null;
	}
}

function messageView(m) {
	if (m.role === "user") {
		const t = (Array.isArray(m.content) ? m.content : [{ type: "text", text: m.content }])
			.filter((c) => c.type === "text")
			.map((c) => c.text)
			.join("");
		return { role: "user", text: t.replace(/^<context>[\s\S]*?<\/context>\n\n/, "") };
	}
	if (m.role === "assistant") {
		return {
			role: "assistant",
			blocks: m.content.map((c) =>
				c.type === "text"
					? { type: "text", text: c.text }
					: c.type === "thinking"
						? { type: "thinking", text: c.thinking ?? "" }
						: { type: "tool", id: c.id, name: c.name, args: c.arguments },
			),
			model: m.model,
			usage: m.usage ? { input: m.usage.input, output: m.usage.output, cost: m.usage.cost?.total ?? 0 } : undefined,
			error: m.stopReason === "error" ? m.errorMessage : undefined,
		};
	}
	if (m.role === "toolResult") {
		return {
			role: "tool",
			id: m.toolCallId,
			name: m.toolName,
			error: !!m.isError,
			text: (m.content ?? []).filter((c) => c.type === "text").map((c) => c.text).join("").slice(0, 4000),
			details: m.details,
		};
	}
	return null;
}

// ---- HTTP ----

function httpError(status, message) {
	return Object.assign(new Error(message), { status });
}

async function body(req) {
	const chunks = [];
	for await (const c of req) chunks.push(c);
	const raw = Buffer.concat(chunks).toString("utf8");
	if (!raw) return {};
	try {
		return JSON.parse(raw);
	} catch {
		throw httpError(400, "请求体不是 JSON");
	}
}

function send(res, status, data) {
	res.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
	res.end(JSON.stringify(data));
}

const routes = [];
const route = (method, pattern, fn) => routes.push({ method, re: new RegExp(`^${pattern}$`), fn });

route("GET", "/health", async () => ({ ok: true, sdk: "@earendil-works/pi-coding-agent" }));
route("GET", "/models", async () => pipeline.describe());
route("PUT", "/prefs", async (req) => {
	await pipeline.setPrefs(await body(req));
	return pipeline.describe();
});
route("PUT", "/providers/([^/]+)/key", async (req, [id]) => {
	const { api_key } = await body(req);
	await pipeline.setKey(decodeURIComponent(id), (api_key ?? "").trim());
	return pipeline.describe();
});
route("PUT", "/providers/([^/]+)", async (req, [id]) => {
	const b = await body(req);
	await pipeline.upsertProvider({
		id: decodeURIComponent(id),
		baseUrl: b.base_url,
		api: b.api,
		apiKey: b.api_key,
		headers: b.headers,
		models: b.models,
		catalogId: b.catalog_id || undefined,
	});
	return pipeline.describe();
});
route("DELETE", "/providers/([^/]+)", async (_req, [id]) => {
	await pipeline.removeProvider(decodeURIComponent(id));
	return pipeline.describe();
});
route("POST", "/providers/([^/]+)/test", async (req, [id]) => {
	const { model } = await body(req);
	return pipeline.test(decodeURIComponent(id), model);
});
route("POST", "/discover", async (req) => {
	const { base_url, api, api_key, provider, catalog_id } = await body(req);
	return { models: await pipeline.discover({ baseUrl: base_url, api, apiKey: api_key, provider, catalogId: catalog_id }) };
});
route("GET", "/catalog/providers", async (req) => {
	const refresh = new URL(req.url, "http://x").searchParams.get("refresh") === "1";
	return { providers: await pipeline.catalog.providers({ refresh }), updated: pipeline.catalog.fetchedAt };
});
route("GET", "/catalog/providers/([^/]+)/models", async (_req, [id]) => ({
	models: await pipeline.catalog.providerModels(decodeURIComponent(id)),
}));
route("POST", "/import/pi", async () => ({ imported: await pipeline.importPiCli(), models: await pipeline.describe() }));

// POST /timeline generates and saves a lecture outline (the player's button).
route("POST", "/timeline", async (req, _m, res) => {
	const { lecture_id } = await body(req);
	if (!lecture_id) throw httpError(400, "缺少 lecture_id");
	const ac = new AbortController();
	res.on("close", () => {
		if (!res.writableFinished) ac.abort();
	});
	return { chapters: await generateTimeline(pipeline, lecture_id, ac.signal) };
});

function sessionTitle(s) {
	return s.name || s.firstMessage.replace(/^<context>[\s\S]*?<\/context>\s*/, "").slice(0, 60) || "新对话";
}

route("GET", "/usage/summary", async (req) => {
	const q = new URL(req.url, "http://x").searchParams;
	const titles = new Map((await SessionManager.list(CWD, SESSIONS)).map((s) => [s.id, sessionTitle(s)]));
	return usage.summary(q.get("from") ?? "", q.get("to") ?? "", titles);
});
route("GET", "/usage/calls", async (req) => {
	const q = new URL(req.url, "http://x").searchParams;
	const titles = new Map((await SessionManager.list(CWD, SESSIONS)).map((s) => [s.id, sessionTitle(s)]));
	const calls = await usage.calls({
		before: q.get("before") || undefined,
		limit: Math.min(Number(q.get("limit")) || 50, 200),
		from: q.get("from") || undefined,
		to: q.get("to") || undefined,
		model: q.get("model") || undefined,
		purpose: q.get("purpose") || undefined,
		session_id: q.get("session_id") || undefined,
	});
	return calls.map((c) => (c.session_id ? { ...c, title: titles.get(c.session_id) ?? null } : c));
});

route("GET", "/sessions", async () => {
	const list = await SessionManager.list(CWD, SESSIONS);
	return list
		.sort((a, b) => b.modified - a.modified)
		.slice(0, 200)
		.map((s) => ({
			id: s.id,
			title: sessionTitle(s),
			modified: s.modified,
			messages: s.messageCount,
			busy: live.get(s.id)?.busy ?? false,
		}));
});
route("GET", "/sessions/([^/]+)", async (_req, [id]) => {
	const conv = await openConversation(id);
	const s = conv.session;
	return {
		id: s.sessionId,
		model: s.model ? `${s.model.provider}/${s.model.id}` : null,
		busy: conv.busy,
		stats: sessionStats(s),
		messages: s.messages.map(messageView).filter(Boolean),
	};
});
route("POST", "/sessions/([^/]+)/compact", async (_req, [id]) => {
	const conv = await openConversation(id);
	if (conv.busy) throw httpError(409, "这个对话正在回复中");
	conv.busy = true;
	try {
		await conv.session.compact();
	} finally {
		conv.busy = false;
	}
	return { ok: true, stats: sessionStats(conv.session) };
});
route("DELETE", "/sessions/([^/]+)", async (_req, [id]) => {
	const c = live.get(id);
	if (c) {
		await c.session.abort().catch(() => {});
		c.session.dispose();
		live.delete(id);
	}
	const path = SessionManager.findById(CWD, id, SESSIONS);
	if (path) await rm(path, { force: true });
	return { ok: true };
});
route("POST", "/sessions/([^/]+)/abort", async (_req, [id]) => {
	await live.get(id)?.session.abort();
	return { ok: true };
});

// POST /chat streams Server-Sent Events for one prompt.
route("POST", "/chat", async (req, _m, res) => {
	const { session_id, message, context } = await body(req);
	if (!message?.trim()) throw httpError(400, "消息为空");
	const conv = await openConversation(session_id || undefined);
	const s = conv.session;
	if (conv.busy) throw httpError(409, "这个对话正在回复中");
	conv.busy = true;
	conv.context = context ?? null;
	conv.calls = 0;
	conv.lastUser = message;

	res.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-cache", "X-Accel-Buffering": "no" });
	const emit = (type, data = {}) => res.write(`data: ${JSON.stringify({ type, ...data })}\n\n`);
	emit("start", { session_id: s.sessionId, model: s.model ? `${s.model.provider}/${s.model.id}` : null });

	const unsub = s.subscribe((ev) => {
		switch (ev.type) {
			case "message_update": {
				const e = ev.assistantMessageEvent;
				if (e.type === "text_delta") emit("text", { delta: e.delta });
				else if (e.type === "thinking_delta") emit("thinking", { delta: e.delta });
				else if (e.type === "text_start") emit("block", { kind: "text" });
				else if (e.type === "thinking_start") emit("block", { kind: "thinking" });
				else if (e.type === "toolcall_end") emit("tool_call", { id: e.toolCall.id, name: e.toolCall.name, args: e.toolCall.arguments });
				break;
			}
			case "tool_execution_start":
				emit("tool_start", { id: ev.toolCallId, name: ev.toolName, args: ev.args });
				break;
			case "tool_execution_end": {
				const r = ev.result ?? {};
				const t = (r.content ?? []).filter((c) => c.type === "text").map((c) => c.text).join("");
				emit("tool_end", { id: ev.toolCallId, name: ev.toolName, error: ev.isError, text: t.slice(0, 2000), details: r.details, ms: ev.durationMs });
				break;
			}
			case "message_end":
				if (ev.message.role === "assistant") {
					const m = ev.message;
					emit("message_end", {
						usage: m.usage ? { input: m.usage.input, output: m.usage.output, cost: m.usage.cost?.total ?? 0 } : null,
						error: m.stopReason === "error" ? m.errorMessage : null,
					});
				}
				break;
			case "auto_retry_start":
				emit("status", { text: "请求失败，正在重试…" });
				break;
			case "compaction_start":
				emit("status", { text: "正在压缩上下文…" });
				break;
		}
	});
	const onClose = () => {
		if (!res.writableFinished) s.abort().catch(() => {});
	};
	res.on("close", onClose);
	try {
		await s.prompt(contextBlock(context) + message.trim());
		if (pipeline.prefs.autoTitle && !s.sessionManager?.getSessionName?.() && s.messages.length <= 4) {
			s.setSessionName(message.trim().replace(/\s+/g, " ").slice(0, 40));
		}
		emit("done", { stats: sessionStats(s) });
	} catch (e) {
		emit("error", { message: String(e?.message ?? e) });
	} finally {
		unsub();
		res.off("close", onClose);
		conv.busy = false;
		res.end();
	}
	return undefined;
});

const server = createServer(async (req, res) => {
	if (req.headers.authorization !== `Bearer ${TOKEN}`) return send(res, 401, { error: "unauthorized" });
	const url = new URL(req.url, "http://x");
	for (const r of routes) {
		const m = r.method === req.method && url.pathname.match(r.re);
		if (!m) continue;
		try {
			const out = await r.fn(req, m.slice(1), res);
			if (out !== undefined && !res.headersSent) send(res, 200, out);
		} catch (e) {
			if (!res.headersSent) send(res, e.status ?? 500, { error: String(e?.message ?? e) });
			else res.end();
		}
		return;
	}
	send(res, 404, { error: "not found" });
});

server.listen(0, "127.0.0.1", () => {
	process.stdout.write(`AGENT_READY ${server.address().port}\n`);
});

for (const sig of ["SIGINT", "SIGTERM"]) {
	process.on(sig, () => {
		for (const c of live.values()) c.session.dispose();
		server.close();
		process.exit(0);
	});
}

// lookd may exit before it can signal us; leave with it instead of lingering.
const parentPid = process.ppid;
setInterval(() => {
	if (process.ppid !== parentPid) process.kill(process.pid, "SIGTERM");
}, 3000).unref();
