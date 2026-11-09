// /go/<slug> - the download links we hand out, counted server-side.
//
// Every "download Burndown" link posted anywhere goes through here instead of straight to GitHub:
//   https://burndown-app.pages.dev/go/zip?src=hn
// The Function counts the hit and 302s to the real target. The count happens ON CLOUDFLARE, before
// the redirect is written, so an ad blocker, a Do-Not-Track setting or a browser with JavaScript
// off changes nothing about it: there is no script and no beacon to block. That is the whole point
// of doing it here rather than with an analytics tag on the page.
//
// WHAT IS RECORDED: the slug, the src token, and the time. Nothing else. No IP address, no user
// agent, no cookie, no referrer, no country, nothing that identifies a person. Both fields are
// normalised to a short allowlisted token before they are written, so a hand-edited link cannot
// push arbitrary text into the dataset.
//
// The redirect targets are CONSTANTS below. Nothing in the request can steer where a visitor is
// sent, which is what keeps this from being an open redirect that phishing can borrow.

// Where each slug goes. Site links stay relative so a preview deployment redirects to its own copy.
const ROUTES = {
  zip: "https://github.com/maz0x/burndown/releases/latest",
  repo: "https://github.com/maz0x/burndown",
  guide: "/guide",
};
// An unknown slug is still a real visitor who clicked something we published: send them to the
// home page rather than a 404, and count the miss so a wrong link in the wild is visible.
const FALLBACK = "/";

// Slugs and src tokens are written to storage, so they are allowlisted rather than escaped:
// lowercase letters, digits, dot, dash, underscore, and never longer than 32 characters.
function token(raw, fallback) {
  const s = String(raw || "").toLowerCase().slice(0, 32);
  if (!s) return fallback;
  return /^[a-z0-9._-]+$/.test(s) ? s : "other";
}

// KV only. Read-modify-write, so concurrent clicks in the same second can lose a count, and the
// free plan caps daily writes: this is the coarse fallback, and GO_COUNTS should be an Analytics
// Engine dataset wherever the plan allows it. The date lives in the key, which is the timestamp.
async function bumpKV(kv, slug, src) {
  const day = new Date().toISOString().slice(0, 10);
  const key = `go:${day}:${slug}:${src}`;
  const n = parseInt(await kv.get(key), 10);
  await kv.put(key, String((Number.isFinite(n) ? n : 0) + 1));
}

// Counting must never be able to break a download link. Every path here is wrapped, and an absent
// binding is simply nothing to do: an unbound deployment still redirects correctly, it just does
// not count. That is deliberate - the binding is attached by hand in the dashboard (see
// functions/README.md), so the code has to survive being deployed before that happens.
function record(context, slug, src) {
  const b = context.env && context.env.GO_COUNTS;
  if (!b) return;
  try {
    if (typeof b.writeDataPoint === "function") {
      // Analytics Engine stamps the timestamp itself. Not awaited, by Cloudflare's own guidance.
      b.writeDataPoint({ indexes: [slug], blobs: [slug, src], doubles: [1] });
    } else if (typeof b.get === "function" && typeof b.put === "function") {
      context.waitUntil(bumpKV(b, slug, src).catch(() => {}));
    }
  } catch {
    // Deliberately silent: a counting failure is not worth a failed download.
  }
}

export async function onRequest(context) {
  const { request, params } = context;
  const raw = Array.isArray(params.slug) ? params.slug[0] : params.slug;
  const slug = token(raw, "home");
  const target = Object.prototype.hasOwnProperty.call(ROUTES, slug) ? ROUTES[slug] : FALLBACK;

  // GET only. A HEAD from a link checker or an uptime monitor would otherwise inflate every
  // number here, and those are the numbers a launch decision gets made on.
  if (request.method === "GET") {
    const src = token(new URL(request.url).searchParams.get("src"), "direct");
    record(context, slug, src);
  }

  return new Response(null, {
    status: 302,
    headers: {
      Location: target,
      // Without this a browser or an edge cache answers the next click itself and the hit is
      // never counted. A redirect that caches is a redirect that stops measuring.
      "Cache-Control": "no-store",
      // These are tracking links, not content. Keep them out of the index.
      "X-Robots-Tag": "noindex",
    },
  });
}
