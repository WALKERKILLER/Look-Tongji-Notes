#!/usr/bin/env node
// capabilities.mjs — capability catalog and progressive-governance helpers.
// Shared by the scaffold and the read-only governance audit. Zero dependencies.
import { createHash } from 'node:crypto';

export const CAPABILITY_STATES = new Set(['enabled', 'external', 'deferred', 'declined']);
export const CAPABILITY_MODEL_VERSION = 1;

const CORE = {
  baseline: {
    id: 'baseline',
    tier: 'core',
    title: 'Agent-native repository baseline',
    benefit: 'Keeps management identity, resident skill routing, repository orientation, human-readable implementation guidance, risk-driven testing policy, review policy, deterministic verification, and safe upgrades available in every managed repository.',
    cost: 'Maintains a small governed surface and ownership manifest.',
    urgency: 'blocking',
    files: [
      ['AGENTS.md', 'instruction'],
      ['CLAUDE.md', 'instruction'],
      ['docs/AGENTS.md', 'docs'],
      ['docs/architecture.md', 'docs'],
      ['docs/development.md', 'docs'],
      ['docs/testing.md', 'docs'],
      ['.agents/skills/repo-review/SKILL.md', 'skill'],
      ['.agents/skills/repo-governance/SKILL.md', 'skill'],
      ['scripts/capabilities.mjs', 'gate'],
      ['scripts/governance-config.mjs', 'gate'],
      ['scripts/audit-governance.mjs', 'gate'],
      ['scripts/run-gates.mjs', 'gate'],
      ['scripts/verify-doc-links.mjs', 'gate'],
      ['scripts/verify-placeholders.mjs', 'gate'],
      ['scripts/verify-manifest.mjs', 'gate'],
      ['scripts/install-hooks.mjs', 'gate'],
      ['CONTRIBUTING.md', 'meta'],
      ['LICENSE', 'meta'],
      ['.editorconfig', 'meta'],
      ['.gitattributes', 'meta'],
      ['.repo-seed/update-strategy.md', 'meta'],
      ['.github/pull_request_template.md', 'github'],
      ['.github/ISSUE_TEMPLATE/bug.md', 'github'],
      ['.github/ISSUE_TEMPLATE/feature.md', 'github'],
    ],
    recommendWhen: [],
    reviewContribution: 'Management identity, resident skill routing, human-readable implementation, risk-adjusted test evidence, project review policy, documentation orientation, manifest ownership, and the upgrade channel stay coherent.',
    verifyCommands: [
      'node scripts/verify-doc-links.mjs',
      'node scripts/verify-placeholders.mjs',
      'node scripts/verify-manifest.mjs',
    ],
  },
  spec: {
    id: 'spec',
    tier: 'core',
    title: 'Risk-triggered change contracts',
    benefit: 'Keeps intent, observable behavior, constraints, and proof stable across agents and sessions.',
    cost: 'One short contract for changes that cross a risk boundary; routine work is exempt.',
    urgency: 'blocking',
    files: [
      ['docs/specs/README.md', 'docs'],
      ['scripts/verify-specs.mjs', 'gate'],
    ],
    recommendWhen: ['riskyChange'],
    reviewContribution: 'Risk-boundary changes require an Approved spec before implementation and permanent Evidence before completion.',
    verifyCommands: ['node scripts/verify-specs.mjs'],
    legacyExtension: true,
  },
  decisions: {
    id: 'decisions',
    tier: 'core',
    title: 'Durable decision memory',
    benefit: 'Preserves choices with genuine alternatives without turning every change into an ADR.',
    cost: 'A MADR record only when rationale is likely to be revisited.',
    urgency: 'blocking',
    files: [
      ['docs/decisions/README.md', 'docs'],
      ['docs/decisions/0000-use-markdown-architectural-decision-records.md', 'docs'],
      ['docs/decisions/0001-repo-seed-is-a-skill-not-a-template.md', 'docs'],
      ['docs/decisions/0002-self-governing-repository-design.md', 'docs'],
      ['docs/decisions/0003-repo-review-instantiated-per-project.md', 'docs'],
      ['.agents/skills/repo-decisions/SKILL.md', 'skill'],
      ['scripts/verify-decisions.mjs', 'gate'],
    ],
    recommendWhen: [],
    reviewContribution: 'Record durable choices with real alternatives; do not use ADRs as a change log.',
    verifyCommands: ['node scripts/verify-decisions.mjs'],
  },
  postmortems: {
    id: 'postmortems',
    tier: 'core',
    title: 'Incident feedback loop',
    benefit: 'Turns systemic failures into linked tests, gates, or standing rules.',
    cost: 'A record only for subtle, systemic, or costly-to-rediscover failures.',
    urgency: 'blocking',
    files: [
      ['docs/postmortems/README.md', 'docs'],
      ['scripts/verify-postmortems.mjs', 'gate'],
    ],
    recommendWhen: ['productionIncident'],
    reviewContribution: 'A qualifying incident links at least one permanent repository guardrail.',
    verifyCommands: ['node scripts/verify-postmortems.mjs'],
  },
};

