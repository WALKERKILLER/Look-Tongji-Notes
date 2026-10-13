#!/usr/bin/env node
// governance-config.mjs — shared manifest, path, and artifact-policy helpers.
import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';

export const DEFAULT_GOVERNANCE_PATHS = Object.freeze({
  architecture: 'docs/architecture.md',
  testing: 'docs/testing.md',
  decisions: 'docs/decisions',
  specs: 'docs/specs',
  postmortems: 'docs/postmortems',
});

export function safeRepositoryRelativePath(rel) {
  if (typeof rel !== 'string' || !rel) return false;
  const normalized = path.posix.normalize(rel.replaceAll('\\', '/'));
  if (path.posix.isAbsolute(normalized) || normalized === '..' || normalized.startsWith('../')) return false;
  return !normalized.split('/').some((segment) => /^\.env(?:\.|$)/.test(segment));
}

export function contentSha256(content) {
  return createHash('sha256').update(content).digest('hex');
}

export async function readRepoManifest(repoRoot) {
  try { return JSON.parse(await readFile(path.join(repoRoot, '.repo-seed', 'manifest.json'), 'utf8')); }
  catch { return null; }
}

export function governancePaths(manifest) {
  return { ...DEFAULT_GOVERNANCE_PATHS, ...(manifest?.governance?.paths ?? {}) };
}

export function artifactVersion(text) {
  const match = text.match(/^Artifact-Version:\s*(\d+)\s*$/m);
  return match ? Number(match[1]) : null;
}

export function grandfatheredArtifact(manifest, rel, content) {
  const entry = manifest?.artifactPolicy?.legacy?.find((item) => item.path === rel);
  return Boolean(entry && entry.sha256 === contentSha256(content));
}

async function artifactFiles(repoRoot, manifest) {
  const paths = governancePaths(manifest);
  const out = [];
  for (const [kind, relDir] of [['spec', paths.specs], ['postmortem', paths.postmortems]]) {
    if (!safeRepositoryRelativePath(relDir)) continue;
    let entries = [];
    try { entries = await readdir(path.join(repoRoot, relDir), { withFileTypes: true }); } catch { continue; }
    for (const entry of entries) {
      if (!entry.isFile() || !entry.name.endsWith('.md') || entry.name === 'README.md') continue;
      const rel = path.posix.join(relDir.split(path.sep).join('/'), entry.name);
      const content = await readFile(path.join(repoRoot, rel), 'utf8');
      out.push({ kind, path: rel, content });
    }
  }
  return out;
}

export async function initializeArtifactPolicy(repoRoot, manifest) {
  if (manifest.artifactPolicy?.version === 1) return manifest.artifactPolicy;
  const legacy = [];
  for (const artifact of await artifactFiles(repoRoot, manifest)) {
    if (artifactVersion(artifact.content) === null) legacy.push({ path: artifact.path, sha256: contentSha256(artifact.content) });
  }
  manifest.artifactPolicy = { version: 1, legacy };
  return manifest.artifactPolicy;
}

export async function refreshArtifactPolicy(repoRoot, manifest) {
  const current = new Map((manifest.artifactPolicy?.legacy ?? []).map((entry) => [entry.path, entry]));
  const legacy = [];
  for (const artifact of await artifactFiles(repoRoot, manifest)) {
    if (artifactVersion(artifact.content) !== null) continue;
    const entry = current.get(artifact.path);
    if (entry) legacy.push(entry); // Never refresh the hash: changed legacy content must migrate.
  }
  manifest.artifactPolicy = { version: 1, legacy };
  return manifest.artifactPolicy;
}
