# Forge CLI Auth Wrappers

`forge-cli-auth` is a small dotfiles package that provides pass-backed
authentication wrappers for source-code forge CLIs.

In this context, a **forge** means a source-code collaboration platform such as
GitHub, GitLab, Gitea, Forgejo, SourceHut, or Bitbucket.

The current wrappers are:

- `ghp` — pass-backed wrapper for GitHub CLI, `gh`
- `glabp` — pass-backed wrapper for GitLab CLI, `glab`

The goal is to keep GitHub/GitLab CLI authentication out of the normal `gh` and
`glab` config locations while still making the tools convenient to use from the
terminal.

## Commands

### `ghp`

`ghp` is a wrapper around `gh`.

It reads a GitHub token from:

```text
tokens/github/gh-oauth
```

Then it runs `gh` with that token provided through `GH_TOKEN`.

Only the first line of the pass entry is used. This allows the pass entry to use
the common password-store convention where the first line is the secret and
later lines contain notes or metadata.

Example pass entry:

```text
gho_xxxxxxxxxxxxxxxxxxxx
host: github.com
purpose: GitHub CLI wrapper token
```

Implementation notes:

- runs under `zsh`
- uses `emulate -R zsh`
- disables shell xtrace with `unsetopt xtrace`
- sets `umask 077`
- requires `pass` and `gh`
- calls the real command with `command gh "$@"`

Example usage:

```sh
ghp auth status
ghp repo view
ghp pr list
ghp api user
```

### `glabp`

`glabp` is a wrapper around `glab`.

It reads a complete GitLab CLI config file from:

```text
tokens/gitlab/glab-oauth-config
```

At runtime, it:

1. Chooses a runtime base directory from `XDG_RUNTIME_DIR`, falling back to
   `/tmp` if needed.
2. Creates a private temporary directory named like `glab-pass.XXXXXX`.
3. Restores the saved `config.yml` into that directory.
4. Secures the directory with mode `700` and the config file with mode `600`.
5. Hashes the restored `config.yml`.
6. Runs `glab` with `GLAB_CONFIG_DIR` pointed at the temporary directory.
7. Hashes `config.yml` again after `glab` exits.
8. Writes the updated config back to `pass` only if the config changed.
9. Deletes the temporary directory on exit.

Implementation notes:

- runs under `zsh`
- uses `emulate -R zsh`
- disables shell xtrace with `unsetopt xtrace`
- sets `umask 077`
- requires `pass`, `glab`, `mktemp`, and `sha256sum`
- calls the real command with `command glab "$@"`
- treats `config.yml` as an opaque file
- does not parse or modify the GitLab CLI config itself

Example usage:

```sh
glabp auth status
glabp repo view
glabp mr list
glabp pipeline list
```

## Install

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

Make sure `~/.local/bin` is in `PATH`.

```sh
echo "$PATH"
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

## Required pass entries

### GitHub

Required pass entry:

```text
tokens/github/gh-oauth
```

Create it manually:

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

`ghp` uses only the first line.

### GitLab

Required pass entry:

```text
tokens/gitlab/glab-oauth-config
```

This entry should contain the full `glab` `config.yml` content, not just a token.

One way to bootstrap it is to authenticate `glab` once using a temporary config
directory, then store that config in `pass`.

Example:

```sh
tmp="$(mktemp -d)"
chmod 700 "$tmp"

GLAB_CONFIG_DIR="$tmp" glab auth login --hostname gitlab.com --web --git-protocol ssh

pass insert --force --multiline tokens/gitlab/glab-oauth-config <"$tmp/config.yml"

rm -rf "$tmp"
```

After that, use:

```sh
glabp auth status
```

## Optional aliases

These wrappers are intentionally named `ghp` and `glabp` so that normal `gh` and
`glab` remain available.

If you want the pass-backed wrappers to be the default in interactive shells,
add aliases separately:

```zsh
alias gh='ghp'
alias glab='glabp'
```

The wrappers themselves call the underlying commands with `command gh` and
`command glab`, so these aliases do not cause recursion.

## Common workflows

These examples assume:

- `ghp auth status` and `glabp auth status` already work
- Git push/pull uses SSH remotes
- the default branch should be `main`
- `OWNER` means a GitHub user or organization
- `NAMESPACE` means a GitLab user or group
- `REPO` means the repository/project name

For single-forge repositories, the conventional remote name is usually `origin`.
For repositories pushed to both GitHub and GitLab, this README uses explicit
remote names:

```text
github
gitlab
```

That avoids ambiguity when the same local repository has two hosting remotes.

### Start tracking an existing directory with Git

Use this when a directory already exists but is not yet a Git repository.

```sh
cd /path/to/project

git init --initial-branch=main
git status

git add .
git commit -m "Initial commit"
```

If the repository already exists but the branch name is not `main`, rename the
current branch:

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
ghp repo create REPO --private --source=. --remote=github --push
```

Check the result:

```sh
git remote -v
git branch -vv
ghp repo view OWNER/REPO
```

### Create a GitLab repo from the current directory with `glabp`

Use this when you want `glab` to create the GitLab project, then push with Git.

```sh
cd /path/to/project

glabp repo create NAMESPACE/REPO \
  --private \
  --defaultBranch main \
  --remoteName gitlab

git remote -v
git push gitlab main
```

