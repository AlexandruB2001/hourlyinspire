import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI

/// Sign in with Apple, wired to Supabase's ID-token login.
///
/// A random nonce is generated per attempt; Apple receives its SHA-256 hash
/// and Supabase receives the raw value, so a stolen token can't be replayed.
/// No name or e-mail scope is requested — Walkscape doesn't need them.
struct WalkscapeSignInButton: View {
    @Environment(AppModel.self) private var model
    @State private var nonce = ""

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            nonce = Self.randomNonce()
            request.requestedScopes = []
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = credential.identityToken,
                      let idToken = String(data: tokenData, encoding: .utf8) else {
                    model.accountError = "Apple didn't return a sign-in token. Please try again."
                    return
                }
                let rawNonce = nonce
                Task { await model.signInWithApple(idToken: idToken, nonce: rawNonce) }
            case .failure(let error):
                if (error as? ASAuthorizationError)?.code != .canceled {
                    model.accountError = "Sign in with Apple failed: \(error.localizedDescription)"
                }
            }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 48)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
        .disabled(model.isSigningIn)
        .overlay {
            if model.isSigningIn { ProgressView().tint(Theme.Palette.ink) }
        }
    }

    static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        if SecRandomCopyBytes(kSecRandomDefault, length, &bytes) != errSecSuccess {
            bytes = (0..<length).map { _ in UInt8.random(in: .min ... .max) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
