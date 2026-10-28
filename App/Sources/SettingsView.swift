import SwiftUI
import VoixaKit

struct SettingsView: View {
    @Bindable var controller: DictationController

    var body: some View {
        Form {
            Section {
                ForEach(SpokenLanguage.allCases, id: \.self) { language in
                    Toggle(language.displayName, isOn: languageBinding(language))
                }
            } header: {
                Text("Languages you speak")
            } footer: {
                Text("Voixa only chooses between these, so accented English isn't mistaken for another language. Pick one for the best accuracy.")
            }

            Section {
                TextEditor(text: vocabularyBinding)
                    .font(.body.monospaced())
                    .frame(height: 100)
            } header: {
                Text("Custom vocabulary")
            } footer: {
                Text("One per line: names, product and technical terms you use often.")
            }

            Section {
                Picker("Model", selection: modelBinding) {
                    ForEach(WhisperModel.allCases, id: \.self) { model in
                        Text("\(model.displayName) · \(model.downloadSize)")
                            .tag(model)
                            .selectionDisabled(!model.fitsInMemory())
                    }
                }
                .disabled(controller.status == .recording || controller.status == .transcribing)
                LabeledContent("Status", value: controller.status.description(model: controller.model))
                LabeledContent("Memory", value: controller.memoryDescription)
            } header: {
                Text("Speech model")
            } footer: {
                Text("Turbo is about 3× faster. large-v3 needs 16 GB of memory. Switching downloads the model if needed. Voixa uses the GPU when memory is free and the lighter Neural Engine when it's tight, and releases the model after 3 idle minutes.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 620)
    }

    private func languageBinding(_ language: SpokenLanguage) -> Binding<Bool> {
        Binding {
            controller.settings.settings.languages.contains(language)
        } set: { enabled in
            var languages = controller.settings.settings.languages
            if enabled {
                languages.append(language)
            } else if languages.count > 1 {
                languages.removeAll { $0 == language }
            }
            // Keep a stable order regardless of toggle order.
            controller.settings.settings.languages = SpokenLanguage.allCases.filter(languages.contains)
        }
    }

    private var modelBinding: Binding<WhisperModel> {
        Binding {
            controller.model
        } set: { model in
            controller.selectModel(model)
        }
    }

    private var vocabularyBinding: Binding<String> {
        Binding {
            controller.settings.settings.customVocabulary.joined(separator: "\n")
        } set: { text in
            controller.settings.settings.customVocabulary = text.components(separatedBy: .newlines)
        }
    }
}
