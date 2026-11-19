import SwiftUI

struct LockView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.lifelogPalette) private var palette
    @State private var pin = ""
    @State private var showPin = false
    @State private var error = ""
    @State private var isWorking = false

    private var canSubmit: Bool {
        (4...12).contains(pin.count) && pin.allSatisfy(\.isNumber) && !isWorking
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(palette.accentSoft)
                        .frame(width: 52, height: 52)
                    Image(systemName: "lock")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(palette.accent)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Lifelog is locked")
                        .font(LifelogTheme.serif(27, relativeTo: .title))
                        .foregroundStyle(palette.text)
                    Text("Your archive remains encrypted on disk while the app is hidden.")
                        .font(LifelogTheme.sans(13))
                        .foregroundStyle(palette.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Group {
                            if showPin {
                                TextField("PIN", text: $pin)
                                    .keyboardType(.numberPad)
                            } else {
                                SecureField("PIN", text: $pin)
                                    .keyboardType(.numberPad)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .textContentType(.password)
                        .font(LifelogTheme.sans(17))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: pin) { _, newValue in
                            let digits = String(newValue.filter(\.isNumber).prefix(12))
                            if digits != newValue { pin = digits }
                            // Keep a failed-unlock message until the user starts a new PIN.
                            if !newValue.isEmpty { error = "" }
                        }

                        Button {
                            showPin.toggle()
                        } label: {
                            Image(systemName: showPin ? "eye.slash" : "eye")
                                .foregroundStyle(palette.secondary)
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel(showPin ? "Hide PIN" : "Show PIN")
                    }

                    if !error.isEmpty {
                        Text(error)
                            .font(LifelogTheme.sans(12))
                            .foregroundStyle(palette.danger)
                    }

                    Button(action: submit) {
                        HStack(spacing: 8) {
                            if isWorking {
                                ProgressView()
                                    .tint(palette.background)
                            }
                            Text(isWorking ? "Unlocking…" : "Unlock")
                                .font(LifelogTheme.sans(15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(palette.accent))
                        .foregroundStyle(palette.background)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.55)
                }

                Text("There is no PIN recovery. The PIN protects this screen; it does not change the archive encryption key. If you forget it, you will need to remove the app’s local data.")
                    .font(LifelogTheme.sans(11))
                    .foregroundStyle(palette.tertiary)
            }
            .frame(maxWidth: 420, alignment: .leading)
            .lifelogCard(padding: 24, radius: 22)

            Spacer()
        }
        .padding(24)
        .lifelogScreenBackground()
        .onSubmit(submit)
        .onAppear {
            if !env.settings.lockEnabled || env.settings.pinHash == nil {
                env.isLocked = false
            }
        }
    }

    private func submit() {
        guard !isWorking else { return }
        guard pin.count >= 4 else {
            error = "Enter your PIN."
            return
        }
        guard canSubmit else {
            error = "Use 4 to 12 digits."
            return
        }

        isWorking = true
        error = ""
        let candidate = pin
        Task {
            let unlocked = await env.unlock(with: candidate)
            await MainActor.run {
                isWorking = false
                if unlocked {
                    pin = ""
                    error = ""
                } else {
                    error = "That PIN did not match."
                    pin = ""
                }
            }
        }
    }
}
