
# Architecture

**Status:** Draft

This document describes the current architecture of `forge-cli-pass`.

Accepted architectural properties are stated normatively. Unresolved questions are identified explicitly and must not be treated as settled implementation requirements.

## 1. Scope

`forge-cli-pass` provides two provider-specific credential lifecycle wrappers:

* `gh-pass`, wrapping GitHub CLI (`gh`)
* `glab-pass`, wrapping GitLab CLI (`glab`)

The wrappers adapt parent CLI credential handling to a `pass`-backed durable storage policy.

The project does not mediate Git transport. SSH keys, Git remote configuration, host trust, and repository transport remain outside its scope.

## 2. Architectural identity

```text
Repository:  forge-cli-pass

Commands:    gh-pass
             glab-pass

Backend:     pass

Parents:     gh
             glab
```

The wrappers remain separate because their parent CLIs expose materially different credential-consumption and credential-mutation models.

## 3. Architectural drivers

The architecture is shaped by the following requirements:

1. Durable wrapper-managed credentials must remain encrypted in `pass`.
2. Git transport must continue to use its independently configured SSH authentication.
3. Parent CLI behavior should be preserved rather than reimplemented.
4. Wrapper-managed authentication state must not remain in the parent CLI’s default config location.
5. Decrypted material must exist only for an active invocation.
6. GitLab OAuth refresh state must be preserved when legitimately changed.
7. Cleanup and failure behavior must be explicit and testable.
8. The implementation must remain proportionate and directly auditable.
9. Dependencies and portability limits must be declared honestly.
10. Security claims must be bounded to wrapper-controlled state.

## 4. System context

```text
                       ┌─────────────────────┐
                       │        pass         │
                       │ GPG-encrypted state │
                       └─────────┬───────────┘
                                 │
                    decrypt only for invocation
                                 │
                 ┌───────────────┴────────────────┐
                 │                                │
        ┌────────▼────────┐              ┌────────▼─────────┐
        │     gh-pass     │              │    glab-pass     │
        │ token injection│              │ config staging   │
        └────────┬────────┘              └────────┬─────────┘
                 │                                │
             GH_TOKEN                    GLAB_CONFIG_DIR
                 │                                │
        ┌────────▼────────┐              ┌────────▼─────────┐
        │       gh        │              │       glab       │
        └────────┬────────┘              └────────┬─────────┘
                 │                                │
        ┌────────▼────────┐              ┌────────▼─────────┐
        │   GitHub API    │              │   GitLab API     │
        └─────────────────┘              └──────────────────┘
```

Git transport follows a separate path:

```text
Git
└── SSH
    ├── GitHub
    └── GitLab
```

The wrappers do not provide, modify, or validate this SSH configuration.

## 5. Components

### 5.1 `gh-pass`

`gh-pass` is a command-compatible wrapper around `gh` for ordinary authenticated operations.

Responsibilities:

* locate the configured GitHub credential entry in `pass`
* retrieve the credential
* extract the expected token value
* reject missing or empty credential data
* provide the token to the child `gh` process through `GH_TOKEN`
* forward arguments without reinterpretation
* preserve the parent command’s relevant exit behavior
* avoid writing wrapper-managed GitHub authentication state to a persistent CLI config location

Non-responsibilities:

* token creation
* token scope selection
* token validation beyond obvious local checks
* token rotation
* GitHub authorization-policy management
* Git transport authentication
* interpretation of normal `gh` subcommands

### 5.2 `glab-pass`

`glab-pass` is a command-compatible wrapper around `glab` for ordinary authenticated operations.

Responsibilities:

* locate the configured GitLab credential-state entry in `pass`
* retrieve the stored GitLab CLI configuration
* create a private temporary runtime directory
* restore the configuration into that directory
* run `glab` with `GLAB_CONFIG_DIR` scoped to that runtime directory
* detect relevant configuration changes
* write changed state back to `pass` according to the accepted writeback policy
* remove wrapper-controlled plaintext runtime configuration
* preserve the parent command’s relevant exit behavior
* avoid retaining wrapper-managed GitLab authentication state in the default CLI configuration location

Non-responsibilities:

* parsing or independently implementing the GitLab OAuth protocol
* issuing or rotating OAuth credentials
* validating GitLab configuration semantics
* managing Git transport
* interpreting normal `glab` subcommands

### 5.3 `pass`

`pass` is the authoritative durable store for wrapper-managed forge API credential state.

The architecture does not provide alternate credential backends or automatic fallback to:

