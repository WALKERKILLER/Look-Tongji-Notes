// The bot's memory: Markdown files it reads in every conversation and edits
// when told to remember, plus during consolidation. File layout, limits and
// the content guard: docs/specs/0007-resident-bot-and-course-agents.md
// Source: RikkaHub "记忆改为按文件组织的 Markdown 记忆库" — https://github.com/rikkahub/rikkahub/pull/2130
// Derived: profile files injected in full and the rest as an index, split
// read/write/str_replace/append tools, hash-checked writes, a sensitive
// number guard (design only; no code taken).
import { createHash } from "node:crypto";
import { chmod, mkdir, readdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { Type } from "typebox";

export const MAX_FILE = 16 * 1024;
export const MAX_FILES = 200;
export const MAX_TOTAL = 1024 * 1024;
export const MAX_PINNED = 8 * 1024;
const MAX_INDEX_LINES = 100;
const PINNED = ["profile.md", "preferences.md"];
const KINDS = ["routines", "courses", "notes"];
const PATH = /^(?:profile|preferences)\.md$|^(?:routines|courses|notes)\/[a-z0-9][a-z0-9_-]{0,63}\.md$/;

const bad = (message, status = 400) => Object.assign(new Error(message), { status });

export const hashOf = (text) => createHash("sha256").update(text).digest("hex").slice(0, 12);

export function checkPath(path) {
	if (typeof path !== "string" || !PATH.test(path)) {
		throw bad(`记忆文件路径无效：${String(path).slice(0, 80)}。可用 profile.md、preferences.md、routines/<名>.md、courses/<课程id>.md、notes/<名>.md（名称用小写字母、数字、- 和 _）`);
	}
	return path;
}

// ---- guard ----

const ID_WEIGHTS = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2];
const validId = (s) => s.slice(0, 17).split("").reduce((sum, d, i) => sum + Number(d) * ID_WEIGHTS[i], 0) % 11 === "10X98765432".indexOf(s[17].toUpperCase());

function luhn(digits) {
	let sum = 0;
	for (let i = 0; i < digits.length; i++) {
		let d = Number(digits[digits.length - 1 - i]);
		if (i % 2 === 1) d = d * 2 > 9 ? d * 2 - 9 : d * 2;
		sum += d;
	}
	return sum % 10 === 0;
}

/** The kind of sensitive data in text, or null. Links into the library are skipped. */
export function sensitiveKind(text) {
	const t = String(text).replace(/look:\/\/\S+/g, " ");
	for (const m of t.matchAll(/(?<![\dA-Za-z])\d{17}[\dXx](?![\dA-Za-z])/g)) if (validId(m[0])) return "身份证号";
	for (const m of t.matchAll(/(?<!\d)[3-6](?:[ -]?\d){14,18}(?!\d)/g)) {
		const d = m[0].replace(/[ -]/g, "");
		if (d.length >= 15 && d.length <= 19 && luhn(d)) return "银行卡号";
	}
	if (/(?<![\d/=_-])1[3-9]\d{9}(?!\d)/.test(t)) return "手机号";
	if (/\b(?:sk-[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})\b/.test(t)) return "密钥";
	if (/(?:密码|口令|password|passwd)\s*(?:是|为|[:：=])\s*\S+/i.test(t)) return "密码";
	return null;
}

function guard(text) {
	const kind = sensitiveKind(text);
	if (kind) throw bad(`记忆里不能保存${kind}，这次写入已拒绝。去掉这类信息后再写。`);
}

// ---- front matter ----

