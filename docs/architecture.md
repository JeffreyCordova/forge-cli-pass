
# Architecture

## Purpose

This document describes the integrated current architecture of
`forge-cli-pass`.

The project provides two provider-specific commands:

```text
gh-pass
glab-pass
```

They are command-compatible wrappers for ordinary authenticated operations
performed by:

```text
gh
glab
```

The wrappers retrieve durable credential state from `pass`, introduce it only
for the active parent CLI invocation, and avoid retaining wrapper-managed
authentication state in the parent CLIs' default configuration locations.

This document explains the resulting system as a whole.

The accepted architecture decision records remain authoritative for the
rationale behind individual decisions.

## Document authority

Project documentation has the following authority order:

1. accepted architecture decision records
2. this integrated architecture document
3. `docs/project-context.md`
4. user-facing documentation such as `README.md`
5. implementation and tests as evidence of conformance

Accepted ADRs define the governing architectural decisions.

This document must remain consistent with those decisions. When an accepted ADR
and this document conflict, the ADR governs until the conflict is corrected.

Implementation and tests must conform to the accepted architecture. Existing
code does not override an accepted decision merely because it predates that
decision.

## Accepted decision set

The current architecture incorporates:

| ADR | Decision |
|---|---|
| 0001 | Use provider-specific commands |
| 0002 | Adopt the `forge-cli-pass`, `gh-pass`, and `glab-pass` identity |
| 0003 | Treat `pass` as the authoritative durable credential store |
| 0004 | Use POSIX shell with an initial Linux support contract |
| 0005 | Define GitLab runtime staging and ordinary writeback |
| 0006 | Define failure and exit-status semantics |
| 0007 | Conditionally persist GitLab state after handled signals |
| 0008 | Restrict credential-management commands |
| 0009 | Use default `pass` entries with environment overrides |
| 0010 | Use copy-based Make installation and tagged source releases |

## System summary

`forge-cli-pass` separates Git transport authentication from forge API
authentication.

The intended operating model is:

```text
Git transport
    SSH

Forge CLI and API authentication
    scoped access or OAuth credentials

Authoritative durable credential state
    GPG-encrypted pass entries

Runtime credential delivery
    per-command environment injection or temporary staging

Persistent wrapper-managed parent CLI login state
    not retained
```

The two wrappers use different runtime mechanisms because the parent CLIs have
different credential-state requirements.

### GitHub

`gh-pass` retrieves a token from `pass` and supplies it to `gh` through
`GH_TOKEN` for the parent process.

No wrapper-managed GitHub CLI config file is required.

### GitLab

`glab-pass` retrieves a complete GitLab CLI authentication-state payload from
`pass`, stages it as `config.yml` in a private directory beneath `/tmp`, and
runs `glab` with `GLAB_CONFIG_DIR` directed to that directory.

Because GitLab authentication state may change during execution, `glab-pass`
detects mutations and conditionally writes changed state back to `pass` before
removing the runtime directory.

## Goals

The architecture is intended to:

- keep durable wrapper-managed forge API credential state in `pass`
- avoid routine persistent authentication state in parent CLI default config
  locations
- support ordinary authenticated `gh` and `glab` operations
- preserve parent CLI argument boundaries
- preserve parent exit statuses when wrapper obligations succeed
- make wrapper lifecycle failures visible
- minimize persistent plaintext credential residue
- keep credential-handling code small enough for direct review
- support static analysis and isolated behavioral testing
- support Linux systems without requiring zsh
- provide deterministic credential selection
- provide a conventional installation interface
- fail closed for unreviewed credential-management behavior

## Non-goals

The project does not:

- replace `pass` or GPG
- provide a new credential vault
- provide process isolation
- protect credentials from the invoking user
- protect against a compromised local account
- protect against a compromised parent CLI
- manage Git SSH keys
- manage HTTPS Git credentials
- manage Git remotes
- manage `known_hosts`
- manage commit or tag signing keys
- create forge accounts
- create access tokens
- revoke server-side credentials
- implement OAuth
- parse GitLab OAuth fields
- reproduce the complete `gh` or `glab` command parser
- prevent direct invocation of `gh` or `glab`
- configure Git or Docker credential helpers
- provide multi-user policy enforcement
- guarantee forensic erasure
- initially support non-Linux operating systems
- initially provide native distribution packages
- automatically update itself

## Terminology

### Forge

A source-code collaboration platform such as GitHub or GitLab.

