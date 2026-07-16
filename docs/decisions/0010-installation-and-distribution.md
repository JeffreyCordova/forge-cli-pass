# ADR 0010: Use Copy-Based Make Installation and Tagged Source Releases

**Status:** Accepted

## Context

`forge-cli-pass` distributes two executable POSIX shell wrappers:

```text
gh-pass
glab-pass
```

The scripts require no compilation, code generation, or platform-specific binary
build.

The project nevertheless needs a defined installation and distribution
interface that supports:

- unprivileged user-local installation
- deliberate system-wide installation
- package-manager staging
- predictable installation paths
- safe removal of installed commands
- development from a working checkout
- tagged source releases
- future third-party packaging

The installation process must remain separate from credential bootstrap and
runtime authentication.

Installing the wrappers must not:

- create or move `pass` entries
- decrypt credential material
- invoke GitHub CLI or GitLab CLI authentication
- populate parent CLI configuration
- modify shell startup files
- change `PATH`
- configure Git or Docker credential helpers
- contact a forge or other network service

The project also needs to distinguish a stable normal installation from a
development workflow in which commands follow changes in a working checkout.

## Decision

The project will provide:

1. a copy-based normal installation through `make install`
2. a path-configurable packaging interface using `PREFIX`, `BINDIR`, and
   `DESTDIR`
3. a narrowly scoped `make uninstall`
4. a separate symlink-based `make dev-install`
5. a guarded `make dev-uninstall`
6. tagged source releases installable through the same Makefile

The installed programs remain plain shell scripts.

The installation process does not transform their contents.

## Canonical executable sources

The canonical executable source files are:

```text
src/gh-pass
src/glab-pass
```

Each source file must:

- contain its final `#!/bin/sh` shebang
- be usable directly from a source checkout
- contain the same program content installed for users
- pass the verification requirements established by ADR 0004
- not require generated runtime files

Normal installation copies these files to the selected binary directory.

Development installation creates symbolic links to these files.

## Makefile interface

The repository root will contain a `Makefile` providing at least these public
targets:

```text
install
uninstall
dev-install
dev-uninstall
check
```

Additional internal or convenience targets may be introduced when documented,
but they must not change the meaning of the accepted public targets
silently.

The Makefile is an installation and development interface. It is not a runtime
dependency of the installed wrappers.

## Installation variables

The initial installation variables are:

```make
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
DESTDIR ?=
```

Their roles are distinct.

### `PREFIX`

`PREFIX` represents the installation prefix as it will appear on the target
system.

The default is:

```text
/usr/local
```

A user-local installation may instead use:

```text
$HOME/.local
```

A distribution package commonly uses:

```text
/usr
```

### `BINDIR`

`BINDIR` represents the binary directory within the target installation.

Its default is:

```make
$(PREFIX)/bin
```

It may be overridden independently when required by an operator or packaging
environment.

### `DESTDIR`

`DESTDIR` is a staging root prepended during installation or removal.

Its default is empty.

It is intended primarily for package construction and filesystem-image
staging.

`DESTDIR` does not alter the runtime installation prefix represented by
`PREFIX`.

For example:

```sh
make install DESTDIR="$pkgdir" PREFIX=/usr
```

installs into:

```text
$pkgdir/usr/bin
```

while representing a final target-system installation under:

```text
/usr/bin
```

## Normal installation

The normal installation interface is:

```sh
make install
```

The installation target will:

1. create the selected binary directory when necessary
2. copy `src/gh-pass` to the selected destination
3. copy `src/glab-pass` to the selected destination
4. install both commands with mode `0755`

The observable installation behavior is equivalent to:

```make
install:
	install -d "$(DESTDIR)$(BINDIR)"
	install -m 0755 src/gh-pass "$(DESTDIR)$(BINDIR)/gh-pass"
	install -m 0755 src/glab-pass "$(DESTDIR)$(BINDIR)/glab-pass"
```

