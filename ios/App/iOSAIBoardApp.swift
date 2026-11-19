import SwiftUI

@main
struct iOSAIBoardApp: App {
    var body: some Scene {
        WindowGroup {
            SetupView()
        }
    }
}

struct SetupView: View {
    @State private var sample = "i think their going to be late, definately by a hour or more"

    var body: some View {
        NavigationStack {
            Form {
                Section("Set up") {
                    Label("Open Settings, then General, Keyboard, Keyboards, Add New Keyboard, iOSAIBoard.", systemImage: "1.circle")
                    Label("Tap iOSAIBoard in that list and turn on Allow Full Access. It needs the network to check your text.", systemImage: "2.circle")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                Section("How to use it") {
                    Label("Type with your usual keyboard.", systemImage: "keyboard")
                    Label("Hold the globe key and pick iOSAIBoard.", systemImage: "globe")
                    Label("Tap Fix. It corrects the text before the cursor, or the selected text if you selected some.", systemImage: "checkmark.circle")
                }
                Section("Try it here") {
                    TextEditor(text: $sample)
                        .frame(minHeight: 140)
                }
                Section {
                    Text("Your text is sent only when you tap Fix, and it is not stored.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("iOSAIBoard")
        }
    }
}
