# ADR 0008: Restrict Credential-Management Commands

**Status:** Accepted

## Context

`gh-pass` and `glab-pass` are command-compatible wrappers for ordinary
authenticated operations performed by GitHub CLI and GitLab CLI.

Their purpose is to preserve the parent CLIs' operational interfaces while
enforcing a different credential lifecycle:

- durable wrapper-managed credential state remains in `pass`
- runtime credential material is introduced only for an active invocation
- wrapper-managed authentication state is not retained in the parent CLI's
  default configuration location

Most parent CLI commands are compatible with that model.

Credential-management commands are different. Operations under the parent
CLIs' `auth` namespaces may:

- create durable parent-managed credentials
- replace or refresh authentication state
- remove stored credentials
- select among stored accounts
- configure Git or Docker credential helpers
- print credential material
- introduce authentication mechanisms outside the project's scope

Blindly forwarding every `auth` command could violate the project's durable-state
invariant, recreate the plaintext-storage condition that motivated the project,
or expose credential material through normal command output.

The wrappers therefore require an explicit compatibility policy for
credential-management commands.

## Decision

`gh-pass` and `glab-pass` will support:

- ordinary authenticated parent CLI operations
- parent CLI help and command-discovery operations
- authentication-status checks that do not intentionally disclose credential
  material

They will reject parent CLI operations that create, replace, mutate, remove,
select, disclose, or repurpose authentication state.

Within the `auth` command namespace, the wrappers use an explicit allowlist.

Unknown or newly introduced `auth` subcommands are rejected by default until
their behavior is reviewed and deliberately accepted.

## Compatibility boundary

The wrappers are described as:

> Command-compatible wrappers for ordinary authenticated operations.

This compatibility statement does not imply unrestricted compatibility with
credential-management commands.

For supported ordinary commands, the wrappers continue to:

- preserve argument order and boundaries
- delegate command parsing to the parent CLI
- preserve normal parent output
- preserve the parent status when wrapper obligations succeed
- avoid reimplementing parent command behavior

Within the `auth` namespace, the wrappers intentionally classify and restrict
commands to preserve the project's credential model.

## Allowed authentication operations

### Authentication status

The following command forms are supported:

```sh
gh-pass auth status
glab-pass auth status
```

Supported status options may include parent CLI options that:

- select a hostname
- select an account or inspect multiple configured hosts
- control non-sensitive output formatting
- produce machine-readable status output
- request help

The wrappers must reject any status option that intentionally displays
credential material.

### Help and command discovery

Help-only forms are supported, including:

```sh
gh-pass auth
gh-pass auth --help
gh-pass auth -h
gh-pass auth status --help
gh-pass auth status -h

glab-pass auth
glab-pass auth --help
glab-pass auth -h
glab-pass auth status --help
glab-pass auth status -h
```

The parent CLI remains responsible for rendering help output.

Help operations must not mutate durable wrapper-managed state.

## Prohibited credential-disclosure options

Authentication-status commands must reject options that request token display.

This includes supported short and long forms such as:

```text
--show-token
-t
```

The restriction applies wherever the parent CLI accepts the option within the
supported `auth status` invocation.

Examples that must be rejected:

```sh
gh-pass auth status --show-token
gh-pass auth status -t

glab-pass auth status --show-token
glab-pass auth status -t
```

The wrappers must reject the operation before invoking the parent CLI.

## Rejected GitHub authentication operations

`gh-pass` will reject credential-management operations including:

```text
auth login
auth logout
auth refresh
auth setup-git
auth switch
auth token
```

### `auth login`

Rejected because it may create durable authentication state through the parent
CLI's native credential store, keyring integration, or configuration files.

Initial credential creation and replacement must use the project's documented
bootstrap procedure.

### `auth logout`

Rejected because the command operates on authentication state managed by the
parent CLI rather than directly expressing the project's `pass` lifecycle.

It may also create ambiguity between:

- removing local parent-managed state
- deleting the credential from `pass`
- revoking the server-side token

