//
//  DeviceKeyManager.swift
//  Vespass
//
//  Created by Nalin Bhardwaj on 23/12/22.
//  Copyright © 2022 Apple. All rights reserved.
//

import Foundation
import CryptoKit
import Security
import LocalAuthentication
import CloudKit
#if os(iOS)
import UIKit
#endif

typealias SecurityError = Unmanaged<CFError>

typealias DeviceUUID = UUID

struct DeviceIdentity {
    let deviceUUID: DeviceUUID
    let deviceName: String
    let signingPubkey: P256.Signing.PublicKey
    let encryptionPubkey: P256.KeyAgreement.PublicKey
}

extension DeviceIdentity: Codable {
    enum CodingKeys: String, CodingKey {
        case deviceUUID
        case deviceName
        case signingPubkey
        case encryptionPubkey
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let uuidStr = try values.decode(String.self, forKey: .deviceUUID)
        deviceUUID = UUID(uuidString: uuidStr)!
        
        let name = try values.decode(String.self, forKey: .deviceName)
        deviceName = name
        
        let signingPubkeystr = try values.decode(String.self, forKey: .signingPubkey)
        signingPubkey = try P256.Signing.PublicKey(pemRepresentation: signingPubkeystr)
        
        let encryptionPubkeystr = try values.decode(String.self, forKey: .encryptionPubkey)
        encryptionPubkey = try P256.KeyAgreement.PublicKey(pemRepresentation: encryptionPubkeystr)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceUUID.uuidString, forKey: .deviceUUID)
        try container.encode(deviceName, forKey: .deviceName)
        try container.encode(signingPubkey.pemRepresentation, forKey: .signingPubkey)
        try container.encode(encryptionPubkey.pemRepresentation, forKey: .encryptionPubkey)
    }
}

extension DeviceIdentity {
    var record: CKRecord {
        let record = CKRecord(recordType: "DeviceIdentity")
        record["deviceUUID"] = deviceUUID.uuidString
        record.encryptedValues["deviceName"] = deviceName
        record.encryptedValues["signingPubkey"] = signingPubkey.x963Representation
        record.encryptedValues["encryptionPubkey"] = encryptionPubkey.x963Representation
        return record
    }
    
    init?(from record: CKRecord) throws {
        guard
            let deviceUUID = UUID(uuidString: record["deviceUUID"] as! String),
            let deviceName = record.encryptedValues["deviceName"] as? String,
            let signingPubkey = try (record.encryptedValues["signingPubkey"] != nil) ? P256.Signing.PublicKey(x963Representation: record.encryptedValues["signingPubkey"] as! Data) : nil,
            let encryptionPubkey = try (record.encryptedValues["encryptionPubkey"] != nil) ? P256.KeyAgreement.PublicKey(x963Representation: record.encryptedValues["encryptionPubkey"] as! Data) : nil
        else { return nil }
        self = .init(deviceUUID: deviceUUID, deviceName: deviceName, signingPubkey: signingPubkey, encryptionPubkey: encryptionPubkey)
    }
}

func loadLocalIdentities() throws -> [DeviceUUID: DeviceIdentity] {
    guard let jsonData = KeyChain.load(key: "deviceIdentities") else {
        return [:]
    }
    let jsonDecoder = JSONDecoder()
    let IDs = try jsonDecoder.decode([DeviceUUID: DeviceIdentity].self, from: jsonData)
    return IDs
}

func storeLocalIdentities(_ identities: [DeviceUUID: DeviceIdentity]) throws {
    let jsonEncoder = JSONEncoder()
    let json = try jsonEncoder.encode(identities)
    let status = KeyChain.save(key: "deviceIdentities", data: json)
    guard status == errSecSuccess else { throw "Unable to write local identities" }
}

extension CloudKitService {
    func fetchCloudIdentities() async throws -> [DeviceUUID: DeviceIdentity] {
        let query = CKQuery(recordType: "DeviceIdentity", predicate: NSPredicate(value: true))
        let result = try await CKContainer.default().privateCloudDatabase.records(matching: query)
        let records = result.matchResults.compactMap { try? $0.1.get() }
        let values = try records.compactMap(DeviceIdentity.init)
        var res: [DeviceUUID: DeviceIdentity] = [:]
        for val in values {
            res[val.deviceUUID] = val
        }
        return res
    }
}

class SelfDeviceIdentity {
    let publicIdentity: DeviceIdentity
    internal let signingPrivkeyData: Data
    internal let encryptionPrivkeyData: Data
    
    internal func createContext(usage: String, duration: TimeInterval) -> LAContext {
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = duration
        context.localizedReason = usage
        return context
    }
    
