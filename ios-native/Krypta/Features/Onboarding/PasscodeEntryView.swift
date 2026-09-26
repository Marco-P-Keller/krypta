import SwiftUI

/// Code festlegen wie beim iPhone-Code: eingeben, bestätigen, Punkte statt Ziffern.
///
/// `submit` bekommt den bestätigten Code und gibt einen Fehlertext zurück,
/// wenn er nicht angenommen wird.
struct PasscodeEntryView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let symbol: String
    let tint: Color
    let submit: (String) -> String?

    @State private var first: String?
    @State private var input = ""
    @State private var error: String?
    @State private var shake = 0
    @FocusState private var focused: Bool

    private let length = 6

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 32)

            VStack(spacing: 8) {
                Text(first == nil ? title : "Code bestätigen")
                    .font(.title2.weight(.bold))
                Text(first == nil ? message : "Gib denselben Code noch einmal ein.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            HStack(spacing: 18) {
                ForEach(0..<length, id: \.self) { i in
                    Circle()
                        .strokeBorder(.primary.opacity(0.6), lineWidth: 1.5)
                        .background(Circle().fill(i < input.count ? Color.primary : .clear))
                        .frame(width: 14, height: 14)
                }
            }
            .modifier(Shake(animatableData: CGFloat(shake)))
            .padding(.vertical, 8)
            .accessibilityElement()
            .accessibilityLabel("\(input.count) von \(length) Ziffern")

            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Unsichtbares Feld für die Zifferntastatur des Systems.
            TextField(String(), text: $input)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityIdentifier("passcode.field")
                .onChange(of: input) { _, value in
                    let digits = String(value.filter(\.isNumber).prefix(length))
                    if digits != value { input = digits }
                    if digits.count == length { complete(digits) }
                }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { focused = true }
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.error, trigger: shake)
    }

    private func complete(_ code: String) {
        guard let first else {
            withAnimation { self.first = code }
            input = ""
            error = nil
            return
        }
        guard code == first else {
            fail(String(localized: "Die Codes stimmen nicht überein. Versuche es noch einmal."))
            self.first = nil
            return
        }
        if let problem = submit(code) {
            fail(problem)
            self.first = nil
        }
    }

    private func fail(_ message: String) {
        error = message
        input = ""
        withAnimation(.default) { shake += 1 }
    }
}

/// Kopfschütteln bei falscher Eingabe, wie der Sperrbildschirm.
struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 4), y: 0))
    }
}
