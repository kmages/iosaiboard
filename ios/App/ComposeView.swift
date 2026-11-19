import MessageUI
import SwiftUI

/// Write an email here and it cannot leave without being checked:
/// the send buttons only work on text that has passed Check unchanged.
struct ComposeView: View {
    @AppStorage("draftSubject") private var subject = ""
    @AppStorage("draftBody") private var message = ""
    @State private var checkedSubject: String?
    @State private var checkedMessage: String?
    @State private var busy = false
    @State private var status = "Write your email, then tap Check."
    @State private var showMail = false
    @Environment(\.openURL) private var openURL

    private var isEmpty: Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isChecked: Bool {
        !isEmpty && checkedMessage == message && checkedSubject == subject
    }

    var body: some View {
        Form {
            Section("Subject") {
                TextField("Subject", text: $subject)
            }
            Section("Message") {
                TextEditor(text: $message)
                    .frame(minHeight: 240)
            }
            Section {
                Button {
                    check()
                } label: {
                    HStack {
                        Label(isChecked ? "Checked" : "Check", systemImage: "checkmark.circle.fill")
                        if busy {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(busy || isEmpty || isChecked)
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button {
                    openGmail()
                } label: {
                    Label("Send with Gmail", systemImage: "envelope")
                }
                Button {
                    openMail()
                } label: {
                    Label("Send with Apple Mail", systemImage: "envelope.fill")
                }
            } header: {
                Text("Send")
            } footer: {
                Text(isChecked
                     ? "Opens the mail app with this email filled in. Add who it goes to there and send."
                     : "These unlock after Check. If you change the text, check it again.")
            }
            .disabled(!isChecked)
            Section {
                Button("Start a new email", role: .destructive) {
                    subject = ""
                    message = ""
                    checkedSubject = nil
                    checkedMessage = nil
                    status = "Write your email, then tap Check."
                }
                .disabled(busy || (subject.isEmpty && message.isEmpty))
            }
        }
        .navigationTitle("Checked email")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMail) {
            MailSheet(subject: subject, message: message)
                .ignoresSafeArea()
        }
    }

    private func check() {
        busy = true
        status = "Checking..."
        let originalSubject = subject
        let originalMessage = message
        Task {
            do {
                var fixedSubject = originalSubject
                if !originalSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    fixedSubject = try await FixClient.fix(originalSubject)
                }
                let fixedMessage = try await FixClient.fix(originalMessage)
                if subject == originalSubject, message == originalMessage {
                    let changed = fixedSubject != originalSubject || fixedMessage != originalMessage
                    subject = fixedSubject
                    message = fixedMessage
                    checkedSubject = fixedSubject
                    checkedMessage = fixedMessage
                    status = changed ? "Checked and corrected. Read it over, then send."
                                     : "Checked. Nothing needed fixing."
                } else {
                    status = "The text changed while checking. Tap Check again."
                }
            } catch {
                status = "Not checked: \(error.localizedDescription)"
            }
            busy = false
        }
    }

    private func encode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    private func openGmail() {
        guard let url = URL(string: "googlegmail://co?subject=\(encode(subject))&body=\(encode(message))") else { return }
        openURL(url) { accepted in
            if !accepted { status = "Could not open Gmail. Is the Gmail app installed?" }
        }
    }

    private func openMail() {
        if MFMailComposeViewController.canSendMail() {
            showMail = true
        } else if let url = URL(string: "mailto:?subject=\(encode(subject))&body=\(encode(message))") {
            openURL(url) { accepted in
                if !accepted { status = "Could not open Mail. Is an account set up in Apple Mail?" }
            }
        }
    }
}

/// Apple Mail's own compose sheet, pre-filled with the checked email.
struct MailSheet: UIViewControllerRepresentable {
    let subject: String
    let message: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setSubject(subject)
        controller.setMessageBody(message, isHTML: false)
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            dismiss()
        }
    }
}