const OPTIONAL = {
  ci: {
    id: 'ci',
    tier: 'optional',
    title: 'CI workflow',
    benefit: 'Runs governance gates and tests for every shared change.',
    cost: 'Maintains a hosted workflow and its permissions.',
    urgency: 'advisory',
    prerequisites: ['a real test entry point', 'a supported hosted CI target'],
    files: [['.github/workflows/ci.yml', 'github']],
    recommendWhen: ['hasTestCommand', 'hasGitHubRemote', '!hasCi'],
    externalWhen: ['hasCi'],
    agentsLine: '- CI runs the gates on every push/PR: [.github/workflows/ci.yml](.github/workflows/ci.yml).',
    reviewContribution: 'Workflow changes retain least privilege and keep the governance runner plus the real test entry point.',
    verifyCommands: ['node scripts/run-gates.mjs'],
    legacyExtension: true,
  },
  release: {
    id: 'release',
    tier: 'optional',
    title: 'Release policy',
    benefit: 'Makes versioning, change records, and commit messages predictable.',
    cost: 'Adds a release policy and optional commit-msg enforcement.',
    urgency: 'blocking',
    prerequisites: ['a versioned release process'],
    files: [
      ['docs/release-policy.md', 'docs'],
      ['scripts/verify-commit-msg.mjs', 'gate'],
    ],
    recommendWhen: ['hasReleaseMarkers', '!hasReleasePolicy'],
    externalWhen: ['hasReleasePolicy'],
    agentsLine: '- Commit messages follow conventional commits; see [docs/release-policy.md](docs/release-policy.md).',
    reviewContribution: 'Release-facing changes follow the repository release policy and preserve rollback information.',
    verifyCommands: ['node scripts/verify-commit-msg.mjs'],
    legacyExtension: true,
  },
  community: {
    id: 'community',
    tier: 'optional',
    title: 'Community health files',
    benefit: 'Defines vulnerability reporting and contributor conduct for public projects.',
    cost: 'Requires maintainers to own and keep public policies current.',
    urgency: 'advisory',
    prerequisites: ['a public maintainer contact'],
    files: [
      ['SECURITY.md', 'meta'],
      ['CODE_OF_CONDUCT.md', 'meta'],
    ],
    recommendWhen: ['isPublic', '!hasSecurityPolicy'],
    externalWhen: ['hasSecurityPolicy'],
    agentsLine: '- Security vulnerabilities are reported per [SECURITY.md](SECURITY.md).',
    reviewContribution: 'Public-facing changes keep security reporting and community policy accurate.',
    verifyCommands: [],
    legacyExtension: true,
  },
  codeowners: {
    id: 'codeowners',
    tier: 'optional',
    title: 'CODEOWNERS',
    benefit: 'Routes protected surfaces to named owners.',
    cost: 'Requires real teams or handles and matching branch protection.',
    urgency: 'blocking',
    prerequisites: ['real user or team owner handles'],
    files: [['CODEOWNERS', 'meta']],
    recommendWhen: ['multiplePackages', '!hasCodeowners'],
    externalWhen: ['hasCodeowners'],
    agentsLine: '- Path-level owners live in [CODEOWNERS](CODEOWNERS); branch protection should require owner review.',
    reviewContribution: 'Ownership changes name real owners and stay aligned with protected paths.',
    verifyCommands: [],
    legacyExtension: true,
  },
  'ai-disclosure': {
    id: 'ai-disclosure',
    tier: 'optional',
    title: 'AI disclosure policy',
    benefit: 'Makes AI participation auditable for repositories that require it.',
    cost: 'Adds contribution metadata maintainers must enforce.',
    urgency: 'advisory',
    prerequisites: ['a maintainer-approved disclosure policy'],
    files: [['docs/ai-disclosure.md', 'docs']],
    recommendWhen: ['requiresAiDisclosure', '!hasAiDisclosure'],
    externalWhen: ['hasAiDisclosure'],
    agentsLine: '- AI-assisted commits/PRs disclose participation per [docs/ai-disclosure.md](docs/ai-disclosure.md).',
    reviewContribution: 'AI-assisted changes carry the disclosure metadata required by policy.',
    verifyCommands: [],
    legacyExtension: true,
  },
  monorepo: {
    id: 'monorepo',
    tier: 'optional',
    title: 'Subtree agent instructions',
    benefit: 'Gives packages with different commands or ownership focused local instructions.',
    cost: 'Adds instruction surfaces that must stay consistent with the root.',
    urgency: 'advisory',
    prerequisites: ['multiple packages with distinct commands, policy, or ownership'],
    files: [],
    dynamicFiles: ['<package>/AGENTS.md'],
    recommendWhen: ['multiplePackages', '!hasSubtreeInstructions'],
    externalWhen: ['hasSubtreeInstructions'],
    reviewContribution: 'Subtree instructions narrow local facts without copying root policy.',
    verifyCommands: [],
  },
  hook: {
    id: 'hook',
    tier: 'optional',
    title: 'Local pre-commit enforcement',
    benefit: 'Runs governance gates before a commit leaves the workstation.',
    cost: 'Writes local Git state and may conflict with an existing hook manager.',
    urgency: 'advisory',
    prerequisites: ['a Git repository', 'explicit user authorization'],
    files: [],
    dynamicFiles: ['<git-common-dir>/hooks/pre-commit'],
    recommendWhen: ['isGit', '!hasPreCommitHook', '!hasHookManager'],
    externalWhen: ['hasPreCommitHook'],
    reviewContribution: 'Hook changes preserve existing user hooks and call the shared governance runner.',
    verifyCommands: ['node scripts/run-gates.mjs --staged'],
  },
};

