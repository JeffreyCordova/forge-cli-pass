# ADR 0006: Define Failure and Exit-Status Semantics

**Status:** Accepted

## Context

`forge-cli-pass` wraps existing command-line tools rather than reimplementing
their operations.

For command-compatible behavior, the wrappers should preserve the parent CLI's
exit status when the wrapper successfully completes its own credential-lifecycle
responsibilities.

A wrapper invocation can, however, produce more than one outcome:

- the parent CLI succeeds
- the parent CLI exits nonzero
- required runtime credential state becomes invalid
- changed credential state cannot be written back
- temporary plaintext state cannot be removed
- multiple wrapper operations fail
- the process is terminated by a signal
- a required dependency cannot be executed

Returning the parent status unconditionally would conceal failures in the
wrapper's credential-handling contract.

Replacing every parent failure with a wrapper-specific status would weaken
command compatibility and make the wrappers less useful in scripts and
automation.

The project therefore needs a deterministic distinction between:

1. **parent CLI outcomes**
2. **wrapper lifecycle failures**
3. **signal-driven termination**
4. **shell-level execution failures**

## Decision

### Result classes

Wrapper outcomes are divided into four classes:

| Result class | Final status |
|---|---:|
| Parent and wrapper succeed | `0` |
| Parent fails but wrapper obligations succeed | Exact parent status |
| Wrapper lifecycle fails during ordinary execution | `1` |
| Handled signal terminates the invocation | Conventional signal-derived status |

Normal shell execution statuses such as `126` and `127` may still occur when
execution fails at the shell level.

### Successful invocation

A wrapper returns status `0` only when:

- the parent CLI returns `0`
- every required wrapper operation succeeds
- all required postconditions are satisfied

For `glab-pass`, required wrapper operations may include:

- validating staged state
- detecting configuration changes
- performing required writeback
- removing temporary plaintext state

For `gh-pass`, no post-command credential handling is normally required because
the wrapper may replace itself directly with `gh`.

### Clean parent failure

A wrapper preserves the exact nonzero status returned by the parent CLI when:

- the parent CLI completes normally
- all required wrapper postconditions succeed
- no wrapper lifecycle failure occurs

Example:

```text
glab exits 4
staged config remains valid
required writeback succeeds
cleanup succeeds
glab-pass exits 4
```

This preserves command compatibility when the credential lifecycle completed
correctly.

### Wrapper lifecycle failure

A wrapper returns status `1` when any required wrapper-managed lifecycle
operation fails during ordinary execution.

Examples include:

- a required dependency is missing
- a credential entry cannot be read
- retrieved credential material is empty
- a temporary runtime directory cannot be created
- required permissions cannot be established
- staged runtime state becomes missing or empty unexpectedly
- required changed state cannot be written back
- cleanup fails
- a documented wrapper postcondition cannot be satisfied

A wrapper lifecycle failure overrides the parent CLI status.

Example:

