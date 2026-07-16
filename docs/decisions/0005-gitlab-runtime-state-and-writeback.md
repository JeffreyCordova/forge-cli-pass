# ADR 0005: Define GitLab Runtime State and Writeback Behavior

**Status:** Accepted

## Context

GitLab CLI OAuth authentication depends on mutable authentication state rather
than only a standalone access token.

The relevant GitLab CLI state is stored in a `config.yml` payload that may
contain access-token, refresh-token, host, and related configuration data. The
payload may change during an invocation, including when `glab` refreshes an
OAuth credential.

`glab-pass` must make this state available to `glab` without retaining
wrapper-managed authentication state in GitLab CLI's default configuration
location.

The wrapper therefore needs to:

- retrieve durable state from `pass`
- materialize a plaintext runtime representation
- protect that runtime representation from ordinary local access
- direct `glab` to use it
- detect parent CLI mutations
- persist changed state back to `pass`
- remove the plaintext runtime representation afterward

The wrapper intentionally treats the GitLab configuration as an opaque payload.
It does not parse the configuration or attempt to distinguish OAuth refresh
changes from other mutations made by `glab`.

The architecture must define:

- where runtime credential state is staged
- how the staging location is created
- which permissions are required
- how mutations are detected
- when changed state is written back
- how missing or empty post-command state is handled
- which behavior remains unresolved for signal-driven termination

## Decision

### Durable state

The complete GitLab CLI authentication-state payload will be stored durably in
`pass`.

The initial pass entry name is defined elsewhere by the project's configuration
policy.

The durable payload is treated as an opaque representation of GitLab CLI
authentication state.

`glab-pass` will not:

- parse OAuth fields
- extract and manage individual refresh tokens
- reimplement token refresh
- reconstruct the configuration from selected fields
- independently validate the GitLab configuration schema

### Staging parent

`glab-pass` will always stage runtime credential state beneath:

```text
/tmp
```

The wrapper will not use:

- `XDG_RUNTIME_DIR`
- another environment-selected staging parent
- GitLab CLI's default configuration directory
- a repository-local directory
- the current working directory

Using a fixed parent avoids relying on an environment-controlled runtime path
and avoids platform-sensitive validation of that parent.

### Runtime-directory creation

The private runtime directory will be created with `mktemp` using the tested
Linux-compatible form:

```sh
mktemp -d /tmp/glab-pass.XXXXXX
```

The wrapper must not construct temporary paths from predictable values such as:

- process identifiers
- timestamps
- usernames
- counters
- fixed filenames

Before creating runtime credential material, the wrapper will establish:

```sh
umask 077
```

The wrapper will defensively require or apply these permissions:

```text
runtime directory: 0700
config file:       0600
```

A permissions failure is a wrapper lifecycle failure.

### Runtime configuration path

The stored payload will be restored to:

```text
<RUNTIME_DIRECTORY>/config.yml
```

`glab-pass` will invoke the parent CLI with:

```text
GLAB_CONFIG_DIR=<RUNTIME_DIRECTORY>
```

scoped to the `glab` process.

The wrapper will not intentionally populate GitLab CLI's default configuration
location with wrapper-managed authentication state.

### Initial-state validation

Before invoking `glab`, the wrapper must verify that:

- the pass entry can be read
- the restored payload is non-empty
- the runtime directory exists
- the runtime config file exists
- the required permissions were established
- all required non-baseline dependencies are available

Failure of any initial-state requirement prevents parent CLI execution and
produces a wrapper failure.

### Change detection

Before invoking `glab`, `glab-pass` will compute a SHA-256 content fingerprint
of the staged configuration using `sha256sum`.

After ordinary parent-process completion, it will compute another fingerprint.

The fingerprints are used only to answer:

> Did the staged configuration content change during this invocation?

They do not:

- authenticate the configuration
- establish provenance
- verify that a mutation was legitimate
- protect against a malicious parent CLI
- provide a trusted integrity measurement
- form part of an external verification protocol

`sha256sum` is an accepted non-baseline dependency under the initial Linux
support contract established by ADR 0004.

### Unchanged state

When the post-command fingerprint matches the initial fingerprint:

- no writeback is performed
- the existing durable pass entry remains unchanged
- cleanup is still required

Avoiding unnecessary writeback reduces password-store mutation and prevents
irrelevant encrypted-file changes.

### Changed state

When the post-command fingerprint differs from the initial fingerprint and the
staged configuration remains valid:

- the complete changed payload is written back to the configured `pass` entry
- the writeback replaces the prior durable payload
- the payload remains opaque to the wrapper
- cleanup is attempted after writeback

The wrapper must not write only selected fields or attempt to merge old and new
configuration content.

### Writeback after parent success

When `glab` exits with status `0` and the staged configuration changed,
`glab-pass` must persist the changed state to `pass`.

Failure to persist required changed state is a wrapper lifecycle failure.

### Writeback after ordinary parent failure

