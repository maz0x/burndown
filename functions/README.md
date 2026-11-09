# Pages Functions

Cloudflare Pages serves this repo's `site/` directory as the live site and runs anything in this
`functions/` directory as an edge Function. The two are siblings on purpose: `site/` is the build
output directory in the Pages project settings, `functions/` is read from the project root, so this
directory must stay at the top level of the repo and must never be moved inside `site/`.

Today there is one Function.

## `go/[[slug]].js` - counted download links

Every link we hand out points here instead of at GitHub:

| Link | Goes to |
| --- | --- |
| `/go/zip?src=hn` | `https://github.com/maz0x/burndown/releases/latest` |
| `/go/repo?src=hn` | `https://github.com/maz0x/burndown` |
| `/go/guide?src=hn` | `/guide` |
| anything else | `/` (counted as a miss, never a 404) |

`src` is the channel tag: `hn`, `reddit`, `readme`, whatever the link was posted as. It is free
text, normalised to at most 32 lowercase characters; a missing `src` counts as `direct`, and
anything with an unexpected character counts as `other`.

The count is written on Cloudflare before the redirect is returned, so it is unaffected by ad
blockers, tracker blockers, Do-Not-Track or JavaScript being off - there is nothing on the page to
block. Only the slug, the `src` token and the time are recorded. No IP address, no user agent, no
referrer, no cookie, no country, nothing that identifies a person, and the redirect targets are
constants in the file so the endpoint cannot be borrowed as an open redirect.

**The Function works with no binding attached.** With nothing bound it redirects and counts
nothing, which is why it is safe to deploy this before doing the step below.

## The one-time step: attach the `GO_COUNTS` binding

Nothing here creates the binding. It is attached once, by hand, to the `burndown-app` Pages project,
and it does not exist until someone does that. Until then every `/go/` link works and no number is
recorded anywhere.

Preferred: an **Analytics Engine dataset**, which is built for exactly this (append-only events, no
read-modify-write, no per-key write ceiling).

1. Cloudflare dashboard → **Workers & Pages** → the **burndown-app** project.
2. **Settings** → **Bindings** → **Add** → **Analytics engine**.
3. **Variable name**: `GO_COUNTS`. **Dataset**: `burndown_go`.
4. **Redeploy the project.** A binding does not apply to deployments that already exist.

The dataset does not have to be created first; it comes into being on the first data point written
to that name.

Check what Analytics Engine costs on the current plan before relying on it
(<https://developers.cloudflare.com/analytics/analytics-engine/>). If it is not available, bind a
**KV namespace** to the same variable name `GO_COUNTS` instead and the Function switches to KV by
itself - it looks at which methods the binding has, not at a setting. KV is the weaker option: it
counts by read-modify-write, so simultaneous clicks can lose a hit, and the free plan caps writes
per day. It is good enough to tell 400 clicks from 4.

Binding docs: <https://developers.cloudflare.com/pages/functions/bindings/#analytics-engine>

## Reading the numbers

With the Analytics Engine binding, over the SQL API (the account id is in `.cf-deployments`, which
is deliberately not published; the token needs Account Analytics read):

```sh
curl "https://api.cloudflare.com/client/v4/accounts/<ACCOUNT_ID>/analytics_engine/sql" \
  --header "Authorization: Bearer <API_TOKEN>" \
  --data "SELECT blob1 AS slug, blob2 AS src, SUM(_sample_interval) AS clicks
          FROM burndown_go
          WHERE timestamp > NOW() - INTERVAL '30' DAY
          GROUP BY slug, src ORDER BY clicks DESC"
```

`SUM(_sample_interval)` rather than `COUNT()`: Analytics Engine samples under load, and each stored
row stands for `_sample_interval` real ones. Counting rows undercounts exactly when a link is doing
well, which is the moment the number matters.

With the KV fallback instead, the keys are `go:<YYYY-MM-DD>:<slug>:<src>` and each value is a count.
