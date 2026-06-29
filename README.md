# Forge CLI Auth Wrappers

`forge-cli-auth` is a small dotfiles package for running forge CLIs with
credentials restored from `pass` only when needed.

The current wrappers are:

| Wrapper | Underlying CLI | Secret source | Runtime credential path |
|---|---|---|---|
| `ghp` | GitHub CLI, `gh` | `tokens/github/gh-oauth` | `GH_TOKEN` for the child `gh` process |
| `glabp` | GitLab CLI, `glab` | `tokens/gitlab/glab-oauth-config` | private temporary `GLAB_CONFIG_DIR` |

In this document, a **forge** means a source-code collaboration platform such
as GitHub, GitLab, Gitea, Forgejo, SourceHut, or Bitbucket.

## Why this exists

The normal GitHub and GitLab CLIs are designed for convenience. They often keep
long-lived authentication state in default config directories such as
`~/.config/gh` or `~/.config/glab-cli`.

That is fine for many systems. This package chooses a narrower operating model:

- keep the durable credential material in `pass`
- keep default CLI config locations clean
- restore credentials only for the command being run
- delete transient GitLab CLI config after each invocation
- keep the wrappers simple enough to audit at a glance

The result is not a vault, sandbox, or high-assurance isolation boundary. It is a
small credential-handling shim with deliberately limited scope.

## Design principles

1. **Prefer explicit credential boundaries.**
   The durable source of authentication state is the password store, not the
   forge CLI's default config directory.

2. **Minimize persistent local residue.**
   `ghp` does not write a GitHub CLI config. `glabp` restores GitLab CLI config
   to a temporary directory and removes it when the command exits.

3. **Do not parse secrets unless necessary.**
   `ghp` extracts only the first line of the GitHub token entry. `glabp` treats
   `config.yml` as an opaque blob.

4. **Make mutation visible.**
   `glabp` hashes the restored GitLab config before and after running `glab`,
   and writes the config back to `pass` only if it changed.

5. **Preserve the underlying CLI behavior.**
   The wrappers do not reimplement `gh` or `glab`. Arguments are forwarded
   directly to the real CLI binaries.

6. **Fail closed where failure is obvious.**
   Missing dependencies, unreadable pass entries, empty GitHub tokens, and
   missing GitLab configs are treated as hard errors.

## Security posture

### What this protects against

This package is intended to reduce these risks:

- accidentally leaving GitHub or GitLab CLI auth state in the default config
  directories
- committing CLI config files or OAuth material into dotfiles
- confusing wrapper-managed credentials with normal CLI login state
- leaving a reusable GitLab CLI config directory behind after each command
- leaking tokens through shell xtrace from the wrapper itself

### What this does not protect against

This package does **not** protect against:

- a compromised local user account
- a compromised `pass` store or exposed GPG private key
- a malicious or compromised `gh`, `glab`, `git`, `pass`, shell, terminal,
  kernel, or filesystem
- process inspection by a sufficiently privileged local actor
- malicious `gh` or `glab` extensions invoked through the wrappers
- secrets already present in repository files, commit history, shell history,
  logs, editor swap files, or terminal scrollback
- Git SSH authentication problems

The wrappers authenticate the forge CLIs. They do not manage Git remotes, SSH
keys, deploy keys, signing keys, repository permissions, branch protection, or
host trust.

## Threat model

### Trusted

The wrappers assume the following are trustworthy enough for local use:

- the local user account
- the `pass` password store
- the GPG private key protecting the password store
- the installed `gh`, `glab`, `git`, `pass`, `zsh`, and `coreutils` binaries
- the shell environment from which the wrappers are invoked

### Untrusted or uncontrolled

The wrappers do not assume that the default CLI config directories are suitable
for long-term credential storage.

They also do not attempt to control:

- what `gh` or `glab` may do internally during command execution
- what remote forge services do after authentication
- what Git does over SSH or HTTPS
- repository contents being pushed
- extensions or plugins loaded by the underlying CLIs

