
# Project Context

## Project identity

**Repository:** `forge-cli-pass`

**Commands:**

* `gh-pass`
* `glab-pass`

**Credential backend:** `pass`

**Wrapped commands:**

* GitHub CLI, `gh`
* GitLab CLI, `glab`

`forge-cli-pass` provides pass-backed credential lifecycle wrappers for Git hosting and collaboration platform command-line clients.

The wrappers preserve the ordinary command interface of their parent CLIs while changing how wrapper-managed API credentials are stored and introduced at runtime.

## Origin

The project originated while configuring the GitHub and GitLab command-line clients in an Arch Linux environment running under Windows Subsystem for Linux.

Git already used SSH keys for repository transport, including:

* clone
* fetch
* pull
* push

The forge CLIs still required separate API credentials for operations such as:

* repository creation
* pull and merge requests
* issues
* releases
* pipelines
* account and project queries

The GitHub CLI reported:

> Authentication credentials saved in plain text

The environment intentionally did not use a graphical desktop keyring or credential manager. Persisting reusable API credentials in plaintext CLI configuration files conflicted with the existing command-line credential-management model, which used `pass` and GPG-encrypted storage.

The original problem was therefore not Git or SSH authentication. It was the lifecycle of API credentials required by `gh` and `glab`.

## Problem statement

GitHub CLI and GitLab CLI require API credentials independently of SSH-based Git transport.

In command-line-only environments without a desktop keyring, reusable authentication state may be retained in plaintext CLI configuration files. This creates persistent credential residue outside the operator’s intended credential store.

The project addresses the need to preserve normal forge CLI functionality while enforcing the following local credential-handling policy:

* SSH keys remain responsible for Git transport.
* OAuth or access tokens authorize forge API operations.
* Durable wrapper-managed credentials remain encrypted in `pass`.
* Decrypted credential material is introduced only while the relevant command is running.
* Wrapper-managed authentication state is not retained in the parent CLI’s default configuration location.
* Browser-based OAuth remains usable where the underlying CLI permits it.
* The upstream CLIs remain responsible for their own command semantics and API behavior.

## Intended operating model

```text
Git transport
└── SSH keys
    ├── clone
    ├── fetch
    ├── pull
    └── push

Forge API operations
└── OAuth or access-token credentials
    ├── repository management
    ├── pull and merge requests
    ├── issues
    ├── pipelines
    └── releases

Durable wrapper-managed credential state
└── pass
    └── GPG-encrypted entries

Runtime credential delivery
├── gh-pass
│   └── per-process token injection
└── glab-pass
    └── temporary mutable credential-state staging
```

## Why there are two commands

The project intentionally provides separate provider-specific commands.

`gh` and `glab` consume and maintain credential state differently. A unified command would conceal that distinction and introduce a shared abstraction that is not required by the underlying behavior.

### `gh-pass`

GitHub CLI can consume an access token directly through `GH_TOKEN`.

`gh-pass` therefore:

1. retrieves the configured GitHub token from `pass`
2. makes it available to the child `gh` process
3. forwards the user’s arguments to `gh`
4. does not create persistent wrapper-managed GitHub CLI authentication state

This is a per-process credential-injection model.

### `glab-pass`

GitLab OAuth operation requires mutable CLI configuration containing more than a single access token. The configuration may change during execution, including through token refresh.

`glab-pass` therefore:

1. retrieves the stored GitLab CLI configuration from `pass`
2. restores it into a private temporary runtime directory
3. runs `glab` against that temporary configuration
4. detects whether the configuration changed
5. writes changed state back to `pass`
6. removes the temporary plaintext configuration

This is a temporary credential-staging and conditional-writeback model.

## Intended users

The project is intended for operators who deliberately prefer a command-line credential workflow and who use `pass` as an authoritative durable credential store.

Relevant environments may include:

* WSL distributions
* headless Linux systems
* minimal Linux installations
* remote administration environments
* systems without a desktop keyring
* systems where a desktop keyring is intentionally excluded
* workflows standardized on GPG and `pass`

The project does not assert that `pass` is categorically more secure than every operating-system keyring. It provides a deterministic alternative for environments where `pass` is the chosen trust and storage model.

## Goals

The project aims to:

1. Keep durable wrapper-managed forge API credentials encrypted in `pass`.
2. Reduce persistent plaintext credential residue in default CLI configuration locations.
3. Limit decrypted credential material to the duration and scope of the relevant CLI invocation.
4. Preserve the ordinary operational interfaces of `gh` and `glab`.
5. Keep Git transport authentication separate and unchanged.
6. Support mutable GitLab OAuth state without leaving its runtime configuration permanently on disk.
7. Make credential flows and trust assumptions explicit and auditable.
8. Fail safely when required dependencies, credentials, or runtime conditions are missing.
9. Remain small enough for direct code review.
10. Provide tests that enforce documented credential-lifecycle properties.

## Non-goals

The project is not intended to:

