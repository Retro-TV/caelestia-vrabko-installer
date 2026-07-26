## Summary

Describe the user-facing change and why it is needed.

## Security and Privilege Impact

Describe changes to sudo usage, sources, checksums, network exposure, services,
credentials, package ownership, backups, or trust boundaries. Write `None` when
not applicable.

## Validation

- [ ] `bash -n install.sh validate.sh tests/*.sh packages/*/PKGBUILD`
- [ ] `shellcheck install.sh validate.sh tests/*.sh`
- [ ] Security and repository fixtures pass
- [ ] Both bundled profile dry-runs pass
- [ ] Package/source CI is expected to pass
- [ ] Documentation, changelog, and version locks are updated when needed
- [ ] No credentials, personal configuration, wallpapers, or build output added

## Test Environment

List distribution, architecture, GPU, profile, and commands run.
