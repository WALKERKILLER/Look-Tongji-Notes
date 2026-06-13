#!/usr/bin/env node

/**
 * vision-support CLI 入口（npm 全局安装后使用）
 *
 * 用法:
 *   vision-support <图片...> [prompt]       识图
 *   vision-support init                     初始化
 *   vision-support config <cmd> [args]      配置管理
 *
 * 本文件是 npm bin 入口，实际逻辑在 scripts/vision.mjs
 */

import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { existsSync } from "node:fs";
import { homedir } from "node:os";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PKG_DIR = resolve(__dirname, "..");
const SKILL_NAME = "vision-support";

/**
 * 找到 vision.mjs 的位置
 * 1) npm 安装：在同目录的 scripts/vision.mjs
 * 2) skill 安装：在 ~/.agents/skills/vision-support/scripts/vision.mjs
 */
function findScript() {
  // 优先用包内的
  const local = join(PKG_DIR, "scripts", "vision.mjs");
  if (existsSync(local)) return local;

  // 回退到 skill 目录
  const home = homedir();
  const candidates = [
    join(home, ".agents", "skills", SKILL_NAME, "scripts", "vision.mjs"),
    join(home, ".pi", "agent", "skills", SKILL_NAME, "scripts", "vision.mjs"),
  ];
  for (const p of candidates) {
    if (existsSync(p)) return p;
  }

  console.error(`✖ 找不到 vision.mjs，请重新安装: npm install -g vision-support`);
  process.exit(1);
}

// 直接把参数透传给 vision.mjs
const scriptPath = findScript();
const args = process.argv.slice(2).map((a) => `"${a.replace(/"/g, '\\"')}"`).join(" ");

// 用动态 import 的方式不太好控制进程退出，直接用 child_process
import { execFileSync } from "node:child_process";
try {
  const result = execFileSync("node", [scriptPath, ...process.argv.slice(2)], {
    stdio: "inherit",
    env: { ...process.env },
    timeout: 120000,
  });
} catch (err) {
  // execFileSync 在非零退出码时会 throw，但 stdio: inherit 已经输出了内容
  // 只需要传递退出码
  if (err.status) process.exit(err.status);
}