The initial implementation supports only GitHub and GitLab.

### Parent CLI

The underlying provider CLI executed by a wrapper:

| Wrapper | Parent CLI |
|---|---|
| `gh-pass` | `gh` |
| `glab-pass` | `glab` |

### Forge API credential

Credential state used by a parent CLI to authenticate API-oriented operations.

This is separate from Git transport authentication.

### Credential material

A token, refresh token, OAuth configuration, or other data that can participate
in authentication.

### Authentication state

The complete state required by a parent CLI to continue an authenticated
session.

For GitLab, this may be broader than one standalone token.

### Durable credential state

The authoritative encrypted credential representation stored in `pass`.

### Runtime credential material

Credential material made available only for an active wrapper invocation.

### Credential injection

Supplying credential material to a parent process through its environment.

`gh-pass` uses credential injection through `GH_TOKEN`.

### Credential staging

Materializing credential state temporarily in a private filesystem location.

`glab-pass` uses credential staging through `GLAB_CONFIG_DIR`.

### Writeback

Persisting changed staged GitLab authentication state to the authoritative
`pass` entry.

### Persistent credential residue

Credential material or reusable authentication state remaining after the
wrapper invocation has completed.

### Wrapper-managed credential state

Credential state whose lifecycle is controlled by `gh-pass` or `glab-pass`.

This excludes unrelated operator-managed parent CLI state created through direct
use of `gh` or `glab`.

## Architectural invariants

### 1. `pass` is authoritative

The selected `pass` entry is the only durable credential source used by a
wrapper invocation.

The wrappers do not fall back to:

- native parent CLI authentication state
- an operating-system keyring
- a desktop credential service
- another pass entry
- a plaintext credential file
- interactive login
- automatic account discovery

### 2. Credential provenance is deterministic

Each invocation uses exactly one selected `pass` entry.

That entry results from either:

- the documented built-in default
- one explicit environment-variable override

Failure to access the selected entry does not trigger another credential lookup.

### 3. Runtime exposure is bounded

Credential material is introduced only through the mechanism required by the
selected parent CLI:

```text
GitHub token
    GH_TOKEN in the gh process environment

GitLab authentication state
    config.yml beneath a private temporary GLAB_CONFIG_DIR
```

The wrappers do not intentionally copy credentials into other runtime
locations.

### 4. Parent CLI default authentication state is not authoritative

The wrappers do not intentionally create or rely on wrapper-managed
authentication state in the parent CLIs' normal persistent configuration
locations.

Direct operator use of an unwrapped parent CLI remains outside this invariant.

### 5. GitLab mutation is preserved when safe enough to do so

After ordinary parent completion, changed, structurally valid GitLab
authentication state is written back to `pass`, including after a nonzero
parent status.

After handled signal termination, changed state is written back only when the
parent has terminated and the staged file remains eligible under the
signal-time structural checks.

### 6. Plaintext GitLab state is cleaned up

`glab-pass` attempts to remove its complete private runtime directory after
every path on which runtime state was created.

Cleanup failure is a material wrapper failure during ordinary completion.

After handled signal termination, cleanup failure is reported while the
signal-derived status remains final.

### 7. Credential-management behavior fails closed

Within the parent `auth` namespace, only explicitly supported status and help
operations are allowed.

Unknown or credential-mutating `auth` operations are rejected before parent
execution.

### 8. Parent behavior is preserved within the compatibility boundary

For supported operations, wrapper arguments retain their order and boundaries
and are delegated to the parent CLI.

The wrapper does not reconstruct the parent command as a shell string.

### 9. Wrapper failures remain visible

The parent status is preserved only when all required wrapper lifecycle
operations succeed.

A wrapper lifecycle failure during ordinary execution returns status `1`.

## System context

### GitHub path

```text
Operator
   |
   | gh-pass <arguments>
   v
gh-pass
   |
   | pass show <selected GitHub entry>
   v
pass and GPG
   |
   | first-line token
   v
gh-pass
   |
   | GH_TOKEN=<token> exec gh <arguments>
   v
GitHub CLI
   |
   | authenticated API operations
   v
GitHub
```

### GitLab path

```text
Operator
   |
   | glab-pass <arguments>
   v
glab-pass
   |
   | pass show <selected GitLab entry>
   v
pass and GPG
   |
   | complete opaque config.yml payload
   v
private /tmp/glab-pass.XXXXXX directory
   |
   | GLAB_CONFIG_DIR=<runtime directory>
   v
GitLab CLI
   |
   | authenticated API operations and possible state mutation
   v
GitLab

After parent completion:
   staged config validation
        |
        +-- unchanged --> cleanup
        |
        +-- changed ----> pass writeback --> cleanup
```

