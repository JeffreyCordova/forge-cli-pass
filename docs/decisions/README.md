# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for
`forge-cli-pass`.

ADRs document decisions that materially affect the project's architecture,
security boundaries, public interface, compatibility contract, or long-term
maintenance. They are not used for routine implementation details.

## Authority

The documentation authority order is:

1. Accepted ADRs record authoritative architectural decisions and their
   rationale.
2. [`../architecture.md`](../architecture.md) describes the integrated current
   architecture and must remain consistent with accepted ADRs.
3. [`../project-context.md`](../project-context.md) records the project's
   origin, problem statement, goals, and historical context.
4. The root [`README.md`](../../README.md) provides a user-facing summary.
5. Code and tests demonstrate whether the implementation conforms to the
   documented architecture.

When an accepted decision changes, add a new ADR that supersedes the earlier
record. Do not silently rewrite the original decision history.

## Decision index

| ADR | Decision | Status |
|---:|---|---|
| 0001 | Provider-specific commands | Accepted |
| 0002 | Project identity and terminology | Accepted |
| 0003 | Use `pass` as the authoritative credential store | Accepted |
| 0004 | Target POSIX `sh` on Linux | Accepted |
| 0005 | Stage GitLab state in a private runtime directory | Accepted |
| 0006 | Preserve parent status unless wrapper obligations fail | Accepted |
| 0007 | Write back eligible GitLab state during handled signals | Accepted |
| 0008 | Restrict credential-management commands | Accepted |
| 0009 | Use default `pass` entries with explicit overrides | Accepted |
| 0010 | Use copy-based installation and tagged source releases | Accepted |
| 0011 | License the project under Apache-2.0 | Accepted |
| 0012 | Verify the project in GitHub Actions | Accepted |
| 0013 | Version releases with SemVer and publish from annotated tags | Accepted |

The numbered ADR files in this directory are the authoritative records. This
index is a navigation summary and must be updated whenever a record is added,
superseded, deprecated, rejected, or otherwise changes status.

## Status values

- **Proposed** — Under consideration and not yet authoritative.
- **Accepted** — Approved and authoritative.
- **Rejected** — Considered but not adopted.
- **Superseded** — Replaced by a later ADR.
- **Deprecated** — Still present but no longer recommended.

## Naming

ADR filenames use a four-digit sequence followed by a concise descriptive name:

```text
0001-provider-specific-commands.md
0002-project-identity-and-terminology.md
```

Numbers are never reused.

## Record structure

Each ADR should contain:

- Title
- Status
- Context
- Decision
- Alternatives considered
- Consequences
- Security implications
- Verification requirements

The amount of detail should remain proportionate to the decision.
