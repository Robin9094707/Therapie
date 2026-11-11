import SwiftUI
import UIKit

// MARK: - Liquid Glass design system
//
// Every screen shares these building blocks. Content cards, chips and controls use
// the system Liquid Glass material; "Transparenz reduzieren" falls back to opaque
// grouped surfaces, and "Ruhige Oberfläche" softens the ambient colour field.

enum TherapyDesign {
    static let contentMaxWidth: CGFloat = 720
    static let cardRadius: CGFloat = 24
    static let tileRadius: CGFloat = 20
    static let insetRadius: CGFloat = 14
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    static let appName = "Kompass"
    static let appTagline = "Therapie & Betreutes Wohnen"
    static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "7000.0.0" }
}

private struct TherapyAccentKey: EnvironmentKey {
    static let defaultValue: AppAccent = .indigo
}
private struct TherapySurfaceKey: EnvironmentKey {
    static let defaultValue = SurfacePreferences()
}

extension EnvironmentValues {
    /// The chosen accent theme, so backgrounds in sheets can derive their companion hue.
    var therapyAccent: AppAccent {
        get { self[TherapyAccentKey.self] }
        set { self[TherapyAccentKey.self] = newValue }
    }
    /// The chosen glass style, coverage and tint strength.
    var therapySurface: SurfacePreferences {
        get { self[TherapySurfaceKey.self] }
        set { self[TherapySurfaceKey.self] = newValue }
    }
}

extension AppAccent {
    /// A calm second hue that keeps the ambient background alive without fighting the accent.
    var companion: Color {
        switch self {
        case .indigo: .teal
        case .blue: .cyan
        case .purple: .pink
        case .red: .orange
        case .teal: .blue
        case .green: .mint
        case .rose: .purple
        case .amber: .pink
        }
    }
}

struct TherapyGlassModifier<S: Shape>: ViewModifier {
    var shape: S
    var tint: Color?
    var interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.therapySurface) private var surface
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || surface.style == .solid {
            // Matt: an opaque card with a hairline and a soft shadow.
            content
                .background { shape.fill(tint ?? Color.clear) }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
                .overlay { shape.stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07), lineWidth: 1).allowsHitTesting(false) }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 10, y: 4)
        } else if surface.style == .soft {
            // Kompass 7 "Sanftes Glas": real Liquid Glass edges and light, over a calm, mostly opaque body. The
            // background only shimmers through at the rim, so text always sits on a quiet surface.
            content
                .background { shape.fill(tint ?? Color.clear) }
                .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(bodyOpacity), in: shape)
                .glassEffect(glass, in: shape)
                .overlay { shape.stroke(Color.white.opacity(colorScheme == .dark ? 0.07 : 0.5), lineWidth: 0.6).allowsHitTesting(false) }
        } else {
            content.glassEffect(glass, in: shape)
        }
    }

    /// Coverage 0…1 maps to a calm 55–95 % body (Kompass 7); the clear style ignores it entirely.
    private var bodyOpacity: Double {
        let coverage = max(0, min(1, surface.coverage))
        return (0.55 + coverage * 0.4) * (colorScheme == .dark ? 0.9 : 1)
    }

    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        return interactive && surface.interactiveGlass ? glass.interactive() : glass
    }
}