## Components

## `gh-pass`

`gh-pass` is a POSIX shell wrapper for GitHub CLI.

Its responsibilities are:

- normalize security-relevant shell state
- enforce the credential-management command policy
- resolve the GitHub pass-entry name
- validate required non-baseline dependencies
- retrieve the selected pass entry
- extract the first line as the GitHub token
- reject missing or empty token material
- scope the token to the parent process through `GH_TOKEN`
- replace itself with `gh`
- preserve parent arguments exactly

It does not perform post-command writeback or filesystem cleanup.

After successful validation, its final invocation is equivalent to:

```sh
GH_TOKEN=$token exec gh "$@"
```

Process replacement means that normal output, signals, and exit status are then
owned directly by `gh`.

## `glab-pass`

`glab-pass` is a POSIX shell wrapper for GitLab CLI.

Its responsibilities are:

- normalize security-relevant shell state
- enforce the credential-management command policy
- resolve the GitLab pass-entry name
- validate required non-baseline dependencies
- create and protect a private runtime directory
- restore the complete opaque GitLab configuration
- establish required file permissions
- fingerprint the initial state
- invoke `glab` with a private `GLAB_CONFIG_DIR`
- record the parent status
- coordinate handled signals with the child process
- validate post-command staged state
- detect changes
- perform required ordinary or signal-time writeback
- remove temporary plaintext state
- calculate the final status
- report material lifecycle failures

Because post-command processing is required, `glab-pass` cannot normally replace
itself with `glab`.

## Credential-entry configuration

### GitHub

Default entry:

```text
forge-cli-pass/github/token
```

Override variable:

```text
FORGE_CLI_PASS_GITHUB_ENTRY
```

### GitLab

Default entry:

```text
forge-cli-pass/gitlab/oauth-config
```

Override variable:

```text
FORGE_CLI_PASS_GITLAB_ENTRY
```

### Resolution rules

For each wrapper:

```text
override unset
    use built-in default

override set and non-empty
    use override

override set but empty
    wrapper failure

override contains newline or carriage return
    wrapper failure
```

The selected value is passed to `pass` as one quoted argument.

The wrappers do not:

- accept an entry-selection command-line option
- parse a project configuration file
- search the password store
- infer an entry from a Git remote
- infer an account from a hostname
- remember a previous selection
- fall back after selection failure

### Interaction with `pass`

Configuration owned by `pass` remains active.

For example, the wrapper does not replace or reinterpret:

```text
PASSWORD_STORE_DIR
PASSWORD_STORE_GPG_OPTS
```

The wrapper controls only the entry name it requests.

## GitHub credential representation

The GitHub pass entry contains the token on its first line.

Example structure:

```text
<GitHub token>
optional operator notes
optional metadata
```

Only the first line is credential input to `gh-pass`.

Later lines are ignored by the wrapper.

The wrapper must reject an empty first line even when later lines contain data.

The token is not:

- written to a file by `gh-pass`
- printed by the wrapper
- exported persistently by the wrapper
- inserted into a reconstructed command string
- retained after successful process replacement beyond the lifetime of `gh`

The token necessarily exists in process memory and in the environment supplied
to the `gh` process.

## GitLab credential representation

The GitLab pass entry contains the complete GitLab CLI authentication-state
payload expected as:

```text
config.yml
```

The payload is opaque to `glab-pass`.

The wrapper does not:

- parse YAML fields
- identify individual access or refresh tokens
- validate OAuth semantics
- merge selected fields
- implement token refresh
- reconstruct the configuration
- classify individual parent mutations

The complete payload is restored and, when required, written back as one unit.

## GitHub execution lifecycle

The intended `gh-pass` lifecycle is:

1. disable inherited command tracing
2. establish `umask 077`
3. classify the requested operation under the credential-management policy
4. reject unsupported `auth` operations
5. resolve and validate the selected pass entry
6. validate `pass` and `gh`
7. retrieve the selected entry
8. extract the first line
9. reject an empty token
10. invoke `gh` through process replacement with `GH_TOKEN`
11. allow `gh` to own normal output, signals, and final status

Credential-policy rejection should occur before credential retrieval when the
command can be classified safely at that stage.

