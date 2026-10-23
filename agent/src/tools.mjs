// Tools the resident assistant can call. All data comes from lookd; the
// assistant reads and organizes, while downloads stay user-initiated (the
// assistant can only *suggest* actions that render as buttons in the app).
//
// Only a small core is declared to the model up front. The rest are grouped
// and loaded on demand with find_tools, so tool schemas do not fill the
// context of every request.
import { Type } from "typebox";
import { api, get } from "./lookd.mjs";
import { checkQuiz, QUIZ_PLAYBOOK } from "./practice.mjs";
import { TASK_WRITES } from "./tasks.mjs";
import { generateTimeline } from "./timeline.mjs";
import { seeImages } from "./vision.mjs";

export const clock = (ms) => {
	const s = Math.floor(ms / 1000);
	const h = Math.floor(s / 3600);
	const mm = String(Math.floor((s % 3600) / 60)).padStart(2, "0");
	const ss = String(s % 60).padStart(2, "0");
	return h ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
};

const text = (t, details = {}) => ({ content: [{ type: "text", text: t }], details });
const json = (v) => JSON.stringify(v, null, 1);
const enc = encodeURIComponent;

const GUIDE = {
	overview: `Look Studio 是同济 Look 录课平台的桌面/移动客户端。主要页面：
- 首页：继续观看、即将到来的日程、最近课程、下载动态。
- 课程：全部课程（可置顶、改别名、设颜色），点进课程看节次列表，可多选批量下载。
- 日程：月历 + 日程列表，记录作业、考试、活动；助手在课堂录音或聊天里发现带日期的事项时可以标记进来，每条都附原话和录像时间点。
- 播放器：多机位切换、倍速（长按加速）、大纲（AI 生成的时间轴章节，进度条分段显示）、PPT 同步面板、课件、转写字幕与全文、时间书签、截图。
- 下载：视频/PPT 快照/转写/课件解析 任务，支持暂停、继续、限速；转写会自动复用已下载的视频。
- 资料库：全文搜索所有转写稿与笔记，笔记以 Markdown 文件保存在课程库文件夹中。
- 助手（就是我）：解释功能、整理笔记、生成大纲、标记日程、出题复习。
- 设置：外观、账户、下载、转写、课件解析（MinerU）、模型配置、存储与导出。`,
	login: `登录使用同济统一身份认证（学号+密码），应用内直接完成，无需浏览器。勾选“记住我”后，令牌临近过期会先用 IAM 单点会话静默续期，必要时用加密保存的密码重新登录，全程无需操作。`,
	download: `在课程或节次页点“下载”，选择 视频 / PPT 快照 / 转写。下载器为 Go 实现：分段多连接、断点续传、签名过期自动重签、可在设置里限速和调整并发。下载页的“已下载”可以按课次、按类型删除本地文件释放空间；设置里可开启“转写完成后删除视频”。`,
	transcript: `转写使用免费云端识别（必剪、剪映两个渠道负载均衡，可在 设置 → 转写 中开关渠道和选择分配方式）：自动提取 16kHz 单声道音频，切成 20 分钟的段识别，某渠道被限流时自动冷却并换另一个，已完成的段在重试时保留。结果写入 transcript.srt 与 transcript.md（按约 60 秒分段，带 [mm:ss] 时间戳），并建立全文索引。`,
	courseware: `Look 平台不提供课件，可以自己上传：播放器 → 资料 → 课件 → 上传（PDF、PPT、Word、Excel、图片）。上传后用 MinerU 在线解析为 Markdown（公式、表格、图片都会保留），解析结果保存在课件旁的 .parsed/full.md，助手可以阅读。设置 → 课件解析 里填写 MinerU Token 后单文件可达 200 MB / 200 页、每天 1000 页优先额度；不填写时使用免登录轻量模式（10 MB / 20 页以内）。`,
	outline: `大纲即时间轴：把一节课按阶段分成若干章节（格式“起始-结束：内容”，与 Look Tongji Notes skill 的 *_timeline.txt 相同）。在播放器的“大纲”页点“生成大纲”，或让助手生成。章节会显示在进度条上，点击即可跳转。`,
	schedule: `日程页按月历和列表显示作业、考试、活动。助手只在原话里出现明确日期（如“10月20日交”“下周三考试”）时才会标记，每条都带原话和录像时间点，可以在聊天卡片里撤销。也可以在日程页手动添加、勾选完成。`,
	notes: `笔记保存为 Markdown 文件（带 YAML 头），位于 课程库/courses/<课程>/<节次>/notes/。助手整理笔记时以字幕为主，遇到重点和不确定处会查看当时的 PPT、搜索已上传的课件来核对，然后保存，标记为 source: agent。笔记在阅读器里打开：左侧目录、正文里的时间戳/PPT/课件引用点开后在右侧显示原声、当时的 PPT 和课件原文。不能看图的对话模型需要在 设置 → 助手 → 识图模型 里选一个能看图的模型。资料库页面可全文搜索。`,
	models: `设置 → 模型 可添加提供商：内置 40+ 家（OpenAI、Anthropic、DeepSeek、OpenRouter 等，只需填 API Key），或添加 OpenAI/Anthropic 兼容端点（Base URL + 模型 ID）。也可一键导入 Pi CLI（~/.pi/agent）的配置。可选思考强度。`,
	library: `课程库是一个普通文件夹（默认 ~/LookStudio），README.md 说明了结构，任何 AI 工具都能直接阅读。library.db 是可重建的 SQLite 索引。可导出为 Look Tongji Notes skill 的工作区格式（含时间轴大纲与课件）。`,
};

// ---- groups for on-demand loading ----

export const CORE = ["current_context", "find_tools", "read_transcript", "search_library", "suggest_actions"];

