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

struct DeviceIdentity {
    var uuid: UUID
    var deviceType: DeviceType
    var signingKey: P256.Signing.PublicKey? // TODO: why is this optional?
    var encryptionKey: P256.KeyAgreement.PublicKey?
}

extension DeviceIdentity {
    var record: CKRecord {
        let record = CKRecord(recordType: "DeviceIdentity")
        record["uuid"] = uuid.uuidString
        record.encryptedValues["deviceType"] = deviceType.rawValue
        record.encryptedValues["signingKey"] = signingKey?.x963Representation
        record.encryptedValues["encryptionKey"] = encryptionKey?.x963Representation
        return record
    }
    
    init?(from record: CKRecord) throws {
        guard
            let uuid = UUID(uuidString: record["uuid"] as! String),
            let deviceType = DeviceType(rawValue: record.encryptedValues["deviceType"] as! Int),
            let signingKey = try (record.encryptedValues["signingKey"] != nil) ? P256.Signing.PublicKey(x963Representation: record.encryptedValues["signingKey"] as! Data) : nil,
            let encryptionKey = try (record.encryptedValues["encryptionKey"] != nil) ? P256.KeyAgreement.PublicKey(x963Representation: record.encryptedValues["encryptionKey"] as! Data) : nil
        else { return nil }
        self = .init(uuid: uuid, deviceType: deviceType, signingKey: signingKey, encryptionKey: encryptionKey)
    }
}

struct NewShareTransferPacket {
    var uuid: UUID
    var secretId: UUID
    var secretTitle: String
    var receiverDeviceType: DeviceType
    var encryptedShare: EncryptedShare
}

extension NewShareTransferPacket {
    var record: CKRecord {
        let record = CKRecord(recordType: "NewShareTransferPacket")
        record["uuid"] = uuid.uuidString
        record["receiverDeviceType"] = receiverDeviceType.rawValue
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
            let receiverDeviceType = DeviceType(rawValue: record["receiverDeviceType"] as! Int),
            let secretId = UUID(uuidString: record.encryptedValues["secretId"] as! String),
            let secretTitle = record.encryptedValues["secretTitle"] as? String,
            let ephemeralPublicKeyData = (record.encryptedValues["ephemeralPublicKeyData"] != nil) ? record.encryptedValues["ephemeralPublicKeyData"] as? Data : nil,
            let ciphertext = (record.encryptedValues["ciphertext"] != nil) ? record.encryptedValues["ciphertext"] as? Data : nil,
            let signature = (record.encryptedValues["signature"] != nil) ? record.encryptedValues["signature"] as? Data : nil
        else { return nil }
        self = .init(uuid: uuid, secretId: secretId, secretTitle: secretTitle, receiverDeviceType: receiverDeviceType, encryptedShare: EncryptedShare(ephemeralPublicKeyData: ephemeralPublicKeyData, ciphertext: ciphertext, signature: signature))
    }
}

struct ReassemblyRequest {
    var uuid: UUID
    var secretId: UUID
    var senderDeviceType: DeviceType
    var signature: P256.Signing.ECDSASignature
}

extension ReassemblyRequest {
    var record: CKRecord {
        let record = CKRecord(recordType: "ReassemblyRequest")
        record["uuid"] = uuid.uuidString
        record.encryptedValues["secretId"] = secretId.uuidString
        record.encryptedValues["senderDeviceType"] = senderDeviceType.rawValue
        record.encryptedValues["signature"] = signature.derRepresentation
        return record
    }
    
    init?(from record: CKRecord) throws {
        guard
            let uuid = UUID(uuidString: record["uuid"] as! String),
            let secretId = (record.encryptedValues["secretId"] != nil) ? UUID(uuidString: record.encryptedValues["secretId"] as! String) : nil,
            let senderDeviceType = DeviceType(rawValue: record.encryptedValues["senderDeviceType"] as! Int),
            let signature = (record.encryptedValues["signature"] != nil) ? try P256.Signing.ECDSASignature(derRepresentation: record.encryptedValues["signature"] as! Data) : nil
        else { return nil }
        self = .init(uuid: uuid, secretId: secretId, senderDeviceType: senderDeviceType, signature: signature)
    }
}

// TODO: seperate types into validated and non-validated and make this a forced transform, same for others?
func validateReassemblyRequest(dm: DeviceKeyManager, req: ReassemblyRequest) -> Bool {
    var sigData = req.uuid.uuidString.data(using: .utf8)!
    sigData.append(req.secretId.uuidString.data(using: .utf8)!)
    print("sigData", sigData)
    return dm.deviceTypeToSigningKey[req.senderDeviceType]!.isValidSignature(req.signature, for: sigData)
}

struct ReassemblyResponse {
    var uuid: UUID
    var requestId: UUID
    var secretId: UUID
    var senderDeviceType: DeviceType
    var encryptedShare: EncryptedShare
}

extension ReassemblyResponse {
    var record: CKRecord {
        let record = CKRecord(recordType: "ReassemblyResponse")
        record["uuid"] = uuid.uuidString
        record["requestId"] = requestId.uuidString
        record.encryptedValues["secretId"] = secretId.uuidString
        record.encryptedValues["senderDeviceType"] = senderDeviceType.rawValue
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
            let senderDeviceType = DeviceType(rawValue: record.encryptedValues["senderDeviceType"] as! Int),
            let ephemeralPublicKeyData = (record.encryptedValues["ephemeralPublicKeyData"] != nil) ? record.encryptedValues["ephemeralPublicKeyData"] as? Data : nil,
            let ciphertext = (record.encryptedValues["ciphertext"] != nil) ? record.encryptedValues["ciphertext"] as? Data : nil,
            let signature = (record.encryptedValues["signature"] != nil) ? record.encryptedValues["signature"] as? Data : nil
        else { return nil }
        self = .init(uuid: uuid, requestId: requestId, secretId: secretId, senderDeviceType: senderDeviceType, encryptedShare: EncryptedShare(ephemeralPublicKeyData: ephemeralPublicKeyData, ciphertext: ciphertext, signature: signature))
    }
}

class CloudKitService {
    func checkAccountStatus() async throws -> CKAccountStatus {
        try await CKContainer.default().accountStatus()
    }
    
    func save(_ record: CKRecord) async throws {
        try await CKContainer.default().privateCloudDatabase.save(record)
    }
    
    func fetchDeviceIdentities() async throws -> [DeviceIdentity] {
        let query = CKQuery(recordType: "DeviceIdentity", predicate: NSPredicate(value: true))
        let result = try await CKContainer.default().privateCloudDatabase.records(matching: query)
        let records = result.matchResults.compactMap { try? $0.1.get() }
        let res = try records.compactMap(DeviceIdentity.init)
        return res
    }
    
    func fetchRelevantShares(deviceType: DeviceType) async throws -> [NewShareTransferPacket] {
        let query = CKQuery(recordType: "NewShareTransferPacket", predicate: NSPredicate(format: "receiverDeviceType = %@", deviceType.rawValue as NSNumber))
        let result = try await CKContainer.default().privateCloudDatabase.records(matching: query)
        let records = result.matchResults.compactMap { try? $0.1.get() }
        let res = try records.compactMap(NewShareTransferPacket.init)
        return res
        // TODO: should delete after usage
    }
    
    func fetchAllRequests(deviceType: DeviceType) async throws -> [ReassemblyRequest] {
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
