import SwiftUI

// The first-run welcome tour: four short pages that explain what Burndown is, where its numbers
// come from, how to connect (with explicit consent for anything that touches an account), and how
// to find your way around. Shown once on a fresh install; reopenable from the About window.
//
// Design: Stone & Clay. Serif display for the wordmark and page titles, quiet eyebrows, the
// LivingFlameMark as the only ornament. No ScrollView (offscreen QA renders) and no em-dashes.

struct WelcomeView: View {
    @ObservedObject var settings: AppSettings
    var engine: UsageEngine
    var openAccount: () -> Void
    var initialPage: Int = 0
    @Environment(\.colorScheme) private var scheme
    @State private var page = 0
    @State private var borrowed = false   // "Use my Claude Code sign-in" succeeded this session
    @State private var borrowing = false  // the attempt is in flight, so the button can say so
    @State private var borrowError: String? = nil

    private let pages = ["Welcome", "Your numbers", "Connect", "Find your way"]

    var body: some View {
        let p = Palette.of(scheme)
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch page {
                case 0: welcomePage(p)
                case 1: sourcesPage(p)
                case 2: connectPage(p)
                default: tourPage(p)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Spacer(minLength: 0)
            bottomBar(p)
        }
        .padding(24)
        // Sized by the WINDOW, not by the view. A hard frame here overrides whatever the window was
        // set to, which is exactly how the Account window ended up truncating its own text: the
        // window was widened and the view inside it stayed 340 points wide. Same trap, third place.
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity, alignment: .top)
        .background(p.bg)
        .onAppear { page = initialPage }
    }

    // ── Page 0: what this is ──
    private func welcomePage(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Spacer(); LivingFlameMark(size: 54); Spacer() }.padding(.top, 18).padding(.bottom, 20)
            HStack { Spacer(); Text("Burndown").font(.system(size: 30, weight: .semibold, design: .serif)).foregroundStyle(p.ink); Spacer() }
            HStack { Spacer(); Text("See the limit coming.").font(.system(size: 12.5)).foregroundStyle(p.sub); Spacer() }
                .padding(.top, 4).padding(.bottom, 22)
            Text("Claude plans have limits: a 5-hour session and a weekly allowance. Hit one mid-task and you are stopped, sometimes for hours. Burndown is a small flame in your menu bar that burns hotter as you spend, so you always see it coming.")
                .font(.system(size: 12.5)).foregroundStyle(p.ink).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // ── Page 1: the two data sources, honestly ──
    private func sourcesPage(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            pageTitle("Where the numbers come from", p)
            sourceCard(p, badge: "ESTIMATE", tint: p.sub, title: "Always on",
                       body: "Reads the session logs Claude Code keeps on this Mac and estimates your usage from them. No network, no sign-in.")
            sourceCard(p, badge: "LIVE", tint: p.session, title: "Optional",
                       body: "Signs in with your Claude account and asks Claude's own usage service for the exact numbers. Only Claude's servers are ever contacted.")
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "lock").font(.system(size: 10)).foregroundStyle(p.faint)
                Text(kTrustSentence).font(.system(size: 11)).foregroundStyle(p.faint)
            }
        }
    }

    private func sourceCard(_ p: Palette, badge: String, tint: Color, title: String, body text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text(badge).font(.system(size: 9, weight: .bold)).tracking(0.8)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(tint.opacity(0.14)))
                Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(p.ink)
            }
            Text(text).font(.system(size: 11.5)).foregroundStyle(p.sub).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.track.opacity(0.45)))
    }

    // ── Page 2: connect, with consent ──
    private func connectPage(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            pageTitle("How would you like to start?", p)
            bigButton(p, primary: true, title: "Sign in with Claude",
                      caption: "Opens the sign-in window. Your browser approves it; Burndown never sees your password.") {
                openAccount()
            }
            if UsageEngine.cliSignInPresent() {
                bigButton(p, primary: false,
                          title: borrowed ? "Connected to your Claude Code sign-in"
                                 : borrowing ? "Connecting\u{2026}" : "Use my Claude Code sign-in",
                          caption: borrowed ? "Live usage is on. You can disconnect any time from the Account window."
                                 : borrowError ?? (borrowing ? "Asking Claude for your current limits."
                                            : "Borrows the sign-in Claude Code already has on this Mac. Nothing new to approve; disconnect any time.")) {
                    guard !borrowed else { return }
                    settings.borrowCLI = true
                    if !settings.usageAPI { settings.usageAPI = true }
                    engine.usageEnabled = true
                    engine.publishAccount()
                    // "Connected" only once the service has actually answered. This used to be set
                    // the moment the button was pressed, so a machine with no Claude Code sign-in,
                    // or no network, was told it was connected and then showed local estimates
                    // while claiming to be live.
                    borrowing = true
                    engine.fetchLive(force: true) { ok in
                        borrowing = false
                        borrowed = ok
                        if !ok { borrowError = "Could not read a Claude Code sign-in on this Mac." }
                    }
                }
            }
            bigButton(p, primary: false, title: "Not now",
                      caption: "Burndown reads only the local logs and never sends your usage anywhere. It still checks for its own updates, which you can turn off in Settings, General. Change your mind any time.") {
                withAnimation(.easeInOut(duration: 0.15)) { page = min(page + 1, pages.count - 1) }
            }
        }
    }

    private func bigButton(_ p: Palette, primary: Bool, title: String, caption: String, action: @escaping () -> Void) -> some View {
        let coral = Color(hex: settings.accentHex)
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(primary ? Color.white : p.ink)
                Text(caption).font(.system(size: 10.5))
                    .foregroundStyle(primary ? Color.white.opacity(0.85) : p.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(primary ? coral : p.track.opacity(0.5)))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain).focusable(false)
    }

    // ── Page 3: orientation ──
    private func tourPage(_ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            pageTitle("Find your way", p)
            tourRow(p, icon: "flame.fill", tint: p.session,
                    text: "The menu bar flame burns with your session. Click it for the full picture.")
            tourRow(p, icon: "questionmark.circle", tint: p.sub,
                    text: "Everything explains itself: click any of the small info marks. In the Settings and Account windows you can hover a label as well. Plain English, no manual.")
            tourRow(p, icon: "chart.bar", tint: p.sub,
                    text: "Pick your charts in Settings, Charts. All 24 are drawn there so you can see before you choose.")
            tourRow(p, icon: "bell", tint: p.sub,
                    text: "Alerts can warn you before a limit lands. They are off until you turn them on.")
            Spacer(minLength: 0)
        }
    }

    private func tourRow(_ p: Palette, icon: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(tint).frame(width: 20)
            Text(text).font(.system(size: 12)).foregroundStyle(p.ink).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pageTitle(_ t: String, _ p: Palette) -> some View {
        Text(t).font(.system(size: 19, weight: .semibold, design: .serif)).foregroundStyle(p.ink)
            .padding(.bottom, 2)
    }

    // ── Bottom bar: dots + navigation ──
    private func bottomBar(_ p: Palette) -> some View {
        let coral = Color(hex: settings.accentHex)
        return HStack(spacing: 8) {
            HStack(spacing: 5) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Circle().fill(i == page ? coral : p.track).frame(width: 6, height: 6)
                }
            }
            .accessibilityLabel("Page \(page + 1) of \(pages.count)")
            Spacer()
            if page > 0 {
                Button("Back") { withAnimation(.easeInOut(duration: 0.15)) { page -= 1 } }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(p.sub).focusable(false)
            }
            Button {
                if page < pages.count - 1 {
                    withAnimation(.easeInOut(duration: 0.15)) { page += 1 }
                } else {
                    settings.onboarded = true
                    NSApp.keyWindow?.close()
                }
            } label: {
                Text(page < pages.count - 1 ? "Continue" : "Get started")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(coral))
            }
            .buttonStyle(.plain).focusable(false)
        }
        .padding(.top, 14)
    }
}