### Security invariant

The intended invariant is:

> Durable forge CLI credential material lives in `pass`; runtime credential
> material exists only for the duration and scope required by the invoked CLI
> command.

That invariant is operational, not absolute. On a compromised machine, the
credential can still be observed at runtime.

## Components

### `ghp`

`ghp` is a pass-backed wrapper around the GitHub CLI.

It reads this pass entry:

```text
tokens/github/gh-oauth
```

Only the first line is used as the GitHub token. Later lines may contain notes
or metadata.

Example pass entry:

```text
gho_xxxxxxxxxxxxxxxxxxxx
host: github.com
purpose: GitHub CLI wrapper token
```

At runtime, `ghp`:

1. runs under `zsh`
2. resets zsh behavior with `emulate -R zsh`
3. disables shell tracing with `unsetopt xtrace`
4. sets `umask 077`
5. requires `pass` and `gh`
6. reads the token from `pass`
7. extracts the first line
8. rejects an empty token
9. invokes the real CLI with `GH_TOKEN="$token" command gh "$@"`

Typical read-only checks:

```sh
ghp auth status
ghp repo view
ghp pr list
ghp api user
```

### `glabp`

`glabp` is a pass-backed wrapper around the GitLab CLI.

It reads this pass entry:

```text
tokens/gitlab/glab-oauth-config
```

This entry contains a complete GitLab CLI `config.yml`, not merely a token.

At runtime, `glabp`:

1. runs under `zsh`
2. resets zsh behavior with `emulate -R zsh`
3. disables shell tracing with `unsetopt xtrace`
4. sets `umask 077`
5. requires `pass`, `glab`, `mktemp`, and `sha256sum`
6. chooses `XDG_RUNTIME_DIR`, falling back to `/tmp` if needed
7. creates a private temporary directory named like `glab-pass.XXXXXX`
8. restores `config.yml` from `pass`
9. applies directory mode `700` and config-file mode `600`
10. hashes the restored config
11. invokes the real CLI with `GLAB_CONFIG_DIR="$tmp" command glab "$@"`
12. checks whether the config is still present and non-empty
13. hashes the updated config
14. writes the config back to `pass` only if it changed
15. removes the temporary directory on exit

Typical read-only checks:

```sh
glabp auth status
glabp repo view
glabp mr list
glabp pipeline list
```

## Installation

This package is intended to be deployed with GNU Stow.

Suggested dotfiles layout:

```text
dotfiles/
└── forge-cli-auth/
    ├── .local/
    │   └── bin/
    │       ├── ghp
    │       └── glabp
    └── README.md
```

Deploy:

```sh
cd ~/dotfiles
stow forge-cli-auth
chmod 700 ~/.local/bin/ghp ~/.local/bin/glabp
```

Confirm that `~/.local/bin` is on `PATH`:

```sh
printf '%s\n' "$PATH" | tr ':' '\n' | grep -Fx "$HOME/.local/bin"
```

## Dependencies

Required for both wrappers:

```text
zsh
pass
```

Required for `ghp`:

```text
gh
```

Required for `glabp`:

```text
glab
mktemp
sha256sum
```

On Arch Linux, the core dependencies are typically provided by:

```sh
sudo pacman -S zsh pass github-cli glab coreutils
```

`mktemp` and `sha256sum` are provided by `coreutils`.

## Secret setup

### GitHub token entry

Create the required pass entry:

```sh
pass insert tokens/github/gh-oauth
```

Paste the GitHub token as the first line.

Optional metadata may be placed on later lines:

```text
gho_xxxxxxxxxxxxxxxxxxxx
host: github.com
purpose: GitHub CLI wrapper token
```

Verify:

```sh
ghp auth status
```

### GitLab config entry

Create a temporary GitLab CLI config, authenticate once, then store the resulting
`config.yml` in `pass`.