The wrapper will not assign new semantics to the parent command.

### `auth refresh`

Rejected because it changes authentication scopes or stored credential state
through the parent CLI's native lifecycle.

The project must not silently create or depend on a second durable credential
store.

### `auth setup-git`

Rejected because it configures Git credential-helper behavior.

Git transport authentication and Git credential-helper configuration are
outside the project's scope.

### `auth switch`

Rejected because it selects among parent-managed stored accounts.

The initial project model uses explicitly configured `pass` entries rather than
the parent CLI's persistent multi-account store.

### `auth token`

Rejected because it intentionally prints credential material.

Operators who deliberately need to inspect a credential must use an explicit
credential-store operation outside the wrapper.

## Rejected GitLab authentication operations

`glab-pass` will reject credential-management operations including:

```text
auth login
auth logout
auth configure-docker
auth docker-helper
auth dpop-gen
```

### `auth login`

Rejected because it bootstraps authentication state through parent-managed
configuration or keyring behavior.

Initial authentication and credential replacement must use the project's
documented isolated bootstrap procedure.

### `auth logout`

Rejected because it may remove the staged GitLab authentication payload.

Under the normal writeback model, forwarding this command could cause the
wrapper to overwrite the durable `pass` entry with logged-out, missing, or
otherwise invalid state.

Logout, credential deletion, and server-side revocation require explicit
maintenance procedures with clearly defined semantics.

### `auth configure-docker`

Rejected because it modifies Docker credential-helper configuration.

Docker authentication is outside the project's forge API credential lifecycle.

### `auth docker-helper`

Rejected because it exposes a separate credential-helper interface and lifecycle
outside ordinary `glab` operations.

### `auth dpop-gen`

Rejected because it introduces a distinct key-bound authentication mechanism
outside the accepted project scope and credential model.

## Unknown authentication subcommands

Any unrecognized `auth` subcommand is rejected.

The wrappers must not assume that a future upstream `auth` subcommand is safe
merely because the current implementation does not recognize it.

The default rule is:

> An `auth` operation is prohibited unless this ADR or a superseding decision
> explicitly permits it.

A newly introduced parent CLI command must be evaluated for:

- durable-state effects
- credential disclosure
- credential replacement
- default config-file behavior
- keyring behavior
- account-selection behavior
- credential-helper changes
- interaction with `pass`
- compatibility with wrapper writeback and cleanup semantics

Support requires updated documentation and tests.

## Bootstrap and credential maintenance

The wrappers are not responsible for initial credential creation.

The project will provide separate documented procedures for:

- initial GitHub token setup
- initial GitLab OAuth setup
- credential replacement
- credential recovery
- credential deletion
- server-side token revocation
- scope changes
- reauthentication after unusable refresh state

Bootstrap procedures must preserve the project's credential model.

A typical bootstrap process may:

1. create a private temporary configuration location
2. invoke the unwrapped parent CLI deliberately
3. complete browser-based or token-based authentication
4. import the resulting credential material into `pass`
5. remove the temporary plaintext state
6. verify the imported state through the corresponding wrapper

The exact bootstrap procedures are operational documentation, not runtime
wrapper behavior.

The wrappers must not silently invoke an unwrapped login flow on the operator's
behalf.

## Parent commands remain available

This policy is a wrapper guardrail, not an operating-system security boundary.

An operator can still deliberately invoke:

```sh
gh
glab
```

directly.

The project does not attempt to prevent use of the parent CLIs outside the
wrappers.

It ensures only that invoking `gh-pass` or `glab-pass` does not accidentally
perform an operation outside the accepted credential lifecycle.

## Parsing boundary

The wrappers will implement only the minimum command inspection required to
enforce this policy.

They will not reproduce the complete parent CLI parser.

The implementation must be able to:

- identify entry into the `auth` namespace
- identify the immediate `auth` subcommand
- allow supported help forms
- allow supported `auth status` forms
- detect prohibited token-display options
- reject prohibited and unknown `auth` subcommands
- preserve all ordinary non-`auth` arguments exactly

