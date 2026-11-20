import SwiftUI
import UIKit

struct LockView: View {
    @EnvironmentObject private var env: AppEnvironment

    @State private var pin = ""
    @State private var message: String?
    @State private var failures = 0
    @State private var lockedUntil: Date?
    @State private var working = false
    @State private var shake: CGFloat = 0

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]
    private var biometrics: (available: Bool, name: String, symbol: String) { Biometrics.availability() }
    private var canUseBiometrics: Bool { env.biometricUnlockEnabled && biometrics.available }

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            VStack(spacing: Space.xl) {
                Spacer(minLength: Space.lg)
                VStack(spacing: Space.sm) {
                    Image(systemName: "lock")
                        .font(.system(.title).weight(.light))
                        .foregroundStyle(Palette.inkTertiary)
                        .accessibilityHidden(true)
                    Text("Lifelog")
                        .font(Typeface.display)
                        .foregroundStyle(Palette.ink)
                    Text(message ?? "Enter your PIN")
                        .font(Typeface.label)
                        .foregroundStyle(message == nil ? Palette.inkSecondary : Palette.danger)
                        .multilineTextAlignment(.center)
                        .accessibilityLiveRegion()
                }

                dots
                    .modifier(ShakeEffect(travel: shake))

                keypad

                Button(working ? "Checking…" : "Unlock") { submit() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(pin.count < 4 || working || isLockedOut)
                    .padding(.horizontal, Space.xxl)

                Spacer(minLength: Space.lg)
            }
            .padding(Space.page)
            .frame(maxWidth: 420)
        }
        .task {
            // Offer biometrics once when the lock appears, never in the background.
            guard canUseBiometrics, UIApplication.shared.applicationState == .active else { return }
            await tryBiometrics()
        }
    }

    private var isLockedOut: Bool {
        if let lockedUntil { return lockedUntil > Date() }
        return false
    }

    // MARK: Pieces

    private var dots: some View {
        HStack(spacing: Space.md) {
            ForEach(0..<max(4, pin.count), id: \.self) { index in
                Circle()
                    .fill(index < pin.count ? Palette.ink : Color.clear)
                    .overlay(Circle().strokeBorder(Palette.inkTertiary, lineWidth: 1))
                    .frame(width: 12, height: 12)
            }
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("\(pin.count) digits entered")
    }

    private var keypad: some View {
        VStack(spacing: Space.md) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: Space.xl) {
                    ForEach(row, id: \.self) { digit in key(digit) }
                }
            }
            HStack(spacing: Space.xl) {
                if canUseBiometrics {
                    Button { Task { await tryBiometrics() } } label: {
                        Image(systemName: biometrics.symbol)
                            .font(.system(.title2))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 72, height: 56)
                    }
                    .accessibilityLabel("Unlock with \(biometrics.name)")
                } else {
                    Color.clear.frame(width: 72, height: 56)
                }
                key("0")
                Button {
                    if !pin.isEmpty { pin.removeLast() }
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(.title3))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(width: 72, height: 56)
                }
                .accessibilityLabel("Delete")
            }
        }
    }

    private func key(_ digit: String) -> some View {
        Button {
            guard pin.count < 12 else { return }
            pin.append(digit)
            message = nil
        } label: {
            Text(digit)
                .font(Typeface.heading.monospacedDigit())
                .foregroundStyle(Palette.ink)
                .frame(width: 72, height: 56)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(digit)
    }

    // MARK: Actions

    private func submit() {
        if let lockedUntil, lockedUntil > Date() {
            let seconds = Int(lockedUntil.timeIntervalSinceNow.rounded(.up))
            message = "Too many attempts. Try again in \(seconds) seconds."
            return
        }
        working = true
        let attempt = pin
        Task {
            let ok = await env.unlock(with: attempt)
            working = false
            if ok {
                pin = ""
                failures = 0
                message = nil
                ActivityClock.shared.reset()
            } else {
                failures += 1
                pin = ""
                withAnimation(.linear(duration: 0.4)) { shake += 1 }
                if failures >= 5 {
                    let wait = min(60, 5 * (failures - 4))
                    lockedUntil = Date().addingTimeInterval(TimeInterval(wait))
                    message = "Too many attempts. Try again in \(wait) seconds."
                } else {
                    message = "That PIN is not right."
                }
            }
        }
    }

    private func tryBiometrics() async {
        let ok = await Biometrics.authenticate(reason: "Unlock your Lifelog.")
        if ok {
            env.isLocked = false
            ActivityClock.shared.reset()
        }
    }
}

private extension View {
    func accessibilityLiveRegion() -> some View {
        self.accessibilityAddTraits(.updatesFrequently)
    }
}

private struct ShakeEffect: GeometryEffect {
    var travel: CGFloat
    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(travel * .pi * 4), y: 0))
    }
}
