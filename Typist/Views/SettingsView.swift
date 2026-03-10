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
                    Button("Done") { dismiss() }
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
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink {
                AcknowledgementsView()
            } label: {
                Text("Acknowledgements")
            }
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
            ForEach(appFontLibrary.items) { item in
                appFontRow(item)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if let fileName = item.fileName, !item.isBuiltIn {
                            Button("Delete", role: .destructive) {
                                appFontLibrary.delete(fileName: fileName)
                            }
                        }
                    }
            }

            Button {
                showingFontPicker = true
            } label: {
                Label("Add Font…", systemImage: "plus.circle")
                    .foregroundStyle(.primary)
            }
        }
    }

    private func appFontRow(_ item: AppFontItem) -> some View {
        HStack {
            Label(item.displayName, systemImage: "character.textbox")
                .foregroundStyle(item.isBuiltIn ? .secondary : .primary)
            Spacer()
            Text(item.isBuiltIn ? L10n.fontScopeBuiltIn : L10n.fontScopeApp)
                .font(.caption)
                .foregroundStyle(.tertiary)
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
