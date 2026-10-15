import assert from "node:assert/strict";
import { Readable } from "node:stream";
import { test } from "node:test";
import { readJson } from "./http.mjs";

const req = (chunks, headers = {}) => Object.assign(Readable.from(chunks.map((c) => Buffer.from(c))), { headers });

test("request bodies are parsed within the size limit", async () => {
	assert.deepEqual(await readJson(req(['{"a":', "1}"])), { a: 1 });
	assert.deepEqual(await readJson(req([])), {});
	await assert.rejects(readJson(req(["{oops"])), { status: 400 });
	// Too large, whether declared up front or only found while reading.
	await assert.rejects(readJson(req(["x"], { "content-length": "2000000" })), { status: 413 });
	await assert.rejects(readJson(req(["a".repeat(600), "b".repeat(600)]), 1000), { status: 413 });
});
