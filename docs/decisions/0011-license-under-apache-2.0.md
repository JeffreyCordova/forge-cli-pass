# ADR 0011: License the project under Apache-2.0

## Status

Accepted

## Context

`forge-cli-pass` is intended for public use, modification, packaging, and contribution.

The project needs a clear repository-wide license before publishing its first tagged release. The license should permit broad commercial and noncommercial reuse while providing explicit terms for contributions, redistribution, notices, and relevant patent rights.

The repository also needs a machine-readable license identifier that source scanners and packaging systems can recognize consistently.

## Decision

`forge-cli-pass` is licensed under the Apache License, Version 2.0.

The canonical SPDX identifier is:

```text
Apache-2.0
```

The repository includes the complete unmodified Apache License 2.0 text in the root `LICENSE` file.

Repository-authored source, test, fixture, and build files use this SPDX comment where the file format permits comments:

```text
SPDX-License-Identifier: Apache-2.0
```

Documentation is covered by the repository license unless a file explicitly states otherwise.

Contributions intentionally submitted for inclusion in the project are accepted under Apache-2.0 unless separately agreed in writing.

The project does not initially distribute a `NOTICE` file because it has no separate attribution notices requiring one.

## Consequences

Users may use, reproduce, modify, and distribute the project subject to Apache-2.0.

Contributors and downstream distributors must follow the license’s applicable notice, attribution, modification, and redistribution requirements.

Third-party material added later must have compatible licensing and must retain any notices required by its own license.

A future licensing change would require a new decision record and consideration of rights held by existing contributors.
