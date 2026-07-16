# forge-cli-pass

Command-compatible wrappers for ordinary authenticated GitHub CLI and GitLab CLI operations, with [`pass`](https://www.passwordstore.org/) as the authoritative credential store.

The project provides two commands:

- `gh-pass` wraps `gh`
- `glab-pass` wraps `glab`

Both commands preserve the parent CLI’s ordinary argument interface while preventing the parent CLI from becoming the durable owner of wrapper-managed credentials.

## Why

The GitHub CLI and GitLab CLI expose different authentication interfaces.

`gh-pass` retrieves a token from `pass` and supplies its first line to `gh` through `GH_TOKEN`.

`glab-pass` restores a complete GitLab CLI configuration from `pass` into a private temporary directory, runs `glab` against that staged state, and writes eligible changes back to `pass`.

This gives both providers the same durable credential boundary:

> Wrapper-managed authentication state belongs in `pass`, not in persistent parent-CLI configuration.

Git transport is independent of these wrappers. SSH remains the recommended transport for Git remotes.

## Status

The project currently targets Linux and the following POSIX shell environments:

- Dash
- Bash in POSIX mode
- BusyBox `ash`

The wrappers are tested against ordinary success and failure paths, credential-policy enforcement, temporary-state handling, writeback behavior, cleanup failures, and handled signals.

The project has not yet published a stable tagged release.

## Requirements

### `gh-pass`

- A POSIX-compatible `sh`
- `pass`
- `gh`

### `glab-pass`

- A POSIX-compatible `sh`
- `pass`
- `glab`
- `mktemp`
- `sha256sum`
- `chmod`
- `rm`

The commands named above must be available through `PATH`.

## Installation

The default installation prefix is `/usr/local`:

```sh
make install
```

The Makefile does not invoke a privilege-management command. Run it with the privileges appropriate for the selected destination, or choose a user-owned prefix.

For a user-local installation:

```sh
make install PREFIX="$HOME/.local"
```

Ensure that the resulting binary directory is in `PATH`:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

An explicit binary directory can be selected independently:

```sh
make install BINDIR="$HOME/bin"
```

Packaging and staged installations may use `DESTDIR`:

```sh
make install DESTDIR="$package_root" PREFIX=/usr
```

This installs:

```text
$package_root/usr/bin/gh-pass
$package_root/usr/bin/glab-pass
```

To remove a copied installation:

```sh
make uninstall PREFIX="$HOME/.local"
```

`uninstall` removes only the two project command paths. It does not remove the containing directory or unrelated files.

## Development installation

A development installation creates absolute symbolic links to the current checkout:

```sh
make dev-install PREFIX="$HOME/.local"
```

The operation is intentionally guarded:

- An expected existing link is accepted.
- An unrelated symbolic link is not replaced.
- A regular file or other existing path is not replaced.

Remove only links owned by the current checkout with:

```sh
make dev-uninstall PREFIX="$HOME/.local"
```

`dev-uninstall` refuses to remove copied installations or symbolic links pointing somewhere else.

## GitHub credential setup

The default GitHub entry is:

```text
forge-cli-pass/github/token
```

Create it with:

```sh
pass insert forge-cli-pass/github/token
```

The first line must contain the GitHub token.

Only the first line is injected into `GH_TOKEN`. Additional lines may be retained as operator notes, but they are not passed to `gh`.

To use another entry:

```sh
export FORGE_CLI_PASS_GITHUB_ENTRY='work/github/token'
```

An explicitly empty override is an error. The wrapper does not fall back to another entry or attempt credential discovery.

## GitLab credential setup

The default GitLab entry is:

```text
forge-cli-pass/gitlab/oauth-config
```

The entry contains the complete opaque `glab` configuration file rather than a single extracted token.

### Initial bootstrap

Run `glab auth login` directly against an isolated temporary configuration directory, then store the resulting file in `pass`:

```sh
(
    set -eu

    bootstrap_dir=$(mktemp -d)
    trap 'rm -rf -- "$bootstrap_dir"' 0 HUP INT TERM

    chmod 700 "$bootstrap_dir"

    GLAB_CONFIG_DIR="$bootstrap_dir" \
        glab auth login

    test -s "$bootstrap_dir/config.yml"

    pass insert -m \
        forge-cli-pass/gitlab/oauth-config \
        <"$bootstrap_dir/config.yml"
)
```

The temporary directory is removed when the subshell exits.

After the entry has been created, ordinary authenticated operations should be run through `glab-pass`, not through persistent default `glab` authentication state.

To use another entry:

```sh
export FORGE_CLI_PASS_GITLAB_ENTRY='work/gitlab/oauth-config'
```

As with the GitHub override, an explicitly empty or structurally invalid entry name is rejected without fallback or discovery.

## Usage

Arguments are forwarded to the corresponding parent CLI without reordering or recombination.

### GitHub

```sh
gh-pass repo view
gh-pass issue list
gh-pass api repos/OWNER/REPOSITORY
```

### GitLab

```sh
glab-pass repo view
glab-pass issue list
glab-pass api projects/PROJECT_ID
```

Empty arguments, arguments containing spaces, and shell metacharacters remain distinct parent arguments.

## Authentication-command policy

These wrappers support ordinary authenticated operations. They are not interfaces for managing or disclosing wrapper-owned credentials.

Non-disclosing authentication status commands are allowed:

```sh
gh-pass auth status
glab-pass auth status
```

Credential-management and credential-disclosure operations are rejected before credential retrieval or staging. Examples include:

```sh
gh-pass auth login
gh-pass auth logout
gh-pass auth token
gh-pass auth status --show-token
gh-pass auth status -t

glab-pass auth login
glab-pass auth logout
glab-pass auth status --show-token
```

Unknown `auth` subcommands are also rejected. This prevents a future parent-CLI authentication command from silently bypassing the wrapper’s credential-ownership policy.

Arguments that merely contain auth-like text outside the parent CLI’s `auth` command namespace are forwarded normally.

## GitHub runtime behavior

For each accepted invocation, `gh-pass`:

1. Resolves the configured `pass` entry.
2. Reads the complete entry.
3. Selects the first line as the token.
4. Rejects an empty first line.
5. Clears the complete retrieved value.
6. Executes `gh` with `GH_TOKEN` set to the selected token.

Because the wrapper replaces itself with `gh`, the parent CLI’s exit status is returned directly.

## GitLab runtime behavior

For each accepted invocation, `glab-pass`:

1. Creates a private temporary directory beneath `/tmp`.
2. Protects the directory with mode `0700`.
3. Restores the complete `pass` entry as `config.yml`.
4. Protects the staged file with mode `0600`.
5. Records the initial-state fingerprint.
6. Runs `glab` with `GLAB_CONFIG_DIR` pointing to the temporary directory.
7. Validates and fingerprints the post-command state.
8. Writes changed eligible state back to `pass`.
9. Removes the temporary directory.

Eligible post-command state must be:

- Present
- A regular file
- Readable
- Nonempty
- Different from the initial state

Changed eligible state is written back after both successful and ordinarily unsuccessful `glab` execution. This preserves authentication refreshes or other legitimate state mutations that occur before the parent command exits.

## Signals and exit statuses

The wrappers use these status rules:

- An ordinary parent status is preserved when all wrapper obligations succeed.
- An ordinary wrapper failure returns status `1`.
- Handled `HUP`, `INT`, and `TERM` preserve statuses `129`, `130`, and `143`.
- A required writeback or cleanup failure overrides an ordinary parent status.
- During handled-signal processing, writeback or cleanup failures are reported without replacing the signal-derived status.

Signal-time writeback is attempted only when staged GitLab state remains eligible.

## Security boundaries

The wrappers are designed to prevent durable wrapper-managed credentials from being left in parent-CLI authentication storage.

They do not protect against:

- A compromised local account
- A compromised shell, parent CLI, `pass`, GPG agent, or operating system
- A malicious executable earlier in `PATH`
- Parent-CLI vulnerabilities
- Credentials deliberately printed or transmitted by an ordinary parent command
- Insecure Git remote or SSH configuration

The wrappers disable shell tracing before handling credentials, but callers remain responsible for their surrounding process and logging environment.

See [SECURITY.md](SECURITY.md) for vulnerability-reporting guidance.

## Verification

Run the complete local verification interface with:

```sh
make check
```

The check includes:

- ShellCheck in POSIX `sh` mode
- Syntax checks under Dash
- Syntax checks under Bash POSIX mode
- Syntax checks under BusyBox `ash`
- Behavioral tests under all three shells
- Installation and development-link tests

The behavioral suite injects fake utilities through `PATH`. Some BusyBox builds prefer internal applets even when a matching external command appears earlier in `PATH`. Such a build cannot run the complete failure-injection matrix.

A compatible BusyBox executable may be supplied explicitly:

```sh
make check BUSYBOX=/path/to/busybox
```

The test runner verifies the required `PATH` behavior before starting the matrix. Failure of that test-specific probe does not by itself demonstrate a runtime incompatibility with the wrappers.

The current verification suite contains:

- 141 wrapper test executions across three shells
- 8 installation and development-link tests
- 149 total behavioral test executions

### Continuous integration

The primary GitHub repository runs the same `make check` interface for pull requests, pushes to `main`, and manual workflow runs.

CI builds a pinned, test-only BusyBox `ash` executable whose configuration permits the failure-injection fixtures to take precedence through `PATH`. The downloaded source archive is verified before it is built.

The workflow does not use forge credentials, password-store contents, or real authentication state.

The GitLab repository is currently a mirror and does not run a duplicate pipeline.

## Documentation

- [Architecture](docs/architecture.md)
- [Project context](docs/project-context.md)
- [Architecture decision records](docs/decisions/)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## License

Licensed under the [Apache License 2.0](LICENSE).

The SPDX license identifier is:

```text
Apache-2.0
```

## Contributing

Contributions should preserve the documented credential-ownership boundary, POSIX shell portability, argument fidelity, and failure semantics.

Run the complete verification interface before submitting a change:

```sh
make check BUSYBOX=/path/to/compatible/busybox
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the project workflow.
