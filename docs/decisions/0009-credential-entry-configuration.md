# ADR 0009: Use Default `pass` Entries with Environment Overrides

**Status:** Accepted

## Context

`gh-pass` and `glab-pass` require deterministic locations for their durable
credential state in `pass`.

The original personal wrappers used fixed entries:

```text
tokens/github/gh-oauth
tokens/gitlab/glab-oauth-config
```

Those paths reflected one operator's password-store organization. A public tool
should provide clear defaults without requiring every operator to adopt an
existing personal hierarchy.

The configuration model must also preserve the wrappers' command-compatibility
goal. Arguments following `gh-pass` or `glab-pass` should ordinarily remain
arguments to the parent CLI rather than being consumed by a growing
wrapper-specific option parser.

The project may need to support:

- different password-store hierarchies
- personal and work accounts
- temporary per-invocation credential selection
- migration from preexisting pass entries
- automation with explicit credential provenance

The configuration model must not:

- place credential values in configuration
- silently select among several possible entries
- fall back to parent CLI credential storage
- introduce configuration complexity without a demonstrated need
- create ambiguous precedence rules

## Decision

Each wrapper will have:

1. one built-in project-scoped default `pass` entry
2. one wrapper-specific environment variable that may override the entry name

The configuration controls only the name of the `pass` entry.

It does not contain the credential value or authentication-state payload.

## Default entries

The built-in default entries are:

```text
GitHub: forge-cli-pass/github/token
GitLab: forge-cli-pass/gitlab/oauth-config
```

These paths are part of the public configuration contract.

### GitHub entry

```text
forge-cli-pass/github/token
```

The entry contains the GitHub API token consumed by `gh-pass`.

The first line contains the token. Additional lines may contain non-secret
operator notes or metadata.

### GitLab entry

```text
forge-cli-pass/gitlab/oauth-config
```

The entry contains the complete opaque GitLab CLI authentication-state payload
consumed by `glab-pass`.

The wrapper does not parse or reconstruct this payload.

## Environment overrides

The supported override variables are:

```text
FORGE_CLI_PASS_GITHUB_ENTRY
FORGE_CLI_PASS_GITLAB_ENTRY
```

### GitHub override

```sh
FORGE_CLI_PASS_GITHUB_ENTRY='work/github/token' \
    gh-pass repo view
```

### GitLab override

```sh
FORGE_CLI_PASS_GITLAB_ENTRY='work/gitlab/oauth-config' \
    glab-pass repo view
```

The variables contain only pass-entry names.

They must never contain:

- an access token
- a refresh token
- a complete OAuth configuration
- decrypted credential material

## Resolution precedence

Each wrapper resolves its pass entry independently.

The precedence is:

1. a valid, explicitly set wrapper-specific environment variable
2. the built-in default entry

No other source participates in entry-name resolution.

### Unset override

When the relevant environment variable is unset, the wrapper uses its built-in
default.

Example:

```sh
unset FORGE_CLI_PASS_GITHUB_ENTRY
gh-pass repo view
```

Resolved entry:

```text
forge-cli-pass/github/token
```

### Non-empty override

When the relevant environment variable is set to a valid, non-empty value, the
wrapper uses that value.

Example:

```sh
FORGE_CLI_PASS_GITHUB_ENTRY='personal/github/token' \
    gh-pass repo view
```

Resolved entry:

```text
personal/github/token
```

### Explicitly empty override

When the relevant environment variable is set but empty, the wrapper returns a
configuration failure.

It must not silently use the built-in default.

Example:

```sh
FORGE_CLI_PASS_GITHUB_ENTRY='' gh-pass repo view
```

Expected behavior:

```text
gh-pass: FORGE_CLI_PASS_GITHUB_ENTRY is set but empty
```

The parent CLI must not be invoked.

The distinction is intentional:

```text
unset variable        → use the documented default
set, non-empty value  → use the explicit override
set, empty value      → fail
```

An explicitly empty value represents an operator or deployment error, not an
instruction to restore default behavior.

## Detecting unset and empty values

The POSIX shell implementation must distinguish an unset variable from a set but
empty variable.

A suitable pattern is:

