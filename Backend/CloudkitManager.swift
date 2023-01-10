//
//  CloudkitManager.swift
//  Vespass
//
//  Created by Nalin Bhardwaj on 23/12/22.
//  Copyright © 2022 Apple. All rights reserved.
//

import Foundation
import CloudKit
import CryptoKit

struct NewShareTransferPacket {
    var uuid: UUID
    var secretId: UUID
    var secretTitle: String
    var receiverDeviceUUID: DeviceUUID
    var encryptedShare: EncryptedShare
}

extension NewShareTransferPacket {
    var record: CKRecord {
        let record = CKRecord(recordType: "NewShareTransferPacket")
        record["uuid"] = uuid.uuidString
        record["receiverDeviceUUID"] = receiverDeviceUUID.uuidString
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
            let secretId = UUID(uuidString: record.encryptedValues["secretId"] as! String),
            let secretTitle = record.encryptedValues["secretTitle"] as? String,
            let ephemeralPublicKeyData = (record.encryptedValues["ephemeralPublicKeyData"] != nil) ? record.encryptedValues["ephemeralPublicKeyData"] as? Data : nil,
            let ciphertext = (record.encryptedValues["ciphertext"] != nil) ? record.encryptedValues["ciphertext"] as? Data : nil,
            let signature = (record.encryptedValues["signature"] != nil) ? record.encryptedValues["signature"] as? Data : nil
        else { return nil }
        self = .init(uuid: uuid, secretId: secretId, secretTitle: secretTitle, receiverDeviceUUID: receiverDeviceUUID, encryptedShare: EncryptedShare(ephemeralPublicKeyData: ephemeralPublicKeyData, ciphertext: ciphertext, signature: signature))
    }
}

struct ReassemblyRequest {
    var uuid: UUID
    var secretId: UUID
    var senderDeviceUUID: DeviceUUID
    var signature: P256.Signing.ECDSASignature
}

extension ReassemblyRequest {
    var record: CKRecord {
        let record = CKRecord(recordType: "ReassemblyRequest")
        record["uuid"] = uuid.uuidString
        record.encryptedValues["secretId"] = secretId.uuidString
        record.encryptedValues["senderDeviceUUID"] = senderDeviceUUID.uuidString
        record.encryptedValues["signature"] = signature.derRepresentation
        return record
    }
    
    init?(from record: CKRecord) throws {
        guard
            let uuid = UUID(uuidString: record["uuid"] as! String),
            let secretId = (record.encryptedValues["secretId"] != nil) ? UUID(uuidString: record.encryptedValues["secretId"] as! String) : nil,
            let senderDeviceUUID = UUID(uuidString: record.encryptedValues["senderDeviceUUID"] as! String) as DeviceUUID?,
            let signature = (record.encryptedValues["signature"] != nil) ? try P256.Signing.ECDSASignature(derRepresentation: record.encryptedValues["signature"] as! Data) : nil
        else { return nil }
        self = .init(uuid: uuid, secretId: secretId, senderDeviceUUID: senderDeviceUUID, signature: signature)
    }
}

// TODO: seperate types into validated and non-validated and make this a forced transform, same for others?
func validateReassemblyRequest(dm: DeviceIdentityManager, req: ReassemblyRequest) -> Bool {
    var sigData = req.uuid.uuidString.data(using: .utf8)!
    sigData.append(req.secretId.uuidString.data(using: .utf8)!)
    print("sigData", sigData)
    return dm.deviceUUIDToIdentity[req.senderDeviceUUID]?.signingPubkey.isValidSignature(req.signature, for: sigData) ?? false
}

struct ReassemblyResponse {
    var uuid: UUID
    var requestId: UUID
    var secretId: UUID
    var senderDeviceUUID: DeviceUUID
    var encryptedShare: EncryptedShare
}

extension ReassemblyResponse {
    var record: CKRecord {
        let record = CKRecord(recordType: "ReassemblyResponse")
        record["uuid"] = uuid.uuidString
        record["requestId"] = requestId.uuidString
        record.encryptedValues["secretId"] = secretId.uuidString
        record.encryptedValues["senderDeviceUUID"] = senderDeviceUUID.uuidString
        record.encryptedValues["ephemeralPublicKeyData"] = encryptedShare.ephemeralPublicKeyData
        record.encryptedValues["ciphertext"] = encryptedShare.ciphertext
        record.encryptedValues["signature"] = encryptedShare.signature
        return record
    }
    
    init?(from record: CKRecord) throws {
        guard
            let uuid = UUID(uuidString: record["uuid"] as! String),
            let requestId = UUID(uuidString: record["requestId"] as! String),
            let secretId = UUID(uuidString: record.encryptedValues["secretId"] as! String),
            let senderDeviceUUID = UUID(uuidString: record.encryptedValues["senderDeviceUUID"] as! String) as DeviceUUID?,
            let ephemeralPublicKeyData = (record.encryptedValues["ephemeralPublicKeyData"] != nil) ? record.encryptedValues["ephemeralPublicKeyData"] as? Data : nil,
            let ciphertext = (record.encryptedValues["ciphertext"] != nil) ? record.encryptedValues["ciphertext"] as? Data : nil,
            let signature = (record.encryptedValues["signature"] != nil) ? record.encryptedValues["signature"] as? Data : nil
        else { return nil }
        self = .init(uuid: uuid, requestId: requestId, secretId: secretId, senderDeviceUUID: senderDeviceUUID, encryptedShare: EncryptedShare(ephemeralPublicKeyData: ephemeralPublicKeyData, ciphertext: ciphertext, signature: signature))
    }
}

class CloudKitService {
    func checkAccountStatus() async throws -> CKAccountStatus {
        try await CKContainer.default().accountStatus()
    }
    
    func save(_ record: CKRecord) async throws {
        try await CKContainer.default().privateCloudDatabase.save(record)
    }
    
    func fetchRelevantShares(deviceUUID: DeviceUUID) async throws -> [NewShareTransferPacket] {
        let query = CKQuery(recordType: "NewShareTransferPacket", predicate: NSPredicate(format: "receiverDeviceUUID = %@", deviceUUID.uuidString as NSString))
        let result = try await CKContainer.default().privateCloudDatabase.records(matching: query)
        let records = result.matchResults.compactMap { try? $0.1.get() }
        let res = try records.compactMap(NewShareTransferPacket.init)
        return res
        // TODO: should delete after usage
    }
    
    func fetchAllRequests(deviceUUID: DeviceUUID) async throws -> [ReassemblyRequest] {
        let query = CKQuery(recordType: "ReassemblyRequest", predicate: NSPredicate(value: true))
        let result = try await CKContainer.default().privateCloudDatabase.records(matching: query)
        let records = result.matchResults.compactMap { try? $0.1.get() }
        let res = try records.compactMap(ReassemblyRequest.init)
        return res
        // TODO: delete after response
    }
    
    func fetchAllResponses(requestIds: [UUID]) async throws -> [ReassemblyResponse] {
        let stringUUIDs = requestIds.map { $0.uuidString }
        let query = CKQuery(recordType: "ReassemblyResponse", predicate: NSPredicate(format: "requestId IN %@", stringUUIDs))
        let result = try await CKContainer.default().privateCloudDatabase.records(matching: query)
        let records = result.matchResults.compactMap { try? $0.1.get() }
        let res = try records.compactMap(ReassemblyResponse.init)
        return res
        // TODO: delete after usage
    }
}
