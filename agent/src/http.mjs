// Request helpers for the host's HTTP API.

export const MAX_BODY = 1 << 20; // 1 MiB: chat messages, settings and tasks are far smaller

export const httpError = (status, message) => Object.assign(new Error(message), { status });

/**
 * Reads a JSON request body of at most `max` bytes. A larger body is drained
 * without being kept and rejected with 413, so a caller cannot exhaust memory.
 */
export async function readJson(req, max = MAX_BODY) {
	if (Number(req.headers?.["content-length"]) > max) {
		req.resume?.();
		throw httpError(413, `请求体超过 ${max} 字节`);
	}
	const chunks = [];
	let size = 0;
	for await (const c of req) {
		size += c.length;
		if (size <= max) chunks.push(c);
	}
	if (size > max) throw httpError(413, `请求体超过 ${max} 字节`);
	const raw = Buffer.concat(chunks).toString("utf8");
	if (!raw) return {};
	try {
		return JSON.parse(raw);
	} catch {
		throw httpError(400, "请求体不是 JSON");
	}
}
