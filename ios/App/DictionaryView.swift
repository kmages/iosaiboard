import SwiftUI

/// Edit the saved words and corrections. Every change is saved to the server right away.
struct DictionaryView: View {
    @State private var saved = SavedDictionary()
    @State private var newWord = ""
    @State private var newTyped = ""
    @State private var newWanted = ""
    @State private var status = "Loading..."
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                ForEach(saved.keep, id: \.self) { word in
                    Text(word)
                }
                .onDelete { offsets in
                    saved.keep.remove(atOffsets: offsets)
                    save()
                }
                HStack {
                    TextField("Add a word or name", text: $newWord)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit(addWord)
                    Button("Add", action: addWord)
                        .disabled(trimmed(newWord).isEmpty)
                }
            } header: {
                Text("My words")
            } footer: {
                Text("Names and terms spelled exactly the way you want them. Fix will never change these, and will correct other spellings to match.")
            }

            Section {
                ForEach(saved.replace, id: \.self) { item in
                    HStack {
                        Text(item.typed)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text(item.wanted)
                    }
                }
                .onDelete { offsets in
                    saved.replace.remove(atOffsets: offsets)
                    save()
                }
                TextField("When I type (for example: omw)", text: $newTyped)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Change it to (for example: on my way)", text: $newWanted)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Add correction", action: addCorrection)
                    .disabled(trimmed(newTyped).isEmpty || trimmed(newWanted).isEmpty)
            } header: {
                Text("My corrections")
            } footer: {
                Text("Swapped every time you tap Fix, whole words only, in capitals or lowercase.")
            }

            Section {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("My words")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(!loaded)
        .task { await load() }
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addWord() {
        let word = trimmed(newWord)
        guard !word.isEmpty else { return }
        if !saved.keep.contains(word) { saved.keep.append(word) }
        newWord = ""
        save()
    }

    private func addCorrection() {
        let typed = trimmed(newTyped), wanted = trimmed(newWanted)
        guard !typed.isEmpty, !wanted.isEmpty else { return }
        saved.replace.removeAll { $0.typed.lowercased() == typed.lowercased() }
        saved.replace.append(.init(typed: typed, wanted: wanted))
        newTyped = ""
        newWanted = ""
        save()
    }

    private func load() async {
        do {
            saved = try await FixClient.loadDictionary()
            loaded = true
            status = "Swipe left on a row to delete it."
        } catch {
            status = "Could not load: \(error.localizedDescription)"
        }
    }

    private func save() {
        let snapshot = saved
        status = "Saving..."
        Task {
            do {
                let kept = try await FixClient.saveDictionary(snapshot)
                if saved == snapshot { saved = kept }
                status = "Saved."
            } catch {
                status = "Not saved: \(error.localizedDescription)"
            }
        }
    }
}
