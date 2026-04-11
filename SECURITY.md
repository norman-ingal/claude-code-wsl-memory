# Security Policy

## Dependency Update Policy

**Do not update dependencies just because a newer version exists.**

The XZ Utils attack (CVE-2024-3094) was delivered via a legitimate release from a trusted
maintainer. Auto-updating to "latest" is itself an attack vector.

Update a dependency only when:
- A vulnerability scanner (`pip-audit`, `npm audit`, etc.) identifies a CVE in the pinned version, **or**
- A security advisory is published for the package

When updating:
1. **Wait 7–14 days** after the new release — give the community time to find issues
2. **Check the changelog** for the version range — look for unexpected scope changes
3. **Check for maintainer changes** — a new maintainer on a previously stable package is a red flag
4. **Review the diff** between the old and new release tag on GitHub
5. **Regenerate the lock file** and verify hashes changed only for the updated package(s)
6. **Test locally** before merging

Dependabot PRs are for awareness only — **never auto-merge**.

## Secrets Rules

- All secrets in `.env` files — never committed
- No hardcoded tokens, passwords, or API keys anywhere in the codebase
- Rotate any key that is accidentally committed immediately

## Reporting a Vulnerability

Open a private security advisory:
`github.com/norman-ingal/<repo>/security/advisories/new`

Do not open a public issue for security vulnerabilities.
