# Contributing to `forge-cli-pass`

Thank you for contributing to `forge-cli-pass`.

This project provides pass-backed credential lifecycle wrappers for the GitHub and GitLab command-line clients:

* `gh-pass`, wrapping `gh`
* `glab-pass`, wrapping `glab`

Because the project handles authentication material, contributions must preserve its documented credential boundaries, failure behavior, and security invariants.

## Project status

`forge-cli-pass` is an active, released project in the `v0.1.x` development
line.

The current supported baseline is:

* Linux
* POSIX `sh`
* Dash
* Bash in POSIX mode
* BusyBox `ash`
* `pass` as the authoritative credential store
* provider-specific `gh-pass` and `glab-pass` commands
* source-only releases published from annotated tags

Substantial changes to this baseline require review against the accepted
architecture decisions, threat model, assurance case, and maintenance guide.

## Start here

Read these documents before making substantial changes:

* [`docs/project-context.md`](docs/project-context.md)
* [`docs/architecture.md`](docs/architecture.md)
* [`docs/threat-model.md`](docs/threat-model.md)
* [`docs/security-assurance.md`](docs/security-assurance.md)
* [`docs/maintenance.md`](docs/maintenance.md)
* [`docs/decisions/`](docs/decisions/)
* [`SECURITY.md`](SECURITY.md), when reporting a vulnerability

`docs/project-context.md` explains why the project exists.

`docs/architecture.md` integrates the current system boundaries, credential
flows, security invariants, and accepted decisions.

Accepted Architecture Decision Records (ADRs) are authoritative. The threat
model records assets, trust boundaries, threats, and residual risks. The
assurance case maps security claims to implementation controls and evidence.
The maintenance guide defines the operational change and release workflow.

## Contribution principles

Contributions should preserve the following principles.

### Keep the wrappers provider-specific

`gh-pass` and `glab-pass` remain separate commands because `gh` and `glab` use materially different credential-delivery and credential-mutation models.

Do not introduce a unified command, shared plugin framework, or generic credential-backend abstraction without an accepted architecture decision.

### Keep `pass` authoritative

`pass` is the authoritative durable store for wrapper-managed forge API credential state.

Do not silently fall back to:

* parent CLI credential files
* desktop keyrings
* plaintext environment files
* alternate secret stores

Support for another credential backend would materially change the product boundary and requires an explicit architecture decision.

### Preserve parent CLI behavior

The wrappers should adapt credential handling without reimplementing ordinary `gh` or `glab` behavior.

For supported commands:

* preserve argument order and boundaries
* forward arguments without semantic reinterpretation
* preserve standard input
* allow the parent CLI to control normal output
* preserve standard output and standard error
* preserve the exact ordinary parent exit status when wrapper obligations
  succeed
* avoid unnecessary modification of parent CLI state

### Minimize credential exposure

Contributions must not unnecessarily:

* persist decrypted credential material
* print credentials in diagnostics
* place credentials in shell history
* introduce long-lived credential environment variables
* copy credential state into repository files
* weaken temporary-file permissions
* bypass cleanup behavior
* populate default parent CLI authentication files

### Fail safely

The wrappers should reject invalid or ambiguous state rather than silently changing the credential model.

Examples include:

* missing dependencies
* missing or empty credentials
* unsafe runtime directories
* failed credential writeback
* malformed staged state
* unexpected filesystem conflicts

Avoid fallback behavior that conceals a failure or uses credentials from an unintended source.

### Keep the implementation auditable

The project should remain proportionate to the problem.

Prefer:

* small, explicit functions
* direct control flow
* narrow dependencies
* documented failure precedence
* isolated behavioral tests
* bounded security claims

Avoid abstractions whose maintenance or review cost exceeds their demonstrated value.

## Security invariant

All contributions must remain consistent with this invariant:

> Durable wrapper-managed forge API credential state is stored only in `pass`. Decrypted credential material is introduced only during an active invocation of the corresponding parent CLI and is not retained in wrapper-controlled plaintext storage after that invocation ends.

This applies only to state controlled by the wrappers. The project does not claim protection against a compromised user account, operating system, parent CLI, dependency, or privileged local process.

## Reporting security vulnerabilities

Do not open a public issue for a suspected vulnerability involving:

* credential disclosure
* unsafe temporary-file handling
* unintended persistent authentication state
* authentication bypass
* command or argument injection
* unsafe writeback behavior
* cleanup failures that expose reusable credential material

Follow the private reporting instructions in [`SECURITY.md`](SECURITY.md).
GitHub private vulnerability reporting is the preferred intake mechanism.

## Development setup

Clone the repository and inspect the current state:

```sh
git clone https://github.com/JeffreyCordova/forge-cli-pass.git
cd forge-cli-pass

git status --short
git log --oneline --decorate --max-count=10
```

The GitHub repository is canonical. GitLab mirrors the canonical `main` branch
and release tags.

Do not use real production credentials in development or tests.

Tests should use:

* a temporary `HOME`
* an isolated `PATH`
* fake `pass`, `gh`, and `glab` executables
* disposable temporary directories
* no network access
* no real forge accounts
* no production password store

Run the accepted verification interface with:

```sh
make check
```

A compatible BusyBox executable may be supplied explicitly:

```sh
make check \
    BUSYBOX=/path/to/compatible/busybox
```

The verification interface runs ShellCheck, syntax checks under Dash, Bash in
POSIX mode, and BusyBox `ash`, the complete behavioral matrix, and installation
tests.

## Making changes

### Keep changes focused

A contribution should address one coherent concern.

Separate unrelated changes such as:

* behavior changes
* refactoring
* documentation rewrites
* test infrastructure
* packaging changes
* CI changes

This makes security review and regression analysis easier.

### Add tests with behavioral changes

Changes affecting runtime behavior should include tests covering:

* the expected success path
* relevant failure paths
* cleanup behavior
* exit-status behavior
* credential confidentiality
* filesystem state
* parent CLI argument forwarding
* standard-input preservation when applicable
* persistent-state effects

A security-relevant fix should include a regression test whenever practical.

### Update documentation

Update the relevant documentation when a change affects:

* command behavior
* credential flow
* trust boundaries
* dependencies
* supported platforms
* failure semantics
* installation behavior
* security limitations
* compatibility guarantees

Do not leave the README, architecture document, tests, and implementation describing different systems.

### Record architecture decisions

Create or update an architecture decision record when a change materially affects:

* product scope
* command structure
* credential backend
* runtime language
* supported platforms
* installation or distribution
* configuration precedence
* credential-management command policy
* writeback semantics
* failure precedence
* security invariants

Decision records belong under:

```text
docs/decisions/
```

A decision record should contain:

```text
Title
Status
Context
Decision
Alternatives considered
Consequences
Security implications
Verification requirements
```

Accepted decision records should not be silently rewritten when the decision later changes. Add a superseding record and preserve the earlier rationale.

## Coding expectations

The runtime implementation language is POSIX `sh`.

Code must remain compatible with Dash, Bash in POSIX mode, and BusyBox `ash`.
Avoid shell-specific extensions and do not broaden the supported baseline
without an accepted architecture decision.

For shell source:

* quote expansions unless deliberate splitting is required
* forward user arguments using `"$@"`
* avoid `eval`
* avoid constructing shell commands as strings
* avoid predictable temporary paths
* use restrictive permissions for credential material
* disable or avoid accidental command tracing
* handle expected failures explicitly
* preserve meaningful exit statuses
* do not parse credential formats unnecessarily
* do not print sensitive values in errors
* bypass interactive aliases and functions when invoking required binaries
* document any nonstandard utility dependency

Comments should explain:

* security boundaries
* non-obvious failure behavior
* cleanup requirements
* compatibility constraints
* why a less obvious implementation was chosen

Comments should not merely restate individual commands.

## Tests

The test suite must not depend on:

* network access
* real GitHub or GitLab credentials
* the developer’s actual password store
* the developer’s normal CLI configuration
* interactive authentication
* a particular home-directory layout

Tests should make credential leakage visible by using recognizable fake values and checking that those values do not appear in unintended output or files.

### Required `gh-pass` coverage

Behavioral tests should cover at least:

* missing `pass`
* missing `gh`
* missing credential entry
* empty token
* expected token extraction
* argument forwarding
* token availability to the child process
* token absence from wrapper diagnostics
* parent exit-status propagation
* standard-input inheritance
* inherited tracing behavior
* absence of persistent wrapper-managed GitHub authentication state

### Required `glab-pass` coverage

Behavioral tests should cover at least:

* missing dependencies
* missing or empty stored configuration
* temporary-directory creation
* directory and file permissions
* `GLAB_CONFIG_DIR` scoping
* unchanged configuration
* changed configuration
* credential-state writeback
* writeback failure
* parent success and failure
* standard-input preservation
* handled signals
* cleanup behavior
* credential absence from wrapper diagnostics
* exit-status precedence
* absence of persistent authentication state in the default config location

## Commit messages

This project uses the Conventional Commits format:

```text
<type>[optional scope]: <description>
```

Common types:

| Type       | Purpose                                          |
| ---------- | ------------------------------------------------ |
| `feat`     | New user-visible behavior                        |
| `fix`      | Correction to defective behavior                 |
| `docs`     | Documentation-only change                        |
| `test`     | Test-only change                                 |
| `refactor` | Internal change without intended behavior change |
| `build`    | Installation, packaging, or build-system change  |
| `ci`       | Continuous-integration change                    |
| `chore`    | Repository maintenance not covered elsewhere     |

