# Burndown privacy

Everything stays on this Mac. Never synced, never uploaded.

## What Burndown reads

- **Your local Claude logs.** Claude Code keeps session logs under `~/.claude`
  on this Mac. Burndown reads them (read-only) to estimate your usage. This
  works with no network and no sign-in.
- **Claude's usage service (optional, off by default on a fresh install).**
  If you sign in, or explicitly choose "Use my Claude Code sign-in", Burndown
  asks Claude's own usage endpoint for your exact limits, using your account.

## What Burndown never does

- It never sends your data anywhere. The only servers it ever talks to are
  Anthropic's (`claude.ai`, `api.anthropic.com`, `console.anthropic.com`),
  and only when live usage is on.
- One exception, and it carries nothing about you or your usage: the updater
  asks `api.github.com` for the latest version number (once a day if automatic
  updates are on, otherwise only when you press Check now), and downloads the
  release file from `github.com` if you choose to install it.
- It never logs your token or password. Sign-in happens in your browser with
  Anthropic; Burndown only receives the resulting token.

## Where things are stored

- Usage history and caches: `~/.config/burndown/`, readable only by your
  user account (permissions 600).
- Your sign-in token: stored privately on this Mac and deleted when you sign
  out. Signing out also stops Burndown from borrowing the Claude Code
  sign-in until you explicitly reconnect.
- Diagnostic logs: `~/.config/burndown/*.log`, private to your user,
  size-capped, never contain your token, and emptied on sign-out. You can
  also clear everything from Settings, Charts, "Reset chart history and
  logs".

## Consent

- A fresh install contacts nothing until you choose to connect.
- "Use my Claude Code sign-in" reads the credential Claude Code already
  keeps on this Mac, only after you click it, and stops the moment you sign
  out.

Burndown is an independent project. It is not affiliated with, endorsed by,
or sponsored by Anthropic.