For a public repository, use `--public` instead of `--private`.

If the remote was not added automatically, add it manually and push:

```sh
git remote add gitlab git@gitlab.com:NAMESPACE/REPO.git
git push gitlab main
```

### Create a GitLab repo by pushing to it

GitLab can create a new private project on first push if your account has
permission to create projects in the target namespace.

```sh
cd /path/to/project

git remote add gitlab git@gitlab.com:NAMESPACE/REPO.git
git push gitlab main
```

For a GitLab-only repository where you want `gitlab/main` to become the branch's
upstream, use:

```sh
git push --set-upstream gitlab main
```

### Push the same existing directory to GitHub and GitLab

Use this when a local repository should have both hosting remotes.

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

git push gitlab main
```

Check the remotes:

```sh
git remote -v
```

Expected shape:

```text
github  git@github.com:OWNER/REPO.git (fetch)
github  git@github.com:OWNER/REPO.git (push)
gitlab  git@gitlab.com:NAMESPACE/REPO.git (fetch)
gitlab  git@gitlab.com:NAMESPACE/REPO.git (push)
```

### Add GitLab to a repo that already has GitHub

Use this when the repository already exists locally and already has a GitHub
remote.

```sh
cd /path/to/project

git remote -v

glabp repo create NAMESPACE/REPO \
  --private \
  --defaultBranch main \
  --remoteName gitlab

git push gitlab main
```

If needed, add the remote manually:

```sh
git remote add gitlab git@gitlab.com:NAMESPACE/REPO.git
git push gitlab main
```

### Add GitHub to a repo that already has GitLab

Use this when the repository already exists locally and already has a GitLab
remote.

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

Use this when a repository started with `origin`, but you now want clearer names
for multi-forge hosting.

```sh
git remote rename origin github
```

Then add the other forge remote:

```sh
git remote add gitlab git@gitlab.com:NAMESPACE/REPO.git
```

Or, if `origin` currently points to GitLab:

```sh
git remote rename origin gitlab
git remote add github git@github.com:OWNER/REPO.git
```

### About `--set-upstream` / `-u`

`git push --set-upstream <remote> <branch>` records a tracking relationship for
the current branch. That is useful for a single primary remote.

For a repository with both GitHub and GitLab remotes, do not set both as the
upstream for the same branch. A local branch should have one upstream. Push to
additional remotes explicitly:

```sh
git push github main
git push gitlab main
```

Check the current upstream with:

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

### Useful repo-check commands

```sh
git status
git remote -v
git branch -vv
git log --oneline --decorate --max-count=5
```

GitHub:

```sh
ghp repo view OWNER/REPO
ghp repo list --limit 10
ghp pr list
```

GitLab:

```sh
glabp repo view NAMESPACE/REPO
glabp repo list --per-page 10
glabp mr list
```

## Security model

These wrappers protect against accidental long-term storage of GitHub/GitLab CLI
credentials in the default CLI config locations.

Tracked in git:

```text
wrapper scripts
README
deployment layout
```

Not tracked in git:

```text
tokens
OAuth config
password-store contents
~/.config/gh
~/.config/glab-cli
temporary runtime files
```

The wrappers assume:

- the local user account is trusted
- the local `pass` store is trusted
- GPG private keys are protected appropriately
- commands are not run with shell tracing enabled
- untrusted `gh` or `glab` extensions are not invoked through these wrappers

## Limitations

`ghp` passes the GitHub token through the process environment as `GH_TOKEN`.

That is the normal mechanism supported by `gh`, but it means the token exists in
the environment of the `gh` process while the command runs.

`glabp` restores the GitLab CLI config to a temporary directory for the duration
of the command. The temporary directory is created with restrictive permissions
and removed after the command exits.

`glabp` treats `config.yml` as an opaque file. If future versions of `glab`
start storing important auth state in additional files under `GLAB_CONFIG_DIR`,
the wrapper may need to be revised.

`glabp` persists only `config.yml`. If `glab` creates additional files in the
runtime config directory, those files are discarded when the temporary directory
is removed.

The wrappers do not manage Git SSH keys. They only affect CLI authentication for
`gh` and `glab`. Git pushes and pulls still depend on your Git remote URLs and
SSH configuration.

## Troubleshooting

### `ghp: failed to read token from pass`

Check that this exists:

```sh
pass show tokens/github/gh-oauth
```

### `ghp: pass entry is empty`

The pass entry exists, but the first line is empty.

Edit the entry and make sure the token is on the first line:

```sh
pass edit tokens/github/gh-oauth
```

### `glabp: failed to read GitLab config from pass`

Check that this exists:

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

`glabp` only writes back to `pass` when the plaintext `config.yml` changes.

If this happens frequently, `glab` is probably refreshing or rewriting some part
of its config. That is expected occasionally for OAuth-backed authentication.

### Git push fails even though `ghp` or `glabp` auth works

The wrappers authenticate the CLI tools. They do not authenticate Git SSH
transport.

Check SSH separately:

```sh
ssh -T git@github.com
ssh -T git@gitlab.com
```

Then check the remote URLs:

```sh
git remote -v
```

## Test commands

```sh
ghp auth status
glabp auth status
```

Then try normal read-only commands:

```sh
ghp repo list --limit 5
glabp repo list --per-page 5
```
