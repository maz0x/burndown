# Anthropic terms: what we know, and Burndown's posture

Researched 2026-07-25 for the public release. Facts first, then how Burndown
positions itself.

## Verified facts

- **February 2026**: Anthropic sent a legal request to OpenCode (a third-party
  coding client) that led it to remove Claude OAuth support; OpenClaw was
  similarly affected. Those tools use a subscriber's OAuth token to RUN
  INFERENCE (spend the subscription) inside a third-party client.
  Sources: OpenCode's own commit messages; daveswift.com/claude-oauth-update.
- **March 2026**: a claude-code GitHub issue (#31637) about the
  `/api/oauth/usage` endpoint's aggressive rate limits was closed "not
  planned" with no staff comment. No commitment to support third-party
  polling, and no statement banning it.
- **No documented enforcement against read-only usage monitors.** Tools in
  Burndown's exact class remain public and popular: ccusage (local logs
  only), Claude-Code-Usage-Monitor (same usage endpoint), claude-meter, and
  others. None are known to have received legal requests as of this writing.

## The distinction that matters

Burndown is a READ-ONLY monitor. It never runs inference with the token,
never spends the subscription from outside Claude's own apps, and only asks
"how much have I used". The February enforcement targeted the other class:
clients that displace Claude Code itself. That distinction is real but it is
Anthropic's to draw, not ours; they could decide differently at any time.

## Burndown's risk posture (implemented, not aspirational)

1. Live mode is opt-in; a fresh install contacts nothing.
2. The mechanism is disclosed in plain English in the README, the Privacy
   doc, and the welcome tour. No user can end up here unknowingly.
3. Polling is gentle (>= 20s floor, backoff on 429) and stops the moment the
   user signs out; sign-out actually sticks.
4. The app never spends the Claude Code refresh token, so it cannot break
   the user's own Claude Code login.
5. If Anthropic changes or closes the endpoint, the app degrades to
   estimate-only mode (local logs) and keeps working.
6. The app is free and open source; there is no commercial exploitation of
   the endpoint.

## Residual risk, stated honestly

Anthropic could rate-limit, block, or object to this usage at any time, and
could in principle flag accounts that use it. Nothing here is legal advice.
If Anthropic reaches out with any request, the project will comply promptly,
as OpenCode did.

## Hardening ideas (not yet done)

- Try narrowing the requested OAuth scopes at sign-in to the minimum the
  usage endpoint needs (currently mirrors Claude Code's own scope set).
  Needs careful testing; a wrong scope set breaks the token exchange.
- Offer an estimate-only build flag for anyone who wants zero network
  capability compiled in.
