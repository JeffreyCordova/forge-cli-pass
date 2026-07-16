# Maintenance guide

This document describes how to maintain `forge-cli-pass` without weakening its
credential-ownership model, command-compatibility contract, portability
baseline, or release provenance.

It is an operational guide for routine changes, upstream compatibility work,
security fixes, testing, and repository maintenance.

Accepted Architecture Decision Records (ADRs) remain authoritative. This guide
does not replace them.

## Maintenance objectives

Maintenance work should preserve five project-level properties:

1. `pass` remains the authoritative store for wrapper-managed authentication
   state.
2. Ordinary allowed commands remain compatible with their parent CLIs.
3. GitLab transient state remains private, validated, conditionally persisted,
   and cleaned up.
4. Behavior remains verified under every supported shell.
5. Published releases remain tied to immutable, verified source commits.

A change that appears locally convenient but weakens one of these properties
requires explicit architectural review rather than an informal implementation
shortcut.

## Authority and supporting documents

Project documentation has different roles:

| Document | Role |
|---|---|
| [`decisions/`](decisions/) | Authoritative accepted architectural decisions |
| [`architecture.md`](architecture.md) | Integrated description of the current design |
| [`threat-model.md`](threat-model.md) | Assets, boundaries, threats, and residual risks |
| [`security-assurance.md`](security-assurance.md) | Claims mapped to controls and evidence |
| This guide | Operational maintenance procedure |
| [`../README.md`](../README.md) | User-facing behavior and usage |
| [`../CHANGELOG.md`](../CHANGELOG.md) | Released user-visible changes |
| Tests | Executable behavioral evidence |

When these sources disagree:

1. accepted ADRs define the architectural constraint
2. implementation and tests must conform to that constraint
3. integrated documentation must be updated to reflect the accepted state
4. user-facing documentation must describe the resulting behavior accurately

A change that alters an accepted architectural decision should add or supersede
an ADR rather than silently editing the implementation around it.

## Supported baseline

The current supported environment is:

- Linux
- POSIX `sh`
- Dash
- Bash in POSIX mode
- BusyBox `ash`
- `pass`
- `gh`
- `glab`
- `mktemp`
- `sha256sum`
- `chmod`
- `rm`

The wrappers rely on required commands being available through `PATH`.

Adding another operating system, shell, provider, credential store, hashing
utility, temporary-file model, or parent CLI is an architectural expansion and
requires review of:

- portability assumptions
- threat boundaries
- authentication behavior
- process and signal semantics
- installation behavior
- verification coverage

## Public compatibility boundary

For allowed ordinary operations, the wrappers aim to preserve:

- argument order
- argument boundaries
- empty arguments
- standard input
- standard output
- standard error
- working-directory behavior
- ordinary parent exit status when wrapper obligations succeed

The wrappers deliberately do not preserve parent behavior for commands that
conflict with wrapper credential ownership.

Credential-management and credential-disclosure operations are rejected
according to the accepted authentication policy.

A change to any of the following is compatibility-sensitive:

- argument parsing
- authentication-command classification
- environment-variable injection
- standard-input handling
- file-descriptor handling
- asynchronous execution
- signal handling
- parent exit-status propagation
- wrapper-failure precedence
- GitLab state restoration or writeback
- temporary-directory creation or cleanup

Compatibility-sensitive changes require behavioral regression tests.

## Credential ownership

### GitHub

The default GitHub entry is:

```text
forge-cli-pass/github/token
```

`gh-pass`:

- reads the selected `pass` entry
- uses only the first line as the token
- rejects an empty first line
- supplies the token through `GH_TOKEN`
- replaces itself with `gh`

Maintenance must not introduce persistent wrapper-managed GitHub CLI state
without a new accepted decision.

### GitLab

The default GitLab entry is:

```text
forge-cli-pass/gitlab/oauth-config
```

`glab-pass` treats the complete entry as opaque GitLab CLI configuration.

It:

- restores the full config
- stages it privately
- fingerprints the initial state
- runs `glab`
- validates post-command state
- writes back eligible changed state
- removes transient state

Maintenance must not parse individual GitLab credential fields merely for
convenience. Parsing the opaque config would create new schema assumptions and
requires architectural and threat-model review.

## Trusted external commands

The wrappers currently trust commands resolved through `PATH`.

Relevant commands include:

- `pass`
- `gh`
- `glab`
- `mktemp`
- `sha256sum`
- `chmod`
- `rm`

