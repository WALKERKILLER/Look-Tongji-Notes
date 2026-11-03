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
export async function fetchBytes(path, { maxBytes = Infinity, signal } = {}) {
	const res = await fetch(BASE + path, { headers: { Authorization: `Bearer ${TOKEN}` }, signal: AbortSignal.any([signal ?? new AbortController().signal, AbortSignal.timeout(60_000)]) });
	if (!res.ok) {
		let msg = `HTTP ${res.status}`;
		try {
			msg = (await res.json()).error ?? msg;
		} catch {}
		throw new Error(msg);
	}
	const chunks = [];
	let size = 0;
	for await (const chunk of res.body) {
		size += chunk.length;
		if (size > maxBytes) throw new Error("选中图像超过大小限制，请缩小选区");
		chunks.push(chunk);
	}
	return { bytes: Buffer.concat(chunks, size), mimeType: (res.headers.get("content-type") ?? "image/jpeg").split(";")[0] };
}


// Library catalog and non-destructive transcript review sidecars (including
// completed/total checkpoints and a rejected-candidate count).
export const libraryCatalog = (courseId) => get('/api/library/catalog'+(courseId ? '?course_id='+encodeURIComponent(courseId) : ''));
// Human UI operations; intentionally absent from general assistant tools.
export const createLocalCourse = (title, teacher = '') => api('POST', '/api/local-courses', {title, teacher});
export async function importLocalVideo(course, name, bytes) {
	const response = await fetch(`${BASE}/api/courses/${encodeURIComponent(course)}/local-videos?name=${encodeURIComponent(name)}`, {
		method: 'POST', headers: {Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/octet-stream'}, body: bytes, signal: AbortSignal.timeout(600_000),
	});
	const result = await response.json();
	if (!response.ok) throw new Error(result.error ?? `HTTP ${response.status}`);
	return result;
}
export const readStudyConversation = (lecture,id) => get(`${studyCanvasPath(lecture)}/conversations/${encodeURIComponent(id)}`);
export const saveStudyConversation = (lecture,id,data) => api('PUT',`${studyCanvasPath(lecture)}/conversations/${encodeURIComponent(id)}`,data);
export const importStudyMaterial = (lecture,path) => api('POST',`${studyCanvasPath(lecture)}/material`,{path});
// The human UI saves documents; scoped canvas tools only read bound sources (spec 0021).
export const studyCanvasPath = (id) => `/api/lectures/${encodeURIComponent(id)}/study-canvas`;
export const readStudyCanvas = (id) => get(studyCanvasPath(id));
export const readStudyContext = (id, selection) => api('POST',`${studyCanvasPath(id)}/context`,selection);
// Dedicated, selection-scoped canvas runs; these helpers do not extend general chat tools.
export const canvasRunPath = (id = '') => `/agent/canvas/runs${id ? `/${encodeURIComponent(id)}` : ''}`;
// Preserve objects[].pdf_column and page-bound ink in whole-document saves.
export const saveStudyCanvas = (id, document) => api('PUT', studyCanvasPath(id), document);
export const importStudyCourseware = (id, path) => api('POST', `${studyCanvasPath(id)}/assets?path=${encodeURIComponent(path)}`, {});
export async function importStudyAsset(id, name, bytes) {
	const response = await fetch(`${BASE}${studyCanvasPath(id)}/assets?name=${encodeURIComponent(name)}`, {
		method: 'POST', headers: { Authorization: `Bearer ${TOKEN}`, 'Content-Type': 'application/octet-stream' }, body: bytes, signal: AbortSignal.timeout(180_000),
	});
	const value = await response.json();
	if (!response.ok) throw new Error(value.error ?? `HTTP ${response.status}`);
	return value;
}
export const transcriptReviewPath = (id) => `/api/lectures/${encodeURIComponent(id)}/transcript-review`;
export const readTranscriptReview = (id) => get(transcriptReviewPath(id));
export const saveTranscriptReview = (id, review) => api('PUT',transcriptReviewPath(id),review);
export const dismissTranscriptSuggestion = (id, suggestionId) => api('PATCH',transcriptReviewPath(id),{suggestion_id:suggestionId});

export const readStudyPDFPage = (id,source,page) => get(`${studyCanvasPath(id)}/pdf-page?source=${encodeURIComponent(source)}&page=${page}`);

export const prepareStudyMedia = (id,query) => api('POST',`${studyCanvasPath(id)}/media`,query);
export const readStudyMediaTask = (id,task) => get(`${studyCanvasPath(id)}/media/${encodeURIComponent(task)}`);
export const cancelStudyMediaTask = (id,task) => api('DELETE',`${studyCanvasPath(id)}/media/${encodeURIComponent(task)}`);

export const studyMediaFilePath = (id,object) => `${studyCanvasPath(id)}/media-file/${encodeURIComponent(object)}`;

// Folder sync configuration is user-operated; assistant access is read-only.
export async function folderSyncStatus() { return api("GET", "/api/sync"); }
