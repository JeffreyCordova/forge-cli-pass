# ADR 0004: Use POSIX Shell with an Initial Linux Support Contract

**Status:** Accepted

## Context

The original wrappers were written in zsh because they began as personal tools
inside a zsh-based dotfiles environment.

As `forge-cli-pass` developed into a public security-focused tool, the runtime
language became an architectural decision rather than an incidental property of
the original environment.

The language choice affects:

- runtime dependencies
- implementation auditability
- static analysis
- shell-behavior consistency
- cleanup and signal handling
- packaging
- test coverage
- platform support claims
- long-term maintenance

The wrappers perform a bounded set of shell-oriented operations:

- validate required dependencies
- retrieve credential material through `pass`
- validate retrieved state
- preserve command-line argument boundaries
- scope credentials to a parent CLI invocation
- create and protect temporary filesystem state
- execute `gh` or `glab`
- detect GitLab configuration changes
- persist changed GitLab state
- clean up temporary credential material
- report wrapper and parent-command failures

These responsibilities do not require zsh-specific features.

Shell-language portability and application portability are separate concerns. A
script can use the POSIX shell language while depending on utilities or
applications that are not specified by POSIX.

For example, this project requires commands including:

```text
pass
gh
glab
mktemp
sha256sum
```

The project must therefore avoid implying universal POSIX-platform support
merely because its scripts use `#!/bin/sh`.

## Decision drivers

The selected runtime should:

1. Keep the implementation small and directly auditable.
2. Preserve user argument boundaries safely.
3. Support explicit and testable failure handling.
4. Support reliable cleanup and signal handling.
5. Avoid dependence on interactive shell configuration.
6. Permit useful static analysis.
7. Minimize unnecessary runtime dependencies.
8. fit common Linux operational environments.
9. Support isolated behavioral testing.
10. Avoid portability claims beyond the tested environment.
11. Remain proportionate to two provider-specific wrappers.
12. Preserve the credential-lifecycle requirements defined by the architecture.

## Decision

The runtime wrappers will be implemented using the POSIX shell command language
with an initial Linux support contract.

The public commands will use:

```sh
#!/bin/sh
```

The initial supported shell implementations are:

- Dash
- Bash operating in POSIX mode
- BusyBox `ash`

The project will use ShellCheck with the `sh` dialect for static analysis.

The initial supported operating-system family is Linux. The project does not
initially claim support for:

- macOS
- FreeBSD
- OpenBSD
- other BSD systems
- every POSIX-conforming operating system
- non-Linux environments that happen to provide `/bin/sh`

Support for another operating system requires explicit testing and, when
material architectural changes are needed, a new or superseding decision
record.

## Shell-language requirements

The runtime scripts must remain within the supported POSIX shell subset.

They must not depend on shell-specific features such as:

- zsh parameter modifiers
- zsh arrays
- Bash arrays
- `[[ ... ]]`
- process substitution
- shell-specific regular-expression operators
- shell-specific path-resolution syntax
- shell-specific trap names where a portable form is available

The implementation must:

- quote expansions unless deliberate field splitting is required
- forward parent CLI arguments using `"$@"`
- avoid `eval`
- avoid constructing executable shell commands as strings
- avoid dependence on aliases, functions, or interactive shell options
- disable inherited command tracing before handling credential material
- establish a restrictive `umask`
- handle expected failures explicitly
- preserve documented parent-command and wrapper exit semantics
- use syntax verified under every supported shell

The language decision does not require pursuing portability at the expense of
clarity or credential-lifecycle correctness.

## Platform utility model

The project distinguishes between:

1. baseline platform utilities
2. explicitly validated non-baseline dependencies

### Baseline platform utilities

A supported Linux environment is assumed to provide a POSIX-compatible
`/bin/sh` and the ordinary userland utilities required for basic file,
permission, and process operations.

The baseline includes the utilities used for operations such as:

- creating directories
- removing files and directories
- changing file permissions
- testing filesystem state
- printing diagnostics

Examples include:

```text
chmod
mkdir
rm
printf
```

Baseline utilities are part of the supported platform contract. The wrappers do
not individually validate each baseline command before execution.

Absence or incompatible behavior of a baseline utility places the system
outside the supported platform contract.

The exact baseline relied upon by the implementation must remain documented and
must not expand silently.

### Non-baseline dependencies

