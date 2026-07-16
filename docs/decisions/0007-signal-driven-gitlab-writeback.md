# ADR 0007: Conditionally Persist GitLab State After Signal-Driven Termination

**Status:** Accepted

## Context

`glab-pass` stages GitLab CLI authentication state in a private temporary
directory and allows `glab` to mutate that state during execution.

Under ordinary process completion, ADR 0005 requires changed, non-empty state
to be written back to `pass`, including when `glab` returns a nonzero status.
This preserves legitimate OAuth refresh changes that may occur before an
unrelated operation fails.

Signal-driven termination presents a different condition.

When `glab-pass` or its parent CLI receives:

```text
HUP
INT
TERM
```

the parent CLI may have been interrupted:

- before changing its configuration
- after completing an OAuth refresh
- during a later unrelated operation
- while writing its configuration
- while configuration state is incomplete or temporarily invalid

Two competing risks exist.

### Discarding all signal-time changes

If `glab` completed an OAuth refresh before interruption, the authentication
state still stored in `pass` may no longer represent the current refresh-token
state.

Discarding the staged changes could require reauthentication on a later
invocation.

### Persisting all signal-time changes

If `glab` was interrupted while updating `config.yml`, unconditional writeback
could replace the last durable payload with missing, empty, unreadable, or
partially written state.

Because `glab-pass` deliberately treats the GitLab CLI configuration as an
opaque payload, it cannot determine whether individual OAuth fields are
semantically complete or valid.

The architecture therefore needs a bounded signal-time writeback policy that
balances credential continuity with protection of the last known durable state.

## Decision

After handled `HUP`, `INT`, or `TERM`, `glab-pass` will conditionally attempt to
persist changed staged authentication state.

Writeback is permitted only after:

1. the parent `glab` process has terminated
2. the staged configuration has passed the defined structural checks
3. the staged configuration is confirmed to differ from the initial state

The wrapper will preserve the conventional signal-derived final status
regardless of signal-time validation, writeback, or cleanup outcomes.

## Parent termination requirement

`glab-pass` must not inspect, fingerprint, persist, or remove staged
authentication state while the parent `glab` process may still be running.

After a handled signal, the wrapper must ensure that the parent process has
terminated before post-signal state handling begins.

The final implementation must define and test:

- how the parent process identifier is recorded
- how the signal is forwarded when required
- how the wrapper waits for parent termination
- how duplicate or repeated signals are handled
- how races between natural parent exit and signal delivery are handled

The implementation mechanism must work under every shell accepted by ADR 0004:

```text
Dash
Bash in POSIX mode
BusyBox ash
```

## Eligible signal-time state

The staged GitLab configuration is eligible for writeback only when all of the
following are true:

- the path exists
- the path is a regular file
- the file is readable
- the file is non-empty
- a post-signal content fingerprint can be computed
- the post-signal fingerprint differs from the initial fingerprint

The wrapper must not write back staged state when any of these conditions is
not satisfied.

These checks establish only that the payload remains structurally usable as an
opaque file.

They do not prove:

- semantic validity
- OAuth completeness
- successful token refresh
- authenticity
- provenance
- absence of partial parent CLI mutation

The architecture continues to trust `glab` as the owner of its configuration
format.

## Unchanged state

If the staged configuration remains valid but its fingerprint matches the
initial fingerprint:

- no writeback is performed
- no writeback warning is required
- cleanup is still attempted
- the final signal-derived status is preserved

Example:

```text
INT received
parent terminates
staged config remains valid and unchanged
cleanup succeeds
glab-pass exits 130
```

## Changed and eligible state

If the staged configuration passes all structural checks and differs from its
initial fingerprint:

- `glab-pass` attempts to replace the configured durable pass entry with the
  complete staged payload
- the payload remains opaque to the wrapper
- cleanup is attempted after the writeback attempt
- the signal-derived status remains final

Example:

```text
TERM received
parent terminates
staged config remains valid and changed
writeback succeeds
cleanup succeeds
glab-pass exits 143
```