function completeDefinition(definition) {
  const signals = [...(definition.recommendWhen ?? [])];
  const equivalentSystemSignals = [...(definition.externalWhen ?? [])];
  return Object.freeze({
    prerequisites: [],
    signals,
    equivalentSystemSignals,
    agentsContribution: definition.agentsLine ?? definition.reviewContribution ?? null,
    gateContribution: [...(definition.verifyCommands ?? [])],
    enableConditions: signals,
    upgradeConditions: ['repoSeedVersionChanged', 'managedFilesUntouched'],
    reevaluateConditions: [...new Set([...signals, ...equivalentSystemSignals].map((name) => name.replace(/^!/, '')))].sort(),
    ...definition,
  });
}

export const CAPABILITIES = Object.freeze(Object.fromEntries(
  Object.entries({ ...CORE, ...OPTIONAL }).map(([id, definition]) => [id, completeDefinition(definition)])
));

export function capabilityCatalog() {
  return Object.values(CAPABILITIES);
}

export function capabilityForFile(rel) {
  for (const definition of capabilityCatalog()) {
    if (definition.files.some(([file]) => file === rel)) return definition.id;
  }
  return null;
}

export function extensionCapabilities() {
  return capabilityCatalog().filter((c) => c.tier === 'optional' && c.legacyExtension);
}