The implementation may define reusable Make variables, but it must preserve the
same installation contract.

Installation replaces an existing destination file when the selected
installation utility normally permits that replacement.

The installer does not attempt to determine whether an existing destination
belongs to another package or installation. Operators and package managers are
responsible for choosing non-conflicting destinations.

## User-local installation

The documentation will present unprivileged installation prominently:

```sh
make install PREFIX="$HOME/.local"
```

This installs:

```text
$HOME/.local/bin/gh-pass
$HOME/.local/bin/glab-pass
```

The project must not assume that:

```text
$HOME/.local/bin
```

is already present in `PATH`.

The installation process will not modify:

- `.profile`
- `.bashrc`
- `.zshrc`
- shell framework configuration
- desktop-session environment files
- system-wide environment configuration

Any required `PATH` configuration remains an explicit operator action.

## System-wide installation

The default prefix permits a conventional system-local installation:

```sh
make install
```

when the selected destination is writable.

An operator may deliberately use privilege escalation:

```sh
sudo make install
```

The Makefile itself must never invoke:

```text
sudo
doas
su
pkexec
```

or another privilege-escalation mechanism.

Privilege selection and authorization belong to the operator, packaging system,
or deployment environment.

## Package-manager staging

The Makefile will support staged package construction through `DESTDIR`.

Example:

```sh
make install DESTDIR="$pkgdir" PREFIX=/usr
```

Expected installed paths:

```text
$pkgdir/usr/bin/gh-pass
$pkgdir/usr/bin/glab-pass
```

The installation target must not:

- write outside the resolved `DESTDIR` and installation directories
- invoke network services
- access the operator's credentials
- depend on the operator's normal `HOME`
- run either installed wrapper
- invoke `pass`, `gh`, `glab`, or GPG

This allows third-party packaging systems to stage the project without
credential access or network activity.

## Normal uninstallation

The normal removal interface is:

```sh
make uninstall
```

It removes only:

```text
$(DESTDIR)$(BINDIR)/gh-pass
$(DESTDIR)$(BINDIR)/glab-pass
```

The observable behavior is equivalent to:

```make
uninstall:
	rm -f \
	    "$(DESTDIR)$(BINDIR)/gh-pass" \
	    "$(DESTDIR)$(BINDIR)/glab-pass"
```

Normal uninstall must not:

- recursively remove `BINDIR`
- remove `PREFIX`
- remove parent directories
- remove files other than the two command paths
- inspect or delete `pass` entries
- modify GitHub CLI or GitLab CLI state
- remove user-created aliases or shell functions
- remove package-manager metadata
- contact a network service

The target cannot prove that an existing file at one of the destination paths
still belongs to the project.

Operators and package managers remain responsible for invoking uninstall with
the same path variables used for installation.

## Development installation

The repository will provide a separate development installation interface:

```sh
make dev-install
```

A typical user-local invocation is:

```sh
make dev-install PREFIX="$HOME/.local"
```

The target creates symbolic links from the selected binary directory to the
canonical source files in the current checkout.

Example:

```text
$HOME/.local/bin/gh-pass
    -> /home/user/src/forge-cli-pass/src/gh-pass

$HOME/.local/bin/glab-pass
    -> /home/user/src/forge-cli-pass/src/glab-pass
```

The symbolic-link targets must use absolute paths derived from the physical
checkout location.

They must not depend on:

- the caller's later working directory
- a relative path from `BINDIR`
- shell aliases
- an unresolved relative repository path

The Makefile may derive the physical checkout path using a tested combination
of shell directory changes and:

```sh
pwd -P
```

The exact mechanism must be verified on the supported Linux development
platform.

## Development-install behavior

`dev-install` is a development convenience, not the normal installation model.

Its consequences must be documented:

- working-tree edits affect command execution immediately
- uncommitted code may execute
- changing branches may change installed behavior
- moving or deleting the checkout breaks the links
- checkout ownership and permissions become part of the runtime trust boundary
- a compromised working tree compromises the linked commands

