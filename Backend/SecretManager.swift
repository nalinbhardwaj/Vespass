//
//  SecretManager.swift
//  Vespass
//
//  Created by Nalin Bhardwaj on 30/12/22.
//  Copyright © 2022 Vespass. All rights reserved.
//

import Foundation
import CloudKit

typealias SecretUUID = UUID
typealias EncryptedSecretShare = EncryptedData

// 2 methods for handling new recieves
// at recieve time, convert to a packet for myself
// - require user to authorize receiving passwords, thats a bit weird? potentially more secure in case of lost device?
// - this for now
//
// keep track of sender signing key, convert to a packet for them on request for reassembly
// - more chance for misplacing, bugs etc.

struct NewSecretShareTransferPacket {
    var uuid: UUID
    var secretId: UUID
    var secretTitle: String
    var receiverDeviceUUID: DeviceUUID
    var senderDeviceUUID: DeviceUUID
    var encryptedShare: EncryptedSecretShare
}

extension NewSecretShareTransferPacket {
    var record: CKRecord {
        let record = CKRecord(recordType: "NewSecretShareTransferPacket")
        record["uuid"] = uuid.uuidString
        record["receiverDeviceUUID"] = receiverDeviceUUID.uuidString
        record.encryptedValues["senderDeviceUUID"] = senderDeviceUUID.uuidString
        record.encryptedValues["secretId"] = secretId.uuidString
        record.encryptedValues["secretTitle"] = secretTitle
        record.encryptedValues["ephemeralPublicKeyData"] = encryptedShare.ephemeralPublicKeyData
        record.encryptedValues["ciphertext"] = encryptedShare.ciphertext
        record.encryptedValues["signature"] = encryptedShare.signature
        return record
    }
    
    init?(from record: CKRecord) throws {
        guard
            let uuid = UUID(uuidString: record["uuid"] as! String),
            let receiverDeviceUUID = UUID(uuidString: record["receiverDeviceUUID"] as! String) as DeviceUUID?,
            let senderDeviceUUID = UUID(uuidString: record.encryptedValues["senderDeviceUUID"] as! String) as DeviceUUID?,
            let secretId = UUID(uuidString: record.encryptedValues["secretId"] as! String),
            let secretTitle = record.encryptedValues["secretTitle"] as? String,
            let ephemeralPublicKeyData = (record.encryptedValues["ephemeralPublicKeyData"] != nil) ? record.encryptedValues["ephemeralPublicKeyData"] as? Data : nil,
            let ciphertext = (record.encryptedValues["ciphertext"] != nil) ? record.encryptedValues["ciphertext"] as? Data : nil,
            let signature = (record.encryptedValues["signature"] != nil) ? record.encryptedValues["signature"] as? Data : nil
        else { return nil }
        self = .init(uuid: uuid, secretId: secretId, secretTitle: secretTitle, receiverDeviceUUID: receiverDeviceUUID, senderDeviceUUID: senderDeviceUUID, encryptedShare: EncryptedSecretShare(ephemeralPublicKeyData: ephemeralPublicKeyData, ciphertext: ciphertext, signature: signature))
    }
}


class SingleSecretManager {
    var secretUUID: SecretUUID
    var title: String {
        get {
            let storedTitle = KeyChain.load(key: secretUUID.uuidString + ".title")!
            return storedTitle.to(type: String.self)
        }
        set(newTitle) {
            let data = Data(from: newTitle)
            let status = KeyChain.save(key: secretUUID.uuidString + ".title", data: data)
            if status != errSecSuccess { print("Unable to write") }
        }
    }
    
    var selfEncryptedSecretShare: EncryptedSecretShare {
        get {
            let storedSig = KeyChain.load(key: secretUUID.uuidString + ".secret.signature")!
            let storedCipher = KeyChain.load(key: secretUUID.uuidString + ".secret.ciphertext")!
            let storedPubKey = KeyChain.load(key: secretUUID.uuidString + ".secret.ephemeralPublicKeyData")!
            return EncryptedSecretShare(ephemeralPublicKeyData: storedPubKey, ciphertext: storedCipher, signature: storedSig)
        }
        
        set(newSelfEncryptedShare) {
            var status = KeyChain.save(key: secretUUID.uuidString + ".secret.signature", data: newSelfEncryptedShare.signature)
            if status != errSecSuccess { print("Unable to write signature") }
            status = KeyChain.save(key: secretUUID.uuidString + ".secret.ciphertext", data: newSelfEncryptedShare.ciphertext)
            if status != errSecSuccess { print("Unable to write ciphertext") }
            status = KeyChain.save(key: secretUUID.uuidString + ".secret.ephemeralPublicKeyData", data: newSelfEncryptedShare.ephemeralPublicKeyData)
            if status != errSecSuccess { print("Unable to write ephemeralPublicKeyData") }
        }
    }
    
    

    init(secretUUID: SecretUUID) {
        self.secretUUID = secretUUID
    }
    
    class func createNewSecret(secretTitle: String, deviceManager: DeviceIdentityManager) throws -> SingleSecretManager {
        let newSecretUUID = UUID()
        // create new secret
        let secretShares = createSecret(deviceUUIDs: Array(deviceManager.deviceUUIDToIdentity.keys))
        
