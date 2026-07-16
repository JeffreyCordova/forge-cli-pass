# Security assurance

This document records the security properties claimed by `forge-cli-pass` and
the evidence supporting those claims.

The threat model describes assets, trust boundaries, threats, and residual
risks. This document provides the complementary assurance view:

> What does the project claim to protect, how is that claim implemented, how is
> it verified, and where does the claim stop?

This is a lightweight assurance case. It is not a formal proof, certification,
or independent security assessment.

## Scope

This assurance case applies to the documented `v0.1.x` architecture:

- Linux
- POSIX `sh`
- Dash
- Bash in POSIX mode
- BusyBox `ash`
- `pass` as the authoritative credential store
- `gh` and `glab` as parent CLIs
- source-only releases
- copy installation and guarded development-link installation

The claims depend on the assumptions and exclusions documented in
[`threat-model.md`](threat-model.md).

## Assurance model

Each assurance claim contains four elements:

- **Claim:** the security or compatibility property the project intends to
  preserve.
- **Controls:** implementation behavior intended to satisfy the claim.
- **Evidence:** source, tests, decisions, and release records supporting the
  claim.
- **Limitations:** conditions under which the evidence does not establish the
  claim.

The evidence types used in this document are:

| Evidence type | Meaning |
|---|---|
| Architectural decision | An accepted constraint on implementation and maintenance |
| Source implementation | Current code implementing the claimed control |
| Behavioral test | Executable evidence for a specific observable property |
| Cross-shell verification | The behavior is exercised under every supported shell |
| Static verification | ShellCheck and syntax validation |
| Process control | Installation, CI, or release procedure enforcing the property |
| Operational evidence | A real command or defect demonstrated outside the fixture environment |

Tests establish behavior under the tested conditions. They do not establish the
security of the operating system, dependencies, remote services, or excluded
adversaries.

## Top-level claim

### SA-00: The wrappers preserve credential ownership and ordinary command behavior

Under the assumptions in the threat model, `forge-cli-pass`:

1. keeps durable GitHub and GitLab authentication state in `pass`
2. limits credential exposure to the mechanism required by the invoked parent
   CLI
3. rejects parent authentication operations that conflict with wrapper-owned
   credentials
4. validates GitLab state before durable writeback
5. preserves ordinary command arguments, standard input, output streams, and
   exit status
6. performs conditional recovery and cleanup after ordinary failure and handled
   signals
7. publishes releases from verified, immutable source revisions

This top-level claim is supported by the subordinate claims below.

## Assurance summary

| Claim | Security property | Primary evidence |
|---|---|---|
| SA-01 | `pass` remains the authoritative credential store | ADRs 0003 and 0009; wrapper source; entry-selection tests |
| SA-02 | GitHub credential exposure is limited to one parent invocation | `src/gh-pass`; first-line and environment-injection tests |
| SA-03 | GitLab configuration is staged privately | ADR 0005; `src/glab-pass`; staging and permission tests |
| SA-04 | Only eligible changed GitLab state is persisted | Fingerprinting, state validation, and writeback tests |
| SA-05 | Credential-management and disclosure operations fail closed | ADR 0008; authentication-policy tests |
| SA-06 | Parent arguments and standard input are preserved | Argument-boundary and stdin round-trip tests |
| SA-07 | Exit-status and failure precedence are deterministic | ADR 0006; status and multi-failure tests |
| SA-08 | Handled signals preserve eligible state and causal status | ADR 0007; HUP, INT, and TERM tests |
| SA-09 | Diagnostics avoid wrapper-originated credential disclosure | Source review and disclosure-regression tests |
| SA-10 | Installation modifies only intended command paths | ADR 0010; installation and guarded-link tests |
| SA-11 | Verification is repeatable across supported shells | ADRs 0004 and 0012; `make check`; GitHub Actions |
| SA-12 | Published releases identify verified source commits | ADR 0013; annotated tags; mirrored tags; GitHub releases |

## Detailed claims

### SA-01: `pass` remains the authoritative credential store

**Claim**

The wrappers do not treat the parent CLIs' normal persistent authentication
state as authoritative. Wrapper-managed durable credentials are selected from
documented `pass` entries.

**Controls**

- GitHub and GitLab use separate documented default entries.
- Each default may be replaced by one provider-specific environment override.
- An unset override selects the documented default.
- An empty override is rejected.
- Overrides containing newline or carriage-return characters are rejected.
- Entry discovery and fallback behavior are not performed.
- `glab-pass` restores the complete stored GitLab configuration and writes
  eligible changes back to the same selected entry.

