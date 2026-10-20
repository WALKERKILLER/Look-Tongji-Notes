import assert from "node:assert/strict";
import { mkdtemp, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { checkPath, hashOf, MAX_FILE, MemoryStore, memoryTools, sensitiveKind } from "./memory.mjs";

async function store() {
	const dir = await mkdtemp(join(tmpdir(), "look-memory-"));
	const s = new MemoryStore(join(dir, "memory"));
	await s.init();
	return { s, done: () => rm(dir, { recursive: true, force: true }) };
}

test("paths are limited to the memory layout", () => {
	for (const ok of ["profile.md", "preferences.md", "routines/weekly-review.md", "courses/12345.md", "notes/a_b.md"]) assert.equal(checkPath(ok), ok);
	for (const badPath of ["../x.md", "notes/../profile.md", "notes/A.md", "other.md", "notes/x.txt", "routines/.md", "/etc/passwd", "notes/a/b.md"]) {
		assert.throws(() => checkPath(badPath), /路径无效/);
	}
});

test("the guard rejects sensitive values and keeps ordinary text", () => {
	assert.equal(sensitiveKind("身份证 11010519491231002X"), "身份证号");
	assert.equal(sensitiveKind("卡号 4111 1111 1111 1111"), "银行卡号");
	assert.equal(sensitiveKind("电话 13812345678"), "手机号");
	assert.equal(sensitiveKind("key sk-abcdefghijklmnop1234"), "密钥");
	assert.equal(sensitiveKind("统一身份认证密码是 hunter2"), "密码");
	assert.equal(sensitiveKind("每周三复习高数，第 3 节 12:30 开始；时间戳 1760000000000"), null);
	assert.equal(sensitiveKind("见 look://lecture/4111111111111111"), null);
	assert.equal(sensitiveKind("忘记密码怎么办"), null);
});

test("writes need the version that was read, and conflicts return the current text", async () => {
	const { s, done } = await store();
	try {
		const a = await s.write("profile.md", "---\ntitle: 我\n---\n大二，土木\n");
		assert.equal(a.action, "created");
		await assert.rejects(s.write("profile.md", "x"), (e) => e.status === 409 && e.current.content.includes("大二"));
		await assert.rejects(s.write("profile.md", "x", "000000000000"), (e) => e.status === 409);
		const b = await s.write("profile.md", "大三\n", a.hash);
		assert.equal(b.action, "updated");
		assert.equal(b.hash, hashOf("大三\n"));
		const st = await stat(join(s.dir, "profile.md"));
		assert.equal(st.mode & 0o777, 0o600);
	} finally {
		await done();
	}
});

test("edit replaces exactly one passage; append creates and extends", async () => {
	const { s, done } = await store();
	try {
		await s.append("notes/habits.md", "- 喜欢 1.5 倍速");
		await s.append("notes/habits.md", "- 先看大纲");
		assert.equal((await s.read("notes/habits.md")).content, "- 喜欢 1.5 倍速\n- 先看大纲\n");
		await assert.rejects(s.edit("notes/habits.md", "不存在", "x"), /没有找到/);
		await s.append("notes/habits.md", "- 先看大纲");
		await assert.rejects(s.edit("notes/habits.md", "先看大纲", "x"), /出现了 2 次/);
		await s.edit("notes/habits.md", "1.5 倍速", "2 倍速");
		assert.match((await s.read("notes/habits.md")).content, /2 倍速/);
		await assert.rejects(s.append("notes/habits.md", "手机 13812345678"), /手机号/);
		await assert.rejects(s.write("notes/big.md", "x".repeat(MAX_FILE + 1)), /16 KB/);
		await s.remove("notes/habits.md");
		await assert.rejects(s.read("notes/habits.md"), (e) => e.status === 404);
	} finally {
		await done();
	}
});

test("the prompt pins profile and preferences and indexes the rest, routines first", async () => {
	const { s, done } = await store();
	try {
		assert.equal(await s.prompt(), "");
		await s.write("notes/zz.md", "---\ntitle: 杂项\ndescription: 零碎\n---\n");
		await s.write("routines/review.md", "---\ntitle: 周复习\nwhen: 周日晚上\n---\n步骤");
		await s.write("preferences.md", "回答简短");
		await s.write("profile.md", "土木大三");
		const p = await s.prompt();
		assert.ok(p.indexOf("profile.md") < p.indexOf("preferences.md"));
		assert.match(p, /土木大三[\s\S]*回答简短/);
		assert.ok(p.indexOf("routines/review.md · 周复习") < p.indexOf("notes/zz.md · 杂项 — 零碎"));
		assert.match(p, /适用：周日晚上/);
		assert.doesNotMatch(p, /步骤/);
		assert.doesNotMatch(await s.prompt({ pinnedOnly: true }), /routines/);
	} finally {
		await done();
	}
});

test("concurrent appends are all kept", async () => {
	const { s, done } = await store();
	try {
		await Promise.all(Array.from({ length: 20 }, (_, i) => s.append("notes/log.md", `- ${i}`)));
		assert.equal((await s.read("notes/log.md")).content.trim().split("\n").length, 20);
	} finally {
		await done();
	}
});

test("tools report changes and consolidation gets no delete", async () => {
	const { s, done } = await store();
	try {
		const seen = [];
		const tools = memoryTools(s, { onChange: (r) => seen.push(r.action) });
		assert.ok(tools.some((t) => t.name === "memory_delete"));
		assert.ok(!memoryTools(s, { allowDelete: false }).some((t) => t.name === "memory_delete"));
		const by = Object.fromEntries(tools.map((t) => [t.name, t]));
		const r = await by.memory_write.execute("1", { path: "notes/a.md", content: "hi" });
		assert.match(r.content[0].text, /已新建 notes\/a\.md/);
		const read = await by.memory_read.execute("2", { path: "notes/a.md" });
		assert.match(read.content[0].text, new RegExp(hashOf("hi")));
		await by.memory_delete.execute("3", { path: "notes/a.md" });
		assert.deepEqual(seen, ["created", "deleted"]);
	} finally {
		await done();
	}
});
