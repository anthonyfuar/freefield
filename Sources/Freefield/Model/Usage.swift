import Foundation
import FreefieldCore

struct UsageEntry: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case image
        case text
        case local
        case video
    }

    var id = UUID()
    var date: Date
    var kind: Kind
    var tool: Tool?
    var title: String
    var modelID: String
    var modelName: String
    var provider: Provider?
    var cost: Double
    var isEstimated: Bool
    var imageCount: Int
    var assetIDs: [UUID]
    var seconds: Double?
    var appID: String?
}

enum UsagePeriod: Hashable {
    case today
    case week
    case month
    case custom(start: Date, end: Date)

    func interval(now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .today:
            return calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 86_400)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 604_800)
        case .month:
            return calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 2_592_000)
        case .custom(let start, let end):
            let from = calendar.startOfDay(for: min(start, end))
            let to = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(start, end))) ?? max(start, end)
            return DateInterval(start: from, end: to)
        }
    }
}

struct UsageLimits: Equatable {
    var daily: Double?
    var weekly: Double?
    var monthly: Double?

    static let dailyKey = "limitDaily", weeklyKey = "limitWeekly", monthlyKey = "limitMonthly"

    static func load(_ defaults: UserDefaults = .standard) -> UsageLimits {
        func value(_ key: String) -> Double? {
            let amount = defaults.double(forKey: key)
            return amount > 0 ? amount : nil
        }
        return UsageLimits(daily: value(dailyKey), weekly: value(weeklyKey), monthly: value(monthlyKey))
    }

    var all: [(period: UsagePeriod, amount: Double, name: String)] {
        var result: [(UsagePeriod, Double, String)] = []
        if let daily { result.append((.today, daily, L("daily"))) }
        if let weekly { result.append((.week, weekly, L("weekly"))) }
        if let monthly { result.append((.month, monthly, L("monthly"))) }
        return result
    }
}

extension Library {
    static func migratedUsage(from assets: [Asset]) -> [UsageEntry] {
        let batches = Dictionary(grouping: assets.filter { $0.tool != .imported }, by: \.batchID)
        return batches.values.compactMap { group -> UsageEntry? in
            guard let first = group.min(by: { $0.createdAt < $1.createdAt }) else { return nil }
            let local = first.modelID.hasPrefix("local:")
            return UsageEntry(
                date: first.createdAt, kind: local ? .local : .image, tool: first.tool, title: first.prompt,
                modelID: first.modelID, modelName: first.modelDisplayName, provider: local ? nil : first.provider,
                cost: group.compactMap(\.cost).reduce(0, +), isEstimated: group.contains { $0.cost == nil && !local },
                imageCount: group.count, assetIDs: group.map(\.id)
            )
        }
        .sorted { $0.date > $1.date }
    }
}