```sh
tmp="$(mktemp -d)"
chmod 700 "$tmp"

GLAB_CONFIG_DIR="$tmp" glab auth login \
  --hostname gitlab.com \
  --web \
  --git-protocol ssh

pass insert --force --multiline tokens/gitlab/glab-oauth-config <"$tmp/config.yml"

rm -rf "$tmp"
```

Verify:

```sh
glabp auth status
```

## Optional aliases

The wrappers are intentionally named `ghp` and `glabp` so that normal `gh` and
`glab` remain available.

If the pass-backed wrappers should be the default in interactive shells, add
aliases outside the wrapper scripts:

```zsh
alias gh='ghp'
alias glab='glabp'
```

The wrappers call the underlying commands with `command gh` and `command glab`,
so these aliases do not recurse.

## Operational safety checks

Before using the repo-creation workflows below, run these checks when the
repository matters.

### Confirm wrapper authentication

```sh
ghp auth status
glabp auth status
```

### Confirm Git SSH authentication

```sh
ssh -T git@github.com
ssh -T git@gitlab.com
```

The wrappers do not replace SSH authentication. A working `ghp auth status` does
not prove that `git push` will work.

### Confirm the repository state

```sh
git status --short
git branch --show-current
git remote -v
git log --oneline --decorate --max-count=5
```

### Look for obvious accidental secrets before first publish

These checks are intentionally simple. They are not a substitute for secret
scanning, but they catch common mistakes before the first public or private
push.

```sh
git status --short
git diff --cached --name-only
git diff --cached --check
```

Also inspect files such as:

```text
.env
.envrc
*.key
*.pem
*_token*
*_secret*
config.yml
```

If any of those are intentionally local-only, add them to `.gitignore` before
committing.

## Common workflows

These examples assume:

- `ghp auth status` and `glabp auth status` already work
- Git push/pull uses SSH remotes
- the default branch should be `main`
- `OWNER` means a GitHub user or organization
- `NAMESPACE` means a GitLab user or group
- `REPO` means the repository/project name

For a single-forge repository, `origin` is conventional and usually fine.

For a repository hosted on both GitHub and GitLab, this README uses explicit
remote names:

```text
github
gitlab
```

That keeps day-to-day commands readable and avoids guessing what `origin` means.

### Start tracking an existing directory with Git

Use this when a directory already exists but is not yet a Git repository.

```sh
cd /path/to/project

git init --initial-branch=main
git status

git add .
git commit -m "Initial commit"
```

If the repository already exists but the current branch is not named `main`,
rename it:

```sh
git branch -M main
```

### Create a GitHub repo from the current directory and push it

Use this when the local directory already has at least one commit.

```sh
cd /path/to/project

ghp repo create OWNER/REPO \
  --private \
  --source=. \
  --remote=github \
  --push
```

For a public repository, use `--public` instead of `--private`.

If the repository should live under the authenticated GitHub user account, omit
`OWNER/`:

```sh
ghp repo create REPO \
  --private \
  --source=. \
  --remote=github \
  --push
```

Check the result:

```sh
git remote -v
git branch -vv
ghp repo view OWNER/REPO
```

### Create a GitLab repo with `glabp`, then push

Use this when you want the GitLab CLI to create the project before the first
push.

```sh
cd /path/to/project

glabp repo create NAMESPACE/REPO \
  --private \
  --defaultBranch main \
  --remoteName gitlab

repo_url="git@gitlab.com:NAMESPACE/REPO.git"
git remote get-url gitlab >/dev/null 2>&1 || git remote add gitlab "$repo_url"

git push gitlab main
```

For a public repository, use `--public` instead of `--private`.

If `glabp repo create` reports that the project already exists, inspect the
remote before changing anything:

```sh
git remote -v
glabp repo view NAMESPACE/REPO
```

### Create a GitLab project by first push

GitLab can create a private project when you push to a path that does not yet
exist, as long as your account has permission to create projects in the target
namespace.

```sh
cd /path/to/project

git remote add gitlab git@gitlab.com:NAMESPACE/REPO.git
git push gitlab main
```

