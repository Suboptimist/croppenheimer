import WidgetKit
import SwiftUI

struct LauncherEntry: TimelineEntry {
    let date: Date
}

struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry {
        LauncherEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) {
        completion(LauncherEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) {
        // Static launcher widget - nothing to refresh.
        completion(Timeline(entries: [LauncherEntry(date: Date())], policy: .never))
    }
}

// Same rune as the app icon: an X whose lower arms continue into a diamond.
// Geometry mirrors AppIcon.icon/Assets/glyph.svg (1024-unit design grid);
// the stroke is baked into the path so the line width scales with the frame.
struct RuneShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1024
        let ox = rect.midX - 512 * s
        let oy = rect.midY - 512 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }
        var path = Path()
        path.move(to: p(512, 362))
        path.addLine(to: p(762, 637))
        path.addLine(to: p(512, 912))
        path.addLine(to: p(262, 637))
        path.closeSubpath()
        path.move(to: p(285, 112))
        path.addLine(to: p(512, 362))
        path.move(to: p(739, 112))
        path.addLine(to: p(512, 362))
        return path.strokedPath(StrokeStyle(lineWidth: 62 * s, lineCap: .butt, lineJoin: .miter))
    }
}

struct LauncherView: View {
    @Environment(\.widgetFamily) private var family

    private let ink = Color(red: 0.15, green: 0.15, blue: 0.17)

    var body: some View {
        content
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.84, blue: 0.25),
                        Color(red: 0.93, green: 0.58, blue: 0.06),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .widgetURL(URL(string: "croppenheimer://open"))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 16) {
                RuneShape()
                    .fill(ink)
                    .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Croppenheimer")
                        .font(.system(size: 19, weight: .bold, design: .serif))
                        .foregroundStyle(ink)
                    Text("\u{201C}I am become breadth.\u{201D}")
                        .font(.system(size: 13, design: .serif))
                        .italic()
                        .foregroundStyle(ink.opacity(0.8))
                    Text("Click to crop a photo")
                        .font(.system(size: 11))
                        .foregroundStyle(ink.opacity(0.55))
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(spacing: 9) {
                RuneShape()
                    .fill(ink)
                    .frame(width: 46, height: 46)
                Text("Croppenheimer")
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

struct CroppenheimerLauncherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CroppenheimerLauncher", provider: LauncherProvider()) { _ in
            LauncherView()
        }
        .configurationDisplayName("Croppenheimer")
        .description("Opens Croppenheimer to crop a photo.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CroppenheimerWidgetBundle: WidgetBundle {
    var body: some Widget {
        CroppenheimerLauncherWidget()
    }
}
