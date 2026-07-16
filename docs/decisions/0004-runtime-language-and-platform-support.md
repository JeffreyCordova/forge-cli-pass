# ADR 0004: Select the Runtime Language and Initial Platform Support

**Status:** Proposed

## Context

The original wrappers were written in zsh because they began as personal tools
inside a zsh-based dotfiles environment.

The public project is intended to demonstrate maintainable internal security
tooling. The runtime-language decision affects:

- required dependencies
- portability claims
- static analysis
- shell-behavior consistency
- signal and cleanup semantics
- packaging
- test matrices
- operator familiarity
- long-term maintenance

The wrappers perform relatively small amounts of shell-oriented work:

- dependency validation
- credential retrieval through `pass`
- argument forwarding
- environment scoping
- secure temporary-directory handling
- file-permission handling
- parent-process execution
- cleanup
- conditional credential-state writeback

The current behavior does not appear to require zsh-specific language features.

Shell-language portability and platform portability are separate concerns. A
script may use POSIX shell syntax while relying on non-POSIX external utilities
such as:

```text
pass
gh
glab
mktemp
sha256sum
```

The project must not claim broad portability merely because a script uses
`#!/bin/sh`.

## Decision drivers

The selected approach should:

1. Keep the implementation directly auditable.
2. Preserve argument boundaries safely.
3. Support explicit and testable failure handling.
4. Support reliable cleanup and signal behavior.
5. Avoid dependence on interactive shell configuration.
6. Permit useful static analysis.
7. Minimize unnecessary runtime dependencies.
8. Match the needs of likely Linux operational environments.
9. Avoid unsupported cross-platform claims.
10. Remain proportionate to two small provider-specific wrappers.

## Options under consideration

### Option A: Retain zsh on Linux

Potential benefits:

- Minimal rewrite from the prototype.
- Existing shell-state normalization through `emulate`.
- Strong native path and parameter-expansion features.
- Consistency with the original development environment.

Potential costs:

- Adds zsh as a dedicated runtime dependency.
- Zsh is less common than `/bin/sh` or Bash in minimal Linux environments.
- ShellCheck does not provide first-class zsh analysis.
- The wrappers do not currently appear to require zsh-specific capabilities.

### Option B: Use Bash on Linux

Potential benefits:

- Common in Linux administration and security operations.
- Supported by ShellCheck.
- Provides arrays, `[[ ... ]]`, and predictable Bash-specific features.
- Easier implementation than strict POSIX shell for some cleanup and path
  logic.

Potential costs:

- Retains a non-POSIX runtime dependency.
- May encourage use of features not required by the problem.
- Does not materially improve cross-Unix portability.

### Option C: Use POSIX shell syntax with a Linux support contract

Potential benefits:

- Removes the dedicated zsh dependency.
- Uses the conventional `/bin/sh` execution model.
- Supports ShellCheck's `sh` dialect.
- Can be tested under multiple Linux shell implementations.
- Matches the wrappers' relatively simple command-execution behavior.

Potential costs:

- Requires careful handling of shell portability and signal behavior.
- Cannot rely on arrays or shell-specific path modifiers.
- External dependencies remain Linux-oriented unless separately abstracted.
- A rewrite introduces regression risk and requires comprehensive tests.

Potential initial shell matrix:

```text
Dash
Bash in POSIX mode
BusyBox ash
```

### Option D: Support POSIX shell across Linux and other Unix systems

Potential benefits:

- Broader operator compatibility.
- Reduced dependence on GNU-specific environments.

Potential costs:

- Requires accommodation for utility differences.
- Expands CI and maintenance requirements.
- May require replacing or abstracting `sha256sum`.
- Requires explicit validation of `mktemp`, permissions, installation paths,
  and runtime-directory conventions on every supported platform.
- Expands scope beyond the original Linux and WSL use case.

## Open questions

Before this ADR can be accepted, the project must decide:

1. Is Linux the intentional initial platform, or merely the first tested
   platform?
2. Which shell implementations will be supported and tested?
3. Is `sha256sum` an acceptable declared Linux dependency?
4. Should GitLab change detection instead use exact comparison against a second
   temporary plaintext copy?
5. What `mktemp` invocation is required across supported systems?
6. What signal and trap behavior must be identical across selected shells?
7. Which static-analysis tools are required?
8. Does the installation system impose additional shell requirements?
9. Is support for macOS or BSD a current requirement or a later enhancement?

## Preliminary assessment

The current leading candidate is:

> POSIX shell syntax with an initial Linux support contract.

This is not yet an accepted decision.

The rationale for further evaluation is:

- the wrappers do not appear to require zsh-specific features
- removing zsh reduces the runtime dependency surface
- POSIX shell permits ShellCheck analysis
- Linux-first support avoids making unverified cross-Unix claims
- non-POSIX external utilities can be declared explicitly

The wrapper implementations must be audited before accepting this option to
confirm that the rewrite does not reduce clarity or weaken failure and cleanup
behavior.

## Security implications

The selected language is not inherently secure.

Security depends on properties including:

- correct quoting
- safe argument forwarding
- no use of `eval`
- predictable dependency invocation
- restrictive temporary-file permissions
- explicit credential cleanup
- bounded environment propagation
- clear exit-status precedence
- behavioral testing under every supported shell
- diagnostics that do not expose credential material

Using POSIX syntax may improve verification through broader static analysis and
multi-shell testing, but it may also introduce subtle portability errors if the
implementation assumes behavior not guaranteed by the selected shells.

## Verification requirements

Before this ADR is accepted:

- the existing wrappers must be audited for language-specific behavior
- proposed rewrites must be compared for clarity and semantic equivalence
- cleanup and signal behavior must be tested
- parent exit-status behavior must be defined
- external utility dependencies must be enumerated
- the supported shell and platform matrix must be explicit
- ShellCheck behavior must be evaluated for the selected dialect
- no portability claim may exceed the tested matrix

After acceptance, CI must run the selected static and behavioral checks under
every supported shell and platform.

## Decision

No final decision has been made.

This ADR remains **Proposed** until the runtime language and initial platform
support contract are explicitly approved.