If this is a GitLab-only repository and you want plain `git push` to target
GitLab in the future, set the upstream:

```sh
git push --set-upstream gitlab main
```

### Push the same existing directory to GitHub and GitLab

Use this for dual-hosted repositories.

```sh
cd /path/to/project

git init --initial-branch=main
git add .
git commit -m "Initial commit"

ghp repo create OWNER/REPO \
  --private \
  --source=. \
  --remote=github \
  --push

glabp repo create NAMESPACE/REPO \
  --private \
  --defaultBranch main \
  --remoteName gitlab

git remote get-url gitlab >/dev/null 2>&1 || \
  git remote add gitlab git@gitlab.com:NAMESPACE/REPO.git

git push gitlab main
```

Expected remote shape:

```text
github  git@github.com:OWNER/REPO.git (fetch)
github  git@github.com:OWNER/REPO.git (push)
gitlab  git@gitlab.com:NAMESPACE/REPO.git (fetch)
gitlab  git@gitlab.com:NAMESPACE/REPO.git (push)
```

### Add GitLab to a repo that already has GitHub

```sh
cd /path/to/project

git remote -v

glabp repo create NAMESPACE/REPO \
  --private \
  --defaultBranch main \
  --remoteName gitlab

git remote get-url gitlab >/dev/null 2>&1 || \
  git remote add gitlab git@gitlab.com:NAMESPACE/REPO.git

git push gitlab main
```

### Add GitHub to a repo that already has GitLab

```sh
cd /path/to/project

git remote -v

ghp repo create OWNER/REPO \
  --private \
  --source=. \
  --remote=github \
  --push
```

### Rename `origin` to a forge-specific remote name

Use this when a repository started with `origin`, but now has more than one
hosting remote.

If `origin` points to GitHub:

```sh
git remote rename origin github
git remote add gitlab git@gitlab.com:NAMESPACE/REPO.git
```

If `origin` points to GitLab:

```sh
git remote rename origin gitlab
git remote add github git@github.com:OWNER/REPO.git
```

Check:

```sh
git remote -v
```

### About `--set-upstream` / `-u`

`git push --set-upstream <remote> <branch>` records the upstream branch for the
current local branch. That is useful when one remote is primary.

For a dual-hosted repository, do not try to make both GitHub and GitLab the
upstream for the same local branch. A branch has one upstream. Push to secondary
remotes explicitly:

```sh
git push github main
git push gitlab main
```

Check the current upstream:

```sh
git branch -vv
```

### Normal push commands after setup

Push to GitHub:

```sh
git push github main
```

Push to GitLab:

```sh
git push gitlab main
```

Push to both:

```sh
git push github main && git push gitlab main
```

## Useful command reference

### Local Git state

```sh
git status
git status --short
git remote -v
git branch -vv
git log --oneline --decorate --max-count=5
```

### GitHub through `ghp`

```sh
ghp auth status
ghp repo view OWNER/REPO
ghp repo list --limit 10
ghp pr list
ghp api user
```

### GitLab through `glabp`

```sh
glabp auth status
glabp repo view NAMESPACE/REPO
glabp repo list --per-page 10
glabp mr list
glabp pipeline list
```

## Files that should not be tracked

Tracked in the dotfiles repo:

```text
wrapper scripts
README
deployment layout
```

Not tracked:

```text
tokens
OAuth config
password-store contents
~/.config/gh
~/.config/glab-cli
temporary runtime files
repository-local secrets
```

The dotfiles repository should contain the mechanism, not the credential state.

## Limitations

### `ghp` uses an environment variable

`ghp` passes the GitHub token through `GH_TOKEN` in the environment of the child
`gh` process.

That is the standard mechanism supported by GitHub CLI, but it means the token
exists in process environment memory while the command runs. This is acceptable
for the intended local threat model, but it is not process-level isolation.

### `glabp` persists only `config.yml`

`glabp` restores and persists only `config.yml`.

