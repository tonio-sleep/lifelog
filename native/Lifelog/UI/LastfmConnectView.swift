import SwiftUI
import WebKit
import UIKit

/// Guided Last.fm setup. A web view can open Last.fm and help someone log in, but
/// Last.fm's documented API still requires a key for reading recent tracks.
/// There is no official keyless web-view connection for third-party apps.
struct LastfmConnectView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var apiKey = ""
    @State private var showKeyPage = false
    @State private var webLoading = false
    @State private var checking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    HStack(alignment: .top, spacing: Space.md) {
                        LifelogMark(size: 42)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Connect Last.fm")
                                .font(Typeface.title)
                                .foregroundStyle(Palette.ink)
                            Text("Bring your listening history into your private archive.")
                                .font(Typeface.label)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }

                    steps
                    privacy
                }
                .padding(Space.page)
            }
            .background(Palette.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showKeyPage) { keyPage }
            .task {
                if username.isEmpty { username = env.settings.lastfmUsername ?? "" }
            }
        }
    }

    // MARK: Steps

    private var steps: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            step(number: 1, title: "Get a free API key", detail: "Last.fm requires a key for any app that reads scrobbles. We can open their page for you.") {
                Button { showKeyPage = true } label: {
                    Label("Open Last.fm", systemImage: "safari")
                }
                .buttonStyle(QuietButtonStyle())
            }

            Hairline()

            step(number: 2, title: "Your username", detail: "The profile name from your Last.fm page.") {
                TextField("username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Hairline()

            step(number: 3, title: "Paste the key", detail: "No password or shared secret is needed. The key is stored encrypted on this device.") {
                HStack(spacing: Space.sm) {
                    SecureField("API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Paste") { apiKey = UIPasteboard.general.string ?? "" }
                        .buttonStyle(QuietButtonStyle())
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button { Task { await connect() } } label: {
                HStack(spacing: Space.sm) {
                    if checking { ProgressView().tint(Palette.onAccent) }
                    Text(checking ? "Checking…" : "Connect")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(checking || username.trimmed.isEmpty || apiKey.trimmed.isEmpty)
        }
        .surface()
    }

    private func step<Content: View>(
        number: Int,
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Text("\(number)")
                    .font(Typeface.captionStrong)
                    .foregroundStyle(Palette.onAccent)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Palette.accent))
                Text(title)
                    .font(Typeface.bodyStrong)
                    .foregroundStyle(Palette.ink)
            }
            Text(detail)
                .font(Typeface.caption)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Privacy")
                .font(Typeface.heading)
                .foregroundStyle(Palette.ink)
            Text("Your archive never leaves this device. Lifelog only asks Last.fm for your recent tracks, and stores what it brings home locally.")
                .font(Typeface.caption)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Web view

    private var keyPage: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                LastfmWebView(
                    url: URL(string: "https://www.last.fm/api/account/create")!,
                    isLoading: $webLoading
                )
                if webLoading {
                    ProgressView()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.top, Space.sm)
                }
            }
            .navigationTitle("Last.fm API keys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showKeyPage = false }
                }
            }
        }
    }

    // MARK: Connect

    @MainActor
    private func connect() async {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !key.isEmpty else { return }

        checking = true
        errorMessage = nil
        do {
            let service = LastFMService()
            _ = try await service.fetchRecentTracks(username: user, apiKey: key, maxPages: 1)
            env.connectLastfm(username: user, apiKey: key)
            apiKey = ""
            checking = false
            dismiss()
            Task { @MainActor in _ = await env.syncLastfm() }
        } catch {
            errorMessage = error.localizedDescription
            checking = false
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Web view

private struct LastfmWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: LastfmWebView

        init(_ parent: LastfmWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
