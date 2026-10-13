#!/usr/bin/env node
// audit-governance.mjs — read-only repository governance assessment.
// Never reads .env files, never accesses the network, and never writes state.
import { access, readdir, readFile, stat } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import path from 'node:path';
import process from 'node:process';
import { pathToFileURL } from 'node:url';
import { assessCapabilities, CAPABILITIES } from './capabilities.mjs';

const execFileAsync = promisify(execFile);
const PACKAGE_MANIFESTS = new Set(['package.json', 'pyproject.toml', 'go.mod', 'Cargo.toml', 'Gemfile', 'requirements.txt']);

async function exists(abs) {
  try { await access(abs); return true; } catch { return false; }
}

async function countPackageManifests(repoRoot) {
  let count = 0;
  async function walk(dir, depth) {
    if (depth > 2) return;
    let entries = [];
    try { entries = await readdir(dir, { withFileTypes: true }); } catch { return; }
    for (const entry of entries) {
      if (entry.name === '.git' || entry.name === 'node_modules' || entry.name === 'vendor' || entry.name === '.env') continue;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) await walk(full, depth + 1);
      else if (PACKAGE_MANIFESTS.has(entry.name)) count++;
    }
  }
  await walk(repoRoot, 0);
  return count;
}

async function detectTestCommand(repoRoot) {
  try {
    const pkg = JSON.parse(await readFile(path.join(repoRoot, 'package.json'), 'utf8'));
    if (pkg.scripts?.test) return 'npm test';
  } catch {}
  if (await exists(path.join(repoRoot, 'pyproject.toml'))) return 'pytest';
  if (await exists(path.join(repoRoot, 'go.mod'))) return 'go test ./...';
  if (await exists(path.join(repoRoot, 'Cargo.toml'))) return 'cargo test';
  if (await exists(path.join(repoRoot, 'Gemfile'))) return 'bundle exec rake test';
  try {
    const agents = await readFile(path.join(repoRoot, 'AGENTS.md'), 'utf8');
    const declared = agents.match(/^- Test:\s*`([^`]+)`\s*$/m)?.[1]?.trim();
    if (declared) return declared;
  } catch {}
  return null;
}

async function gitFacts(repoRoot) {
  const isGit = await exists(path.join(repoRoot, '.git'));
  if (!isGit) return { isGit: false, hasGitHubRemote: false, hasTags: false, hasPreCommitHook: false };
  let remote = '';
  let hasTags = false;
  let hasPreCommitHook = false;
  try { remote = (await execFileAsync('git', ['config', '--get', 'remote.origin.url'], { cwd: repoRoot })).stdout.trim(); } catch {}
  try { hasTags = (await execFileAsync('git', ['tag', '-l'], { cwd: repoRoot })).stdout.trim() !== ''; } catch {}
  try {
    const hook = (await execFileAsync('git', ['rev-parse', '--git-path', 'hooks/pre-commit'], { cwd: repoRoot })).stdout.trim();
    hasPreCommitHook = await exists(path.resolve(repoRoot, hook));
  } catch {
    hasPreCommitHook = await exists(path.join(repoRoot, '.git', 'hooks', 'pre-commit'));
  }
  return { isGit, hasGitHubRemote: /github\.com[:/]/i.test(remote), hasTags, hasPreCommitHook };
}

async function readManifest(repoRoot) {
  try { return JSON.parse(await readFile(path.join(repoRoot, '.repo-seed', 'manifest.json'), 'utf8')); } catch { return null; }
}

export async function collectGovernanceFacts(repoRoot) {
  const git = await gitFacts(repoRoot);
  const packageCount = await countPackageManifests(repoRoot);
  const testCommand = await detectTestCommand(repoRoot);
  const hasHookManager = await exists(path.join(repoRoot, '.husky')) || await exists(path.join(repoRoot, '.pre-commit-config.yaml'));
  const hasCi = await exists(path.join(repoRoot, '.github', 'workflows')) ||
    await exists(path.join(repoRoot, '.gitlab-ci.yml')) || await exists(path.join(repoRoot, '.circleci'));
  const hasReleasePolicy = await exists(path.join(repoRoot, 'docs', 'release-policy.md')) ||
    await exists(path.join(repoRoot, '.releaserc')) || await exists(path.join(repoRoot, 'release-please-config.json'));
  const hasReleaseMarkers = git.hasTags || hasReleasePolicy || await exists(path.join(repoRoot, 'CHANGELOG.md'));
  return {
    ...git,
    managed: await exists(path.join(repoRoot, '.repo-seed', 'manifest.json')),
    testCommand,
    hasTestCommand: Boolean(testCommand),
    packageCount,
    multiplePackages: packageCount > 1,
    hasCi,
    hasReleasePolicy,
    hasReleaseMarkers,
    hasDeploymentMarkers: await exists(path.join(repoRoot, 'Dockerfile')) ||
      await exists(path.join(repoRoot, 'docker-compose.yml')) ||
      await exists(path.join(repoRoot, 'compose.yml')) ||
      await exists(path.join(repoRoot, 'k8s')) ||
      await exists(path.join(repoRoot, 'terraform')) ||
      await exists(path.join(repoRoot, 'vercel.json')),
    hasAgents: await exists(path.join(repoRoot, 'AGENTS.md')),
    hasArchitecture: await exists(path.join(repoRoot, 'docs', 'architecture.md')) || await exists(path.join(repoRoot, 'ARCHITECTURE.md')),
    hasDecisionSystem: await exists(path.join(repoRoot, 'docs', 'decisions')) || await exists(path.join(repoRoot, 'docs', 'adr')),
    hasSpecSystem: await exists(path.join(repoRoot, 'docs', 'specs')) || await exists(path.join(repoRoot, 'docs', 'rfcs')),
    hasPostmortemSystem: await exists(path.join(repoRoot, 'docs', 'postmortems')) || await exists(path.join(repoRoot, 'docs', 'incidents')),
    hasSecurityPolicy: await exists(path.join(repoRoot, 'SECURITY.md')),
    hasCodeowners: await exists(path.join(repoRoot, 'CODEOWNERS')) || await exists(path.join(repoRoot, '.github', 'CODEOWNERS')),
    hasAiDisclosure: await exists(path.join(repoRoot, 'docs', 'ai-disclosure.md')),
    hasSubtreeInstructions: packageCount > 1 && await exists(path.join(repoRoot, 'packages', 'AGENTS.md')),
    hasHookManager,
    isPublic: null,
    requiresAiDisclosure: false,
    riskyChange: false,
    productionIncident: false,
  };
}

export async function auditGovernance(repoRoot) {
  const facts = await collectGovernanceFacts(repoRoot);
  const manifest = await readManifest(repoRoot);
  const items = manifest?.capabilities?.items ?? {};
  const capabilities = assessCapabilities(facts, items).map((assessment) => ({
    ...assessment,
    ...(items[assessment.id]?.reason ? { recordedReason: items[assessment.id].reason } : {}),
    ...(items[assessment.id]?.source ? { source: items[assessment.id].source } : {}),
    title: CAPABILITIES[assessment.id].title,
    benefit: CAPABILITIES[assessment.id].benefit,
    cost: CAPABILITIES[assessment.id].cost,
    reviewContribution: CAPABILITIES[assessment.id].reviewContribution,
  }));
  return {
    managed: Boolean(manifest),
    repoSeedVersion: manifest?.repoSeedVersion ?? null,
    facts,
    capabilities,
  };
}

async function main() {
  const args = process.argv.slice(2);
  const json = args.includes('--json');
  const target = args.find((arg) => !arg.startsWith('--')) ?? '.';
  const result = await auditGovernance(path.resolve(target));
  if (json) {
    console.log(JSON.stringify(result, null, 2));
    return;
  }
  console.log(`governance-audit: ${result.managed ? `managed by repo-seed ${result.repoSeedVersion ?? ''}`.trim() : 'unmanaged repository'}`);
  const recommendations = result.capabilities.filter((item) => item.recommendation === 'recommended');
  if (!recommendations.length) console.log('governance-audit: no new capability recommendations');
  for (const item of recommendations) {
    console.log(`governance-audit: ${item.urgency} recommendation ${item.id} — ${item.benefit} Cost: ${item.cost}`);
  }
}

const isMain = process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (isMain) main().catch((error) => { console.error(`governance-audit: fatal ${error.message}`); process.exit(2); });