**Evidence**

- ADR 0003: `pass` is the authoritative credential store.
- ADR 0009: default entries and override behavior.
- `src/gh-pass`
- `src/glab-pass`
- Tests covering:
  - documented defaults
  - explicit overrides
  - entry names containing spaces
  - empty overrides
  - newline and carriage-return rejection
  - exact writeback-entry selection

**Related threats**

- TM-06: legitimate GitLab changes are lost
- TM-08: authentication commands bypass wrapper ownership
- TM-10: wrong `pass` entry is selected

**Limitations**

A syntactically valid override can intentionally select an unintended entry.
The invoking environment and user are trusted.

The wrappers do not authenticate the contents of the password store or protect
against compromise of the GPG key, GPG agent, or local user account.

---

### SA-02: GitHub credential exposure is limited to one parent invocation

**Claim**

`gh-pass` supplies the selected GitHub token only to the invoked `gh` process
and does not create wrapper-managed persistent GitHub CLI state.

**Controls**

- The complete `pass` entry is read before token extraction.
- Only the first line is used as the GitHub token.
- An empty first line is rejected.
- The complete retrieved value is cleared before parent execution.
- The token is supplied through `GH_TOKEN`.
- The wrapper replaces itself with `gh` using `exec`.
- Shell tracing is disabled.

**Evidence**

- `src/gh-pass`
- Tests covering:
  - complete retrieval before execution
  - empty-token rejection
  - first-line-only injection
  - prevention of parent execution after credential failure
  - exact parent argument preservation
  - exact parent exit status

**Related threats**

- TM-02: disclosure through tracing or diagnostics
- TM-03: GitHub token exposure through the environment
- TM-09: wrapper changes parent command behavior

**Limitations**

The token is present in the parent process environment because that is the
supported parent CLI interface.

The wrapper does not protect the token from:

- the parent CLI
- the operating system
- a debugger
- sufficiently privileged process inspection
- a compromised local user
- a malicious executable resolved as `gh`

Clearing a shell variable does not guarantee removal from all process memory.

---

### SA-03: GitLab configuration is staged privately

**Claim**

The GitLab configuration restored from `pass` is staged in a private,
unpredictable runtime directory rather than the user's ordinary persistent
GitLab configuration location.

**Controls**

- `/tmp` must exist and be usable as the accepted runtime parent.
- The runtime directory is created with `mktemp -d`.
- The accepted template is `/tmp/glab-pass.XXXXXX`.
- The process uses `umask 077`.
- The runtime directory is set to mode `0700`.
- The staged configuration is set to mode `0600`.
- `GLAB_CONFIG_DIR` points only to the private runtime directory for the parent
  invocation.
- The runtime directory is removed after processing.

**Evidence**

- ADR 0005: private GitLab runtime staging.
- `src/glab-pass`
- Tests covering:
  - accepted `/tmp` template
  - unpredictable runtime creation
  - directory mode
  - file mode
  - `GLAB_CONFIG_DIR`
  - `mktemp` failure
  - permission failure
  - cleanup after success and failure

**Related threats**

- TM-04: unauthorized access to transient GitLab state
- TM-07: temporary state remains after execution

**Limitations**

Filesystem permissions do not protect against:

- root
- a compromised kernel
- another process operating as the invoking user
- forensic recovery
- filesystem snapshots
- journals
- swap
- backups

Deletion is cleanup, not guaranteed secure erasure.

---

### SA-04: Only eligible changed GitLab state is persisted

**Claim**

`glab-pass` writes state back to `pass` only when the staged GitLab
configuration changed and remains structurally eligible for persistence.

**Controls**

Before parent execution, the staged configuration must:

- exist
- be a regular file
- be readable
- be non-empty
- produce a successful SHA-256 fingerprint

After parent execution or a handled signal, state must again satisfy the
applicable eligibility checks.

Writeback occurs only when:

- post-execution state is eligible
- fingerprinting succeeds
- the post-execution fingerprint differs from the initial fingerprint

The complete opaque configuration is written back without field-level
transformation.

**Evidence**

- ADR 0005
- `src/glab-pass`
- Tests covering:
  - complete opaque-config restoration
  - unchanged-state suppression
  - changed-state writeback after success
  - changed-state writeback after ordinary parent failure
  - missing post-command state
  - empty post-command state
  - non-regular post-command state
  - initial and final fingerprint failure
  - writeback failure
  - exact writeback payload

