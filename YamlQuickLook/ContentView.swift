import SwiftUI
import UniformTypeIdentifiers

// MARK: - Root

struct ContentView: View {
    @ObservedObject private var appState: AppState = .shared

    var body: some View {
        TabView(selection: Binding(
            get: { appState.selectedTab },
            set: { appState.selectedTab = $0 }
        )) {
            StatusView()
                .tabItem { Label("Status", systemImage: "checkmark.seal") }
                .tag(ContentTab.status)

            PreviewView()
                .tabItem { Label("Preview", systemImage: "doc.text.magnifyingglass") }
                .tag(ContentTab.preview)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(ContentTab.settings)
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 520, idealHeight: 960)
    }
}

// MARK: - Status Tab

private struct StatusView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // App header
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.viewfinder")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .foregroundStyle(.blue)
                    Text("YAML Quick Look")
                        .font(.largeTitle.bold())
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        Text("Version \(version)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Text("Quick Look and Finder thumbnail previews for .yaml and .yml files")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)

                Divider()

                GlassEffectContainer(spacing: 16) {
                    VStack(spacing: 16) {
                        // Extension status
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Extension Status", systemImage: "puzzlepiece.extension")
                                .font(.headline)

                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Extension is bundled and ready")
                                        .fontWeight(.medium)
                                    Text("To activate Quick Look previews and Finder thumbnails, enable both extensions in System Settings → Privacy & Security → Extensions → Quick Look.")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Button {
                                NSWorkspace.shared.open(
                                    URL(string: "x-apple.systempreferences:com.apple.Extensions-Settings.QuickLookExtensions")!
                                )
                            } label: {
                                Label("Open Extension Settings…", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.glassProminent)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))

                        // How to use
                        VStack(alignment: .leading, spacing: 10) {
                            Label("How to Use", systemImage: "hand.point.up.left")
                                .font(.headline)

                            VStack(alignment: .leading, spacing: 8) {
                                StepRow(number: "1", text: "Enable both extensions in System Settings (see above)")
                                StepRow(number: "2", text: "Select any .yaml or .yml file in Finder")
                                StepRow(number: "3", text: "Press Space — the Quick Look preview appears instantly")
                                StepRow(number: "4", text: "Drag a YAML file to the Preview tab to test in-app")
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))

                        // Features
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Features", systemImage: "sparkles")
                                .font(.headline)

                            VStack(alignment: .leading, spacing: 6) {
                                FeatureRow(icon: "eye",                   text: "Quick Look preview for .yaml and .yml")
                                FeatureRow(icon: "photo",                  text: "Finder thumbnail generation")
                                FeatureRow(icon: "scroll",                 text: "Scrollable preview for large files")
                                FeatureRow(icon: "doc.badge.ellipsis",     text: "Safe handling of files up to 10 MB")
                                FeatureRow(icon: "character.textbox",      text: "UTF-8, Latin-1, and binary-safe reading")
                                FeatureRow(icon: "circle.lefthalf.filled", text: "Light and dark mode")
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular, in: .rect(cornerRadius: 12))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct StepRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(.blue))
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.callout)
    }
}

// MARK: - Preview Tab

private struct PreviewView: View {
    @ObservedObject private var appState: AppState = .shared
    @ObservedObject private var settings: PreviewSettings = .shared
    @State private var loadedContent: String?
    @State private var loadedFileName = ""
    @State private var isTargeted = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            if let content = loadedContent {
                fileHeader
                Divider()
                YAMLContentView(content: content)
            } else {
                DropZoneView(isTargeted: $isTargeted, error: loadError)
                    .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
            }
        }
        .onChange(of: appState.openedURL) { _, url in
            guard let url else { return }
            loadFile(at: url)
        }
        .onAppear {
            if let url = appState.openedURL { loadFile(at: url) }
        }
    }

    private var fileHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.fill")
                .foregroundStyle(.blue)
            Text(loadedFileName)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
            Spacer()
            Button("Clear") {
                loadedContent = nil
                loadedFileName = ""
                loadError = nil
                appState.openedURL = nil
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async { loadFile(at: url) }
        }
        return true
    }

    private func loadFile(at url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let result = try YAMLFileReader.read(fileAt: url)
            DispatchQueue.main.async {
                loadedContent = result.content
                loadedFileName = url.lastPathComponent
                loadError = nil
            }
        } catch {
            DispatchQueue.main.async {
                loadError = error.localizedDescription
                loadedContent = nil
                loadedFileName = ""
            }
        }
    }
}

private struct DropZoneView: View {
    @Binding var isTargeted: Bool
    let error: String?

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: isTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 52, height: 52)
                    .foregroundStyle(isTargeted ? .blue : .secondary)

                VStack(spacing: 4) {
                    Text("Drop a YAML file here")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(isTargeted ? .blue : .primary)
                    Text("or use \u{201C}Open With\u{201D} \u{2192} YAML Quick Look from Finder")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }
            }
            .padding(48)
            .glassEffect(
                isTargeted ? .regular.tint(.blue) : .regular,
                in: .rect(cornerRadius: 20)
            )
            .animation(.easeInOut(duration: 0.15), value: isTargeted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct YAMLContentView: View {
    let content: String
    @ObservedObject private var settings: PreviewSettings = .shared

    private var lines: [String] {
        // Cap at 5 000 lines to keep the UI responsive for very large files
        Array(
            content
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .components(separatedBy: "\n")
                .prefix(5_000)
        )
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 0) {
                if settings.showLineNumbers {
                    lineGutter
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 1)
                        .padding(.vertical, 10)
                }
                contentLines
                Spacer(minLength: 0)
            }
        }
        .background(Color(.textBackgroundColor))
    }

    private var lineGutter: some View {
        let gutterWidth = CGFloat(max("\(lines.count)".count, 2)) * settings.fontSize * 0.62 + 16
        return VStack(alignment: .trailing, spacing: 0) {
            ForEach(lines.indices, id: \.self) { i in
                Text("\(i + 1)")
                    .font(.system(size: settings.fontSize - 1, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: gutterWidth, alignment: .trailing)
                    .padding(.leading, 10)
                    .padding(.trailing, 8)
            }
        }
        .padding(.top, 10)
    }

    private var contentLines: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines.indices, id: \.self) { i in
                Text(lines[i].isEmpty ? "\u{200B}" : lines[i])
                    .font(.system(size: settings.fontSize, design: .monospaced))
                    .foregroundStyle(color(for: lines[i]))
                    .lineLimit(settings.wordWrap ? nil : 1)
                    .fixedSize(horizontal: !settings.wordWrap, vertical: true)
            }
        }
        .padding(10)
    }

    private func color(for line: String) -> Color {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") { return Color(nsColor: .systemGreen) }
        return .primary
    }
}

// MARK: - Settings Tab

private struct SettingsView: View {
    @ObservedObject private var settings: PreviewSettings = .shared

    var body: some View {
        Form {
            Section("In-App Preview") {
                HStack {
                    Text("Font Size")
                    Spacer()
                    Stepper(
                        value: $settings.fontSize,
                        in: 10...24,
                        step: 1
                    ) {
                        Text("\(Int(settings.fontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                }
                Toggle("Show Line Numbers", isOn: $settings.showLineNumbers)
                Toggle("Word Wrap", isOn: $settings.wordWrap)
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Quick Look Extension") {
                    Label("Bundled", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                }
                LabeledContent("Thumbnail Extension") {
                    Label("Bundled", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    ContentView()
}