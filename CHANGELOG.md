# Changelog

All notable project changes are documented here. Versions follow Semantic
Versioning while the project is pre-1.0.

## [Unreleased]

## [0.2.6] - 2026-07-26

### Fixed

- Consumed every `makepkg --packagelist` result so automatic debug archives do
  not trigger a broken pipe while selecting the primary package.
- Restricted temporary dots cleanup to the top-level installer process so an
  inherited subshell error trap cannot remove verified inputs prematurely.

## [0.2.5] - 2026-07-26

### Fixed

- Built replacement shell archives without requiring their paired CLI package
  to be installed before the final dependency-enforcing package transaction.
- Updated CI to exercise the installer's build-both-before-switch ordering.

## [0.2.4] - 2026-07-26

### Fixed

- Installed pinned-package runtime and build dependencies in the initial package
  transaction so unattended profiles do not encounter late sudo prompts.
- Selected the requested package archive when current Arch `makepkg` also emits
  an automatic debug archive.

## [0.2.3] - 2026-07-26

### Changed

- Replaced cryptic free-form locale and keyboard prompts with labeled English,
  Slovenian, and custom choices.
- Expanded browser, gaming, communication, development, Caelestia package, and
  OpenCode menus to explain exactly what each selection installs or enables.

## [0.2.2] - 2026-07-26

### Added

- Fail-closed VirtIO, QEMU, QXL, VMware, VirtualBox, and Hyper-V graphics
  detection when the system is positively identified as a virtual machine.
- Mesa software Vulkan packages for supported virtual GPU installations.

## [0.2.1] - 2026-07-26

### Added

- Public contribution, support, conduct, issue, and pull-request guidance.
- Dependabot monitoring for SHA-pinned GitHub Actions.
- CI scheduling, least-privilege permissions, concurrency, and time limits.
- Explicit update, troubleshooting, and uninstall documentation.

### Changed

- Installer metadata and managed dots branches now consistently use `0.2.1`.
- Preference profiles now use schema version 2 after removal of the media option.
- Quick installation is formatted as an auditable immutable-commit bootstrap.

### Removed

- All bundled and generated starter wallpapers and their profile option.

[Unreleased]: https://github.com/Retro-TV/caelestia-vrabko-installer/compare/v0.2.6...HEAD
[0.2.6]: https://github.com/Retro-TV/caelestia-vrabko-installer/releases/tag/v0.2.6
[0.2.5]: https://github.com/Retro-TV/caelestia-vrabko-installer/releases/tag/v0.2.5
[0.2.4]: https://github.com/Retro-TV/caelestia-vrabko-installer/releases/tag/v0.2.4
[0.2.3]: https://github.com/Retro-TV/caelestia-vrabko-installer/releases/tag/v0.2.3
[0.2.2]: https://github.com/Retro-TV/caelestia-vrabko-installer/releases/tag/v0.2.2
[0.2.1]: https://github.com/Retro-TV/caelestia-vrabko-installer/releases/tag/v0.2.1