The target may replace an existing destination only under an explicitly
documented policy.

At minimum, it must not silently replace an unrelated regular file.

A safe implementation should fail when the destination exists unless it is
already the expected development symlink or the operator has deliberately
removed the conflicting path.

## Development uninstallation

The development removal interface is:

```sh
make dev-uninstall
```

It must be more conservative than normal uninstall.

For each command, `dev-uninstall` will remove the destination only when the
destination is a symbolic link associated with the corresponding canonical
source file in the current checkout.

It must not remove:

- a copied normal installation
- a regular file
- a directory
- a symbolic link into another checkout
- an unrelated symbolic link
- a destination whose ownership cannot be established safely

When a destination exists but does not match the expected development link, the
target must leave it unchanged and report the mismatch.

The exact link-verification mechanism must be:

- compatible with the accepted Linux installation environment
- resistant to path-comparison mistakes
- covered by automated tests
- documented if it introduces another installation dependency

## Installation scope

The initial normal installation installs only:

```text
gh-pass
glab-pass
```

The target does not install:

- credential entries
- example credentials
- authentication state
- aliases
- shell functions
- desktop files
- services
- scheduled tasks
- Git credential-helper configuration
- Docker credential-helper configuration
- parent CLI configuration
- shell completion files
- man pages

Man pages, shell completions, and other installed documentation may be added
later through documented paths and targets.

Adding them must not silently broaden the ownership or removal scope of the
existing targets.

## Credential bootstrap boundary

Installation and credential bootstrap are separate operations.

No installation target may:

- invoke `pass show`
- invoke `pass insert`
- invoke `pass mv`
- initialize a password store
- generate a GPG key
- invoke `gh auth login`
- invoke `glab auth login`
- import authentication state
- validate live credentials
- run an authenticated forge command

Credential creation, import, replacement, recovery, and revocation remain
documented operational procedures governed by the relevant credential
architecture decisions.

This separation ensures that package installation can occur without access to
credential material.

## Build and installation dependencies

The installed wrappers have the runtime dependencies defined by ADR 0004 and
the provider-specific architecture.

Source installation additionally requires a tested Make implementation and
ordinary installation utilities.

The initial installation environment assumes:

```text
make
install
rm
ln
pwd
```

The Makefile may also use baseline POSIX shell functionality for straightforward
path and filesystem operations.

The initial tested Make implementation may be GNU Make on Linux.

The project must not claim compatibility with BSD Make or another Make
implementation until the complete public target interface has been tested
there.

The Makefile should avoid unnecessary implementation-specific extensions where
a clear portable expression is practical, but untested portability must not be
claimed.

## `check` target

The repository will provide:

```sh
make check
```

as the primary local verification entry point.

It should run the project's established static and behavioral checks, including
those required by accepted architecture decisions.

The exact test implementation may evolve, but `make check` must remain suitable
for:

- local development
- continuous integration
- release preparation
- package-maintainer verification

The target must not:

- access real credentials
- use the real password store
- contact GitHub or GitLab
- require a production account
- modify normal parent CLI state

A failed check must produce a nonzero status.

## Distribution unit

The initial distribution unit is a source checkout or source release archive.

A release archive must contain the files required to inspect, test, and install
the project, including at least:

```text
Makefile
src/
tests/
docs/
README.md
CONTRIBUTING.md
LICENSE
```

When present, it should also include:

```text
SECURITY.md
CHANGELOG.md
```

and other release-relevant repository files.

The executable scripts under `src/` are the distributable programs.

The project does not require generated binary artifacts.

## Release model

The initial project release model consists of:

- versioned Git tags
- GitHub as the primary public release location
- corresponding tags mirrored to GitLab
- source archives associated with released tags
- installation from an unpacked release archive using `make install`

A normal stable installation should use a released tag or archive rather than
an arbitrary state of the default branch.