If a future `glab` version begins storing important auth state in additional
files under `GLAB_CONFIG_DIR`, those files will be discarded when the temporary
directory is removed. In that case, the wrapper should be revised.

### `glabp` treats the config as opaque

`glabp` does not parse or validate the GitLab CLI config format. That is
intentional. The wrapper avoids becoming a partial, fragile implementation of
GitLab CLI internals.

### The wrappers do not manage Git transport

`ghp` and `glabp` authenticate API-oriented CLI commands. They do not manage Git
SSH keys, Git credential helpers, known_hosts entries, remote URLs, or branch
upstreams.

## Troubleshooting

### `ghp: failed to read token from pass`

Check that this entry exists and is readable:

```sh
pass show tokens/github/gh-oauth
```

### `ghp: pass entry is empty`

The pass entry exists, but the first line is empty.

Edit it and make sure the token is on the first line:

```sh
pass edit tokens/github/gh-oauth
```

### `glabp: failed to read GitLab config from pass`

Check that this entry exists and contains a complete GitLab CLI config:

```sh
pass show tokens/gitlab/glab-oauth-config
```

### `ghp: missing dependency: gh`

Install GitHub CLI.

On Arch:

```sh
sudo pacman -S github-cli
```

### `glabp: missing dependency: glab`

Install GitLab CLI.

On Arch:

```sh
sudo pacman -S glab
```

### `glabp: missing dependency: sha256sum`

Install `coreutils`.

On Arch:

```sh
sudo pacman -S coreutils
```

### `glabp` works but keeps updating the pass entry

`glabp` writes back to `pass` only when the plaintext `config.yml` changes.

If this happens often, `glab` is probably refreshing or rewriting part of its
config. Occasional rewrites are expected for OAuth-backed authentication.
Frequent rewrites are worth inspecting by testing with a throwaway temporary
config directory.

### Git push fails even though wrapper auth works

The wrappers authenticate `gh` and `glab`. They do not authenticate Git SSH
transport.

Check SSH:

```sh
ssh -T git@github.com
ssh -T git@gitlab.com
```

Check remotes:

```sh
git remote -v
```

Check upstreams:

```sh
git branch -vv
```

### `remote origin already exists`

Use an explicit remote name or rename the existing remote.

For a GitHub remote:

```sh
git remote rename origin github
```

For a GitLab remote:

```sh
git remote rename origin gitlab
```

Then add the other remote explicitly.

## Maintenance checklist

After editing the wrappers:

```sh
zsh -n ~/.local/bin/ghp
zsh -n ~/.local/bin/glabp
```

Run read-only smoke tests:

```sh
ghp auth status
ghp repo list --limit 5

glabp auth status
glabp repo list --per-page 5
```

Check that normal CLI config locations were not repopulated unexpectedly:

```sh
find ~/.config/gh ~/.config/glab-cli -maxdepth 2 -type f 2>/dev/null
```

Check that no wrapper secrets are tracked:

```sh
git status --short
git ls-files | grep -Ei 'token|secret|oauth|config\.yml|\.env|\.pem|\.key' || true
```

## Hardening backlog

These are optional improvements, not requirements for the current design.

- add a small `forge-cli-auth doctor` script for dependency and config checks
- add shell tests for missing dependencies, empty pass entries, and temp cleanup
- add a `README.security.md` if the package grows beyond two wrappers
- support non-`gitlab.com` hosts with documented examples
- document minimum token scopes for the intended `gh` and `glab` workflows
- consider rejecting execution when shell tracing is enabled in the parent shell,
  if that becomes operationally useful
- periodically verify whether `glab` still stores all required auth state in
  `config.yml`

## Summary

`forge-cli-auth` is intentionally small.

It does one thing: it makes `gh` and `glab` convenient to use while keeping their
durable authentication state in `pass` instead of the default CLI config
locations.

It is not a substitute for endpoint security, repository hygiene, SSH key
management, token scoping, or secret scanning. It is a clean, auditable boundary
around one specific credential-handling decision.
