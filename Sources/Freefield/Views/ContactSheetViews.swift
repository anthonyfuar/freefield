import FreefieldCore
import SwiftUI
import UniformTypeIdentifiers

extension AppItem {
    func cellGrid(for asset: Asset) -> (columns: Int, rows: Int)? {
        guard splitsIntoCells, asset.parentAssetID == nil, !asset.isVideo else { return nil }
        for text in [asset.prompt, asset.finalPrompt] {
            if let match = text.firstMatch(of: /([2-6])\s*[×x]\s*([2-6])/),
               let columns = Int(match.1), let rows = Int(match.2) {
                return (columns, rows)
            }
        }
        return nil
    }
}

nonisolated enum ContactSheet {
    @concurrent
    static func cells(at url: URL, columns: Int, rows: Int) async -> [CGRect] {
        detectCells(at: url, columns: columns, rows: rows)
    }

    @concurrent
    static func crop(_ url: URL, cell: CGRect) async -> Data? {
        guard let data = try? Data(contentsOf: url), let image = ImageCoding.cgImage(from: data) else { return nil }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let rect = CGRect(x: cell.minX * width, y: cell.minY * height, width: cell.width * width, height: cell.height * height)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard rect.width >= 8, rect.height >= 8, let cropped = image.cropping(to: rect) else { return nil }
        return ImageCoding.encode(cropped, as: .png)
    }

    static func evenCells(columns: Int, rows: Int) -> [CGRect] {
        (0..<rows).flatMap { row in
            (0..<columns).map { column in
                CGRect(x: Double(column) / Double(columns), y: Double(row) / Double(rows),
                       width: 1 / Double(columns), height: 1 / Double(rows))
            }
        }
    }

    static func detectCells(at url: URL, columns: Int, rows: Int) -> [CGRect] {
        let even = evenCells(columns: columns, rows: rows)
        guard let data = try? Data(contentsOf: url), let image = ImageCoding.cgImage(from: data, maxPixel: 600) else { return even }
        let width = image.width, height = image.height
        guard width >= columns * 8, height >= rows * 8 else { return even }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return even }
        let columnFlat = (0..<width).map { x in isFlat(stride(from: x, to: width * height, by: width).map { pixels[$0] }) }
        let rowFlat = (0..<height).map { y in isFlat(Array(pixels[(y * width)..<((y + 1) * width)])) }
        guard let xs = spans(columnFlat, count: columns), let ys = spans(rowFlat, count: rows) else { return even }
        return ys.flatMap { y in
            xs.map { x in
                CGRect(x: Double(x.lowerBound) / Double(width), y: Double(y.lowerBound) / Double(height),
                       width: Double(x.count) / Double(width), height: Double(y.count) / Double(height))
            }
        }
    }

    private static func isFlat(_ values: [UInt8]) -> Bool {
        guard !values.isEmpty else { return false }
        let count = Double(values.count)
        let mean = values.reduce(0.0) { $0 + Double($1) } / count
        let variance = values.reduce(0.0) { $0 + (Double($1) - mean) * (Double($1) - mean) } / count
        return variance.squareRoot() < 9
    }

    private static func spans(_ flat: [Bool], count: Int) -> [Range<Int>]? {
        let length = flat.count
        let cell = Double(length) / Double(count)
        var start = 0
        while start < Int(cell * 0.2), flat[start] { start += 1 }
        var end = length
        while end > length - Int(cell * 0.2), flat[end - 1] { end -= 1 }
        let window = max(2, Int(cell * 0.12))
        var gutters: [Range<Int>] = []
        for index in 1..<count {
            let expected = Int((Double(index) * cell).rounded())
            let candidates = (max(0, expected - window)...min(length - 1, expected + window)).filter { flat[$0] }
            guard let nearest = candidates.min(by: { abs($0 - expected) < abs($1 - expected) }) else {
                gutters.append(expected..<expected)
                continue
            }
            var low = nearest, high = nearest + 1
            while low > 0, flat[low - 1], expected - (low - 1) <= window * 2 { low -= 1 }
            while high < length, flat[high], high - expected <= window * 2 { high += 1 }
            gutters.append(low..<high)
        }
        let edges = [start..<start] + gutters + [end..<end]
        let inset = 1
        var result: [Range<Int>] = []
        for index in 0..<count {
            let lower = edges[index].upperBound + inset, upper = edges[index + 1].lowerBound - inset
            guard upper - lower >= Int(cell * 0.6) else { return nil }
            result.append(lower..<upper)
        }
        return result
    }
}

struct ContactSheetPicker: View {
    let item: AppItem
    @Binding var selectedID: UUID?

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cells: [CGRect] = []
    @State private var cellsFor: UUID?
    @State private var hovered: Int?
    @State private var working: Int?
    @State private var kept: [String: UUID] = [:]
    @State private var lastKeptID: UUID?
    @State private var failed = false

    private var sheet: Asset? {
        if let selectedID, let asset = app.library.asset(selectedID), asset.appID == item.id, item.cellGrid(for: asset) != nil {
            return asset
        }
        return app.library.assets.first { $0.tool == .app && $0.appID == item.id && item.cellGrid(for: $0) != nil }
    }