The parser must not:

- evaluate user input
- reconstruct a command as a string
- use `eval`
- reinterpret ordinary parent subcommands
- normalize or reorder forwarded arguments
- inspect credential values
- infer parent CLI semantics beyond the documented allowlist

## Global options and argument placement

Parent CLIs may permit global options before a command name.

The implementation must define and test the invocation forms it supports.

At minimum, it must correctly handle the conventional forms:

```sh
gh-pass auth status
glab-pass auth status
```

Support for global options preceding `auth`, for example:

```sh
gh-pass --hostname github.com auth status
```

must not be assumed unless verified against the parent CLI and covered by tests.

The initial implementation may adopt one of these bounded approaches:

1. recognize documented global options before locating the `auth` namespace
2. conservatively reject ambiguous authentication-management invocations
3. document that compatibility enforcement applies to conventional command
   placement

The selected parsing behavior must be explicit in code, tests, and user
documentation.

The wrapper must never forward an ambiguous `auth` invocation merely because
its parser failed to recognize the command structure.

## Rejection behavior

A prohibited operation is a wrapper lifecycle failure.

The wrapper must:

- reject the command before invoking the parent CLI
- return status `1`
- write an actionable diagnostic to standard error
- identify the rejected operation
- avoid printing credential material
- direct the operator to the relevant bootstrap or maintenance documentation

Example:

```text
gh-pass: unsupported credential-management command: auth token
gh-pass: credential disclosure is outside the wrapper compatibility contract
```

Example:

```text
glab-pass: unsupported credential-management command: auth login
glab-pass: use the documented isolated bootstrap procedure to create or replace the pass entry
```

The wrapper should not automatically suggest a direct parent login command
without the surrounding isolation procedure, because doing so could recreate
the original persistent plaintext state.

## Diagnostic requirements

Diagnostics must distinguish among:

- prohibited credential creation
- prohibited credential mutation
- prohibited credential deletion
- prohibited credential disclosure
- unsupported credential-helper configuration
- unknown future authentication commands
- prohibited token-display options

Diagnostics must not include:

- token values
- OAuth configuration contents
- decrypted pass-entry data
- reconstructed commands containing sensitive arguments
- speculative claims about parent CLI state

## Alternatives considered

### Forward every parent CLI command

Rejected because credential-management commands can violate the project's
durable-state and disclosure boundaries.

### Block the entire `auth` namespace

Rejected because non-disclosing status checks are operationally useful and
compatible with the project model.

Help output is also useful for discovery and does not inherently mutate
credential state.

### Permit login and logout with wrapper-defined semantics

Rejected because this would require the wrappers to reinterpret parent commands
and own additional lifecycle behaviors such as:

- bootstrap
- credential replacement
- revocation
- deletion
- account switching
- state migration

Those responsibilities should remain explicit operational procedures unless a
future architecture decision justifies expanding the runtime interface.

### Permit token-display commands with warnings

Rejected because intentionally printing credential material conflicts with the
wrapper's default credential-exposure posture.

Operators can use `pass` directly when disclosure is deliberate.

### Allow unknown future `auth` commands

Rejected because a new upstream command could introduce unreviewed mutation,
disclosure, or persistence behavior.

### Implement a complete parent CLI argument parser

Rejected because it would:

- duplicate upstream parsing logic
- increase maintenance cost
- create version-coupling
- expand the wrapper's semantic responsibilities
- undermine direct auditability

Only the narrow policy-enforcement boundary should be parsed.

## Consequences

### Positive

- The compatibility boundary becomes explicit.
- Status checks remain available.
- Token-display commands are blocked.
- Parent-native login cannot silently recreate persistent credential state.
- Git and Docker credential-helper configuration remains outside scope.
- Future upstream authentication commands fail closed pending review.
- The wrappers remain focused on ordinary authenticated operations.
- Credential bootstrap remains deliberate and documented.

### Negative