## GitLab ordinary execution lifecycle

The intended ordinary `glab-pass` lifecycle is:

1. disable inherited command tracing
2. establish `umask 077`
3. classify the requested operation under the credential-management policy
4. reject unsupported `auth` operations
5. resolve and validate the selected pass entry
6. validate `pass`, `glab`, `mktemp`, and `sha256sum`
7. verify that `/tmp` is a usable staging parent
8. create a private runtime directory beneath `/tmp`
9. apply directory mode `0700`
10. restore the pass entry as `config.yml`
11. apply config-file mode `0600`
12. validate the initial staged file
13. compute the initial content fingerprint
14. invoke `glab` with `GLAB_CONFIG_DIR` scoped to the runtime directory
15. record the exact parent status immediately
16. validate the post-command staged config
17. compute the post-command fingerprint
18. write changed state back to `pass` when required
19. attempt complete runtime-directory cleanup
20. determine the final status under the failure model
21. report every material wrapper failure

### Runtime staging location

The runtime directory is always created beneath:

```text
/tmp
```

The accepted creation form is:

```sh
mktemp -d /tmp/glab-pass.XXXXXX
```

The wrapper does not use:

```text
XDG_RUNTIME_DIR
HOME
the current working directory
a repository-local directory
the parent CLI default config directory
```

The wrapper uses a fixed shared parent and a private unpredictable child
directory.

### Runtime permissions

Required permissions are:

```text
runtime directory    0700
config.yml           0600
```

`umask 077` is established before runtime credential material is created.

The wrapper also applies the required permissions defensively.

Failure to establish the required permissions prevents normal parent execution
or becomes a wrapper lifecycle failure, depending on when it occurs.

### Initial staged-state requirements

Before `glab` is invoked, the config must:

- exist
- be a regular file
- be readable by the invoking user
- be non-empty
- be fingerprintable

Failure prevents parent execution.

### Parent invocation

The parent process receives:

```text
GLAB_CONFIG_DIR=<private runtime directory>
```

The environment assignment is scoped to the `glab` invocation.

All supported parent arguments are forwarded in their original order and
boundaries through:

```sh
glab "$@"
```

or an equivalent non-evaluating invocation.

### Change detection

The wrapper computes a SHA-256 content fingerprint before and after ordinary
parent completion.

The fingerprint answers only:

```text
Did the staged file content change?
```

It does not establish:

- authenticity
- trusted integrity
- semantic validity
- provenance
- successful OAuth refresh
- legitimacy of the mutation

### Unchanged state

When the post-command fingerprint matches the initial fingerprint:

- no pass writeback occurs
- the prior durable entry remains unchanged
- cleanup remains required

### Changed state

When the staged file remains valid and its fingerprint changed:

- the complete file is written back to the selected pass entry
- writeback occurs after parent success
- writeback also occurs after ordinary nonzero parent completion
- cleanup is attempted after writeback

The writeback operation is equivalent to:

```sh
pass insert --force --multiline "$pass_entry" <"$config_file"
```

The implementation must not expose the payload through command arguments or
diagnostics.

### Invalid post-command state

After ordinary parent completion, the staged config must still:

- exist
- be a regular file
- be readable
- be non-empty
- be fingerprintable

Invalid state is not written back.

Invalid state is a wrapper lifecycle failure regardless of the parent status.

Cleanup is still attempted.

## Signal-driven GitLab lifecycle

`glab-pass` explicitly handles:

```text
HUP
INT
TERM
```

The wrapper must ensure that the child `glab` process is not left running
unintentionally.

After receiving a handled signal, it must:

1. record the signal
2. forward or otherwise deliver appropriate termination to the child
3. wait until the child has terminated
4. avoid inspecting or deleting staged state while the child may still mutate it
5. validate the staged config
6. conditionally attempt writeback
7. attempt cleanup
8. report lifecycle failures
9. preserve the signal-derived final status

### Signal-time writeback eligibility

Signal-time state is eligible for writeback only when it:

- exists
- is a regular file
- is readable
- is non-empty
- can be fingerprinted
- differs from the initial fingerprint

Eligible changed state is written back on a best-effort basis with explicit
diagnostics.

### Invalid signal-time state

Missing, non-regular, unreadable, empty, or unfingerprintable state does not
replace the durable pass entry.

The wrapper reports that:

- the prior durable entry was retained
- GitLab reauthentication may be required

Cleanup remains required.

### Signal-time writeback failure

