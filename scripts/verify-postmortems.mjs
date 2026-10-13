#!/usr/bin/env node
// verify-postmortems.mjs — incident feedback-loop gate.
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { pathToFileURL } from 'node:url';
import { artifactVersion, grandfatheredArtifact, governancePaths, readRepoManifest } from './governance-config.mjs';

export const POSTMORTEM_SECTIONS = ['Executive summary', 'Summary', 'Timeline', 'Root cause', 'Guardrails'];

function orderedSections(text) {
  const names = [...text.matchAll(/^## (.+)$/gm)].map((match) => match[1].trim());
  return POSTMORTEM_SECTIONS.every((section, index) => names[index] === section);
}

function guardrailLinks(text) {
  const body = text.match(/^## Guardrails\n([\s\S]*)$/m)?.[1] ?? '';
  return [...body.matchAll(/\[[^\]]+\]\(([^)]+)\)/g)]
    .map((match) => match[1].trim())
    .filter((target) => !/^(https?:|mailto:|#)/.test(target));
}

export async function verifyPostmortems(repoRoot) {
  const errors = [];
  const manifest = await readRepoManifest(repoRoot);
  const dirRel = governancePaths(manifest).postmortems;
  if (manifest?.capabilities?.items?.postmortems?.state === 'external') return { errors, files: [] };
  let entries = [];
  try { entries = await readdir(path.join(repoRoot, dirRel), { withFileTypes: true }); }
  catch { return { errors: [`postmortem directory missing: ${dirRel}`], files: [] }; }
  const files = entries.filter((entry) => entry.isFile() && entry.name !== 'README.md' && entry.name.endsWith('.md')).sort((a, b) => a.name.localeCompare(b.name));
  for (const entry of files) if (!/^\d{4}-[a-z0-9]+(?:-[a-z0-9]+)*\.md$/.test(entry.name)) errors.push(`${entry.name}: invalid postmortem filename`);
  const numbers = files.filter((entry) => /^\d{4}-/.test(entry.name)).map((entry) => Number(entry.name.slice(0, 4)));
  for (let index = 0; index < numbers.length; index++) {
    if (numbers[index] !== index) { errors.push(`postmortem numbers must be sequential starting at 0; found ${files[index].name}`); break; }
  }
  for (const entry of files) {
    const rel = path.posix.join(dirRel.split(path.sep).join('/'), entry.name);
    const text = await readFile(path.join(repoRoot, rel), 'utf8');
    if (artifactVersion(text) === null && grandfatheredArtifact(manifest, rel, text)) continue;
    if (artifactVersion(text) !== 1) { errors.push(`${entry.name}: missing or unsupported Artifact-Version: 1`); continue; }
    if (!orderedSections(text)) errors.push(`${entry.name}: required postmortem sections missing or out of order`);
    if (guardrailLinks(text).length === 0) errors.push(`${entry.name}: Guardrails must link a permanent repository test, gate, or rule`);
  }
  return { errors, files: files.map((entry) => entry.name) };
}

async function main() {
  const repoRoot = path.resolve(process.argv[2] ?? '.');
  const { errors, files } = await verifyPostmortems(repoRoot);
  if (errors.length) { for (const error of errors) console.error(`verify-postmortems: ${error}`); process.exit(1); }
  console.log(`verify-postmortems: OK (${files.length} records)`);
}

const isMain = process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (isMain) main().catch((error) => { console.error(`verify-postmortems: fatal ${error.message}`); process.exit(2); });
