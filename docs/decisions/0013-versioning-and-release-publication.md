# ADR 0013: Version releases with SemVer and publish from annotated tags

## Status

Accepted

## Context

`forge-cli-pass` has implemented and verified its initial public command
interface, credential-ownership model, installation behavior, documentation,
licensing, and continuous integration.

The project needs a release-versioning convention and a repeatable publication
process before its first public release.

The release process must distinguish development state from published state,
connect each release to an immutable Git commit, preserve release history, and
avoid publishing unverified source.

The GitHub repository is the primary upstream repository. The GitLab repository
is a mirror.

## Decision

The project uses Semantic Versioning 2.0.0.

The initial release version is:

```text
0.1.0
```

The root `VERSION` file records the intended release version without a leading
`v`.

Git tags use the corresponding `v`-prefixed form:

```text
v0.1.0
```

Release tags must be annotated tags.

A release may be created only when:

- The release commit is on `main`.
- The working tree is clean.
- The `VERSION` file matches the intended tag.
- `CHANGELOG.md` contains a dated entry for the version.
- The complete local verification interface passes.
- Continuous integration passes for the release commit.
- The release commit has been pushed to both upstream repositories.

The Git tag is pushed to both GitHub and GitLab.

The GitHub repository publishes the canonical release record. The GitLab mirror
receives the corresponding tag but does not initially publish an independently
maintained release record.

The first release is published manually. The existing `gh-pass` wrapper may be
used to invoke the ordinary authenticated GitHub CLI release operation.

GitHub release creation must verify that the referenced tag already exists. The
release process must not allow the release command to create a tag implicitly.

Initial releases distribute source only. No platform-specific binaries,
packages, or generated executables are published.

The release notes are derived from the annotated tag message and the
corresponding `CHANGELOG.md` entry.

Published release contents are not replaced in place. Corrections require a new
version and tag.

Automated release publication may be added later through a separate accepted
decision after the manual process has been exercised successfully.

## Alternatives considered

### Begin at version 1.0.0

This would communicate a stable compatibility commitment immediately.

It was rejected because the project has not yet accumulated real-world
downstream use sufficient to validate every public-interface and portability
assumption.

### Use date-based versions

Date-based versions would make release chronology obvious but would not
communicate compatibility expectations as clearly as Semantic Versioning.

### Use lightweight tags

Lightweight tags identify a commit but do not carry a tag annotation containing
release identity and notes.

Annotated tags provide a clearer release record and are therefore required.

### Publish automatically from every matching tag

Automatic publication would reduce manual work but would make the first release
process harder to inspect and correct.

The initial release remains manual so the complete process can be validated
before automation is accepted.

### Publish generated binaries

The wrappers are portable shell source files installed directly from the source
tree. Publishing generated binaries would add platform and supply-chain
complexity without providing meaningful value for the initial release.

## Consequences

Users can identify published revisions through conventional Semantic Versioning
numbers and `v`-prefixed tags.

The `0.y.z` release line communicates that compatibility may still evolve before
version `1.0.0`.

Every release is tied to a reviewed and verified Git commit.

The GitHub release page is canonical while GitLab remains a source and tag
mirror.

Release preparation requires synchronized changes to `VERSION`,
`CHANGELOG.md`, and the annotated tag.

A failed or incorrect published release is corrected with a new version rather
than by moving or reusing an existing tag.

## Security implications

Requiring an existing remote tag prevents the release command from silently
creating a tag from an unintended branch or commit.

Requiring successful local and continuous verification reduces the risk of
publishing code that differs from the accepted behavioral contract.

Avoiding replacement of published release contents preserves provenance and
reduces ambiguity for downstream users.

The initial source-only model avoids adding unverified generated artifacts to
the release boundary.

## Verification requirements

Before creating a release:

```sh
test "$(cat VERSION)" = '0.1.0'
git diff --quiet
git diff --cached --quiet
git branch --show-current
make check BUSYBOX=/path/to/compatible/busybox
```

The release tag must resolve to the intended commit:

```sh
git rev-parse v0.1.0^{commit}
git rev-parse HEAD
```

The two commit identifiers must match.

The tag must exist on both upstream repositories before the GitHub release is
published.