Signal-time writeback failure:

- is reported
- does not prevent cleanup
- does not replace the signal-derived status
- may leave durable state stale when the server-side refresh state already
  changed

### Signal-time cleanup failure

Signal-time cleanup failure is reported prominently because plaintext runtime
state may remain.

The signal-derived status remains final.

### Signal statuses

```text
HUP   129
INT   130
TERM  143
```

These remain final even when validation, writeback, cleanup, or multiple
signal-time lifecycle operations fail.

Signals such as `KILL` cannot be trapped and are outside the cleanup guarantee.

## Credential-management command policy

The wrappers support:

- ordinary authenticated operations
- help and command discovery
- authentication-status checks that do not display credential material

Within the `auth` namespace, the wrappers use an explicit allowlist.

### Allowed forms

Required conventional forms include:

```sh
gh-pass auth
gh-pass auth --help
gh-pass auth -h
gh-pass auth status
gh-pass auth status --help
gh-pass auth status -h

glab-pass auth
glab-pass auth --help
glab-pass auth -h
glab-pass auth status
glab-pass auth status --help
glab-pass auth status -h
```

Non-disclosing status options may be supported when explicitly tested.

### Prohibited disclosure options

Within `auth status`, the wrappers reject known credential-display options,
including:

```text
--show-token
-t
```

The parent CLI is not invoked for a rejected form.

### Rejected GitHub operations

`gh-pass` rejects at least:

```text
auth login
auth logout
auth refresh
auth setup-git
auth switch
auth token
```

### Rejected GitLab operations

`glab-pass` rejects at least:

```text
auth login
auth logout
auth configure-docker
auth docker-helper
auth dpop-gen
```

### Unknown `auth` operations

Unknown future `auth` subcommands are rejected by default.

Support requires deliberate review, documentation, implementation, and tests.

### Parsing boundary

The wrappers implement only enough argument inspection to enforce the accepted
policy.

They do not reproduce the complete parent CLI parser.

The implementation must:

- recognize conventional entry into the `auth` namespace
- recognize its immediate subcommand
- identify supported help and status forms
- detect prohibited token-display flags
- reject known prohibited operations
- reject unknown `auth` operations
- preserve ordinary non-`auth` arguments exactly

Ambiguous invocations that appear to target credential management must fail
closed rather than being forwarded merely because the wrapper could not
classify them.

Broader parent-global-option placement is supported only when explicitly
covered by the compatibility tests.

The policy is an accidental-misuse guardrail, not a security boundary. An
operator can still invoke the parent CLI directly.

## Failure model

Wrapper results are divided into four classes:

| Result | Final status |
|---|---:|
| Parent and wrapper succeed | `0` |
| Parent fails; wrapper obligations succeed | Exact parent status |
| Wrapper lifecycle fails during ordinary execution | `1` |
| Handled signal terminates `glab-pass` | Signal-derived status |

### Clean parent failure

A parent nonzero status is preserved when every required wrapper postcondition
succeeds.

Example:

```text
glab exits 4
staged state remains valid
required writeback succeeds
cleanup succeeds
glab-pass exits 4
```

### Wrapper lifecycle failure

Ordinary wrapper failures include:

- invalid configuration override
- missing non-baseline dependency
- unreadable pass entry
- empty credential material
- runtime-directory creation failure
- permission failure
- initial fingerprint failure
- invalid post-command config
- required writeback failure
- cleanup failure
- another unsatisfied architectural postcondition

Any ordinary wrapper lifecycle failure returns:

```text
1
```

and overrides the parent status.

When a parent nonzero status is overridden, diagnostics must still report that
status.

### Multiple failures

The wrapper does not rank lifecycle failures.

It must:

1. record the parent status
2. attempt every remaining safe operation
3. record each wrapper failure
4. report each material failure
5. return status `1` during ordinary execution

A writeback failure must not prevent cleanup.

Invalid staged state must not prevent cleanup.

### Shell execution failures

Statuses such as:

```text
126
127
```

may still arise from shell-level execution failures.

Expected non-baseline dependencies are validated before credential handling
where practical, so ordinary missing-dependency failures normally return
wrapper status `1` with an explicit diagnostic.

## Diagnostic model

Wrapper diagnostics are written to standard error.

They must:

- identify the wrapper
- identify the failed operation
- distinguish parent failure from wrapper failure
- report an overridden parent status
- report every material lifecycle failure
- identify non-sensitive entry names or paths when useful
- provide actionable remediation where practical
- avoid credential disclosure

