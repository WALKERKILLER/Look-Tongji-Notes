#!/usr/bin/env node
// verify-decisions.mjs — decision log gate.
// Enforces the MADR-based decision log contract in docs/decisions/:
//   - file naming NNNN-title.md, unique sequential numbering
//   - required sections, in order
//   - valid status values
//   - valid Class: extension values when present
//   - "Superseded by NNNN" targets that exist
// Zero dependencies; Node >= 18. Exits non-zero on any violation.
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { pathToFileURL } from 'node:url';
import { governancePaths, readRepoManifest } from './governance-config.mjs';

export const DECISIONS_DIR = 'docs/decisions';
export const REQUIRED_SECTIONS = [
  'Status',
  'Context and Problem Statement',
  'Decision Drivers',
  'Considered Options',
  'Decision Outcome',
  'Pros and Cons of the Options',
  'Links',
];
export const VALID_STATUSES = new Set(['Proposed', 'Accepted', 'Rejected', 'Deprecated']);
export const SUPERSEDED_PREFIX = 'Superseded by ';
export const VALID_CLASSES = new Set([
  'architecture',
  'process',
  'testing',
  'feature',
  'bug-fix',
  'simplification',
]);

export function sectionOrder(text) {
  const re = /^## (.+)$/gm;
  const names = [];
  let m;
  while ((m = re.exec(text)) !== null) names.push(m[1].trim());
  if (names[0] !== 'Status') return false;
  const positions = REQUIRED_SECTIONS.map((s) => names.indexOf(s));
  if (positions.some((p) => p === -1)) return false;
  for (let i = 1; i < positions.length; i++) {
    if (positions[i] < positions[i - 1]) return false;
  }
  return true;
}

export function checkStatusAndClass(f, text, nums, errors) {
  const statusMatch = text.match(/^## Status\n+([^\n]+)/m);
  if (!statusMatch) {
    errors.push(`${f}: missing status value`);
    return;
  }
  const statusLine = statusMatch[1].trim();
  let statusOk = VALID_STATUSES.has(statusLine);
  if (!statusOk && statusLine.startsWith(SUPERSEDED_PREFIX)) {
    const num = statusLine.match(/(\d{4})/);
    if (num && nums.includes(Number(num[1]))) {
      statusOk = true;
    } else {
      errors.push(`${f}: superseded target missing or does not exist: "${statusLine}"`);
    }
  }
  if (!statusOk) errors.push(`${f}: invalid status "${statusLine}"`);

  // Class extension: first non-empty line after the status value line.
  const lines = text.split('\n');
  let idx = lines.findIndex((l) => l.startsWith('## Status'));
  idx += 1;
  while (idx < lines.length && lines[idx].trim() === '') idx++; // status value
  idx += 1;
  while (idx < lines.length && lines[idx].trim() === '') idx++; // possible Class line
  if (idx < lines.length && lines[idx].trim().startsWith('Class: ')) {
    const cls = lines[idx].trim().slice('Class: '.length).trim();
    if (!VALID_CLASSES.has(cls)) errors.push(`${f}: invalid Class "${cls}"`);
  }
}

export async function verifyDir(dirPath) {
  const errors = [];
  let entries;
  try {
    entries = await readdir(dirPath, { withFileTypes: true });
  } catch {
    errors.push(`decisions directory missing: ${dirPath}`);
    return errors;
  }
  const files = entries
    .filter((e) => e.isFile() && /^\d{4}-.+\.md$/.test(e.name))
    .map((e) => e.name)
    .sort();
  const nums = files.map((f) => Number(f.slice(0, 4)));
  const seen = new Set();
  for (const n of nums) {
    if (seen.has(n)) errors.push(`duplicate decision number ${String(n).padStart(4, '0')}`);
    seen.add(n);
  }
  for (let i = 0; i < nums.length; i++) {
    if (nums[i] !== i) {
      errors.push(`decision numbers must be sequential starting at 0; found ${files[i]}`);
      break;
    }
  }
  for (const f of files) {
    const text = await readFile(path.join(dirPath, f), 'utf8');
    if (!sectionOrder(text)) errors.push(`${f}: required sections missing or out of order`);
    checkStatusAndClass(f, text, nums, errors);
  }
  return errors;
}

async function main() {
  const repoRoot = process.cwd();
  const manifest = await readRepoManifest(repoRoot);
  const dir = process.argv[2] ?? path.join(repoRoot, governancePaths(manifest).decisions);
  const errors = await verifyDir(dir);
  if (errors.length) {
    for (const e of errors) console.error(`verify-decisions: ${e}`);
    process.exit(1);
  }
  const entries = await readdir(dir, { withFileTypes: true });
  const count = entries.filter((e) => e.isFile() && /^\d{4}-.+\.md$/.test(e.name)).length;
  console.log(`verify-decisions: OK (${count} records)`);
}

const isMain =
  process.argv[1] &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (isMain) {
  main().catch((e) => {
    console.error('verify-decisions: fatal', e);
    process.exit(2);
  });
}