```sh
if [ "${FORGE_CLI_PASS_GITHUB_ENTRY+x}" = x ]; then
    [ -n "$FORGE_CLI_PASS_GITHUB_ENTRY" ] ||
        die "FORGE_CLI_PASS_GITHUB_ENTRY is set but empty"

    pass_entry=$FORGE_CLI_PASS_GITHUB_ENTRY
else
    pass_entry='forge-cli-pass/github/token'
fi
```

The GitLab wrapper follows the equivalent logic for:

```text
FORGE_CLI_PASS_GITLAB_ENTRY
```

The implementation may differ, but the observable semantics must remain the
same.

## Entry-name validation

A selected pass-entry name must be validated before credential retrieval.

The wrapper must reject values that are:

- empty
- terminated or separated by a newline
- terminated or separated by a carriage return
- otherwise unusable as one pass-entry argument

The wrapper must pass the selected entry to `pass` as one quoted argument.

Example:

```sh
pass show "$pass_entry"
```

It must not:

- evaluate the entry as shell code
- split it into multiple arguments
- construct a command string
- use `eval`
- interpret wildcard characters
- perform pathname expansion
- normalize it into a different credential path without documentation

Spaces and ordinary shell metacharacters may be accepted when they remain one
quoted pass-entry argument and are supported by `pass`.

The initial implementation should reject only conditions with a concrete safety
or correctness justification rather than inventing an unnecessarily restrictive
entry-name grammar.

## Failure to read the selected entry

If the selected entry:

- does not exist
- cannot be decrypted
- cannot be read
- contains invalid or empty required credential state

the wrapper must fail.

It must not:

- try the built-in default after an override fails
- search neighboring password-store paths
- try the parent CLI's native credential storage
- consult a desktop keyring
- try another account
- invoke an interactive login flow

The selected entry remains the sole credential source for that invocation.

This makes credential provenance deterministic.

## Interaction with `pass` configuration

`forge-cli-pass` configures only the entry name supplied to `pass`.

It does not duplicate configuration that already belongs to `pass`.

Existing `pass` and GPG behavior may continue to use their normal environment
and configuration, including settings such as:

```text
PASSWORD_STORE_DIR
PASSWORD_STORE_GPG_OPTS
PASSWORD_STORE_GENERATED_LENGTH
```

The wrappers do not introduce project-specific replacements for these settings.

In particular:

- `PASSWORD_STORE_DIR` may select a different password store
- GPG configuration remains owned by GPG and `pass`
- password-store Git synchronization remains outside this project

The environment from which the wrappers are invoked is already part of the
documented trust boundary.

## Multiple accounts and environments

Environment overrides provide explicit per-invocation credential selection
without introducing a profile subsystem.

Examples:

```sh
FORGE_CLI_PASS_GITHUB_ENTRY='personal/github/token' \
    gh-pass repo list
```

```sh
FORGE_CLI_PASS_GITHUB_ENTRY='work/github/token' \
    gh-pass repo list
```

```sh
FORGE_CLI_PASS_GITLAB_ENTRY='personal/gitlab/oauth-config' \
    glab-pass project list
```

```sh
FORGE_CLI_PASS_GITLAB_ENTRY='work/gitlab/oauth-config' \
    glab-pass project list
```

Operators may define non-secret shell aliases or functions for repeated use.

Example:

```sh
gh-work() {
    FORGE_CLI_PASS_GITHUB_ENTRY='work/github/token' \
        gh-pass "$@"
}
```

Such aliases and functions are operator configuration and are not part of the
project's public command interface.

Native parent CLI account switching remains governed by ADR 0008 and is not
used as an alternative credential-selection mechanism.

## No wrapper-specific command-line options

The wrappers will not introduce command-line options such as:

```text
--pass-entry
--credential-entry
--profile
--account
```

Reasons include:

- collision with current or future parent CLI options
- additional parsing before argument forwarding
- weakened direct command substitution
- ambiguity around `--`
- a broader compatibility surface
- pressure to reproduce parent CLI option parsing

Every ordinary argument following the wrapper command remains intended for the
parent CLI, except for the narrow credential-management policy enforcement
defined by ADR 0008.