When `glab` exits normally with a nonzero status and the staged configuration
changed, `glab-pass` must still persist the changed, non-empty state to `pass`.

This policy exists because `glab` may refresh OAuth state before a later,
unrelated part of the requested operation fails.

For example:

```text
glab refreshes OAuth state
        ↓
glab performs the requested API operation
        ↓
the API operation fails
        ↓
glab exits nonzero
```

Discarding all configuration changes after a nonzero parent exit could discard
valid refreshed authentication state and impair later invocations.

Because the configuration is opaque, the wrapper cannot reliably distinguish a
refresh mutation from another parent CLI mutation.

The architecture therefore accepts the parent CLI's complete changed
configuration after ordinary process completion, regardless of the parent exit
status.

### Post-command state validation

After ordinary parent-process completion, the staged configuration must still:

- exist
- be a regular file
- be non-empty

If the staged configuration is missing or empty, the wrapper must not write it
back to `pass`.

For ordinary supported operations, missing or empty post-command state is a
wrapper lifecycle failure.

This applies whether the parent returned success or failure.

Examples:

```text
glab exits 0
config.yml is missing
→ wrapper failure
```

```text
glab exits 4
config.yml is empty
→ report parent status and invalid runtime state
→ wrapper failure
```

Credential-management commands may intentionally remove, replace, or disclose
authentication state. Their compatibility policy is governed by a separate
architecture decision.

### Writeback failure

A required writeback failure is a wrapper lifecycle failure.

The wrapper must:

1. report that changed authentication state could not be persisted
2. avoid printing the credential payload
3. preserve enough diagnostic context to identify the affected pass entry
4. continue to attempt cleanup
5. return according to ADR 0006

A writeback failure must not prevent cleanup from being attempted.

### Cleanup

After ordinary parent-process completion, the wrapper must attempt to remove
the complete private runtime directory and its contents.

Cleanup is required after:

- parent success
- parent failure
- unchanged configuration
- successful writeback
- failed writeback
- invalid post-command state

A cleanup failure is a wrapper lifecycle failure under ADR 0006.

Removal reduces ordinary persistent plaintext credential residue. It does not
guarantee forensic erasure from:

- process memory
- swap
- filesystem journals
- storage media
- backups
- privileged process inspection
- parent CLI internals

### Signal-driven termination

This ADR does not decide whether changed GitLab state should be written back
after signal-driven termination.

Signal interruption differs from ordinary parent completion because the parent
may have been interrupted during a partial configuration mutation.

The signal-time writeback policy must be resolved separately before the final
signal-handling implementation is accepted.

Cleanup must still be attempted after handled termination signals.

## Alternatives considered

### Use `XDG_RUNTIME_DIR`

Rejected for the initial architecture.

Using `XDG_RUNTIME_DIR` would require the wrapper to validate an
environment-controlled parent directory, including:

- ownership
- permissions
- writability
- searchability
- platform-specific metadata behavior

A private `mktemp` directory beneath `/tmp` provides a simpler and deterministic
runtime model.

### Use GitLab CLI's default configuration directory

Rejected because retaining wrapper-managed authentication state there is the
condition the project exists to avoid.

### Use only `GITLAB_TOKEN`

Rejected because the intended GitLab OAuth workflow depends on mutable
configuration and refresh state beyond a standalone access token.

Using only `GITLAB_TOKEN` would change the authentication model and could prevent
OAuth state from surviving between invocations.

### Retain a second plaintext copy and compare with `cmp`

This would provide exact byte comparison through a baseline utility.

Rejected for the initial Linux design because it would create another plaintext
copy of the complete authentication-state payload.

The accepted fingerprint approach requires only one staged plaintext config
copy.

### Use POSIX `cksum`

Rejected because it offers no material architectural advantage under the
accepted Linux support contract.

The project already accepts `sha256sum` as a documented non-baseline dependency.

### Write back only after parent success

Rejected because valid OAuth refresh state may be produced before an unrelated
operation fails.

Discarding changed state after every nonzero parent exit could damage later
authentication continuity.

### Parse the GitLab configuration

Rejected because it would:

- couple the wrapper to GitLab CLI internals
- require schema and version handling
- increase the sensitive parsing surface
- force the wrapper to classify mutations it does not own
- move the project toward reimplementing parent CLI authentication behavior

The parent CLI configuration remains an opaque payload.

### Ignore missing or empty post-command state

Rejected because returning success while required durable authentication state
cannot be preserved would conceal a wrapper lifecycle failure.

### Treat cleanup as best effort

Rejected because failure to remove staged plaintext authentication state is
material to the project's security objective and must be visible.

## Consequences

### Positive

- Runtime credential staging is deterministic.
- The wrapper does not trust an environment-selected staging parent.
- Temporary directory creation avoids predictable-name races.
- Staged credential material has explicit restrictive permissions.
- GitLab CLI's mutable OAuth behavior remains supported.
- Legitimate refresh changes can survive unrelated parent-command failures.
- Unchanged state does not create unnecessary password-store writes.
- Only one plaintext configuration copy is required.
- The wrapper remains decoupled from GitLab CLI's internal configuration schema.
- Cleanup and writeback failures are treated as visible lifecycle failures.