Commands specific to this project's functionality, or utilities not guaranteed
by the baseline platform contract, must be validated explicitly before handling
credential material where practical.

For `gh-pass`, the initial non-baseline dependencies are:

```text
pass
gh
```

For `glab-pass`, the initial non-baseline dependencies are:

```text
pass
glab
mktemp
sha256sum
```

Missing non-baseline dependencies must produce an explicit wrapper diagnostic
and a wrapper failure.

The wrappers must not silently substitute another utility or credential source.

## Temporary-directory utility

`mktemp` is an accepted non-baseline dependency.

Although `mktemp` is widely available on Unix-like systems, it is not treated as
part of the project's POSIX utility baseline.

`glab-pass` will use a tested Linux-compatible invocation to create a private,
unpredictably named directory beneath `/tmp`:

```sh
mktemp -d /tmp/glab-pass.XXXXXX
```

The runtime-directory policy, permissions, cleanup, and writeback behavior are
defined separately in ADR 0005.

The use of `mktemp` is preferred over constructing predictable paths from
process IDs, timestamps, usernames, or other guessable values.

## Content-fingerprint utility

`sha256sum` is an accepted non-baseline dependency for the initial Linux
release.

`glab-pass` uses `sha256sum` to produce content fingerprints before and after
ordinary parent CLI execution.

The fingerprints are used only to determine whether the staged GitLab
configuration changed and therefore requires writeback.

This use does not:

- authenticate the configuration
- verify its provenance
- establish a trusted integrity measurement
- protect it from a malicious parent CLI
- make SHA-256 part of an external verification protocol

The use of `sha256sum` is an implementation mechanism for mutation detection.

It is retained because it:

- avoids creating a second plaintext configuration copy
- is readily available on the initial supported Linux environments
- keeps the comparison mechanism simple
- is already compatible with the existing credential-staging model

A future cross-platform decision may replace or abstract this mechanism if
another supported operating system does not provide `sha256sum`.

## Static analysis

ShellCheck will be used with the POSIX shell dialect:

```sh
shellcheck --shell=sh src/gh-pass src/glab-pass
```

Static-analysis findings must be reviewed rather than suppressed broadly.

A suppression is acceptable only when:

- the behavior is intentional
- the reason is documented near the affected code
- the suppression is as narrow as practical
- behavioral tests cover the relevant behavior where appropriate

ShellCheck complements but does not replace manual review or behavioral tests.

## Supported shell matrix

The scripts must be syntax-checked and behaviorally tested under:

```text
Dash
Bash in POSIX mode
BusyBox ash
```

Representative syntax checks include:

```sh
dash -n src/gh-pass
dash -n src/glab-pass

bash --posix -n src/gh-pass
bash --posix -n src/glab-pass

busybox ash -n src/gh-pass
busybox ash -n src/glab-pass
```

Syntax validation alone is insufficient.

Behavioral tests must execute the wrappers under every supported shell because
portability defects may involve:

- trap behavior
- signal handling
- command substitution
- expansion semantics
- exit-status propagation
- environment assignment
- temporary-file cleanup
- argument forwarding

## Installation boundary

This decision applies to the runtime wrapper commands.

It does not determine:

- the installation interface
- whether installation uses a `Makefile`
- release-archive structure
- package-manager integration
- development symlink workflows
- installation prefixes
- man-page installation
- shell-completion installation

The installation and distribution model requires a separate architecture
decision.

An installation mechanism must not impose a stronger runtime-shell dependency
on the installed wrappers unless that distinction is explicit.

## Alternatives considered

### Retain zsh on Linux

Potential advantages included:

- minimal change from the prototype
- existing shell-state normalization through `emulate`
- convenient path and parameter operations
- consistency with the original development environment

Rejected because:

- zsh would remain an otherwise unnecessary runtime dependency
- the wrapper behavior does not require zsh-specific capabilities
- zsh has weaker support from the selected static-analysis tooling
- the public tool should not inherit a personal interactive-shell dependency
  without a functional requirement

### Use Bash on Linux

Potential advantages included:

- broad familiarity in Linux administration and security operations
- ShellCheck support
- arrays and richer conditional syntax
- simpler implementation of some shell logic

Rejected because:

- the current wrapper responsibilities do not require Bash-specific features
- Bash would remain a dedicated runtime dependency
- using Bash would not materially improve the initial Linux support contract
- the smaller POSIX shell subset is adequate and can be tested across several
  implementations