## No project configuration file

The initial project will not create or parse a configuration file such as:

```text
~/.config/forge-cli-pass/config
```

A configuration file is not justified by the current requirements.

Introducing one would require decisions about:

- format
- parsing
- schema
- precedence
- permissions
- migration
- profiles
- error recovery
- backward compatibility
- whether sensitive values are permitted
- interaction with environment overrides

A future configuration file requires a new architecture decision based on
concrete operator needs.

## No automatic discovery

The wrappers will not search for credential entries automatically.

They will not:

- test several likely paths
- scan the password store
- infer an account from the current Git remote
- infer an entry from a forge hostname
- select the first readable credential
- choose between personal and work entries automatically
- fall back to an entry used during a previous invocation

Automatic discovery would make credential provenance dependent on local state
and could select an unintended account.

The selected entry must always result from either:

- the documented default
- an explicit environment override

## No credential-source fallback

Failure to access the selected `pass` entry must not cause fallback to:

- GitHub CLI's stored authentication state
- GitLab CLI's stored authentication state
- an operating-system keyring
- a desktop credential service
- a plaintext file
- a long-lived credential environment variable
- interactive authentication
- another pass entry

This preserves ADR 0003's authoritative-store model.

## Diagnostics

Configuration diagnostics must:

- identify the wrapper
- identify the invalid environment-variable name
- identify the selected pass-entry name when useful
- state whether the problem is configuration or credential retrieval
- avoid printing credential material
- write to standard error
- return wrapper status `1`

Examples:

```text
gh-pass: FORGE_CLI_PASS_GITHUB_ENTRY is set but empty
```

```text
glab-pass: FORGE_CLI_PASS_GITLAB_ENTRY contains a newline
```

```text
gh-pass: failed to read credential entry: work/github/token
```

Entry names are not treated as credential values, but diagnostics should still
avoid unnecessary disclosure of local naming details when they are not useful
for remediation.

## Migration from prototype entry names

The prototype used:

```text
tokens/github/gh-oauth
tokens/gitlab/glab-oauth-config
```

Operators may migrate those entries to the public defaults:

```sh
pass mv \
    tokens/github/gh-oauth \
    forge-cli-pass/github/token
```

```sh
pass mv \
    tokens/gitlab/glab-oauth-config \
    forge-cli-pass/gitlab/oauth-config
```

Operators must inspect their password-store state before performing a move.

Alternatively, they may retain the existing hierarchy through overrides:

```sh
export FORGE_CLI_PASS_GITHUB_ENTRY='tokens/github/gh-oauth'
export FORGE_CLI_PASS_GITLAB_ENTRY='tokens/gitlab/glab-oauth-config'
```

The old entry names are not built-in compatibility aliases.

The wrappers will not search them automatically.

## Alternatives considered

### Fixed entries without overrides

Potential advantages:

- smallest possible configuration surface
- completely uniform password-store hierarchy
- no environment-controlled entry selection

Rejected because:

- it imposes one hierarchy on every operator
- it makes work and personal accounts awkward
- it complicates migration from existing password stores
- operators would need to edit wrapper code for local organization

### Wrapper-specific command-line options

Rejected because they would compete with parent CLI arguments and weaken the
command-compatible wrapper model.

### Project configuration file

Rejected for the initial architecture because current requirements do not
justify the parsing, precedence, schema, and migration complexity.

### Automatic password-store discovery

Rejected because it could select unintended credentials and make provenance
difficult to reason about.

### Native parent CLI account selection

Rejected as a configuration mechanism because it depends on persistent
parent-managed credential state and conflicts with ADR 0003 and ADR 0008.

### Credential values in environment variables

Rejected as a project configuration mechanism.

`gh-pass` necessarily supplies the GitHub token to the `gh` child process
through `GH_TOKEN`, but the durable credential value originates in `pass`.

The public override variables contain only entry names.

### Silent fallback from invalid override to default

Rejected because it could cause an invocation intended for one account to use
another account silently.

Explicit configuration errors must remain visible.

## Consequences

### Positive

