import AppKit
import FreefieldCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        TabView {
            Tab(L("General"), systemImage: "gearshape") {
                GeneralSettings()
            }
            Tab(L("Account & Keys"), systemImage: "key") {
                ProvidersSettings()
            }
            Tab(L("AI Models"), systemImage: "cpu") {
                GenerationSettings()
            }
            Tab(L("Storage"), systemImage: "externaldrive") {
                LibrarySettings()
            }
        }
        .frame(width: 620, height: 600)
        .scenePadding()
    }
}

struct InlineSettingsView: View {
    var body: some View {
        TabView {
            Tab(L("General"), systemImage: "gearshape") { GeneralSettings() }
            Tab(L("Account & Keys"), systemImage: "key") { ProvidersSettings() }
            Tab(L("AI Models"), systemImage: "cpu") { GenerationSettings() }
            Tab(L("Storage"), systemImage: "externaldrive") { LibrarySettings() }
        }
        .frame(maxWidth: 760)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(L("Settings"))
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKey.language) private var language = ""
    @AppStorage(SettingsKey.appearance) private var appearance = "system"
    @AppStorage(SettingsKey.shareClipsWithTunnel) private var shareClipsWithTunnel = true
    @State private var confirmingRestart = false
    @State private var restartError: String?

    var body: some View {
        Form {
            Section {
                Picker(L("Language"), selection: $language) {
                    Text(L("System")).tag("")
                    Text("English").tag("en")
                    Text("Español").tag("es")
                }
                .onChange(of: language) { _, newValue in AppLanguage.set(newValue) }
                if language != AppLanguage.atLaunch {
                    HStack {
                        Label(L("Restart Freefield to apply the new language."), systemImage: "arrow.clockwise")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Restart Now"), action: restart)
                            .fixedSize()
                    }
                    if let restartError {
                        Label(restartError, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
                Picker(L("Appearance"), selection: $appearance) {
                    Text(L("Automatic")).tag("system")
                    Text(L("Light Mode")).tag("light")
                    Text(L("Dark Mode")).tag("dark")
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { _, newValue in Appearance.apply(newValue) }
            } header: {
                Text(L("Language and appearance"))
            } footer: {
                Text(L("System follows your Mac's language and uses English when it isn't Spanish."))
            }
            Section {
                Toggle(isOn: $shareClipsWithTunnel) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Share clips from this Mac through a temporary Cloudflare link"))
                        Text(L("Needed by the video tools that start from your clip or sound: Edit Video, Upscale Video, Reframe Video, Swap in Video, Motion Transfer, Talking Avatar and more."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                PrivacyPoint(symbol: "link", title: L("Why a link"),
                             text: L("Video models read clips and sounds only from a web link (https). They can't receive a file from your Mac any other way."))
                PrivacyPoint(symbol: "point.3.connected.trianglepath.dotted", title: L("How it's shared"),
                             text: L("When a video job needs your clip or sound, Freefield serves that one file straight from this Mac through a temporary Cloudflare Quick Tunnel. The tunnel program, cloudflared (open source, Apache 2.0 license), comes inside Freefield; nothing else is installed."))
                PrivacyPoint(symbol: "timer", title: L("What, and for how long"),
                             text: L("A 720p copy of at most 15 seconds (Upscale and Reframe send the full size), only for the seconds the provider takes to download it. The link is random and closes right after. Nothing is uploaded to a storage service, and nothing runs when Freefield opens or while you aren't making a video."))
                PrivacyPoint(symbol: "arrow.triangle.branch", title: L("Other ways"),
                             text: L("Paste your own public link (https) to the file instead. Or turn this off: Freefield then recreates the clip from its first frame (frame-based mode) and opens no link; only a short copy of the clip goes, once, to the model that describes its motion."))
            } header: {
                Text(L("Privacy"))
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(L("Restart Freefield now?"), isPresented: $confirmingRestart) {
            Button(L("Restart Now"), role: .destructive) { relaunch() }
        } message: {
            Text(L("Images are still being generated. Restarting cancels them: their results are lost, and the provider may still charge for them."))
        }
    }

    private func restart() {
        if app.engine.runningCount > 0 {
            confirmingRestart = true
        } else {
            relaunch()
        }
    }

    private func relaunch() {
        restartError = nil
        AppLanguage.relaunch(app) { message in
            restartError = L("Freefield couldn't restart (%@). Quit it and open it again to apply the new language.", message)
        }
    }
}

private struct PrivacyPoint: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

enum Appearance {
    static func apply(_ value: String?) {
        NSApp.appearance = switch value {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
    }
}

enum AppLanguage {
    static let atLaunch = UserDefaults.standard.string(forKey: SettingsKey.language) ?? ""

    static func set(_ code: String) {
        if code.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }

    static func relaunch(_ app: AppModel, failed: @escaping @MainActor (String) -> Void) {
        Task {
            let deadline = Date().addingTimeInterval(60)
            while app.engine.isSendingVideos, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !app.engine.isSendingVideos else {
                failed(L("a video is still being sent to OpenRouter; try again in a moment"))
                return
            }
            app.engine.suspendVideosForRelaunch()
            app.engine.jobs.filter(\.isRunning).forEach(app.engine.cancel)
            app.library.flush()
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { instance, error in
                let opened = instance != nil
                let reason = error?.localizedDescription
                DispatchQueue.main.async {
                    if opened {
                        NSApp.terminate(nil)
                    } else {
                        app.engine.resumeSuspendedVideos()
                        failed(reason ?? L("the new copy didn't open"))
                    }
                }
            }
        }
    }
}

struct ProvidersSettings: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKey.preferredProvider) private var preferredProvider = Provider.openRouter.rawValue

    var body: some View {
        Form {
            Section {
                ProviderKeyRow(provider: .openRouter, recommended: true)
            } header: {
                Text("OpenRouter")
            } footer: {
                Text(L("Recommended: one key unlocks every model in the lineup — Nano Banana, Seedream, GPT Image, FLUX, Recraft, Grok and more — and reports the exact cost of each image."))
            }
            Section {
                ProviderKeyRow(provider: .google, recommended: false)
            } header: {
                Text("Google Gemini")
            } footer: {
                Text(L("Google's own models: Nano Banana for images and Gemini Omni Flash for video (video needs billing turned on in Google AI Studio). The other models, Veo included, need an OpenRouter key."))
            }
            Section {
                Picker(L("Default provider"), selection: $preferredProvider) {
                    ForEach(Provider.allCases) { provider in
                        Text(app.keys.key(for: provider) == nil ? L("%@ (no key)", provider.displayName) : provider.displayName)
                            .tag(provider.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text(L("Default provider"))
            } footer: {
                Text(L("Freefield calls this provider first. A model it doesn't offer (for example GPT Image or Seedream with only Google) uses the other key, if you have one."))
            }
            Section {
                Label(L("Keys are encrypted and stored only on this Mac, and are sent only to their own provider."), systemImage: "lock.shield")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct ProviderKeyRow: View {
    let provider: Provider
    let recommended: Bool

    @Environment(AppModel.self) private var app
    @State private var draft = ""
    @State private var isEditing = false
    @State private var isVerifying = false
    @State private var errorMessage: String?
    @State private var rejections = 0

    private var savedKey: String? { app.keys.key(for: provider) }
    private var showsField: Bool { savedKey == nil || isEditing }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: provider.symbolName)
                    .font(.title3)
                    .foregroundStyle(Color.brand)
                Text(provider.displayName).font(.headline)
                if recommended {
                    Text(L("Recommended"))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.brand.opacity(0.18), in: .capsule)
                        .foregroundStyle(Color.brand)
                        .fixedSize()
                }
                Spacer()
                status
            }

            if showsField {
                HStack {
                    SecureField("API key", text: $draft, prompt: Text(provider.keyPlaceholder))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(verifyAndSave)
                        .shake(rejections)
                    Button(L("Save"), action: verifyAndSave)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || isVerifying)
                        .keyboardShortcut(.defaultAction)
                    if isEditing {
                        Button(L("Cancel")) { isEditing = false; draft = ""; errorMessage = nil }
                    }
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .transition(Motion.transition(.opacity.combined(with: .offset(y: -4))))
                }
                Link(L("Get a %@ API key →", provider.displayName), destination: provider.keyURL)
                    .font(.callout)
            } else if let savedKey {
                HStack {
                    Text(masked(savedKey))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Change…")) { isEditing = true; errorMessage = nil }
                    Button(L("Remove"), role: .destructive) {
                        errorMessage = app.saveKey(nil, for: provider) ? nil : L("Couldn't remove the key on this Mac.")
                    }
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .transition(Motion.transition(.opacity.combined(with: .offset(y: -4))))
                }
                if let account = app.catalog.accounts[provider] {
                    HStack(spacing: 14) {
                        if let remaining = account.remainingCredits {
                            Label(L("Balance: %@", AppModel.money(remaining)), systemImage: "creditcard")
                        }
                        let count = app.catalog.models[provider]?.count ?? 0
                        Label(L("%ld image models", count), systemImage: "square.stack.3d.up")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                if let error = app.catalog.errors[provider] {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
        .animation(Motion.standard, value: showsField)
        .animation(Motion.standard, value: errorMessage)
    }

    @ViewBuilder private var status: some View {
        if isVerifying || app.catalog.loading.contains(provider) {
            ProgressView().controlSize(.small)
        } else if savedKey != nil, app.catalog.errors[provider] == nil {
            Label(L("Connected"), systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
        } else if savedKey != nil {
            Label(L("Check"), systemImage: "exclamationmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)
        }
    }

    private func masked(_ key: String) -> String {
        guard key.count > 12 else { return String(repeating: "•", count: key.count) }
        return "\(key.prefix(8))••••••••\(key.suffix(4))"
    }

    private func verifyAndSave() {
        let candidate = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        isVerifying = true
        errorMessage = nil
        Task {
            defer { isVerifying = false }
            var keys = APIKeys()
            keys.set(candidate, for: provider)
            do {
                _ = try await ImageService(keys: keys).accountStatus(for: provider)
                if app.saveKey(candidate, for: provider) {
                    draft = ""
                    isEditing = false
                } else {
                    errorMessage = L("Couldn't save the key on this Mac.")
                }
            } catch {
                errorMessage = error.localizedDescription
                rejections += 1
            }
        }
    }
}

struct GenerationSettings: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKey.showAllModels) private var showAllModels = false
    @AppStorage(SettingsKey.autoEnhance) private var autoEnhance = false
    @AppStorage(SettingsKey.helperModelID) private var helperModelID = ""

    var body: some View {
        Form {
            Section {
                Toggle(L("Also show the providers' other image models"), isOn: $showAllModels)
            } header: {
                Text(L("Models"))
            } footer: {
                Text(L("By default Freefield shows a curated lineup of the best image models. Turn this on to see the full catalog (%ld models).", app.catalog.allModels.count))
            }
            Section {
                Toggle(isOn: $autoEnhance) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Enhance prompts automatically when generating"))
                        Text(L("The same switch appears next to the model in Create Image, the editing tools and the video tools: changing it in one place changes it everywhere."))
                            .helperTextStyle()
                    }
                }
                EnhancePoint(title: L("What it does"),
                             text: L("Before each generation, a fast AI text model rewrites what you typed as a detailed description in English: the subject, the setting, the camera and the light. Image and video models follow that better than a short idea, and your words can be in any language."))
                EnhancePoint(title: L("Keep in mind"),
                             text: L("It can add or change details you didn't ask for. Names, numbers and text in quotation marks are kept exactly. Tools whose text is drawn exactly as typed (Change Text) never use it. To read and edit the result before generating, use the Improve description button in Create Image instead."))
                EnhancePoint(title: L("Cost"),
                             text: L("About $0.001 per generation, charged by the model below and recorded in Usage."))
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Example")).font(.callout.weight(.semibold))
                    Text(L("You write: “a cat on the beach”"))
                        .font(.callout)
                    Text(L("It sends:"))
                        .font(.callout)
                    Text(verbatim: "A ginger tabby cat sitting on wet sand at the edge of a calm beach at golden hour, small waves breaking behind it, shot at eye level with a shallow depth of field, warm low sunlight from the left.")
                        .font(.callout)
                        .italic()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Picker(L("Model for enhancing and describing"), selection: $helperModelID) {
                    HelperModelMenu.options(app)
                }
            } header: {
                Text(L("Prompt assistant"))
            }
        }
        .formStyle(.grouped)
    }
}

private struct EnhancePoint: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.callout.weight(.semibold))
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct LibrarySettings: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SettingsKey.autoExport) private var autoExport = false
    @AppStorage(SettingsKey.exportFolder) private var exportFolder = ""

    var body: some View {
        Form {
            Section(L("Automatic copy")) {
                Toggle(L("Save a copy of every new image to a folder"), isOn: $autoExport)
                LabeledContent(L("Folder")) {
                    HStack {
                        Text(SettingsKey.exportFolderURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button(L("Change…"), action: chooseFolder)
                            .fixedSize()
                    }
                }
                .disabled(!autoExport)
            }
            Section(L("On this Mac")) {
                LabeledContent(L("Images"), value: "\(app.library.assets.count)")
                LabeledContent(L("Characters"), value: "\(app.library.characters.count)")
                LabeledContent(L("Recorded spending"), value: AppModel.money(app.library.totalSpent))
                Button(L("Show Library in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([app.library.root])
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("Choose")
        if panel.runModal() == .OK, let url = panel.url { exportFolder = url.path }
    }
}