function normalizedRelevantFacts(definition, facts) {
  const names = new Set(
    [...(definition.recommendWhen ?? []), ...(definition.externalWhen ?? [])].map((n) => n.replace(/^!/, ''))
  );
  return Object.fromEntries([...names].sort().map((name) => [name, facts[name] ?? null]));
}

export function assessmentHash(definition, facts) {
  const input = JSON.stringify({
    version: CAPABILITY_MODEL_VERSION,
    id: definition.id,
    urgency: definition.urgency,
    recommendWhen: definition.recommendWhen ?? [],
    externalWhen: definition.externalWhen ?? [],
    facts: normalizedRelevantFacts(definition, facts),
  });
  return createHash('sha256').update(input).digest('hex');
}

function conditionsMatch(conditions, facts) {
  return (conditions ?? []).every((condition) => {
    const negated = condition.startsWith('!');
    const key = negated ? condition.slice(1) : condition;
    const value = Boolean(facts[key]);
    return negated ? !value : value;
  });
}

export function assessCapability(definition, facts, current = null) {
  const hash = assessmentHash(definition, facts);
  const timing = definition.urgency === 'blocking' ? 'before-implementation' : 'handoff';
  if (definition.tier === 'core') {
    const state = current?.state === 'external' ? 'external' : 'enabled';
    return {
      id: definition.id,
      state,
      recommendation: state === 'external' ? 'satisfied-external' : 'satisfied',
      urgency: definition.urgency,
      timing,
      assessmentHash: hash,
      reasons: [],
    };
  }
  if (current?.state === 'enabled' || current?.state === 'external') {
    return { id: definition.id, state: current.state, recommendation: 'satisfied', urgency: definition.urgency, timing, assessmentHash: hash, reasons: [] };
  }
  if (conditionsMatch(definition.externalWhen, facts)) {
    return { id: definition.id, state: current?.state ?? 'external', recommendation: 'satisfied-external', urgency: definition.urgency, timing, assessmentHash: hash, reasons: definition.externalWhen };
  }
  const relevant = conditionsMatch(definition.recommendWhen, facts) && (definition.recommendWhen?.length ?? 0) > 0;
  const suppressed = relevant && ['declined', 'deferred'].includes(current?.state) && current.assessmentHash === hash;
  return {
    id: definition.id,
    state: current?.state ?? null,
    recommendation: suppressed ? 'suppressed' : relevant ? 'recommended' : 'not-applicable',
    urgency: definition.urgency,
    timing,
    assessmentHash: hash,
    reasons: relevant ? definition.recommendWhen : [],
  };
}

export function assessCapabilities(facts, items = {}) {
  return capabilityCatalog().map((definition) => assessCapability(definition, facts, items[definition.id]));
}

export function defaultCapabilityState() {
  return {
    version: CAPABILITY_MODEL_VERSION,
    items: Object.fromEntries(
      Object.values(CORE).map((definition) => [definition.id, { state: 'enabled', ...(definition.id === 'spec' ? { mode: 'repo' } : {}) }])
    ),
  };
}

export function normalizeCapabilities(manifest) {
  const existing = manifest.capabilities?.items ?? {};
  const next = defaultCapabilityState();
  for (const [id, value] of Object.entries(existing)) {
    if (CAPABILITIES[id] && CAPABILITY_STATES.has(value?.state)) next.items[id] = { ...value };
  }
  for (const entry of manifest.files ?? []) {
    if (entry.extension && CAPABILITIES[entry.extension]?.tier === 'optional') {
      if (!next.items[entry.extension]) next.items[entry.extension] = { state: 'enabled' };
    }
  }
  manifest.capabilities = next;
  return next;
}
