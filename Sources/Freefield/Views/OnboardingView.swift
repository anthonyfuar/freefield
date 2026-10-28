import FreefieldCore
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var provider: Provider = .openRouter
    @State private var key = ""
    @State private var isVerifying = false
    @State private var error: String?
    @State private var isConnected = false
    @State private var rejections = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 76, height: 76)
                Text(L("Welcome to Freefield"))
                    .displayTitleStyle()
                Text(L("Your AI studio for images and video: create, edit, animate and make ads with the best AI models."))
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 500)
            }
            .padding(.top, 26)
            .padding(.bottom, 18)

            HStack(alignment: .top, spacing: 14) {
                feature("create", L("Create"), L("Images and videos from an idea, or one-click effects"))
                feature("photo", L("Improve a Photo"), L("Background, quality, light and touch-ups in words"))
                feature("video", L("More Ways to Make Video"), L("Animate photos, talking avatars and film scenes"))
                feature("ads", L("Ads & Products"), L("Product photos, ads and videos that sell"))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 18)

            keyCard
                .padding(.horizontal, 28)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Button(L("Not Now")) { dismiss() }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    Text(L("You can look around first; you'll need a key to create images and videos."))
                        .helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(action: connect) {
                    Text(L("Connect and Start"))
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 8)
                        .prominentLabel()
                        .opacity(isVerifying || isConnected ? 0 : 1)
                        .overlay {
                            if isVerifying {
                                ProgressView().controlSize(.small)
                                    .transition(.opacity)
                            }
                        }
                        .overlay {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .symbolEffect(.bounce, value: isConnected && !reduceMotion)
                                .opacity(isConnected ? 1 : 0)
                                .accessibilityHidden(true)
                        }
                        .animation(Motion.fade, value: isVerifying)
                        .animation(Motion.standard, value: isConnected)
                }
                .buttonStyle(.glassProminent)
                .tint(.brandFill)
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || isVerifying)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
        .frame(width: 680)
    }

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Connect your %@ account", provider.displayName))
                    .sectionTitleStyle()
                Text(provider.onboardingNote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Label(costLine, systemImage: "dollarsign.circle")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(provider.onboardingSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        StepBadge(number: index + 1)
                        Text(step.text)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        if let link = step.link {
                            Link(link.title + " →", destination: link.url)
                                .font(.callout)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L("%@ key", provider.displayName))
                    .font(.callout.weight(.semibold))
                SecureField(L("%@ key", provider.displayName), text: $key,
                            prompt: Text(L("Paste your key here (it starts with %@)", provider.keyPlaceholder)))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(connect)
                    .shake(rejections)
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                        .transition(Motion.transition(.opacity.combined(with: .offset(y: -4))))
                }
                Label(L("Keys are encrypted and stored only on this Mac, and are sent only to their own provider."), systemImage: "lock.shield")
                    .fineTextStyle()
            }
            .animation(Motion.standard, value: error)

            Button(provider == .openRouter ? L("Prefer Google Gemini?") : L("Use OpenRouter instead (recommended)")) {
                provider = provider == .openRouter ? .google : .openRouter
                key = ""
                error = nil
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: Radius.card))
    }

    private var costLine: String {
        let perImage = Lineup.defaultModelIDs(for: .create).lazy
            .compactMap(Lineup.entry)
            .compactMap { app.catalog.resolve($0, preferring: provider) }
            .first?.estimatedCostPerImage
        let price = perImage.map { L("About %@ per image with the default model; a video costs more.", AppModel.money($0)) }
            ?? L("An image usually costs a few cents; a video, a bit more.")
        return price + " " + L("You pay %@ directly, only for what you create.", provider.displayName)
    }

    private func feature(_ family: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            FamilyStyle.tile(symbol: NavCatalog.familySymbol(family), family: family, side: 40)
            Text(title).font(.headline)
            Text(detail).helperTextStyle()
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    private func connect() {
        let candidate = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !isVerifying, !isConnected else { return }
        isVerifying = true
        error = nil
        Task {
            defer { isVerifying = false }
            var keys = APIKeys()
            keys.set(candidate, for: provider)
            do {
                _ = try await ImageService(keys: keys).accountStatus(for: provider)
                if app.saveKey(candidate, for: provider) {
                    isVerifying = false
                    isConnected = true
                    try? await Task.sleep(for: .seconds(0.6))
                    dismiss()
                } else {
                    self.error = L("Couldn't save the key on this Mac.")
                }
            } catch {
                self.error = error.localizedDescription
                rejections += 1
            }
        }
    }
}

extension View {
    func shake(_ trigger: Int) -> some View {
        modifier(ShakeEffect(trigger: trigger))
    }
}

private struct ShakeEffect: ViewModifier {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let still = reduceMotion
        return content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, offset in
            view.offset(x: still ? 0 : offset)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(6, duration: 0.07)
                CubicKeyframe(-6, duration: 0.07)
                CubicKeyframe(4, duration: 0.07)
                CubicKeyframe(-3, duration: 0.07)
                CubicKeyframe(0, duration: 0.07)
            }
        }
    }
}

extension Provider {
    var symbolName: String {
        switch self {
        case .openRouter: "point.3.connected.trianglepath.dotted"
        case .google: "g.circle"
        }
    }

    var onboardingNote: String {
        switch self {
        case .openRouter: L("Every model with a single key")
        case .google: L("Nano Banana models only")
        }
    }

    var onboardingSteps: [(text: String, link: (title: String, url: URL)?)] {
        switch self {
        case .openRouter: [
            (L("Create a free account."), (L("Open OpenRouter"), URL(string: "https://openrouter.ai")!)),
            (L("Add credit: $5 is enough for dozens of images."), (L("Add credit"), URL(string: "https://openrouter.ai/settings/credits")!)),
            (L("Create a key, copy it and paste it below."), (L("Create a key"), keyURL)),
        ]
        case .google: [
            (L("Sign in to Google AI Studio with your Google account."), (L("Open Google AI Studio"), URL(string: "https://aistudio.google.com")!)),
            (L("Create a key and copy it."), (L("Create a key"), keyURL)),
            (L("Paste it below."), nil),
        ]
        }
    }
}
