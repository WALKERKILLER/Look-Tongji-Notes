import test from "node:test";
import assert from "node:assert/strict";
import { reviewChunks, validateReviewOutput, filterReviewOutput, TranscriptReviewer } from "./transcript-review.mjs";

const material = { id: "ocr", title: "课堂 OCR", text: "TLB 是地址转换缓存，正确术语。" };
const segment = (idx, text = "页表缓冲缓存地址转换。") => ({ idx, start_ms: idx * 1000, end_ms: idx * 1000 + 1000, text });
const suggestion = (segment = 0) => ({
	segment,
	original: "页表缓冲",
	guess: "TLB",
	reason: "疑似术语误识别，需听录音核对",
	evidence_source: "ocr",
	evidence_quote: "TLB 是地址转换缓存",
});

test("all multibyte segments are targets exactly once with context at both boundaries", () => {
	const segs = Array.from({ length: 401 }, (_, i) => segment(i, "地址转换".repeat(35)));
	const chunks = reviewChunks(segs);
	assert.deepEqual(
		chunks.flatMap((c) => c.targets),
		segs,
	);
	assert.ok(chunks.every((c) => c.targets.reduce((n, s) => n + [...s.text].length, 0) <= 6000));
	assert.ok(chunks[1].context[0].idx < chunks[1].targets[0].idx);
	assert.equal(chunks.at(-1).targets.at(-1).idx, 400);
});

test("only unique target spans with literal source evidence are accepted", () => {
	const chunk = { targets: [segment(0)], context: [segment(0), segment(1)] };
	assert.equal(validateReviewOutput(JSON.stringify([suggestion()]), chunk, [material])[0].evidence, "课堂 OCR：TLB 是地址转换缓存");
	for (const bad of [
		{ ...suggestion(), segment: 1 },
		{ ...suggestion(), original: "并不存在" },
		{ ...suggestion(), evidence_quote: "编造的引用" },
		{ ...suggestion(), evidence_source: "other" },
		{ ...suggestion(), guess: "新\n内容" },
	]) {
		assert.throws(() => validateReviewOutput(JSON.stringify([bad]), chunk, [material]));
	}
	assert.throws(() => validateReviewOutput(JSON.stringify([suggestion(), suggestion()]), chunk, [material]));
});

function harness(complete) {
	let saved = { state: "none", run_id: "", suggestions: [] };
	const checkpoints = [],
		ledger = [];
	const info = {
		course: "操作系统",
		lecture: "第一节",
		date: "2026-09-10",
		fingerprint: "abc",
		segments: Array.from({ length: 200 }, (_, i) => segment(i, "页表缓冲" + "地址转换".repeat(20))),
		materials: [material],
	};
	const call = async (method, path, body) => {
		if (path.endsWith("/context")) return structuredClone(info);
		if (method === "PUT") {
			saved = structuredClone(body);
			checkpoints.push(saved);
			return structuredClone(saved);
		}
		return structuredClone(saved);
	};
	const pipeline = {
		currentModel: async () => ({ provider: "test", id: "local" }),
		usage: { record: (e) => ledger.push(e) },
		runtime: {
			completeSimple:
				complete ??
				(async (_m, input) => {
					const data = JSON.parse(input.messages[0].content[0].text);
					return { content: [{ type: "text", text: JSON.stringify([suggestion(data.targets[0].idx)]) }], stopReason: "stop" };
				}),
		},
	};
	return { reviewer: new TranscriptReviewer(pipeline, call), info, checkpoints, ledger, read: () => saved };
}
async function finish(r) {
	await r.jobs.get("one")?.done;
}

test("a complete review checkpoints every batch; restart reads saved suggestions", async () => {
	const h = harness();
	await h.reviewer.start("one");
	await finish(h.reviewer);
	const out = h.read();
	assert.equal(out.state, "completed");
	assert.equal(out.completed, out.total);
	assert.ok(out.total > 1);
	assert.equal(out.suggestions.length, out.total);
	assert.equal(h.ledger.length, out.total);
	assert.equal(h.ledger[0].purpose, "transcript-review");
	assert.equal((await h.reviewer.status("one")).state, "completed");
	h.read().state = "running";
	assert.equal((await h.reviewer.status("one")).state, "interrupted");
});

test("duplicate start does not create another model call; cancel aborts current call", async () => {
	let calls = 0;
	const h = harness(async (_m, _i, { signal }) => {
		calls++;
		await new Promise((resolve, reject) => {
			if (signal.aborted) return reject(signal.reason);
			signal.addEventListener("abort", () => reject(signal.reason), { once: true });
		});
	});
	await h.reviewer.start("one");
	await h.reviewer.start("one");
	assert.equal(calls, 1);
	const cancelled = await h.reviewer.cancel("one");
	assert.equal(cancelled.state, "cancelled");
	assert.equal(calls, 1);
	assert.equal(h.reviewer.jobs.size, 0);
});

test("malformed model JSON is retried once, then remains an incomplete error", async () => {
	let n = 0;
	const h = harness(async () => {
		n++;
		return { content: [{ type: "text", text: "{broken-json" }] };
	});
	await h.reviewer.start("one");
	await finish(h.reviewer);
	assert.equal(n, 2);
	assert.equal(h.read().state, "error");
	assert.equal(h.read().completed, 0);
});

test("missing model fails before creating a task or changing sidecar", async () => {
	const h = harness();
	h.reviewer.pipeline.currentModel = async () => null;
	await assert.rejects(h.reviewer.start("one"), /模型/);
	assert.equal(h.checkpoints.length, 0);
	assert.equal(h.reviewer.jobs.size, 0);
});

test("unsupported guesses are filtered while grounded neighbours are retained", () => {
	const chunk = { targets: [segment(0)], context: [segment(0)] };
	const result = filterReviewOutput(JSON.stringify([suggestion(), { ...suggestion(), original: "虚构" }]), chunk, [material]);
	assert.equal(result.suggestions.length, 1);
	assert.equal(result.rejected, 1);
});
test("retry resumes a compatible partial checkpoint without paying for finished batches", async () => {
	const h = harness();
	await h.reviewer.start("one");
	await finish(h.reviewer);
	const total = h.read().total;
	h.read().state = "error";
	h.read().completed = 1;
	h.read().suggestions = h.read().suggestions.slice(0, 1);
	h.ledger.length = 0;
	await h.reviewer.start("one");
	await finish(h.reviewer);
	assert.equal(h.read().state, "completed");
	assert.equal(h.ledger.length, total - 1);
	assert.equal(h.read().suggestions.length, total);
});
