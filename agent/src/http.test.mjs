import assert from "node:assert/strict";
import { request, createServer } from "node:http";
import { Readable } from "node:stream";
import { test } from "node:test";
import { readJson, replyError } from "./http.mjs";

const req = (chunks, headers = {}) => Object.assign(Readable.from(chunks.map((c) => Buffer.from(c))), { headers });

test("request bodies are parsed within the size limit", async () => {
	assert.deepEqual(await readJson(req(['{"a":', "1}"])), { a: 1 });
	assert.deepEqual(await readJson(req([])), {});
	await assert.rejects(readJson(req(["{oops"])), { status: 400 });
	// Too large, whether declared up front or only found while reading.
	await assert.rejects(readJson(req(["x"], { "content-length": "2000000" })), { status: 413, drop: true });
	await assert.rejects(readJson(req(["a".repeat(600), "b".repeat(600)]), 1000), { status: 413, drop: true });
});

test("reading stops at the limit and at the deadline without waiting for the end", async () => {
	const endless = () =>
		Object.assign(
			new Readable({
				read() {
					setTimeout(() => this.push(Buffer.alloc(100)), 1);
				},
			}),
			{ headers: {} },
		);
	const big = endless();
	await assert.rejects(readJson(big, 1000, 5000), { status: 413 });
	big.destroy();
	const slow = Object.assign(new Readable({ read() {} }), { headers: {} });
	slow.push("{");
	await assert.rejects(readJson(slow, 1000, 50), { status: 408, drop: true });
	slow.destroy();
});

test("an oversized chunked upload gets 413 and a closed connection while still sending", async (t) => {
	const server = createServer(async (rq, rs) => {
		try {
			await readJson(rq, 1000);
			rs.end("{}");
		} catch (e) {
			replyError(rq, rs, e);
		}
	});
	await new Promise((r) => server.listen(0, "127.0.0.1", r));
	t.after(() => server.close());
	const res = await new Promise((resolve, reject) => {
		const rq = request({ port: server.address().port, method: "POST", headers: { "Transfer-Encoding": "chunked" } }, resolve);
		rq.on("error", () => {}); // the server hangs up on the rest of the body
		const timer = setInterval(() => rq.write("x".repeat(500)), 5);
		rq.on("close", () => clearInterval(timer));
		setTimeout(() => reject(new Error("no early response")), 3000).unref();
	});
	assert.equal(res.statusCode, 413);
	assert.equal(res.headers.connection, "close");
	res.resume();
	await new Promise((r) => res.on("close", r));
});
