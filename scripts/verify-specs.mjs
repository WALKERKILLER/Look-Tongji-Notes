#!/usr/bin/env node
// verify-specs.mjs — risk-triggered change-contract gate.
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { pathToFileURL } from 'node:url';
import { artifactVersion, grandfatheredArtifact, governancePaths, readRepoManifest } from './governance-config.mjs';

export const SPEC_SECTIONS = ['Intent', 'Contract', 'Plan', 'Verification', 'Evidence'];

function sectionNames(text) {
  return [...text.matchAll(/^## (.+)$/gm)].map((match) => match[1].trim());
}

export function hasOrderedSpecSections(text) {
  const names = sectionNames(text);
  let cursor = -1;
  for (const section of SPEC_SECTIONS) {
    const next = names.indexOf(section);
    if (next === -1 || next <= cursor) return false;
    cursor = next;
  }
  return true;
}

function relativeMarkdownLinks(text) {
  return [...text.matchAll(/\[[^\]]+\]\(([^)]+)\)/g)]
    .map((match) => match[1].trim())
    .filter((target) => !/^(https?:|mailto:|#)/.test(target));
}

function sectionBody(text, name) {
  const marker = `## ${name}\n`;
  const start = text.indexOf(marker);
  if (start === -1) return '';
  const rest = text.slice(start + marker.length);
  const next = rest.search(/^## /m);
  return (next === -1 ? rest : rest.slice(0, next)).trim();
}

export async function verifySpecs(repoRoot) {
  const errors = [];
  const manifest = await readRepoManifest(repoRoot);
  const dirRel = governancePaths(manifest).specs;
  const specCapability = manifest?.capabilities?.items?.spec ?? { state: 'enabled', mode: 'repo' };
  if (specCapability.state === 'external' || specCapability.mode === 'external') return { errors, files: [] };
  let entries = [];
  try { entries = await readdir(path.join(repoRoot, dirRel), { withFileTypes: true }); }
  catch {
    errors.push(`spec directory missing: ${dirRel}`);
    return { errors, files: [] };
  }
  const markdown = entries.filter((entry) => entry.isFile() && entry.name.endsWith('.md') && entry.name !== 'README.md');
  const validName = /^(?:draft-|\d{4}-)[a-z0-9]+(?:-[a-z0-9]+)*\.md$/;
  for (const entry of markdown) if (!validName.test(entry.name)) errors.push(`${entry.name}: invalid spec filename`);
  const numbered = markdown.filter((entry) => /^\d{4}-/.test(entry.name)).sort((a, b) => a.name.localeCompare(b.name));
  const numbers = numbered.map((entry) => Number(entry.name.slice(0, 4)));
  for (let index = 0; index < numbers.length; index++) {
    if (numbers[index] !== index) { errors.push(`spec numbers must be sequential starting at 0; found ${numbered[index].name}`); break; }
  }
  for (const entry of markdown) {
    const rel = path.posix.join(dirRel.split(path.sep).join('/'), entry.name);
    const text = await readFile(path.join(repoRoot, rel), 'utf8');
    if (artifactVersion(text) === null && grandfatheredArtifact(manifest, rel, text)) continue;
    if (artifactVersion(text) !== 1) { errors.push(`${entry.name}: missing or unsupported Artifact-Version: 1`); continue; }
    const status = text.match(/^Status:\s*(.+)$/m)?.[1]?.trim();
    if (!status) { errors.push(`${entry.name}: missing Status metadata`); continue; }
    const isDraftName = entry.name.startsWith('draft-');
    if ((status === 'Draft') !== isDraftName) errors.push(`${entry.name}: Draft status and draft- filename must match`);
    if (!['Draft', 'Approved', 'Implemented'].includes(status) && !status.startsWith('Superseded by ')) {
      errors.push(`${entry.name}: invalid status "${status}"`);
    }
    if (status.startsWith('Superseded by ')) {
      const target = status.match(/(\d{4})/)?.[1];
      if (!target || !numbers.includes(Number(target))) errors.push(`${entry.name}: superseded target missing`);
    }
    if (!hasOrderedSpecSections(text)) errors.push(`${entry.name}: required spec sections missing or out of order`);
    if (status === 'Implemented' && relativeMarkdownLinks(sectionBody(text, 'Evidence')).length === 0) {
      errors.push(`${entry.name}: Implemented spec Evidence must link a permanent repository artifact`);
    }
  }
  return { errors, files: markdown.map((entry) => entry.name) };
}

async function main() {
  const repoRoot = path.resolve(process.argv[2] ?? '.');
  const { errors, files } = await verifySpecs(repoRoot);
  if (errors.length) { for (const error of errors) console.error(`verify-specs: ${error}`); process.exit(1); }
  console.log(`verify-specs: OK (${files.length} records)`);
}

const isMain = process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (isMain) main().catch((error) => { console.error(`verify-specs: fatal ${error.message}`); process.exit(2); });
