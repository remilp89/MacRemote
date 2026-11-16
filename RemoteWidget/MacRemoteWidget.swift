import WidgetKit
import SwiftUI
import AppIntents

struct MacsEntry: TimelineEntry {
    let date: Date
    let macs: [SharedStore.Entry]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> MacsEntry {
        MacsEntry(date: Date(), macs: [.init(name: "Mon Mac", manual: false, lastUsed: Date())])
    }
    func getSnapshot(in context: Context, completion: @escaping (MacsEntry) -> Void) {
        completion(MacsEntry(date: Date(), macs: SharedStore.recent()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MacsEntry>) -> Void) {
        completion(Timeline(entries: [MacsEntry(date: Date(), macs: SharedStore.recent())], policy: .never))
    }
}

struct MacRemoteWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MacsEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "computermouse.fill").font(.title2)
            }
            .widgetURL(entry.macs.first.map(SharedStore.connectURL))
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label("MacRemote", systemImage: "computermouse.fill").font(.headline)
                Text(entry.macs.first?.name ?? "Ouvrir l'app").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(entry.macs.first.map(SharedStore.connectURL))
        case .systemMedium:
            VStack(alignment: .leading, spacing: 8) {
                Label("MacRemote", systemImage: "computermouse.fill").font(.caption).foregroundStyle(.secondary)
                if entry.macs.isEmpty {
                    Text("Ouvre l'app et connecte un Mac une première fois.").font(.footnote)
                }
                ForEach(entry.macs.prefix(3)) { mac in
                    Link(destination: SharedStore.connectURL(mac)) {
                        HStack {
                            Image(systemName: "desktopcomputer")
                            Text(mac.name).lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                Spacer(minLength: 0)
            }
        default: // systemSmall
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "computermouse.fill").font(.title)
                Spacer()
                Text(entry.macs.first?.name ?? "Aucun Mac").font(.headline).lineLimit(2)
                Text(entry.macs.isEmpty ? "Ouvre l'app" : "Piloter").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(entry.macs.first.map(SharedStore.connectURL))
        }
    }
}

struct MacRemoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MacRemoteWidget", provider: Provider()) { entry in
            MacRemoteWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("MacRemote")
        .description("Reconnecte tes Macs en un tap.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: Centre de contrôle (iOS 18+)

struct OpenMacRemoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Ouvrir MacRemote"
    static let openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult { .result() }
}

@available(iOS 18.0, *)
struct MacRemoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.macremote.control") {
            ControlWidgetButton(action: OpenMacRemoteIntent()) {
                Label("MacRemote", systemImage: "computermouse.fill")
            }
        }
        .displayName("MacRemote")
        .description("Ouvre MacRemote et reconnecte le dernier Mac.")
    }
}

@main
struct MacRemoteWidgetBundle: WidgetBundle {
    var body: some Widget {
        MacRemoteWidget()
        if #available(iOS 18.0, *) { MacRemoteControl() }
    }
}
