import SwiftUI
import UIKit

// MARK: - Liquid Glass design system
//
// Every screen shares these building blocks. Content cards, chips and controls use
// the system Liquid Glass material; "Transparenz reduzieren" falls back to opaque
// grouped surfaces, and "Ruhige Oberfläche" softens the ambient colour field.

enum TherapyDesign {
    static let contentMaxWidth: CGFloat = 720
    static let cardRadius: CGFloat = 26
    static let tileRadius: CGFloat = 20
    static let insetRadius: CGFloat = 14
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "5000.0.0" }
}

private struct TherapyAccentKey: EnvironmentKey {
    static let defaultValue: AppAccent = .indigo
}

extension EnvironmentValues {
    /// The chosen accent theme, so backgrounds in sheets can derive their companion hue.
    var therapyAccent: AppAccent {
        get { self[TherapyAccentKey.self] }
        set { self[TherapyAccentKey.self] = newValue }
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

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
                .overlay { shape.stroke(tint ?? Color.primary.opacity(0.08), lineWidth: 1).allowsHitTesting(false) }
        } else {
            content.glassEffect(glass, in: shape)
        }
    }

    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        return interactive ? glass.interactive() : glass
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.therapyAccent) private var accent

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            if !reduceTransparency {
                MeshGradient(width: 3, height: 3, points: [
                    SIMD2<Float>(0, 0), SIMD2<Float>(0.5, 0), SIMD2<Float>(1, 0),
                    SIMD2<Float>(0, 0.42), SIMD2<Float>(0.6, 0.36), SIMD2<Float>(1, 0.48),
                    SIMD2<Float>(0, 1), SIMD2<Float>(0.5, 1), SIMD2<Float>(1, 1)
                ], colors: meshColors)
                .mask {
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.6), location: 0.5),
                        .init(color: .black.opacity(0.3), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var meshColors: [Color] {
        let strength = (calmInterface ? 0.62 : 1.0) * (colorScheme == .dark ? 1.3 : 1.0)
        let main = accent.color, second = accent.companion
        func tone(_ color: Color, _ opacity: Double) -> Color { color.opacity(min(1, opacity * strength)) }
        return [
            tone(main, 0.34), tone(second, 0.18), tone(main, 0.24),
            tone(second, 0.16), tone(main, 0.05), tone(second, 0.14),
            tone(main, 0.12), tone(second, 0.06), tone(main, 0.14)
        ]
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
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .therapyGlass(in: shape, tint: emphasized ? Color.accentColor.opacity(calmInterface ? 0.08 : 0.15) : nil)
            .overlay {
                if emphasized {
                    shape.strokeBorder(LinearGradient(colors: [Color.accentColor.opacity(0.5), Color.accentColor.opacity(0.06)],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: TherapyDesign.cardRadius, style: .continuous) }
}

struct TherapyIconTile: View {
    let icon: String
    var size: CGFloat = 32
    var tint: Color = .accentColor

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
        Image(systemName: icon)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: shape)
            .overlay { shape.strokeBorder(.white.opacity(0.28), lineWidth: 0.6) }
            .shadow(color: tint.opacity(0.3), radius: size * 0.18, y: size * 0.08)
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
        .therapyGlass(in: Capsule(), tint: tint.opacity(0.12))
        .accessibilityElement(children: .combine)
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
                        Text("Therapie")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("Dein ruhiger Begleiter")
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
        .accessibilityLabel("Therapie wird geöffnet")
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
        Item(icon: "sparkles", title: "Therapie 5 – neu aufgebaut",
             text: "Vier ruhige Bereiche: Heute, Therapie, Alltag und Verlauf. Alles ist mit weniger Tippen erreichbar, mit mehr Symbolen und durchgehend Liquid Glass."),
        Item(icon: "magnifyingglass", title: "Suche & alle Funktionen",
             text: "Der Such-Tab zeigt jede Funktion der App als Kachel und findet Notizen, Aufgaben, Check-ins, Themen und mehr."),
        Item(icon: "figure.mind.and.body", title: "Neuer Bereich „Alltag“",
             text: "Routinen, Aufgaben, Wecker, Duschtage, Notfallplan und Methoden an einem Ort – mit dem heutigen Stand auf einen Blick."),
        Item(icon: "timer", title: "Dynamic Island, die wirklich mitläuft",
             text: "Die Live-Aktivität startet sofort, bleibt beim Verlassen der App erhalten und zeigt Abschnittswechsel und das Ende auch ohne geöffnete App. Eine Mini-Leiste über der Tableiste führt zurück zur Stunde."),
        Item(icon: "brain.head.profile", title: "Klügere KI",
             text: "Der Begleiter kennt jetzt dein Lagebild (Tageszeit, nächste Therapie, offene Aufgaben) und denkt standardmäßig kurz nach. Die Denktiefe stellst du in den KI-Einstellungen ein."),
        Item(icon: "person.crop.circle.fill", title: "Profil oben rechts",
             text: "Profil und Einstellungen öffnest du jetzt über deinen Avatar oben rechts – auf jeder Seite."),
        Item(icon: "lock.shield.fill", title: "Deine Daten bleiben",
             text: "Alle Einträge, Fotos, Aufnahmen, Sicherungen und Einstellungen funktionieren unverändert. Beim ersten Start legt die App zusätzlich eine Kopie deiner Daten an.")
    ]

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 26) {
                    VStack(spacing: 14) {
                        TherapyLogoMark(size: 88)
                        Text("Neu in Therapie")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .multilineTextAlignment(.center)
                        Text("Version \(TherapyDesign.appVersion) · gleiches Zuhause, frisch gestaltet.")
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
