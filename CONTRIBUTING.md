# Contributing

Contributions are welcome when they preserve the installer's fail-closed,
reviewable behavior.

## Before Opening a Pull Request

1. Open an issue for substantial behavior or trust-model changes.
2. Never include credentials, personal configuration, generated packages, or
   wallpapers.
3. Keep upstream sources immutable and checksum-pinned.
4. Do not add runtime AUR helpers, remote shell pipelines, or automatic public
   network exposure.
5. Update documentation, tests, `versions.lock`, and the changelog as needed.

## Local Validation

Run on an Arch-based development system:

```bash
bash -n install.sh validate.sh tests/*.sh packages/*/PKGBUILD
shellcheck install.sh validate.sh tests/*.sh
tests/security-fixtures.sh
tests/repository-fixtures.sh
./install.sh --profile profiles/minimal.profile --dry-run
./install.sh --profile profiles/vrabko.profile --dry-run
```

Package or patch changes must also pass `makepkg --verifysource`, clean package
builds, both AW/official transition directions, and managed-update refusal in
the GitHub Actions workflow.

## Pull Requests

Explain the user-facing change, privilege/security impact, test environment,
and exact commands run. Keep unrelated changes separate. Security reports must
follow [SECURITY.md](SECURITY.md), not a public issue or pull request.