Bash remains part of the test matrix through its POSIX mode.

### Use POSIX shell across multiple Unix systems

Potential advantages included:

- broader operator compatibility
- reduced Linux-specific positioning
- possible support for macOS and BSD environments

Deferred because:

- utility behavior differs across operating systems
- `sha256sum` is not normally present under that name on all target systems
- `mktemp` options and conventions require platform-specific verification
- installation paths and userland behavior differ
- each supported platform would expand CI and maintenance requirements
- the original and immediate target environments are Linux-based

The project will not claim untested cross-Unix support.

### Continue using personal zsh wrappers while documenting POSIX intent

Rejected because documentation should describe the actual implementation rather
than a future aspiration.

The public commands must conform to this decision before the project claims the
accepted runtime contract.

## Consequences

### Positive

- zsh is removed as a dedicated runtime dependency.
- The implementation can be analyzed using ShellCheck.
- The wrappers can be tested across multiple `/bin/sh` implementations.
- The language matches the bounded shell-oriented responsibilities of the
  project.
- Common minimal Linux environments are more likely to satisfy the interpreter
  requirement.
- Shell-language portability and operating-system support are distinguished
  explicitly.
- Linux-specific utility dependencies remain visible and testable.
- The public architecture no longer depends on the maintainer's interactive
  shell preference.

### Negative

- The existing zsh implementations must be rewritten.
- The rewrite introduces regression risk.
- POSIX shell lacks conveniences available in zsh and Bash.
- Signal and trap behavior require explicit testing under every supported
  shell.
- Application portability remains limited by non-POSIX dependencies.
- Cross-platform support will require additional design and CI work.
- Maintaining compatibility across several shell implementations expands the
  test matrix.

## Security implications

POSIX shell is not considered inherently more secure than zsh or Bash.

The security value of this decision comes from:

- removing an unnecessary runtime dependency
- enabling first-class ShellCheck analysis
- testing behavior under multiple shell implementations
- reducing reliance on shell-specific implicit behavior
- making the platform and dependency boundaries explicit

The implementation must still protect the documented credential lifecycle
through:

- correct quoting
- exact argument forwarding
- no use of `eval`
- deterministic dependency invocation
- restrictive runtime permissions
- explicit error handling
- explicit cleanup
- bounded credential environment propagation
- defined writeback behavior
- defined failure and exit-status semantics
- diagnostics that do not expose credential material

Portability defects can themselves become security defects when they affect:

- cleanup
- file permissions
- temporary-directory creation
- signal handling
- credential writeback
- argument interpretation

The multi-shell support claim therefore requires behavioral verification, not
only syntactic conformance.

## Verification requirements

Before the project claims conformance with this decision:

- `gh-pass` and `glab-pass` must be rewritten using the supported POSIX shell
  subset
- the prior zsh behavior must be audited and represented in regression tests
- ShellCheck must pass using the `sh` dialect, subject only to reviewed and
  narrowly documented suppressions
- syntax validation must pass under Dash
- syntax validation must pass under Bash POSIX mode
- syntax validation must pass under BusyBox `ash`
- behavioral tests must run under every supported shell
- the non-baseline dependency checks must be tested
- argument forwarding must preserve values and boundaries
- credential delivery must remain scoped as documented
- cleanup and signal behavior must be tested
- GitLab mutation and writeback behavior must be tested
- parent and wrapper exit-status semantics must be tested
- tests must not use real credentials, a real password store, or network access
- no documentation may claim support beyond the tested Linux shell matrix

## Follow-on decisions

This decision does not resolve:

- GitLab runtime-state and writeback semantics
- signal-driven writeback
- failure and exit-status precedence
- credential-management command compatibility
- installation and distribution
- release packaging
- future non-Linux platform support

Those concerns are governed by separate architecture decisions.

## Decision summary

`forge-cli-pass` will implement `gh-pass` and `glab-pass` in POSIX shell for an
initial Linux support contract.

The project will test the wrappers under Dash, Bash in POSIX mode, and BusyBox
`ash`, and will use ShellCheck with the `sh` dialect.

The project will assume a documented baseline Linux userland and will explicitly
validate only its non-baseline dependencies.

`sha256sum` and `mktemp` remain accepted non-baseline dependencies for
`glab-pass`.

The project does not currently claim universal POSIX-platform portability.
