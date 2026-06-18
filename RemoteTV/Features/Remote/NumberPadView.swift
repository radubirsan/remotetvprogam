import RemoteTVCore
import SwiftUI

/// Sheet-presented number keypad for entering a channel number. Each digit tap
/// dispatches the matching `KEY_<n>` command immediately — Tizen accumulates the
/// sequence and tunes to that channel after a short timeout, the same way pressing
/// digits on the physical remote works. The local display above the grid mirrors
/// what the user has typed; **Clear** wipes the local display and **Enter** commits
/// (`KEY_ENTER`) and clears.
@MainActor
struct NumberPadView: View {
    let onCommand: (TVCommand) async -> Void

    @State private var typed: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("CHANNEL")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(RemoteTheme.labelDim)
                    Text(typed.isEmpty ? "—" : typed)
                        .font(.system(size: 48, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(minHeight: 60)
                        .accessibilityLabel(typed.isEmpty ? "No digits entered" : "Channel \(typed)")
                }
                .padding(.top, 12)

                Spacer(minLength: 16)

                VStack(spacing: 12) {
                    row(1, 2, 3)
                    row(4, 5, 6)
                    row(7, 8, 9)
                    HStack(spacing: 12) {
                        DigitKey(label: "Clear", style: .secondary) {
                            typed = ""
                        }
                        DigitKey(label: "0") {
                            tap(digit: 0)
                        }
                        DigitKey(label: "Enter", style: .primary) {
                            tapEnter()
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RemoteTheme.bg.ignoresSafeArea())
            .navigationTitle("Number Pad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.4), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .bold()
                }
            }
        }
        .tint(RemoteTheme.accent)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func row(_ a: Int, _ b: Int, _ c: Int) -> some View {
        HStack(spacing: 12) {
            DigitKey(label: "\(a)") { tap(digit: a) }
            DigitKey(label: "\(b)") { tap(digit: b) }
            DigitKey(label: "\(c)") { tap(digit: c) }
        }
    }

    private func tap(digit: Int) {
        typed += "\(digit)"
        guard let command = TVCommand.digit(digit) else { return }
        Task { await onCommand(command) }
    }

    private func tapEnter() {
        Task { await onCommand(.enter) }
        typed = ""
    }
}

/// Single keypad cell. `style` swaps the fill so the bottom-row Clear/Enter buttons
/// read distinct from the digit keys without breaking the dark Samsung theme.
private struct DigitKey: View {
    enum Style { case standard, primary, secondary }

    let label: String
    var style: Style = .standard
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: label.count > 1 ? 17 : 28, weight: .semibold, design: .rounded))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: 70)
                .background(background, in: .rect(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var foreground: Color {
        switch style {
        case .standard, .secondary: RemoteTheme.iconColor
        case .primary:              .white
        }
    }

    private var background: AnyShapeStyle {
        switch style {
        case .standard:  AnyShapeStyle(RemoteTheme.buttonFace)
        case .secondary: AnyShapeStyle(Color.white.opacity(0.06))
        case .primary:   AnyShapeStyle(Color.green)
        }
    }
}
