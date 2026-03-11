//
//  SettingsView.swift
//  Typist
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppFontLibrary.self) private var appFontLibrary
    @Environment(AppAppearanceManager.self) private var appAppearanceManager
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingZipImporter = false
    @State private var zipImportError: String?

    var onImport: (URL) -> Void

    private var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return L10n.format("settings.version_format", v, b)
    }

    private var typstVersionString: String? {
        guard let version = TypstBridge.runtimeVersion else { return nil }
        return L10n.format("settings.typst_version_format", version)
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                appearanceSection
                projectsSection
                fontsSection
                cacheSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        InteractionFeedback.impact(.light)
                        dismiss()
                    }
                    .accessibilityIdentifier("settings.done")
                }
            }
            .fileImporter(isPresented: $showingZipImporter, allowedContentTypes: [.zip]) { result in
                switch result {
                case .success(let url):
                    onImport(url)
                    dismiss()
                case .failure(let error):
                    zipImportError = error.localizedDescription
                }
            }
            .alert("Import Error", isPresented: Binding(
                get: { zipImportError != nil },
                set: { if !$0 { zipImportError = nil } }
            )) {
                Button("OK") { zipImportError = nil }
            } message: {
                Text(zipImportError ?? "")
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(spacing: 10) {
                appIconView
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    .accessibilityHidden(true)
                Text("Typist")
                    .font(.title2.bold())
                Text(versionString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let typstVersionString {
                    Text(typstVersionString)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.a11ySettingsHeaderLabel)
            .accessibilityValue(
                L10n.a11ySettingsHeaderValue(version: versionString, typstVersion: typstVersionString)
            )
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var appIconView: some View {
        if let icon = Bundle.main.appIcon {
            Image(uiImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.accentColor)
                .overlay(
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                )
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("App Appearance", selection: Binding(
                get: { appAppearanceManager.mode },
                set: { newMode in
                    withTransaction(Transaction(animation: nil)) {
                        appAppearanceManager.mode = newMode
                    }
                }
            )) {
                Text("Follow System").tag(AppAppearanceMode.system.rawValue)
                Text("Light").tag(AppAppearanceMode.light.rawValue)
                Text("Dark").tag(AppAppearanceMode.dark.rawValue)
            }

            Picker("Editor Theme", selection: Binding(
                get: { themeManager.themeID },
                set: { newID in
                    withTransaction(Transaction(animation: nil)) {
                        themeManager.themeID = newID
                    }
                }
            )) {
                Text("Auto").tag("system")
                Text("Mocha · Dark").tag("mocha")
                Text("Latte · Light").tag("latte")
            }
        }
    }

    private var projectsSection: some View {
        Section("Projects") {
            Button {
                showingZipImporter = true
            } label: {
                Label("Import ZIP", systemImage: "square.and.arrow.down")
                    .foregroundStyle(.primary)
            }
            .accessibilityIdentifier("settings.import-zip")
        }
    }

    private var fontsSection: some View {
        Section("Fonts") {
            NavigationLink {
                AppFontManagementView()
            } label: {
                HStack {
                    Label(L10n.appFontsTitle, systemImage: "character.textbox")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(
                        appFontLibrary.isEmpty
                            ? L10n.appFontsBuiltInOnlySummary
                            : L10n.appFontsImportedSummary(count: appFontLibrary.fileNames.count)
                    )
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("settings.fonts")
        }
    }

    private var cacheSection: some View {
        Section("Cache") {
            NavigationLink {
                PreviewPackageCacheManagementView()
            } label: {
                Label("Manage Package Cache", systemImage: "externaldrive.badge.person.crop")
                    .foregroundStyle(.primary)
            }
            .accessibilityIdentifier("settings.cache")
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink {
                AcknowledgementsView()
            } label: {
                Text("Acknowledgements")
            }
            .accessibilityIdentifier("settings.acknowledgements")
        }
    }
}

private struct AppFontManagementView: View {
    @Environment(AppFontLibrary.self) private var appFontLibrary

    @State private var showingFontPicker = false
    @State private var actionError: String?

    var body: some View {
        List {
            overviewSection
            fontsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.appFontsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showingFontPicker,
            allowedContentTypes: [.font],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else {
                if case .failure(let error) = result {
                    actionError = error.localizedDescription
                }
                return
            }

            do {
                try appFontLibrary.importFonts(from: urls)
            } catch {
                actionError = error.localizedDescription
            }
        }
        .alert(L10n.appFontsErrorTitle, isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private var overviewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.appFontsOverviewTitle)
                    .font(.body.weight(.medium))
                Text(L10n.appFontsOverviewDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var fontsSection: some View {
        Section(L10n.appFontsTitle) {
            ExpandableFontList(
                groups: appFontLibrary.groupedItems,
                scopeLabel: { $0.isBuiltIn ? L10n.fontScopeBuiltIn : L10n.fontScopeApp },
                onDeleteGroup: { group in
                    guard !group.isBuiltIn else { return }
                    InteractionFeedback.notify(.warning)
                    for fileName in group.fileNames {
                        appFontLibrary.delete(fileName: fileName)
                    }
                }
            )

            Button {
                InteractionFeedback.impact(.light)
                showingFontPicker = true
            } label: {
                Label("Add Font…", systemImage: "plus.circle")
                    .foregroundStyle(.primary)
            }
        }
    }
}

struct ExpandableFontList: View {
    let groups: [AppFontGroup]
    let scopeLabel: (AppFontGroup) -> String
    var onDeleteGroup: ((AppFontGroup) -> Void)? = nil

    @State private var expandedGroupIDs: Set<String> = []
    private let previewText = "AaBb 0123456789 .,!? 中文预览"

    private var visibleRows: [VisibleFontRow] {
        var rows: [VisibleFontRow] = []
        for group in groups {
            let isExpanded = expandedGroupIDs.contains(group.id)
            rows.append(VisibleFontRow(kind: .group(group), depth: 0, isExpanded: isExpanded))
            if isExpanded, group.count > 1 {
                for face in group.faces {
                    rows.append(VisibleFontRow(kind: .face(groupID: group.id, face: face), depth: 1, isExpanded: false))
                }
            }
        }
        return rows
    }

    var body: some View {
        ForEach(visibleRows) { row in
            switch row.kind {
            case .group(let group):
                Button {
                    guard group.count > 1 else { return }
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0.03)) {
                        if expandedGroupIDs.contains(group.id) {
                            expandedGroupIDs.remove(group.id)
                        } else {
                            expandedGroupIDs.insert(group.id)
                        }
                    }
                } label: {
                    fontGroupRowLabel(for: group, row: row)
                }
                .buttonStyle(FontListRowButtonStyle())
                .contentShape(Rectangle())
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if let onDeleteGroup, !group.fileNames.isEmpty {
                        Button("Delete", role: .destructive) {
                            onDeleteGroup(group)
                        }
                    }
                }
            case .face(_, let face):
                fontFaceRowLabel(face: face, depth: row.depth)
                    .padding(.vertical, 2)
            }
        }
    }

    private func fontGroupRowLabel(for group: AppFontGroup, row: VisibleFontRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                if group.count > 1 {
                    Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12, height: 18, alignment: .center)
                } else {
                    Color.clear
                        .frame(width: 12, height: 18)
                }
                Image(systemName: "character.textbox")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 16))
                    .frame(width: 22, height: 18, alignment: .center)
                Text(group.familyName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if group.count > 1 {
                    Text(L10n.fontFacesCount(group.count))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(scopeLabel(group))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            FontPreviewLine(
                fontPath: group.previewPath,
                text: previewText,
                fallbackTextStyle: .caption1
            )
            .padding(.leading, 54)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(0.9)
        }
        .padding(.leading, CGFloat(row.depth) * 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func fontFaceRowLabel(face: AppFontFace, depth: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Color.clear
                    .frame(width: 12, height: 18)
                Color.clear
                    .frame(width: 22, height: 18)
                Text(face.displayName)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }

            FontPreviewLine(
                fontPath: face.path,
                text: previewText,
                fallbackTextStyle: .caption2
            )
            .padding(.leading, 54)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(0.9)
        }
        .padding(.leading, CGFloat(depth) * 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct VisibleFontRow: Identifiable {
    enum Kind {
        case group(AppFontGroup)
        case face(groupID: String, face: AppFontFace)
    }

    let kind: Kind
    let depth: Int
    let isExpanded: Bool

    var id: String {
        switch kind {
        case .group(let group):
            return "group:\(group.id)"
        case .face(let groupID, let face):
            return "face:\(groupID):\(face.id)"
        }
    }
}

private struct FontListRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct FontGroupRow: View {
    let group: AppFontGroup
    let scopeLabel: String

    var body: some View {
        ExpandableFontList(groups: [group], scopeLabel: { _ in scopeLabel })
    }
}

private struct FontPreviewLine: UIViewRepresentable {
    let fontPath: String?
    let text: String
    let fallbackTextStyle: UIFont.TextStyle

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.55
        label.lineBreakMode = .byTruncatingTail
        label.textColor = UIColor.secondaryLabel
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.text = text
        if let fontPath, !fontPath.isEmpty,
           let font = FontManager.previewUIFont(forFontAtPath: fontPath, size: 13) {
            label.font = font
        } else {
            label.font = UIFont.preferredFont(forTextStyle: fallbackTextStyle)
        }
    }
}

private struct PreviewPackageCacheManagementView: View {
    @State private var snapshot = PreviewPackageCacheSnapshot(entries: [])
    @State private var isLoading = true
    @State private var cacheError: String?
    @State private var showingClearAllConfirmation = false

    private let store = PreviewPackageCacheStore()

    var body: some View {
        List {
            overviewSection
            packagesSection
            actionsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Package Cache")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
        .alert("Cache Error", isPresented: Binding(
            get: { cacheError != nil },
            set: { if !$0 { cacheError = nil } }
        )) {
            Button("OK") { cacheError = nil }
        } message: {
            Text(cacheError ?? "")
        }
        .alert("Clear All Package Cache?", isPresented: $showingClearAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                Task { await clearAll() }
            }
        } message: {
            Text("This removes all downloaded @preview packages. They will be downloaded again on the next compile.")
        }
    }

    private var overviewSection: some View {
        Section("Overview") {
            HStack {
                Label("Total Size", systemImage: "internaldrive")
                Spacer()
                if isLoading {
                    ProgressView()
                } else {
                    Text(formattedSize(snapshot.totalSizeInBytes))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Label("Cached Packages", systemImage: "shippingbox")
                Spacer()
                Text("\(snapshot.entries.count)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var packagesSection: some View {
        Section("Packages") {
            if !isLoading && snapshot.entries.isEmpty {
                Text("No cached @preview packages")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.displayName)
                                .font(.body.weight(.medium))
                            Text(entry.version)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(formattedSize(entry.sizeInBytes))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) {
                            Task { await delete(entry) }
                        }
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button("Clear All Package Cache", role: .destructive) {
                showingClearAllConfirmation = true
            }
            .disabled(isLoading || snapshot.entries.isEmpty)
        }
    }

    private func refresh() async {
        isLoading = true
        do {
            let rootURL = store.rootURL
            let latestSnapshot = try await Task.detached(priority: .userInitiated) {
                try PreviewPackageCacheStore(rootURL: rootURL).snapshot()
            }.value
            await MainActor.run {
                snapshot = latestSnapshot
                isLoading = false
            }
        } catch {
            await MainActor.run {
                cacheError = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func delete(_ entry: PreviewPackageCacheEntry) async {
        do {
            let rootURL = store.rootURL
            try await Task.detached(priority: .userInitiated) {
                try PreviewPackageCacheStore(rootURL: rootURL).remove(entry)
            }.value
            await refresh()
        } catch {
            await MainActor.run {
                cacheError = error.localizedDescription
            }
        }
    }

    private func clearAll() async {
        do {
            let rootURL = store.rootURL
            try await Task.detached(priority: .userInitiated) {
                try PreviewPackageCacheStore(rootURL: rootURL).clearAll()
            }.value
            await refresh()
        } catch {
            await MainActor.run {
                cacheError = error.localizedDescription
            }
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Acknowledgements

private struct AcknowledgementsView: View {
    var body: some View {
        List {
            Section {
                creditRow(
                    name: "Typst",
                    detail: "The open-source typesetting system at the core of Typist.",
                    license: "Apache 2.0",
                    url: "https://typst.app"
                )
                creditRow(
                    name: "Catppuccin",
                    detail: "Soothing pastel color palette powering the editor themes.",
                    license: "MIT",
                    url: "https://github.com/catppuccin/catppuccin"
                )
                creditRow(
                    name: "Source Han Sans / Serif",
                    detail: "Bundled CJK fonts used as default fallbacks in Typist.",
                    license: "OFL-1.1",
                    url: "https://github.com/adobe-fonts/source-han-sans"
                )
                creditRow(
                    name: "swift-bridge",
                    detail: "Reference implementation for Swift/Rust interop.",
                    license: "MIT or Apache-2.0",
                    url: "https://github.com/chinedufn/swift-bridge"
                )
            }
            Section("Special Thanks") {
                creditRow(
                    name: "Donut",
                    detail: "Thanks to everyone at Donut for support and inspiration.",
                    license: nil,
                    url: "https://donutblogs.com/"
                )
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func creditRow(name: String, detail: LocalizedStringKey, license: String?, url: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.headline)
                Spacer()
                if let license {
                    Text(license)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.secondary.opacity(0.12), in: Capsule())
                }
            }
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let link = URL(string: url) {
                Link(url, destination: link)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Bundle app icon helper

private extension Bundle {
    var appIcon: UIImage? {
        if let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let name = files.last {
            return UIImage(named: name)
        }
        return UIImage(named: "AppIcon")
    }
}
