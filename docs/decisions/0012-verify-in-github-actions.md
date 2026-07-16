# ADR 0012: Verify the project in GitHub Actions

## Status

Accepted

## Context

`forge-cli-pass` has a complete local verification interface through `make check`.

That interface checks:

- POSIX shell linting
- Syntax under Dash, Bash POSIX mode, and BusyBox `ash`
- Wrapper behavior under all three shells
- Installation and development-link behavior

The behavioral test suite injects controlled utility failures through `PATH`. Some distribution BusyBox builds execute internal applets before external commands found through `PATH`, making those builds unsuitable for the failure-injection harness even though they may still run the production wrappers correctly.

The GitHub repository is the primary upstream repository. The GitLab repository is a mirror.

Continuous integration should reproduce the accepted local verification interface without requiring forge credentials, password-store contents, persistent secrets, or network access to GitHub and GitLab APIs.

## Decision

The primary GitHub repository runs continuous verification through GitHub Actions.

The workflow runs for:

- Pull requests
- Pushes to `main`
- Explicit manual dispatches

The workflow grants the GitHub-provided token read-only repository-content access.

External GitHub Actions are pinned to reviewed full commit identifiers rather than mutable branch or major-version references.

The workflow builds a test-only BusyBox executable from the official BusyBox 1.36.1 source archive.

The source archive is verified against this SHA-256 digest before extraction:

```text
b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314
```

The BusyBox build begins with `defconfig`. It explicitly disables the unrelated `tc` applet and requires these shell execution features to remain disabled:

```text
CONFIG_FEATURE_PREFER_APPLETS
CONFIG_FEATURE_SH_STANDALONE
CONFIG_FEATURE_SH_NOFORK
```

The builder verifies that the `busybox` and `ash` applets remain enabled and that the resulting shell honors external `PATH` precedence before making the executable available to the project test suite.

CI then invokes the same public verification interface used locally:

```sh
make check BUSYBOX=/path/to/ci/busybox
```

The GitLab mirror does not initially run a duplicate CI pipeline. GitHub Actions is the canonical automated verification result.

CI does not receive or exercise real credentials. All wrapper behavior continues to be tested with isolated fixtures and synthetic authentication material.

## Consequences

Local and automated verification share one authoritative entry point.

The supported shell matrix and installation tests run for every proposed change to the primary repository.

The CI environment does not depend on the configuration choices made by a distribution BusyBox package.

BusyBox source retrieval is an external network dependency. Its version and digest are explicit, reviewed repository inputs.

Upgrading the CI BusyBox version requires changing both the version and expected digest and rerunning the complete verification suite.

A GitLab pipeline may be added later if independent mirror verification provides enough value to justify duplicate execution and maintenance.

Release publication remains outside this workflow and requires a separate decision and permission model.