extension View {
    /// Liquid Glass surface with an accessible opaque fallback.
    func therapyGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(TherapyGlassModifier(shape: shape, tint: tint, interactive: interactive))
    }

    /// Quiet surface for tiles and fields that sit inside a glass card.
    func therapyInsetSurface(cornerRadius: CGFloat = TherapyDesign.insetRadius, selected: Bool = false) -> some View {
        background(Color.accentColor.opacity(selected ? 0.18 : 0.075), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

// MARK: - Backgrounds and screens

struct AppBackground: View {
    @AppStorage("therapy.calmInterface") private var calmInterface = true
    @Environment(\.therapySurface) private var surface
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.therapyAccent) private var accent

    var body: some View {
        // Kompass 7: one soft wash of the accent at the top that fades into the system background. Two plain
        // gradients instead of a mesh: calmer to look at and cheaper to draw behind every scrolling screen.
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            if !reduceTransparency {
                LinearGradient(colors: [accent.color.opacity(0.22 * strength), accent.companion.opacity(0.08 * strength), .clear],
                               startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55))
                RadialGradient(colors: [accent.companion.opacity(0.12 * strength), .clear], center: .topTrailing, startRadius: 0, endRadius: 420)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var strength: Double {
        (calmInterface ? 0.8 : 1.0) * (colorScheme == .dark ? 1.35 : 1.0) * (0.25 + surface.backgroundIntensity * 1.2)
    }
}

struct TherapyScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                content
                    .frame(maxWidth: TherapyDesign.contentMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Cards and headers

struct GlassCard<Content: View>: View {
    var emphasized = false
    @AppStorage("therapy.calmInterface") private var calmInterface = true
    @Environment(\.therapySurface) private var surface
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .therapyGlass(in: shape, tint: emphasized ? Color.accentColor.opacity((calmInterface ? 0.05 : 0.08) + surface.tintStrength * 0.08) : nil)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: surface.roundedCards ? TherapyDesign.cardRadius : 16, style: .continuous) }
}

struct TherapyIconTile: View {
    let icon: String
    var size: CGFloat = 32
    var tint: Color = .accentColor

    var body: some View {
        // Kompass 7: flat, softly tinted tiles instead of glossy gradients with shadows.
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Image(systemName: icon)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: shape)
            .accessibilityHidden(true)
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String
    var subtitle: String? = nil
    @ScaledMetric(relativeTo: .headline) private var tileSize: CGFloat = 32

    var body: some View {
        HStack(alignment: subtitle == nil ? .center : .top, spacing: 12) {
            TherapyIconTile(icon: icon, size: tileSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct StatusPill: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .therapyGlass(in: Capsule())
    }
}

/// A small glass capsule with a tinted symbol, used for status rows.
struct TherapyChip: View {
    let text: String
    let icon: String
    var tint: Color = .accentColor

    var body: some View {
        Label {
            Text(text).foregroundStyle(.primary)
        } icon: {
            Image(systemName: icon).foregroundStyle(tint)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .modifier(TherapyChipSurface(tint: tint))
        .accessibilityElement(children: .combine)
    }
}

private struct TherapyChipSurface: ViewModifier {
    let tint: Color
    @Environment(\.therapySurface) private var surface
    func body(content: Content) -> some View {
        content.therapyGlass(in: Capsule(), tint: tint.opacity(0.06 + surface.tintStrength * 0.14))
    }
}

// MARK: - Buttons

struct PrimaryActionButton: View {
    let title: String
    let icon: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: icon)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }
}

struct QuickActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    var tint: Color = .accentColor
    let action: () -> Void
    @ScaledMetric(relativeTo: .title3) private var tileSize: CGFloat = 40

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                TherapyIconTile(icon: icon, size: tileSize, tint: tint)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .padding(14)
            .contentShape(RoundedRectangle(cornerRadius: TherapyDesign.tileRadius, style: .continuous))
        }
        .buttonStyle(TherapyPressStyle())
        .therapyGlass(in: RoundedRectangle(cornerRadius: TherapyDesign.tileRadius, style: .continuous), interactive: true)
        .accessibilityElement(children: .combine)
    }
}

struct ResponsiveButtonRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                content
            }

            VStack(spacing: 10) {
                content
            }
        }
    }
}

// MARK: - Grouped menus

extension View {
    /// Native grouped forms on the shared ambient background, so every menu and editor matches.
    func therapyFormStyle() -> some View {
        scrollContentBackground(.hidden)
            .background { AppBackground() }
    }
}

struct TherapyRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.07 : 0))
            .contentShape(Rectangle())
    }
}

/// A titled group of rows on one glass surface, like a Settings section.
struct TherapySettingsSection<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 18)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(subviews) { subview in
                        subview
                        if subview.id != subviews.last?.id {
                            Divider().padding(.leading, 62)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: TherapyDesign.tileRadius + 4, style: .continuous))
            .therapyGlass(in: RoundedRectangle(cornerRadius: TherapyDesign.tileRadius + 4, style: .continuous))
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
            }
        }
    }
}

struct TherapySettingsRow: View {
    let title: String
    let icon: String
    var subtitle: String? = nil
    var tint: Color = .accentColor
    var value: String? = nil
    var destructive = false
    var showsChevron = true