```text
glab exits 0
changed config cannot be written back
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

When a parent status is overridden, the wrapper must report the parent status in
its diagnostics.

### No custom wrapper exit-code taxonomy

The general wrapper operational failure status is:

```text
1
```

The project will not initially assign separate public exit codes for:

- dependency failure
- credential retrieval failure
- invalid runtime state
- writeback failure
- cleanup failure
- permission failure

A larger exit-code taxonomy would:

- create additional public interface commitments
- risk collisions with parent CLI statuses
- require long-term compatibility guarantees
- provide limited value without a demonstrated automation requirement

Diagnostics identify the specific wrapper failure.

A future decision may introduce structured failure codes if concrete operator
or automation requirements justify them.

## Parent CLI status preservation

### `gh-pass`

`gh-pass` has no normal post-command credential state to validate, persist, or
remove.

After successful dependency and credential validation, it may replace itself
with the parent CLI:

```sh
GH_TOKEN=$token exec gh "$@"
```

When process replacement succeeds, the resulting status is naturally the
status of `gh`.

If process replacement itself fails, normal shell execution behavior applies.

### `glab-pass`

`glab-pass` cannot replace itself with `glab` because it must perform
post-command work.

It must:

1. run `glab`
2. record the exact parent status immediately
3. validate staged state
4. perform required writeback
5. attempt cleanup
6. determine the final result according to this ADR

The parent status must not be overwritten accidentally by later shell commands.

## Multiple wrapper failures

More than one wrapper operation may fail during a single invocation.

For example:

```text
glab exits 4
changed config writeback fails
runtime directory removal fails
```

The wrapper will not assign a semantic priority between writeback, cleanup, and
other lifecycle failures.

Instead, it must:

1. record the parent status
2. attempt every remaining safe wrapper operation
3. record each wrapper failure
4. report each relevant failure
5. return status `1`

A failure in one post-command operation must not prevent another safe operation
from being attempted.

In particular:

- writeback failure must not prevent cleanup
- invalid runtime state must not prevent cleanup
- a parent failure must not prevent required writeback
- a parent failure must not prevent cleanup

## Failure-reporting requirements

Wrapper diagnostics must:

- identify which wrapper produced the message
- state the failed wrapper operation
- avoid printing credential values
- identify non-sensitive paths or pass-entry names when useful
- distinguish parent failure from wrapper failure
- report an overridden parent status
- report every material wrapper failure encountered
- write diagnostic messages to standard error

Example:

```text
glab-pass: glab exited with status 4
glab-pass: failed to persist changed GitLab authentication state
glab-pass: failed to remove runtime directory: /tmp/glab-pass.ABC123
```

Diagnostics must not include:

- access tokens
- refresh tokens
- complete credential payloads
- decrypted pass-entry content
- command strings reconstructed through unsafe interpolation

Normal parent CLI output remains controlled by the parent CLI.

## Startup and pre-execution failures

A failure before parent execution is a wrapper lifecycle failure and returns
status `1`.

Examples include:

- missing `pass`
- missing parent CLI
- missing `mktemp`
- missing `sha256sum`
- unreadable pass entry
- empty credential material
- inability to establish runtime state
- inability to apply required permissions

When startup validation fails:

- the parent CLI must not be invoked
- no fallback credential source may be used
- any runtime state already created must be cleaned up
- cleanup failure must also be reported

## Shell execution failures

Normal shell conventions may produce:

```text
126  command found but not executable
127  command not found
```

Expected non-baseline dependencies must be validated before credential handling
where practical, so missing dependencies should normally produce:

```text
1
```

with an explicit wrapper diagnostic.

Statuses `126` and `127` remain possible for unexpected execution failures,
races, or failures occurring after validation.

The wrappers must not redefine these shell-level statuses as project-specific
meanings.

## Signal-driven termination

Handled signal termination remains distinct from ordinary parent or wrapper
failure.

The accepted signal-derived statuses are:

```text
HUP   129
INT   130
TERM  143
```

When a handled signal terminates the invocation, the wrapper must:

1. record that signal-driven termination occurred
2. ensure the parent process is not left running unintentionally
3. attempt required cleanup
4. report cleanup failure
5. preserve the conventional signal-derived status

If cleanup fails after a handled signal, the signal-derived status remains the
final status.

Example:

```text
TERM received
cleanup fails
glab-pass reports cleanup failure
glab-pass exits 143
```

The signal remains the causal termination condition.

Whether changed GitLab state should be written back after signal-driven
termination is outside this ADR and requires a separate decision.

## Cleanup semantics

Cleanup is part of the wrapper's credential-lifecycle contract.

During ordinary completion:

- cleanup success is required for the wrapper to preserve the parent status
- cleanup failure produces wrapper status `1`
- cleanup failure must be reported
- cleanup must still be attempted after another wrapper failure

During handled signal termination:

- cleanup must be attempted
- cleanup failure must be reported
- the signal-derived status remains final

Removal of temporary state reduces ordinary persistent credential residue. It
does not guarantee forensic erasure.

## Writeback semantics

For ordinary `glab-pass` completion, required writeback is a wrapper
postcondition.

If changed state must be persisted and writeback fails:

- the failure must be reported
- cleanup must still be attempted
- the final status is `1`
- any nonzero parent status must also be reported

Writeback after ordinary nonzero parent completion is governed by ADR 0005.

Writeback after signal-driven termination remains unresolved.

## Alternatives considered

### Always return the parent status

Rejected because it could conceal:

- failed credential writeback
- failed cleanup
- invalid staged state
- other violations of the wrapper lifecycle

A caller could incorrectly interpret the invocation as an ordinary parent CLI
failure even though the wrapper did not preserve its credential guarantees.

### Always return wrapper status after any parent failure

Rejected because it would discard useful parent CLI status information even
when the wrapper completed correctly.

That would weaken command compatibility.

### Preserve the parent status when both parent and wrapper fail

Rejected because a caller could mistake a wrapper lifecycle failure for a normal
parent CLI outcome.

The parent status is still reported diagnostically.

### Define a unique status for every wrapper failure

Rejected for the initial release because it would create an unnecessarily broad
public interface without a demonstrated consumer requirement.

### Assign precedence among wrapper failures

Rejected because writeback, cleanup, invalid runtime state, and permission
failures affect different lifecycle obligations.

All material failures should be reported. Any one of them is sufficient to make
the wrapper invocation unsuccessful.

### Let cleanup failure remain best effort

Rejected because inability to remove staged plaintext credential material is
directly relevant to the project's security objective.

### Override signal status when cleanup fails

Rejected because the signal is the causal termination event and its conventional
status is useful to callers and operators.

Cleanup failure remains visible through diagnostics.

## Consequences

### Positive

- Parent CLI statuses are preserved when the wrapper behaves correctly.
- Wrapper lifecycle failures cannot be hidden behind parent statuses.
- Cleanup remains mandatory and observable.
- Required writeback failures are visible.
- Multiple failures can be reported without inventing an artificial ranking.
- The status model remains small and understandable.
- Signal-derived statuses retain their conventional meaning.
- Automation can distinguish clean parent behavior from wrapper failure in most
  cases.

### Negative

- Wrapper status `1` can also be returned by a parent CLI.
- Diagnostics are required to distinguish those cases.
- A wrapper failure can replace a meaningful parent status.
- Callers cannot recover both statuses through exit codes alone.
- Multiple diagnostics may be emitted for one invocation.
- Signal-time writeback behavior remains unresolved.

## Security implications

This decision treats failure to maintain the documented credential lifecycle as
a failure of the wrapper invocation.

It ensures that:

- failed writeback cannot appear as successful credential persistence
- failed cleanup cannot appear as ordinary successful completion
- invalid staged state cannot be silently ignored
- parent failure does not excuse wrapper postcondition failures
- cleanup remains required after writeback or validation failure
- multiple wrapper failures remain visible
- diagnostics preserve failure context without exposing credentials

The decision does not provide:

- structured machine-readable error output
- unique public status values for every failure
- recovery of both parent and wrapper statuses from the final status alone
- guarantees about unhandled or uncatchable signals

## Verification requirements

Tests must cover all of the following.

### Successful outcomes

- parent success with all wrapper postconditions satisfied
- final status `0`

### Clean parent failures

- multiple representative parent nonzero statuses
- exact parent status preservation
- successful validation, writeback, and cleanup

### Startup failures

- missing non-baseline dependency
- unreadable credential entry
- empty credential material
- runtime-directory creation failure
- permission-establishment failure
- confirmation that the parent CLI is not invoked
- cleanup of any partially created runtime state

### Writeback failures

- writeback failure after parent success
- writeback failure after parent failure
- final status `1`
- parent status reported when nonzero
- cleanup still attempted
- no credential material in diagnostics

### Cleanup failures

- cleanup failure after parent success
- cleanup failure after parent failure
- cleanup failure after successful writeback
- cleanup failure after failed writeback
- final status `1` during ordinary execution
- relevant parent status reported

### Invalid runtime state

- missing staged config after parent success
- empty staged config after parent success
- missing staged config after parent failure
- empty staged config after parent failure
- invalid state not written back
- cleanup still attempted
- final status `1`

### Multiple failures

- simultaneous writeback and cleanup failure
- simultaneous invalid state and cleanup failure
- parent failure combined with multiple wrapper failures
- every material failure reported
- final status `1`

### Signals

- handled `HUP` produces `129`
- handled `INT` produces `130`
- handled `TERM` produces `143`
- cleanup is attempted after each handled signal
- cleanup failure is reported
- signal-derived status is retained after cleanup failure
- the parent process is not unintentionally left running
- no credential material appears in diagnostics

### `gh-pass`

- successful process replacement
- exact parent exit-status behavior
- argument preservation
- missing dependency behavior
- credential retrieval failure
- unexpected execution failure behavior where practical

### Isolation

All tests must use:

- fake parent CLI executables
- a fake `pass`
- fake credential values
- isolated temporary directories
- no network
- no real password store
- no production forge credentials

## Follow-on decisions

This ADR does not resolve:

- writeback behavior after signal-driven termination
- credential-management command compatibility
- structured diagnostics
- future project-specific exit-code taxonomy
- installation or packaging failure semantics

Those concerns require separate decisions if introduced.

## Decision summary

`forge-cli-pass` preserves a parent CLI's exact exit status only when all
wrapper-managed credential-lifecycle obligations complete successfully.

Ordinary wrapper lifecycle failures return status `1` and override the parent
status while preserving it in diagnostics.

All remaining safe wrapper operations must still be attempted, and every
material wrapper failure must be reported.

Handled `HUP`, `INT`, and `TERM` preserve their conventional signal-derived
statuses even when cleanup fails.