export function frontMatter(content) {
	const m = /^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(content);
	if (!m) return {};
	const out = {};
	for (const line of m[1].split(/\r?\n/)) {
		const kv = /^(title|description|when)\s*:\s*(.*)$/.exec(line.trim());
		if (kv) out[kv[1]] = kv[2].replace(/^["']|["']$/g, "").slice(0, 120);
	}
	return out;
}

// ---- store ----

export class MemoryStore {
	constructor(dir) {
		this.dir = dir;
		this.tail = Promise.resolve();
	}

	serial(fn) {
		const p = this.tail.then(fn);
		this.tail = p.catch(() => {});
		return p;
	}

	async init() {
		await mkdir(this.dir, { recursive: true, mode: 0o700 });
		await chmod(this.dir, 0o700).catch(() => {});
	}

	/** Every file with its index fields, pinned first, then routines, then by path. */
	async list() {
		const out = [];
		const visit = async (rel) => {
			let ents = [];
			try {
				ents = await readdir(join(this.dir, rel), { withFileTypes: true });
			} catch {
				return;
			}
			for (const e of ents) {
				const path = rel ? `${rel}/${e.name}` : e.name;
				if (e.isDirectory() && !rel && KINDS.includes(e.name)) await visit(e.name);
				else if (e.isFile() && PATH.test(path)) {
					const content = await readFile(join(this.dir, path), "utf8");
					const st = await stat(join(this.dir, path));
					const fm = frontMatter(content);
					out.push({ path, title: fm.title ?? "", description: fm.description ?? "", when: fm.when ?? "", bytes: Buffer.byteLength(content), updated: st.mtimeMs, hash: hashOf(content) });
				}
			}
		};
		await visit("");
		const rank = (p) => (PINNED.includes(p) ? PINNED.indexOf(p) : p.startsWith("routines/") ? 2 : 3);
		return out.sort((a, b) => rank(a.path) - rank(b.path) || a.path.localeCompare(b.path));
	}

	async read(path) {
		checkPath(path);
		try {
			const content = await readFile(join(this.dir, path), "utf8");
			const st = await stat(join(this.dir, path));
			return { path, content, hash: hashOf(content), updated: st.mtimeMs };
		} catch (e) {
			if (e.code === "ENOENT") throw bad(`没有记忆文件 ${path}`, 404);
			throw e;
		}
	}

	async current(path) {
		try {
			return await readFile(join(this.dir, path), "utf8");
		} catch (e) {
			if (e.code === "ENOENT") return null;
			throw e;
		}
	}

	conflict(path, content) {
		return Object.assign(bad(`${path} 已被修改（当前版本 ${hashOf(content)}），请基于下面的最新内容重新写入：\n${content}`, 409), {
			current: { path, content, hash: hashOf(content) },
		});
	}

	async save(path, content, old) {
		if (Buffer.byteLength(content) > MAX_FILE) throw bad(`单个记忆文件最多 ${MAX_FILE / 1024} KB，请精简或拆分`);
		guard(content);
		const files = await this.list();
		if (old === null && files.length >= MAX_FILES) throw bad(`记忆文件最多 ${MAX_FILES} 个，请先合并或删除一些`);
		const total = files.reduce((n, f) => n + (f.path === path ? 0 : f.bytes), 0) + Buffer.byteLength(content);
		if (total > MAX_TOTAL) throw bad(`记忆总量最多 ${MAX_TOTAL / 1024} KB，请先精简`);
		const abs = join(this.dir, path);
		await mkdir(dirname(abs), { recursive: true, mode: 0o700 });
		const tmp = `${abs}.tmp`;
		await writeFile(tmp, content, { mode: 0o600 });
		await rename(tmp, abs);
		return { path, hash: hashOf(content), action: old === null ? "created" : "updated" };
	}

	/** Creates or replaces a file; replacing needs the hash the writer read. */
	write(path, content, baseHash) {
		checkPath(path);
		return this.serial(async () => {
			const old = await this.current(path);
			if (old !== null && baseHash !== hashOf(old)) throw this.conflict(path, old);
			return this.save(path, String(content ?? ""), old);
		});
	}

	/** Replaces the one occurrence of oldText. */
	edit(path, oldText, newText, baseHash) {
		checkPath(path);
		return this.serial(async () => {
			const old = await this.current(path);
			if (old === null) throw bad(`没有记忆文件 ${path}`, 404);
			if (baseHash !== undefined && baseHash !== hashOf(old)) throw this.conflict(path, old);
			const n = oldText ? old.split(oldText).length - 1 : 0;
			if (n !== 1) throw bad(n === 0 ? `${path} 里没有找到要替换的原文` : `原文在 ${path} 里出现了 ${n} 次，请多带一些上下文`);
			return this.save(path, old.replace(oldText, () => String(newText ?? "")), old);
		});
	}

	append(path, text) {
		checkPath(path);
		return this.serial(async () => {
			const old = await this.current(path);
			const base = old ?? "";
			const sep = base && !base.endsWith("\n") ? "\n" : "";
			const r = await this.save(path, `${base}${sep}${String(text ?? "").trim()}\n`, old);
			return { ...r, action: old === null ? "created" : "appended" };
		});
	}

	remove(path) {
		checkPath(path);
		return this.serial(async () => {
			if ((await this.current(path)) === null) throw bad(`没有记忆文件 ${path}`, 404);
			await rm(join(this.dir, path));
			return { path, action: "deleted" };
		});
	}

	/**
	 * The memory section of a system prompt: profile.md and preferences.md in
	 * full (MAX_PINNED together, cut at a line), then an index of the rest
	 * unless pinnedOnly.
	 */
	async prompt({ pinnedOnly = false } = {}) {
		const files = await this.list();
		let pinned = "";
		for (const p of PINNED) {
			const f = files.find((x) => x.path === p);
			if (!f) continue;
			const content = await readFile(join(this.dir, p), "utf8");
			pinned += `<memory path="${p}">\n${content.trim()}\n</memory>\n`;
		}
		if (Buffer.byteLength(pinned) > MAX_PINNED) {
			const lines = [];
			let n = 0;
			for (const l of pinned.split("\n")) {
				n += Buffer.byteLength(l) + 1;
				if (n > MAX_PINNED) break;
				lines.push(l);
			}
			pinned = `${lines.join("\n")}\n…(其余部分用 memory_read 读取)\n`;
		}
		const rest = pinnedOnly ? [] : files.filter((f) => !PINNED.includes(f.path)).slice(0, MAX_INDEX_LINES);
		const index = rest.map((f) => `- ${f.path}${f.title ? ` · ${f.title}` : ""}${f.description ? ` — ${f.description}` : ""}${f.when ? `（适用：${f.when}）` : ""} · ${new Date(f.updated).toLocaleDateString("sv-SE")}`);
		if (!pinned && !index.length) return "";
		return [pinned.trim(), index.length ? `其他记忆文件（需要时用 memory_read 读取）：\n${index.join("\n")}` : ""].filter(Boolean).join("\n\n");
	}
}

// ---- tools ----

const text = (t, details = {}) => ({ content: [{ type: "text", text: t }], details });

/**
 * Memory tools over store. onChange receives each change ({path, action});
 * without allowDelete there is no memory_delete (consolidation).
 */
export function memoryTools(store, { allowDelete = true, onChange = () => {} } = {}) {
	const changed = (r) => {
		onChange(r);
		return text(`已${{ created: "新建", updated: "更新", appended: "追加到", deleted: "删除" }[r.action]} ${r.path}${r.hash ? `（版本 ${r.hash}）` : ""}`, { memory: r });
	};
	const pathParam = Type.String({ description: "profile.md | preferences.md | routines/<slug>.md | courses/<course_id>.md | notes/<slug>.md" });
	const tools = [
		{
			name: "memory_list",
			label: "查看记忆",
			description: "List the bot's memory files with titles, descriptions and versions.",
			parameters: Type.Object({}),
			execute: async () => {
				const files = await store.list();
				return text(files.length ? files.map((f) => `- ${f.path} · ${f.title || f.description || ""} · ${f.bytes} B · 版本 ${f.hash}`).join("\n") : "还没有记忆文件");
			},
		},
		{
			name: "memory_read",
			label: "读取记忆",
			description: "Read one memory file; returns its content and version hash (needed to replace or edit it).",
			parameters: Type.Object({ path: pathParam }),
			execute: async (_id, { path }) => {
				const f = await store.read(path);
				return text(`${f.path}（版本 ${f.hash}）\n${f.content}`);
			},
		},
		{
			name: "memory_write",
			label: "写入记忆",
			description:
				"Create a memory file, or replace one (pass base_hash from memory_read). Start with front matter: ---\\ntitle: …\\ndescription: …\\n--- (routines also `when: …`). Never store secrets, ID or card numbers, phone numbers or passwords.",
			parameters: Type.Object({ path: pathParam, content: Type.String(), base_hash: Type.Optional(Type.String()) }),
			execute: async (_id, { path, content, base_hash }) => changed(await store.write(path, content, base_hash)),
		},
		{
			name: "memory_edit",
			label: "修改记忆",
			description: "Replace one exact passage in a memory file (it must occur once).",
			parameters: Type.Object({ path: pathParam, old: Type.String(), new: Type.String(), base_hash: Type.Optional(Type.String()) }),
			execute: async (_id, p) => changed(await store.edit(p.path, p.old, p.new, p.base_hash)),
		},
		{
			name: "memory_append",
			label: "追加记忆",
			description: "Append lines to a memory file, creating it if needed.",
			parameters: Type.Object({ path: pathParam, text: Type.String() }),
			execute: async (_id, { path, text: t }) => changed(await store.append(path, t)),
		},
	];
	if (allowDelete) {
		tools.push({
			name: "memory_delete",
			label: "删除记忆",
			description: "Delete a memory file. Only when the user asks to forget it.",
			parameters: Type.Object({ path: pathParam }),
			execute: async (_id, { path }) => changed(await store.remove(path)),
		});
	}
	return tools;
}
