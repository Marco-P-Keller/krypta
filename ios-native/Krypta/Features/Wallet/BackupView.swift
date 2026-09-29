import KryptaBitcoin
import KryptaWallet
import SwiftUI

/// Die zwölf Wörter aufschreiben und die Abschrift prüfen.
///
/// Die Wörter erscheinen erst nach Face ID oder Code, stehen in der Fläche,
/// die iOS aus Bildschirmfotos herausnimmt (immer in `ShieldedSheet(always:)`
/// zeigen), und leben nur so lange im Speicher, wie dieses Blatt offen ist.
struct BackupView: View {
    @Environment(WalletEngine.self) private var wallet: WalletEngine?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.closeSheet) private var closeSheet

    enum Step { case intro, words, check, done }

    @State private var step: Step = .intro
    @State private var words: [String] = []
    @State private var quiz: [Int] = []
    @State private var answers: [String] = ["", "", ""]
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .intro: intro
                case .words: wordList
                case .check: check
                case .done: done
                }
            }
            .navigationTitle("Wiederherstellungswörter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(step == .done ? "Fertig" : "Abbrechen") { close() } }
            }
            .interactiveDismissDisabled(step == .words || step == .check)
        }
        .onDisappear { forget() }
    }

    private var intro: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "key.horizontal.fill").font(.largeTitle).foregroundStyle(.orange)
                    Text("Zwölf Wörter sind deine Wallet.").font(.title3.weight(.semibold))
                    Text("Wer sie hat, hat dein Bitcoin. Schreib sie auf Papier und bewahre es sicher auf. Kein Foto, keine Notiz-App, nicht in die Cloud.")
                    Text("Krypta kennt sie nur auf diesem iPhone. Löscht Krypta alles (Löschcode, Notfallknopf, fünfmal falsches Passwort) oder geht das iPhone verloren, holst du dein Bitcoin nur mit diesen Wörtern zurück, in Krypta oder in jeder anderen Bitcoin-Wallet (BIP39, BIP84).")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
            Section {
                Button {
                    Task { await reveal() }
                } label: {
                    HStack {
                        Spacer()
                        if loading { ProgressView() } else { Label("Wörter anzeigen", systemImage: Biometrics.symbol).fontWeight(.semibold) }
                        Spacer()
                    }
                }
                .disabled(loading)
                .accessibilityIdentifier("backup.reveal")
            } footer: {
                Text("Achte darauf, dass niemand mitsieht.")
            }
        }
    }

    private var wordList: some View {
        VStack(spacing: 16) {
            // Das ganze Blatt liegt in der geschützten Fläche (ShieldedSheet, always).
            WordGrid(words: words)
            Text("Schreib die Wörter in dieser Reihenfolge ab.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                quiz = Array((0..<words.count).shuffled().prefix(3)).sorted()
                answers = ["", "", ""]
                error = nil
                step = .check
            } label: {
                Text("Ich habe sie aufgeschrieben").frame(maxWidth: .infinity).fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .accessibilityIdentifier("backup.written")
        }
        .padding(.top)
        .padding(.bottom)
    }

    private var check: some View {
        Form {
            Section {
                ForEach(quiz.indices, id: \.self) { i in
                    TextField("Wort \(quiz[i] + 1)", text: $answers[i])
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("backup.answer.\(i)")
                }
            } header: {
                Text("Kurz prüfen")
            } footer: {
                Text("Gib die Wörter an diesen Stellen ein, so wie sie auf deinem Zettel stehen.")
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
            Section {
                Button("Prüfen") { verify() }
                    .disabled(answers.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                Button("Wörter noch einmal ansehen") { step = .words }
            }
        }
    }

    private var done: some View {
        ContentUnavailableView {
            Label {
                Text("Gesichert")
            } icon: {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            }
        } description: {
            Text("Bewahre den Zettel gut auf. Krypta fragt nicht mehr danach; du kannst die Wörter aber jederzeit in den Wallet-Einstellungen wieder ansehen.")
        }
    }

    private func reveal() async {
        guard let wallet else { return }
        loading = true
        defer { loading = false }
        do {
            words = try await wallet.recoveryWords(reason: String(localized: "Wiederherstellungswörter anzeigen"))
            error = nil
            step = .words
        } catch let failure as WalletFailure {
            error = BitcoinFormat.message(failure)
        } catch {
            self.error = BitcoinFormat.message(.noWallet)
        }
    }

    private func verify() {
        let ok = quiz.indices.allSatisfy { i in
            answers[i].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == words[quiz[i]]
        }
        guard ok else {
            Haptics.error()
            error = String(localized: "Mindestens ein Wort stimmt nicht. Sieh dir die Wörter noch einmal an.")
            return
        }
        Haptics.success()
        wallet?.confirmBackup()
        forget()
        step = .done
    }

    private func close() {
        forget()
        if let closeSheet { closeSheet() } else { dismiss() }
    }

    private func forget() {
        for i in words.indices { words[i] = "" }
        words = []
        answers = ["", "", ""]
    }
}

/// Zwölf Wörter, nummeriert, in zwei Spalten.
struct WordGrid: View {
    let words: [String]

    var body: some View {
        let half = (words.count + 1) / 2
        HStack(alignment: .top, spacing: 24) {
            column(0..<half)
            column(half..<words.count)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
        .accessibilityElement(children: .contain)
    }

    private func column(_ range: Range<Int>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(range, id: \.self) { i in
                HStack(spacing: 8) {
                    Text(verbatim: "\(i + 1).")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                    Text(verbatim: words[i])
                        .font(.body.monospaced().weight(.semibold))
                }
            }
        }
    }
}
