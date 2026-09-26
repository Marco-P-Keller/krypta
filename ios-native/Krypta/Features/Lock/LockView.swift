import SwiftUI

/// Sperrbildschirm ohne Rechner-Tarnung: Face ID und fertig.
struct LockView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Krypta ist gesperrt")
                .font(.title2.weight(.semibold))
            Spacer()
            Button {
                Task { await app.unlockWithBiometrics() }
            } label: {
                Label("Mit \(Biometrics.name) entsperren", systemImage: Biometrics.symbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task { await app.unlockWithBiometrics() }
    }
}
