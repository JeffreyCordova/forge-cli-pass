# ADR 0006: Define Failure and Exit-Status Semantics

**Status:** Accepted

## Context

A wrapper invocation may produce multiple outcomes:

- the parent CLI succeeds
- the parent CLI returns a nonzero status
- staged credential state becomes invalid
- required writeback fails
- cleanup fails
- more than one wrapper obligation fails
- a termination signal is received

The project must preserve parent CLI behavior where possible while also making
credential-lifecycle failures visible.

Returning the parent status unconditionally would conceal wrapper failures.

Replacing every parent failure with a wrapper status would undermine command
compatibility.

A deterministic result model is therefore required.

## Decision

### Parent status preservation

The wrapper will preserve the parent CLI's exact exit status only when all
wrapper-managed postconditions complete successfully.

For `glab-pass`, those postconditions include:

- staged state remains valid when required
- changed state is written back successfully
- cleanup succeeds

For `gh-pass`, direct process replacement may allow the parent status to be
returned naturally because no wrapper post-processing is required.

### Successful invocation

Return status `0` only when:

- the parent CLI returns `0`
- every required wrapper operation succeeds

### Clean parent failure

Return the exact nonzero parent status when:

- the parent CLI returns nonzero
- every wrapper-managed credential validation, writeback, and cleanup operation
  succeeds

Example:

```text
glab exits 4
writeback succeeds
cleanup succeeds
glab-pass exits 4
```

### Wrapper lifecycle failure

Return status `1` when any wrapper-managed lifecycle obligation fails during
ordinary completion.

Wrapper failures include:

- invalid or unexpectedly missing runtime credential state
- required credential-state writeback failure
- cleanup failure
- another postcondition required by the accepted architecture

A wrapper failure overrides the parent status.

Example:

```text
glab exits 0
writeback fails
cleanup succeeds
glab-pass exits 1
```

Another example:

```text
glab exits 4
writeback succeeds
cleanup fails
glab-pass exits 1
```

When a parent failure is overridden, diagnostics must still report the parent
status.

### Multiple wrapper failures

The wrapper will not assign a priority ordering among writeback, cleanup, and
other lifecycle failures.

It will:

1. record the parent status
2. attempt every remaining safe wrapper operation
3. report each wrapper failure
4. return status `1` if any wrapper lifecycle operation failed

A writeback failure must not prevent cleanup from being attempted.

### Wrapper failure code

The general wrapper operational failure code is:

```text
1
```

The project will not define a larger custom exit-code taxonomy unless a
concrete automation requirement justifies it.

Diagnostics, rather than unique status values, distinguish the specific
wrapper failure.

### Shell execution failures

Normal shell execution statuses such as `126` and `127` may still occur when
the shell cannot execute a command.

Expected non-baseline dependencies should be validated before credential
handling so missing dependencies normally produce an explicit wrapper
diagnostic and status `1`.

### Signal-driven termination

For handled signals, the wrapper will preserve the conventional
signal-derived status:

```text
HUP   129
INT   130
TERM  143
```

Cleanup must still be attempted.

If cleanup fails during signal-driven termination:

- the cleanup failure must be reported prominently
- the signal-derived status remains the final status

The signal remains the causal termination event.

Whether changed GitLab configuration is written back after signal-driven
termination remains a separate open decision.

## Alternatives considered

### Always return the parent status

Rejected because wrapper failures could leave credential state unpersisted or
plaintext runtime material behind while appearing indistinguishable from a
normal parent result.

### Always prioritize wrapper status

Accepted for ordinary wrapper lifecycle failures, but not for handled signals.

Signal-derived statuses remain useful to calling processes and communicate the
causal termination condition.

### Define separate status codes for writeback and cleanup failures

Rejected initially because:

- there is no universally recognized project-specific code range
- codes could overlap with parent CLI statuses
- the public status API would need long-term stability
- diagnostics are required regardless
- current automation needs do not justify the additional interface

### Rank wrapper failures

Rejected because writeback and cleanup failures violate different parts of the
credential lifecycle and both must be reported.

The wrapper should attempt all remaining safe operations rather than stop after
the nominally highest-priority failure.

### Preserve parent status when both parent and wrapper fail

Rejected because callers could interpret the result as an ordinary parent CLI
failure even though the wrapper did not fulfill its credential-lifecycle
contract.

## Consequences

### Positive

- Parent command compatibility is preserved when the wrapper works correctly.
- Credential-lifecycle failures cannot be silently hidden behind parent status.
- Cleanup is attempted even after another wrapper failure.
- The status model remains small and documentable.
- Signal-derived statuses remain recognizable to callers.

### Negative

- A wrapper failure can replace a meaningful parent status.
- Status `1` can also be returned by the parent CLI, so diagnostics remain
  necessary to distinguish the source.
- Callers needing both statuses must parse diagnostics unless a future
  structured interface is introduced.
- Signal-time writeback semantics remain unresolved.

## Security implications

This model treats failure to maintain the documented credential lifecycle as a
failure of the wrapper invocation.

In particular:

- failed writeback cannot appear as successful credential persistence
- failed cleanup cannot appear as a clean invocation
- parent failure does not excuse wrapper postcondition failures
- cleanup remains required after writeback or validation failure
- diagnostics must not expose credential material while reporting failures

Preserving signal statuses avoids concealing interruption, but cleanup failure
must remain visible because staged plaintext material may remain.

## Verification requirements

Tests must cover:

- parent success with successful postconditions
- parent nonzero status with successful postconditions
- writeback failure after parent success
- writeback failure after parent failure
- cleanup failure after parent success
- cleanup failure after parent failure
- simultaneous writeback and cleanup failure
- invalid staged state after parent success
- invalid staged state after parent failure
- preservation of exact clean parent statuses
- wrapper status `1` after ordinary lifecycle failure
- signal-derived statuses
- cleanup attempts after handled signals
- cleanup diagnostics after signal-time cleanup failure
- absence of credential values from diagnostics
