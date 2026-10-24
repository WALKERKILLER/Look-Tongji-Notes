import assert from "node:assert/strict";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { SessionManager } from "@earendil-works/pi-coding-agent";
import { Sessions } from "./sessions.mjs";

/** A conversation file as another device wrote it, with that device's library as cwd. */
async function syncedSession(dir, id, cwd) {
	const at = new Date().toISOString();
	const lines = [
		{ type: "session", version: 3, id, timestamp: at, cwd },
		{ type: "message", id: "m1", parentId: null, timestamp: at, message: { role: "user", content: "第三讲讲了什么", timestamp: Date.now() } },
	];
	const path = join(dir, `${at.replace(/[:.]/g, "-")}_${id}.jsonl`);
	await writeFile(path, lines.map((l) => JSON.stringify(l)).join("\n") + "\n");
	return path;
}

test("a conversation synced from another device is listed, found and continues in this library", async () => {
	const dir = await mkdtemp(join(tmpdir(), "sessions-"));
	const here = await mkdtemp(join(tmpdir(), "library-"));
	const path = await syncedSession(dir, "phone-1", "/data/user/0/cn.lookstudio.look_studio/files/LookStudio");
	// What Pi does on its own: the other device's conversation is invisible.
	assert.equal(SessionManager.findById(here, "phone-1", dir), undefined);

	const s = new Sessions(dir, here);
	assert.deepEqual((await s.list()).map((x) => x.id), ["phone-1"]);
	assert.equal(await s.find("phone-1"), path);
	assert.equal(await s.find("missing"), undefined);
	const sm = s.open(path);
	assert.equal(sm.getSessionId(), "phone-1");
	assert.equal(sm.getCwd(), here);
	assert.equal(sm.getBranch().filter((e) => e.type === "message").length, 1);
});
