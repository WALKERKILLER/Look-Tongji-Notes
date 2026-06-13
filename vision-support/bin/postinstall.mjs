#!/usr/bin/env node

/**
 * vision-support npm postinstall 脚本
 *
 * npm install -g vision-support 后自动运行
 * 安装到所有已知 agent 的 skills 目录（自动创建目录）
 */

import { existsSync, mkdirSync, cpSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PKG_DIR = resolve(__dirname, "..");
const SKILL_NAME = "vision-support";

const KNOWN_AGENTS = [
  { name: "通用 (Pi / Codex)", dir: join(homedir(), ".agents", "skills") },
  { name: "Pi Agent", dir: join(homedir(), ".pi", "agent", "skills") },
  { name: "Claude Code", dir: join(homedir(), ".claude", "skills") },
];

const FILES = [
  ["SKILL.md", "SKILL.md"],
  ["config.example.json", "config.example.json"],
  ["scripts/vision.mjs", "scripts/vision.mjs"],
  ["references/supported-models.md", "references/supported-models.md"],
];

function installSkill() {
  const skillMd = join(PKG_DIR, "SKILL.md");
  if (!existsSync(skillMd)) return;

  const installed = [];

  for (const agent of KNOWN_AGENTS) {
    const dest = join(agent.dir, SKILL_NAME);
    mkdirSync(dest, { recursive: true });

    for (const [src, dst] of FILES) {
      const srcPath = join(PKG_DIR, src);
      const dstPath = join(dest, dst);
      const dstDir = dirname(dstPath);
      if (!existsSync(dstDir)) mkdirSync(dstDir, { recursive: true });
      if (existsSync(srcPath)) cpSync(srcPath, dstPath);
    }

    installed.push(`${agent.name}: ${agent.dir}`);
  }

  if (installed.length > 0) {
    process.stderr.write(
      `\n  ✓ vision-support 已安装到 ${installed.length} 个位置:\n` +
      installed.map((i) => `    - ${i}`).join("\n") +
      `\n  运行 vision-support init 来配置模型\n\n`
    );
  }
}

try {
  installSkill();
} catch {
  // 静默失败，不影响 npm install
}
