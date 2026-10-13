// models.dev catalog: provider directory plus per-model prices and limits.
// Cached in AGENT_DATA_DIR/models-dev.json and refreshed at most daily, so the
// model screen works offline after the first fetch.
import { readFile, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";

const SOURCE = "https://models.dev/api.json";
const TTL = 24 * 3600 * 1000;

// models.dev names the AI SDK package; map it to the Pi API type.
const API_OF = {
	"@ai-sdk/openai-compatible": "openai-completions",
	"@ai-sdk/openai": "openai-responses",
	"@ai-sdk/anthropic": "anthropic-messages",
	"@ai-sdk/google": "google-generative-ai",
	"@openrouter/ai-sdk-provider": "openai-completions",
	"@ai-sdk/xai": "openai-completions",
	"@ai-sdk/togetherai": "openai-completions",
	"@ai-sdk/perplexity": "openai-completions",
	"@ai-sdk/deepseek": "openai-completions",
	"@ai-sdk/mistral": "openai-completions",
	"@ai-sdk/groq": "openai-completions",
	"@ai-sdk/cerebras": "openai-completions",
	"@ai-sdk/fireworks": "openai-completions",
	"@ai-sdk/deepinfra": "openai-completions",
};

// Base URLs for first-party SDK providers that models.dev leaves implicit.
const BASE_OF = {
	openai: "https://api.openai.com/v1",
	anthropic: "https://api.anthropic.com",
	google: "https://generativelanguage.googleapis.com/v1beta",
	deepseek: "https://api.deepseek.com/v1",
	mistral: "https://api.mistral.ai/v1",
	groq: "https://api.groq.com/openai/v1",
	xai: "https://api.x.ai/v1",
	togetherai: "https://api.together.xyz/v1",
	perplexity: "https://api.perplexity.ai",
	cerebras: "https://api.cerebras.ai/v1",
	"fireworks-ai": "https://api.fireworks.ai/inference/v1",
	deepinfra: "https://api.deepinfra.com/v1/openai",
};

// When a bare model ID appears under several providers, prefer the maker.
const PRIORITY = ["openai", "anthropic", "google", "deepseek", "moonshotai", "moonshotai-cn", "zhipuai", "alibaba", "alibaba-cn", "xai", "mistral", "minimax", "openrouter"];

export class Catalog {
	constructor(dataDir) {
		this.file = join(dataDir, "models-dev.json");
		this.data = null;
		this.fetchedAt = 0;
		this.index = null;
		this.pending = null;
	}

	async load({ refresh = false } = {}) {
		if (this.data && !refresh && Date.now() - this.fetchedAt < TTL) return this.data;
		if (this.pending) return this.pending;
		this.pending = (async () => {
			if (!this.data) {
				try {
					this.data = JSON.parse(await readFile(this.file, "utf8"));
					this.fetchedAt = (await stat(this.file)).mtimeMs;
					this.index = null;
				} catch {}
			}
			if (refresh || !this.data || Date.now() - this.fetchedAt >= TTL) {
				try {
					const res = await fetch(SOURCE, { signal: AbortSignal.timeout(30_000) });
					if (!res.ok) throw new Error(`HTTP ${res.status}`);
					const text = await res.text();
					this.data = JSON.parse(text);
					this.fetchedAt = Date.now();
					this.index = null;
					await writeFile(this.file, text);
				} catch (e) {
					if (!this.data) throw new Error(`无法获取 models.dev 目录：${e.message}`);
				}
			}
			return this.data;
		})().finally(() => {
			this.pending = null;
		});
		return this.pending;
	}

	async providers(opts) {
		const d = await this.load(opts);
		return Object.values(d)
			.map((p) => ({
				id: p.id,
				name: p.name,
				api: API_OF[p.npm] ?? null,
				base_url: p.api ?? BASE_OF[p.id] ?? "",
				doc: p.doc ?? "",
				env: p.env ?? [],
				models: Object.keys(p.models ?? {}).length,
				logo: `https://models.dev/logos/${p.id}.svg`,
			}))
			.filter((p) => p.api && p.base_url && !p.base_url.includes("${"))
			.sort((a, b) => a.name.localeCompare(b.name));
	}

	async providerModels(id) {
		const d = await this.load();
		return Object.values(d[id]?.models ?? {})
			.map((m) => ({ id: m.id, ...meta(m) }))
			.sort((a, b) => (b.release_date ?? "").localeCompare(a.release_date ?? ""));
	}

	/** Metadata for a model ID, preferring the given models.dev provider. */
	async lookup(id, providerHint) {
		const d = await this.load().catch(() => null);
		if (!d || !id) return null;
		if (providerHint && d[providerHint]?.models?.[id]) return meta(d[providerHint].models[id]);
		if (!this.index) {
			this.index = new Map();
			const order = [...PRIORITY.filter((p) => d[p]), ...Object.keys(d).filter((p) => !PRIORITY.includes(p))];
			for (const pid of order) {
				for (const m of Object.values(d[pid].models ?? {})) {
					for (const key of [m.id.toLowerCase(), m.id.toLowerCase().split("/").pop()]) {
						if (!this.index.has(key)) this.index.set(key, m);
					}
				}
			}
		}
		const k = id.toLowerCase();
		const m = this.index.get(k) ?? this.index.get(k.split("/").pop()) ?? this.index.get(k.replace(/:.*$/, ""));
		return m ? meta(m) : null;
	}
}

function meta(m) {
	return {
		name: m.name ?? m.id,
		context_window: m.limit?.context ?? 0,
		max_tokens: m.limit?.output ?? 0,
		cost_in: m.cost?.input ?? null,
		cost_out: m.cost?.output ?? null,
		cache_read: m.cost?.cache_read ?? null,
		cache_write: m.cost?.cache_write ?? null,
		reasoning: !!m.reasoning,
		vision: (m.modalities?.input ?? []).includes("image") || !!m.attachment,
		tool_call: m.tool_call !== false,
		knowledge: m.knowledge ?? "",
		release_date: m.release_date ?? "",
		deprecated: m.status === "deprecated",
	};
}
