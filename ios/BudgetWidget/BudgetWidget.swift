import WidgetKit
import SwiftUI

// Must match HomeWidgetBridge.appGroupId on the Flutter side.
private let appGroupId = "group.com.kadingo.budget"

struct BudgetEntry: TimelineEntry {
    let date: Date
    let month: String
    let spent: String
    let income: String
    let net: String
    let netValue: Double
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> BudgetEntry {
        BudgetEntry(date: Date(), month: "This month", spent: "TSh 0",
                    income: "TSh 0", net: "TSh 0", netValue: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (BudgetEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BudgetEntry>) -> Void) {
        // The app reloads the widget on every change; this is just a safety net.
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date()
        completion(Timeline(entries: [readEntry()], policy: .after(next)))
    }

    private func readEntry() -> BudgetEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        return BudgetEntry(
            date: Date(),
            month: defaults?.string(forKey: "month") ?? "This month",
            spent: defaults?.string(forKey: "spent") ?? "TSh 0",
            income: defaults?.string(forKey: "income") ?? "TSh 0",
            net: defaults?.string(forKey: "net") ?? "TSh 0",
            netValue: defaults?.double(forKey: "netValue") ?? 0
        )
    }
}

struct BudgetWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    private var netColor: Color {
        entry.netValue < 0 ? .red : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.month.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            Text(entry.spent)
                .font(.system(size: family == .systemSmall ? 22 : 30, weight: .bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text("spent this month")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if family != .systemSmall {
                Spacer(minLength: 8)
                HStack(spacing: 20) {
                    stat(label: "Income", value: entry.income, color: .primary)
                    stat(label: "Net", value: entry.net, color: netColor)
                    Spacer()
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .widgetBackground(Color(.systemBackground))
    }

    private func stat(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }
}

extension View {
    // containerBackground is required on iOS 17+ but unavailable before it.
    @ViewBuilder
    func widgetBackground(_ color: Color) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(color, for: .widget)
        } else {
            background(color)
        }
    }
}

struct BudgetWidget: Widget {
    let kind: String = "BudgetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            BudgetWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Budget")
        .description("Your spending this month at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct BudgetWidgetBundle: WidgetBundle {
    var body: some Widget {
        BudgetWidget()
    }
}