- The wrappers are not unconditional replacements for every parent CLI command.
- Some users must invoke documented maintenance procedures outside the wrapper.
- Narrow command classification adds parsing and testing requirements.
- Parent CLI changes may require updates to the allowlist.
- Global option placement may create parsing complexity.
- Operators familiar with native `auth login` or `auth logout` must learn the
  project-specific lifecycle procedures.

## Security implications

This decision prevents the wrappers from intentionally:

- creating parent-managed durable credential state
- deleting durable state through ambiguous parent semantics
- changing token scopes through the native credential store
- selecting among parent-managed accounts
- configuring unrelated credential helpers
- printing credentials through known authentication commands
- forwarding unknown future credential-management behavior

The policy reduces accidental misuse.

It does not prevent a local operator or compromised process from:

- invoking `gh` or `glab` directly
- reading credentials through `pass` when authorized
- modifying the password store
- changing wrapper code
- bypassing the wrapper entirely

This is a command-policy guardrail, not process isolation or access control.

## Verification requirements

Tests must cover the policy under every supported shell.

### Allowed GitHub operations

- `gh-pass auth`
- `gh-pass auth --help`
- `gh-pass auth -h`
- `gh-pass auth status`
- supported non-disclosing `auth status` options
- `gh-pass auth status --help`
- ordinary non-`auth` commands

### Rejected GitHub operations

- `auth login`
- `auth logout`
- `auth refresh`
- `auth setup-git`
- `auth switch`
- `auth token`
- unknown `auth` subcommand
- `auth status --show-token`
- `auth status -t`

Tests must verify that `gh` is not invoked for rejected commands.

### Allowed GitLab operations

- `glab-pass auth`
- `glab-pass auth --help`
- `glab-pass auth -h`
- `glab-pass auth status`
- supported non-disclosing `auth status` options
- `glab-pass auth status --help`
- ordinary non-`auth` commands

### Rejected GitLab operations

- `auth login`
- `auth logout`
- `auth configure-docker`
- `auth docker-helper`
- `auth dpop-gen`
- unknown `auth` subcommand
- `auth status --show-token`
- `auth status -t`

Tests must verify that `glab` is not invoked for rejected commands.

### Argument handling

Tests must cover:

- empty argument list
- help-only invocation
- conventional `auth` placement
- options before and after `auth status`
- repeated token-display flags
- `--` argument separator behavior
- argument values containing spaces
- arguments that resemble `auth` values but belong to another command
- ordinary parent arguments remaining byte-for-byte equivalent
- ambiguous invocation forms being rejected rather than forwarded unsafely

### Diagnostics

Tests must verify:

- status `1` for rejected commands
- actionable standard-error messages
- parent CLI is not executed
- no credential value appears in output
- no staged GitLab state is created when rejection can occur before credential
  handling
- no real password-store access occurs for commands rejected before credential
  retrieval

### Future compatibility

When a parent CLI adds or changes an `auth` subcommand:

- the test fixtures must be reviewed
- the allowlist must not expand automatically
- support requires an explicit code and documentation change
- security implications must be evaluated

## Relationship to other decisions

This ADR refines the compatibility language accepted in ADR 0002.

It operates within:

- ADR 0001's provider-specific command model
- ADR 0003's `pass`-authoritative durable-state model
- ADR 0005's GitLab staging and writeback model
- ADR 0006's wrapper failure semantics
- ADR 0007's signal-driven GitLab state policy

The project-context and architecture documents must describe the resulting
bounded compatibility contract.

## Decision summary

`gh-pass` and `glab-pass` support ordinary authenticated operations,
non-mutating help, and authentication-status checks that do not intentionally
display credential material.

They reject credential creation, mutation, deletion, disclosure, account
selection, credential-helper configuration, and unknown future operations
within the parent `auth` namespace.

Rejected commands return status `1`, do not invoke the parent CLI, and provide a
non-sensitive diagnostic.

Credential bootstrap, replacement, revocation, deletion, and recovery remain
separately documented operational procedures outside the wrapper compatibility
contract.
