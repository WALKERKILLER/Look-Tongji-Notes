import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { DefaultResourceLoader } from "@earendil-works/pi-coding-agent";
import { applySettings, bundledPluginsDir, engineSatisfied, lookdRoute, PluginHost, validateManifest } from "./plugins.mjs";

const pkg = (lookStudio, extra = {}) => ({ name: `p-${lookStudio.id}`, version: "1.0.0", ...extra, lookStudio: { title: "测试", summary: "测试插件", engine: "^1.0.0", ...lookStudio } });

const AGENT = `
export function activate(look) {
	look.effect(() => { globalThis.__disposed = (globalThis.__disposed ?? 0) + 1; });
	look.action("hello", async (ctx) => ({ toast: "hi " + (ctx.name ?? ""), state: { n: 1 } }));
	look.action("show", async () => ({ view: { kind: "checklist", data: { items: [] } } }));
	look.action("bad_view", async () => ({ view: { kind: "graph", data: {} } }));
	look.action("slow", async (_ctx, { signal }) => {
		globalThis.__slowSignal = signal;
		await new Promise((r) => (globalThis.__slowGo = r));
		try {
			await look.lookd.get("/api/courses");
		} catch (e) {
			globalThis.__slowError = e;
			throw e;
		}
		return { toast: "late" };
	});
}
export default function (pi, look) {
	pi.registerTool({
		name: "ping",
		label: "Ping",
		description: "Answers pong. Second sentence.",
		parameters: { type: "object", properties: {} },
		execute: async () => ({ content: [{ type: "text", text: "pong" }], details: {} }),
	});
	pi.registerTool({
		name: "read",
		label: "Read",
		description: "Reads a course.",
		parameters: { type: "object", properties: {} },
		execute: async () => look.lookd.get("/api/courses"),
	});
	pi.registerTool({
		name: "secret",
		label: "Secret",
		description: "Reads settings.",
		parameters: { type: "object", properties: {} },
		execute: async () => look.lookd.get("/api/settings"),
	});
}
`;

async function fixture(t) {
	const root = await mkdtemp(join(tmpdir(), "look-plugins-"));
	t.after(() => rm(root, { recursive: true, force: true }));
	const bundled = join(root, "bundled");
	const write = async (dir, files) => {
		await mkdir(dir, { recursive: true });
		for (const [name, body] of Object.entries(files)) {
			await mkdir(join(dir, name, ".."), { recursive: true });
			await writeFile(join(dir, name), typeof body === "string" ? body : JSON.stringify(body));
		}
	};
	await write(join(bundled, "demo"), {
		"package.json": pkg({
			id: "demo",
			agent: "index.mjs",
			skills: ["skills"],
			views: ["checklist"],
			permissions: ["views", "library.read"],
			settings: { type: "object", properties: { port: { type: "integer", title: "端口", format: "port", default: 27121 } } },
			contributes: { actions: [{ id: "hello", title: "你好", surface: "composer.plus", action: "hello" }] },
		}),
		"index.mjs": AGENT,
		"skills/demo/SKILL.md": "---\nname: demo-skill\ndescription: A demo\n---\n# Demo\nDo the demo.",
	});
	await write(join(bundled, "broken"), {
		"package.json": pkg({ id: "broken", agent: "index.mjs" }),
		"index.mjs": "export default function () { throw new Error('boom'); }",
	});
	await write(bundled, { "catalog.json": { name: "official", plugins: [{ source: "demo", featured: true }, { source: "broken" }] } });
	const calls = [];
	const events = [];
	const host = new PluginHost({
		dataDir: join(root, "data"),
		libraryRoot: join(root, "lib"),
		bundledDir: bundled,
		lookd: async (method, path) => (calls.push(`${method} ${path}`), { content: [{ type: "text", text: "ok" }] }),
		notify: (e) => events.push(e),
	});
	await host.init();
	return { root, bundled, host, calls, events, write };
}

const install = async (host, source) => host.confirm((await host.preview(source)).token);

