# ADR 0003: Use `pass` as the Authoritative Durable Credential Store

**Status:** Accepted

## Context

The project originated in a command-line-only Arch Linux and WSL environment
that intentionally did not use a desktop keyring.

GitHub CLI warned that authentication credentials had been saved in plaintext.
GitLab CLI also maintained reusable authentication state in CLI-managed
configuration.

Git already used SSH keys for repository transport. The unresolved problem was
the durable storage and runtime exposure of API credentials required by `gh`
and `glab`.

The existing local credential-management model used `pass`, which stores
entries as GPG-encrypted files.

The project could either enforce one deterministic credential backend or
abstract over multiple possible stores.

## Decision

`pass` is the authoritative durable store for all wrapper-managed forge API
credential state.

`gh-pass` retrieves its GitHub credential material from `pass`.

`glab-pass` retrieves its GitLab authentication-state payload from `pass` and
writes legitimate runtime changes back to the same store according to the
accepted writeback policy.

The wrappers will not silently fall back to:

- parent CLI credential files
- desktop keyrings
- operating-system credential services
- plaintext environment files
- shell configuration
- alternate secret stores

If the required `pass` entry is unavailable, unreadable, empty, or otherwise
invalid, the wrapper must fail rather than use an unintended credential source.

Support for another durable credential backend requires a new architecture
decision and is outside the initial project scope.

## Security invariant

> Durable wrapper-managed forge API credential state is stored only in `pass`.
> Decrypted credential material is introduced only during an active invocation
> of the corresponding parent CLI and is not retained in wrapper-controlled
> plaintext storage after that invocation ends.

This invariant applies to state controlled by the wrappers.

It does not claim that credential material is absent from:

- process memory
- child-process environments
- swap
- filesystem journals
- privileged process inspection
- parent CLI internals
- extensions
- external logs or forensic systems

## Alternatives considered

### Use the parent CLI's native credential storage

Rejected because the triggering environment lacked or intentionally excluded a
desktop keyring, and the resulting storage behavior did not satisfy the desired
credential policy.

### Prefer `pass` but fall back to native CLI storage

Rejected because fallback would make credential provenance and persistence
dependent on the environment and could silently reintroduce the original
plaintext-storage condition.

### Support multiple credential backends

Rejected for the initial scope because it would introduce backend discovery,
configuration precedence, capability differences, additional trust boundaries,
and a larger test matrix.

### Use environment variables as durable configuration

Rejected because shell configuration and long-lived environment variables are
not acceptable durable stores for reusable credential material.

### Implement a new encrypted store

Rejected because `pass` already provides the intended GPG-backed durable storage
model. Reimplementing secret storage is outside the project's scope.

## Consequences

### Positive

- Credential provenance is deterministic.
- The project has one explicit durable-state trust boundary.
- Behavior does not depend on desktop integration.
- The wrappers can be tested against a fake `pass` interface.
- Credential state is not fragmented across multiple stores.
- The project's purpose remains clear and bounded.

### Negative

- `pass` and GPG are mandatory runtime dependencies.
- Users committed to another credential backend are outside the initial target
  audience.
- Availability of wrapper-managed credentials depends on the user's password
  store and GPG configuration.
- The project inherits relevant risks and operational requirements from `pass`
  and GPG.
- Multi-backend extensibility is intentionally deferred.

## Security implications

The project trusts:

- the local `pass` executable
- the password-store contents
- GPG
- the relevant private key
- the local user account

Compromise of these components is outside the wrapper protection boundary.

Using `pass` reduces persistent plaintext credential residue under the intended
operating model, but it does not provide:

- process isolation
- runtime secrecy from privileged actors
- token issuance or rotation
- endpoint compromise protection
- guaranteed secure deletion
- protection from malicious parent CLIs

The wrappers must avoid printing decrypted entries or persisting them outside
their documented runtime paths.

## Verification requirements

Tests must verify that:

- missing `pass` causes a wrapper failure
- missing credential entries cause a wrapper failure
- empty credential data causes a wrapper failure
- no fallback credential source is consulted
- `gh-pass` retrieves its token through `pass`
- `glab-pass` retrieves and writes its configuration through `pass`
- wrapper diagnostics do not expose credential values
- default parent CLI authentication locations are not used for
  wrapper-managed state
- tests use a fake password store and never access the developer's real store
