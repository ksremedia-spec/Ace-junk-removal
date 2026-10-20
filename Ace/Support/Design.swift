import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Ace's look, shared by every screen on iPhone and Mac (Kyle, 2026-10-19:
/// "make app look slick - i was only trying to avoid an 'AI' look";
/// docs/decisions.md). Flat colour, rounded numbers, roomy rows, status
/// pills. Never gradients, glow, sparkles or chat bubbles.

/// The spacing scale. Everything lines up on these.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

extension Color {
    /// One colour for light mode and another for dark. The system green,
    /// orange and red are too pale to read as text on white, so light mode
    /// gets deeper shades (Oct 20 audit: under 3:1 before).
    init(light: Color, dark: Color) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil
                ? NSColor(dark) : NSColor(light)
        })
        #else
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #endif
    }
}

/// What each colour means, used the same way everywhere. Each meaning has
/// one colour, and no colour means two things: green is good (paid, in the
/// yard, booked), orange is money or attention owed, red is overdue, grey is
/// finished. Blue and indigo are only job-type and dumpster colours.
enum Tint {
    static let paid = Color(light: Color(red: 0.11, green: 0.50, blue: 0.22), dark: .green)
    static let owed = Color(light: Color(red: 0.72, green: 0.33, blue: 0.0), dark: .orange)
    static let overdue = Color(light: Color(red: 0.78, green: 0.16, blue: 0.11), dark: .red)
    static let done = Color.secondary
    /// The fill behind cards and tiles, right in light and dark. On iPhone
    /// the same white (or dark grey) as a grouped list's rows, so cards sit
    /// on the grey page like the rest of the screen; on the Mac a faint tint.
    #if os(iOS)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let cardStroke = Color.clear
    #else
    static let card = Color.primary.opacity(0.055)
    static let cardStroke = Color.primary.opacity(0.07)
    #endif
}

// MARK: - Job types

extension JobType {
    var symbol: String {
        switch self {
        case .junkRemoval: return "truck.box.fill"
        case .demolition: return "hammer.fill"
        case .dumpsterDropOff: return "tray.and.arrow.down.fill"
        case .dumpsterPickup: return "tray.and.arrow.up.fill"
        case .dumpsterSwap: return "arrow.triangle.2.circlepath"
        case .estimate: return "ruler.fill"
        case .other: return "ellipsis"
        }
    }

    var tint: Color {
        switch self {
        case .junkRemoval: return .blue
        case .demolition: return Color(red: 0.70, green: 0.42, blue: 0.20)
        case .dumpsterDropOff, .dumpsterPickup, .dumpsterSwap: return .indigo
        case .estimate: return .purple
        case .other: return .gray
        }
    }
}

/// A job type's symbol in a rounded square of its colour.
struct TypeBadge: View {
    let type: JobType
    var size: CGFloat = 30
    /// Done work is shown quieter.
    var muted = false

    var body: some View {
        Image(systemName: type.symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(muted ? Color.gray.opacity(0.55) : type.tint)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Pills

/// A small coloured label: "Paid", "Unpaid", "Done", "Overdue".
struct StatusPill: View {
    @Environment(\.backgroundProminence) private var prominence
    let text: String
    let tint: Color
    var symbol: String? = nil

    /// On a selected row the colours would vanish into the highlight, so
    /// the pill goes white.
    private var onSelection: Bool { prominence == .increased }

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol)
                    .imageScale(.small)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(onSelection ? Color.white : tint)
        .padding(.horizontal, Space.s)
        .padding(.vertical, 3)
        .background((onSelection ? Color.white.opacity(0.22) : tint.opacity(0.15)), in: Capsule())
        .fixedSize()
    }
}

/// A colour for text on a row that turns plain when the row is selected.
struct RowTint: ViewModifier {
    @Environment(\.backgroundProminence) private var prominence
    let tint: Color

    func body(content: Content) -> some View {
        content.foregroundStyle(prominence == .increased ? Color.white.opacity(0.85) : tint)
    }
}

extension View {
    func rowTint(_ tint: Color) -> some View {
        modifier(RowTint(tint: tint))
    }
}

/// The pills for a job: Done, then Paid or Unpaid. A job still to come
/// that is not paid shows nothing; there is nothing to chase yet.
struct JobPills: View {
    let job: Job
    /// Off in the Done list, where every row is done.
    var showDone = true

