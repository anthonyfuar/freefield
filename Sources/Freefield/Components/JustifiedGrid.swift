import SwiftUI

enum JustifiedLayout {
    struct Cell {
        let index: Int
        let id: UUID
        let size: CGSize
    }

    static func rows(_ items: [(id: UUID, aspect: Double)], width: CGFloat, targetHeight: CGFloat, spacing: CGFloat) -> [[Cell]] {
        guard width > 0 else { return [] }
        var rows: [[Cell]] = []
        var pending: [(index: Int, id: UUID, aspect: Double)] = []
        var aspectSum = 0.0

        func flush(stretch: Bool) {
            guard !pending.isEmpty else { return }
            let gaps = spacing * CGFloat(pending.count - 1)
            let fittedHeight = (width - gaps) / CGFloat(aspectSum)
            let height = stretch ? fittedHeight : min(fittedHeight, targetHeight)
            rows.append(pending.map { Cell(index: $0.index, id: $0.id, size: CGSize(width: CGFloat($0.aspect) * height, height: height)) })
            pending.removeAll()
            aspectSum = 0
        }

        for (index, item) in items.enumerated() {
            let raw = item.aspect
            let aspect = raw.isFinite && raw > 0 ? min(max(raw, 0.25), 4) : 1
            pending.append((index, item.id, aspect))
            aspectSum += aspect
            let rowWidth = CGFloat(aspectSum) * targetHeight + spacing * CGFloat(pending.count - 1)
            if rowWidth >= width { flush(stretch: true) }
        }
        flush(stretch: false)
        return rows
    }
}

struct JustifiedAssetGrid<Cell: View>: View {
    let assets: [Asset]
    var targetHeight: CGFloat = 200
    var spacing: CGFloat = 6
    @ViewBuilder var cell: (Asset, CGSize) -> Cell

    @State private var width: CGFloat = 0

    var body: some View {
        let rows = JustifiedLayout.rows(assets.map { ($0.id, $0.aspect) }, width: width, targetHeight: targetHeight, spacing: spacing)
        LazyVStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.id) { item in
                        cell(assets[item.index], item.size)
                            .frame(width: item.size.width, height: item.size.height)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
    }
}
