# Security policy

## Reporting a vulnerability

Please report security issues privately, not as a public issue.

Use [GitHub's private vulnerability reporting](https://github.com/maz0x/burndown/security/advisories/new)
on this repository. It is visible only to the maintainer until a fix ships.

Expect an acknowledgement within a week. This is a small project maintained by one
person, so please allow reasonable time for a fix before disclosing publicly.

## Supported versions

Only the latest release gets fixes. Older versions are not patched.

## What is worth reporting

Burndown reads a Claude subscription's usage figures and keeps everything on the
machine it runs on, so the interesting surfaces are:

- Anything that exposes the OAuth token or the Admin API key, including through the
  diagnostic log, an export, a crash, or a file written with the wrong permissions.
- Anything that lets another local process read credentials or usage data.
- A flaw in the updater: signature or checksum verification that can be bypassed, or a
  path that installs a bundle it did not verify.
- A path that writes or deletes outside `~/.config/burndown` without the user asking.

## What is already known and documented

These are not vulnerabilities, they are stated limitations:

- **Releases are ad-hoc signed, not Developer ID signed or notarized.** There is no
  paid Apple Developer account behind this project yet, so macOS quarantines a
  downloaded copy and a release cannot be verified against a known developer identity.
  Building from source avoids the question entirely.
- **Credentials live in files, not the Keychain.** The OAuth token and the Admin API
  key are stored in `~/.config/burndown` at mode 600 inside a mode 700 directory. Any
  process running as the same user can read them, which is true of most CLI tools but
  is weaker than the Keychain. Moving them is on the roadmap.
- **The usage endpoint is undocumented.** Burndown reads the same server-side figures
  behind Claude's own usage page. It is read-only and never spends the subscription,
  but the endpoint carries no compatibility promise and can change without notice.