export const GROUPS = {
	course: { label: "课程与节次", tools: ["list_courses", "list_lectures", "lecture_info"], words: "课程 节次 课次 老师 列表 哪节 日期 course lecture" },
	notes: {
		label: "笔记",
		tools: ["list_notes", "read_note", "save_note", "lecture_info", "read_timeline"],
		with: ["materials"],
		words: "笔记 整理 保存 总结 复习 讲义 知识点 note",
	},
	schedule: { label: "日程", tools: ["mark_schedule", "list_schedule", "update_schedule"], words: "日程 作业 考试 截止 ddl 活动 提醒 日历 安排 交 schedule homework exam deadline" },
	outline: { label: "时间轴大纲", tools: ["read_timeline", "generate_timeline", "save_timeline"], words: "大纲 时间轴 时间线 章节 目录 结构 outline timeline chapter" },
	materials: {
		label: "PPT 与课件",
		tools: ["view_slides", "list_courseware", "search_courseware", "read_courseware", "view_images"],
		words: "ppt 幻灯片 截图 板书 图片 看图 课件 讲义 pdf 教材 资料 文档 courseware slides image",
	},
	practice: {
		label: "练习题",
		tools: ["create_quiz", "list_quizzes", "read_quiz_results", "lecture_info"],
		with: ["materials"],
		words: "出题 练习 测验 自测 题目 选择题 考考 刷题 错题 quiz test practice",
	},
	help: { label: "应用帮助", tools: ["app_guide"], words: "怎么 如何 功能 设置 帮助 使用 下载 登录 转写 模型 help" },
};

function matchGroups(query, groups = GROUPS) {
	const q = (query ?? "").toLowerCase();
	if (!q.trim()) return [];
	return Object.entries(groups)
		.map(([id, g]) => {
			const terms = `${g.label} ${g.words} ${g.tools.join(" ")}`.toLowerCase().split(/\s+/);
			const score = terms.filter((t) => t && (q.includes(t) || t.includes(q))).length;
			return [id, score];
		})
		.filter(([, s]) => s > 0)
		.sort((a, b) => b[1] - a[1])
		.map(([id]) => id);
}

// Loaded with the notes group (via find_tools), so it costs no context until
// the assistant actually writes notes.
const NOTE_PLAYBOOK = `写课堂笔记的流程（按顺序执行）：
1. 定位：lecture_info 看时长、PPT 时间点、已有大纲/笔记；有大纲就 read_timeline，用它做骨架。
2. 先读字幕：read_transcript 从头按 from_sec 连续分页读完整节课，不能跳段（保存时会检查是否读完）。字幕是笔记的主体依据；已有的笔记最多作参考，不要照搬。边读边记两类位置（带时间）：
   - 重点：定义、定理/公式/推导步骤、方法流程、例题、老师强调（“重点”“要考”“注意”“记住”）、课堂问答、作业与考试安排；
   - 疑点：可能识别错的术语/人名/符号、口述的公式（“dp 等于 rho 乘…”）、指着画面说的话（“看这里”“这个图”“如图”）、含糊或前后矛盾处。
3. 对照 PPT：view_slides 一次传入多个重点/疑点时间（每次 ≤6 个），看当时的 PPT，校正术语、符号、公式、图表。PPT 与字幕冲突时以 PPT 为准；PPT 也看不清的保留疑问。
4. 查课件：list_courseware 有已解析的课件时，用 search_courseware 按关键词（概念名、公式名、例题名）查相关段落，必要时 read_courseware 读上下文、view_images 看插图，补全推导和准确表述。没有课件就跳过。
5. 写作并保存：save_note 新建一篇（务必带 lecture_id 和 course_id，不要传 note_id；只有用户明确要求改写某篇时才覆盖），然后在回复里用两三句话说明覆盖了什么、哪些地方存疑，不要把整篇笔记贴进聊天。

写作要求（适用于各类课程）：
- 只写知识内容，不写“本笔记根据字幕整理”“从 PPT 可以看到”之类的过程描述。
- 先判断课程类型再组织：
  · 理工推导：概念 → 公式/定理 → 推导关键步骤 → 适用条件与物理/几何意义 → 例题与解法；
  · 文史社科：核心论点 → 论据与案例 → 不同观点比较 → 时间线/人物/概念关系；
  · 语言、编程、实验：规则或语法 → 代码/操作步骤（代码块）→ 常见错误 → 练习；
  · 研讨、答疑：问题 → 各方观点 → 老师总结。
- 结构：标题从 ### 开始。有作业/考试/签到/分组安排时，开头写“### 课程提醒”（带明确日期的同时用 mark_schedule 标记）。正文按大纲章节或课堂阶段展开，每个阶段都要覆盖，课堂问答和例题不能漏。结尾写“### 小结”（3–6 条）和“### 自测题”（3–5 道，附简要答案）。
- 详细程度：不看录像也能学懂，每 10 分钟课程大约 300–600 字；推导写出关键中间步骤，不只给结论。
- 每个要点后附时间戳 [mm:ss]。信息量大的 PPT（公式页、图表页、总结页，一般 2–6 张）用 view_slides 给出的写法嵌入；引用课件用 search_courseware 给出的链接。
- 公式一律 LaTeX：行内 $...$，独立公式 $$...$$ 单独成行；公式里不写中文，需要时用 \\text{}。
- 字幕、PPT、课件都无法确认的内容，用“> ⚠️ 存疑：……”单独标出，不要编造。`;

// ---- schedule grounding ----

// A mark needs a concrete date in the original words: absolute dates,
// weekdays with a week reference, or near days. "期末""下周" alone do not count.
const DATE_RE = new RegExp(
	[
		String.raw`\d{4}\s*[-/.年]\s*\d{1,2}\s*[-/.月]\s*\d{1,2}`,
		String.raw`\d{1,2}\s*月\s*(?:\d{1,2}|[一二三四五六七八九十]{1,3})\s*[日号]?`,
		String.raw`(?<!\d)\d{1,2}\s*[/.]\s*\d{1,2}(?!\d)`,
		String.raw`(?:这|本|下下?|下个|下一)?个?(?:周|星期|礼拜)[一二三四五六日天1-7]`,
		String.raw`(?:今|明|后|大后)天|今晚|明晚|明早|明儿`,
		String.raw`(?<![第\d])\d{1,2}\s*[号日](?!\s*[之以]?[内后])`,
		String.raw`\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{1,2}\b`,
		String.raw`\b(?:next|this)\s+(?:mon|tues|wednes|thurs|fri|satur|sun)day\b|\btomorrow\b|\btonight\b`,
	].join("|"),
	"i",
);

const squash = (s) => (s ?? "").toLowerCase().replace(/[\s\p{P}\p{S}]+/gu, "");

const WEEK = ["日", "一", "二", "三", "四", "五", "六"];
const weekday = (iso) => `周${WEEK[new Date(`${iso}T00:00:00`).getDay()]}`;
const dayDiff = (a, b) => Math.round((new Date(`${a}T00:00:00`) - new Date(`${b}T00:00:00`)) / 86400000);
const today = () => new Date().toLocaleDateString("sv-SE");

