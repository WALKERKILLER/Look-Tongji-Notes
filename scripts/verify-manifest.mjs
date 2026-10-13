#!/usr/bin/env node
// verify-manifest.mjs — manifest gate.
// Checks that every file recorded in .repo-seed/manifest.json still exists and
// matches its recorded sha256, and that seeded files are recorded.
// Files marked userModified in the manifest are checked for existence only:
// the user took them over, so the recorded hash is informational.
// Zero dependencies; Node >= 18. Exits non-zero on any violation.
import { readFile, stat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import process from 'node:process';
import { pathToFileURL } from 'node:url';
import { CAPABILITIES, CAPABILITY_STATES } from './capabilities.mjs';
import { safeRepositoryRelativePath } from './governance-config.mjs';

export const MANIFEST_PATH = '.repo-seed/manifest.json';

export function sha256(text) {
  return createHash('sha256').update(text).digest('hex');
}

export async function loadManifest(repoRoot) {
  const abs = path.join(repoRoot, MANIFEST_PATH);
  try {
    const raw = await readFile(abs, 'utf8');
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

export async function verifyManifest(repoRoot) {
  const errors = [];
  const manifest = await loadManifest(repoRoot);
  if (!manifest) {
    return { errors: ['no manifest found at .repo-seed/manifest.json — run the repo-seed skill first'], files: [] };
  }
  if (manifest.version !== 1) {
    errors.push(`unsupported manifest version ${manifest.version} (expected 1)`);
  }
  if (manifest.capabilities?.version !== 1) {
    errors.push('capabilities.version must be 1');
  }
  for (const [id, capability] of Object.entries(manifest.capabilities?.items ?? {})) {
    if (!CAPABILITIES[id]) errors.push(`unknown capability: ${id}`);
    if (!CAPABILITY_STATES.has(capability?.state)) errors.push(`invalid capability state for ${id}: ${capability?.state}`);
    if (CAPABILITIES[id]?.tier === 'core' && !['enabled', 'external'].includes(capability?.state)) {
      errors.push(`core capability ${id} must be enabled or external`);
    }
    if (id === 'baseline' && capability?.state !== 'enabled') {
      errors.push('baseline capability must remain enabled in a managed repository');
    }
    if (['declined', 'deferred'].includes(capability?.state) && !/^[a-f0-9]{64}$/.test(capability?.assessmentHash ?? '')) {
      errors.push(`${id}: declined/deferred capability requires a sha256 assessmentHash`);
    }
    if (['declined', 'deferred'].includes(capability?.state) && !capability?.reason?.trim()) {
      errors.push(`${id}: declined/deferred capability requires a reason`);
    }
  }
  const governancePaths = manifest.governance?.paths ?? {};
  for (const [kind, rel] of Object.entries(governancePaths)) {
    if (!safeRepositoryRelativePath(rel)) {
      errors.push(`invalid governance path for ${kind}: ${rel}`);
    }
  }
  for (const [kind, source] of Object.entries(manifest.governance?.externalSources ?? {})) {
    if (!['repository', 'link'].includes(source?.type) || !source.location) errors.push(`invalid external source for ${kind}`);
  }
  for (const [id, definition] of Object.entries(CAPABILITIES)) {
    const sourceKind = id === 'spec' ? 'specs' : id;
    if (definition.tier === 'core' && !manifest.capabilities?.items?.[id]) {
      errors.push(`core capability missing from manifest: ${id}`);
      continue;
    }
    if (definition.tier === 'core' && manifest.capabilities?.items?.[id]?.state === 'external' &&
        !manifest.governance?.externalSources?.[sourceKind]) {
      errors.push(`external core capability ${id} requires governance.externalSources.${sourceKind}`);
    }
  }
  if (manifest.artifactPolicy?.version !== 1) errors.push('artifactPolicy.version must be 1');
  for (const entry of manifest.artifactPolicy?.legacy ?? []) {
    if (!entry.path || !/^[a-f0-9]{64}$/.test(entry.sha256 ?? '')) errors.push(`invalid legacy artifact entry: ${JSON.stringify(entry)}`);
  }
  const files = manifest.files ?? [];
  const seen = new Set();
  for (const entry of files) {
    if (!entry.path || !entry.sha256) {
      errors.push(`manifest entry missing path or sha256: ${JSON.stringify(entry)}`);
      continue;
    }
    if (entry.capability && !CAPABILITIES[entry.capability]) {
      errors.push(`manifest entry has unknown capability ${entry.capability}: ${entry.path}`);
    }
    if (!safeRepositoryRelativePath(entry.path)) {
      errors.push(`manifest entry escapes repository: ${entry.path}`);
      continue;
    }
    if (seen.has(entry.path)) {
      errors.push(`duplicate manifest entry: ${entry.path}`);
    }
    seen.add(entry.path);
    const abs = path.join(repoRoot, entry.path);
    let st;
    try {
      st = await stat(abs);
    } catch {
      errors.push(`seeded file missing: ${entry.path}`);
      continue;
    }
    if (st.isDirectory()) {
      errors.push(`seeded path is a directory, expected file: ${entry.path}`);
      continue;
    }
    if (entry.userModified) {
      // User took over this seeded file; existence is the only invariant.
      continue;
    }
    const content = await readFile(abs, 'utf8');
    const hash = sha256(content);
    if (hash !== entry.sha256) {
      errors.push(`seeded file modified since seed (hash mismatch): ${entry.path}`);
    }
  }
  return { errors, files };
}

async function main() {
  const repoRoot = path.resolve(process.argv[2] ?? '.');
  const { errors, files } = await verifyManifest(repoRoot);
  if (errors.length) {
    for (const e of errors) console.error(`verify-manifest: ${e}`);
    process.exit(1);
  }
  console.log(`verify-manifest: OK (${files.length} entries)`);
}

const isMain =
  process.argv[1] &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (isMain) {
  main().catch((e) => {
    console.error('verify-manifest: fatal', e);
    process.exit(2);
  });
}
