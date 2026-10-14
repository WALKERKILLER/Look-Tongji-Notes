// Model pipeline for the embedded Pi agent.
//
// App-owned files in AGENT_DATA_DIR (never the user's ~/.pi unless imported):
//   models.json     Pi-format custom providers (OpenAI/Anthropic/Google-compatible endpoints)
//   keys.json       API keys for built-in providers, applied with setRuntimeApiKey (0600)
//   assistant.json  selected provider/model/thinking level and prompt preferences
import { chmod, mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { ModelRuntime } from "@earendil-works/pi-coding-agent";
import { Catalog } from "./catalog.mjs";
import { entryFrom } from "./usage.mjs";

export const DATA_DIR = process.env.AGENT_DATA_DIR ?? join(homedir(), ".local/share/look-studio/agent");
const MODELS = join(DATA_DIR, "models.json");
const KEYS = join(DATA_DIR, "keys.json");
const PREFS = join(DATA_DIR, "assistant.json");
// App-only provider metadata (models.dev link, preset id); kept out of models.json.
const LINKS = join(DATA_DIR, "provider-links.json");
const PI_DIR = join(homedir(), ".pi", "agent");

const APIS = ["openai-completions", "openai-responses", "anthropic-messages", "google-generative-ai"];

async function readJSON(path, fallback) {
	try {
		return JSON.parse(await readFile(path, "utf8"));
	} catch {
		return fallback;
	}
}

async function writeJSON(path, value, mode = 0o600) {
	await mkdir(DATA_DIR, { recursive: true });
	const tmp = `${path}.tmp`;
	await writeFile(tmp, JSON.stringify(value, null, 2) + "\n", { mode });
	await rename(tmp, path);
	await chmod(path, mode);
}

const mask = (k) => (k ? `${k.slice(0, 3)}…${k.slice(-4)}` : "");

export class ModelPipeline {
	runtime = null;
	// vision: "provider/model" that transcribes images for text-only chat models.
	prefs = { provider: "", model: "", thinking: "medium", persona: "", autoTitle: true, vision: "" };
	listeners = new Set();
	catalog = new Catalog(DATA_DIR);

	async init() {
		await mkdir(DATA_DIR, { recursive: true });
		this.prefs = { ...this.prefs, ...(await readJSON(PREFS, {})) };
		await this.rebuild();
	}

	onChange(fn) {
		this.listeners.add(fn);
		return () => this.listeners.delete(fn);
	}

	async rebuild() {
		const runtime = await ModelRuntime.create({
			authPath: join(DATA_DIR, "auth.json"),
			modelsPath: MODELS,
			modelsStorePath: join(DATA_DIR, "models-store.json"),
			allowModelNetwork: true,
			refreshOnCreate: false,
		});
		const keys = await readJSON(KEYS, {});
		for (const [provider, key] of Object.entries(keys)) {
			if (key) await runtime.setRuntimeApiKey(provider, key).catch(() => {});
		}
		this.runtime = runtime;
		for (const fn of this.listeners) fn();
	}

	/** Resolve the selected model, falling back to the first usable one. */
	async currentModel() {
		const rt = this.runtime;
		const { provider, model } = this.prefs;
		const available = await rt.getAvailable();
		const picked = provider && model ? available.find((m) => m.provider === provider && m.id === model) : undefined;
		return picked ?? available[0];
	}

	/** The configured vision model, when it is usable and accepts images. */
	async visionModel() {
		const v = this.prefs.vision ?? "";
		const at = v.indexOf("/");
		if (at <= 0) return undefined;
		const available = await this.runtime.getAvailable();
		return available.find((m) => m.provider === v.slice(0, at) && m.id === v.slice(at + 1) && (m.input ?? []).includes("image"));
	}

	async describe() {
		const rt = this.runtime;
		const keys = await readJSON(KEYS, {});
		const custom = (await readJSON(MODELS, { providers: {} })).providers ?? {};
		const links = await readJSON(LINKS, {});
		const available = new Set((await rt.getAvailable()).map((m) => `${m.provider}/${m.id}`));
		const providers = rt.getProviders().map((p) => {
			const status = rt.getProviderAuthStatus(p.id);
			const models = rt.getModels(p.id).map((m) => ({
				id: m.id,
				name: m.name ?? m.id,
				reasoning: !!m.reasoning,
				vision: (m.input ?? []).includes("image"),
				context_window: m.contextWindow ?? 0,
				max_tokens: m.maxTokens ?? 0,
				cost_in: m.cost?.input ?? null,
				cost_out: m.cost?.output ?? null,
				cache_read: m.cost?.cacheRead ?? null,
				available: available.has(`${p.id}/${m.id}`),
			}));
			const c = custom[p.id];
			return {
				id: p.id,
				name: p.name ?? p.id,
				base_url: c?.baseUrl ?? p.baseUrl ?? "",
				api: c?.api ?? models[0]?.api ?? "",
				custom: !!c,
				catalog_id: links[p.id]?.catalogId ?? "",
				configured: !!status?.configured,
				auth_source: status?.source ?? "",
				key_hint: mask(keys[p.id] ?? (typeof c?.apiKey === "string" && !c.apiKey.startsWith("$") ? c.apiKey : "")),
				models,
			};
		});
		providers.sort((a, b) => Number(b.configured) - Number(a.configured) || Number(b.custom) - Number(a.custom) || a.name.localeCompare(b.name));
		const cur = await this.currentModel();
		return {
			providers,
			apis: APIS,
			selected: cur ? { provider: cur.provider, model: cur.id, reasoning: !!cur.reasoning, vision: (cur.input ?? []).includes("image") } : null,
			vision_ready: !!(await this.visionModel()),
			prefs: this.prefs,
			catalog_updated: this.catalog.fetchedAt || null,
			pi_cli_available: !!(await readJSON(join(PI_DIR, "models.json"), null)),
			error: rt.getError() ?? null,
		};
	}

	async setPrefs(patch) {
		const allowed = ["provider", "model", "thinking", "persona", "autoTitle", "vision"];
		for (const k of allowed) if (k in patch) this.prefs[k] = patch[k];
		await writeJSON(PREFS, this.prefs, 0o644);
		for (const fn of this.listeners) fn();
	}

	async setKey(provider, apiKey) {
		const keys = await readJSON(KEYS, {});
		if (apiKey) keys[provider] = apiKey;
		else delete keys[provider];
		await writeJSON(KEYS, keys);
		await this.rebuild();
	}

	/** Add or replace a custom compatible endpoint. */
	async upsertProvider({ id, baseUrl, api, apiKey, headers, models, catalogId }) {
		if (!/^[a-z0-9][a-z0-9._-]{0,40}$/i.test(id ?? "")) throw new Error("提供商 ID 只能包含字母、数字、点、下划线和短横线");
		if (!APIS.includes(api)) throw new Error(`不支持的 API 类型: ${api}`);
		if (!/^https?:\/\//.test(baseUrl ?? "")) throw new Error("Base URL 需以 http(s):// 开头");
		const list = (models ?? []).filter((m) => m?.id);
		if (!list.length) throw new Error("至少填写一个模型 ID");
		const file = await readJSON(MODELS, { providers: {} });
		file.providers ??= {};
		const prev = file.providers[id] ?? {};
		const links = await readJSON(LINKS, {});
		if (catalogId) {
			links[id] = { ...(links[id] ?? {}), catalogId };
			await writeJSON(LINKS, links, 0o644);
		}
		const hint = catalogId ?? links[id]?.catalogId;
		file.providers[id] = {
			...prev,
			baseUrl,
			api,
			apiKey: apiKey === undefined ? prev.apiKey : apiKey || "none",
			...(headers && Object.keys(headers).length ? { headers } : {}),
			models: await Promise.all(
				list.map(async (m) => {
					// Fill gaps from models.dev so context limits and prices are known.
					const c = (await this.catalog.lookup(m.id, hint)) ?? {};
					const pick = (a, b) => (a !== undefined && a !== null && a !== "" && a !== 0 ? a : b);
					const ctx = Number(pick(m.context_window, c.context_window)) || 0;
					const out = Number(pick(m.max_tokens, c.max_tokens)) || 0;
					const cin = pick(m.cost_in, c.cost_in);
					const cout = pick(m.cost_out, c.cost_out);
					return {
						id: m.id,
						...(pick(m.name, c.name) && pick(m.name, c.name) !== m.id ? { name: pick(m.name, c.name) } : {}),
						reasoning: m.reasoning ?? c.reasoning ?? false,
						input: (m.vision ?? c.vision) ? ["text", "image"] : ["text"],
						...(ctx ? { contextWindow: ctx } : {}),
						...(out ? { maxTokens: out } : {}),
						...(cin != null || cout != null
							? {
									cost: {
										input: Number(cin ?? 0),
										output: Number(cout ?? 0),
										cacheRead: Number(pick(m.cache_read, c.cache_read) ?? 0),
										cacheWrite: Number(pick(m.cache_write, c.cache_write) ?? 0),
									},
								}
							: {}),
					};
				}),
			),
		};
		await writeJSON(MODELS, file);
		await this.rebuild();
	}

	async removeProvider(id) {
		const file = await readJSON(MODELS, { providers: {} });
		delete file.providers?.[id];
		await writeJSON(MODELS, file);
		const links = await readJSON(LINKS, {});
		delete links[id];
		await writeJSON(LINKS, links, 0o644);
		await this.setKey(id, "");
	}

	/** Copy custom providers and API keys from the Pi CLI (~/.pi/agent). */
	async importPiCli() {
		const src = await readJSON(join(PI_DIR, "models.json"), { providers: {} });
		const auth = await readJSON(join(PI_DIR, "auth.json"), {});
		const file = await readJSON(MODELS, { providers: {} });
		file.providers = { ...(file.providers ?? {}), ...(src.providers ?? {}) };
		await writeJSON(MODELS, file);
		const keys = await readJSON(KEYS, {});
		let keyCount = 0;
		for (const [provider, cred] of Object.entries(auth ?? {})) {
			const key = typeof cred === "string" ? cred : cred?.type === "api_key" ? (cred.key ?? cred.apiKey) : undefined;
			if (key) {
				keys[provider] = key;
				keyCount++;
			}
		}
		await writeJSON(KEYS, keys);
		const settings = await readJSON(join(PI_DIR, "settings.json"), {});
		if (!this.prefs.provider && settings.defaultProvider && settings.defaultModel) {
			this.prefs.provider = settings.defaultProvider;
			this.prefs.model = settings.defaultModel;
			await writeJSON(PREFS, this.prefs, 0o644);
		}
		await this.rebuild();
		return { providers: Object.keys(src.providers ?? {}).length, keys: keyCount };
	}

	/** List model IDs an endpoint offers (OpenAI / Anthropic / Gemini model APIs). */
	async discover({ baseUrl, api, apiKey, provider, catalogId }) {
		if (provider) {
			// Fill whatever the form left blank from the stored provider.
			const custom = (await readJSON(MODELS, { providers: {} })).providers?.[provider];
			const keys = await readJSON(KEYS, {});
			baseUrl ||= custom?.baseUrl;
			api ||= custom?.api;
			apiKey ||= keys[provider] || (typeof custom?.apiKey === "string" && !custom.apiKey.startsWith("$") ? custom.apiKey : "");
		}
		if (!/^https?:\/\//.test(baseUrl ?? "")) throw new Error("Base URL 需以 http(s):// 开头");
		const base = baseUrl.replace(/\/+$/, "");
		let url = `${base}/models`;
		const headers = { Accept: "application/json" };
		if (api === "anthropic-messages") {
			url = /\/v1$/.test(base) ? `${base}/models` : `${base}/v1/models`;
			if (apiKey) headers["x-api-key"] = apiKey;
			headers["anthropic-version"] = "2023-06-01";
		} else if (api === "google-generative-ai") {
			if (apiKey) url += `?key=${encodeURIComponent(apiKey)}`;
		} else if (apiKey && apiKey !== "none") {
			headers.Authorization = `Bearer ${apiKey}`;
		}
		const res = await fetch(url, { headers, signal: AbortSignal.timeout(20_000) });
		const text = await res.text();
		if (!res.ok) throw new Error(`获取模型列表失败（HTTP ${res.status}）：${text.slice(0, 160)}`);
		let data;
		try {
			data = JSON.parse(text);
		} catch {
			throw new Error("服务返回的不是 JSON");
		}
		const list = data.data ?? data.models ?? (Array.isArray(data) ? data : []);
		const ids = list
			.map((m) => (typeof m === "string" ? m : (m.id ?? m.name ?? "")).replace(/^models\//, ""))
			.filter(Boolean);
		const hint = catalogId ?? (provider ? (await readJSON(LINKS, {}))[provider]?.catalogId : undefined) ?? provider;
		return Promise.all(
			[...new Set(ids)].sort().map(async (id) => ({ id, ...((await this.catalog.lookup(id, hint)) ?? { name: id, known: false }) })),
		);
	}

	/** Round-trip a tiny request to verify credentials and endpoint. */
	async test(provider, model) {
		const rt = this.runtime;
		const m = rt.getModel(provider, model) ?? (await rt.getAvailable(provider))[0];
		if (!m) throw new Error("该提供商没有可用模型（检查 API Key）");
		const t0 = Date.now();
		const res = await rt.completeSimple(
			m,
			{ messages: [{ role: "user", content: [{ type: "text", text: "Reply with: ok" }], timestamp: Date.now() }] },
			{ signal: AbortSignal.timeout(30_000), maxTokens: 64 },
		);
		this.usage?.record(entryFrom(res, { purpose: "test" }));
		if (res.stopReason === "error") throw new Error(res.errorMessage ?? "请求失败");
		const reply = res.content.filter((c) => c.type === "text").map((c) => c.text).join("").trim();
		return { model: `${m.provider}/${m.id}`, latency_ms: Date.now() - t0, reply: reply.slice(0, 80) };
	}
}