Signal-time writeback is **best effort with explicit diagnostics**.

In this context, best effort means:

- failure does not replace the signal-derived status
- failure must not be silent
- cleanup must still be attempted
- credential material must not appear in diagnostics

## Invalid or unverifiable state

The staged configuration must not replace the durable pass entry when it is:

- missing
- not a regular file
- unreadable
- empty
- unable to be fingerprinted

The wrapper must report that signal-time state could not be safely persisted.

The diagnostic should make clear that:

- the previous durable pass entry was retained
- the current GitLab OAuth state may require reauthentication
- no credential payload is printed

Example:

```text
glab-pass: interrupted GitLab state is empty; retaining the existing pass entry
glab-pass: GitLab reauthentication may be required
```

Cleanup must still be attempted.

The final status remains the signal-derived status.

## Signal-time writeback failure

If eligible changed state cannot be written back to `pass`, the wrapper must:

1. report the writeback failure
2. identify the affected pass entry when useful
3. avoid printing the staged payload
4. warn that the existing durable state may no longer match the parent CLI's
   refreshed state
5. attempt cleanup
6. preserve the signal-derived final status

Example:

```text
INT received
parent terminates
staged config is valid and changed
writeback fails
cleanup succeeds
glab-pass reports the writeback failure
glab-pass exits 130
```

## Cleanup

Cleanup remains mandatory after handled signal termination.

The wrapper must attempt to remove the complete private runtime directory after:

- unchanged state
- successful signal-time writeback
- failed signal-time writeback
- invalid staged state
- fingerprint failure

A cleanup failure must be reported prominently because plaintext credential
material may remain under `/tmp`.

Under ADR 0006, cleanup failure does not replace the signal-derived status.

Example:

```text
HUP received
parent terminates
writeback succeeds
cleanup fails
glab-pass reports the cleanup failure
glab-pass exits 129
```

## Final status

Handled signal termination preserves these final statuses:

```text
HUP   129
INT   130
TERM  143
```

These statuses remain final when:

- staged state is unchanged
- writeback succeeds
- writeback fails
- staged state is invalid
- fingerprinting fails
- cleanup fails
- multiple signal-time lifecycle operations fail

The signal remains the causal termination event.

Diagnostics carry the additional lifecycle failure information.

## Diagnostic requirements

Signal-time diagnostics must:

- identify `glab-pass`
- identify the relevant lifecycle failure
- distinguish invalid state, writeback failure, and cleanup failure
- explain when the existing durable pass entry was retained
- warn when reauthentication may be required
- avoid printing credential material
- avoid reconstructing sensitive command strings
- write to standard error

Diagnostics may identify:

- the configured pass entry name
- the private runtime-directory path
- the signal received
- the parent process status, when available

## Alternatives considered

### Never write back after a signal

Rejected because `glab` may complete an OAuth refresh before being interrupted
during a later operation.

In that case, retaining only the previous pass entry could leave durable state
out of sync with the server-recognized refresh state.

### Always write back changed state

Rejected because the parent may be interrupted while creating or replacing its
configuration.

Unconditional writeback could overwrite the last durable payload with
obviously unusable state.

### Parse the staged configuration before writeback

Rejected because the project intentionally treats GitLab CLI configuration as
opaque.

Parsing would:

- couple the wrapper to GitLab CLI internals
- require schema and version handling
- expand the sensitive parsing surface
- encourage the wrapper to infer OAuth validity it cannot authoritatively
  establish

### Preserve wrapper failure status instead of signal status

Rejected by ADR 0006.

The signal remains the causal termination event and its conventional status is
valuable to callers.

Lifecycle failures remain visible through diagnostics.

### Create a durable recovery copy outside `pass`

Rejected because it would introduce another persistent plaintext or separately
managed credential location, contradicting the project's durable-state model.

### Skip cleanup when writeback fails

Rejected because failed persistence does not justify retaining plaintext staged
credential material.

Cleanup must still be attempted.

## Consequences

### Positive