    var body: some View {
        HStack(spacing: Space.xs) {
            if job.isDone && showDone {
                StatusPill(text: "Done", tint: Tint.done, symbol: "checkmark")
            }
            if job.isPaid {
                StatusPill(text: "Paid", tint: Tint.paid)
            } else if job.isUnpaid() {
                StatusPill(text: "Unpaid", tint: Tint.owed)
            }
        }
    }
}

// MARK: - Figures

/// A number with its label, in a card: "Owed  $19,550".
struct StatTile: View {
    let title: String
    let value: String
    var detail: String? = nil
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.title2.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m)
        .cardBackground()
        .accessibilityElement(children: .combine)
    }
}

/// Tiles in rows of two, or another number of columns.
struct StatGrid<Content: View>: View {
    var columns = 2
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s), count: columns),
                  spacing: Space.s) {
            content
        }
    }
}

// MARK: - People

/// A customer's initials in a circle of a colour picked from their name, so
/// the same person always gets the same colour.
struct Avatar: View {
    let name: String
    var size: CGFloat = 34

    private var initials: String {
        let words = name.split(whereSeparator: { !$0.isLetter && $0 != "'" })
            .filter { $0.first?.isUppercase ?? false || $0.count > 1 }
        let letters = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }

    /// One quiet colour for everyone, like Mail and Contacts. Ten bright
    /// hues made the 600-name list look like a colour chart (Oct 20 audit).
    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.primary.opacity(0.09)))
            .accessibilityHidden(true)
    }
}

// MARK: - Buttons

/// A compact rounded action: "Call", "Directions", "Mark paid".
struct ActionButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, Space.m)
            .padding(.vertical, 7)
            .foregroundStyle(prominent ? Color.white : tint)
            .background(
                Capsule().fill(prominent ? tint : tint.opacity(0.14))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == ActionButtonStyle {
    static func action(_ tint: Color = .accentColor, prominent: Bool = false) -> ActionButtonStyle {
        ActionButtonStyle(tint: tint, prominent: prominent)
    }
}

// MARK: - Cards and headers

extension View {
    /// The rounded fill used behind tiles and header cards.
    func cardBackground(cornerRadius: CGFloat = 12) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Tint.card)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Tint.cardStroke, lineWidth: 1)
                )
        )
    }

    /// Lets a header or tiles sit in a Form or List without the row's own
    /// box around them.
    func bareRow() -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
    }

    /// Keeps a detail page to a readable width on the Mac, centred, instead
    /// of stretching labels and values to opposite edges of a wide window.
    func readableWidth() -> some View {
        #if os(macOS)
        frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        #else
        self
        #endif
    }
}

/// The top of a detail page: a badge, a title and subtitle, a big value on
/// the right, pills, and a row of actions.
struct DetailHeader<Badge: View, Pills: View, Actions: View>: View {
    let title: String
    var subtitle: String? = nil
    var caption: String? = nil
    var value: String? = nil
    var valueTint: Color = .primary
    /// False leaves out the actions row, so an empty one takes no room.
    var hasActions = true
    @ViewBuilder var badge: Badge
    @ViewBuilder var pills: Pills
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.m) {
                badge
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .fontDesign(.rounded)
                        .lineLimit(2)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let caption {
                        Text(caption)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: Space.s)
                if let value {
                    Text(value)
                        .font(.title.weight(.semibold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(valueTint)
                        .lineLimit(1)
                }
            }
            pills
            if hasActions {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s) {
                        actions
                    }
                }
                .scrollClipDisabled()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(macOS)
        // A Mac Form draws its own box around the section; a second card
        // inside it looked doubled.
        .padding(.vertical, Space.m)
        .padding(.horizontal, Space.xs)
        #else
        .padding(Space.l)
        .cardBackground(cornerRadius: 16)
        .padding(.vertical, Space.xs)
        #endif
    }
}

/// An empty detail column: a symbol and a line of help, centred.
struct EmptyDetail: View {
    let title: String
    let symbol: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        }
    }
}