Suggested scopes include:

```text
gh-pass
glab-pass
docs
tests
install
ci
release
```

Examples:

```text
docs: add project context and architecture
feat(gh-pass): support configurable pass entry
fix(glab-pass): remove staged config after interrupted execution
test(glab-pass): cover failed credential writeback
build: add prefix-based installation targets
ci: test supported shell implementations
```

Use the imperative mood and keep the summary concise.

### Security-significant commits

Changes affecting credential flow, trust boundaries, permissions, cleanup, writeback, or failure precedence should include an explanatory commit body.

Example:

```text
fix(glab-pass): reject non-regular post-command state

Refuse to persist a staged GitLab configuration that is no longer a regular
file after the parent command exits. Retain the existing pass entry, report
the wrapper failure, and continue attempting runtime cleanup.

This prevents a parent-side filesystem mutation from replacing durable
credential state with an ineligible object.

Tests cover the non-regular state, absence of writeback, cleanup, and final
wrapper status.
```

The body should explain:

* what changed
* why it changed
* which security property or invariant was affected
* how the behavior was verified
* any remaining limitation

### Breaking changes

Mark a breaking change with `!` or a `BREAKING CHANGE:` footer:

```text
feat(gh-pass)!: rename the default credential entry
```

Do not label internal refactoring as a breaking change unless it changes the public interface or documented behavior.

## Pull requests

The canonical GitHub `main` branch is protected. Changes must arrive through a
pull request and pass the required `CI/Verify` status check against the current
target-branch state. Direct pushes, force pushes, and branch deletion are
restricted by repository rules.

The complete operational workflow is documented in
[`docs/maintenance.md`](docs/maintenance.md).

A pull request should include:

1. A concise description of the problem.
2. The proposed behavior.
3. Relevant security implications.
4. Tests added or updated.
5. Documentation updated.
6. Open questions or residual risks.
7. Any architecture decision involved.

For security-sensitive changes, identify:

* credential material affected
* trust boundary affected
* persistent state affected
* cleanup behavior
* failure precedence
* compatibility impact

Avoid combining formatting-only changes with security-sensitive logic unless the formatting change is necessary for the implementation.

## Review expectations

Review should consider:

* whether the problem is within project scope
* whether the implementation matches accepted architecture
* whether credential exposure is minimized
* whether failure behavior is explicit
* whether cleanup is reliable
* whether parent behavior remains compatible
* whether dependencies are justified
* whether tests exercise failure paths
* whether claims are proportionate to demonstrated behavior
* whether documentation remains consistent

A passing test suite does not replace manual review of credential-handling code.

## Dependency changes

New runtime dependencies require explicit justification.

A dependency proposal should explain:

* why the behavior cannot remain simple and local
* whether the dependency is required at runtime or only for development
* its availability on supported platforms
* its maintenance and security implications
* how it affects installation and packaging
* how its absence is detected and reported

Avoid adding a framework solely to make the repository appear more substantial.

## Documentation style

Documentation should:

* define specialized terminology on first use
* distinguish SSH Git transport from forge API authorization
* distinguish durable state from runtime material
* identify assumptions and limitations
* avoid unbounded claims
* use concrete credential-flow descriptions
* link to architecture decisions where rationale matters

Avoid phrases such as:

* “completely secure”
* “zero residue”
* “credentials never leave `pass`”
* “plaintext-free”
* “drop-in replacement” without qualification
* “protects against compromise” without naming the actor and boundary

## Licensing of contributions

The project is licensed under the Apache License 2.0.

By submitting a contribution, you agree that it may be distributed under the
same license. See [`LICENSE`](LICENSE).

## Before submitting

Before committing or opening a pull request:

```sh
git status --short
git diff --check
git diff --cached --check

make check \
    BUSYBOX=/path/to/compatible/busybox
```

Also verify that no credential material or local authentication state has been added:

```sh
git diff --cached --name-only
git ls-files |
  grep -Ei 'token|secret|oauth|config\.yml|\.env|\.pem|\.key' ||
  true
```

Treat matches as prompts for review, not automatic proof of a secret.

Do not commit:

* actual access tokens
* OAuth configuration
* password-store contents
* private keys
* real credential fixtures
* local CLI authentication files
* production host or account data that should remain private

## Questions and proposals

Use an issue or discussion for:

* feature proposals
* architecture questions
* compatibility changes
* platform-support proposals
* dependency additions
* installation-model changes

Do not use a public issue to disclose a vulnerability or real credential material.