* desktop keyrings
* operating-system credential services
* cloud secret managers
* plaintext config files
* environment files

Supporting multiple backends would materially change the product boundary and requires a separate architecture decision.

### 5.4 Parent CLIs

`gh` and `glab` remain responsible for:

* API request construction
* command parsing
* command output
* platform-specific API behavior
* server communication
* normal command exit conditions
* extension behavior
* authentication-state mutation performed internally by the parent CLI

The wrappers trust the installed parent CLI binaries within the documented threat model.

## 6. State model

### 6.1 Durable state

Durable wrapper-managed credential state is state intended to survive between invocations.

It belongs only in `pass`.

Examples:

* GitHub API token
* GitLab CLI OAuth configuration, including refresh-capable state

### 6.2 Runtime state

Runtime credential material is the decrypted form introduced for one invocation.

Examples:

* a GitHub token held in wrapper memory and provided through `GH_TOKEN`
* a temporary GitLab `config.yml`
* temporary content fingerprints or metadata used for change detection

### 6.3 Parent-managed non-credential state

The project may allow parent CLI preferences that are not part of wrapper-managed authentication state, but the boundary must be explicitly defined.

The architecture must not assume that every parent CLI configuration value is sensitive or that every default config file is prohibited.

The governing concern is persistent wrapper-managed authentication state.

### 6.4 External state

The following state is outside the wrapper-controlled lifecycle:

* SSH private keys
* SSH agents
* Git credential helpers
* Git remote URLs
* `known_hosts`
* GPG keys
* the password-store repository
* kernel memory
* swap
* filesystem journals
* terminal output
* logs created by other components
* state copied internally by a trusted parent CLI

## 7. GitHub credential flow

```text
┌──────────────────────────────┐
│ pass entry: GitHub token     │
│ durable and GPG-encrypted    │
└──────────────┬───────────────┘
               │ decrypt
               ▼
┌──────────────────────────────┐
│ gh-pass                      │
│ validate non-empty token     │
└──────────────┬───────────────┘
               │ GH_TOKEN
               ▼
┌──────────────────────────────┐
│ gh process                   │
│ receives original arguments  │
└──────────────┬───────────────┘
               │
               ▼
        GitHub API operation
```

Required properties:

1. The token is obtained from `pass` only when `gh-pass` is invoked.
2. The token is not placed in a persistent wrapper-managed config file.
3. The token is provided only to the intended parent process and its descendants.
4. Wrapper diagnostics must not print the token.
5. Arguments must be forwarded without unintended expansion or reinterpretation.
6. The wrapper must not claim that the token is absent from process memory or all operating-system observation surfaces.
7. Normal GitHub CLI configuration outside the wrapper-managed credential boundary must not be modified unnecessarily.

## 8. GitLab credential flow

```text
┌──────────────────────────────────┐
│ pass entry: GitLab CLI config    │
│ durable and GPG-encrypted        │
└────────────────┬─────────────────┘
                 │ decrypt
                 ▼
┌──────────────────────────────────┐
│ private temporary directory      │
│ temporary config.yml             │
└────────────────┬─────────────────┘
                 │ GLAB_CONFIG_DIR
                 ▼
┌──────────────────────────────────┐
│ glab process                     │
│ may read and mutate config       │
└────────────────┬─────────────────┘
                 │
                 ▼
        compare runtime state
          │                 │
     unchanged            changed
          │                 │
          │                 ▼
          │        write updated state
          │             to pass
          │                 │
          └────────┬────────┘
                   ▼
       remove temporary directory
```

Required properties:

1. The stored configuration is restored only for an active invocation.
2. The temporary directory must be created without a predictable-name race.
3. The runtime directory and credential file must have restrictive permissions.
4. `glab` must be directed to the temporary configuration rather than the default configuration location.
5. Changed credential state must be written back only through the defined writeback path.
6. Unchanged state should not cause unnecessary writeback.
7. Cleanup must be attempted after success, parent-command failure, and handled termination signals.
8. Cleanup failure must be reported without concealing the parent command’s outcome.
9. The project must not claim forensic erasure after file deletion.
10. The exact writeback policy after a nonzero `glab` exit remains an open architecture decision.

## 9. Trust boundaries

### 9.1 Trusted components

The current model assumes the following are trustworthy enough for local operation:

* the local user account
* the selected shell runtime
* `pass`
* GPG and the relevant private key
* the local password store
* `gh`
* `glab`
* required filesystem and utility commands
* the operating-system kernel
* the repository checkout or installed release
* the environment from which the wrapper is invoked

