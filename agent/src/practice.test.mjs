import assert from "node:assert/strict";
import { test } from "node:test";
import { checkQuiz, parseRef } from "./practice.mjs";

const q = (ref, answer = 0) => ({ stem: "s", options: [{ text: "a" }, { text: "b" }], answer, ref });
const reads = { L1: { spans: [[0, 600_000]], end: 600_000 } };
const full = { gaps: [], ratio: 0 };

test("parseRef reads the three link kinds", () => {
	assert.deepEqual(parseRef("look://lecture/L1?t=125"), { kind: "time", lecture: "L1", sec: 125 });
	assert.deepEqual(parseRef("look://slide/L1/3"), { kind: "slide", lecture: "L1", idx: 3 });
	assert.equal(parseRef("look://courseware/L1?file=a.pdf&q=x").file, "a.pdf");
	for (const bad of ["", "https://x", "look://lecture/L1", "look://slide/L1/x", "look://courseware/L1", "look://lecture/%ZZ?t=10"]) assert.equal(parseRef(bad), null, bad);
});

test("checkQuiz requires reading and real sources", () => {
	const ok = { lecture_id: "L1", questions: [q("look://lecture/L1?t=120", 0), q("look://slide/L1/2", 1)] };
	assert.equal(checkQuiz(ok, reads, full), "");
	assert.match(checkQuiz(ok, {}, null), /还没有读/);
	assert.match(checkQuiz(ok, reads, { gaps: [[600_000, 1_200_000]], ratio: 0.5 }), /\[10:00\]–\[20:00\]/);
	assert.equal(checkQuiz({ ...ok, partial: true }, reads, null), "");
	assert.match(checkQuiz({ ...ok, questions: [q("look://lecture/L1?t=900")] }, reads, full), /不在本次读过的字幕范围内/);
	assert.match(checkQuiz({ ...ok, questions: [q("look://slide/L2/1")] }, reads, full), /另一节课/);
	assert.match(checkQuiz({ ...ok, questions: [q("")] }, reads, full), /ref 无效/);
	assert.match(checkQuiz({ ...ok, questions: [q("look://lecture/%ZZ?t=10")] }, reads, full), /ref 无效/);
	const same = { lecture_id: "L1", questions: [1, 2, 3, 4].map((i) => ({ ...q(`look://slide/L1/${i}`), stem: `s${i}` })) };
	assert.match(checkQuiz(same, reads, full), /同一个位置/);
});