Diagnostics must not include:

- access-token values
- refresh-token values
- complete GitLab configuration
- decrypted pass-entry content
- reconstructed commands containing sensitive data
- shell traces containing credentials

Normal parent CLI output remains controlled by the parent CLI.

## Runtime language

The wrappers are implemented using POSIX shell syntax.

Shebang:

```sh
#!/bin/sh
```

The supported shell implementations are:

```text
Dash
Bash in POSIX mode
BusyBox ash
```

The initial supported operating-system family is:

```text
Linux
```

The project does not currently claim support for:

- macOS
- FreeBSD
- OpenBSD
- other BSD systems
- every POSIX-conforming system
- every implementation of `/bin/sh`

## Shell-language constraints

The wrappers must not rely on:

- zsh-specific parameter expansion
- Bash arrays
- zsh arrays
- `[[ ... ]]`
- process substitution
- shell-specific regular-expression syntax
- `eval`
- executable command strings
- interactive aliases
- interactive functions
- interactive shell startup configuration

The wrappers must:

- use `"$@"` for parent argument forwarding
- quote data expansions
- disable inherited command tracing
- establish `umask 077`
- preserve statuses intentionally
- handle expected failures explicitly
- remain syntactically valid under every supported shell
- behave consistently under the tested shell matrix

## Runtime dependency model

The project distinguishes:

1. POSIX shell facilities
2. baseline Linux platform utilities
3. validated non-baseline dependencies

### Shell facilities

The implementation may rely on ordinary supported shell facilities such as:

```text
command
exec
printf
test / [ ]
trap
kill
wait
umask
parameter expansion
command substitution
environment assignment
```

### Baseline external utilities

The runtime architecture currently assumes ordinary Linux implementations of:

```text
chmod
rm
```

These are part of the baseline supported platform contract and are not
individually validated before every invocation.

The final implementation must document any additional baseline utility it uses.

The baseline must not expand silently.

### `gh-pass` non-baseline dependencies

```text
pass
gh
```

### `glab-pass` non-baseline dependencies

```text
pass
glab
mktemp
sha256sum
```

Non-baseline dependencies are validated explicitly before credential handling
where practical.

## Trusted components

The architecture trusts:

- the invoking local user account
- the invoking environment
- the installed wrapper scripts
- the selected POSIX shell
- the Linux kernel
- the local filesystem
- `/tmp` filesystem semantics
- baseline platform utilities
- `pass`
- GPG and the relevant private key
- `gh`
- `glab`
- `mktemp`
- `sha256sum`
- extensions or subprocesses deliberately invoked through a parent CLI
- the operator's password-store configuration

A malicious or compromised trusted component may access or alter runtime
credential material.

Protecting against such a component is outside the project boundary.

## Security posture

### Risks reduced

The architecture is intended to reduce:

- routine retention of wrapper-managed parent CLI login state
- accidental inclusion of parent CLI OAuth config in dotfiles
- confusion between wrapper-managed and parent-managed credentials
- persistent reusable GitLab runtime config after ordinary completion
- accidental token display through supported `auth` operations
- silent credential-source fallback
- accidental use of an unintended discovered account
- loss of legitimate GitLab refresh state after ordinary command failure
- hidden writeback or cleanup failures
- zsh as an unnecessary dedicated runtime dependency

### Risks not addressed

The architecture does not protect against:

- a compromised local user account
- a compromised password store
- an exposed GPG private key
- a malicious parent CLI
- malicious CLI extensions
- a compromised shell, terminal, kernel, or filesystem
- privileged process inspection
- process-environment inspection by an authorized actor
- memory or swap exposure
- filesystem journals
- backups or snapshots
- forensic recovery
- shell history containing operator-entered secrets
- secrets already present in repository files
- direct invocation of parent CLIs
- direct use of `pass`
- uncatchable signals
- power loss or kernel failure
- remote service compromise
- weak token scope choices
- Git transport authentication failure

### `/tmp` boundary

GitLab plaintext runtime state exists beneath a shared parent directory.

The credential file itself remains inside a private, unpredictably named
wrapper-controlled child directory with restrictive permissions.

The architecture relies on:

- atomic private-directory creation by `mktemp`
- appropriate local filesystem permission enforcement
- no hostile privileged actor within the threat model

### Opaque-state limitation

A regular, readable, non-empty GitLab config may still be semantically invalid
or partially mutated.