### Negative

- Plaintext runtime state necessarily exists on disk during invocation.
- The state exists beneath the shared `/tmp` parent, although inside a private
  child directory.
- `mktemp` and `sha256sum` are required non-baseline dependencies.
- Any complete configuration mutation made by trusted `glab` may be persisted,
  not only OAuth refreshes.
- The wrapper cannot distinguish a legitimate refresh from an undesirable
  parent CLI mutation.
- Writeback after a nonzero parent status may surprise operators unfamiliar with
  mutable OAuth state.
- Signal-driven writeback remains unresolved.
- The implementation requires careful cleanup and exit-status tests.

## Security implications

This decision treats the following components as trusted within the project's
boundary:

- `mktemp`
- `chmod`
- `sha256sum`
- `glab`
- `pass`
- the local filesystem
- the Linux kernel
- the invoking local user account

The project assumes that:

- `mktemp` creates the private runtime directory without a predictable-name race
- filesystem permissions restrict ordinary local access
- `glab` is permitted to read and mutate its staged configuration
- `sha256sum` produces deterministic content fingerprints
- `pass` correctly persists the changed payload

A malicious or compromised `glab` can access the complete staged
authentication-state payload and can mutate it before writeback. Protecting
against a compromised trusted parent CLI is outside the project scope.

Using `/tmp` as the parent does not make the staged file publicly readable. The
credential material remains inside a private wrapper-controlled directory.

Deleting the runtime directory reduces persistent credential residue but does
not guarantee secure erasure.

## Verification requirements

Tests must verify all of the following.

### Staging location

- Staging always occurs beneath `/tmp`.
- `XDG_RUNTIME_DIR` does not redirect staging.
- The current working directory does not affect the staging location.
- The GitLab default config location is not used for wrapper-managed state.

### Runtime creation

- The runtime directory is created through `mktemp`.
- The runtime directory has mode `0700`.
- The staged config file has mode `0600`.
- Predictable pre-created paths are not reused.
- Failure to create or protect runtime state prevents parent execution.

### Parent invocation

- `GLAB_CONFIG_DIR` points to the private runtime directory.
- User arguments preserve their values, order, and boundaries.
- The parent CLI receives the complete restored config payload.
- Wrapper diagnostics do not print credential material.

### Change detection

- The pre-command fingerprint is computed.
- The post-command fingerprint is computed after ordinary completion.
- Unchanged state causes no writeback.
- Changed state causes one complete writeback.
- Fingerprint output is not treated as an external integrity claim.

### Parent success and failure

- Changed state is written back after parent success.
- Changed state is written back after an ordinary nonzero parent exit.
- The exact clean parent status is preserved when all wrapper obligations
  succeed.
- No writeback occurs for unchanged state.

### Invalid post-command state

- Missing config produces a wrapper failure.
- Empty config produces a wrapper failure.
- Invalid state is not written back.
- Parent status is reported when invalid state follows a parent failure.
- Cleanup is still attempted.

### Writeback failure

- Failed writeback produces a wrapper failure.
- Failed writeback does not prevent cleanup.
- Credential material does not appear in diagnostics.
- The real password store is never used in tests.

### Cleanup

- Runtime state is removed after parent success.
- Runtime state is removed after parent failure.
- Runtime state is removed after unchanged state.
- Runtime state is removed after successful writeback.
- Cleanup is attempted after failed writeback.
- Cleanup failure is reported.
- Cleanup failure follows ADR 0006 exit semantics.

### Isolation

Tests must use:

- a temporary `HOME`
- an isolated `PATH`
- fake `pass` and `glab` commands
- fake credential-state payloads
- no network
- no production GitLab account
- no real password store
- no normal GitLab CLI authentication state

Signal-driven writeback tests are deferred until the corresponding decision is
accepted.

## Follow-on decisions

This ADR does not resolve:

- signal-driven writeback behavior
- credential-management command compatibility
- credential-entry configuration and precedence
- installation and distribution
- future GitLab configuration-format changes
- future non-Linux platform support

Failure and exit-status behavior for ordinary completion is governed by
ADR 0006.

## Decision summary

`glab-pass` will restore its complete GitLab CLI authentication-state payload
from `pass` into a private `mktemp` directory beneath `/tmp`.

The staged config will have restrictive permissions and will be supplied to
`glab` through `GLAB_CONFIG_DIR`.

The wrapper will use `sha256sum` content fingerprints to detect mutations.

Changed, non-empty state will be written back after ordinary parent completion,
including when `glab` returns a nonzero status.

Missing or empty post-command state, failed required writeback, and failed
cleanup are wrapper lifecycle failures.

Signal-driven writeback remains a separate unresolved decision.
