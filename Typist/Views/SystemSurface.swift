//
//  SystemSurface.swift
//  Typist
//

import SwiftUI

extension View {
    @ViewBuilder
    func systemFloatingSurface(cornerRadius: CGFloat = 12) -> some View {
        if #available(iOS 26, *) {
            self
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
                }
        }
    }
}