**Related threats**

- TM-05: invalid GitLab state replaces durable state
- TM-06: legitimate GitLab changes are lost
- TM-12: fingerprinting is mistaken for authentication

**Limitations**

Structural eligibility does not establish semantic correctness.

The wrapper deliberately treats the GitLab configuration as opaque. It does not
parse tokens, validate YAML semantics, authenticate field values, or determine
whether a changed credential remains accepted by GitLab.

SHA-256 is used for change detection, not origin authentication.

---

### SA-05: Credential-management and disclosure operations fail closed

**Claim**

Commands that would replace, remove, or disclose wrapper-managed credentials
are rejected before the wrapper retrieves or stages credential material.

**Controls**

- Ordinary commands are allowed.
- Help behavior is allowed.
- Non-disclosing authentication status is allowed.
- Known credential-management commands are rejected.
- Known credential-display options are rejected.
- Unknown authentication subcommands are rejected.
- Policy enforcement occurs before credential access.

**Evidence**

- ADR 0008: parent authentication-command policy.
- `src/gh-pass`
- `src/glab-pass`
- Tests covering:
  - allowed authentication status
  - rejected token retrieval or display
  - rejected login
  - rejected unknown authentication commands
  - absence of `pass`, staging, or parent execution after rejection
  - ordinary arguments that resemble authentication text

**Related threats**

- TM-02: credential disclosure
- TM-08: authentication commands bypass wrapper ownership

**Limitations**

The policy is based on the parent CLIs' command structure.

A future parent version could add credential-affecting behavior outside the
currently recognized authentication command tree. Upstream changes therefore
require maintenance review.

The wrapper does not sanitize the output of allowed ordinary commands.

---

### SA-06: Parent arguments and standard input are preserved

**Claim**

For allowed ordinary operations, wrapper mediation does not alter parent
argument boundaries or the bytes supplied through standard input.

**Controls**

- Arguments are forwarded using `"$@"`.
- Empty arguments are retained.
- Arguments containing spaces remain single arguments.
- `gh-pass` uses `exec`, inheriting the caller's standard input directly.
- `glab-pass` preserves descriptor 0 before asynchronous execution and restores
  it explicitly for `glab`.
- Standard output and standard error remain inherited.

**Evidence**

- `src/gh-pass`
- `src/glab-pass`
- Tests covering:
  - argument count
  - argument order
  - spaces within arguments
  - empty trailing arguments
  - byte-for-byte standard-input capture
  - stdin verification under Dash, Bash POSIX mode, and BusyBox `ash`
- Operational evidence:
  - a real `glab api --input -` request exposed the original compatibility
    failure
  - the same command succeeded after the `v0.1.1` correction

**Related threats**

- TM-09: wrapper changes parent command behavior
- TM-11: upstream behavior invalidates assumptions

**Limitations**

The evidence covers the supported shells and tested invocation patterns.

It does not establish equivalence for every terminal mode, descriptor
arrangement, interactive prompt, parent CLI version, shell implementation, or
future command.

---

### SA-07: Exit-status and failure precedence are deterministic

**Claim**

An ordinary parent exit status is returned exactly when all wrapper obligations
succeed. A wrapper-obligation failure returns status `1` and reports relevant
failure context.

**Controls**

- Ordinary parent status is captured without normalization.
- Unchanged or successfully persisted GitLab state permits exact parent-status
  return.
- Failed validation, fingerprinting, writeback, or cleanup is a wrapper failure.
- Wrapper failure takes precedence over an ordinary parent status.
- When multiple failures occur, diagnostics report each relevant failure.

**Evidence**

- ADR 0006: exit-status and failure-precedence contract.
- `src/glab-pass`
- Tests covering:
  - exact parent success
  - exact nonzero parent failure
  - changed-state writeback after parent failure
  - cleanup failure overriding parent status
  - simultaneous parent, writeback, and cleanup failures
  - reporting of both writeback and cleanup failures

**Related threats**

- TM-09: changed parent behavior
- TM-13: wrapper failure obscures parent failure

**Limitations**

One process exit status cannot encode multiple independent failures.

Status `1` indicates that the wrapper failed to complete its obligations.
Diagnostics are required to distinguish validation, persistence, and cleanup
failures.

---

### SA-08: Handled signals preserve eligible state and causal status

**Claim**

When the wrapper receives HUP, INT, or TERM while `glab` is running, it attempts
eligible state recovery and cleanup while preserving a final status associated
with the causal signal.

