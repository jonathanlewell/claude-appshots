import Foundation
import Security

/// True when the app on disk is exactly as built and signed on this Mac: the
/// app and every helper inside it match the seal made with this Mac's own
/// certificate (signerSHA1, compiled in by build.sh). Checked before a helper
/// runs, so a swapped file never runs with Appshots' permissions.
/// shortcut: a file swapped in the instant between this check and the launch
/// would still run; closing that needs the helpers merged into one binary.
func bundleIntact(_ app: URL) -> Bool {
    var code: SecStaticCode?, req: SecRequirement?
    let rule = "identifier \"com.jonathanlewell.claude-appshots\" and certificate leaf = H\"\(signerSHA1)\""
    guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
          SecRequirementCreateWithString(rule as CFString, [], &req) == errSecSuccess
    else { return false }
    let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
    return SecStaticCodeCheckValidity(code, flags, req) == errSecSuccess
}