The exact policies for:

- version numbering
- release notes
- tag signing
- archive checksums
- provenance attestations
- release automation

require a separate release-management decision.

## Repository mirrors

GitHub remains the primary upstream repository under the accepted project
workflow.

GitLab is maintained as a mirror.

Release tags intended to appear on both forges must refer to the same commit.

The installation system does not embed assumptions about the hosting forge and
must work from an unpacked source tree without network access.

## Initially excluded distribution methods

The project will not initially provide or recommend:

- `curl | sh`
- `wget | sh`
- another remote shell installer
- automatic self-update
- installation by executing code directly from the default branch
- project-maintained Debian repositories
- project-maintained RPM repositories
- project-maintained Homebrew taps
- project-maintained Arch User Repository packages
- Snap packaging
- Flatpak packaging
- AppImage packaging
- standalone compiled bundles

Third parties may create packages using the documented `DESTDIR` interface.

Such packages are not automatically official project releases.

## Alternatives considered

### Document only manual copy commands

Potential advantages included:

- no Make dependency
- minimal repository machinery
- transparent installation steps

Rejected because:

- documentation would duplicate installation logic
- packaging systems would lack a conventional staging interface
- permissions and path handling could drift between examples
- uninstall behavior would remain informal
- verification targets would lack a common entry point

Manual copying may still be documented as an advanced fallback, but it is not
the primary installation interface.

### Use symbolic links for every installation

Rejected because:

- moving or deleting the checkout breaks installed commands
- uncommitted changes immediately affect production use
- branch changes alter installed behavior
- source checkout permissions remain part of the runtime path
- release archives no longer correspond directly to copied installed files

Symlinks remain available only through the explicit development interface.

### Provide a dedicated installer script

Rejected because the current installation requirements are fully represented by
a small Makefile.

A separate installer would add:

- another executable interface
- duplicated path and permission logic
- another security-review surface
- additional documentation and compatibility obligations

### Install through a remote shell pipeline

Rejected because it combines download and execution into one operation and
creates unnecessary transport, provenance, and auditability concerns.

The project instead distributes inspectable source archives.

### Require a native package manager

Rejected because maintaining official packages across multiple distributions
would add significant release and infrastructure obligations.

The Makefile provides the staging primitives needed by future package
maintainers.

### Perform credential setup during installation

Rejected because installation should not require credential access, interactive
authentication, or network connectivity.

Combining installation and credential bootstrap would weaken separation of
responsibilities and complicate packaging.

### Automatically modify `PATH`

Rejected because shell startup configuration is operator-owned and differs by
shell, login environment, and platform.

## Consequences

### Positive

- Installation has one conventional documented interface.
- User-local installation does not require privilege escalation.
- System and packaging paths can be configured explicitly.
- `DESTDIR` supports staged package construction.
- Installed commands are stable copies rather than working-tree references.
- Development symlinks remain available through an explicit target.
- Normal uninstall has a narrow ownership scope.
- Development uninstall protects unrelated destinations.
- Installation requires no credentials or network access.
- Release archives contain the exact executable source files.
- Third-party packaging can reuse the same installation interface.

### Negative

- Source installation requires `make` and installation utilities.
- The Makefile becomes part of the project's public interface.
- Development-link verification adds implementation and test complexity.
- Normal uninstall cannot prove file ownership.
- Operators must configure `PATH` themselves when necessary.
- Native package-manager integration is not provided initially.
- GNU Make may be the only initially tested Make implementation.
- Release-management details still require a separate decision.

## Security implications

Copy-based installation limits stable command execution to the files placed in
the selected installation directory.

Development symlinks deliberately expand the runtime trust boundary to the
working checkout and must be clearly identified as a development mechanism.

The installation system must:

- quote filesystem paths correctly
- avoid command evaluation
- avoid unsafe wildcard expansion
- avoid writing outside selected installation paths
- avoid invoking privilege escalation
- avoid accessing credential material
- avoid network activity
- avoid silently replacing unrelated files during development installation
- avoid deleting unrelated files during development uninstallation

A user invoking:

```sh
sudo make install
```

trusts the repository's Makefile and installation recipes with elevated
filesystem privileges.

Release documentation should therefore encourage inspection of source and use
of authenticated release references when those policies are established.

The project does not claim that Makefile-based installation provides package
ownership tracking, rollback, or tamper detection.

Those responsibilities belong to a package manager or deployment system.

## Verification requirements

Tests must cover the installation interface on the supported Linux development
platform.

### Normal installation

- default installation resolves beneath `/usr/local`
- custom `PREFIX` changes the installation prefix
- custom `BINDIR` changes the command directory
- `DESTDIR` prepends a staging root
- both commands are installed
- installed commands have mode `0755`
- installed contents match the canonical source files
- installation creates the binary directory when absent
- installation performs no credential or network operation

Tests must use an isolated writable staging destination rather than modify the
real system prefix.

### User-local installation

- `PREFIX` values containing spaces are handled safely where supported
- installation does not edit shell startup files
- installation does not modify `PATH`
- installation does not invoke privilege escalation

### Normal uninstallation

- only `gh-pass` and `glab-pass` destination paths are removed
- the binary directory remains
- parent directories remain
- unrelated files remain
- missing destinations do not cause destructive fallback behavior
- `DESTDIR`, `PREFIX`, and `BINDIR` resolve consistently with installation
- credential state remains untouched

### Development installation

- links target the canonical source files
- link targets are absolute
- physical checkout paths are used
- calling from another working directory does not affect the links
- moving or removing the checkout demonstrates the documented broken-link
  behavior
- unrelated regular destination files are not silently replaced
- development installation performs no credential or network operation

### Development uninstallation

- expected links into the current checkout are removed
- copied installations are retained
- regular files are retained
- directories are retained
- links into another checkout are retained
- unrelated links are retained
- mismatches produce useful diagnostics
- parent directories remain

### Packaging interface

- `make install DESTDIR=<staging-root> PREFIX=/usr` produces the expected staged
  paths
- no files are written outside the staging root
- staged files are directly usable after installation into the represented
  prefix
- packaging does not require a normal user home directory
- packaging does not access credentials or network services

### Verification target

- `make check` returns success when all checks pass
- `make check` returns nonzero when a check fails
- it uses no real credentials
- it uses no real password store
- it performs no network requests
- it is suitable for CI execution

### Release archive

Before release:

- the archive contains the required installation files
- the archive contains the accepted decision records
- `make check` succeeds from an unpacked archive
- staged installation succeeds from an unpacked archive
- installed files match the source files from the tagged release
- no untracked local files are required to install or test the release

## Relationship to other decisions

This ADR operates within:

- ADR 0001's provider-specific command model
- ADR 0002's accepted project and command names
- ADR 0004's POSIX shell and Linux runtime contract
- ADR 0009's credential-entry configuration model

Installation does not alter:

- the authoritative credential store defined by ADR 0003
- GitLab runtime-state behavior defined by ADR 0005
- failure semantics defined by ADR 0006
- signal-time writeback defined by ADR 0007
- credential-management restrictions defined by ADR 0008

A separate decision will govern release versioning, signing, checksums, and
release-publication procedures.

## Decision summary

`forge-cli-pass` uses copy-based normal installation through:

```sh
make install
```

The installation interface supports:

```text
PREFIX
BINDIR
DESTDIR
```

and installs `src/gh-pass` and `src/glab-pass` as mode-`0755` commands.

Normal uninstall removes only those two command paths.

Development workflows use separate symlink-based `dev-install` and guarded
`dev-uninstall` targets.

Installation performs no credential, authentication, shell-configuration, or
network operations.

Initial distribution consists of versioned tagged source releases installable
through the same Makefile.
