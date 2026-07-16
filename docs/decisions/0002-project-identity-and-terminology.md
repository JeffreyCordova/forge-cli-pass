# ADR 0002: Adopt the Public Project Identity and Terminology Model

**Status:** Accepted

## Context

The project began as two personal scripts named:

```text
ghp
glabp
```

Those names were compact but did not communicate their purpose to an unfamiliar
operator. The original repository name, `forge-cli-auth`, also suggested a
broader authentication function than the project actually performs.

The project does not:

- authenticate identities itself
- implement OAuth
- issue credentials
- manage authorization policy
- manage Git SSH authentication
- replace `pass`
- replace the parent CLIs

It adapts how existing forge API credentials are stored, introduced at runtime,
and persisted around invocations of `gh` and `glab`.

The public identity must communicate:

- the relationship to `gh` and `glab`
- the fundamental role of `pass`
- the provider-specific command model
- the credential-lifecycle scope
- bounded compatibility and security claims

## Decision

The public project identity is:

```text
Repository:  forge-cli-pass

Commands:    gh-pass
             glab-pass

Backend:     pass

Parents:     gh
             glab
```

The formal project description is:

> Pass-backed credential lifecycle wrappers for GitHub CLI and GitLab CLI.

The project category is:

> Credential lifecycle tooling.

The compatibility description is:

> Command-compatible wrappers for ordinary authenticated operations.

The earlier names `ghp` and `glabp` are not part of the public interface. They
may remain private user-defined aliases.

## Approved terminology

### Forge

A Git hosting and collaboration platform, such as GitHub or GitLab.

### Parent CLI

The upstream command-line utility invoked by a wrapper:

- `gh` for `gh-pass`
- `glab` for `glab-pass`

### Forge API credential

A token or OAuth credential used by a parent CLI to authorize API operations.

### Credential material

Sensitive data that enables authenticated or authorized access.

### Authentication state

Credential material and associated configuration required for a parent CLI to
remain authenticated.

### Durable credential state

Credential material intended to survive between command invocations.

### Runtime credential material

A decrypted representation introduced for one active invocation.

### Credential injection

Providing credential material directly to a process without creating
persistent CLI authentication configuration.

This term applies primarily to `gh-pass`.

### Credential staging

Materializing credential state in a controlled temporary location for a
process that requires file-based or mutable configuration.

This term applies primarily to `glab-pass`.

### Writeback

Persisting changed runtime credential state back into `pass`.

### Persistent credential residue

Reusable credential material left after an invocation in an unintended durable
location.

This term does not imply forensic erasure when the material is removed.

### Wrapper-managed credential state

Credential state introduced, persisted, or removed by this project.

## Terms to avoid

The project should avoid unqualified use of:

- secure wrapper
- authentication provider
- credential broker
- OAuth implementation
- secrets vault
- ephemeral credential
- zero residue
- plaintext-free
- complete isolation
- unconditional drop-in replacement

These terms either overstate the project's scope or imply guarantees beyond its
enforcement boundary.

## Alternatives considered

### Retain `forge-cli-auth`

Rejected because `auth` suggests responsibility for authentication protocols
or identity verification that the project does not provide.

### Retain `ghp` and `glabp`

Rejected as public names because the `p` suffix is ambiguous and does not make
the `pass` integration clear.

### Use `pass-gh` and `pass-glab`

Rejected because the names could be interpreted as native `pass` extensions
rather than wrappers around the forge CLIs.

### Use a broad name such as `forge-credential-tools`

Rejected because it suggests a larger credential-management product than the
current bounded scope.

## Consequences

### Positive

- The repository and command names communicate the central `pass` integration.
- The parent CLI remains visible in each command name.
- The terminology distinguishes credential lifecycle management from
  authentication implementation.
- Documentation and interviews can use one consistent vocabulary.
- Security claims remain bounded and technically defensible.

### Negative

- Existing personal command names must be renamed or retained as local aliases.
- The word `pass` may require explanation for readers unfamiliar with the Unix
  password store.
- “Command-compatible” requires a documented boundary for credential-management
  subcommands.

## Security implications

Precise terminology reduces the risk of overstating protection.

In particular:

- runtime credential material is not described as inherently ephemeral
- deletion is not described as forensic erasure
- the project does not claim that credentials never leave `pass`
- SSH Git transport remains explicitly separate
- wrapper-controlled state is distinguished from parent CLI and operating-system
  behavior

## Verification requirements

Public documentation, diagnostics, command names, tests, packaging, and release
artifacts must use:

```text
forge-cli-pass
gh-pass
glab-pass
```

Documentation must distinguish:

- Git transport authentication from forge API credentials
- durable state from runtime material
- credential injection from credential staging
- wrapper-controlled behavior from external behavior

The public interface must not install `ghp` or `glabp` unless a later decision
adds them as supported compatibility aliases.
