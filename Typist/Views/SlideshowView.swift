//
//  SlideshowView.swift
//  Typist
//
//  Full-screen PDF slideshow: one page at a time, swipe or arrow buttons to navigate.
//

import SwiftUI
import PDFKit

// MARK: - Slideshow

struct SlideshowView: View {
    let document: PDFDocument
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage: Int = 0
    @State private var showControls: Bool = true

    private var pageCount: Int { document.pageCount }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentPage) {
                ForEach(0..<pageCount, id: \.self) { index in
                    if let page = document.page(at: index) {
                        PDFSlideView(page: page)
                            .tag(index)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
            }

            if showControls {
                controlsOverlay
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: showControls)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
    }

    // MARK: Controls overlay

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            // ── Top bar ──────────────────────────────────────────────
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.title2.weight(.semibold))
                }
                .buttonStyle(.glass)

                Spacer()

                Text("\(currentPage + 1) / \(pageCount)")
                    .foregroundStyle(.white)
                    .font(.subheadline.monospacedDigit().bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            )

            Spacer()

            // ── Bottom bar ───────────────────────────────────────────
            HStack {
                navButton(systemImage: "chevron.left", enabled: currentPage > 0) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentPage = max(0, currentPage - 1)
                    }
                }

                Spacer()

                navButton(systemImage: "chevron.right", enabled: currentPage < pageCount - 1) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentPage = min(pageCount - 1, currentPage + 1)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            )
        }
    }

    @ViewBuilder
    private func navButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
        }
        .buttonStyle(.glass)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }
}

// MARK: - Per-page renderer

struct PDFSlideView: View {
    let page: PDFPage
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView().tint(.white)
            }
        }
        .ignoresSafeArea()
        .task { await renderPage() }
    }

    private func renderPage() async {
        let pageRect = page.bounds(for: .mediaBox)
        // Render at 2× for crisp Retina display.
        let scale: CGFloat = 4.0
        let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        image = page.thumbnail(of: size, for: .mediaBox)
    }
}
