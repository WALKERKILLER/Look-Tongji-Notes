// Timeline outlines (时间轴大纲) as in the Look-Tongji-Notes skill: one model
// call over the (uniformly sampled) transcript, then lookd normalizes the
// chapters so they tile the lecture from 00:00 to its end.
import { api, get } from "./lookd.mjs";
import { entryFrom } from "./usage.mjs";

const enc = encodeURIComponent;
const MAX_CHARS = 28000;

const mmss = (ms) => {
	const s = Math.floor(ms / 1000);
	return `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
};

/** Transcript as ~30 s paragraphs "[MM:SS] …", sampled evenly to fit. */
function transcriptDigest(segs) {
	const paras = [];
	let cur = null;
	for (const g of segs) {
		if (!cur || g.end_ms - cur.start >= 30000) {
			cur = { start: g.start_ms, text: [] };
			paras.push(cur);
		}
		cur.text.push(g.text.trim());
	}
	let lines = paras.map((p) => `[${mmss(p.start)}] ${p.text.join(" ")}`);
	const total = lines.reduce((n, l) => n + l.length + 1, 0);
	if (total > MAX_CHARS) {
		// Keep an even spread across the whole lecture, including both ends.
		const keep = Math.max(20, Math.floor((lines.length * MAX_CHARS) / total));
		const step = lines.length / keep;
		const idx = new Set([0, lines.length - 1]);
		for (let i = 0; i < keep; i++) idx.add(Math.floor(i * step));
		lines = [...idx].sort((a, b) => a - b).map((i) => lines[i]);
	}
	return lines.join("\n");
}

function prompt(info, durMs, slideTimes) {
	const mins = durMs / 60000;
	const lo = Math.max(3, Math.round(mins / 12));
	const hi = Math.max(lo + 2, Math.min(18, Math.round(mins / 5)));
	return `你是大学课程助教，为课堂录像写“时间轴大纲”，帮助学生快速定位。

课程：${info.course}
节次：${info.lecture}（${info.date}）
时长：${mmss(durMs)}
${slideTimes ? `PPT 换页时间（可作为分段参考）：${slideTimes}\n` : ""}
输出要求：
1. 每行一个时间段，格式严格为 \`MM:SS-MM:SS：阶段内容\`；超过 60 分钟继续累加分钟（如 75:20），不要写小时。
2. 第一行从 00:00 开始；相邻时间段首尾相接；最后一段结束于 ${mmss(durMs)}。
3. 按课堂实际阶段划分，共 ${lo}-${hi} 段，每段至少 2 分钟。
4. 阶段内容用简体中文，8-24 字，写清这段讲的具体知识点或活动（例如“傅里叶变换的卷积定理推导”），不要写“老师讲解”“继续讲课”这类空话。
5. 课前准备、点名、课间休息、布置作业等如实单独成段。
6. 只输出大纲本身，不要标题、编号、解释或代码块。

转写稿（[MM:SS] 为该段开始时间，可能经过均匀抽样）：`;
}

/**
 * Generates and saves a lecture outline. Returns the saved chapters.
 * @param {import("./models.mjs").ModelPipeline} pipeline
 */
export async function generateTimeline(pipeline, lectureId, signal) {
	const r = await get(`/api/lectures/${enc(lectureId)}`);
	const segs = await get(`/api/lectures/${enc(lectureId)}/transcript`);
	if (!segs.length) throw new Error("这节课还没有文字稿，先转写再生成大纲");
	const durMs = Math.max((r.lecture.duration_s || 0) * 1000, segs.at(-1).end_ms);
	let slideTimes = "";
	try {
		const sl = await get(`/api/lectures/${enc(lectureId)}/slides`);
		slideTimes = sl.filter((s) => s.is_key).map((s) => mmss(s.t_sec * 1000)).slice(0, 80).join(", ");
	} catch {}
	const model = await pipeline.currentModel();
	if (!model) throw new Error("还没有可用的模型。请在 设置 → 模型 中添加 API Key。");
	const sys = prompt({ course: r.course.title, lecture: r.lecture.title, date: r.lecture.date }, durMs, slideTimes);
	const body = transcriptDigest(segs);
	const deadline = AbortSignal.timeout(180_000);
	const sig = signal ? AbortSignal.any([signal, deadline]) : deadline;
	let text = "";
	for (let attempt = 0; attempt < 2; attempt++) {
		const res = await pipeline.runtime.completeSimple(
			model,
			{
				systemPrompt: sys,
				messages: [
					{
						role: "user",
						content: [{ type: "text", text: attempt ? `${body}\n\n上一次输出无法解析。请严格按“MM:SS-MM:SS：阶段内容”逐行输出。` : body }],
						timestamp: Date.now(),
					},
				],
			},
			{ signal: sig, maxTokens: 4000 },
		);
		pipeline.usage?.record(entryFrom(res, { purpose: "timeline" }));
		if (res.stopReason === "error") throw new Error(res.errorMessage ?? "模型请求失败");
		text = res.content.filter((c) => c.type === "text").map((c) => c.text).join("");
		const lines = text.split("\n").filter((l) => /\d{1,3}:\d{2}\s*[-–—~～]\s*\d{1,3}:\d{2}/.test(l));
		if (lines.length >= 2) break;
	}
	return api("PUT", `/api/lectures/${enc(lectureId)}/timeline`, { text });
}
