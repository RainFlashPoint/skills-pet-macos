# Releasing

This project uses lightweight GitHub releases.

## Recommended versioning

- Use `v0.x.y` while the app is still evolving quickly
- Bump `x` for visible feature groups
- Bump `y` for fixes, polish, or documentation-only updates

## Release checklist

1. Confirm the app still opens from Xcode or `bash scripts/build.sh`
2. Review `README.md` and preview assets
3. Update release notes in `docs/releases/`
4. Commit all source, asset, and docs changes
5. Push `main` to GitHub
6. Create a Git tag such as `v0.1.0`
7. Create a GitHub Release and paste the matching notes file

## Commands

```bash
git checkout main
git pull
git tag v0.1.0
git push origin main --tags
```

## GitHub Release body

Use the matching file under `docs/releases/` as the release body, for example:

```text
docs/releases/v0.1.0.md
```