async function groundQuote(p, conv) {
	const q = squash(p.quote);
	if (q.length < 4) throw new Error("quote 太短：请逐字摘录提到这件事和日期的原话");
	if (!DATE_RE.test(p.quote)) {
		throw new Error("原话里没有明确的日期（如“10月20日”“下周三”“明天”）。只有出现日期时才能标记日程；没有日期就不要标记，必要时在回复里提醒用户。");
	}
	switch (p.source) {
		case "transcript": {
			if (!p.lecture_id || p.t_sec == null) throw new Error("来自录音的标记需要 lecture_id 和 t_sec");
			const from = Math.max(0, p.t_sec - 240) * 1000;
			const segs = await get(`/api/lectures/${enc(p.lecture_id)}/transcript?from_ms=${from}&to_ms=${(p.t_sec + 240) * 1000}`);
			// Find the utterance where the quote starts.
			const joined = segs.map((g) => squash(g.text));
			const all = joined.join("");
			const at = all.indexOf(q);
			if (at < 0) throw new Error(`在 [${clock(p.t_sec * 1000)}] 前后 4 分钟的转写里找不到这段原话。请用 read_transcript 读到原文后逐字摘录。`);
			let pos = 0;
			for (let i = 0; i < segs.length; i++) {
				if (pos + joined[i].length > at) return segs[i].start_ms;
				pos += joined[i].length;
			}
			return p.t_sec * 1000;
		}
		case "chat":
			if (!squash(conv.lastUser).includes(q)) throw new Error("用户这条消息里没有这段原话；只能摘录用户本轮说过的话。");
			return -1;
		case "courseware": {
			if (!p.lecture_id || !p.file) throw new Error("来自课件的标记需要 lecture_id 和 file");
			for (let off = 0, i = 0; i < 20; i++) {
				const r = await get(`/api/lectures/${enc(p.lecture_id)}/courseware/text?path=${enc(p.file)}&offset=${off}&max=20000`);
				if (squash(r.text).includes(q)) return -1;
				if (!r.more) break;
				off = r.next - 200;
			}
			throw new Error("课件解析文本里找不到这段原话。");
		}
		case "note": {
			const n = await get(`/api/notes/${enc(p.note_id ?? "")}`);
			if (!squash(n.body).includes(q)) throw new Error("笔记里找不到这段原话。");
			return -1;
		}
	}
	throw new Error("source 无效");
}

// ---- transcript coverage ----

// Records which parts of a lecture's transcript this conversation has read,
// so a lecture note can only be saved after the whole transcript was read.
function markRead(conv, lectureId, fromMs, toMs, endMs) {
	conv.reads ??= {};
	const r = (conv.reads[lectureId] ??= { spans: [], end: 0 });
	r.spans.push([fromMs, toMs]);
	if (endMs) r.end = Math.max(r.end, endMs);
}

async function unread(conv, lectureId) {
	const r = conv.reads?.[lectureId];
	if (!r) return null;
	if (!r.end) {
		const tail = await get(`/api/lectures/${enc(lectureId)}/transcript?from_ms=${Math.max(0, ...r.spans.map((x) => x[1]))}`);
		r.end = tail.length ? tail.at(-1).end_ms : Math.max(...r.spans.map((x) => x[1]));
	}
	const spans = [...r.spans].sort((a, b) => a[0] - b[0]);
	const gaps = [];
	let at = 0;
	for (const [a, b] of spans) {
		if (a - at > 60_000) gaps.push([at, a]);
		at = Math.max(at, b);
	}
	if (r.end - at > 60_000) gaps.push([at, r.end]);
	const missing = gaps.reduce((n, [a, b]) => n + b - a, 0);
	return { gaps, ratio: r.end ? missing / r.end : 0 };
}

// ---- tool definitions ----

/**
 * @param {object} conv the conversation (see host.mjs)
 * @param {Record<string, {label: string, tools: string[], descriptions: Record<string, string>, playbook: string, words: string}>} [pluginGroups]
 *   groups of the plugins loaded when the conversation opened (plugins.mjs)
 * @param {{tools?: any[], groups?: Record<string, any>, core?: string[]}} [extra]
 *   the bot's tools (operate.mjs, memory.mjs): more groups and core tools
 */