**Controls**

- Signal handlers record HUP, INT, or TERM.
- The asynchronous child is terminated.
- Eligible changed GitLab state is considered for writeback.
- Cleanup is attempted.
- Signal-derived final statuses are:
  - HUP: `129`
  - INT: `130`
  - TERM: `143`
- Signal-time writeback or cleanup failure is reported without replacing the
  causal signal status.
- INT uses TERM to ensure termination of an asynchronous child in shells where
  asynchronous commands inherit SIGINT as ignored.

**Evidence**

- ADR 0007: signal-time writeback and cleanup.
- `src/glab-pass`
- Tests covering:
  - HUP with unchanged state
  - INT with changed state
  - TERM with empty interrupted state
  - signal-time writeback failure
  - signal-time cleanup failure
  - expected child signal
  - expected final wrapper status
  - runtime cleanup

**Related threats**

- TM-06: legitimate state is lost
- TM-07: temporary state remains
- TM-09: wrapper changes signal behavior

**Limitations**

The recovery path cannot execute after:

- SIGKILL
- kernel failure
- power loss
- machine reset
- catastrophic shell failure

Signal behavior also depends on the operating system, shell, parent CLI, and
process topology.

---

### SA-09: Diagnostics avoid wrapper-originated credential disclosure

**Claim**

Wrapper-generated diagnostics identify operational failures without printing
the GitHub token or complete GitLab authentication state.

**Controls**

- Shell tracing is disabled.
- Credential values are not interpolated into error messages.
- Known disclosure commands fail before credential retrieval or staging.
- Writeback errors refer to the entry or operation rather than its payload.
- Tests use recognizable fake credential material and assert that it does not
  appear in diagnostics.

**Evidence**

- `src/gh-pass`
- `src/glab-pass`
- Tests covering:
  - rejected token-display operations
  - writeback failure
  - signal-time writeback failure
  - absence of known fake credential values in standard error

**Related threats**

- TM-02: credential disclosure through tracing or diagnostics

**Limitations**

The wrapper does not filter:

- parent standard output
- parent standard error
- terminal history
- shell history
- debugger output
- process inspection
- core dumps
- audit logs outside wrapper control

Allowed ordinary commands may intentionally print sensitive remote data.

---

### SA-10: Installation modifies only intended command paths

**Claim**

Project installation and removal operate only on the selected wrapper command
paths and avoid deleting unrelated files.

**Controls**

- Normal installation copies the two wrapper commands.
- `PREFIX`, `BINDIR`, and `DESTDIR` are explicit.
- Normal uninstall removes only the project command paths.
- Development installation creates absolute links to the current checkout.
- Development installation refuses an existing regular file.
- Development uninstall removes only links that resolve to the matching
  checkout.

**Evidence**

- ADR 0010: installation and source distribution.
- `Makefile`
- Installation tests covering:
  - staged installation through `DESTDIR`
  - prefixes containing spaces
  - explicit binary directories
  - narrow uninstall
  - absolute development links
  - refusal to overwrite regular files
  - matching-link removal
  - retention of copied installations

**Related threats**

- TM-15: installation damages unrelated paths

**Limitations**

The build interface does not authenticate the selected destination.

A user can still choose an incorrect path or invoke installation with elevated
privileges. The Makefile deliberately does not acquire privilege itself.

---

### SA-11: Verification is repeatable across supported shells

**Claim**

The accepted verification interface exercises the implementation consistently
under every supported shell and checks installation behavior independently.

**Controls**

- ShellCheck runs in POSIX `sh` mode.
- Syntax is checked with:
  - Dash
  - Bash in POSIX mode
  - BusyBox `ash`
- Behavioral suites run under the same three-shell matrix.
- Installation tests run separately.
- The CI test BusyBox is built from a checksum-verified upstream source archive.
- CI invokes the same accepted `make check` interface used locally.

**Evidence**

- ADR 0004: language, platform, shell, and utility baseline.
- ADR 0012: GitHub Actions verification.
- `.github/workflows/ci.yml`
- `ci/build-test-busybox.sh`
- `tests/run.sh`
- `tests/test-gh-pass.sh`
- `tests/test-glab-pass.sh`
- installation test suite
- successful GitHub Actions runs for release commits

**Related threats**

- TM-09: command incompatibility
- TM-11: upstream behavior invalidates assumptions
- TM-14: release does not correspond to verified source

**Limitations**

