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
    /// Green behind white text (a filled Call, Done or Paid button). Apple's
    /// dark-mode green is too bright for white text (about 2:1), so dark
    /// mode gets a deeper one (about 6:1).
    static let paidFill = Color(light: Color(red: 0.11, green: 0.50, blue: 0.22), dark: Color(red: 0.10, green: 0.45, blue: 0.22))
    static let owed = Color(light: Color(red: 0.72, green: 0.33, blue: 0.0), dark: .orange)
    /// A field or question that needs attention: the same readable orange
    /// as owed money (Apple's own orange is too pale in sunlight).
    static let warning = owed
    static let overdue = Color(light: Color(red: 0.78, green: 0.16, blue: 0.11), dark: .red)
    static let done = Color.secondary
    /// The fill behind cards and tiles, right in light and dark. On iPhone
    /// the same white (or dark grey) as a grouped list's rows, so cards sit
    /// on the grey page like the rest of the screen; on the Mac a faint tint.
    #if os(iOS)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let cardStroke = Color.clear
    /// The board pages on iPhone: the grouped-list grey with white cards,
    /// like Settings and Health.
    static let boardPage = Color(uiColor: .systemGroupedBackground)
    static let boardCard = Color(uiColor: .secondarySystemGroupedBackground)
    #else
    static let card = Color.primary.opacity(0.055)
    static let cardStroke = Color.primary.opacity(0.07)
    /// The Mac Calendar board: a soft grey page with white cards, and
    /// their dark-mode pair.
    static let boardPage = Color(light: Color(white: 0.945), dark: Color(white: 0.105))
    static let boardCard = Color(light: .white, dark: Color(white: 0.165))
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

// MARK: - Payment

extension PaymentType {
    /// The icon in pickers and menus.
    var symbol: String {
        switch self {
        case .cash: return "banknote"
        case .check: return "signature"
        case .card: return "creditcard"
        case .venmo: return "v.square"
        case .cashApp: return "dollarsign.square"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// How a job was paid, beside "Paid": the real Venmo wordmark and Cash App
/// badge (Kyle, Oct 21: "download the actual logos"; files from
/// venmo.com/about/brand and Cash App's developer site), and the plain
/// Apple icon for cash, check and card. Venmo's guidelines ask for the
/// full wordmark rather than the "V" alone, so the wordmark is used.
struct PaymentMark: View {
    let type: PaymentType
    /// The height of the mark.
    var size: CGFloat = 18

    var body: some View {
        Group {
            switch type {
            case .venmo:
                Image("VenmoLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: size * 0.62)
            case .cashApp:
                Image("CashAppBadge")
                    .resizable()
                    .scaledToFit()
                    .frame(height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            default:
                Image(systemName: type.symbol)
                    .font(.system(size: size * 0.7, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(height: size)
            }
        }
        .accessibilityLabel(type.rawValue)
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
                if job.paymentType != .unknown {
                    PaymentMark(type: job.paymentType, size: 16)
                }
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
    @Environment(\.dynamicTypeSize) private var typeSize
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
                    // Wraps at the largest sizes instead of cutting mid-word.
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    var columns = 2
    @ViewBuilder var content: Content

    /// One tile a row at the largest text sizes, where two cut every word.
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s), count: typeSize.isAccessibilitySize ? 1 : columns),
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

    /// The filled colour: paid green is deepened in dark mode so the
    /// white text reads.
    private var fill: Color { tint == Tint.paid ? Tint.paidFill : tint }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .padding(.horizontal, Space.m)
            .padding(.vertical, 7)
            #if os(iOS)
            // Apple's smallest comfortable tap, for gloves in a truck.
            .frame(minHeight: 44)
            #endif
            .foregroundStyle(prominent ? Color.white : tint)
            .background(
                Capsule().fill(prominent ? fill : tint.opacity(0.14))
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

extension EnvironmentValues {
    /// The fill behind cards and tiles. The Mac Calendar board sets white
    /// cards on a grey page (Kyle, Oct 20: "bright cards").
    @Entry var cardFill: Color = Tint.card
}

/// The rounded fill behind tiles and header cards, in the colour the
/// surroundings ask for.
private struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.cardFill) private var fill

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Tint.cardStroke, lineWidth: 1)
                )
        )
    }
}

extension View {
    /// The rounded fill used behind tiles and header cards.
    func cardBackground(cornerRadius: CGFloat = 12) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
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

/// Lays its views out left to right, starting a new line when one is full.
/// The Missing chips and, on the iPhone, a detail page's buttons.
struct FlowRow: Layout {
    var spacing: CGFloat = Space.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, needed > width {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
                row.indices = [index]
                row.width = size.width
                row.height = size.height
            } else {
                row.indices.append(index)
                row.width = needed
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
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
                #if os(iOS)
                // Wrapped onto a second line rather than scrolled sideways:
                // Directions sat off the edge with no hint (Oct 20 phone audit).
                FlowRow(spacing: Space.s) {
                    actions
                }
                #else
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s) {
                        actions
                    }
                }
                .scrollClipDisabled()
                #endif
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

// MARK: - Ace's logo

/// Ace's own logo (from acejunkremovalma.com, Oct 20), drawn in the colour
/// around it: white in dark mode, near-black in light. Kyle: "a nice little
/// touch for them". Kept to the Mac sidebar and Settings › About.
struct AceLogo: View {
    var height: CGFloat = 28

    var body: some View {
        Image("AceLogo")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel("Ace Junk Removal")
    }
}