    var body: some View {
        if let sheet, let grid = item.cellGrid(for: sheet) {
            PanelSection(title: L("Keep one variation"), systemImage: "crop") {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text(L("Click a cell to save it as its own image at full size. Cutting it out is free: it happens on your Mac."))
                        .helperTextStyle()
                        .fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: Spacing.l) {
                            sheetView(sheet, grid: grid)
                                .frame(maxWidth: 460)
                            keptPanel
                                .frame(width: 240, alignment: .leading)
                        }
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            sheetView(sheet, grid: grid)
                                .frame(maxWidth: 460)
                            keptPanel
                        }
                    }
                }
            }
            .task(id: sheet.id) { await loadCells(sheet, grid: grid) }
        }
    }

    private func sheetView(_ sheet: Asset, grid: (columns: Int, rows: Int)) -> some View {
        Color.clear
            .aspectRatio(sheet.aspect, contentMode: .fit)
            .overlay {
                ThumbnailImage(url: app.library.url(for: sheet), maxPixel: 1400, contentMode: .fit)
            }
            .overlay {
                GeometryReader { proxy in
                    let size = proxy.size
                    ForEach(Array(shownCells(grid).enumerated()), id: \.offset) { index, cell in
                        cellButton(index: index, sheet: sheet, total: grid.columns * grid.rows)
                            .frame(width: cell.width * size.width, height: cell.height * size.height)
                            .position(x: cell.midX * size.width, y: cell.midY * size.height)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: Radius.tile))
    }

    private func cellButton(index: Int, sheet: Asset, total: Int) -> some View {
        let isKept = kept["\(sheet.id)-\(index)"] != nil
        let isHovered = hovered == index
        return Button {
            keep(index, of: sheet, total: total)
        } label: {
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(isHovered ? 0 : 0.0001))
                if working == index {
                    ProgressView().controlSize(.small)
                        .padding(8)
                        .background(.regularMaterial, in: .circle)
                } else if isKept {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.brand)
                        .shadow(radius: 3)
                } else if isHovered {
                    Label(L("Keep"), systemImage: "crop")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.regularMaterial, in: .capsule)
                }
            }
            .overlay {
                Rectangle()
                    .strokeBorder(isHovered || isKept ? Color.brand : .clear, lineWidth: 2.5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(working != nil)
        .onHover { inside in
            withAnimation(reduceMotion ? nil : Motion.standard) {
                if inside { hovered = index } else if hovered == index { hovered = nil }
            }
        }
        .help(L("Save variation %ld of %ld as its own image", index + 1, total))
        .accessibilityLabel(L("Variation %ld of %ld", index + 1, total))
    }

    @ViewBuilder private var keptPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let lastKeptID, let asset = app.library.asset(lastKeptID) {
                Text(L("Saved to your Library")).groupTitleStyle()
                Color.clear
                    .aspectRatio(asset.aspect, contentMode: .fit)
                    .overlay { ThumbnailImage(url: app.library.url(for: asset), maxPixel: 600, contentMode: .fill) }
                    .clipShape(.rect(cornerRadius: Radius.thumb))
                    .frame(maxHeight: 200)
                    .onTapGesture(count: 2) { app.quickLook(asset) }
                Text(L("%ld × %ld pixels", asset.width, asset.height)).fineTextStyle()
                Button(L("Improve Quality"), systemImage: Tool.upscale.systemImage) { app.open(.upscale, with: asset) }
                    .buttonStyle(.glassProminent)
                    .help(L("Opens Improve Quality with this variation, to make it sharper and bigger (2K or 4K)"))
                Button(L("View"), systemImage: "eye") { app.quickLook(asset) }
                    .buttonStyle(.glass)
            } else {
                Label(L("Tip: pick your favorite, then send it to Improve Quality for a sharp 4K version."), systemImage: "lightbulb")
                    .helperTextStyle()
                    .fixedSize(horizontal: false, vertical: true)
            }
            if failed {
                Label(L("Couldn't cut out that cell. Try again."), systemImage: "exclamationmark.triangle")
                    .fineTextStyle()
                    .foregroundStyle(.orange)
            }
        }
        .controlSize(.regular)
    }

    private func shownCells(_ grid: (columns: Int, rows: Int)) -> [CGRect] {
        cells.count == grid.columns * grid.rows ? cells : ContactSheet.evenCells(columns: grid.columns, rows: grid.rows)
    }

    private func loadCells(_ sheet: Asset, grid: (columns: Int, rows: Int)) async {
        guard cellsFor != sheet.id else { return }
        cells = ContactSheet.evenCells(columns: grid.columns, rows: grid.rows)
        let detected = await ContactSheet.cells(at: app.library.url(for: sheet), columns: grid.columns, rows: grid.rows)
        cells = detected
        cellsFor = sheet.id
        hovered = nil
    }

    private func keep(_ index: Int, of sheet: Asset, total: Int) {
        let key = "\(sheet.id)-\(index)"
        if let existing = kept[key], app.library.asset(existing) != nil {
            lastKeptID = existing
            return
        }
        guard let grid = item.cellGrid(for: sheet) else { return }
        let cell = shownCells(grid)[index]
        let url = app.library.url(for: sheet)
        working = index
        failed = false
        Task {
            let data = await ContactSheet.crop(url, cell: cell)
            working = nil
            guard let data else {
                failed = true
                return
            }
            var template = sheet
            template.id = UUID()
            template.createdAt = .now
            template.batchID = UUID()
            template.cost = nil
            template.isFavorite = false
            template.parentAssetID = sheet.id
            template.prompt = "\(sheet.prompt) · cell \(index + 1) of \(total)"
            let asset = app.library.add(GeneratedImage(data: data, mimeType: "image/png"), template: template)
            kept[key] = asset.id
            withAnimation(reduceMotion ? nil : Motion.standard) { lastKeptID = asset.id }
        }
    }
}