* implement an authentication protocol
* replace GitHub CLI or GitLab CLI
* replace `pass`
* issue or rotate access tokens
* manage SSH keys
* manage Git credential helpers
* manage repository permissions
* manage branch protection
* manage signing keys
* provide a graphical credential interface
* provide process isolation or sandboxing
* protect credentials on a compromised host
* guarantee forensic erasure of runtime material
* abstract over multiple credential backends
* become a general-purpose secrets manager
* conceal or reinterpret parent CLI command semantics

## Security objective

The primary security objective is:

> Minimize the duration, scope, and persistence of decrypted forge API credential material under wrapper control.

The project is concerned primarily with unnecessary persistent credential residue, including:

* plaintext tokens in default CLI configuration directories
* authentication files entering dotfiles repositories
* reusable credentials being copied into routine backups
* credentials embedded in shell configuration
* credentials placed in long-lived environment variables
* persistent GitLab OAuth configuration remaining after each command
* confusion between non-secret CLI preferences and authentication state

## Security invariant

> Durable wrapper-managed forge API credential state is stored only in `pass`. Decrypted credential material is introduced only during an active invocation of the corresponding parent CLI and is not retained in wrapper-controlled plaintext storage after that invocation ends.

This invariant applies only to state controlled by the wrappers.

It does not guarantee that credential material cannot be observed or retained by:

* the operating system
* process memory
* swap
* filesystem journaling
* privileged local processes
* a compromised dependency
* the parent CLI
* extensions executed by the parent CLI
* terminal, logging, debugging, backup, or forensic systems

## Design principles

### Explicit credential boundaries

The durable source of wrapper-managed credential state must be clear and deterministic.

### Provider-specific adaptation

Different parent CLI credential models should remain explicit rather than being hidden behind a premature shared abstraction.

### Minimal reimplementation

The wrappers should adapt credential delivery while leaving command behavior, API operations, and output semantics to `gh` and `glab`.

### Limited persistence

Decrypted credential material should not become ordinary durable CLI configuration.

### Visible mutation

Persistent GitLab credential-state changes should occur only through an explicit, testable writeback path.

### Non-destructive behavior

The project should not overwrite unrelated files, configuration, or credentials without an explicit operator decision.

### Auditable implementation

The code and its dependency surface should remain proportionate to the problem.

### Honest security claims

Documentation should describe bounded properties and residual risks rather than use unqualified claims such as “secure,” “zero residue,” or “plaintext-free.”

## Terminology

### Forge

A Git hosting and collaboration platform, such as GitHub or GitLab.

### Parent CLI

The upstream command-line utility invoked by a wrapper:

* `gh` for `gh-pass`
* `glab` for `glab-pass`

### Forge API credential

A token or OAuth credential used by a parent CLI to authorize API operations.

### Credential material

Sensitive data that enables authenticated or authorized access.

### Authentication state

Credential material and associated configuration required for a parent CLI to remain authenticated.

### Durable credential state

Credential material intended to survive between command invocations.

### Runtime credential material

A decrypted representation introduced for one active command invocation.

### Credential injection

Providing credential material directly to a process without creating persistent CLI authentication configuration.

### Credential staging

Materializing credential state in a controlled temporary location for a process that requires file-based or mutable configuration.

### Writeback

Persisting changed runtime credential state back into `pass`.

### Persistent credential residue

Reusable credential material left after an invocation in an unintended durable location.

### Wrapper-managed credential state

Credential state introduced, persisted, or removed by this project.

## Compatibility goal

The wrappers are intended to be:

> Command-compatible wrappers for ordinary authenticated operations.

Arguments for ordinary operations are forwarded to the corresponding parent CLI without reinterpretation.

Credential-management commands, including login, logout, and credential-display operations, require a separately defined compatibility policy and are not implicitly covered by this statement.

## Project evolution

The project began as two scripts inside a personal dotfiles repository:

* `ghp`
* `glabp`

As the credential-handling behavior matured, the scripts became a distinct tool with its own:

* problem definition
* security objective
* terminology
* architecture
* tests
* installation boundary
* documentation
* release lifecycle

The public project adopts the names:

* repository: `forge-cli-pass`
* GitHub wrapper: `gh-pass`
* GitLab wrapper: `glab-pass`

The earlier command names may remain private shell aliases but are not part of the intended public interface.

## Current maturity

The project is undergoing an architecture and assurance pass before its first public release.

The following decisions are accepted:

* separate provider-specific wrapper commands
* `pass` as the authoritative durable credential store
* SSH remaining outside the wrappers’ responsibility
* `gh-pass` using token injection
* `glab-pass` using temporary credential staging and conditional writeback
* the approved project identity and terminology model
* command compatibility for ordinary authenticated operations

The following areas remain under design:

* runtime shell language
* supported platform contract
* installation and distribution model
* configuration and credential-entry overrides
* compatibility policy for credential-management commands
* GitLab writeback behavior after unsuccessful parent commands
* exact change-detection mechanism
* release and packaging model

These decisions are documented separately and must be resolved before the first stable release.
