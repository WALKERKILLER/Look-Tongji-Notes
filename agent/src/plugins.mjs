// Plugin platform: manifests, install state, catalogs, and loading enabled
// plugins as Pi inline extensions with a permission-gated Look API.
// Contract: docs/specs/0004-plugin-platform.md; why Pi extensions:
// docs/decisions/0005-plugins-as-pi-extensions-with-declarative-views.md
import { AsyncLocalStorage } from "node:async_hooks";
import { spawn as spawnProcess, execFile } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync } from "node:fs";
import { chmod, cp, mkdir, readdir, readFile, rename, rm, stat, writeFile } from "node:fs/promises";
import { isAbsolute, join, normalize, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { promisify } from "node:util";

export const PLUGIN_API_VERSION = "1.0.0";

export const PERMISSIONS = {
	"library.read": "读取课程资料",
	"library.write": "写入笔记、练习和日程",
	views: "在对话中显示交互视图",
	localhost: "连接本机程序",
	exec: "启动本机程序",
	workspace: "在课程库中创建工作目录",
	network: "访问网络",
	folder: "读写你选择的文件夹",
};
export const CATEGORIES = { notes: "笔记", visualize: "可视化", review: "复习", programming: "编程", connector: "连接器", tutor: "学习方式", assignment: "作业" };
export const SURFACES = ["note.toolbar", "lecture.menu", "course.menu", "schedule.item", "assignment.actions", "composer.plus"];
const SCOPES = ["note", "course", "library", "schedule"];

const bad = (message, status = 400) => Object.assign(new Error(message), { status });
const PRIVATE = 0o600;
const ID = /^[a-z][a-z0-9-]{1,31}$/;
// Ids that would shadow plugin routes (host.mjs).
const RESERVED = new Set(["catalog", "catalogs", "install", "third-party"]);
const NAME = /^[a-z][a-z0-9_]{0,39}$/;
const SEMVER = /^(\d+)\.(\d+)\.(\d+)(?:-[0-9A-Za-z.-]+)?$/;
const MAX_VIEW_BYTES = 256 * 1024;
const ACTION_TIMEOUT_MS = 60_000;

// The abort signal of the action whose code is running (it follows awaits),
// so the look API refuses work an action attempts after it timed out.
const actionScope = new AsyncLocalStorage();

function checkNotTimedOut() {
	if (actionScope.getStore()?.aborted) throw bad("插件动作已超时，后续操作已取消", 504);
}

// Set while a plugin tool runs in a scheduled task (it follows awaits), so the
// look API refuses the plugin's own persistent writes there.
const taskScope = new AsyncLocalStorage();

function checkNotInTask() {
	if (taskScope.getStore()) throw new Error("定时任务里插件不能写入自己的存储");
}
const MAX_PLAYBOOK = 12_000;
const MAX_CATALOG_BYTES = 1024 * 1024;
const MAX_CATALOG_ENTRIES = 500;
// Permissions that cannot change anything outside the conversation.
const READ_ONLY = new Set(["library.read", "views"]);

// lookd routes plugins may call, by method; * is one path segment.
const LOOKD_ROUTES = {
	GET: [
		"/api/courses",
		"/api/courses/*/lectures",
		"/api/lectures/*",
		"/api/lectures/*/slides",
		"/api/lectures/*/transcript",
		"/api/lectures/*/timeline",
		"/api/lectures/*/courseware",
		"/api/lectures/*/courseware/text",
		"/api/lectures/*/courseware/search",
		"/api/recent",
		"/api/search",
		"/api/notes",
		"/api/notes/*",
		"/api/activity",
		"/api/activity/day",
		"/api/quizzes",
		"/api/quizzes/*",
		"/api/schedule",
	],
	POST: ["/api/lectures/*/bookmarks", "/api/quizzes", "/api/quizzes/*/attempts", "/api/schedule"],
	PUT: ["/api/notes", "/api/lectures/*/timeline"],
	PATCH: ["/api/schedule/*"],
	DELETE: ["/api/notes/*", "/api/quizzes/*", "/api/schedule/*", "/api/lectures/*/timeline"],
};

/**
 * Whether a plugin may call lookd with method and path. The path must already
 * be in normal form (no dot segments, encoded slashes or dots, backslashes or
 * empty segments) so the route checked is the route lookd serves.
 */
export function lookdRoute(method, path) {
	if (typeof path !== "string" || path.length > 2048 || /[\\#\s\x00-\x1f\x7f]/.test(path)) return false;
	const q = path.indexOf("?");
	const pathname = q < 0 ? path : path.slice(0, q);
	if (/%(2e|2f|5c)/i.test(pathname)) return false;
	let url;
	try {
		url = new URL(path, "http://lookd");
	} catch {
		return false;
	}
	if (url.origin !== "http://lookd" || url.pathname !== pathname) return false;
	const segs = pathname.split("/");
	if (segs[0] !== "" || segs.slice(1).some((x) => !x || x === "." || x === "..")) return false;
	return (LOOKD_ROUTES[method] ?? []).some((r) => {
		const parts = r.split("/");
		return parts.length === segs.length && parts.every((x, i) => x === "*" || x === segs[i]);
	});
}

// Reads a response body, refusing more than max bytes.
async function readCapped(res, max) {
	if (Number(res.headers.get("content-length")) > max) throw new Error("目录过大");
	const chunks = [];
	let n = 0;
	for await (const chunk of res.body ?? []) {
		n += chunk.byteLength;
		if (n > max) throw new Error("目录过大");
		chunks.push(chunk);
	}
	return Buffer.concat(chunks).toString("utf8");
}

// ---- versions ----

const parts = (v) => SEMVER.exec(v)?.slice(1, 4).map(Number) ?? null;
const cmp = (a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2];

/** Compares two semver strings (prerelease tags ignored). */
export const compareVersions = (a, b) => cmp(parts(a) ?? [0, 0, 0], parts(b) ?? [0, 0, 0]);

/** `^x.y.z`, `>=x.y.z` or an exact version against `version`. */
export function engineSatisfied(range, version = PLUGIN_API_VERSION) {
	const m = /^(\^|>=)?(\d+\.\d+\.\d+)$/.exec(String(range ?? "").trim());
	if (!m) return false;
	const want = parts(m[2]);
	const have = parts(version);
	if (m[1] === ">=") return cmp(have, want) >= 0;
	if (m[1] === "^") return have[0] === want[0] && cmp(have, want) >= 0;
	return cmp(have, want) === 0;
}

// ---- manifest ----

const str = (v, max, what) => {
	if (typeof v !== "string" || !v.trim() || v.length > max) throw bad(`${what} 应为 1–${max} 字的文本`);
	return v.trim();
};
const list = (v, what) => {
	if (v === undefined) return [];
	if (!Array.isArray(v)) throw bad(`${what} 应为数组`);
	return v;
};
const relPath = (p, what) => {
	if (typeof p !== "string" || !p || isAbsolute(p) || normalize(p).split(/[\\/]/).includes("..")) throw bad(`${what} 应为插件目录内的相对路径`);
	return normalize(p);
};

/** Validates a settings schema (the JSON Schema subset in the spec). */
export function validateSettingsSchema(schema) {
	if (schema === undefined) return { type: "object", properties: {} };
	if (schema?.type !== "object" || typeof schema.properties !== "object") throw bad("settings 应为 {type: object, properties}");
	for (const [key, p] of Object.entries(schema.properties)) {
		if (!NAME.test(key)) throw bad(`设置项名 ${key} 无效`);
		if (p.secret) throw bad("暂不支持 secret 设置项");
		if (!["string", "number", "integer", "boolean", "array"].includes(p.type)) throw bad(`设置项 ${key} 的 type 不受支持`);
		if (p.type === "array" && !["string", "number", "integer"].includes(p.items?.type)) throw bad(`设置项 ${key} 的 items.type 不受支持`);
		if (p.format && !["port", "path"].includes(p.format) && !["port", "path"].includes(p.items?.format)) throw bad(`设置项 ${key} 的 format 不受支持`);
		if (p.enum && !Array.isArray(p.enum)) throw bad(`设置项 ${key} 的 enum 应为数组`);
		str(p.title ?? key, 24, `设置项 ${key} 的 title`);
	}
	return schema;
}

function checkValue(p, v, key) {
	const fail = () => bad(`设置项「${p.title ?? key}」的值无效`);
	switch (p.type) {
		case "string":
			if (typeof v !== "string" || v.length > 1000) throw fail();
			if (p.format === "path" && v && !isAbsolute(v)) throw bad(`「${p.title ?? key}」应为绝对路径`);
			break;
		case "boolean":
			if (typeof v !== "boolean") throw fail();
			break;
		case "number":
		case "integer":
			if (typeof v !== "number" || !Number.isFinite(v) || (p.type === "integer" && !Number.isInteger(v))) throw fail();
			if ((p.minimum !== undefined && v < p.minimum) || (p.maximum !== undefined && v > p.maximum)) throw bad(`「${p.title ?? key}」应在 ${p.minimum ?? "-∞"}–${p.maximum ?? "∞"} 之间`);
			if (p.format === "port" && !(Number.isInteger(v) && v >= 1 && v <= 65535)) throw bad(`「${p.title ?? key}」应为 1–65535 的端口`);
			break;
		case "array":
			if (!Array.isArray(v) || v.length > 32) throw fail();
			for (const x of v) checkValue({ ...p.items, title: p.title }, x, key);
			break;
	}
	if (p.enum && !p.enum.includes(v)) throw bad(`「${p.title ?? key}」应为 ${p.enum.join("、")} 之一`);
}

/** Merges `input` into `old` values, with schema defaults; throws 400. */
export function applySettings(schema, input = {}, old = {}) {
	const out = {};
	for (const [key, p] of Object.entries(schema.properties)) {
		const v = key in input ? input[key] : key in old ? old[key] : p.default;
		if (v === undefined) continue;
		checkValue(p, v, key);
		out[key] = v;
	}
	return out;
}

/** Validates a plugin's package.json; returns the normalized manifest. */
export function validateManifest(pkg) {
	const m = pkg?.lookStudio;
	if (!m || typeof m !== "object") throw bad("package.json 缺少 lookStudio 字段");
	if (!ID.test(m.id ?? "") || RESERVED.has(m.id)) throw bad("id 应为 2–32 位小写字母、数字或 -，以字母开头，且不能是保留名");
	if (!SEMVER.test(pkg.version ?? "")) throw bad("version 应为 semver，例如 1.0.0");
	const permissions = list(m.permissions, "permissions");
	for (const p of permissions) if (!(p in PERMISSIONS)) throw bad(`未知权限 ${p}`);
	const categories = list(m.categories, "categories");
	for (const c of categories) if (!(c in CATEGORIES)) throw bad(`未知分类 ${c}`);
	const exec = list(m.exec, "exec").map((c) => str(c, 200, "exec 命令"));
	if (exec.length && !permissions.includes("exec")) throw bad("声明 exec 命令需要 exec 权限");
	if (permissions.includes("exec") && !exec.length) throw bad("exec 权限需要在 exec 中列出命令");
	const hosts = list(m.hosts, "hosts").map((h) => str(h, 200, "hosts"));
	if (permissions.includes("network") && !hosts.length) throw bad("network 权限需要在 hosts 中列出域名");
	const views = list(m.views, "views").map((v) => {
		if (!/^[a-z][a-z-]{1,23}$/.test(v)) throw bad(`视图名 ${v} 无效`);
		return v;
	});
	if (views.length && !permissions.includes("views")) throw bad("声明视图需要 views 权限");
	const c = m.contributes ?? {};
	const entry = (e, what, extra) => {
		if (!NAME.test(e?.id ?? "")) throw bad(`${what} 的 id 无效`);
		if (!NAME.test(e.action ?? "")) throw bad(`${what}「${e.id}」缺少 action`);
		return { id: e.id, title: str(e.title, 16, `${what} 的 title`), icon: /^[a-z_0-9]{1,40}$/.test(e.icon ?? "") ? e.icon : "extension", action: e.action, ...extra(e) };
	};
	const contributes = {
		noteViews: list(c.noteViews, "contributes.noteViews").map((e) => entry(e, "noteViews", () => ({}))),
		actions: list(c.actions, "contributes.actions").map((e) =>
			entry(e, "actions", (x) => {
				if (!SURFACES.includes(x.surface)) throw bad(`actions「${x.id}」的 surface 应为 ${SURFACES.join("、")} 之一`);
				return { surface: x.surface };
			}),
		),
		exporters: list(c.exporters, "contributes.exporters").map((e) =>
			entry(e, "exporters", (x) => {
				if (!SCOPES.includes(x.scope)) throw bad(`exporters「${x.id}」的 scope 应为 ${SCOPES.join("、")} 之一`);
				return { scope: x.scope };
			}),
		),
		pages: list(c.pages, "contributes.pages").map((e) => entry(e, "pages", () => ({}))),
		blocks: list(c.blocks, "contributes.blocks").filter((v) => views.includes(v)),
	};
	return {
		id: m.id,
		name: String(pkg.name ?? m.id),
		version: pkg.version,
		title: str(m.title, 24, "title"),
		summary: str(m.summary, 80, "summary"),
		description: typeof m.description === "string" ? m.description.slice(0, 2000) : "",
		icon: /^[a-z_0-9]{1,40}$/.test(m.icon ?? "") ? m.icon : "extension",
		author: typeof pkg.author === "string" ? pkg.author : (pkg.author?.name ?? ""),
		license: typeof pkg.license === "string" ? pkg.license : "",
		homepage: typeof pkg.homepage === "string" ? pkg.homepage : "",
		categories,
		engine: (() => {
			if (!engineSatisfied(m.engine)) throw Object.assign(bad(`需要插件接口 ${m.engine}，当前为 ${PLUGIN_API_VERSION}`), { incompatible: true });
			return m.engine;
		})(),
		agent: m.agent === undefined ? null : relPath(m.agent, "agent"),
		skills: list(m.skills, "skills").map((p) => relPath(p, "skills")),
		views,
		permissions,
		exec,
		hosts,
		settings: validateSettingsSchema(m.settings),
		examples: list(m.examples, "examples")
			.slice(0, 6)
			.map((e) => str(e, 60, "examples")),
		contributes,
	};
}

/** Public shape of a manifest for the app. */
const publicManifest = (m) => ({
	id: m.id,
	version: m.version,
	title: m.title,
	summary: m.summary,
	description: m.description,
	icon: m.icon,
	author: m.author,
	license: m.license,
	homepage: m.homepage,
	categories: m.categories,
	views: m.views,
	permissions: m.permissions.map((p) => ({ id: p, label: PERMISSIONS[p], ...(p === "exec" ? { detail: m.exec.join("、") } : p === "network" ? { detail: m.hosts.join("、") } : {}) })),
	settings: m.settings,
	examples: m.examples,
	contributes: m.contributes,
});

// ---- the host ----

const execFileP = promisify(execFile);

/**
 * Owns installed plugins: state in plugins.json, packages, catalogs, and the
 * loaded runtime (one Pi resource loader per generation of enabled plugins).
 */
export class PluginHost {
	/**
	 * @param {object} o
	 * @param {string} o.dataDir agent data directory
	 * @param {string} o.libraryRoot library root (workspaces live there)
	 * @param {string} o.bundledDir official plugins and catalog.json
	 * @param {(method: string, path: string, body?: any) => Promise<any>} o.lookd lookd client
	 * @param {(e: object) => void} [o.notify] plugin events for the app
	 * @param {(sessionId: string) => any} [o.convOf] conversation for a session id (tool guard)
	 * @param {(conv: any, tool: object) => object} [o.guard] wraps a tool with the turn budget
	 * @param {Function} [o.fetch] for user catalogs
	 * @param {number} [o.actionTimeoutMs] how long an action may run
	 */
	constructor({ dataDir, libraryRoot, bundledDir, lookd, notify = () => {}, convOf = () => null, guard = (_c, t) => t, fetch = globalThis.fetch, actionTimeoutMs = ACTION_TIMEOUT_MS }) {
		this.root = join(dataDir, "plugins");
		this.stateFile = join(dataDir, "plugins.json");
		this.libraryRoot = libraryRoot;
		this.bundledDir = bundledDir;
		this.lookd = lookd;
		this.notify = notify;
		this.convOf = convOf;
		this.guard = guard;
		this.fetch = fetch;
		this.actionTimeoutMs = actionTimeoutMs;
		this.state = { allow_third_party: false, plugins: {}, catalogs: [] };
		this.loaded = new Map(); // id → {manifest, dir, tools, actions, effects, error}
		this.staged = new Map(); // token → {dir, manifest, source, official, at}
		this.generation = 0;
	}

	async init() {
		// Plugin packages and storage are private to the user, like plugins.json.
		await mkdir(this.root, { recursive: true, mode: 0o700 });
		await chmod(this.root, 0o700);
		await mkdir(join(this.root, "pkgs"), { recursive: true });
		await mkdir(join(this.root, "data"), { recursive: true });
		await rm(join(this.root, "staging"), { recursive: true, force: true });
		try {
			this.state = { ...this.state, ...JSON.parse(await readFile(this.stateFile, "utf8")) };
		} catch {}
		await chmod(this.stateFile, PRIVATE).catch(() => {});
		await this.reload();
	}

	async save() {
		const tmp = `${this.stateFile}.tmp`;
		await writeFile(tmp, JSON.stringify({ schema: "look-studio/plugins@1", ...this.state }, null, 1), { mode: PRIVATE });
		await chmod(tmp, PRIVATE);
		await rename(tmp, this.stateFile);
	}

	// ---- packages and catalogs ----

	dirOf(id) {
		const s = this.state.plugins[id];
		return s?.source?.startsWith("bundled:") ? join(this.bundledDir, s.source.slice(8)) : join(this.root, "pkgs", id);
	}

	async readManifest(dir) {
		let pkg;
		try {
			pkg = JSON.parse(await readFile(join(dir, "package.json"), "utf8"));
		} catch {
			throw bad("找不到插件的 package.json");
		}
		const m = validateManifest(pkg);
		if (m.agent && !existsSync(join(dir, m.agent))) throw bad(`找不到 agent 模块 ${m.agent}`);
		return m;
	}

	async officialCatalog() {
		const c = JSON.parse(await readFile(join(this.bundledDir, "catalog.json"), "utf8"));
		const out = [];
		for (const e of c.plugins ?? []) {
			try {
				const m = await this.readManifest(join(this.bundledDir, e.source));
				out.push({ ...publicManifest(m), source: `bundled:${e.source.replace(/^\.\//, "")}`, official: true, featured: e.featured === true, catalog: c.name ?? "official" });
			} catch (err) {
				console.error(`official plugin ${e.source}: ${err.message}`);
			}
		}
		return out;
	}

	/** Every catalog's plugins with install state; user catalogs that fail to load are reported. */
	async catalog() {
		const entries = await this.officialCatalog();
		const errors = [];
		for (const c of this.state.catalogs) {
			try {
				const res = await this.fetch(c.url, { signal: AbortSignal.timeout(15_000) });
				if (!res.ok) throw new Error(`HTTP ${res.status}`);
				const data = JSON.parse(await readCapped(res, MAX_CATALOG_BYTES));
				for (const e of (Array.isArray(data.plugins) ? data.plugins : []).slice(0, MAX_CATALOG_ENTRIES)) {
					if (!ID.test(e.id ?? "") || typeof e.source !== "string" || entries.some((x) => x.id === e.id)) continue;
					entries.push({
						id: e.id,
						version: String(e.version ?? ""),
						title: String(e.title ?? e.id).slice(0, 24),
						summary: String(e.summary ?? "").slice(0, 80),
						icon: /^[a-z_0-9]{1,40}$/.test(e.icon ?? "") ? e.icon : "extension",
						categories: (e.categories ?? []).filter((x) => x in CATEGORIES),
						author: String(e.author ?? data.owner?.name ?? ""),
						source: e.source,
						official: false,
						catalog: String(data.name ?? c.url),
					});
				}
			} catch (err) {
				errors.push({ url: c.url, error: err.message });
			}
		}
		return {
			allow_third_party: this.state.allow_third_party,
			catalogs: this.state.catalogs,
			errors,
			plugins: entries.map((e) => {
				const s = this.state.plugins[e.id];
				return { ...e, installed: s ? { version: s.version, enabled: s.enabled } : null, update: s && e.version && compareVersions(e.version, s.version) > 0 };
			}),
		};
	}

	async addCatalog(url) {
		let u;
		const gh = /^([\w.-]+)\/([\w.-]+)$/.exec(String(url ?? "").trim());
		try {
			u = new URL(gh ? `https://raw.githubusercontent.com/${gh[1]}/${gh[2]}/HEAD/look-catalog.json` : url);
		} catch {
			throw bad("目录地址应为 https:// 链接或 owner/repo");
		}
		if (u.protocol !== "https:") throw bad("目录地址需要 https");
		if (this.state.catalogs.some((c) => c.url === u.href)) throw bad("这个目录已添加", 409);
		this.state.catalogs.push({ url: u.href, added_at: Date.now() });
		await this.save();
		return this.state.catalogs;
	}

	async removeCatalog(url) {
		this.state.catalogs = this.state.catalogs.filter((c) => c.url !== url);
		await this.save();
		return this.state.catalogs;
	}

	async setAllowThirdParty(on) {
		this.state.allow_third_party = on === true;
		await this.save();
	}

	/** Fetches a source into a staging directory and validates it; nothing is installed yet. */
	async preview(source) {
		source = String(source ?? "").trim();
		const official = source.startsWith("bundled:");
		if (!official && !this.state.allow_third_party) throw bad("第三方插件未开启：设置 → 插件 → 允许第三方插件", 403);
		const token = randomBytes(12).toString("hex");
		const dir = join(this.root, "staging", token);
		await mkdir(dir, { recursive: true });
		try {
			if (official) {
				const rel = source.slice(8);
				if (!ID.test(rel)) throw bad("官方插件不存在", 404);
				await cp(join(this.bundledDir, rel), dir, { recursive: true });
			} else if (source.startsWith("path:")) {
				const p = source.slice(5);
				if (!isAbsolute(p)) throw bad("本地路径应为绝对路径");
				await cp(p, dir, { recursive: true, filter: (f) => !f.includes(`${join(p, "node_modules")}`) });
			} else if (source.startsWith("npm:")) {
				const spec = source.slice(4);
				if (!/^(@[\w.-]+\/)?[\w.-]+@\d+\.\d+\.\d+$/.test(spec)) throw bad("npm 来源需要固定版本，例如 npm:@scope/name@1.2.3");
				const { stdout } = await execFileP("npm", ["pack", spec, "--pack-destination", dir, "--json", "--ignore-scripts"], { timeout: 120_000 });
				const file = JSON.parse(stdout)[0].filename;
				await execFileP("tar", ["-xzf", join(dir, file), "-C", dir, "--strip-components=1"], { timeout: 60_000 });
				await rm(join(dir, file), { force: true });
			} else if (source.startsWith("git:")) {
				const [url, ref] = source.slice(4).split("#");
				if (!/^https:\/\//.test(url) || !ref) throw bad("git 来源需要 https 地址和固定版本，例如 git:https://github.com/a/b#v1.0.0");
				await execFileP("git", ["clone", "--depth", "1", "--branch", ref, "--", url, dir], { timeout: 120_000 });
				await rm(join(dir, ".git"), { recursive: true, force: true });
			} else {
				throw bad("来源应为 bundled:、path:、npm: 或 git:");
			}
			const manifest = await this.readManifest(dir);
			if (!official && (await this.isOfficialId(manifest.id))) throw bad(`id ${manifest.id} 属于官方插件`);
			const old = this.state.plugins[manifest.id];
			this.staged.set(token, { dir, manifest, source, official, at: Date.now() });
			setTimeout(() => this.dropStaged(token), 10 * 60_000).unref?.();
			return {
				token,
				official,
				source,
				manifest: publicManifest(manifest),
				update: old ? { from: old.version, added_permissions: manifest.permissions.filter((p) => !old.granted.includes(p)) } : null,
			};
		} catch (e) {
			await rm(dir, { recursive: true, force: true });
			throw e;
		}
	}

	async isOfficialId(id) {
		return (await this.officialCatalog()).some((e) => e.id === id);
	}

	async dropStaged(token) {
		const s = this.staged.get(token);
		this.staged.delete(token);
		if (s) await rm(s.dir, { recursive: true, force: true });
	}

	/** Installs a previewed package with exactly the permissions shown. */
	async confirm(token) {
		const s = this.staged.get(token);
		if (!s) throw bad("安装预览已过期，请重新安装", 410);
		this.staged.delete(token);
		const { manifest, dir, source, official } = s;
		try {
			if (!official) {
				const pkg = JSON.parse(await readFile(join(dir, "package.json"), "utf8"));
				if (Object.keys(pkg.dependencies ?? {}).length) {
					await execFileP("npm", ["install", "--omit=dev", "--ignore-scripts", "--no-audit", "--no-fund"], { cwd: dir, timeout: 300_000 });
				}
				const target = join(this.root, "pkgs", manifest.id);
				await rm(`${target}.old`, { recursive: true, force: true });
				if (existsSync(target)) await rename(target, `${target}.old`);
				await rename(dir, target);
				await rm(`${target}.old`, { recursive: true, force: true });
			} else {
				await rm(dir, { recursive: true, force: true });
			}
			const old = this.state.plugins[manifest.id];
			this.state.plugins[manifest.id] = {
				source,
				version: manifest.version,
				official,
				enabled: true,
				granted: manifest.permissions,
				settings: applySettings(manifest.settings, {}, old?.settings ?? {}),
				installed_at: old?.installed_at ?? Date.now(),
				updated_at: Date.now(),
			};
			await this.save();
			await this.reload();
			return this.view(manifest.id);
		} catch (e) {
			await rm(dir, { recursive: true, force: true });
			throw e;
		}
	}

	async update(id, { enabled, settings, grant } = {}) {
		const s = this.state.plugins[id];
		if (!s) throw bad("插件未安装", 404);
		const m = await this.readManifest(this.dirOf(id));
		if (grant === true) {
			// Re-consent after an update on disk asked for more.
			s.granted = m.permissions;
			s.version = m.version;
		}
		if (settings !== undefined) s.settings = applySettings(m.settings, settings, s.settings);
		if (enabled !== undefined) s.enabled = enabled === true;
		await this.save();
		await this.reload();
		return this.view(id);
	}

	async uninstall(id) {
		const s = this.state.plugins[id];
		if (!s) throw bad("插件未安装", 404);
		delete this.state.plugins[id];
		await this.save();
		await this.reload();
		if (!s.source.startsWith("bundled:")) await rm(join(this.root, "pkgs", id), { recursive: true, force: true });
		await rm(join(this.root, "data", id), { recursive: true, force: true });
	}

	// ---- runtime ----

	/** Installed plugins with their state for the app. */
	async list() {
		const out = [];
		for (const id of Object.keys(this.state.plugins)) out.push(await this.view(id));
		return out;
	}

	async view(id) {
		const s = this.state.plugins[id];
		const l = this.loaded.get(id);
		let manifest = l?.manifest;
		let error = l?.error ?? null;
		if (!manifest) {
			try {
				manifest = await this.readManifest(this.dirOf(id));
			} catch (e) {
				error = e.message;
			}
		}
		const missing = manifest ? manifest.permissions.filter((p) => !s.granted.includes(p)) : [];
		return {
			...(manifest ? publicManifest(manifest) : { id, title: id, summary: "", icon: "extension", permissions: [], contributes: {} }),
			version: manifest?.version ?? s.version,
			source: s.source,
			official: s.official,
			enabled: s.enabled,
			settings_values: s.settings,
			state: !s.enabled ? "disabled" : missing.length ? "needs_consent" : error ? "error" : "enabled",
			error: missing.length ? null : error,
			needs_permissions: missing.map((p) => ({ id: p, label: PERMISSIONS[p] })),
			tools: l?.tools?.map((t) => ({ name: t.name, label: t.label })) ?? [],
			skills: l?.skills?.map((k) => ({ name: k.name, description: k.description })) ?? [],
			status: l?.status ?? null,
		};
	}

	/**
	 * Disposes the current generation and loads enabled plugins again: runs
	 * each `activate(look)` once and dry-runs its Pi factory to learn its tools.
	 * Conversations opened afterwards get the new set (see extensionFactories).
	 */
	async reload() {
		await this.close();
		this.loaded = new Map();
		this.generation++;
		for (const [id, s] of Object.entries(this.state.plugins)) {
			if (!s.enabled) continue;
			const dir = this.dirOf(id);
			const rec = { manifest: null, dir, mod: null, tools: [], skills: [], actions: new Map(), effects: [], error: null, look: null, status: null };
			this.loaded.set(id, rec);
			try {
				rec.manifest = await this.readManifest(dir);
				const missing = rec.manifest.permissions.filter((p) => !s.granted.includes(p));
				if (missing.length) {
					rec.error = `更新后需要新权限：${missing.map((p) => PERMISSIONS[p]).join("、")}`;
					continue;
				}
				rec.skills = await readSkills(dir, rec.manifest.skills);
				if (!rec.manifest.agent) continue;
				rec.look = this.lookApi(rec);
				const mod = await import(`${pathToFileURL(join(dir, rec.manifest.agent)).href}?g=${this.generation}`);
				if (mod.default !== undefined && typeof mod.default !== "function") throw new Error("agent 模块的 default 导出应为函数 (pi, look)");
				if (typeof mod.activate === "function") await mod.activate(rec.look);
				if (typeof mod.default === "function") await mod.default(this.wrapPi(stubPi(), rec, true), rec.look);
				rec.mod = mod;
			} catch (e) {
				rec.error = `加载失败：${e.message}`;
				await runEffects(rec);
				rec.tools = [];
				rec.actions.clear();
			}
		}
	}

	/** Pi inline extensions for a new conversation, one per loaded plugin. */
	extensionFactories() {
		const out = [];
		for (const [id, rec] of this.loaded) {
			if (rec.error || typeof rec.mod?.default !== "function") continue;
			out.push({ name: id, factory: (pi) => rec.mod.default(this.wrapPi(pi, rec, false), rec.look) });
		}
		return out;
	}

	wrapPi(pi, rec, record) {
		const id = rec.manifest.id;
		const host = this;
		const blocked = new Set(["registerProvider", "unregisterProvider", "registerVirtualModel", "registerMcpServer", "unregisterMcpServer", "setModel", "setThinkingLevel", "setActiveTools"]);
		return new Proxy(pi, {
			get(target, prop) {
				if (prop === "registerTool") {
					return (def) => {
						if (!NAME.test(def?.name ?? "")) throw new Error(`工具名 ${def?.name} 无效`);
						if (typeof def.execute !== "function" || typeof def.parameters !== "object" || !def.parameters) throw new Error(`工具 ${def.name} 需要 parameters 和 execute`);
						const name = `${id}__${def.name}`;
						const label = String(def.label ?? def.name).slice(0, 24);
						if (record) rec.tools.push({ name, label, description: String(def.description ?? "") });
						return target.registerTool({
							...def,
							name,
							label,
							exposure: "deferred",
							namespace: { name: id, description: rec.manifest.title },
							execute: host.guardedExecute(rec, name, def.execute),
						});
					};
				}
				if (blocked.has(prop)) {
					return () => {
						throw new Error(`插件不能调用 ${String(prop)}`);
					};
				}
				const v = Reflect.get(target, prop);
				return typeof v === "function" ? v.bind(target) : v;
			},
		});
	}

	/**
	 * Runs a plugin tool under the calling conversation's budget and result cap.
	 * Scheduled task runs (conv.writes set) only get plugins with read-only
	 * permissions, and their tools cannot write the plugin's storage.
	 */
	guardedExecute(rec, name, execute) {
		return async (callId, params, signal, onUpdate, ctx) => {
			const conv = this.convOf(ctx?.sessionManager?.getSessionId?.());
			if (conv?.writes && rec.manifest.permissions.some((p) => !READ_ONLY.has(p))) {
				throw new Error(`定时任务里不能使用会写入或连接外部的插件工具 ${name}。不要再尝试，把结果写在总结里。`);
			}
			const tool = { name, execute: conv?.writes ? (...a) => taskScope.run(true, () => execute(...a)) : execute };
			return (conv ? this.guard(conv, tool) : tool).execute(callId, params, signal, onUpdate, ctx);
		};
	}

	lookApi(rec) {
		const m = rec.manifest;
		const id = m.id;
		const host = this;
		const granted = () => host.state.plugins[id]?.granted ?? [];
		const need = (p) => {
			if (!m.permissions.includes(p) || !granted().includes(p)) throw new Error(`插件 ${m.title} 没有「${PERMISSIONS[p]}」权限`);
		};
		const settings = () => host.state.plugins[id]?.settings ?? {};
		const dataDir = join(host.root, "data", id);
		const ports = () => {
			const out = new Set();
			for (const [k, p] of Object.entries(m.settings.properties)) {
				const v = settings()[k];
				if (p.format === "port" && Number.isInteger(v)) out.add(v);
				if (p.items?.format === "port" && Array.isArray(v)) v.forEach((x) => out.add(x));
			}
			return out;
		};
		const write = (method) => (path, body) => {
			checkNotTimedOut();
			need("library.write");
			if (!lookdRoute(method, path)) throw new Error(`插件不能写入 ${method} ${path}`);
			return host.lookd(method, path, body);
		};
		return Object.freeze({
			id,
			version: m.version,
			settings,
			lookd: Object.freeze({
				get: (path) => {
					checkNotTimedOut();
					need("library.read");
					if (!lookdRoute("GET", path)) throw new Error(`插件不能读取 ${path}`);
					return host.lookd("GET", path);
				},
				post: write("POST"),
				put: write("PUT"),
				patch: write("PATCH"),
				delete: write("DELETE"),
			}),
			view(kind, data, text) {
				need("views");
				if (!m.views.includes(kind)) throw new Error(`插件没有声明视图 ${kind}`);
				if (Buffer.byteLength(JSON.stringify(data ?? null)) > MAX_VIEW_BYTES) throw new Error("视图数据过大");
				return { content: [{ type: "text", text: text ?? `已在界面中显示「${kind}」视图。` }], details: { view: { kind, version: 1, plugin: id, data } } };
			},
			action(name, handler) {
				if (!NAME.test(name) || typeof handler !== "function") throw new Error(`动作 ${name} 无效`);
				rec.actions.set(name, handler);
			},
			effect(dispose) {
				if (typeof dispose === "function") rec.effects.push(dispose);
			},
			storage: Object.freeze({
				dir: async () => (checkNotInTask(), await mkdir(dataDir, { recursive: true }), dataDir),
				get: async (key) => {
					try {
						return JSON.parse(await readFile(join(dataDir, "storage.json"), "utf8"))[key];
					} catch {
						return undefined;
					}
				},
				set: async (key, value) => {
					checkNotTimedOut();
					checkNotInTask();
					await mkdir(dataDir, { recursive: true });
					let all = {};
					try {
						all = JSON.parse(await readFile(join(dataDir, "storage.json"), "utf8"));
					} catch {}
					all[key] = value;
					await writeFile(join(dataDir, "storage.json"), JSON.stringify(all), { mode: PRIVATE });
				},
			}),
			async workspace(name) {
				need("workspace");
				if (!/^[\w.-]{1,64}$/.test(name) || name.startsWith(".")) throw new Error("工作目录名无效");
				const dir = join(host.libraryRoot, "workspaces", id, name);
				await mkdir(dir, { recursive: true });
				return dir;
			},
			folder(key) {
				need("folder");
				const p = m.settings.properties[key];
				const v = settings()[key];
				if (p?.format !== "path" || typeof v !== "string" || !isAbsolute(v)) throw new Error("请先在插件设置中选择文件夹");
				return v;
			},
			/** Resolves `rel` inside `base`, refusing escapes. */
			inside(base, rel) {
				const p = resolve(base, rel);
				const r = relative(base, p);
				if (r.startsWith("..") || isAbsolute(r)) throw new Error("路径超出允许的目录");
				return p;
			},
			spawn(command, args = [], opts = {}) {
				checkNotTimedOut();
				need("exec");
				if (!m.exec.includes(command)) throw new Error(`插件没有声明命令 ${command}`);
				const child = spawnProcess(command, args, { cwd: opts.cwd, env: { ...process.env, LOOKD_TOKEN: "", ...(opts.env ?? {}) }, stdio: opts.stdio ?? "pipe", shell: false });
				rec.effects.push(() => child.exitCode === null && child.kill());
				return child;
			},
			async fetch(url, init) {
				checkNotTimedOut();
				const u = new URL(url);
				const local = ["127.0.0.1", "localhost", "[::1]"].includes(u.hostname);
				if (local) {
					need("localhost");
					if (!ports().has(Number(u.port))) throw new Error(`插件设置中没有端口 ${u.port}`);
				} else {
					need("network");
					if (!m.hosts.includes(u.hostname)) throw new Error(`插件没有声明域名 ${u.hostname}`);
				}
				const action = actionScope.getStore();
				const signal = init?.signal ?? AbortSignal.timeout(30_000);
				return fetch(u, { ...init, signal: action ? AbortSignal.any([signal, action]) : signal });
			},
			notify(text) {
				checkNotTimedOut();
				host.notify({ plugin: id, kind: "notify", text: String(text).slice(0, 200) });
			},
			emit(data) {
				checkNotTimedOut();
				host.notify({ plugin: id, kind: "update", data });
			},
			/** Small public state the app shows, e.g. {active: true} for a composer mode. */
			status(value) {
				checkNotTimedOut();
				if (Buffer.byteLength(JSON.stringify(value ?? null)) > 4096) throw new Error("状态过大");
				rec.status = value ?? null;
				host.notify({ plugin: id, kind: "status", status: rec.status });
			},
		});
	}

	/**
	 * Runs a contributed action for the app. The handler gets `{signal}`; on
	 * timeout the signal aborts, its plugin fetches are cancelled, and look
	 * API calls it makes afterwards are refused.
	 */
	async runAction(id, name, context = {}) {
		const rec = this.loaded.get(id);
		if (!rec || !this.state.plugins[id]?.enabled) throw bad("插件未启用", 404);
		if (rec.error) throw bad(rec.error, 409);
		const handler = rec.actions.get(name);
		if (!handler) throw bad(`插件没有动作 ${name}`, 404);
		const ac = new AbortController();
		let timer;
		const r = await Promise.race([
			actionScope.run(ac.signal, async () => handler(context, { signal: ac.signal })),
			new Promise((_, rej) => {
				timer = setTimeout(() => {
					ac.abort(bad("插件动作超时", 504));
					rej(ac.signal.reason);
				}, this.actionTimeoutMs);
			}),
		]).finally(() => clearTimeout(timer));
		return checkActionResult(rec.manifest, r);
	}

	/** Runs every loaded plugin's cleanup (on reload and when the agent exits). */
	async close() {
		for (const l of this.loaded.values()) await runEffects(l);
		this.loaded = new Map();
	}

	/** find_tools groups: a plugin's tools, with its skills as the playbook. */
	groups() {
		const out = {};
		for (const [id, rec] of this.loaded) {
			if (rec.error || !rec.manifest || (!rec.tools.length && !rec.skills.length)) continue;
			const m = rec.manifest;
			out[`plugin:${id}`] = {
				label: m.title,
				tools: rec.tools.map((t) => t.name),
				descriptions: Object.fromEntries(rec.tools.map((t) => [t.name, t.description])),
				playbook: rec.skills.map((k) => `## ${k.name}\n${k.body}`).join("\n\n").slice(0, MAX_PLAYBOOK),
				words: `${m.title} ${m.summary} ${m.categories.map((c) => CATEGORIES[c]).join(" ")} ${id}`,
			};
		}
		return out;
	}

	/** System prompt lines naming each loaded plugin and how to reach it. */
	promptLines() {
		const groups = this.groups();
		const lines = [];
		for (const [id, rec] of this.loaded) {
			if (rec.error || !rec.manifest) continue;
			const g = groups[`plugin:${id}`];
			lines.push(`- ${rec.manifest.title}：${rec.manifest.summary}${g ? `（find_tools 加载 plugin:${id}）` : ""}`);
		}
		return lines;
	}
}

/** Reads SKILL.md files: `paths` are directories holding SKILL.md, or .md files. */
async function readSkills(dir, paths) {
	const out = [];
	for (const p of paths) {
		const base = join(dir, p);
		const files = [];
		try {
			const st = await stat(base);
			if (st.isFile()) files.push(base);
			else if (existsSync(join(base, "SKILL.md"))) files.push(join(base, "SKILL.md"));
			else for (const d of await readdir(base, { withFileTypes: true })) if (d.isDirectory() && existsSync(join(base, d.name, "SKILL.md"))) files.push(join(base, d.name, "SKILL.md"));
		} catch {
			throw new Error(`找不到技能 ${p}`);
		}
		for (const f of files) {
			const text = await readFile(f, "utf8");
			const fm = /^---\n([\s\S]*?)\n---\n?/.exec(text);
			const field = (k) => fm && new RegExp(`^${k}:\\s*(.+)$`, "m").exec(fm[1])?.[1].trim().replace(/^["']|["']$/g, "");
			out.push({ name: field("name") || p, description: field("description") || "", body: (fm ? text.slice(fm[0].length) : text).trim() });
		}
	}
	return out;
}

function checkActionResult(m, r) {
	if (!r || typeof r !== "object") throw bad("插件动作没有返回结果", 502);
	if (r.view) {
		if (!m.views.includes(r.view.kind)) throw bad(`插件没有声明视图 ${r.view.kind}`, 502);
		if (Buffer.byteLength(JSON.stringify(r.view.data ?? null)) > MAX_VIEW_BYTES) throw bad("视图数据过大", 502);
		return { view: { kind: r.view.kind, version: 1, plugin: m.id, data: r.view.data, title: String(r.view.title ?? m.title).slice(0, 40) }, toast: r.toast ? String(r.toast).slice(0, 120) : undefined };
	}
	if (typeof r.prompt === "string") return { prompt: r.prompt.slice(0, 4000) };
	if (typeof r.open === "string") return { open: r.open };
	if (typeof r.toast === "string") return { toast: r.toast.slice(0, 120), ...(r.state && typeof r.state === "object" ? { state: r.state } : {}) };
	throw bad("插件动作返回了未知结果", 502);
}

async function runEffects(rec) {
	for (const dispose of rec.effects.splice(0).reverse()) {
		try {
			await dispose();
		} catch (e) {
			console.error(`plugin ${rec.manifest?.id} cleanup: ${e.message}`);
		}
	}
}

/** Pi's ExtensionAPI for the load-time dry run: records tools, ignores the rest. */
function stubPi() {
	const api = { registerTool() {}, on: () => () => {} };
	return new Proxy(api, { get: (t, p) => (p in t ? t[p] : () => {}) });
}

export const bundledPluginsDir = fileURLToPath(new URL("../plugins/", import.meta.url));
export { publicManifest };