Trust does not mean these components are proven secure. It means compromise of these components is outside the protection boundary of the project.

### 9.2 Untrusted or uncontrolled inputs

The wrappers must treat the following as potentially invalid:

* command-line arguments
* unset or malformed environment variables
* missing credential entries
* empty credential material
* malformed stored GitLab configuration
* unavailable dependencies
* unsuitable runtime directories
* conflicting filesystem paths
* failed writes to `pass`
* parent CLI failures
* unexpected parent CLI mutation of runtime configuration

### 9.3 External services

GitHub and GitLab are outside the local enforcement boundary.

The project does not control:

* server-side credential handling
* API authorization policy
* account compromise
* remote logging
* token revocation behavior
* server availability
* API compatibility

## 10. Security objectives and invariants

### 10.1 Primary objective

> Minimize the duration, scope, and persistence of decrypted forge API credential material under wrapper control.

### 10.2 Durable-state invariant

> Durable wrapper-managed forge API credential state is stored only in `pass`.

### 10.3 Runtime-state invariant

> Decrypted wrapper-managed credential material is introduced only during an active invocation of the corresponding parent CLI.

### 10.4 Cleanup invariant

> Wrapper-controlled plaintext credential files are not intentionally retained after the invocation ends.

### 10.5 Parent-interface invariant

> For supported ordinary operations, arguments are passed to the parent CLI without semantic reinterpretation.

### 10.6 Non-interference invariant

> The wrappers do not modify Git transport authentication or unrelated parent CLI state as part of normal credential delivery.

## 11. Compatibility contract

The wrappers are command-compatible with their parent CLIs for ordinary authenticated operations.

Examples include:

```sh
gh-pass repo view
gh-pass pr list
gh-pass api user

glab-pass repo view
glab-pass mr list
glab-pass pipeline list
```

Command compatibility means:

* the wrapper command is substituted for the parent command
* remaining arguments retain their order and boundaries
* the parent CLI performs command parsing
* the parent CLI controls ordinary output
* the wrapper does not reimplement parent subcommands

The initial compatibility contract does not automatically include credential-management operations such as:

```sh
gh-pass auth login
gh-pass auth logout
gh-pass auth token

glab-pass auth login
glab-pass auth logout
```

These operations may expose, replace, invalidate, or mutate stored credential state. Their support policy must be defined explicitly.

## 12. Failure behavior

The wrappers should follow these failure principles:

1. Reject missing dependencies before handling credential material where practical.
2. Reject missing or empty credentials.
3. Do not silently fall back to a different credential store.
4. Do not silently use persistent parent CLI authentication state.
5. Do not print credential material in diagnostics.
6. Report cleanup and writeback failures clearly.
7. Preserve the parent CLI exit status unless a more serious wrapper failure prevents correct completion.
8. Avoid implicit behavior dependent on an interactive shell configuration.
9. Avoid broad error-handling constructs whose behavior is difficult to reason about.
10. Make partial persistent mutation visible.

The exact precedence between parent-command failure, writeback failure, and cleanup failure must be defined and tested.

## 13. Configuration model

The prototype uses fixed `pass` entry names.

The public configuration model remains unresolved.

Candidate approaches include:

* fixed documented conventions
* environment-variable overrides with documented defaults
* command-line options
* a configuration file
* a combination with explicit precedence

Any configuration mechanism must define:

* accepted values
* precedence
* validation
* whether configuration values may contain credential material
* file-permission expectations
* diagnostic behavior
* interaction with parent CLI environment variables

A configuration file must not be introduced merely for extensibility. Its complexity must be justified by concrete operator requirements.

## 14. Runtime language and platform support

The runtime language and support contract remain unresolved.

The current architectural requirements are:

* the language must support safe argument forwarding
* cleanup and signal behavior must be testable
* dependency lookup must be deterministic
* the implementation must not depend on interactive shell configuration
* static and behavioral verification should be available
* the supported platform claim must distinguish shell-language portability from external utility portability

Candidate decisions include:

* zsh on Linux
* Bash on Linux
* POSIX shell language with Linux support
* broader cross-Unix POSIX shell support

No portability claim should be made until the selected shell and external dependency matrix are tested.

## 15. Change detection and writeback

`glab-pass` must determine whether the staged GitLab configuration changed.

The architectural requirement is:

> Avoid unnecessary writes to `pass` while reliably persisting legitimate mutable authentication state.

Possible mechanisms include:

