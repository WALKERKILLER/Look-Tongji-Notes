#!/usr/bin/env node
// verify-placeholders.mjs — placeholder gate.
// Flags fill-in tokens (__UPPERCASE__) left in seeded documentation and skills.
// Scope: AGENTS.md, CLAUDE.md, docs/**, .agents/skills/repo-review, .agents/skills/repo-decisions, CONTRIBUTING.md.
// Zero dependencies; Node >= 18. Exits non-zero on any violation.
import { readdir, stat, readFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { pathToFileURL } from 'node:url';

export const SCOPED_PATHS = [
  'AGENTS.md',
  'CLAUDE.md',
  'docs',
  'CONTRIBUTING.md',
  '.agents/skills/repo-review/SKILL.md',
  '.agents/skills/repo-decisions/SKILL.md',
  '.agents/skills/repo-governance/SKILL.md',
  'SECURITY.md',
  'CODE_OF_CONDUCT.md',
  'CODEOWNERS',
  '.github/workflows',
];

const TOKEN_RE = /__[A-Z][A-Z0-9_]*__/g;

// No fill-in token may remain in shipped content. The model resolves every
// token during instantiation; the gate fails on any survivor.
const ALLOWED_TOKENS = new Set();

export function findPlaceholders(text) {
  const found = [];
  let m;
  while ((m = TOKEN_RE.exec(text)) !== null) {
    if (!ALLOWED_TOKENS.has(m[0])) found.push(m[0]);
  }
  return found;
}

export async function collectScopedFiles(repoRoot) {
  const files = [];
  async function walk(dir, prefix) {
    let entries;
    try {
      entries = await readdir(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      if (e.name === '.git' || e.name === 'node_modules' || e.name === '.repo-seed') continue;
      const full = path.join(dir, e.name);
      if (e.isDirectory()) {
        await walk(full, path.join(prefix, e.name));
      } else if (e.name.endsWith('.md') || e.name.endsWith('.yml') || e.name.endsWith('.yaml')) {
        files.push(path.join(prefix, e.name));
      }
    }
  }
  for (const p of SCOPED_PATHS) {
    const abs = path.join(repoRoot, p);
    let st;
    try {
      st = await stat(abs);
    } catch {
      continue;
    }
    if (st.isDirectory()) {
      await walk(abs, p);
    } else if (st.isFile()) {
      files.push(p);
    }
  }
  return files;
}

export async function verifyPlaceholders(repoRoot) {
  const errors = [];
  const files = await collectScopedFiles(repoRoot);
  for (const f of files) {
    const text = await readFile(path.join(repoRoot, f), 'utf8');
    const tokens = findPlaceholders(text);
    for (const t of tokens) {
      errors.push(`${f}: placeholder ${t} left in shipped content`);
    }
  }
  return { errors, files };
}

async function main() {
  const repoRoot = path.resolve(process.argv[2] ?? '.');
  const { errors, files } = await verifyPlaceholders(repoRoot);
  if (errors.length) {
    for (const e of errors) console.error(`verify-placeholders: ${e}`);
    process.exit(1);
  }
  console.log(`verify-placeholders: OK (${files.length} files)`);
}

const isMain =
  process.argv[1] &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (isMain) {
  main().catch((e) => {
    console.error('verify-placeholders: fatal', e);
    process.exit(2);
  });
}
