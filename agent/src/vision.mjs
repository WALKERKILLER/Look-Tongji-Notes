// Lets the assistant look at slides and courseware figures. A chat model that
// accepts images gets them directly; a text-only model gets a transcription
// from the vision model chosen in settings (cached by image hash), the same
// split as the Look Tongji Notes vision-support skill: the vision model only
// reads images and never takes part in the reasoning.
import { createHash } from "node:crypto";
import { readFile, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fetchBytes } from "./lookd.mjs";
import { DATA_DIR } from "./models.mjs";
import { entryFrom } from "./usage.mjs";

const CACHE = join(DATA_DIR, "vision-cache.json");
const CACHE_MAX = 2000;
const MAX_IMAGES = 6;

const PROMPT = `这是一张课堂 PPT 截图或课件插图。请把图中内容完整转写出来：
- 文字按原有层级逐条写出，不要概括或省略；
- 公式用 LaTeX（行内 $...$，独立 $$...$$）；
- 表格用 Markdown 表格；
- 图示、曲线、示意图用一两句话说明结构、坐标轴、趋势和标注。
只输出内容本身，不要评价，不要解释你在做什么。`;

let cache = null;

async function loadCache() {
	if (!cache) {
		try {
			cache = JSON.parse(await readFile(CACHE, "utf8"));
		} catch {
			cache = {};
		}
	}
	return cache;
}

async function saveCache() {
	const keys = Object.keys(cache);
	if (keys.length > CACHE_MAX) {
		keys.sort((a, b) => cache[a].at - cache[b].at);
		for (const k of keys.slice(0, keys.length - CACHE_MAX)) delete cache[k];
	}
	await writeFile(`${CACHE}.tmp`, JSON.stringify(cache), { mode: 0o600 });
	await rename(`${CACHE}.tmp`, CACHE);
}

async function describe(pipeline, vm, img, signal) {
	const key = `${createHash("sha1").update(img.bytes).digest("hex")}:${vm.provider}/${vm.id}`;
	const c = await loadCache();
	if (c[key]) return c[key].text;
	const res = await pipeline.runtime.completeSimple(
		vm,
		{
			messages: [
				{
					role: "user",
					content: [
						{ type: "text", text: PROMPT },
						{ type: "image", data: img.bytes.toString("base64"), mimeType: img.mimeType },
					],
					timestamp: Date.now(),
				},
			],
		},
		{ signal: AbortSignal.any([signal ?? new AbortController().signal, AbortSignal.timeout(120_000)]), maxTokens: 2000 },
	);
	pipeline.usage?.record(entryFrom(res, { purpose: "vision" }));
	if (res.stopReason === "error") throw new Error(res.errorMessage ?? "识图失败");
	const text = res.content.filter((x) => x.type === "text").map((x) => x.text).join("").trim();
	c[key] = { text, at: Date.now() };
	await saveCache().catch(() => {});
	return text;
}

/**
 * Tool content for images: [{label, path}] where path is a lookd URL path.
 * Returns {content, mode} with mode "image" | "described" | "unavailable".
 */
export async function seeImages(pipeline, images, signal) {
	images = images.slice(0, MAX_IMAGES);
	const model = await pipeline.currentModel();
	const direct = (model?.input ?? []).includes("image");
	const vm = direct ? null : await pipeline.visionModel();
	if (!direct && !vm) {
		return {
			mode: "unavailable",
			content: [
				{
					type: "text",
					text:
						"当前对话模型不能看图，也没有设置识图模型（设置 → 助手 → 识图模型），无法查看这些图片：\n" +
						images.map((i) => `- ${i.label}`).join("\n") +
						"\n请仅依据字幕和课件文字继续，并在回复里提醒用户可以设置识图模型以校对 PPT。",
				},
			],
		};
	}
	const loaded = await Promise.all(
		images.map(async (i) => {
			try {
				return { ...i, img: await fetchBytes(i.path) };
			} catch (e) {
				return { ...i, error: e.message };
			}
		}),
	);
	const content = [];
	if (direct) {
		for (const i of loaded) {
			content.push({ type: "text", text: i.error ? `${i.label}：无法获取（${i.error}）` : i.label });
			if (!i.error) content.push({ type: "image", data: i.img.bytes.toString("base64"), mimeType: i.img.mimeType });
		}
		return { mode: "image", content };
	}
	// Describe up to three at a time with the vision model.
	const texts = new Array(loaded.length);
	for (let k = 0; k < loaded.length; k += 3) {
		await Promise.all(
			loaded.slice(k, k + 3).map(async (i, j) => {
				if (i.error) {
					texts[k + j] = `${i.label}：无法获取（${i.error}）`;
					return;
				}
				try {
					texts[k + j] = `${i.label}（识图模型转写）：\n${await describe(pipeline, vm, i.img, signal)}`;
				} catch (e) {
					texts[k + j] = `${i.label}：识图失败（${e.message}）`;
				}
			}),
		);
	}
	content.push({ type: "text", text: texts.join("\n\n---\n\n") });
	return { mode: "described", content };
}
