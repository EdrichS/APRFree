import SwiftUI

/// Every animation and transition in the first-run setup, in one place.
///
/// The setup views never write an animation themselves; they ask for one of the slots below by
/// name. To change how setup moves, change the slot here. The defaults are deliberately plain,
/// so each one is a placeholder waiting for a real design decision.
///
///     Slot          Where it shows                               What it does now
///     1 step        one step leaving, the next arriving          slides sideways and fades
///     2 hero        the card stack on the welcome step           cards rise in, one after another
///     3 headline    each step's title and note                   fades up
///     4 selection   a choice becoming the selected one           quick ease
///     5 list        a debt joining or leaving the "Added" list   fades and scales
///     6 progress    the step dots                                ease
///     7 press       the big buttons while pressed                shrink slightly
///     8 finish      leaving setup for the app                    fade
///
/// With Reduce Motion turned on, slots 1, 2, 3, 5 and 7 become a plain fade or nothing.
enum OnboardingMotion {

    // MARK: 1. Step

    /// `forward` is false when the user taps Back, so the steps move the other way.
    static func stepTransition(forward: Bool, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                           removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    static let stepAnimation = Animation.easeInOut(duration: 0.3)

    // MARK: 2. Hero

    /// How long card `index` waits before it comes in.
    static func heroDelay(index: Int) -> Double { 0.1 + 0.08 * Double(index) }
    static let heroAnimation = Animation.spring(response: 0.55, dampingFraction: 0.82)
    /// How far below its place each card starts.
    static func heroStartOffset(reduceMotion: Bool) -> CGFloat { reduceMotion ? 0 : 28 }

    // MARK: 3. Headline

    static func headlineTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8))
    }

    // MARK: 4. Selection

    static let selection = Animation.easeOut(duration: 0.15)

    // MARK: 5. List

    static let list = Animation.easeInOut(duration: 0.25)

    static func listRowTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96))
    }

    // MARK: 6. Progress

    static let progress = Animation.easeInOut(duration: 0.25)

    // MARK: 7. Press

    static func pressScale(reduceMotion: Bool) -> CGFloat { reduceMotion ? 1 : 0.97 }
    static let press = Animation.easeOut(duration: 0.12)

    // MARK: 8. Finish

    static let finish = Animation.easeInOut(duration: 0.35)
    static let finishTransition = AnyTransition.opacity
}

/// The setup flow's big buttons: the app's standard look, plus the "press" slot above.
struct SetupButtonStyle: ButtonStyle {
    var kind = PrimaryButtonStyle.Kind.primary

    func makeBody(configuration: Configuration) -> some View {
        Pressed(kind: kind, configuration: configuration)
    }

    private struct Pressed: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let kind: PrimaryButtonStyle.Kind
        let configuration: Configuration

        var body: some View {
            PrimaryButtonStyle(kind: kind).makeBody(configuration: configuration)
                .scaleEffect(configuration.isPressed ? OnboardingMotion.pressScale(reduceMotion: reduceMotion) : 1)
                .animation(OnboardingMotion.press, value: configuration.isPressed)
        }
    }
}
