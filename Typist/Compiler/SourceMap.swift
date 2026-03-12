//
//  SourceMap.swift
//  Typist
//
//  Bidirectional mapping between editor source locations and PDF positions.
//

import Foundation

struct SourceMapLocation: Sendable, Equatable {
    let page: Int
    let yPoints: Float
    let xPoints: Float
    let line: Int      // 1-based
    let column: Int    // 1-based
    let sourceOffset: Int
    let sourceLength: Int
}

struct SourceMap: Sendable {
    /// Entries sorted by source offset (for editor -> preview lookup).
    let byOffset: [SourceMapLocation]
    /// Entries sorted by (page, yPoints) (for preview -> editor lookup).
    let byPosition: [SourceMapLocation]

    var isEmpty: Bool { byOffset.isEmpty }

    /// Find the PDF position for a given 1-based line number.
    /// Returns the closest entry at or before the given line.
    func pdfPosition(forLine line: Int) -> SourceMapLocation? {
        guard !byOffset.isEmpty else { return nil }

        // Binary search for the first entry with line >= target.
        var lo = 0
        var hi = byOffset.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if byOffset[mid].line < line {
                lo = mid + 1
            } else {
                hi = mid
            }
        }

        // If exact match, use it; otherwise use the previous entry.
        if lo < byOffset.count && byOffset[lo].line == line {
            return byOffset[lo]
        } else if lo > 0 {
            return byOffset[lo - 1]
        }
        return byOffset.first
    }

    /// Find the source location for a tap at a given page and Y position.
    /// Returns the closest entry at or before the given Y on that page.
    func sourceLocation(forPage page: Int, yPoints: Float) -> SourceMapLocation? {
        guard !byPosition.isEmpty else { return nil }

        // Find entries on the target page.
        var lo = 0
        var hi = byPosition.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if byPosition[mid].page < page {
                lo = mid + 1
            } else {
                hi = mid
            }
        }

        let pageStart = lo
        lo = pageStart
        hi = byPosition.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if byPosition[mid].page <= page {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        let pageEnd = lo

        guard pageStart < pageEnd else { return nil }

        // Within this page's entries, find the closest Y.
        var bestIndex = pageStart
        var bestDist = abs(byPosition[pageStart].yPoints - yPoints)
        for i in (pageStart + 1)..<pageEnd {
            let dist = abs(byPosition[i].yPoints - yPoints)
            if dist < bestDist {
                bestDist = dist
                bestIndex = i
            }
        }

        return byPosition[bestIndex]
    }
}