    func getSigningPrivkey(usage: String, duration: TimeInterval = 0.05) throws -> SecureEnclave.P256.Signing.PrivateKey {
        let context = createContext(usage: usage, duration: duration)
        return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: signingPrivkeyData, authenticationContext: context)
    }
    
    func getEncryptionPrivkey(usage: String, duration: TimeInterval = 0.05) throws -> SecureEnclave.P256.KeyAgreement.PrivateKey {
        let context = createContext(usage: usage, duration: duration)
        return try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: encryptionPrivkeyData, authenticationContext: context)
    }
    
    init() throws {
        let selfUUIDdata = KeyChain.load(key: "selfIdentityUUID")
        var selfUUID = selfUUIDdata == nil ? nil : UUID.from(data: selfUUIDdata)
        if selfUUID == nil {
            selfUUID = UUID() as DeviceUUID
            let writeStatus = KeyChain.save(key: "selfIdentityUUID", data: selfUUID!.data)
            guard writeStatus == errSecSuccess else { throw "Unable to write self UUID" }
            print("Created new self UUID \(selfUUID)")
        }
        
        let store = GenericPasswordStore()
        
        let readSigningPrivkey: SecureEnclave.P256.Signing.PrivateKey? = try store.readKey(account: "signing")
        let readEncryptionPrivkey: SecureEnclave.P256.KeyAgreement.PrivateKey? = try store.readKey(account: "encryption")
        
        var signingPrivkey = readSigningPrivkey
        var encryptionPrivkey = readEncryptionPrivkey
        if signingPrivkey == nil || encryptionPrivkey == nil {
            var accessError: SecurityError?
            let accessControl = SecAccessControlCreateWithFlags(
               kCFAllocatorDefault,
               kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
               [.privateKeyUsage, .userPresence],
               &accessError
            )!
            
            signingPrivkey = try SecureEnclave.P256.Signing.PrivateKey(accessControl: accessControl)
            encryptionPrivkey = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: accessControl)
            
            try store.storeKey(signingPrivkey!, account: "signing")
            try store.storeKey(encryptionPrivkey!, account: "encryption")
            print("Created new self identity")
        }
        
        signingPrivkeyData = signingPrivkey!.rawRepresentation
        encryptionPrivkeyData = encryptionPrivkey!.rawRepresentation
        #if os(iOS)
        let deviceName = UIDevice.current.name
        #else
        let deviceName = Host.current().localizedName ?? selfUUID!.uuidString
        #endif
        publicIdentity = DeviceIdentity(deviceUUID: selfUUID!, deviceName: deviceName, signingPubkey: signingPrivkey!.publicKey, encryptionPubkey: encryptionPrivkey!.publicKey)
        // TODO: Prevent iCloud TOFU by forcing existing identity to sign off another identity
    }
}

extension Notification.Name {
    static let refreshIdentities = Notification.Name("refreshIdentities")
}

class DeviceIdentityManager {
    private var addedSelf: Bool = false
    var selfIdentity: SelfDeviceIdentity
    var deviceUUIDToIdentity: [DeviceUUID: DeviceIdentity]
    
    func refreshCloud() async {
        print("Syncing Cloud store")
        var curLocalIdentities = deviceUUIDToIdentity
        // Load cloudkit identities
        let ck = CloudKitService()
        let cloudIdentities = try! await ck.fetchCloudIdentities()

        // Diff for inconsistencies
        for (localUUID, _) in curLocalIdentities {
            if cloudIdentities[localUUID] == nil && localUUID != selfIdentity.publicIdentity.deviceUUID {
                curLocalIdentities[localUUID] = nil
                print("Found deleted identity \(localUUID) locally not in cloud store? Deleted")
            }
        }
        
        // Add new cloudkit identities to local
        for (cloudUUID, cloudIdentity) in cloudIdentities {
            if curLocalIdentities[cloudUUID] == nil {
                curLocalIdentities[cloudUUID] = cloudIdentity
                print("Added cloud identity \(cloudUUID) to local store")
            }
        }
        try! storeLocalIdentities(curLocalIdentities)
        deviceUUIDToIdentity = curLocalIdentities
        if cloudIdentities[selfIdentity.publicIdentity.deviceUUID] == nil && !addedSelf {
            try! await ck.save(selfIdentity.publicIdentity.record)
            addedSelf = true
            print("Added self identity \(selfIdentity.publicIdentity.deviceUUID) to cloud store")
        }
    }
    
    @objc func syncRefreshCloud() { // Annoyingly, NotificationCenter needs sync calls
        Task {
            await refreshCloud()
        }
    }
    
    init() throws {
        selfIdentity = try SelfDeviceIdentity()
        print("self identity is \(selfIdentity.publicIdentity.deviceUUID)")
        
        // Load local identities
        var localIdentities = try loadLocalIdentities()
        
        // If self not in stores, add self
        let selfUUID = selfIdentity.publicIdentity.deviceUUID
        if localIdentities[selfUUID] == nil {
            localIdentities[selfUUID] = selfIdentity.publicIdentity
            print("Added self identity \(selfUUID) to local store")
        }
        try storeLocalIdentities(localIdentities)
        deviceUUIDToIdentity = localIdentities
        NotificationCenter.default.addObserver(self, selector: #selector(self.syncRefreshCloud), name: .refreshIdentities, object: nil)
        
        // Cloud sync task
        Task {
            await refreshCloud()
        }
    }
}
