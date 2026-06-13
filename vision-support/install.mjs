#!/usr/bin/env node

/**
 * vision-support 安装脚本
 *
 * 用法:
 *   node install.mjs              # 交互式选择安装到哪个 agent（默认全局）
 *   node install.mjs --all        # 装到所有已知 agent
 *   node install.mjs --local      # 装到当前项目目录
 *   node install.mjs --dir <path> # 指定目录
 *   node install.mjs --uninstall  # 卸载
 *
 * 一行安装:
 *   git clone https://github.com/penfick/skills.git /tmp/skills && node /tmp/skills/vision-support/install.mjs
 *   Mac/Linux: bash -c "$(curl -fsSL https://raw.githubusercontent.com/penfick/skills/main/vision-support/install.sh)"
 */

import {
  existsSync,
  mkdirSync,
  rmSync,
  cpSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { join, dirname, resolve } from "node:path";
import { homedir } from "node:os";
import { execSync } from "node:child_process";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const SOURCE_DIR = resolve(__dirname);
const SKILL_NAME = "vision-support";

// ---------------------------------------------------------------------------
// 已知 agent 安装位置
// ---------------------------------------------------------------------------

const KNOWN_AGENTS = [
  {
    id: "common",
    name: "通用 Agent Skills",
    desc: "Pi / Codex / Cursor / Trae / Windsurf 等所有支持 Agent Skills 标准的工具",
    dir: join(homedir(), ".agents", "skills"),
  },
  {
    id: "claude",
    name: "Claude Code",
    desc: "~/.claude/skills/",
    dir: join(homedir(), ".claude", "skills"),
  },
];

// ---------------------------------------------------------------------------
// 工具函数
// ---------------------------------------------------------------------------

function ask(question) {
  return new Promise((resolve) => {
    const r = createInterface({ input: process.stdin, output: process.stdout });
    r.question(`  ${question}: `, (answer) => {
      r.close();
      resolve((answer.trim() || "").trim());
    });
  });
}

function askConfirm(question, defaultYes = true) {
  return new Promise((resolve) => {
    const r = createInterface({ input: process.stdin, output: process.stdout });
    const hint = defaultYes ? "[Y/n]" : "[y/N]";
    r.question(`  ${question} ${hint}: `, (answer) => {
      r.close();
      const a = answer.trim().toLowerCase();
      resolve(!a ? defaultYes : a === "y" || a === "yes");
    });
  });
}

function banner(text) {
  const line = "─".repeat(46);
  process.stdout.write(`\n  ┌${line}┐\n`);
  process.stdout.write(`  │${text.padStart((46 + text.length) / 2).padEnd(46)}│\n`);
  process.stdout.write(`  └${line}┘\n\n`);
}

// ---------------------------------------------------------------------------
// 复制 skill 文件
// ---------------------------------------------------------------------------

const FILES_TO_COPY = [
  "SKILL.md",
  "config.example.json",
  join("scripts", "vision.mjs"),
  join("references", "supported-models.md"),
];

function copySkill(destDir) {
  // 备份用户配置（如果有）
  const configPath = join(destDir, "config.json");
  let userConfig = null;
  if (existsSync(configPath)) {
    try { userConfig = readFileSync(configPath, "utf-8"); } catch {}
  }

  mkdirSync(destDir, { recursive: true });
  for (const f of FILES_TO_COPY) {
    const src = join(SOURCE_DIR, f);
    const dst = join(destDir, f);
    const dstDir = dirname(dst);
    if (!existsSync(dstDir)) mkdirSync(dstDir, { recursive: true });
    if (existsSync(src)) cpSync(src, dst);
  }

  // 恢复用户配置
  if (userConfig) {
    writeFileSync(configPath, userConfig, "utf-8");
  }
}

// ---------------------------------------------------------------------------
// 安装
// ---------------------------------------------------------------------------

async function install(opts) {
  // --local: 装到当前项目
  if (opts.local) {
    const destDir = join(process.cwd(), ".agents", "skills", SKILL_NAME);
    banner(`${SKILL_NAME} 安装（项目级）`);
    copySkill(destDir);
    process.stdout.write(`\n  ✓ 已安装到: ${destDir}\n\n`);
    return;
  }

  // --dir: 指定目录
  if (opts.dir) {
    const destDir = join(resolve(opts.dir), SKILL_NAME);
    banner(`${SKILL_NAME} 安装`);
    copySkill(destDir);
    process.stdout.write(`\n  ✓ 已安装到: ${destDir}\n`);
    showNextSteps(destDir);
    return;
  }

  // --all: 全装
  if (opts.all) {
    banner(`${SKILL_NAME} 安装`);
    installToAgents(KNOWN_AGENTS);
    return;
  }

  // 交互式选择
  banner(`${SKILL_NAME} 安装`);

  process.stdout.write(`  选择要安装到哪些 agent:\n\n`);
  KNOWN_AGENTS.forEach((agent, i) => {
    process.stdout.write(`    ${i + 1}. ${agent.name}\n`);
    process.stdout.write(`       ${agent.desc}\n\n`);
  });
  process.stdout.write(`    ${KNOWN_AGENTS.length + 1}. ALL  全部安装\n\n`);

  const input = await ask(`请选择 (1-${KNOWN_AGENTS.length + 1}，可多选如 "1 2")`);

  if (!input) {
    process.stdout.write("  已取消\n");
    process.exit(0);
  }

  if (input.toLowerCase() === "all" || input === String(KNOWN_AGENTS.length + 1)) {
    installToAgents(KNOWN_AGENTS);
    return;
  }

  const nums = input.split(/[\s,]+/).map((s) => parseInt(s, 10))
    .filter((n) => n >= 1 && n <= KNOWN_AGENTS.length);

  if (nums.length > 0) {
    const selected = nums.map((n) => KNOWN_AGENTS[n - 1]);
    installToAgents(selected);
    return;
  }

  process.stdout.write("  已取消\n");
}

function installToAgents(agents) {
  process.stdout.write(`\n`);
  const installed = [];

  for (const agent of agents) {
    const destDir = join(agent.dir, SKILL_NAME);

    // 备份用户配置
    const configPath = join(destDir, "config.json");
    let userConfig = null;
    if (existsSync(configPath)) {
      try { userConfig = readFileSync(configPath, "utf-8"); } catch {}
    }

    if (existsSync(destDir)) rmSync(destDir, { recursive: true, force: true });
    copySkill(destDir);

    // 恢复用户配置
    if (userConfig) {
      writeFileSync(configPath, userConfig, "utf-8");
    }

    process.stdout.write(`    ✓ ${agent.name}\n`);
    process.stdout.write(`      ${destDir}\n\n`);
    installed.push(destDir);
  }

  process.stdout.write(`  共安装到 ${installed.length} 个位置\n`);
  showNextSteps(installed[0]);
}

async function showNextSteps(destDir) {
  process.stdout.write(`\n  ━━━ 下一步 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n`);
  process.stdout.write(`  初始化模型配置:\n\n`);
  process.stdout.write(`    node ${join(destDir, "scripts", "vision.mjs")} init\n\n`);

  const doInit = await askConfirm("是否现在初始化？", true);
  if (doInit) {
    process.stdout.write("\n");
    try {
      execSync(`node "${join(destDir, "scripts", "vision.mjs")}" init`, { stdio: "inherit" });
    } catch {}
  }

  process.stdout.write(`\n  ✓ 安装完成！\n\n`);
}

// ---------------------------------------------------------------------------
// 卸载
// ---------------------------------------------------------------------------

async function uninstall() {
  banner(`${SKILL_NAME} 卸载`);

  const locations = [
    ...KNOWN_AGENTS.map((a) => ({ name: a.name, dir: join(a.dir, SKILL_NAME) })),
    { name: "当前项目", dir: join(process.cwd(), ".agents", "skills", SKILL_NAME) },
  ];

  const installed = locations.filter((l) => existsSync(l.dir));

  if (installed.length === 0) {
    process.stdout.write("  未检测到已安装的 vision-support\n");
    process.exit(0);
  }

  process.stdout.write("  检测到安装:\n\n");
  for (const l of installed) {
    process.stdout.write(`    - ${l.name}: ${l.dir}\n`);
  }

  const confirm = await askConfirm("\n  确认卸载以上所有？", false);
  if (!confirm) {
    process.stdout.write("  已取消\n");
    process.exit(0);
  }

  for (const l of installed) {
    rmSync(l.dir, { recursive: true, force: true });
    process.stdout.write(`  ✓ 已删除: ${l.name}\n`);
  }

  process.stdout.write("\n  ✓ 卸载完成\n");
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

const args = process.argv.slice(2);

if (args.includes("--uninstall") || args.includes("-u")) {
  uninstall();
} else {
  install({
    all: args.includes("--all"),
    local: args.includes("--local") || args.includes("-l"),
    dir: (() => {
      const i = args.indexOf("--dir");
      return i >= 0 ? args[i + 1] : null;
    })(),
  });
}
