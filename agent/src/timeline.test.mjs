import assert from "node:assert/strict";
import { test } from "node:test";
import { timelinePlan } from "./timeline.mjs";

test("concise outlines cut a 95-minute lecture into its main stages", () => {
	const p = timelinePlan(95, "concise");
	assert.deepEqual([p.lo, p.hi, p.minLen], [5, 10, 6]);
});

test("detailed outlines allow about twice as many chapters", () => {
	const p = timelinePlan(95, "detailed");
	assert.deepEqual([p.lo, p.hi, p.minLen], [12, 24, 2]);
	assert.ok(p.lo > timelinePlan(95).hi);
});

test("short lectures still get a usable range", () => {
	for (const d of ["concise", "detailed"]) {
		const p = timelinePlan(20, d);
		assert.ok(p.lo >= 3 && p.hi > p.lo, d);
	}
});