        // encrypt new secret and disperse
        let encryptedSecretShares = try deviceManager.encryptNewShares(secretShares: secretShares)
        let ret = SingleSecretManager(secretUUID: newSecretUUID)
        for (deviceUUID, encryptedShare) in encryptedSecretShares {
            if deviceUUID == deviceManager.selfIdentity.publicIdentity.deviceUUID {
                ret.title = secretTitle
                ret.selfEncryptedSecretShare = encryptedShare

            } else {
                Task {
                    let shareTransferPacket = NewSecretShareTransferPacket(uuid: UUID(), secretId: newSecretUUID, secretTitle: secretTitle, receiverDeviceUUID: deviceUUID, senderDeviceUUID: deviceManager.selfIdentity.publicIdentity.deviceUUID, encryptedShare: encryptedShare)
                    try! await saveCloudKitRecord(shareTransferPacket.record)
                }
            }
        }
        
        return ret
    }
    
    class func recieveNewShare(newSecretShareTransferPacket: NewSecretShareTransferPacket, deviceManager: DeviceIdentityManager) throws -> SingleSecretManager {
        assert(newSecretShareTransferPacket.receiverDeviceUUID == deviceManager.selfIdentity.publicIdentity.deviceUUID)
                
        let receivedSecretShare = try decrypt(newSecretShareTransferPacket.encryptedShare, using: deviceManager.selfIdentity.getEncryptionPrivkey(usage: "Recieve new secret share"), from: deviceManager.deviceUUIDToIdentity[newSecretShareTransferPacket.senderDeviceUUID]!.signingPubkey)
        
        let reEncryptedSecretShare = try encrypt(receivedSecretShare, to: deviceManager.selfIdentity.publicIdentity.encryptionPubkey, signedBy: try deviceManager.selfIdentity.getSigningPrivkey(usage: "Save new secret share"))
        
        let ret = SingleSecretManager(secretUUID: newSecretShareTransferPacket.secretId)
        ret.title = newSecretShareTransferPacket.secretTitle
        ret.selfEncryptedSecretShare = reEncryptedSecretShare
        return ret
    }
}

func loadLocalKeyChainSecrets() throws -> [SecretUUID: SingleSecretManager] {
    let secretUUIDdata = KeyChain.load(key: "secretUUIDdata")
    
    let secretUUIDStrs = secretUUIDdata == nil ? nil : (try JSONSerialization.jsonObject(with: secretUUIDdata!) as? [String])
    let secretUUIDs = secretUUIDStrs?.map { UUID(uuidString: $0)! }
    var secretShares: [SecretUUID: SingleSecretManager] = [:]
    for secretUUID in secretUUIDs ?? [] {
        secretShares[secretUUID] = SingleSecretManager(secretUUID: secretUUID)
    }
    return secretShares
}

extension Notification.Name {
    static let refreshSecrets = Notification.Name("refreshSecrets")
}

class SecretManager {
    var secretShares: [SecretUUID: SingleSecretManager]
    let deviceManager: DeviceIdentityManager
    
    var othersOpenRequests: [RequestUUID: ReassemblyRequest] = [:]
    var selfOpenRequests: [RequestUUID: ReassemblyRequest] = [:]
    var selfFilledResponses: [ResponseUUID: ReassemblyResponse] = [:]
    
    func writeKeyChainSecretUUIDs() throws {
        let secretUUidStrs = secretShares.values.map { $0.secretUUID.uuidString }
        let jsonUUIDs = try JSONSerialization.data(withJSONObject: secretUUidStrs)
        let status = KeyChain.save(key: "secretUUIDdata", data: jsonUUIDs)
        guard status == errSecSuccess else { throw "Unable to write local identities" }
    }
    
    init(dm: DeviceIdentityManager) throws {
        secretShares = try loadLocalKeyChainSecrets()
        deviceManager = dm
        NotificationCenter.default.addObserver(self, selector: #selector(self.syncRefreshCloud), name: .refreshSecrets, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.syncRefreshCloudReassembly), name: .refreshReassemblies, object: nil)
    }
    
    func createNewSecret(secretTitle: String) throws {
        let newSecret = try SingleSecretManager.createNewSecret(secretTitle: secretTitle, deviceManager: deviceManager)
        secretShares[newSecret.secretUUID] = newSecret
        try writeKeyChainSecretUUIDs()
    }

    func recieveNewSecretShare(newSecretShareTransferPacket: NewSecretShareTransferPacket) throws {
        let newSecret = try SingleSecretManager.recieveNewShare(newSecretShareTransferPacket: newSecretShareTransferPacket, deviceManager: deviceManager)
        secretShares[newSecret.secretUUID] = newSecret
        try writeKeyChainSecretUUIDs()
    }

    func refreshCloud() async throws {
        let query = CKQuery(recordType: "NewSecretShareTransferPacket", predicate: NSPredicate(format: "receiverDeviceUUID = %@", deviceManager.selfIdentity.publicIdentity.deviceUUID.uuidString as NSString))
        let result = try await CKContainer.default().privateCloudDatabase.records(matching: query)
        let records = result.matchResults.compactMap { try? $0.1.get() }
        let res = try records.compactMap(NewSecretShareTransferPacket.init)
        
        for transferPacket in res {
            if secretShares[transferPacket.secretId] != nil {
                // TODO: delete record from cloudkit
                continue
            }
            try recieveNewSecretShare(newSecretShareTransferPacket: transferPacket)
        }
    }
    
    @objc func syncRefreshCloud() { // Annoyingly, NotificationCenter needs sync calls
        Task {
            try await refreshCloud()
        }
    }
}
