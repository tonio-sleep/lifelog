import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var step = 0

    private let lastStep = 2

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: privacy
                    default: permissions
                    }
                }
                .padding(.horizontal, Space.page)
                .padding(.top, Space.xxl)
                .padding(.bottom, Space.xl)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .id(step)
                .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.25), value: step)

            footer
        }
        .paperScreen()
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("Welcome")
                .font(Typeface.micro).textCase(.uppercase).tracking(1.2)
                .foregroundStyle(Palette.inkTertiary)
            Text("A quiet place for your days.")
                .font(Typeface.display)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Write when you want to. Add photos, voice notes, places, and the small things you keep track of. Lifelog arranges them into your timeline, and never invents anything you did not record.")
                .font(Typeface.reading)
                .lineSpacing(5)
                .foregroundStyle(Palette.inkSecondary)
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Text("Private by design")
                .font(Typeface.display)
                .foregroundStyle(Palette.ink)
            point("lock", "Encrypted on this device", "Your journal, photos, and recordings are encrypted before they are written to storage.")
            point("iphone", "Local first", "There is no account to make. Nothing leaves your phone unless you choose to export a backup or connect an optional service.")
            point("key", "A backup only you can open", "Backups are encrypted with a passphrase that only you know. Keep it somewhere safe, since it cannot be recovered.")
        }
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: symbol)
                .font(.system(.title3))
                .foregroundStyle(Palette.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Typeface.bodyStrong).foregroundStyle(Palette.ink)
                Text(detail).font(Typeface.label).foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("Allow only what helps")
                .font(Typeface.display)
                .foregroundStyle(Palette.ink)
            Text("Everything here is optional, and you can change your mind later in Settings. Lifelog asks again only when a feature needs something you have not allowed.")
                .font(Typeface.label)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PermissionsList(permissions: env.permissions, location: env.location, includeBiometrics: false)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: Space.sm) {
            Hairline()
            HStack(spacing: Space.sm) {
                ForEach(0...lastStep, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? Palette.accent : Palette.line)
                        .frame(width: index == step ? 22 : 8, height: 8)
                }
                .accessibilityHidden(true)
                Spacer()
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(QuietButtonStyle())
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.sm)

            Button(step == lastStep ? "Begin" : "Continue") { advance() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.md)
        }
        .background(Palette.paper)
    }

    private func advance() {
        if step < lastStep {
            step += 1
        } else {
            env.updateSettings { $0.onboardingComplete = true }
            Task { _ = await env.syncReminders() }
        }
    }
}

/// Shown when the stored archive cannot be decrypted. Nothing is written, so the
/// unreadable file is never overwritten while the person decides what to do.
struct RecoveryView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var showImporter = false
    @State private var importedData: IdentifiableData?
    @State private var confirmErase = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                PageHeader(
                    eyebrow: "Needs attention",
                    title: "Your archive can't be opened",
                    subtitle: "The encrypted data on this device could not be read with this device's key."
                )
                Text("This can happen after moving to a new device or restoring a phone backup that did not include the keychain. Nothing has been changed or deleted. Lifelog is not writing anything while this screen is showing.")
                    .font(Typeface.reading)
                    .lineSpacing(4)
                    .foregroundStyle(Palette.inkSecondary)

                VStack(spacing: Space.md) {
                    Button("Restore from a backup file") { showImporter = true }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Start fresh and erase the unreadable data", role: .destructive) { confirmErase = true }
                        .buttonStyle(QuietButtonStyle())
                        .tint(Palette.danger)
                }
            }
            .padding(Space.page)
            .padding(.top, Space.xl)
        }
        .paperScreen()
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                importedData = IdentifiableData(data: data)
            } else {
                env.present("That file could not be read.")
            }
        }
        .sheet(item: $importedData) { wrapper in
            BackupImportView(data: wrapper.data).environmentObject(env)
        }
        .confirmationDialog("Erase the unreadable data?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase and start fresh", role: .destructive) { env.clearAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the data that cannot be opened. Restore a backup instead if you have one.")
        }
    }
}