- The default setup works without additional project configuration.
- Credential provenance remains deterministic.
- Operators can use their existing password-store hierarchy.
- Work and personal credentials can be selected explicitly.
- No project-specific config parser is required.
- No wrapper option namespace competes with parent CLI options.
- Explicitly empty configuration fails visibly.
- Failure to read one entry cannot silently select another credential.
- Credential values remain outside the configuration mechanism.

### Negative

- Environment variables become part of the public configuration interface.
- Operators using several accounts may rely on shell aliases or external
  environment management.
- The project does not provide stored named profiles.
- Entry-name overrides can be controlled by any process that controls the
  invocation environment.
- Future renaming of default entries would be a public compatibility change.
- Password-store migration remains an operator responsibility.

## Security implications

This decision preserves the project's credential boundaries by ensuring that:

- the configuration mechanism carries entry names, not secrets
- `pass` remains the only durable wrapper-managed credential source
- credential selection is explicit and deterministic
- failed overrides do not silently fall back
- no additional plaintext project configuration is introduced
- no automatic account inference occurs
- parent-native stored credentials are not consulted

The environment is within the project's trusted invocation boundary.

A process able to control the wrapper environment may select another readable
pass entry. Preventing that is outside the scope of these wrappers and would
require a different execution or policy boundary.

The wrappers must still ensure that environment-variable values are handled as
data rather than executable shell syntax.

## Verification requirements

Tests must cover this decision under every shell supported by ADR 0004.

### Default resolution

- unset GitHub override selects `forge-cli-pass/github/token`
- unset GitLab override selects `forge-cli-pass/gitlab/oauth-config`
- the selected default is passed to `pass` as one argument

### Explicit overrides

- a valid GitHub override selects the requested entry
- a valid GitLab override selects the requested entry
- entry names containing spaces remain one argument
- shell metacharacters are not evaluated
- wildcard characters are not expanded
- the parent CLI receives its original arguments unchanged

### Empty overrides

- set-but-empty GitHub override fails
- set-but-empty GitLab override fails
- the built-in default is not consulted
- `pass` is not invoked
- the parent CLI is not invoked
- final status is `1`

### Invalid overrides

- newline-containing GitHub entry is rejected
- carriage-return-containing GitHub entry is rejected
- newline-containing GitLab entry is rejected
- carriage-return-containing GitLab entry is rejected
- diagnostics do not contain credential material
- the parent CLI is not invoked

### Credential retrieval failure

- unreadable selected entry fails
- missing selected entry fails
- failure does not trigger default fallback
- failure does not trigger another entry lookup
- failure does not invoke native parent authentication
- final status is `1`

### Multiple accounts

- separate overrides select separate fake entries
- no state leaks from one invocation to another
- one wrapper's override does not affect the other wrapper
- parent-native account-switching is not used

### Existing `pass` configuration

- `PASSWORD_STORE_DIR` is allowed to pass through to fake `pass`
- the wrappers do not reinterpret password-store configuration
- the test suite never accesses the real password store

### Isolation

All tests must use:

- a fake `pass`
- fake credential entries
- fake parent CLI commands
- an isolated `PATH`
- a temporary `HOME`
- a temporary password-store directory
- no network
- no production credentials
- no real parent CLI authentication state

## Relationship to other decisions

This ADR operates within:

- ADR 0001's provider-specific command model
- ADR 0002's public naming and terminology
- ADR 0003's `pass`-authoritative durable-state model
- ADR 0004's POSIX shell and Linux support contract
- ADR 0008's credential-management command restrictions

It does not alter the credential-delivery mechanisms defined for `gh-pass` and
`glab-pass`.

## Decision summary

`gh-pass` and `glab-pass` use documented project-scoped default `pass` entries:

```text
forge-cli-pass/github/token
forge-cli-pass/gitlab/oauth-config
```

Operators may override the selected entry through:

```text
FORGE_CLI_PASS_GITHUB_ENTRY
FORGE_CLI_PASS_GITLAB_ENTRY
```

An unset override selects the default.

A valid non-empty override selects the explicit entry.

A set but empty or invalid override is a wrapper failure.

The project provides no wrapper-specific entry-selection options, configuration
file, automatic discovery, or credential-source fallback.
