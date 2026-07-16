# ADR 0005: Define GitLab Runtime State and Writeback Behavior

**Status:** Accepted

## Context

GitLab CLI OAuth authentication depends on mutable configuration state rather
than only a standalone token.

`glab-pass` must make that state available to `glab` without retaining
wrapper-managed authentication state in GitLab CLI's default configuration
location.

The staged configuration may change during an invocation. For example, `glab`
may refresh OAuth state before a later operation succeeds or fails.

The wrapper treats the configuration as an opaque payload. It does not parse
GitLab CLI authentication fields or attempt to classify individual mutations.

The architecture must define:

- where plaintext runtime state is staged
- how the staging location is created
- how changes are detected
- when changes are written back
- what constitutes invalid post-command state
- which utility dependencies are accepted

Signal-driven termination requires separate consideration because the parent
process may be interrupted during a partial mutation.

## Decision

### Staging parent

`glab-pass` will always create its private runtime directory beneath:

```text
/tmp
```

It will not use `XDG_RUNTIME_DIR` or another environment-selected staging
parent.

The runtime directory will be created using a tested `mktemp` template:

```sh
mktemp -d /tmp/glab-pass.XXXXXX
```

The wrapper will set:

```sh
umask 077
```

before creating runtime credential material.

It will defensively apply:

```text
runtime directory: 0700
config file:       0600
```

### Parent CLI configuration

The stored GitLab CLI configuration will be restored as:

```text
<RUNTIME_DIRECTORY>/config.yml
```

The parent CLI will be invoked with `GLAB_CONFIG_DIR` scoped to that runtime
directory.

The wrapper will not intentionally populate GitLab CLI's default configuration
location with wrapper-managed authentication state.

### Change detection

`glab-pass` will use `sha256sum` to compute a content fingerprint before and
after ordinary parent-process execution.

The fingerprint is used only to determine whether writeback is necessary.

It does not:

- authenticate the configuration
- establish provenance
- prevent malicious modification
- provide a trusted integrity measurement

`sha256sum` is an accepted non-baseline dependency under the initial Linux
support contract.

### Ordinary parent exit

After `glab` exits normally, including with a nonzero status, `glab-pass` will:

1. verify that the staged configuration still exists and is non-empty
2. compute its post-command fingerprint
3. write the configuration back to `pass` when its content changed
4. avoid writeback when its content did not change
5. attempt removal of the staged plaintext state

Changed, non-empty configuration will be persisted even when `glab` returns a
nonzero status.

This preserves legitimate mutable authentication state, including possible
OAuth refresh changes that occurred before an unrelated command failure.

### Missing or empty post-command configuration

For ordinary supported operations, staged configuration that becomes missing
or empty is invalid wrapper state.

If the parent returned success but the staged configuration is missing or
empty, `glab-pass` will return a wrapper failure.

If the parent returned nonzero and the staged configuration is missing or
empty, the wrapper will report both the parent failure and the invalid runtime
state, then return a wrapper failure according to ADR 0006.

Credential-management commands may intentionally remove or replace
authentication state. Their compatibility policy remains a separate
architecture decision.

### Signal-driven termination

Writeback behavior after signal-driven termination is not decided by this ADR.

Signal-driven writeback must be addressed separately before implementation of
the final signal-handling path.

Cleanup must still be attempted after handled termination signals.

## Alternatives considered

### Use `XDG_RUNTIME_DIR` when available

Rejected for the initial design because it would require validation of an
environment-controlled parent directory and introduce platform-sensitive
ownership and permission inspection.

A private child directory beneath `/tmp` provides a simpler and deterministic
staging model.

### Use GitLab CLI's default configuration location

Rejected because persistent wrapper-managed authentication state in that
location is the original condition the project is intended to avoid.

### Use `GITLAB_TOKEN` only

Rejected because the intended OAuth workflow requires mutable configuration and
refresh state beyond a standalone access token.

### Use exact comparison against a second plaintext copy

This would permit byte-for-byte comparison through `cmp`, but it would create
another temporary plaintext copy of the credential-state payload.

Rejected for the initial Linux design in favor of one staged plaintext copy and
a content fingerprint.

### Use POSIX `cksum`

Rejected because it offers no meaningful architectural advantage over
`sha256sum` under the accepted Linux support contract.

### Write back only after parent success

Rejected because OAuth state may be refreshed before a later operation fails.
Discarding all changes after a nonzero parent status could lose legitimate
updated authentication state.

### Parse the GitLab configuration

Rejected because the project intentionally treats the parent CLI configuration
as opaque. Parsing and classifying GitLab authentication mutations would expand
the project scope and couple it to parent CLI internals.

## Consequences

### Positive

- The staging location is deterministic.
- No environment-selected runtime parent must be trusted.
- Temporary directory creation avoids predictable-name races.
- Only one plaintext configuration copy is required.
- Legitimate OAuth refresh changes survive unrelated parent-command failures.
- Unchanged state does not cause unnecessary password-store writes.
- The parent CLI configuration format remains opaque to the wrapper.

### Negative

- Runtime plaintext state exists beneath a shared system parent directory,
  although inside a private child directory.
- `mktemp` and `sha256sum` remain explicit runtime dependencies.
- Writeback after a nonzero parent status may persist any configuration
  mutation made by the parent, not only OAuth refreshes.
- The wrapper cannot distinguish legitimate refresh changes from other parent
  CLI mutations.
- Signal-driven writeback remains a separate unresolved decision.

## Security implications

The architecture trusts:

- `mktemp` to create the runtime directory without a predictable-name race
- filesystem permissions to restrict ordinary access to the staged state
- `glab` as a trusted parent CLI
- `sha256sum` for deterministic content fingerprinting
- `pass` to persist updated credential state

The use of `/tmp` does not imply that the credential file itself is
world-readable. Credential material must remain within a private,
wrapper-controlled child directory.

Removal of staged state reduces ordinary persistent credential residue. It does
not guarantee forensic erasure from memory, swap, filesystem journals, storage
media, or other operating-system layers.

## Verification requirements

Tests must verify:

- staging always occurs beneath `/tmp`
- `XDG_RUNTIME_DIR` does not redirect staging
- the staging directory is created through `mktemp`
- the staging directory has mode `0700`
- the staged configuration has mode `0600`
- `GLAB_CONFIG_DIR` references the private staging directory
- unchanged state is not written back
- changed state is written back after parent success
- changed state is written back after an ordinary nonzero parent exit
- missing or empty staged state produces a wrapper failure
- writeback failure produces a wrapper failure
- staged plaintext state is removed after ordinary completion
- diagnostics do not disclose credential material
- tests never use real credentials or the real password store

Signal-driven writeback tests must be added after the corresponding decision is
accepted.