* content fingerprint comparison
* exact byte comparison against a second temporary copy
* another explicit mutation signal, if supported by the parent CLI

The mechanism must be evaluated for:

* correctness
* dependency cost
* transient plaintext exposure
* portability
* auditability
* behavior under parent CLI failure

The current use of SHA-256 is an implementation mechanism for change detection, not an integrity or authentication guarantee.

## 16. Installation and distribution boundary

The public installation model remains unresolved.

Candidate models include:

* copy-based installation through a `Makefile`
* package-manager installation
* release archives
* development-only symlink installation
* a dedicated installer invoked through a conventional task interface

The default public installation model should not make installed behavior change implicitly when a development checkout changes, unless that behavior is explicitly selected by the operator.

The installation design must define:

* installation prefix
* uninstallation behavior
* executable permissions
* conflict handling
* development workflow
* release-artifact relationship
* packaging compatibility
* whether man pages or completion files are installed

## 17. Observability and diagnostics

Diagnostics should:

* identify the wrapper producing the message
* describe actionable local failures
* avoid printing credential values
* distinguish parent CLI failures from wrapper failures
* report cleanup or writeback problems
* avoid claiming cleanup guarantees beyond wrapper control

Normal parent CLI output should pass through without unnecessary wrapper decoration.

A future diagnostic command may be considered, but no unified command or shared runtime framework should be introduced solely to provide one.

## 18. Verification requirements

The implementation must be verified through isolated tests that do not use real credentials or network access.

### `gh-pass`

Tests must cover:

* missing dependencies
* missing credential entry
* empty credential
* expected token extraction
* argument forwarding
* environment scoping
* absence of token material from wrapper diagnostics
* parent exit-status behavior
* interaction with tracing or inherited shell state
* absence of persistent wrapper-managed authentication state

### `glab-pass`

Tests must cover:

* missing dependencies
* missing or empty stored configuration
* secure temporary-directory creation
* runtime directory permissions
* runtime file permissions
* `GLAB_CONFIG_DIR` scoping
* unchanged configuration
* changed configuration
* failed writeback
* parent command success and failure
* signal handling
* cleanup behavior
* output confidentiality
* exit-status precedence
* absence of persistent default-location authentication state

### Cross-cutting verification

Tests must use:

* a temporary `HOME`
* an isolated `PATH`
* fake parent CLI binaries
* a fake `pass`
* no production password store
* no network
* no real forge credentials

Static analysis and shell matrices must match the accepted runtime-language decision.

## 19. Known limitations

The architecture does not prevent:

* runtime process inspection by privileged actors
* credentials existing in process memory
* operating-system swap
* filesystem or storage-layer forensic recovery
* malicious behavior by trusted dependencies
* parent CLI extensions from receiving credentials
* parent CLIs from changing their credential interfaces
* user commands that deliberately print credential material
* misuse of valid credentials by an authorized local user
* repository compromise affecting an installed development symlink

Temporary deletion reduces ordinary persistence. It is not secure erasure.

## 20. Open architecture decisions

| Decision                              | Status   |
| ------------------------------------- | -------- |
| Provider-specific command model       | Accepted |
| Public naming and terminology         | Accepted |
| `pass` as authoritative durable store | Accepted |
| Separation from SSH Git transport     | Accepted |
| GitHub token-injection model          | Accepted |
| GitLab temporary staging model        | Accepted |
| Runtime shell language                | Open     |
| Initial supported platforms           | Open     |
| Public installation model             | Open     |
| Credential-entry configuration model  | Open     |
| Credential-management command policy  | Open     |
| GitLab writeback after parent failure | Open     |
| Change-detection mechanism            | Open     |
| Exit-status precedence                | Open     |
| Release and packaging model           | Open     |

## 21. Decision records

Material architecture decisions should be recorded under:

```text
docs/decisions/
```

Initial records should cover:

1. provider-specific command model
2. public naming and terminology
3. `pass` as the authoritative durable credential store
4. runtime language and platform support
5. installation and distribution model
6. credential-management command compatibility
7. GitLab mutation and writeback policy

Accepted decisions should be integrated into this document. Superseded decisions should remain available as historical records rather than being silently rewritten.

## 22. Conformance

An implementation conforms to this architecture only when:

* accepted invariants are reflected in code
* behavioral tests exercise those invariants
* documentation does not claim unsupported guarantees
* unresolved decisions are not presented as settled features
* credential lifecycle behavior matches the documented provider-specific flow
* public installation and release artifacts match the accepted distribution model