test("manifest validation", () => {
	assert.equal(validateManifest(pkg({ id: "ok-id" })).id, "ok-id");
	const bad = (lookStudio, re) => assert.throws(() => validateManifest(pkg({ id: "x1", ...lookStudio })), re);
	bad({ id: "Bad" }, /id/);
	bad({ id: "install" }, /保留名/);
	bad({ engine: "^2.0.0" }, /插件接口/);
	bad({ permissions: ["root"] }, /未知权限/);
	bad({ exec: ["cph"] }, /exec 权限/);
	bad({ permissions: ["network"] }, /hosts/);
	bad({ views: ["graph"] }, /views 权限/);
	bad({ agent: "../x.mjs" }, /相对路径/);
	bad({ settings: { type: "object", properties: { token: { type: "string", secret: true } } } }, /secret/);
	bad({ contributes: { actions: [{ id: "a", title: "A", action: "a", surface: "sidebar" }] } }, /surface/);
	assert.ok(engineSatisfied("^1.0.0", "1.4.2"));
	assert.ok(!engineSatisfied("^1.5.0", "1.4.2"));
	assert.ok(engineSatisfied(">=0.9.0", "1.0.0"));
});

test("settings get defaults and are checked", () => {
	const schema = { type: "object", properties: { port: { type: "integer", format: "port", default: 27121 }, mode: { type: "string", enum: ["a", "b"] } } };
	assert.deepEqual(applySettings(schema), { port: 27121 });
	assert.deepEqual(applySettings(schema, { mode: "b" }, { port: 8080 }), { port: 8080, mode: "b" });
	assert.throws(() => applySettings(schema, { port: 70000 }), /端口/);
	assert.throws(() => applySettings(schema, { mode: "c" }), /之一/);
});

