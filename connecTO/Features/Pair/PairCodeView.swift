import SwiftUI

struct PairCodeView: View {
    var macName: String
    @Binding var code: String
    var message: String?
    var onSubmit: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(macName)
                .font(.title2.weight(.semibold))
            Text("Escribe los 6 dígitos de la barra de menú del Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            TextField("482 193", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .textFieldStyle(.roundedBorder)
                .onChange(of: code) { _, newValue in
                    let digits = String(newValue.filter(\.isNumber).prefix(6))
                    if digits != newValue {
                        code = digits
                        return
                    }
                    if digits.count == 6 {
                        onSubmit()
                    }
                }
            if let message {
                Text(message)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button("Cancelar", action: onCancel)
        }
        .padding(24)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
