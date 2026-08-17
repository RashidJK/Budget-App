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

// MARK: - Quick Add widget

// Tapping a tile opens the app on a "budget://" deep link that the Flutter
// side (HomeShell) routes to the matching capture flow.
struct QuickAction {
    let url: String
    let symbol: String
    let label: String
    let tint: Color
}

private let quickActions = [
    QuickAction(url: "budget://add", symbol: "plus", label: "Add", tint: .blue),
    QuickAction(url: "budget://income", symbol: "arrow.down.left", label: "Income", tint: .green),
    QuickAction(url: "budget://transfer", symbol: "arrow.left.arrow.right", label: "Transfer", tint: .purple),
    QuickAction(url: "budget://scan", symbol: "camera", label: "Scan", tint: .orange),
]

struct QuickAddEntry: TimelineEntry {
    let date: Date
}

struct QuickAddProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickAddEntry { QuickAddEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (QuickAddEntry) -> Void) {
        completion(QuickAddEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickAddEntry>) -> Void) {
        // Static content — never needs a scheduled refresh.
        completion(Timeline(entries: [QuickAddEntry(date: Date())], policy: .never))
    }
}

struct QuickAddEntryView: View {
    var entry: QuickAddProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(10)
            .widgetBackground(Color(.systemBackground))
    }

    @ViewBuilder
    private var content: some View {
        if family == .systemSmall {
            // A single tap area for the whole widget (works on all versions).
            tile(quickActions[0], big: true)
                .widgetURL(URL(string: quickActions[0].url))
        } else {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    linkTile(quickActions[0])
                    linkTile(quickActions[1])
                }
                HStack(spacing: 8) {
                    linkTile(quickActions[2])
                    linkTile(quickActions[3])
                }
            }
        }
    }

    private func linkTile(_ action: QuickAction) -> some View {
        Link(destination: URL(string: action.url)!) { tile(action, big: false) }
    }

    private func tile(_ action: QuickAction, big: Bool) -> some View {
        VStack(spacing: big ? 8 : 4) {
            Image(systemName: action.symbol)
                .font(.system(size: big ? 28 : 18, weight: .bold))
                .foregroundColor(action.tint)
            Text(action.label)
                .font(.system(size: big ? 15 : 12, weight: .semibold))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(action.tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct QuickAddWidget: Widget {
    let kind: String = "QuickAddWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickAddProvider()) { entry in
            QuickAddEntryView(entry: entry)
        }
        .configurationDisplayName("Quick Add")
        .description("Add an expense, income or transfer in one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct BudgetWidgetBundle: WidgetBundle {
    var body: some Widget {
        BudgetWidget()
        QuickAddWidget()
    }
}