test("install, tools, groups, actions and uninstall", async (t) => {
	const { host, calls, root } = await fixture(t);
	const catalog = await host.catalog();
	assert.deepEqual(catalog.plugins.map((p) => p.id), ["demo", "broken"]);
	const preview = await host.preview("bundled:demo");
	assert.deepEqual(preview.manifest.permissions.map((p) => p.id), ["views", "library.read"]);
	const view = await host.confirm(preview.token);
	assert.equal(view.state, "enabled");
	assert.deepEqual(view.tools.map((x) => x.name), ["demo__ping", "demo__read", "demo__secret"]);
	assert.deepEqual(view.settings_values, { port: 27121 });
	const state = await stat(join(root, "data", "plugins.json"));
	assert.equal(state.mode & 0o777, 0o600);

	const g = host.groups()["plugin:demo"];
	assert.deepEqual(g.tools, ["demo__ping", "demo__read", "demo__secret"]);
	assert.match(g.playbook, /## demo-skill\nDo the demo|# Demo/);
	assert.match(host.promptLines()[0], /plugin:demo/);

	assert.deepEqual(await host.runAction("demo", "hello", { name: "A" }), { toast: "hi A", state: { n: 1 } });
	assert.equal((await host.runAction("demo", "show")).view.plugin, "demo");
	await assert.rejects(host.runAction("demo", "bad_view"), /没有声明视图/);
	await assert.rejects(host.runAction("demo", "nope"), /没有动作/);

	// Real Pi loader: tools are prefixed, deferred and namespaced; permissions gate the Look API.
	const loader = new DefaultResourceLoader({ cwd: root, agentDir: root, noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true, extensionFactories: host.extensionFactories() });
	await loader.reload();
	const ext = loader.getExtensions();
	assert.deepEqual(ext.errors, []);
	const tools = ext.extensions[0].tools;
	const ping = tools.get("demo__ping").definition;
	assert.equal(ping.exposure, "deferred");
	assert.equal(ping.namespace.name, "demo");
	await tools.get("demo__read").definition.execute("1", {}, undefined, undefined, {});
	assert.deepEqual(calls, ["GET /api/courses"]);
	await assert.rejects(tools.get("demo__secret").definition.execute("1", {}, undefined, undefined, {}), /不能读取/);

	await host.uninstall("demo");
	assert.deepEqual(await host.list(), []);
	assert.deepEqual(host.groups(), {});
});

test("an action that times out is aborted and its later look calls are refused", async (t) => {
	const { host, calls } = await fixture(t);
	host.actionTimeoutMs = 50;
	await install(host, "bundled:demo");
	await assert.rejects(host.runAction("demo", "slow"), { status: 504 });
	assert.equal(globalThis.__slowSignal.aborted, true);
	globalThis.__slowGo(); // the handler carries on after the caller got 504
	await new Promise((r) => setImmediate(r));
	assert.match(globalThis.__slowError?.message ?? "", /已超时/);
	assert.deepEqual(calls, []); // its lookd read never ran
	assert.equal((await host.runAction("demo", "hello", { name: "B" })).toast, "hi B"); // other actions unaffected
});

test("close runs every plugin's cleanup", async (t) => {
	const { host } = await fixture(t);
	await install(host, "bundled:demo");
	globalThis.__disposed = 0;
	await host.close();
	assert.equal(globalThis.__disposed, 1);
	assert.equal(host.loaded.size, 0);
});

test("tool calls count against the conversation budget", async (t) => {
	const { host } = await fixture(t);
	const conv = { calls: 0 };
	host.convOf = (id) => (id === "s1" ? conv : null);
	host.guard = (c, tool) => ({ ...tool, execute: (...a) => (c.calls++, tool.execute(...a)) });
	await install(host, "bundled:demo");
	const loader = new DefaultResourceLoader({ cwd: host.root, agentDir: host.root, noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true, extensionFactories: host.extensionFactories() });
	await loader.reload();
	const ping = loader.getExtensions().extensions[0].tools.get("demo__ping").definition;
	await ping.execute("1", {}, undefined, undefined, { sessionManager: { getSessionId: () => "s1" } });
	assert.equal(conv.calls, 1);
});

test("scheduled task runs only get read-only plugin tools", async (t) => {
	const { host } = await fixture(t);
	const task = { calls: 0, writes: [] };
	host.convOf = (id) => (id === "task" ? task : { calls: 0 });
	const ctx = (id) => ({ sessionManager: { getSessionId: () => id } });
	const ok = async () => ({ content: [{ type: "text", text: "ok" }] });
	const writer = host.guardedExecute({ manifest: { permissions: ["library.write"] } }, "w__save", ok);
	await assert.rejects(writer("1", {}, undefined, undefined, ctx("task")), /定时任务里不能使用/);
	assert.equal((await writer("1", {}, undefined, undefined, ctx("chat"))).content[0].text, "ok");
	const reader = host.guardedExecute({ manifest: { permissions: ["library.read", "views"] } }, "r__read", ok);
	assert.equal((await reader("1", {}, undefined, undefined, ctx("task"))).content[0].text, "ok");

	// A read-only plugin's tool cannot write its own storage in a run either.
	await install(host, "bundled:demo");
	const { look } = host.loaded.get("demo");
	const saver = host.guardedExecute(host.loaded.get("demo"), "demo__save", async () => {
		await new Promise((r) => setImmediate(r));
		await look.storage.set("k", 1);
		return ok();
	});
	await assert.rejects(saver("1", {}, undefined, undefined, ctx("task")), /不能写入自己的存储/);
	assert.equal(await look.storage.get("k"), undefined);
	await saver("1", {}, undefined, undefined, ctx("chat"));
	assert.equal(await look.storage.get("k"), 1);
});

test("plugin lookd paths must be normal and on the route list", () => {
	assert.ok(lookdRoute("GET", "/api/courses"));
	assert.ok(lookdRoute("GET", "/api/courses/c%201/lectures"));
	assert.ok(lookdRoute("GET", "/api/search?q=%E6%A0%88&limit=5"));
	assert.ok(lookdRoute("PUT", "/api/notes"));
	assert.ok(lookdRoute("DELETE", "/api/schedule/s1"));
	assert.ok(lookdRoute("POST", "/api/lectures/l1/bookmarks"));
	for (const path of [
		"/api/notes/../library/export",
		"/api/notes/%2e%2e/library/export",
		"/api/notes/%2E%2E/settings",
		"/api/notes/./x",
		"/api/notes%2fx",
		"/api/notes\\..\\settings",
		"/api//notes",
		"//lookd/api/notes",
		"/api/notes/",
		"/api/settings",
		"/api/lectures/l1/media",
		"/api/lectures/l1/slides/0/image",
		"/api/notes/n1#x",
		"http://lookd/api/notes",
		"/api/notes/\u6808",
	]) {
		assert.equal(lookdRoute("GET", path), false, path);
		assert.equal(lookdRoute("DELETE", path), false, path);
	}
	assert.equal(lookdRoute("DELETE", "/api/courses"), false); // a read route is not writable
	assert.equal(lookdRoute("PATCH", "/api/notes"), false); // nor with another method
	assert.equal(lookdRoute("GET", "/api/notes/a/b"), false); // * is one segment
});

test("user catalogs are capped in bytes and entries", async (t) => {
	const { host } = await fixture(t);
	await host.addCatalog("https://example.com/big.json");
	let pulls = 0;
	host.fetch = async () =>
		new Response(
			new ReadableStream({
				pull(c) {
					pulls++;
					c.enqueue(new Uint8Array(64 * 1024));
				},
			}),
		);
	const big = await host.catalog();
	assert.match(big.errors[0].error, /目录过大/);
	assert.ok(pulls < 40); // stopped reading after the cap
	const plugins = Array.from({ length: 600 }, (_, i) => ({ id: `p-${i}`, source: `npm:p-${i}` }));
	host.fetch = async () => new Response(JSON.stringify({ name: "many", plugins }));
	const many = await host.catalog();
	assert.deepEqual(many.errors, []);
	assert.equal(many.plugins.filter((p) => p.catalog === "many").length, 500);
});

test("a failing plugin is isolated and effects run on disable", async (t) => {
	const { host } = await fixture(t);
	globalThis.__disposed = 0;
	await install(host, "bundled:demo");
	const broken = await install(host, "bundled:broken");
	assert.equal(broken.state, "error");
	assert.match(broken.error, /boom/);
	assert.equal((await host.view("demo")).state, "enabled");
	assert.deepEqual(host.extensionFactories().map((f) => f.name), ["demo"]);
	globalThis.__disposed = 0; // every reload disposes the previous generation
	const off = await host.update("demo", { enabled: false });
	assert.equal(off.state, "disabled");
	assert.equal(globalThis.__disposed, 1);
	await assert.rejects(host.runAction("demo", "hello"), /未启用/);
});

test("third-party sources need the opt-in, and new permissions need consent", async (t) => {
	const { host, root, write } = await fixture(t);
	const src = join(root, "third");
	await write(src, { "package.json": pkg({ id: "third", permissions: [] }) });
	await assert.rejects(host.preview(`path:${src}`), /第三方插件未开启/);
	await host.setAllowThirdParty(true);
	assert.equal((await install(host, `path:${src}`)).state, "enabled");

	await write(src, { "package.json": pkg({ id: "third", permissions: ["views"], views: ["checklist"] }, { version: "1.1.0" }) });
	// The installed copy is replaced only through preview/confirm; simulate an
	// updated package on disk to check the consent gate.
	await write(join(root, "data", "plugins", "pkgs", "third"), { "package.json": pkg({ id: "third", permissions: ["views"], views: ["checklist"] }, { version: "1.1.0" }) });
	await host.reload();
	const v = await host.view("third");
	assert.equal(v.state, "needs_consent");
	assert.deepEqual(v.needs_permissions.map((p) => p.id), ["views"]);
	assert.equal((await host.update("third", { grant: true })).state, "enabled");

	const preview = await host.preview(`path:${src}`);
	assert.deepEqual(preview.update, { from: "1.1.0", added_permissions: [] });
	await write(join(root, "official"), { "package.json": pkg({ id: "demo" }) });
	await assert.rejects(host.preview(`path:${join(root, "official")}`), /官方插件/);
});

test("the bundled catalog's plugins are valid", async () => {
	const c = JSON.parse(await readFile(join(bundledPluginsDir, "catalog.json"), "utf8"));
	for (const e of c.plugins) {
		const m = validateManifest(JSON.parse(await readFile(join(bundledPluginsDir, e.source, "package.json"), "utf8")));
		assert.equal(m.id, e.source);
	}
});

test("socratic toggles a mode that extends the system prompt", async (t) => {
	const root = await mkdtemp(join(tmpdir(), "look-socratic-"));
	t.after(() => rm(root, { recursive: true, force: true }));
	const host = new PluginHost({ dataDir: root, libraryRoot: root, bundledDir: bundledPluginsDir, lookd: async () => ({}) });
	await host.init();
	const v = await install(host, "bundled:socratic");
	assert.deepEqual(v.status, { active: false });
	assert.equal(host.groups()["plugin:socratic"].tools.length, 0);
	assert.match(host.groups()["plugin:socratic"].playbook, /提示梯度/);
	const loader = new DefaultResourceLoader({ cwd: root, agentDir: root, noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true, extensionFactories: host.extensionFactories() });
	await loader.reload();
	const [hook] = loader.getExtensions().extensions[0].handlers.get("before_agent_start");
	assert.equal(await hook({ systemPrompt: "BASE" }), undefined);
	assert.deepEqual((await host.runAction("socratic", "toggle")).state, { active: true });
	assert.deepEqual((await host.view("socratic")).status, { active: true });
	const r = await hook({ systemPrompt: "BASE" });
	assert.match(r.systemPrompt, /^BASE\n\n## 引导式提问模式/);
	assert.match(r.systemPrompt, /2 次/);
});
