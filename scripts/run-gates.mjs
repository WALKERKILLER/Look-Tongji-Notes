#!/usr/bin/env node
// run-gates.mjs — execute all installed repo-seed governance gates.
import { readFile, stat } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import path from 'node:path';
import process from 'node:process';
import { pathToFileURL } from 'node:url';

const EXCLUDED = new Set(['scripts/verify-commit-msg.mjs']);

export function governanceGatePaths(manifest) {
  const seen = new Set();
  const paths = [];
  for (const entry of manifest?.files ?? []) {
    if (entry.category !== 'gate' || !/^scripts\/verify-.+\.mjs$/.test(entry.path) || EXCLUDED.has(entry.path)) continue;
    const state = entry.capability ? manifest?.capabilities?.items?.[entry.capability]?.state : null;
    if (state && state !== 'enabled') continue;
    if (!seen.has(entry.path)) paths.push(entry.path);
    seen.add(entry.path);
  }
  return paths;
}

function run(command, args, cwd) {
  return new Promise((resolve) => {
    const child = spawn(command, args, { cwd, stdio: 'inherit' });
    child.on('error', () => resolve(2));
    child.on('exit', (code) => resolve(code ?? 2));
  });
}

export async function runGates(repoRoot, { staged = false } = {}) {
  let manifest;
  try { manifest = JSON.parse(await readFile(path.join(repoRoot, '.repo-seed', 'manifest.json'), 'utf8')); }
  catch { return { errors: ['cannot read .repo-seed/manifest.json'], gates: [] }; }
  const gates = governanceGatePaths(manifest);
  const errors = [];
  for (const rel of gates) {
    try { const file = await stat(path.join(repoRoot, rel)); if (!file.isFile()) throw new Error('not a file'); }
    catch { errors.push(`${rel}: gate file missing`); continue; }
    const code = await run(process.execPath, [rel], repoRoot);
    if (code !== 0) errors.push(`${rel}: exited ${code}`);
  }
  if (staged) {
    const code = await run('git', ['diff', '--cached', '--check'], repoRoot);
    if (code !== 0) errors.push(`git diff --cached --check: exited ${code}`);
  }
  return { errors, gates };
}

async function main() {
  const staged = process.argv.includes('--staged');
  const repoRoot = path.resolve(process.argv.find((arg, index) => index > 1 && !arg.startsWith('--')) ?? '.');
  const { errors, gates } = await runGates(repoRoot, { staged });
  if (errors.length) {
    for (const error of errors) console.error(`run-gates: ${error}`);
    process.exit(1);
  }
  console.log(`run-gates: OK (${gates.length} governance gates${staged ? ' + staged whitespace' : ''})`);
}

const isMain = process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (isMain) main().catch((error) => { console.error(`run-gates: fatal ${error.message}`); process.exit(2); });
