import SwiftUI

/// On-screen keyboard relay, presented from the remote's gear ("more") menu. Pops the iOS
/// keyboard and pushes whatever the user types to the TV's currently-focused text field via
/// `SendInputString` (the same transport voice dictation uses). The keyboard's return key (and
/// the Send button) fires `KEY_ENTER` to submit.
///
/// The text is sent in full on every change, which Samsung's `SendInputString` treats as
/// "set the field to this" — so edits and backspaces just re-send the new value. It only has
/// a visible effect when a text field is focused *on the TV* (e.g. a search box); otherwise
/// the frames are silently ignored, which is why the view leads with that instruction.
@MainActor
struct KeyboardInputView: View {
    /// Send the current text to the TV's focused field.
    let onType: (String) async -> Void
    /// Submit (KEY_ENTER).
    let onSubmit: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Label("Open a search or text field on the TV first — what you type here appears there live.",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                TextField("Type to send to the TV", text: $text)
                    .focused($focused)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .font(.title3)
                    .padding(.horizontal)
                    .onChange(of: text) { _, newValue in
                        Task { await onType(newValue) }
                    }
                    .onSubmit {
                        Task { await onSubmit() }
                    }

                HStack {
                    Button("Clear") {
                        text = ""
                        Task { await onType("") }
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        Task { await onSubmit() }
                    } label: {
                        Label("Send", systemImage: "return")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("TV Keyboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
        .tint(RemoteTheme.accent)
        .presentationDetents([.medium, .large])
    }
}
