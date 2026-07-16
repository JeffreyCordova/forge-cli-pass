# Changelog

All notable changes to `forge-cli-pass` are documented in this file.

The project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.1] - 2026-07-16

### Fixed

- Preserve standard input passed through `glab-pass`, including piped request
  bodies used by commands such as `glab api --input -`.

## [0.1.0] - 2026-07-16

### Added

- `gh-pass`, a command-compatible GitHub CLI wrapper that retrieves its token
  from `pass` and injects only the first credential line through `GH_TOKEN`.
- `glab-pass`, a command-compatible GitLab CLI wrapper that restores complete
  opaque authentication state into a private runtime directory.
- GitLab authentication-state writeback after successful and ordinarily
  unsuccessful parent execution.
- Conditional GitLab writeback during handled `HUP`, `INT`, and `TERM`
  processing.
- Explicit authentication-command policy that permits non-disclosing
  `auth status` operations while rejecting credential management and
  disclosure.
- Default password-store entries with explicit environment-variable
  overrides.
- Copy-based installation and narrow uninstall targets.
- Guarded development symlink installation and removal.
- Behavioral verification under Dash, Bash POSIX mode, and BusyBox `ash`.
- Installation and development-link verification.
- GitHub Actions continuous integration using a checksum-verified test-only
  BusyBox build.
- Architecture documentation and accepted Architecture Decision Records.
- Security reporting and threat-boundary documentation.
- Apache License 2.0 licensing with SPDX identifiers.

[Unreleased]: https://github.com/JeffreyCordova/forge-cli-pass/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/JeffreyCordova/forge-cli-pass/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/JeffreyCordova/forge-cli-pass/releases/tag/v0.1.0
