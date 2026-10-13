#!/usr/bin/env node
// install-hooks.mjs — install the repo-seed pre-commit (and optionally
// commit-msg) hook into a target repository's .git/hooks. Zero dependencies;
// Node >= 18.
// Usage: install-hooks.mjs <target-dir> [--with-commit-msg]
// Existing user hooks are never overwritten. Managed hooks resolve the active
// worktree at runtime and call the shared governance runner.
import { mkdir, writeFile, readFile, stat, chmod } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { pathToFileURL } from 'node:url';

export const HOOK_NAME = 'pre-commit';
export const COMMIT_MSG_HOOK_NAME = 'commit-msg';
export const MANAGED_MARKER = '# repo-seed managed hook';

export function hookScript() {
  return `#!/bin/sh
${MANAGED_MARKER}: pre-commit
set -e
repo_root=$(git rev-parse --show-toplevel) || exit 1
cd "$repo_root" || exit 1
node scripts/run-gates.mjs --staged
`;
}

export function commitMsgHookScript() {
  return `#!/bin/sh
${MANAGED_MARKER}: commit-msg
set -e
repo_root=$(git rev-parse --show-toplevel) || exit 1
cd "$repo_root" || exit 1
node scripts/verify-commit-msg.mjs "\${1:-.git/COMMIT_EDITMSG}"
`;
}

async function writeHookFile(gitDir, hookName, content) {
  const hooksDir = path.join(gitDir, 'hooks');
  await mkdir(hooksDir, { recursive: true });
  const hookPath = path.join(hooksDir, hookName);
  let previous = null;
  try { previous = await readFile(hookPath, 'utf8'); } catch {}
  if (previous !== null && !previous.includes(MANAGED_MARKER)) {
    return { status: 'conflict', hookPath };
  }
  await writeFile(hookPath, content, { mode: 0o755 });
  await chmod(hookPath, 0o755);
  return { status: previous === null ? 'installed' : 'updated', hookPath };
}

export async function resolveGitDir(targetDir) {
  const gitDir = path.join(targetDir, '.git');
  let st;
  try {
    st = await stat(gitDir);
  } catch {
    throw new Error(`not a git repository: ${targetDir} (no .git)`);
  }
  let realGit = gitDir;
  if (!st.isDirectory()) {
    // worktree: .git is a file pointing to the real git dir
    const gitFile = await readFile(gitDir, 'utf8');
    const m = gitFile.match(/^gitdir:\s*(.+)$/m);
    if (!m) throw new Error(`cannot resolve git dir from ${gitDir}`);
    realGit = path.resolve(targetDir, m[1].trim());
    // Linked worktrees keep hooks in the common Git directory, not under the
    // worktree-specific metadata directory. Git records that relationship in
    // `commondir`; resolving it here also keeps the installer testable without
    // invoking Git or assuming a particular `.git/worktrees/*` layout.
    try {
      const common = (await readFile(path.join(realGit, 'commondir'), 'utf8')).trim();
      if (common) realGit = path.resolve(realGit, common);
    } catch {
      // A hand-written .git indirection may not provide commondir. In that
      // case retain the pointed-to directory as the safest local target.
    }
  }
  return realGit;
}

export async function installHook(targetDir) {
  const gitDir = await resolveGitDir(targetDir);
  const result = await writeHookFile(gitDir, HOOK_NAME, hookScript());
  return { gitDir, ...result };
}

export async function installCommitMsgHook(gitDir) {
  return writeHookFile(gitDir, COMMIT_MSG_HOOK_NAME, commitMsgHookScript());
}

async function main() {
  const args = process.argv.slice(2);
  const target = args[0];
  const withCommitMsg = args.includes('--with-commit-msg');
  if (!target) {
    console.error('usage: install-hooks.mjs <target-dir> [--with-commit-msg]');
    process.exit(2);
  }
  const abs = path.resolve(target);
  try {
    const preCommit = await installHook(abs);
    const results = [{ name: HOOK_NAME, ...preCommit }];
    if (withCommitMsg) {
      results.push({ name: COMMIT_MSG_HOOK_NAME, gitDir: preCommit.gitDir, ...(await installCommitMsgHook(preCommit.gitDir)) });
    }
    for (const result of results) {
      if (result.status === 'conflict') console.warn(`install-hooks: preserved custom ${result.name} hook at ${result.hookPath}`);
      else console.log(`install-hooks: ${result.status} ${result.name} at ${result.hookPath}`);
    }
  } catch (e) {
    console.error(`install-hooks: ${e.message}`);
    process.exit(1);
  }
}

const isMain =
  process.argv[1] &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;
if (isMain) {
  main().catch((e) => {
    console.error('install-hooks: fatal', e);
    process.exit(2);
  });
}