export function createTools(conv, pluginGroups = {}, extra = {}) {
	const own = { ...GROUPS, ...(extra.groups ?? {}) };
	const all = { ...own, ...pluginGroups };
	const core = [...CORE, ...(extra.core ?? [])];
	const plugins = Object.entries(pluginGroups);
	const tools = [
		{
			name: "find_tools",
			label: "加载工具",
			description:
				"Load more tools before using them. Groups: " +
				Object.entries(own)
					.map(([id, g]) => `${id} (${g.label}: ${g.tools.join(", ")})`)
					.join("; ") +
				(plugins.length ? `. Plugin groups: ${plugins.map(([id, g]) => `${id} (${g.label})`).join("; ")}` : "") +
				". Pass groups directly when you know them, or a query in the user's words. Loaded tools are callable from your next step.",
			promptSnippet: `find_tools(groups|query): load tool groups (${Object.keys(own).join(", ")})`,
			parameters: Type.Object({
				groups: Type.Optional(Type.Array(Type.Union(Object.keys(all).map((k) => Type.Literal(k))))),
				query: Type.Optional(Type.String({ description: "What you need to do, e.g. 标记作业截止日期" })),
			}),
			execute: async (_id, { groups = [], query }) => {
				let ids = [...new Set([...groups, ...matchGroups(query, all)])].filter((id) => all[id]);
				ids = [...new Set(ids.flatMap((id) => [id, ...(all[id]?.with ?? [])]))];
				if (!ids.length) return text(`没有匹配的工具组。可选：${Object.entries(all).map(([id, g]) => `${id}（${g.label}）`).join("、")}`);
				const names = [...new Set(ids.flatMap((id) => all[id].tools))];
				conv.load(names);
				const describe = (n) => tools.find((x) => x.name === n)?.description ?? plugins.find(([, g]) => n in g.descriptions)?.[1].descriptions[n] ?? "";
				const lines = names.map((n) => `- ${n}: ${describe(n).split(/(?<=\.)\s/)[0]}`);
				const playbook = [ids.includes("notes") && NOTE_PLAYBOOK, ids.includes("practice") && QUIZ_PLAYBOOK, ...ids.map((id) => pluginGroups[id]?.playbook)]
					.filter(Boolean)
					.map((p) => `\n\n${p}`)
					.join("");
				return text(`已加载 ${ids.map((id) => all[id].label).join("、")}，下一步即可调用：\n${lines.join("\n")}${playbook}`, { loaded: names });
			},
		},
		{
			name: "app_guide",
			label: "功能介绍",
			description: "Look up how Look Studio features work. Use when the user asks how to do something in the app.",
			parameters: Type.Object({
				topic: Type.Union(Object.keys(GUIDE).map((k) => Type.Literal(k)), { description: "Feature area" }),
			}),
			execute: async (_id, { topic }) => text(GUIDE[topic] ?? GUIDE.overview),
		},
		{
			name: "current_context",
			label: "当前页面",
			description: "Get what the user is looking at right now in the app (course, lecture, playback position).",
			parameters: Type.Object({}),
			execute: async () => text(json(conv.context ?? { screen: "unknown" })),
		},
		{
			name: "list_courses",
			label: "课程列表",
			description: "List the user's enrolled courses with ids, teachers, terms and how many lectures are stored locally.",
			parameters: Type.Object({
				query: Type.Optional(Type.String({ description: "Filter by title/teacher substring" })),
			}),
			execute: async (_id, { query }) => {
				let cs = await get("/api/courses");
				if (query) cs = cs.filter((c) => `${c.title}${c.alias}${c.teacher}`.includes(query));
				const rows = cs.map((c) => `- ${c.alias || c.title} (id ${c.id}) · ${c.teacher} · ${c.term} · 本地 ${c.local_lectures} 节`);
				return text(rows.join("\n") || "没有匹配的课程", { count: cs.length });
			},
		},
		{
			name: "list_lectures",
			label: "节次列表",
			description: "List lectures of a course with dates and which artifacts (video/slides/transcript/courseware) exist locally.",
			parameters: Type.Object({ course_id: Type.String() }),
			execute: async (_id, { course_id }) => {
				const r = await get(`/api/courses/${enc(course_id)}/lectures`);
				const rows = r.lectures.map(
					(l) =>
						`- ${l.title} (id ${l.id}) · ${l.date} · ${l.lecturer}${l.has_playback ? "" : " · 无回放"}` +
						(l.assets.length ? ` · 本地: ${l.assets.join("/")}` : "") +
						(l.segments ? ` · 转写 ${l.segments} 句` : ""),
				);
				return text(`${r.course.title}\n${rows.join("\n")}`);
			},
		},
		{
			name: "read_transcript",
			label: "读取转写",
			description:
				"Read a lecture transcript with [mm:ss] timestamps. Long transcripts are paged: pass from_sec to continue. Returns at most max_chars characters (≤ 15000).",
			parameters: Type.Object({
				lecture_id: Type.String(),
				from_sec: Type.Optional(Type.Number({ default: 0 })),
				to_sec: Type.Optional(Type.Number()),
				max_chars: Type.Optional(Type.Number({ default: 15000 })),
			}),
			execute: async (_id, { lecture_id, from_sec = 0, to_sec, max_chars = 15000 }) => {
				// Below the harness cap, so the continuation hint is never cut off.
				max_chars = Math.min(Math.max(max_chars, 1000), 15000);
				const q = new URLSearchParams({ from_ms: String(Math.round(from_sec * 1000)) });
				if (to_sec) q.set("to_ms", String(Math.round(to_sec * 1000)));
				const segs = await get(`/api/lectures/${enc(lecture_id)}/transcript?${q}`);
				if (!segs.length) return text("这节课还没有转写稿。可以建议用户在节次页点击“转写”。");
				let out = "";
				let lastEnd = from_sec * 1000;
				let para = [];
				let paraStart = segs[0].start_ms;
				let full = false;
				for (const g of segs) {
					para.push(g.text);
					if (g.end_ms - paraStart >= 45000) {
						const line = `[${clock(paraStart)}] ${para.join(" ")}\n`;
						if (out.length + line.length > max_chars) {
							full = true;
							break;
						}
						out += line;
						lastEnd = g.end_ms;
						para = [];
						paraStart = g.end_ms;
					}
				}
				// The trailing short paragraph, unless the page filled up first.
				if (!full && para.length) {
					const line = `[${clock(paraStart)}] ${para.join(" ")}\n`;
					if (out.length + line.length <= max_chars) {
						out += line;
						lastEnd = segs.at(-1).end_ms;
					}
				}
				const more = lastEnd < segs.at(-1).end_ms - 1000;
				markRead(conv, lecture_id, from_sec * 1000, lastEnd, to_sec ? 0 : segs.at(-1).end_ms);
				return text(out + (more ? `\n…(未完，可用 from_sec=${Math.floor(lastEnd / 1000)} 继续)` : ""), { more });
			},
		},
		{
			name: "lecture_info",
			label: "节次详情",
			description: "Get a lecture's metadata (date, room, duration), local files, slide times, bookmarks, notes and whether it has an outline.",
			parameters: Type.Object({ lecture_id: Type.String() }),
			execute: async (_id, { lecture_id }) => {
				const r = await get(`/api/lectures/${enc(lecture_id)}`);
				let slides = [];
				try {
					slides = await get(`/api/lectures/${enc(lecture_id)}/slides`);
				} catch {}
				const info = {
					course: r.course.title,
					course_id: r.course.id,
					lecture: r.lecture.title,
					date: `${r.lecture.date} ${r.lecture.date ? weekday(r.lecture.date) : ""}`,
					lecturer: r.lecture.lecturer,
					room: r.lecture.room,
					duration: clock((r.lecture.duration_s || 0) * 1000),
					local_files: r.assets.map((a) => `${a.kind}: ${a.path}`),
					transcript_segments: r.lecture.segments,
					outline_chapters: (r.timeline ?? []).length,
					slide_times: slides.filter((s) => s.is_key).map((s) => clock(s.t_sec * 1000)).join(", "),
					bookmarks: r.bookmarks.map((b) => `${clock(b.t_ms)} ${b.label}`),
					notes: r.notes.map((n) => `${n.title} (id ${n.id})`),
				};
				return text(json(info));
			},
		},
		{
			name: "search_library",
			label: "全文搜索",
			description: "Full-text search across all transcripts and notes. Returns lecture ids and timestamps.",
			parameters: Type.Object({
				query: Type.String({ description: "Words to find; 3+ characters works best for Chinese" }),
				course_id: Type.Optional(Type.String()),
			}),
			execute: async (_id, { query, course_id }) => {
				const q = new URLSearchParams({ q: query, limit: "30" });
				if (course_id) q.set("course_id", course_id);
				const hits = await get(`/api/search?${q}`);
				const rows = hits.map((h) =>
					h.kind === "note"
						? `- 笔记 ${h.note_id} · ${h.course_title} ${h.lecture}: ${h.snippet}`
						: `- ${h.course_title} · ${h.lecture} (lecture ${h.lecture_id}) [${clock(h.start_ms)}]: ${h.snippet}`,
				);
				return text(rows.join("\n") || "没有找到", { count: hits.length });
			},
		},
		{
			name: "list_notes",
			label: "笔记列表",
			description: "List notes, optionally for a course or lecture.",
			parameters: Type.Object({ course_id: Type.Optional(Type.String()), lecture_id: Type.Optional(Type.String()) }),
			execute: async (_id, { course_id = "", lecture_id = "" }) => {
				const ns = await get(`/api/notes?course_id=${enc(course_id)}&lecture_id=${enc(lecture_id)}`);
				return text(ns.map((n) => `- ${n.title} (id ${n.id}, ${n.source})`).join("\n") || "暂无笔记");
			},
		},
		{
			name: "read_note",
			label: "读取笔记",
			description: "Read a note's Markdown body.",
			parameters: Type.Object({ note_id: Type.String() }),
			execute: async (_id, { note_id }) => {
				const n = await get(`/api/notes/${enc(note_id)}`);
				return text(`# ${n.title}\n\n${n.body}`);
			},
		},
		{
			name: "save_note",
			label: "保存笔记",
			description:
				"Create or update a Markdown note in the user's library. Only when the user asks to save. Use [mm:ss] timestamps when referring to the lecture (they become clickable seek links; use [mm:ss](look://lecture/<id>?t=<sec>) for another lecture). Pass note_id to update an existing note.",
			parameters: Type.Object({
				title: Type.String(),
				body: Type.String({ description: "Markdown content" }),
				lecture_id: Type.Optional(Type.String()),
				course_id: Type.Optional(Type.String()),
				note_id: Type.Optional(Type.String({ description: "Only to rewrite a note the user explicitly asked you to change; omit to create a new note" })),
				replace: Type.Optional(Type.Boolean({ description: "Required with note_id: confirms the user asked to overwrite that note" })),
				partial: Type.Optional(Type.Boolean({ description: "The user asked for notes on only part of the lecture" })),
			}),
			execute: async (_id, p) => {
				if (p.note_id) {
					const old = await get(`/api/notes/${enc(p.note_id)}`);
					if (old.source !== "agent") throw new Error("这是用户自己写的笔记，不能覆盖。请不传 note_id，另存为一篇新笔记。");
					if (!p.replace) throw new Error("覆盖已有笔记需要用户明确要求修改这一篇（并传 replace: true）。否则不要传 note_id，新建一篇笔记。");
				}
				if (p.lecture_id && !p.partial) {
					const u = await unread(conv, p.lecture_id);
					if (u && u.ratio > 0.1) {
						const list = u.gaps.map(([a, b]) => `[${clock(a)}]–[${clock(b)}]`).join("、");
						throw new Error(`字幕还有 ${list} 没有读（约 ${Math.round(u.ratio * 100)}%）。整节课的笔记必须以完整字幕为依据：先用 read_transcript 读完这些部分，补充笔记后再保存。只整理部分内容时传 partial: true。`);
					}
				}
				const n = await api("PUT", "/api/notes", {
					id: p.note_id ?? "",
					title: p.title,
					body: p.body,
					lecture_id: p.lecture_id ?? "",
					course_id: p.course_id ?? "",
					source: "agent",
				});
				return text(`已保存笔记「${n.title}」(id ${n.id})，文件：${n.path}`, { note: n });
			},
		},
		{
			name: "mark_schedule",
			label: "标记日程",
			description:
				"Add a dated item (homework, exam, activity, deadline) to the user's schedule. ONLY when the source states a concrete date or day (e.g. 10月20日, 下周三, 明天); never guess a date. " +
				"quote must be the exact original words mentioning the item and its date, copied from the transcript (source=transcript, with lecture_id and t_sec of that passage), the user's current message (source=chat), a parsed courseware file (source=courseware, with lecture_id and file) or a note (source=note, with note_id). " +
				"Resolve relative dates against the lecture date (transcript/courseware) or today (chat) and pass due_date as YYYY-MM-DD. Each item shows up as a card the user can undo.",
			parameters: Type.Object({
				kind: Type.Union(["homework", "exam", "activity", "deadline", "task"].map((k) => Type.Literal(k))),
				title: Type.String({ description: "Short title, ≤ 30 chars, e.g. 实验二报告" }),
				due_date: Type.String({ description: "YYYY-MM-DD" }),
				due_time: Type.Optional(Type.String({ description: "HH:MM when stated" })),
				quote: Type.String({ description: "Exact original words containing the date" }),
				source: Type.Union(["transcript", "chat", "courseware", "note"].map((k) => Type.Literal(k))),
				lecture_id: Type.Optional(Type.String()),
				t_sec: Type.Optional(Type.Number({ description: "Where the passage is in the recording" })),
				file: Type.Optional(Type.String({ description: "Courseware file path or name" })),
				note_id: Type.Optional(Type.String()),
				detail: Type.Optional(Type.String({ description: "Requirements worth remembering, one or two lines" })),
			}),
			execute: async (_id, p) => {
				if (!/^\d{4}-\d{2}-\d{2}$/.test(p.due_date)) throw new Error("due_date 必须是 YYYY-MM-DD");
				const tMs = await groundQuote(p, conv);
				let anchor = today();
				let courseId = "";
				if (p.lecture_id) {
					const r = await get(`/api/lectures/${enc(p.lecture_id)}`);
					courseId = r.lecture.course_id;
					if (p.source === "transcript" || p.source === "courseware") anchor = r.lecture.date || anchor;
				}
				const d = dayDiff(p.due_date, anchor);
				if (d < -1 || d > 200) {
					throw new Error(`due_date ${p.due_date} 与参照日期 ${anchor}（${weekday(anchor)}）相差 ${d} 天，不合理。相对日期要以${p.source === "chat" ? "今天" : "这节课的日期"}为准重新换算。`);
				}
				const r = await api("POST", "/api/schedule", {
					kind: p.kind,
					title: p.title.trim().slice(0, 40),
					detail: p.detail ?? "",
					due_date: p.due_date,
					due_time: p.due_time ?? "",
					course_id: courseId,
					lecture_id: p.lecture_id ?? "",
					t_ms: tMs,
					quote: p.quote.trim().slice(0, 200),
					source: "agent",
				});
				const it = r.item;
				const when = `${it.due_date}（${weekday(it.due_date)}${it.due_time ? " " + it.due_time : ""}）`;
				return text(
					r.duplicate ? `日程里已有「${it.title}」${when}，没有重复添加。` : `已加入日程「${it.title}」${when}，参照日期 ${anchor}（${weekday(anchor)}）。`,
					{ schedule: it, duplicate: r.duplicate },
				);
			},
		},
		{
			name: "list_schedule",
			label: "查看日程",
			description: "List schedule items (homework, exams, activities) in a date range; open items only unless include_done.",
			parameters: Type.Object({
				from: Type.Optional(Type.String({ description: "YYYY-MM-DD, default today" })),
				to: Type.Optional(Type.String()),
				course_id: Type.Optional(Type.String()),
				include_done: Type.Optional(Type.Boolean()),
			}),
			execute: async (_id, { from, to, course_id, include_done }) => {
				const q = new URLSearchParams({ from: from ?? today() });
				if (to) q.set("to", to);
				if (course_id) q.set("course_id", course_id);
				if (!include_done) q.set("open", "1");
				const items = await get(`/api/schedule?${q}`);
				const rows = items.map(
					(i) =>
						`- ${i.due_date} ${weekday(i.due_date)}${i.due_time ? " " + i.due_time : ""} · ${i.title} [${i.kind}${i.done ? " 已完成" : ""}] · ${i.course_title || "无课程"} (id ${i.id}, ${i.source})`,
				);
				return text(`今天是 ${today()} ${weekday(today())}\n${rows.join("\n") || "这段时间没有日程"}`, { count: items.length });
			},
		},
		{
			name: "update_schedule",
			label: "修改日程",
			description: "Change a schedule item (title, date, done) or remove one you marked by mistake (remove: true; only items with source agent).",
			parameters: Type.Object({
				id: Type.String(),
				title: Type.Optional(Type.String()),
				due_date: Type.Optional(Type.String()),
				due_time: Type.Optional(Type.String()),
				done: Type.Optional(Type.Boolean()),
				remove: Type.Optional(Type.Boolean()),
			}),
			execute: async (_id, { id, remove, ...patch }) => {
				const items = await get(`/api/schedule`);
				const it = items.find((x) => x.id === id);
				if (!it) throw new Error("没有这条日程");
				if (remove) {
					if (it.source !== "agent") throw new Error("这条是用户自己添加的，不能删除；请让用户在日程页处理。");
					await api("DELETE", `/api/schedule/${enc(id)}`);
					return text(`已删除「${it.title}」`, { removed: id });
				}
				const r = await api("PATCH", `/api/schedule/${enc(id)}`, patch);
				return text(`已更新「${r.title}」${r.due_date} ${weekday(r.due_date)}${r.done ? "（已完成）" : ""}`, { schedule: r });
			},
		},
		{
			name: "read_timeline",
			label: "读取大纲",
			description: "Read a lecture's outline (timeline chapters) if it has one.",
			parameters: Type.Object({ lecture_id: Type.String() }),
			execute: async (_id, { lecture_id }) => {
				const chs = await get(`/api/lectures/${enc(lecture_id)}/timeline`);
				if (!chs.length) return text("这节课还没有大纲。可以用 generate_timeline 生成。");
				return text(chs.map((c) => `[${clock(c.start_ms)}]–[${clock(c.end_ms)}] ${c.title}`).join("\n"));
			},
		},
		{
			name: "generate_timeline",
			label: "生成大纲",
			description:
				"Generate and save a lecture's outline from its transcript in one step (a separate model call reads the whole transcript, so you do not need to). Overwrites any existing outline.",
			parameters: Type.Object({ lecture_id: Type.String() }),
			execute: async (_id, { lecture_id }, signal) => {
				const chs = await generateTimeline(conv.pipeline, lecture_id, signal);
				return text(chs.map((c) => `[${clock(c.start_ms)}]–[${clock(c.end_ms)}] ${c.title}`).join("\n"), { timeline: chs, lecture_id });
			},
		},
		{
			name: "save_timeline",
			label: "保存大纲",
			description:
				"Save an outline you wrote or edited. text: one chapter per line, 'MM:SS-MM:SS：阶段内容' (minutes keep counting past 60, e.g. 75:20); chapters are made contiguous from 00:00 to the end.",
			parameters: Type.Object({ lecture_id: Type.String(), text: Type.String() }),
			execute: async (_id, { lecture_id, text: t }) => {
				const chs = await api("PUT", `/api/lectures/${enc(lecture_id)}/timeline`, { text: t });
				return text(`已保存 ${chs.length} 个章节`, { timeline: chs, lecture_id });
			},
		},
		{
			name: "list_courseware",
			label: "课件列表",
			description: "List courseware files the user uploaded for a lecture and whether MinerU has parsed them.",
			parameters: Type.Object({ lecture_id: Type.String() }),
			execute: async (_id, { lecture_id }) => {
				const fs = await get(`/api/lectures/${enc(lecture_id)}/courseware`);
				const rows = fs.map((f) => `- ${f.name} (path ${f.path}) · ${f.parse?.state === "done" ? `已解析 ${f.parse.pages || "?"} 页` : f.parse?.state === "failed" ? "解析失败" : "未解析"}`);
				return text(rows.join("\n") || "这节课还没有课件。课件需要用户自己上传（播放器 → 资料 → 课件）。");
			},
		},
		{
			name: "read_courseware",
			label: "阅读课件",
			description: "Read the parsed Markdown of a courseware file, paged by offset (characters); search_courseware gives offsets of relevant passages.",
			parameters: Type.Object({
				lecture_id: Type.String(),
				file: Type.String({ description: "path or name from list_courseware" }),
				offset: Type.Optional(Type.Number()),
			}),
			execute: async (_id, { lecture_id, file, offset = 0 }) => {
				const r = await get(`/api/lectures/${enc(lecture_id)}/courseware/text?path=${enc(file)}&offset=${offset}&max=12000`);
				const note = `（图片路径相对于 ${r.dir}/，view_images 时写成 ${r.dir}/images/xxx.jpg）\n\n`;
				return text(note + r.text + (r.more ? `\n…(未完，共 ${r.total} 字，可用 offset=${r.next} 继续)` : ""), { more: r.more });
			},
		},
		{
			name: "view_slides",
			label: "查看 PPT",
			description:
				"Look at the slides on screen at given moments of a lecture (the key slide showing at each time; up to 6 per call). Use it to check terms, symbols, formulas and figures the transcript is unsure about. Returns the images, or their transcription when the chat model cannot see images, plus Markdown to embed each slide in a note.",
			parameters: Type.Object({
				lecture_id: Type.String(),
				at_sec: Type.Array(Type.Number(), { minItems: 1, maxItems: 6, description: "Moments (seconds) to look at" }),
			}),
			execute: async (_id, { lecture_id, at_sec }, signal) => {
				const all = (await get(`/api/lectures/${enc(lecture_id)}/slides`)).sort((a, b) => a.t_sec - b.t_sec);
				if (!all.length) return text("这节课没有 PPT 截图（老师没有投屏，或平台没有生成）。请只依据字幕和课件。");
				const key = all.some((x) => x.is_key) ? all.filter((x) => x.is_key) : all;
				const picked = new Map();
				for (const t of at_sec.slice(0, 6)) {
					let hit = key[0];
					for (const x of key) {
						if (x.t_sec <= t + 5) hit = x;
						else break;
					}
					picked.set(hit.idx, hit);
				}
				const list = [...picked.values()].sort((a, b) => a.t_sec - b.t_sec);
				const seen = await seeImages(
					conv.pipeline,
					list.map((x) => ({ label: `PPT 第 ${x.idx} 张（[${clock(x.t_sec * 1000)}] 起显示）`, path: `/api/lectures/${enc(lecture_id)}/slides/${x.idx}/image` })),
					signal,
				);
				const embed = list.map((x) => `![PPT ${x.idx} · ${clock(x.t_sec * 1000)}](look://slide/${lecture_id}/${x.idx})`).join("\n");
				return {
					content: [...seen.content, { type: "text", text: `\n在笔记里嵌入这些页时使用：\n${embed}` }],
					details: { lecture_id, slides: list.map((x) => x.idx), mode: seen.mode },
				};
			},
		},
		{
			name: "search_courseware",
			label: "搜索课件",
			description:
				"Search the parsed courseware of a lecture (scope=lecture) or of its whole course (scope=course) for passages: definitions, formulas, examples. Returns snippets with page numbers, nearby figures, and a link to cite each passage in a note.",
			parameters: Type.Object({
				lecture_id: Type.String(),
				query: Type.String({ description: "Keywords separated by spaces, e.g. 欧拉平衡方程 压强" }),
				scope: Type.Optional(Type.Union([Type.Literal("lecture"), Type.Literal("course")], { default: "course" })),
			}),
			execute: async (_id, { lecture_id, query, scope = "course" }) => {
				const hits = await get(`/api/lectures/${enc(lecture_id)}/courseware/search?q=${enc(query)}&scope=${scope}&limit=8`);
				if (!hits.length) {
					const fs = await get(`/api/lectures/${enc(lecture_id)}/courseware`);
					return text(fs.length ? `课件里没有找到“${query}”，可以换个说法或更短的关键词。` : "这节课还没有课件（需要用户在 播放器 → 资料 → 课件 上传）。请只依据字幕和 PPT。");
				}
				const rows = hits.map((h) => {
					const where = `${h.name}${h.page ? ` 第 ${h.page} 页` : ""}`;
					const cite = `[课件·${where}](look://courseware/${h.lecture_id}?file=${enc(h.file)}&q=${enc(query)})`;
					const imgs = h.images?.length ? `\n插图（可用 view_images 查看，嵌入写 ![说明](look://file/路径)）：${h.images.join("，")}` : "";
					return `### ${where}（lecture ${h.lecture_id}，file ${h.file}，offset ${h.offset}）\n${h.snippet}${imgs}\n引用写法：${cite}`;
				});
				return text(rows.join("\n\n"), { count: hits.length });
			},
		},
		{
			name: "view_images",
			label: "查看插图",
			description: "Look at courseware figures by their library paths (from search_courseware or read_courseware; up to 6 per call).",
			parameters: Type.Object({ paths: Type.Array(Type.String(), { minItems: 1, maxItems: 6 }) }),
			execute: async (_id, { paths }, signal) => {
				const clean = paths.map((x) => x.replace(/^look:\/\/file\//, "").replace(/^\/+/, ""));
				const seen = await seeImages(
					conv.pipeline,
					clean.map((x) => ({ label: `插图 ${x.split("/").pop()}`, path: `/files/${x.split("/").map(enc).join("/")}` })),
					signal,
				);
				const embed = clean.map((x) => `![插图](look://file/${x})`).join("\n");
				return { content: [...seen.content, { type: "text", text: `\n在笔记里嵌入时使用：\n${embed}` }], details: { mode: seen.mode } };
			},
		},
		{
			name: "create_quiz",
			label: "生成练习",
			description:
				"Save a multiple-choice practice set grounded in the lecture material; it shows in chat as a card the user can start. Read the transcript first (whole lecture unless partial), then write every question with one correct answer, a rationale for every option and a ref to its source. " +
				"Refs: look://lecture/<id>?t=<sec> (a transcript position you read), look://slide/<id>/<idx>, or a courseware link from search_courseware.",
			parameters: Type.Object({
				title: Type.String({ description: "Short, e.g. 第 3 讲 傅里叶变换 · 自测" }),
				lecture_id: Type.Optional(Type.String()),
				course_id: Type.Optional(Type.String({ description: "Only for a course-wide set without lecture_id" })),
				difficulty: Type.Union(["easy", "medium", "hard"].map((k) => Type.Literal(k))),
				partial: Type.Optional(Type.Boolean({ description: "The set covers only part of the lecture, or the lecture has no transcript" })),
				questions: Type.Array(
					Type.Object({
						stem: Type.String({ description: "Markdown, LaTeX allowed" }),
						options: Type.Array(Type.Object({ text: Type.String(), rationale: Type.String({ description: "Why this option is right or wrong" }) }), {
							minItems: 2,
							maxItems: 6,
						}),
						answer: Type.Integer({ description: "Index of the correct option, from 0" }),
						hint: Type.Optional(Type.String({ description: "Points the way without giving the answer" })),
						topic: Type.Optional(Type.String({ description: "2–6 字的知识点" })),
						ref: Type.String({ description: "look:// link to the evidence" }),
					}),
					{ minItems: 1, maxItems: 30 },
				),
			}),
			execute: async (_id, p) => {
				const coverage = p.lecture_id ? await unread(conv, p.lecture_id) : null;
				const problem = checkQuiz(p, conv.reads, coverage);
				if (problem) throw new Error(problem);
				const { partial: _, ...body } = p;
				const q = await api("POST", "/api/quizzes", { ...body, source: "agent" });
				return text(`已保存练习「${q.title}」${q.count} 题（id ${q.id}）。聊天里会显示练习卡片，用户点“开始练习”即可作答。`, {
					quiz: { id: q.id, title: q.title, count: q.count, difficulty: q.difficulty, lecture_id: q.lecture_id, lecture_title: q.lecture_title ?? "" },
				});
			},
		},
		{
			name: "list_quizzes",
			label: "练习列表",
			description: "List saved practice sets with their best and last scores, optionally for a course or lecture.",
			parameters: Type.Object({ course_id: Type.Optional(Type.String()), lecture_id: Type.Optional(Type.String()) }),
			execute: async (_id, { course_id = "", lecture_id = "" }) => {
				const qs = await get(`/api/quizzes?course_id=${enc(course_id)}&lecture_id=${enc(lecture_id)}`);
				const score = (s) => (s ? `${s.correct}/${s.total}` : "未作答");
				const rows = qs.map((q) => `- ${q.title} · ${q.count} 题 · ${q.difficulty} · 最好 ${score(q.best)} · 最近 ${score(q.last)} · 已练 ${q.attempts} 次 (id ${q.id})`);
				return text(rows.join("\n") || "还没有练习");
			},
		},
		{
			name: "read_quiz_results",
			label: "查看作答",
			description: "Read the student's latest attempt at a practice set: score, and each missed question with their choice and the correct answer. Use before explaining mistakes or writing a follow-up set on them.",
			parameters: Type.Object({ quiz_id: Type.String() }),
			execute: async (_id, { quiz_id }) => {
				const q = await get(`/api/quizzes/${enc(quiz_id)}`);
				if (!q.last?.answers) return text(`「${q.title}」还没有作答记录。`);
				const L = (i) => String.fromCharCode(65 + i);
				const missed = q.questions
					.map((x, i) => ({ x, i, a: q.last.answers[i] }))
					.filter(({ x, a }) => a !== x.answer)
					.map(({ x, i, a }) => {
						const chose = a < 0 ? "未作答" : `选了 ${L(a)}「${x.options[a].text}」`;
						return `第 ${i + 1} 题${x.topic ? `［${x.topic}］` : ""} ${x.stem}\n  ${chose}；正确 ${L(x.answer)}「${x.options[x.answer].text}」 出处 ${x.ref ?? "无"}`;
					});
				const head = `「${q.title}」最近一次 ${q.last.correct}/${q.last.total}，最好 ${q.best.correct}/${q.best.total}，共练 ${q.attempts} 次。`;
				return text(missed.length ? `${head}\n做错的题：\n${missed.join("\n")}` : `${head}\n最近一次全部答对。`, { quiz_id });
			},
		},
		{
			name: "suggest_actions",
			label: "操作建议",
			description:
				"Offer clickable buttons in the chat. The user decides whether to click. kinds: seek (jump the player to seconds), open_lecture, open_course, open_note, open_schedule, download (prefill the download sheet; never starts by itself).",
			parameters: Type.Object({
				actions: Type.Array(
					Type.Object({
						kind: Type.Union(["seek", "open_lecture", "open_course", "open_note", "open_schedule", "download"].map((k) => Type.Literal(k))),
						label: Type.String({ description: "Short button text" }),
						lecture_id: Type.Optional(Type.String()),
						course_id: Type.Optional(Type.String()),
						note_id: Type.Optional(Type.String()),
						seconds: Type.Optional(Type.Number()),
						kinds: Type.Optional(Type.Array(Type.String())),
					}),
					{ maxItems: 6 },
				),
			}),
			execute: async (_id, { actions }) => text(`已向用户展示 ${actions.length} 个操作按钮。`, { actions }),
		},
	];
	tools.push(...(extra.tools ?? []));
	return tools.map((t) => guard(conv, { ...t, exposure: core.includes(t.name) ? undefined : "deferred" }));
}

// ---- harness ----

export const TURN_TOOL_BUDGET = 24;

/** Tools that change the library, by the task permission (TASK_WRITES) allowing them. */
export const WRITE_TOOLS = {
	save_note: "notes",
	save_timeline: "notes",
	generate_timeline: "notes",
	mark_schedule: "schedule",
	update_schedule: "schedule",
	create_quiz: "quiz",
};
const MAX_RESULT_CHARS = 16000;

// guard enforces the per-turn call budget, a scheduled run's allowed writes
// (conv.writes; unset in chats) and caps result size.
export function guard(conv, tool) {
	const run = tool.execute;
	return {
		...tool,
		execute: async (id, params, signal, ...rest) => {
			const kind = WRITE_TOOLS[tool.name];
			if (conv.writes && kind && !conv.writes.includes(kind)) {
				throw new Error(`这个定时任务没有被允许「${TASK_WRITES[kind]}」，${tool.name} 已拒绝。不要再尝试写入，把结果写在总结里。`);
			}
			conv.calls = (conv.calls ?? 0) + 1;
			if (conv.calls > TURN_TOOL_BUDGET) {
				throw new Error(`本轮已调用 ${TURN_TOOL_BUDGET} 次工具，已达上限。请基于已获得的信息直接回答，并告诉用户还缺什么。`);
			}
			const r = await run(id, params, signal, ...rest);
			for (const c of r.content ?? []) {
				if (c.type === "text" && c.text.length > MAX_RESULT_CHARS) {
					c.text = `${c.text.slice(0, MAX_RESULT_CHARS)}\n…(结果过长，已截断；请缩小范围或分页读取)`;
				}
			}
			return r;
		},
	};
}
