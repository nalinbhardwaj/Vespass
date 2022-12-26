//
//  DeviceKeyManager.swift
//  Vespass
//
//  Created by Nalin Bhardwaj on 23/12/22.
//  Copyright © 2022 Apple. All rights reserved.
//

import Foundation
import CryptoKit

typealias SecurityError = Unmanaged<CFError>

let ACCOUNT_PREFIX = "com.nibnalin.pwdmanager."

// TODO: Devices should be identified by UUIDs, not IDs
enum DeviceType: Int, CaseIterable {
    case laptop = 1
    case mobile = 2
    case paper = 3
}

enum OneOfTheKeys {
    case Signing
    case Encryption
}

func loadOrCreateKeyStoreKey<T: GenericPasswordConvertible>(usage: OneOfTheKeys, selfDeviceType: DeviceType) throws -> T {
    var accessError: SecurityError?
    let store = GenericPasswordStore()

    let accessControl = SecAccessControlCreateWithFlags(
       kCFAllocatorDefault,
       kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
       [.privateKeyUsage, .userPresence],
       &accessError
    )!
    
    
    let readKey: T? = try store.readKey(account: ACCOUNT_PREFIX + String(describing: usage) + "." + String(describing: selfDeviceType))
    let key: T
    if readKey != nil {
        key = readKey!
    } else {
        if usage == .Signing {
            key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: accessControl) as! T
        } else {
            key = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: accessControl) as! T
        }
        try store.storeKey(key, account: ACCOUNT_PREFIX + String(describing: usage) + "." + String(describing: selfDeviceType))
    }
    return key
}

class DeviceKeyManager {
    var selfDeviceType: DeviceType
    
    var deviceTypeToSigningKey: [DeviceType: P256.Signing.PublicKey]
    var deviceTypeToEncryptionKey: [DeviceType: P256.KeyAgreement.PublicKey]
    
    var selfSigningPrivKey: SecureEnclave.P256.Signing.PrivateKey
    var selfSigningPubKey: P256.Signing.PublicKey
    var selfEncryptionPrivKey: SecureEnclave.P256.KeyAgreement.PrivateKey
    var selfEncryptionPubKey: P256.KeyAgreement.PublicKey

    
    init(deviceType _self: DeviceType) async throws {
        selfDeviceType = _self
        
        // Load or initialise fresh private keys
        selfSigningPrivKey = try loadOrCreateKeyStoreKey(usage: .Signing, selfDeviceType: selfDeviceType)
        selfSigningPubKey = selfSigningPrivKey.publicKey
        selfEncryptionPrivKey = try loadOrCreateKeyStoreKey(usage: .Encryption, selfDeviceType: selfDeviceType)
        selfEncryptionPubKey = selfEncryptionPrivKey.publicKey
        
        // Load cloudkit public keys
        deviceTypeToSigningKey = [:]
        deviceTypeToEncryptionKey = [:]
        let ck = CloudKitService()
        let allIds = try await ck.fetchDeviceIdentities()
        for dId in allIds {
            deviceTypeToSigningKey[dId.deviceType] = dId.signingKey
            deviceTypeToEncryptionKey[dId.deviceType] = dId.encryptionKey
        }
        
        
        // if self doesnt have cloudkit keys or they differ, populate DB and locally
        // TODO: need to make this DB entry immutable, otherwise attackers can change it if icloud
        // TODO: is broken into, easiest way is to dump in local db and diff that
        if deviceTypeToSigningKey[selfDeviceType] == nil {
            deviceTypeToSigningKey[selfDeviceType] = selfSigningPubKey
            deviceTypeToEncryptionKey[selfDeviceType] = selfEncryptionPubKey
            let selfIdentity = DeviceIdentity(uuid: UUID(), deviceType: selfDeviceType, signingKey: selfSigningPubKey, encryptionKey: selfEncryptionPubKey)
            try! await ck.save(selfIdentity.record)
        }
    }
}
