//
//  SettingsView.swift
//  Typist
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingZipImporter = false
    @State private var zipImportError: String?

    var onImport: (URL) -> Void

    private var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                appearanceSection
                projectsSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.catppuccinBase)
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
        .id(themeManager.themeID)
        .preferredColorScheme(themeManager.colorScheme)
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
                .fill(Color.catppuccinBlue)
                .overlay(
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                )
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: Binding(
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
            .listRowBackground(Color.catppuccinElevated)
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
            .listRowBackground(Color.catppuccinElevated)
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink {
                AcknowledgementsView()
            } label: {
                Text("Acknowledgements")
            }
            .listRowBackground(Color.catppuccinElevated)
        }
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
                .listRowBackground(Color.catppuccinElevated)
                creditRow(
                    name: "Catppuccin",
                    detail: "Soothing pastel color palette powering the editor themes.",
                    license: "MIT",
                    url: "https://github.com/catppuccin/catppuccin"
                )
                .listRowBackground(Color.catppuccinElevated)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.catppuccinBase)
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func creditRow(name: String, detail: String, license: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.headline)
                Spacer()
                Text(license)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.12), in: Capsule())
            }
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let link = URL(string: url) {
                Link(url, destination: link)
                    .font(.caption)
                    .tint(.catppuccinBlue)
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
