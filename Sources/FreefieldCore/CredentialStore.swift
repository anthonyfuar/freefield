import CryptoKit
import Foundation
import IOKit

public enum CredentialStore {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Freefield", isDirectory: true)
    }

    static var vaultURL: URL { folder.appendingPathComponent("credentials.vault") }
    static var keyURL: URL { folder.appendingPathComponent("credentials.key") }
    static var legacyURL: URL { folder.appendingPathComponent("credentials.json") }

    public static func loadKeys() -> APIKeys {
        let stored = readVault() ?? migrateLegacy() ?? [:]
        return APIKeys(openRouter: stored[Provider.openRouter.rawValue], google: stored[Provider.google.rawValue])
    }

    public static func read(_ provider: Provider) -> String? {
        loadKeys().key(for: provider)
    }

    @discardableResult
    public static func save(_ value: String?, for provider: Provider) -> Bool {
        var stored: [String: String] = [:]
        let current = loadKeys()
        for other in Provider.allCases {
            if let key = current.key(for: other) { stored[other.rawValue] = key }
        }
        stored[provider.rawValue] = value?.nilIfBlank
        return write(stored.compactMapValues { $0 }) && read(provider) == value?.nilIfBlank
    }

    public static var protection: String {
        (try? Vault.loadOrCreateKey().scheme) ?? "none"
    }

    private static func readVault() -> [String: String]? {
        guard let data = try? Data(contentsOf: vaultURL),
              let envelope = try? JSONDecoder().decode(Vault.Envelope.self, from: data),
              let plaintext = try? Vault.open(envelope) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: plaintext)
    }

    private static func write(_ stored: [String: String]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let envelope = try Vault.seal(try JSONEncoder().encode(stored), replacingUnusableKey: true)
            try writePrivately(try JSONEncoder().encode(envelope), to: vaultURL)
            return true
        } catch {
            return false
        }
    }

    private static func migrateLegacy() -> [String: String]? {
        guard let data = try? Data(contentsOf: legacyURL),
              let stored = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
        if write(stored) {
            wipe(legacyURL, byteCount: data.count)
            try? FileManager.default.removeItem(at: legacyURL)
        }
        return stored
    }

    private static func wipe(_ url: URL, byteCount: Int) {
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        try? handle.write(contentsOf: Data(repeating: 0, count: byteCount))
        try? handle.synchronize()
    }

    static func writePrivately(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

enum Vault {
    struct Envelope: Codable {
        var version = 1
        var scheme: String
        var ephemeral: Data?
        var sealed: Data
    }

    struct KeyFile: Codable {
        var scheme: String
        var material: Data

        var isUsable: Bool {
            guard scheme == "secure-enclave" else { return true }
            guard let key = try? SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: material) else { return false }
            return (try? key.sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PrivateKey().publicKey)) != nil
        }
    }

    static let context = Data("Freefield credentials v1".utf8)

    static func seal(_ plaintext: Data, replacingUnusableKey: Bool = false) throws -> Envelope {
        let keyFile = try loadOrCreateKey(replacingUnusable: replacingUnusableKey)
        if keyFile.scheme == "secure-enclave" {
            let enclaveKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: keyFile.material)
            let ephemeral = P256.KeyAgreement.PrivateKey()
            let secret = try ephemeral.sharedSecretFromKeyAgreement(with: enclaveKey.publicKey)
            let key = derive(secret, salt: ephemeral.publicKey.x963Representation)
            let box = try AES.GCM.seal(plaintext, using: key)
            return Envelope(scheme: keyFile.scheme, ephemeral: ephemeral.publicKey.x963Representation, sealed: box.combined!)
        }
        let box = try AES.GCM.seal(plaintext, using: deviceKey(salt: keyFile.material))
        return Envelope(scheme: keyFile.scheme, sealed: box.combined!)
    }

    static func open(_ envelope: Envelope) throws -> Data {
        let keyFile = try loadOrCreateKey()
        let box = try AES.GCM.SealedBox(combined: envelope.sealed)
        if envelope.scheme == "secure-enclave", keyFile.scheme == "secure-enclave", let ephemeral = envelope.ephemeral {
            let enclaveKey = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: keyFile.material)
            let secret = try enclaveKey.sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(x963Representation: ephemeral))
            return try AES.GCM.open(box, using: derive(secret, salt: ephemeral))
        }
        return try AES.GCM.open(box, using: deviceKey(salt: keyFile.material))
    }

    static func loadOrCreateKey(replacingUnusable: Bool = false) throws -> KeyFile {
        if let data = try? Data(contentsOf: CredentialStore.keyURL),
           let keyFile = try? JSONDecoder().decode(KeyFile.self, from: data) {
            if !replacingUnusable || keyFile.isUsable { return keyFile }
            setAside(CredentialStore.vaultURL)
            setAside(CredentialStore.keyURL)
        }
        let keyFile: KeyFile
        if SecureEnclave.isAvailable, let enclaveKey = try? SecureEnclave.P256.KeyAgreement.PrivateKey() {
            keyFile = KeyFile(scheme: "secure-enclave", material: enclaveKey.dataRepresentation)
        } else {
            keyFile = KeyFile(scheme: "device", material: Data(SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) }))
        }
        try FileManager.default.createDirectory(at: CredentialStore.folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try CredentialStore.writePrivately(try JSONEncoder().encode(keyFile), to: CredentialStore.keyURL)
        return keyFile
    }

    private static func setAside(_ url: URL) {
        let stale = url.appendingPathExtension("stale")
        try? FileManager.default.removeItem(at: stale)
        try? FileManager.default.moveItem(at: url, to: stale)
    }

    private static func derive(_ secret: SharedSecret, salt: Data) -> SymmetricKey {
        secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: context, outputByteCount: 32)
    }

    private static func deviceKey(salt: Data) -> SymmetricKey {
        let uuid = Data((hardwareUUID() ?? "freefield").utf8)
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: uuid), salt: salt, info: context, outputByteCount: 32)
    }

    private static func hardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }
}