The matrix verifies selected shell implementations, not every POSIX-conforming
shell.

Fixtures model expected dependency behavior but cannot reproduce every future
version, environmental interaction, network condition, or parent CLI defect.

---

### SA-12: Published releases identify verified source commits

**Claim**

A canonical GitHub release refers to an existing annotated tag that resolves to
the intended verified source commit and is mirrored to GitLab.

**Controls**

A release requires:

- the intended version in `VERSION`
- a dated changelog entry
- a clean working tree and index
- the release commit on `main`
- successful local verification
- successful CI for the exact release commit
- the commit pushed to GitHub and GitLab
- an annotated release tag
- the tag pushed to both upstreams
- verification that both remote tags resolve to the release commit
- GitHub release creation with an already-existing remote tag
- immutable correction through a new version rather than tag movement

**Evidence**

- ADR 0013: versioning and release publication.
- `VERSION`
- `CHANGELOG.md`
- signed annotated tags:
  - `v0.1.0`
  - `v0.1.1`
- matching GitHub and GitLab tags
- GitHub Actions records
- canonical GitHub release records

**Related threats**

- TM-14: release does not correspond to verified source

**Limitations**

The project currently publishes source only.

The process does not provide:

- generated-artifact provenance
- reproducible-build evidence
- source-archive checksums maintained by the project
- SLSA provenance
- independent attestations
- protection against maintainer account or signing-key compromise

Those controls would become more relevant if the project begins publishing
generated executables or packages.

## Claim-to-threat traceability

| Threat | Supporting assurance claims |
|---|---|
| TM-01: malicious dependency through `PATH` | SA-11 provides dependency-explicit verification; underlying trust remains accepted |
| TM-02: credential disclosure | SA-02, SA-05, SA-09 |
| TM-03: token exposure through environment | SA-02 |
| TM-04: transient-state access | SA-03 |
| TM-05: invalid durable writeback | SA-04 |
| TM-06: lost GitLab changes | SA-01, SA-04, SA-08 |
| TM-07: residual temporary state | SA-03, SA-08 |
| TM-08: authentication-policy bypass | SA-01, SA-05 |
| TM-09: changed parent semantics | SA-06, SA-07, SA-08, SA-11 |
| TM-10: wrong entry selection | SA-01 |
| TM-11: upstream behavior drift | SA-05, SA-06, SA-11 |
| TM-12: fingerprint mistaken for authentication | SA-04 |
| TM-13: obscured parent failure | SA-07 |
| TM-14: release provenance failure | SA-11, SA-12 |
| TM-15: unsafe installation | SA-10 |

## Evidence gaps

The current assurance case deliberately does not claim evidence for:

- resistance to a compromised local user or root
- dependency-binary authenticity at runtime
- semantic validation of the GitLab configuration
- guaranteed cleanup after uncatchable termination
- secure erasure
- memory zeroization
- parent CLI extension isolation
- remote service correctness
- network-path security
- non-Linux portability
- every POSIX shell implementation
- generated-artifact supply-chain provenance
- independent security review
- formal verification

These are limitations of the selected system boundary, not undocumented
guarantees.

## Maintenance requirements

A change requires assurance review when it:

- changes a security claim
- changes a trust boundary
- adds a dependency
- adds a credential-bearing environment variable or file
- changes `pass` entry selection
- changes GitLab staging, validation, fingerprinting, or writeback
- changes argument, stdin, output, status, or signal behavior
- changes authentication-command policy
- adds a shell, operating system, provider, or installation method
- changes release publication or adds generated artifacts
- invalidates an existing behavioral test
- addresses a new threat or security report

For each affected claim, maintainers should update:

1. the implementation control
2. the behavioral evidence
3. the relevant ADR when the accepted architecture changes
4. [`threat-model.md`](threat-model.md)
5. this assurance document
6. release notes when user-visible behavior changes

## Related documents

- [`threat-model.md`](threat-model.md) — assets, boundaries, threats, and
  residual risks
- [`architecture.md`](architecture.md) — integrated current architecture
- [`project-context.md`](project-context.md) — project purpose and constraints
- [`decisions/README.md`](decisions/README.md) — accepted architectural
  decisions
- [`../SECURITY.md`](../SECURITY.md) — vulnerability-reporting policy
- [`../README.md`](../README.md) — user-facing contract
- [`../tests/`](../tests/) — executable behavioral evidence
- [`../CHANGELOG.md`](../CHANGELOG.md) — released behavior changes