- Completed OAuth refresh changes can survive a later signal interruption.
- Obviously unusable staged state cannot overwrite the last durable pass entry.
- The wrapper preserves recognizable signal statuses.
- Cleanup remains mandatory.
- The configuration remains opaque to the wrapper.
- Signal-time behavior is explicit and testable.
- Writeback and cleanup failures remain visible without changing the causal
  exit status.

### Negative

- Structural checks cannot prove semantic validity.
- A non-empty regular file may still contain partial or undesirable mutation.
- Signal handling and child-process coordination add implementation complexity.
- Behavior must be tested across multiple shell implementations.
- Failed signal-time writeback may leave the durable pass entry unusable if the
  old OAuth refresh state was already invalidated.
- Operators may need to reauthenticate after interruption.
- Multiple diagnostics may accompany one signal-derived exit.

## Security implications

This decision balances two security-relevant properties:

1. preserving valid refreshed authentication state
2. avoiding replacement of durable state with obviously invalid runtime data

It does not protect against:

- a compromised `glab`
- malicious mutation by another trusted component
- semantically invalid but structurally non-empty configuration
- privileged runtime inspection
- memory or swap exposure
- forensic recovery
- uncatchable signals such as `KILL`
- abrupt system failure before traps execute

A signal may occur at any point in the parent CLI's mutation sequence.
Conditional writeback reduces obvious failure modes but cannot make interrupted
opaque state fully trustworthy.

## Verification requirements

Tests must cover all of the following under every supported shell.

### Parent termination

- the parent process is not left running after handled `HUP`
- the parent process is not left running after handled `INT`
- the parent process is not left running after handled `TERM`
- post-signal inspection begins only after parent termination
- natural parent exit racing with signal delivery is handled
- repeated signals do not cause duplicate unsafe processing

### Unchanged state

- valid unchanged state is not written back
- cleanup is attempted
- the correct signal-derived status is returned

### Changed eligible state

- valid changed state is written back after `HUP`
- valid changed state is written back after `INT`
- valid changed state is written back after `TERM`
- the complete opaque payload is persisted
- cleanup is attempted
- the signal-derived status remains final

### Invalid state

- missing staged config is not written back
- non-regular staged config is not written back
- unreadable staged config is not written back
- empty staged config is not written back
- fingerprint failure prevents writeback
- the prior pass entry remains unchanged
- diagnostics warn that reauthentication may be required
- cleanup is attempted
- the signal-derived status remains final

### Writeback failure

- failed signal-time writeback is reported
- credential material is absent from diagnostics
- cleanup is still attempted
- the signal-derived status remains final

### Cleanup failure

- cleanup failure after unchanged state is reported
- cleanup failure after successful writeback is reported
- cleanup failure after failed writeback is reported
- cleanup failure after invalid state is reported
- the signal-derived status remains final

### Multiple failures

- invalid state combined with cleanup failure
- writeback failure combined with cleanup failure
- every material failure is reported
- no credential payload appears in output
- the signal-derived status remains final

### Isolation

Tests must use:

- a fake `glab`
- a fake `pass`
- fake OAuth configuration
- isolated temporary directories
- no network
- no production GitLab account
- no real password store
- no normal GitLab CLI authentication state

## Relationship to other decisions

This ADR extends:

- ADR 0005, which governs GitLab runtime state and ordinary writeback
- ADR 0006, which governs failure and exit-status semantics

ADR 0005 remains authoritative for ordinary parent-process completion.

ADR 0006 remains authoritative for final signal-derived statuses and cleanup
failure reporting.

## Decision summary

After handled `HUP`, `INT`, or `TERM`, `glab-pass` will wait for the parent
process to terminate and then conditionally persist staged GitLab authentication
state.

Writeback occurs only when the staged configuration remains a regular,
readable, non-empty file and differs from its initial fingerprint.

Invalid or unverifiable staged state does not replace the existing pass entry.

Cleanup is always attempted, lifecycle failures are reported, and the final
status remains the conventional signal-derived status.
