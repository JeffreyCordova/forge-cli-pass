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

1. Creates a private temporary directory.
2. Restores the saved `config.yml` into that directory.
3. Runs `glab` with `GLAB_CONFIG_DIR` pointed at that temporary directory.
4. Checks whether `glab` changed the config.
5. Writes the updated config back to `pass` only if it changed.
6. Deletes the temporary directory.

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

Required:

```text
zsh
pass
gh
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

## Troubleshooting

### `ghp: failed to read token from pass`

Check that this exists:

```sh
pass show tokens/github/gh-oauth
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

### `glabp` works but keeps updating the pass entry

`glabp` only writes back to `pass` when the plaintext `config.yml` changes.

If this happens frequently, `glab` is probably refreshing or rewriting some part
of its config. That is expected occasionally for OAuth-backed authentication.

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
