import SwiftUI

extension View {
    /// An action that failed: its title, its message and OK. Closing it clears the failure.
    func failureAlert(_ failure: Binding<(title: String, message: String)?>) -> some View {
        alert(failure.wrappedValue?.title ?? "",
              isPresented: Binding(get: { failure.wrappedValue != nil }, set: { if !$0 { failure.wrappedValue = nil } }),
              presenting: failure.wrappedValue) { _ in
            Button("OK") {}
        } message: {
            Text($0.message)
        }
    }
}
