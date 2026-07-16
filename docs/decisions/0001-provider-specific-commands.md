# ADR 0001: Use Provider-Specific Wrapper Commands

**Status:** Accepted

## Context

`forge-cli-pass` adapts the credential lifecycle of two separate parent
command-line interfaces:

- GitHub CLI, `gh`
- GitLab CLI, `glab`

The parent CLIs consume and maintain authentication state differently.

GitHub CLI can consume a token directly through the `GH_TOKEN` environment
variable. The GitHub wrapper can therefore retrieve a token from `pass` and
provide it to the child `gh` process.

GitLab CLI's OAuth workflow depends on mutable configuration state. The GitLab
wrapper must restore a complete configuration payload into a private temporary
directory, run `glab` against that directory, detect relevant changes, write
updated state back to `pass`, and remove the temporary plaintext copy.

A unified command would conceal these materially different credential flows and
would require dispatch or abstraction that is unnecessary for the current
scope.

The wrappers are also intended to function as direct command substitutions for
their respective parent CLIs during ordinary authenticated operations.

## Decision

The project will provide two separate provider-specific commands:

```text
gh-pass
glab-pass
```

`gh-pass` wraps `gh`.

`glab-pass` wraps `glab`.

The commands will preserve the parent CLI argument interface for supported
ordinary authenticated operations.

The project will not introduce a unified top-level runtime command, provider
plugin system, or generic credential-backend framework unless a later
architecture decision establishes a concrete need.

Shared implementation code may be considered only when it reduces verified
duplication without obscuring provider-specific security behavior or coupling
the two credential lifecycles unnecessarily.

## Alternatives considered

### One command with provider subcommands

Example:

```sh
forge-cli-pass github ...
forge-cli-pass gitlab ...
```

This would create a cohesive top-level product interface but would add command
dispatch and make the wrappers less direct substitutes for `gh` and `glab`.

Rejected because the provider behaviors are materially different and the shared
interface would not simplify normal use.

### One command plus compatibility aliases

This would expose a unified public command while retaining provider-specific
aliases.

Rejected because it would increase the public surface without resolving a
current operator need.

### Generic provider plugin architecture

Rejected because only two known providers are supported and their credential
models do not currently justify a generalized extension mechanism.

## Consequences

### Positive

- Each command has one clear parent CLI.
- Provider-specific credential behavior remains visible and independently
  auditable.
- Arguments can be forwarded directly to the corresponding parent command.
- Tests can isolate each credential lifecycle.
- Failure in one provider adapter does not require a shared abstraction.
- The command model remains proportionate to the project's scope.

### Negative

- Some validation and diagnostic logic may be duplicated.
- The project exposes two commands rather than one product command.
- Cross-provider behavior must be kept consistent through tests and
  documentation rather than a mandatory shared runtime layer.

## Security implications

Keeping the wrappers separate makes the distinct credential exposure and
persistence models explicit:

- `gh-pass` performs per-process credential injection.
- `glab-pass` performs temporary mutable credential-state staging and
  conditional writeback.

A shared abstraction must not erase security-relevant differences such as:

- environment-based versus file-based credential delivery
- immutable versus mutable runtime credential state
- cleanup requirements
- writeback behavior
- exit-status precedence

## Verification requirements

Tests must verify independently that:

- `gh-pass` invokes `gh` with the expected credential environment.
- `glab-pass` invokes `glab` with the expected temporary configuration.
- User arguments retain their order and boundaries.
- The wrappers do not reinterpret ordinary parent CLI subcommands.
- Provider-specific failure and cleanup behavior remains isolated.
- No unified command is required for normal operation.
