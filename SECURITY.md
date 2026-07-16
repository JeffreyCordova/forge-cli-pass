# Security Policy

`forge-cli-pass` handles access tokens and GitLab CLI authentication state. Vulnerability reports should avoid public disclosure of credential material or exploitable implementation details before a fix is available.

## Supported versions

Before the first tagged release, security fixes are made against the current `main` branch.

After tagged releases begin, the intended support policy is:

| Version | Support |
|---|---|
| Current `main` | Supported |
| Latest tagged release | Supported |
| Older tagged releases | Best effort |
| Modified downstream copies | Not directly supported |

A report affecting an older version should identify the affected revision or release.

## Reporting a vulnerability

Use GitHub private vulnerability reporting for the primary repository when that feature is available.

Do not place sensitive details, proof-of-concept credential material, access tokens, private configuration, or exploitable reproduction steps in a public issue.

When no private reporting mechanism is visible, open a minimal public issue requesting a private communication channel. Include no vulnerability details beyond the fact that the report concerns a potential security issue.

Primary repository:

```text
https://github.com/JeffreyCordova/forge-cli-pass
```

The GitLab repository is a mirror. Reports should be coordinated through the primary repository unless it is unavailable.

## What to include

A useful report includes:

- The affected command: `gh-pass`, `glab-pass`, or installation/test infrastructure
- The affected commit or release
- The operating system and shell
- Relevant parent CLI and `pass` versions
- Preconditions required for exploitation
- Reproduction steps using synthetic credentials
- Expected and observed behavior
- Potential confidentiality, integrity, or availability impact
- Any proposed mitigation

Replace all real tokens, hostnames, account names, configuration values, repository names, and filesystem paths with synthetic equivalents.

## Response process

The intended response process is:

1. Confirm receipt of the report.
2. Reproduce and assess the issue.
3. Determine affected revisions and releases.
4. Develop and verify a correction.
5. Coordinate disclosure with the reporter.
6. Publish the correction and appropriate release notes.

Response timing depends on severity, reproducibility, maintainer availability, and coordination requirements. No fixed response-time guarantee is currently offered.

## Security model

The project’s central security invariant is:

> Wrapper-managed authentication state is durable in `pass` and transient in parent-CLI runtime interfaces.

For `gh-pass`, the wrapper reads a token from `pass` and injects only the first line through `GH_TOKEN`.

For `glab-pass`, the wrapper restores a complete opaque configuration into a private temporary directory, runs `glab` against it, persists eligible changes, and removes the runtime directory.

Credential-management and credential-disclosure commands are outside the wrapper compatibility contract.

## Relevant vulnerability classes

Reports are especially useful when they concern:

- Credential disclosure through diagnostics
- Credential disclosure through shell tracing
- Unsafe handling of temporary files or directories
- Incorrect filesystem permissions
- Symlink or path-substitution attacks
- Failure to remove staged authentication state
- Incorrect or missing required writeback
- Unauthorized replacement of durable `pass` state
- Authentication commands bypassing wrapper policy
- Argument-boundary corruption
- Environment-variable leakage
- Signal handling that loses eligible state
- Exit-status behavior that conceals wrapper failures
- Installation or uninstall behavior that modifies unrelated paths
- Development-link removal without ownership validation

## Out-of-scope conditions

The following conditions are generally outside the project’s direct security boundary unless the wrapper makes them materially worse:

- A compromised local user account
- A compromised operating system or kernel
- A compromised shell
- A compromised `pass`, GPG implementation, or GPG agent
- A compromised `gh` or `glab` executable
- A malicious executable already earlier in `PATH`
- Parent-CLI commands intentionally printing credentials
- Parent-CLI commands intentionally transmitting credentials
- Insecure Git remote configuration
- Insecure SSH configuration
- Deliberately weakened local filesystem permissions
- Modified downstream copies with behavior not present upstream

A report involving one of these conditions may still be actionable when the wrapper unnecessarily expands impact or violates its documented guarantees.

## Handling test material

Security reproductions must use synthetic credentials.

Suitable examples include:

```text
example-token-not-valid
synthetic-refresh-token
gitlab.invalid
example-owner/example-repository
```

Do not submit:

- Active access tokens
- Refresh tokens
- Cookies
- Private keys
- GPG private material
- Real `glab` configuration files
- Password-store contents
- Production hostnames
- Private repository information
- Personal filesystem paths that reveal sensitive information

## Public discussion

After a correction is available, public documentation may include:

- The affected behavior
- The affected revisions or releases
- The security impact
- The correction
- Required user action
- Credit for the reporter, when requested

Public disclosure should not include active credential material or unnecessary exploit details.