Using `command` avoids shell aliases and functions but does not authenticate the
resolved executable.

When adding an external command:

1. justify why existing POSIX shell functionality is insufficient
2. document the new runtime dependency
3. update dependency checks
4. add controlled test fixtures where failure behavior matters
5. update the README requirements
6. update the threat model
7. update the assurance case
8. review CI and BusyBox implications
9. consider whether an ADR is required

Avoid adding dependencies solely to shorten otherwise clear shell code.

## Repository workflow

The canonical repository is GitHub.

GitLab mirrors the canonical `main` branch and release tags but does not
currently publish an independently maintained release record.

### Protected `main`

GitHub protects `main` through a branch ruleset.

Changes to `main` must:

- arrive through a pull request
- pass the required `Verify` status check
- be tested against the latest target-branch state
- avoid force pushes
- avoid branch deletion

No approving review is currently required because the project has one
maintainer. The pull request still provides a review boundary, CI record, and
durable change narrative.

### Protected release tags

Tags matching `v*` are protected against update and deletion.

New release tags may be created, but existing release tags must not be moved or
reused.

Corrections are published through a new version and tag.

### Repository security automation

GitHub Actions dependencies are pinned to full commit identifiers and monitored
by Dependabot through weekly update pull requests.

OpenSSF Scorecard runs after pushes to `main` and on a weekly schedule. Its
findings are reviewed as supplemental evidence; Scorecard is not a substitute
for `make check` and is not a required pull-request status check.

### Normal change workflow

Create a focused topic branch:

```sh
git switch main
git pull --ff-only github main
git switch -c TYPE/short-description
```

Examples:

```text
fix/preserve-parent-input
docs/maintenance-guide
test/auth-policy-regression
refactor/staging-validation
```

Make and verify the change:

```sh
git diff --check

make check \
    BUSYBOX="$HOME/.cache/forge-cli-pass/ci/busybox"
```

Commit with a concise summary and an explanatory body when useful:

```sh
git add PATHS

git commit \
    -m "TYPE: concise summary" \
    -m "Explain the reason, affected contract, and verification evidence."
```

Push the topic branch to GitHub:

```sh
git push --set-upstream github HEAD
```

Capture the branch name and create the pull request:

```sh
branch=$(git branch --show-current)

src/gh-pass pr create \
    --repo JeffreyCordova/forge-cli-pass \
    --head "$branch" \
    --base main \
    --fill
```

Wait for the required check. The installed GitHub CLI requires an explicit pull
request selector when `--repo` is present:

```sh
src/gh-pass pr checks "$branch" \
    --repo JeffreyCordova/forge-cli-pass \
    --required \
    --watch \
    --fail-fast
```

Review the complete server-side pull-request diff:

```sh
src/gh-pass pr diff "$branch" \
    --repo JeffreyCordova/forge-cli-pass
```

Merge only the exact head commit that was reviewed:

```sh
pr_head=$(git rev-parse HEAD)

src/gh-pass pr merge "$branch" \
    --repo JeffreyCordova/forge-cli-pass \
    --squash \
    --delete-branch \
    --match-head-commit "$pr_head"
```

After the pull request is merged, update local `main`, mirror it to GitLab, and
prune stale remote-tracking references:

```sh
git switch main
git pull --ff-only github main
git push gitlab main
git fetch --all --prune
```

Because squash merging does not make the topic commit an ancestor of `main`,
delete the local topic branch explicitly after confirming the merge:

```sh
git branch -D "$branch"
```

The GitHub pull request is the canonical change record. GitLab receives the
resulting `main` state.

## Change classification

Classify a proposed change before implementation.

### Documentation-only

Examples:

- correcting wording
- adding examples
- documenting an existing behavior
- improving links or navigation

Required review:

- verify statements against implementation and accepted decisions
- run `git diff --check`
- run targeted link and path review
- run the full suite when documentation contains executable commands or
  behavioral claims that may expose an implementation mismatch

A documentation-only change does not require a version bump unless it corrects
materially misleading release documentation.

### Test-only

Examples:

- adding missing regression coverage
- improving fixtures
- strengthening failure injection
- clarifying test diagnostics

Required review:

- confirm the test expresses an accepted property
- confirm it fails against the defective or incomplete behavior where practical
- run the complete shell matrix
- ensure fixture behavior does not accidentally replace the property under test

A test-only change does not normally require a release.

### Internal refactor

Examples:

- simplifying control flow
- renaming internal functions
- reducing duplication
- reorganizing tests

Required review:

- preserve observable behavior
- run the full suite
- compare status, signal, and diagnostic behavior
- avoid expanding runtime dependencies
- update source comments when reasoning changes

A refactor should not receive a user-visible changelog entry unless it changes
observable behavior or security posture.

### Compatibility fix

Examples:

- restoring stdin behavior
- preserving an exit status
- correcting argument handling
- adapting to upstream CLI drift

Required review:

- document the violated compatibility property
- reproduce the issue
- add a property-oriented regression test
- run the complete supported-shell matrix
- update the threat model or assurance case when evidence or assumptions change
- add a changelog entry
- publish a patch release when released behavior is corrected

### Security fix

Examples:

- preventing credential disclosure
- rejecting unsafe state
- correcting temporary-file handling
- preventing unintended credential mutation
- restoring required cleanup or writeback

Required review:

- assess disclosure risk before using a public issue or pull request
- follow the private-reporting procedure where appropriate
- identify affected assets and trust boundaries
- add regression evidence
- update the threat model
- update the assurance case
- add a changelog entry that does not expose unnecessary exploit detail before
  users can update
- publish a patch release unless compatibility requires a larger increment

### Architectural change

Examples:

- adding a provider
- adding a credential backend
- parsing GitLab config
- supporting another platform
- changing the durable-state model
- automating release publication
- publishing generated artifacts

Required review:

- create or supersede an ADR
- update architecture documentation
- update the threat model
- update the assurance case
- expand tests and CI
- review versioning implications
- update the README

Implementation should not precede acceptance of the architectural decision
unless the work is explicitly exploratory and not intended for merge.

## Upstream CLI maintenance

`gh` and `glab` are external interfaces that can change independently.

Monitor changes involving:

- authentication commands
- token-display flags
- environment variables
- config paths
- config file format
- token refresh behavior
- exit-status behavior
- stdin consumption
- signal behavior
- extension and plugin loading
- API command syntax

### Parent CLI update procedure

When updating or evaluating a new parent CLI version:

1. record the old and new versions
2. run the complete local verification suite
3. run representative real commands through the wrapper
4. inspect authentication-command help for new subcommands or disclosure flags
5. verify GitHub environment-token behavior
6. verify GitLab config read and refresh behavior
7. test one stdin-dependent GitLab API operation
8. test an ordinary nonzero parent exit
9. inspect temporary-state cleanup
10. review upstream release notes for authentication or configuration changes

Representative smoke tests should use non-destructive operations where
possible.

Examples:

```sh
gh-pass auth status
gh-pass repo view
gh-pass api user

glab-pass auth status
glab-pass repo view
glab-pass api user
```

For stdin:

```sh
printf '%s\n' '{}' |
    glab-pass api \
        --method POST \
        --header 'Content-Type: application/json' \
        SAFE_ENDPOINT \
        --input -
```

Use an endpoint and request that cannot cause unintended destructive behavior.

### New authentication commands

When `gh` or `glab` adds an authentication subcommand or option:

1. determine whether it is:
   - ordinary and non-disclosing
   - credential-management
   - credential-disclosure
   - ambiguous
2. fail closed while ambiguous
3. add or update policy tests
4. document the accepted classification
5. create an ADR only if the governing policy changes

Do not allow an unknown authentication operation merely because the parent CLI
accepts it.

## Runtime dependency maintenance

### BusyBox

The CI BusyBox exists to verify `ash` behavior and controlled `PATH` fixture
precedence.

When changing its pinned version:

1. update the source URL
2. update the expected SHA-256 checksum
3. build it through `ci/build-test-busybox.sh`
4. verify the output basename remains `busybox`
5. verify `ash` is available
6. verify external fixture commands take precedence through `PATH`
7. run the complete suite locally
8. allow GitHub Actions to rebuild and verify it independently

Do not replace the test build with a system BusyBox that prefers internal
applets over controlled fixtures.

### ShellCheck

When ShellCheck introduces a new diagnostic:

1. determine whether it identifies a real defect
2. prefer correcting the code over suppressing the warning
3. localize any necessary suppression
4. explain why the suppression is safe
5. preserve POSIX `sh` analysis mode
6. run syntax and behavioral tests after the change

Do not disable a diagnostic globally merely to make CI green.

### POSIX shells

A new supported shell should not be added based only on syntax success.

Support requires:

- syntax verification
- complete behavioral execution
- signal tests
- stdin tests
- failure-injection support
- documented installation and CI availability

## Test maintenance

Tests should encode properties rather than one-off command transcripts.

Good regression statement:

> Standard-input bytes reach the parent CLI unchanged.

Narrow incident statement:

> The metadata JSON request succeeds.

The broader property remains useful across parent commands and future
maintenance.

### Test requirements by affected property

| Affected behavior | Minimum evidence |
|---|---|
| Entry selection | Default, explicit override, invalid override |
| Argument forwarding | Count, order, spaces, empty arguments |
| Standard input | Byte-for-byte round trip under all supported shells |
| Parent status | Exact nonzero status preservation |
| Auth policy | Allowed status, known rejection, unknown fail-closed behavior |
| GitLab staging | Path, directory mode, file mode, config path |
| State validation | Missing, empty, non-regular, fingerprint failure |
| Writeback | Unchanged, changed after success, changed after failure |
| Cleanup | Success, ordinary failure, cleanup failure |
| Signals | HUP, INT, TERM, writeback failure, cleanup failure |
| Installation | Prefixes, `DESTDIR`, ownership, guarded links |

### Fixture discipline

Fixtures should:

- record observable inputs
- expose explicit behavior modes
- avoid relying on real credentials or network services
- fail clearly when configured incorrectly
- remain disabled for optional blocking behavior such as stdin capture
- avoid duplicating wrapper logic

A fixture should not decide whether the wrapper's behavior is correct. It should
record enough evidence for the test to decide.

### Full verification

The accepted interface is:

```sh
make check
```

A compatible BusyBox may be supplied explicitly:

```sh
make check \
    BUSYBOX=/path/to/compatible/busybox
```

Before merging a compatibility-sensitive or security-sensitive change, confirm:

- ShellCheck passes
- Dash syntax passes
- Bash POSIX syntax passes
- BusyBox `ash` syntax passes
- all three behavioral matrices pass
- installation tests pass
- GitHub Actions passes on the pull request

## Threat-model and assurance review

Update [`threat-model.md`](threat-model.md) when a change:

- introduces a new asset
- crosses a new trust boundary
- adds an actor or dependency
- changes transient credential exposure
- changes persistent credential ownership
- changes failure or recovery behavior
- changes installation privileges or locations
- introduces generated artifacts
- invalidates a residual-risk statement

Update [`security-assurance.md`](security-assurance.md) when a change:

- adds or removes a claimed property
- changes an implementation control
- changes supporting test evidence
- changes an accepted limitation
- closes or creates an evidence gap
- changes claim-to-threat traceability

Not every code edit requires rewriting both documents. Review is always
required; modification is required only when their current statements would no
longer be accurate.

## Security-report handling

GitHub private vulnerability reporting is the preferred intake path.

Do not request that reporters disclose suspected vulnerabilities through public
issues.

When a report arrives:

1. acknowledge receipt
2. avoid exposing details publicly
3. reproduce the issue in a controlled environment
4. identify affected versions
5. map the issue to assets, boundaries, and assurance claims
6. determine whether durable credential confidentiality or integrity is at risk
7. develop the smallest safe correction
8. add regression evidence
9. run the full verification interface
10. prepare a patch release
11. coordinate disclosure with the reporter when applicable
12. update security documentation after users have an available correction

Do not promise confidentiality beyond the capabilities of the reporting and
hosting systems.

Do not assign a severity merely from intuition. Consider:

- required attacker access
- credential exposure
- credential modification
- persistence
- user interaction
- exploit reliability
- affected operations
- existing mitigations
- recovery requirements

## Failure triage

When a wrapper operation fails, isolate the failure boundary before changing
code.

### GitHub triage

Check:

1. policy rejection
2. selected entry name
3. `pass` retrieval
4. nonempty first line
5. direct `gh` behavior with equivalent environment
6. parent status and diagnostics

Do not print the token during routine diagnosis.

### GitLab triage

Check:

1. policy rejection
2. selected entry name
3. `/tmp` usability
4. runtime-directory creation
5. directory and file permissions
6. config restoration
7. initial fingerprinting
8. parent arguments and stdin
9. parent status
10. post-command config eligibility
11. change detection
12. writeback
13. cleanup

Compare a failing stdin operation with the same input supplied through a file
when narrowing descriptor-related problems.

### Failure-injection discipline

Before modifying failure precedence:

- reproduce the relevant parent and wrapper failures
- identify the accepted precedence rule
- add or update a test
- verify diagnostics retain useful context
- verify credential material does not appear in diagnostics

## Documentation maintenance

Update the README when user-visible behavior changes, including:

- installation
- supported platforms or shells
- credential setup
- environment overrides
- allowed or rejected commands
- exit statuses
- signal behavior
- security boundaries
- verification commands

Update the changelog for released user-visible changes.

Update architecture documentation when the integrated design changes.

Update ADRs only through a new decision or an explicit status transition. Avoid
rewriting historical rationale to make an older decision appear to have
anticipated later events.

Case studies should preserve the actual sequence of observation,
investigation, correction, verification, and release. They should not be edited
into an unrealistically linear story.

## Versioning decisions

The project uses Semantic Versioning.

Typical version effects:

| Change | Likely increment |
|---|---|
| Documentation correction only | No release required |
| Internal refactor with identical behavior | No release required |
| Backward-compatible defect correction | Patch |
| Backward-compatible new capability | Minor |
| Intentional incompatible public behavior | Major, subject to `0.y.z` policy |
| Security correction | Usually patch unless compatibility requires otherwise |

Version selection should reflect observable behavior, not implementation effort.

A small code change that restores a documented compatibility property can
justify a patch release.

A large internal refactor with no observable change may require no release.

## Release maintenance

The authoritative release process is defined by
[ADR 0013](decisions/0013-versioning-and-release-publication.md).

This guide intentionally does not duplicate every release command.

Before tagging, verify at minimum:

- `VERSION` matches the intended version
- `CHANGELOG.md` contains the dated release entry
- the working tree and index are clean
- the release commit is on `main`
- local verification passes
- GitHub Actions passes for the exact release commit
- GitHub and GitLab `main` resolve to that commit

Then:

- create a signed annotated tag
- verify the tag locally
- push the tag to GitHub and GitLab
- verify both remote tags resolve to the release commit
- publish the canonical GitHub release from the existing tag

Never:

- move a published release tag
- delete and recreate a published release tag
- replace release contents in place
- let the release command create an implicit tag
- publish from a commit that has not passed the required CI check

## GitLab mirror maintenance

GitHub is canonical.

After a GitHub pull request is merged:

```sh
git switch main
git pull --ff-only github main
git push gitlab main
```

Before a release, confirm:

```sh
test "$(git rev-parse github/main)" = "$(git rev-parse HEAD)"
test "$(git rev-parse gitlab/main)" = "$(git rev-parse HEAD)"
```

Release tags are pushed to both remotes.

The GitLab project may have provider-specific metadata identifying it as a
mirror, but source content should not diverge.

Do not maintain separate implementation commits on GitLab.

## Periodic maintenance review

Perform a lightweight review periodically and before significant releases.

Check:

- current `gh` and `glab` versions
- new authentication subcommands or flags
- current ShellCheck diagnostics
- CI health
- BusyBox source availability and checksum
- broken documentation links
- stale supported-version statements
- open private vulnerability reports
- repository ruleset enforcement
- pending Dependabot action updates
- OpenSSF Scorecard findings
- OpenSSF Best Practices badge assessment status
- GitHub and GitLab branch synchronization
- release-tag synchronization
- README examples against current CLI behavior
- threat-model assumptions
- assurance evidence references

The review should produce changes only when evidence shows they are needed.
Avoid adding process or dependencies merely to make the repository appear more
complex.

## Maintenance non-goals

This guide does not require:

- release automation
- dependency bots without meaningful dependency coverage
- a second CI implementation on GitLab
- mandatory self-approval
- code-coverage percentages
- a CLA or DCO
- generated SBOMs for source-only shell releases
- SLSA provenance before generated artifacts exist
- new features solely to demonstrate activity

The maintenance objective is disciplined preservation of the project's security
and compatibility properties, not continuous expansion.

## Related documents

- [`../README.md`](../README.md)
- [`architecture.md`](architecture.md)
- [`project-context.md`](project-context.md)
- [`threat-model.md`](threat-model.md)
- [`security-assurance.md`](security-assurance.md)
- [`case-studies/001-stdin-preservation.md`](case-studies/001-stdin-preservation.md)
- [`decisions/`](decisions/)
- [`../CONTRIBUTING.md`](../CONTRIBUTING.md)
- [`../SECURITY.md`](../SECURITY.md)
- [`../CHANGELOG.md`](../CHANGELOG.md)
