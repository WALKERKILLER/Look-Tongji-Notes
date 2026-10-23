// Request helpers for the host's HTTP API.

export const MAX_BODY = 1 << 20; // 1 MiB: chat messages, settings and tasks are far smaller
export const BODY_TIMEOUT_MS = 30_000;

export const httpError = (status, message) => Object.assign(new Error(message), { status });

/**
 * Reads a JSON request body of at most `max` bytes within `timeoutMs`. Reading
 * stops at the first byte over the limit (413) or at the deadline (408); such
 * errors carry `drop`, and replyError then closes the connection instead of
 * waiting for the rest of the body.
 */
export function readJson(req, max = MAX_BODY, timeoutMs = BODY_TIMEOUT_MS) {
	return new Promise((resolve, reject) => {
		const chunks = [];
		let size = 0;
		let timer;
		const settle = (err, value) => {
			clearTimeout(timer);
			req.off("data", onData);
			req.off("end", onEnd);
			req.off("error", onError);
			if (err) {
				req.pause?.();
				reject(err);
			} else {
				resolve(value);
			}
		};
		const drop = (status, message) => settle(Object.assign(httpError(status, message), { drop: true }));
		const onData = (c) => {
			size += c.length;
			if (size > max) drop(413, `请求体超过 ${max} 字节`);
			else chunks.push(c);
		};
		const onEnd = () => {
			const raw = Buffer.concat(chunks).toString("utf8");
			if (!raw) return settle(null, {});
			try {
				settle(null, JSON.parse(raw));
			} catch {
				settle(httpError(400, "请求体不是 JSON"));
			}
		};
		const onError = (e) => settle(e);
		if (Number(req.headers?.["content-length"]) > max) return drop(413, `请求体超过 ${max} 字节`);
		timer = setTimeout(() => drop(408, "读取请求体超时"), timeoutMs);
		req.on("data", onData);
		req.on("end", onEnd);
		req.on("error", onError);
	});
}

/** Sends an error as JSON; a `drop` error also closes the connection. */
export function replyError(req, res, e) {
	if (res.headersSent) return res.end();
	const headers = { "Content-Type": "application/json; charset=utf-8" };
	if (e?.drop) {
		headers.Connection = "close";
		res.on("finish", () => req.destroy());
	}
	res.writeHead(e?.status ?? 500, headers);
	res.end(JSON.stringify({ error: String(e?.message ?? e) }));
}