    var body: some View {
        HStack(spacing: 14) {
            TherapyIconTile(icon: icon, size: 32, tint: destructive ? .red : tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(destructive ? Color.red : Color.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct TherapySettingsLink<Destination: View>: View {
    let title: String
    let icon: String
    var subtitle: String? = nil
    var tint: Color = .accentColor
    var value: String? = nil
    @ViewBuilder var destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            TherapySettingsRow(title: title, icon: icon, subtitle: subtitle, tint: tint, value: value)
        }
        .buttonStyle(TherapyRowPressStyle())
    }
}

/// A pushed settings page that keeps cards on the shared background.
struct TherapySettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        TherapyScreen {
            VStack(spacing: 18) {
                content
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Brand

struct TherapyLogoMark: View {
    var size: CGFloat = 104
    var glow = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
        Image("TherapyMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.04)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            }
            .shadow(color: Color.indigo.opacity(glow ? 0.35 : 0), radius: size * 0.2, y: size * 0.09)
            .accessibilityHidden(true)
    }
}

// MARK: - Launch splash

/// Continues the static launch screen: the logo starts exactly where the storyboard
/// drew it, then the glass plate, colour field and title settle in before the app appears.
struct TherapySplashView: View {
    static let logoSize: CGFloat = 120
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var leaving = false
    @State private var finished = false

    var body: some View {
        let plate = RoundedRectangle(cornerRadius: (Self.logoSize + 36) * 0.2237, style: .continuous)
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            AppBackground()
                .opacity(revealed ? 1 : 0)

            Color.clear
                .frame(width: Self.logoSize + 36, height: Self.logoSize + 36)
                .therapyGlass(in: plate)
                .opacity(revealed ? 1 : 0)
                .scaleEffect(revealed || reduceMotion ? 1 : 0.82)

            TherapyLogoMark(size: Self.logoSize, glow: revealed)
                .overlay(alignment: .top) {
                    VStack(spacing: 6) {
                        Text(TherapyDesign.appName)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text(TherapyDesign.appTagline)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                    .offset(y: Self.logoSize + 46 + (revealed || reduceMotion ? 0 : 12))
                    .opacity(revealed ? 1 : 0)
                }
        }
        .scaleEffect(leaving && !reduceMotion ? 1.04 : 1)
        .opacity(leaving ? 0 : 1)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kompass wird geöffnet")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tippen zum Überspringen")
        .task { await run() }
    }

    private func run() async {
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 40 : 120))
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.65, dampingFraction: 0.82)) { revealed = true }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 450 : 1050))
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.38)) { leaving = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 220 : 400))
            onFinish()
        }
    }
}

// MARK: - What's new after an update

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Item: Identifiable {
        let icon: String, title: String, text: String
        var id: String { title }
    }

    private let items: [Item] = [
        Item(icon: "sun.max", title: "Heute ist ruhiger",
             text: "Eine kurze Seite: was als Nächstes kommt (Therapie und BeWo), deine Wochenaufgaben zum Abhaken und Hinzufügen, fällige Routinen und „Schnell festhalten“. Weitere Karten ergänzt du unter „Heute anpassen“."),
        Item(icon: "square.on.square", title: "Neues, klares Design",
             text: "Weiterhin Liquid Glass – aber mit ruhigen, fast deckenden Flächen, flachen Symbolen und einem sanften Hintergrund. Alles ist leichter zu lesen und läuft flüssiger."),
        Item(icon: "forward.end.fill", title: "Schritte überspringen",
             text: "Kaffee schon fertig? In der Therapiestunde kannst du einzelne Schritte überspringen oder direkt zu einem späteren springen – immer mit Rückfrage. Oder du lässt sie schon beim Start weg."),
        Item(icon: "alarm", title: "Wecker zuverlässig",
             text: "Wenn du über einen Wecker in die App gehst, erscheint der passende Bildschirm sofort. Eine Pause stoppt alle Wecker der Stunde direkt, und gleichzeitige Wecker klingeln nur noch einmal."),
        Item(icon: "mappin.and.ellipse", title: "Wo du es festgehalten hast",
             text: "Einträge mit Standort zeigen im Verlauf ein kleines „Ort“-Zeichen. Ein Tipp öffnet die Karte mit Ortsnamen."),
        Item(icon: "lock.shield.fill", title: "Alle Daten bleiben",
             text: "Deine Einträge, Sicherungen, KI-Einstellungen und Erinnerungen bleiben unverändert erhalten.")
    ]

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 26) {
                    VStack(spacing: 14) {
                        TherapyLogoMark(size: 88)
                        Text("Neu in Kompass")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .multilineTextAlignment(.center)
                        Text("Version \(TherapyDesign.appVersion) · Kompass 7 – ruhiger, einfacher, verlässlicher.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 36)

                    VStack(spacing: 12) {
                        ForEach(items) { item in
                            HStack(alignment: .top, spacing: 14) {
                                TherapyIconTile(icon: item.icon, size: 40)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(.system(.headline, design: .rounded))
                                    Text(item.text).font(.subheadline).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(16)
                            .therapyGlass(in: RoundedRectangle(cornerRadius: TherapyDesign.tileRadius + 2, style: .continuous))
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(title: "Los geht’s", icon: "arrow.right") { dismiss() }
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                    .accessibilityIdentifier("whatsnew.continue")
            }
        }
        .presentationDragIndicator(.visible)
    }
}
