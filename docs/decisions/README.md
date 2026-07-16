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
4. The root `README.md` provides a user-facing summary.
5. Code and tests demonstrate whether the implementation conforms to the
   documented architecture.

When an accepted decision changes, add a new ADR that supersedes the earlier
record. Do not silently rewrite the original decision history.

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
