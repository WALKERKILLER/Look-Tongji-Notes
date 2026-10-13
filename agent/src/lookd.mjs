// Minimal client for the lookd daemon API (the agent's only data source).
const BASE = process.env.LOOKD_URL ?? "http://127.0.0.1:0";
const TOKEN = process.env.LOOKD_TOKEN ?? "";

export async function api(method, path, body) {
	const res = await fetch(BASE + path, {
		method,
		headers: { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" },
		body: body === undefined ? undefined : JSON.stringify(body),
		signal: AbortSignal.timeout(60_000),
	});
	const text = await res.text();
	let data;
	try {
		data = text ? JSON.parse(text) : null;
	} catch {
		data = text;
	}
	if (!res.ok) throw new Error(data?.error ?? `lookd ${method} ${path}: HTTP ${res.status}`);
	return data;
}

export const get = (path) => api("GET", path);

/** Fetch binary content (an image) from lookd. */
export async function fetchBytes(path) {
	const res = await fetch(BASE + path, { headers: { Authorization: `Bearer ${TOKEN}` }, signal: AbortSignal.timeout(60_000) });
	if (!res.ok) {
		let msg = `HTTP ${res.status}`;
		try {
			msg = (await res.json()).error ?? msg;
		} catch {}
		throw new Error(msg);
	}
	return { bytes: Buffer.from(await res.arrayBuffer()), mimeType: (res.headers.get("content-type") ?? "image/jpeg").split(";")[0] };
}