Structural validation cannot prove OAuth correctness.

This limitation is accepted because the wrapper does not own the GitLab config
schema and intentionally avoids becoming a partial authentication
implementation.

## Installation architecture

Canonical executable sources:

```text
src/gh-pass
src/glab-pass
```

The installed files are direct copies of these scripts.

No compilation or generated runtime artifact is required.

### Public Make targets

```text
install
uninstall
dev-install
dev-uninstall
check
```

### Installation variables

```make
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
DESTDIR ?=
```

### Normal installation

```sh
make install
```

Normal installation:

- creates the selected binary directory
- copies both canonical scripts
- installs them with mode `0755`
- performs no credential operation
- performs no authentication
- performs no network request
- does not modify `PATH`
- does not modify shell startup files
- does not invoke privilege escalation

User-local example:

```sh
make install PREFIX="$HOME/.local"
```

Packaging example:

```sh
make install DESTDIR="$pkgdir" PREFIX=/usr
```

### Normal uninstall

```sh
make uninstall
```

Normal uninstall removes only:

```text
$(DESTDIR)$(BINDIR)/gh-pass
$(DESTDIR)$(BINDIR)/glab-pass
```

It does not remove directories, credentials, parent CLI state, or unrelated
files.

### Development installation

```sh
make dev-install PREFIX="$HOME/.local"
```

Development installation creates absolute symlinks to the canonical scripts in
the current physical checkout.

It is explicitly not the stable normal installation model.

Working-tree edits, branch changes, and checkout compromise affect linked
commands immediately.

### Development uninstall

```sh
make dev-uninstall PREFIX="$HOME/.local"
```

Development uninstall removes only links verified to belong to the current
checkout.

It must retain:

- copied installations
- regular files
- directories
- links into another checkout
- unrelated symlinks

## Distribution architecture

The initial distribution unit is a source checkout or tagged source archive.

A release archive must contain enough material to inspect, test, and install the
project, including:

```text
Makefile
src/
tests/
docs/
README.md
CONTRIBUTING.md
LICENSE
```

When present, it should also contain:

```text
SECURITY.md
CHANGELOG.md
```

Initial release distribution consists of:

- versioned Git tags
- GitHub as the primary public release location
- corresponding tags mirrored to GitLab
- source archives associated with released tags
- installation from an unpacked source tree through `make install`

The project does not initially provide:

- `curl | sh`
- another remote shell installer
- automatic self-update
- standalone compiled bundles
- project-maintained native package repositories
- Homebrew, Snap, Flatpak, or AppImage distribution

Third-party packages may use the supported `DESTDIR` interface.

## Verification architecture

Verification must use fake dependencies and isolated state.

Tests must not:

- access a real password store
- decrypt real credentials
- use production forge credentials
- access normal parent CLI authentication state
- contact GitHub
- contact GitLab
- require a production account
- modify normal operator configuration

### Shell matrix

Syntax and behavior must be tested under:

```text
Dash
Bash in POSIX mode
BusyBox ash
```

### Static analysis

ShellCheck is run with the POSIX shell dialect:

```sh
shellcheck --shell=sh src/gh-pass src/glab-pass
```

Suppressions must be narrow and documented.

### `gh-pass` coverage

Tests must cover:

- default entry selection
- explicit entry override
- empty and invalid overrides
- missing dependencies
- pass retrieval failure
- empty first line
- first-line extraction
- argument preservation
- environment scoping
- allowed authentication status
- rejected authentication operations
- token-display rejection
- exact parent status through process replacement
- absence of credential material from diagnostics

### `glab-pass` coverage

Tests must cover:

- fixed staging beneath `/tmp`
- isolation from `XDG_RUNTIME_DIR`
- private directory creation
- required permissions
- opaque config restoration
- initial validation
- parent argument preservation
- unchanged-state behavior
- changed-state writeback after parent success
- changed-state writeback after ordinary parent failure
- invalid post-command state
- writeback failure
- cleanup failure
- multiple wrapper failures
- exact clean parent-status preservation
- ordinary wrapper status `1`
- handled `HUP`, `INT`, and `TERM`
- child-process termination
- signal-time unchanged state
- signal-time changed eligible state
- signal-time invalid state
- signal-time writeback failure
- signal-time cleanup failure
- preservation of signal-derived statuses
- absence of credential material from diagnostics

### Installation coverage

Tests must cover:

- `PREFIX`
- `BINDIR`
- `DESTDIR`
- installed file modes
- installed content identity
- narrow uninstall behavior
- safe development symlinks
- guarded development uninstall
- no credential access
- no network access
- operation from an unpacked source archive

### Primary verification entry point

```sh
make check
```

This command is the supported local, CI, packaging, and release-preparation
verification interface.

## Expected repository structure

The implementation is expected to converge on:

```text
forge-cli-pass/
├── Makefile
├── README.md
├── CONTRIBUTING.md
├── LICENSE
├── SECURITY.md
├── src/
│   ├── gh-pass
│   └── glab-pass
├── tests/
│   ├── fixtures/
│   ├── helpers/
│   ├── test-gh-pass.sh
│   ├── test-glab-pass.sh
│   ├── test-install.sh
│   └── run.sh
└── docs/
    ├── architecture.md
    ├── project-context.md
    └── decisions/
        ├── README.md
        ├── 0001-provider-specific-commands.md
        ├── 0002-project-identity-and-terminology.md
        ├── 0003-pass-as-authoritative-store.md
        ├── 0004-runtime-language-and-platform-support.md
        ├── 0005-gitlab-runtime-state-and-writeback.md
        ├── 0006-failure-and-exit-status-semantics.md
        ├── 0007-signal-driven-gitlab-writeback.md
        ├── 0008-credential-management-command-policy.md
        ├── 0009-credential-entry-configuration.md
        └── 0010-installation-and-distribution.md
```

`SECURITY.md`, tests, and the final license may not exist during early
implementation, but they are required before the first public release under the
current distribution contract.

## Operational documentation boundary

User-facing documentation must explain:

- project purpose
- threat model in practical terms
- runtime dependencies
- installation
- default pass entries
- environment overrides
- GitHub credential bootstrap
- GitLab credential bootstrap
- authentication verification
- supported and rejected `auth` operations
- expected cleanup and writeback behavior
- recovery after unusable GitLab state
- distinction between forge API authentication and Git SSH authentication
- uninstall behavior
- limitations

Bootstrap documentation must not encourage unisolated login behavior that
recreates the original persistent-state problem.

## Deferred decisions

The following concerns are deferred and do not block wrapper implementation:

- release versioning
- tag signing
- release checksums
- provenance attestations
- release automation
- native package ownership
- future non-Linux support
- future alternate fingerprint utilities
- future config-file support
- structured machine-readable wrapper errors
- expanded wrapper-specific exit codes
- support for additional forges
- support for additional GitLab authentication files
- support for new parent `auth` subcommands
- parent-global-option placements not included in the initial compatibility
  tests

A deferred concern requires a new or superseding decision when it would change
an accepted public contract.

## Implementation risks

The principal remaining risks are implementation risks rather than unresolved
system-purpose questions.

### Signal coordination

Portable child-process and signal coordination may differ among supported
shells.

The implementation must be driven by behavioral tests rather than assumed
equivalence.

### Argument classification

The credential-management allowlist must fail closed without becoming a partial
parent CLI parser or changing ordinary argument forwarding.

### Cleanup verification

Failure injection for `rm`, writeback, and simultaneous lifecycle failures must
demonstrate the documented result model.

### Opaque GitLab mutation

A structurally valid config may still be semantically unusable after
interruption.

The wrapper can report and preserve durable state carefully, but it cannot prove
OAuth correctness.

### Parent CLI evolution

A future parent release may:

- change authentication environment behavior
- add `auth` subcommands
- change token-display options
- store GitLab authentication state in additional files
- alter its config update sequence

Such changes require compatibility review and regression testing.

## Architecture summary

`forge-cli-pass` is a small Linux-focused credential-lifecycle boundary around
GitHub CLI and GitLab CLI.

`gh-pass` retrieves a GitHub token from a deterministic `pass` entry and injects
it into one `gh` process through `GH_TOKEN`.

`glab-pass` retrieves an opaque GitLab CLI configuration from a deterministic
`pass` entry, stages it in a private directory beneath `/tmp`, executes `glab`,
persists eligible changes, and removes the runtime state.

Both wrappers:

- use POSIX shell
- validate non-baseline dependencies
- preserve ordinary parent arguments
- restrict credential-management commands
- avoid credential-source fallback
- report wrapper lifecycle failures
- keep `pass` authoritative

The architecture reduces routine persistent credential residue without claiming
to provide isolation from the local user, the operating system, or trusted
runtime components.
