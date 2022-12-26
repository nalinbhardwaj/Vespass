//
//  EncryptionHelpers.swift
//  Vespass
//
//  Created by Nalin Bhardwaj on 23/12/22.
//  Copyright © 2022 Apple. All rights reserved.
//

import CryptoKit
import Foundation

// Create a salt for key derivation.
let protocolSalt = "nibnalin's cool password manager".data(using: .utf8)!

struct EncryptedShare {
    var ephemeralPublicKeyData: Data
    var ciphertext: Data
    var signature: Data
}

/// Generates an ephemeral key agreement key and performs key agreement to get the shared secret and derive the symmetric encryption key.
func encrypt(_ data: Data, to theirEncryptionKey: P256.KeyAgreement.PublicKey, signedBy ourSigningKey: SecureEnclave.P256.Signing.PrivateKey) throws -> EncryptedShare {
        let ephemeralKey = P256.KeyAgreement.PrivateKey()
        let ephemeralPublicKey = ephemeralKey.publicKey.rawRepresentation
        
        let sharedSecret = try ephemeralKey.sharedSecretFromKeyAgreement(with: theirEncryptionKey)
        
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(using: SHA256.self,
                                                                salt: protocolSalt,
                                                                sharedInfo: ephemeralPublicKey +
                                                                    theirEncryptionKey.rawRepresentation +
                                                                    ourSigningKey.publicKey.rawRepresentation,
                                                                outputByteCount: 32)
        
        let ciphertext = try ChaChaPoly.seal(data, using: symmetricKey).combined
        let signature = try ourSigningKey.signature(for: ciphertext + ephemeralPublicKey + theirEncryptionKey.rawRepresentation)
                
        return EncryptedShare(ephemeralPublicKeyData: ephemeralPublicKey, ciphertext: ciphertext, signature: signature.derRepresentation)
}

enum DecryptionErrors: Error {
    case authenticationError
}

/// Generates an ephemeral key agreement key and the performs key agreement to get the shared secret and derive the symmetric encryption key.
func decrypt(_ sealedMessage: EncryptedShare,
             using ourKeyEncryptionKey: SecureEnclave.P256.KeyAgreement.PrivateKey,
             from theirSigningKey: P256.Signing.PublicKey) throws -> Data {
    let data = sealedMessage.ciphertext + sealedMessage.ephemeralPublicKeyData + ourKeyEncryptionKey.publicKey.rawRepresentation
    guard theirSigningKey.isValidSignature(try P256.Signing.ECDSASignature(derRepresentation: sealedMessage.signature), for: data) else {
        throw DecryptionErrors.authenticationError
    }
    let ephemeralKey = try P256.KeyAgreement.PublicKey(rawRepresentation: sealedMessage.ephemeralPublicKeyData)
    let sharedSecret = try ourKeyEncryptionKey.sharedSecretFromKeyAgreement(with: ephemeralKey)
    
    let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(using: SHA256.self,
                                                            salt: protocolSalt,
                                                            sharedInfo: ephemeralKey.rawRepresentation +
                                                                ourKeyEncryptionKey.publicKey.rawRepresentation +
                                                                theirSigningKey.rawRepresentation,
                                                            outputByteCount: 32)
    
    let sealedBox = try! ChaChaPoly.SealedBox(combined: sealedMessage.ciphertext)
    
    return try ChaChaPoly.open(sealedBox, using: symmetricKey)
}
