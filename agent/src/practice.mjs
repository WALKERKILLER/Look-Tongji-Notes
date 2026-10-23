// Quiz grounding checks for create_quiz (docs/specs/0002-tutor-quiz-cards.md).
// Pure functions so they can be tested without lookd.

// Loaded with the practice group, so it costs no context until the assistant
// writes a quiz.
export const QUIZ_PLAYBOOK = `出题流程（按顺序执行）：
1. 定位：lecture_info 看时长、PPT、课件；用户指定了侧重点就围绕它出题。
2. 读材料：read_transcript 从头连续读完整节课（只针对部分内容出题时，读相关段落并传 partial: true）；拿不准的术语、公式用 view_slides 看当时的 PPT，有课件时用 search_courseware 核对。
3. 出题：create_quiz 一次保存整组题目，然后用一两句话说明覆盖了哪些知识点，不要把题目贴进聊天。

出题要求：
- 每题只考一个知识点，题干自足、不依赖“上面那题”；考理解和应用，不考“老师第几分钟说了什么”。
- 4 个选项为宜，只有一个正确答案；干扰项来自常见误解、相近概念或计算中易犯的错误，长度和语气与正确答案相近；不用“以上都对/都不对”。
- 正确答案的位置要分散。
- 每个选项都写 rationale：正确项说明为什么对，错误项指出错在哪里（一两句）。
- 每题给 ref 出处：录像时间 look://lecture/<id>?t=<秒>（必须是读过的字幕位置）、PPT look://slide/<id>/<序号> 或课件链接（search_courseware 给出的写法）。
- hint 提示思路但不泄露答案；topic 用 2–6 个字概括知识点，用于统计错题。
- 公式用 LaTeX（$...$），题干和选项都可以用 Markdown。
- 难度：easy 考定义和直接结论；medium 考理解、比较和一步推理；hard 考多步推导、综合应用和易混淆点。`;

// parseRef understands the look:// links the app opens.
export function parseRef(ref) {
	let u;
	try {
		u = new URL(ref);
	} catch {
		return null;
	}
	if (u.protocol !== "look:") return null;
	let seg;
	try {
		seg = u.pathname.split("/").filter(Boolean).map(decodeURIComponent);
	} catch {
		return null; // malformed escapes such as %ZZ
	}
	switch (u.hostname) {
		case "lecture": {
			const t = u.searchParams.has("t") ? Number(u.searchParams.get("t")) : NaN;
			return seg[0] && Number.isFinite(t) && t >= 0 ? { kind: "time", lecture: seg[0], sec: t } : null;
		}
		case "slide": {
			const idx = Number(seg[1]);
			return seg[0] && Number.isInteger(idx) && idx >= 0 ? { kind: "slide", lecture: seg[0], idx } : null;
		}
		case "courseware":
			return seg[0] && u.searchParams.get("file") ? { kind: "courseware", lecture: seg[0], file: u.searchParams.get("file") } : null;
	}
	return null;
}

const clock = (sec) => `${String(Math.floor(sec / 60)).padStart(2, "0")}:${String(Math.floor(sec % 60)).padStart(2, "0")}`;

/**
 * Returns an error message, or "" when the set may be saved.
 * reads: conv.reads (transcript spans read in this conversation, ms).
 * coverage: result of unread() for the lecture, or null when never read.
 */
export function checkQuiz({ questions, lecture_id, partial }, reads, coverage) {
	if (lecture_id && !partial) {
		if (!coverage) return "还没有读这节课的字幕。整节课出题前先用 read_transcript 从头读完；没有转写稿或只针对部分内容出题时传 partial: true，并用 PPT 或课件作为出处。";
		if (coverage.ratio > 0.1) {
			const list = coverage.gaps.map(([a, b]) => `[${clock(a / 1000)}]–[${clock(b / 1000)}]`).join("、");
			return `字幕还有 ${list} 没有读（约 ${Math.round(coverage.ratio * 100)}%）。先读完再出题；只针对部分内容出题时传 partial: true。`;
		}
	}
	for (const [i, q] of questions.entries()) {
		const n = i + 1;
		const r = parseRef(q.ref ?? "");
		if (!r) return `第 ${n} 题的 ref 无效。出处写成 look://lecture/<id>?t=<秒>、look://slide/<id>/<序号> 或 search_courseware 给出的课件链接。`;
		if (lecture_id && r.lecture !== lecture_id) return `第 ${n} 题的出处指向另一节课（${r.lecture}），应引用本节 ${lecture_id} 的材料。`;
		if (r.kind === "time") {
			const spans = reads?.[r.lecture]?.spans ?? [];
			const ms = r.sec * 1000;
			if (!spans.some(([a, b]) => ms >= a - 90_000 && ms <= b + 90_000)) {
				return `第 ${n} 题引用的 [${clock(r.sec)}] 不在本次读过的字幕范围内。先用 read_transcript 读到那里，确认后再引用。`;
			}
		}
	}
	if (questions.length >= 4 && new Set(questions.map((q) => q.answer)).size === 1) {
		return "所有题的正确答案都在同一个位置。请打乱选项顺序，让正确答案分散。";
	}
	return "";
}
