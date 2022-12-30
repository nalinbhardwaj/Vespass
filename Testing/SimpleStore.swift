//
//  SimpleStore.swift
//  Vespass
//
//  Created by Nalin Bhardwaj on 22/12/22.
//  Copyright © 2022 Apple. All rights reserved.
//

import Foundation

let UUID_KEY = "com.nibnalin.vespas.uuid"

func readUUIDs() -> [UUID] {
    let userDefaults = UserDefaults.standard
    
    let stringUUIDs: [String] = userDefaults.object(forKey: UUID_KEY) as? [String] ?? []
    let uuids = stringUUIDs.map { UUID(uuidString: $0)! }
    return uuids
}

func setUUIDs(uuids: [UUID]) {
    let stringUUIDS = uuids.map { $0.uuidString }
    
    let userDefaults = UserDefaults.standard
    userDefaults.set(stringUUIDS, forKey: UUID_KEY)
}

func readSecretIdentifiers() -> [SecretIdentifier] {
    let uuids = readUUIDs()
    var secretIdentifiers: [SecretIdentifier] = []
    
    for uuid in uuids {
        let storedTitle = KeyChain.load(key: uuid.uuidString + ".title")!
        if storedTitle.isEmpty {
            continue
        }
        let title = try storedTitle.to(type: String.self)
        secretIdentifiers.append(SecretIdentifier(id: uuid, title: title))
    }
    return secretIdentifiers
}

extension String: Error {}

func addSecretIdentifierTitle(secretIdentifier: SecretIdentifier) throws {
    let data = Data(from: secretIdentifier.title)
    let status = KeyChain.save(key: secretIdentifier.id.uuidString + ".title", data: data)
    guard status == errSecSuccess else { throw "Unable to write" }
}

func storeSecretIdentifierEncryptedShare(secretIdentifier: SecretIdentifier, encryptedShare: EncryptedShare) throws {
    var status = KeyChain.save(key: secretIdentifier.id.uuidString + ".secret.signature", data: encryptedShare.signature)
    guard status == errSecSuccess else { throw "Unable to write signature" }
    status = KeyChain.save(key: secretIdentifier.id.uuidString + ".secret.ciphertext", data: encryptedShare.ciphertext)
    guard status == errSecSuccess else { throw "Unable to write ciphertext" }
    status = KeyChain.save(key: secretIdentifier.id.uuidString + ".secret.ephemeralPublicKeyData", data: encryptedShare.ephemeralPublicKeyData)
    guard status == errSecSuccess else { throw "Unable to write ephemeralPublicKeyData" }
}

func retrieveSecretIdentifierEncryptedShare(secretIdentifier: SecretIdentifier) throws -> EncryptedShare {
    let storedSig = KeyChain.load(key: secretIdentifier.id.uuidString + ".secret.signature")!
    let storedCipher = KeyChain.load(key: secretIdentifier.id.uuidString + ".secret.ciphertext")!
    let storedPubKey = KeyChain.load(key: secretIdentifier.id.uuidString + ".secret.ephemeralPublicKeyData")!
    
    return EncryptedShare(ephemeralPublicKeyData: storedPubKey, ciphertext: storedCipher, signature: storedSig)
}
