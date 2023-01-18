//
//  SecretManager+Reassembly.swift
//  Vespass
//
//  Created by Nalin Bhardwaj on 12/01/23.
//  Copyright © 2023 Vespass. All rights reserved.
//

import Foundation
import CryptoKit
import CloudKit
import BigInt

typealias RequestUUID = UUID
typealias ResponseUUID = UUID

struct ReassemblyRequest {
    let uuid: RequestUUID
    let secretId: SecretUUID
    let senderDeviceUUID: DeviceUUID
    let timestampUnixSecs: UInt64
    var signature: P256.Signing.ECDSASignature?
}

typealias ValidatedReassemblyRequest = ReassemblyRequest

let MAX_REQUEST_AGE = 3000 // in seconds, possible TODO

extension ReassemblyRequest {
    var sigData: Data {
        var sigData = self.uuid.uuidString.data(using: .utf8)!
        sigData.append(self.secretId.uuidString.data(using: .utf8)!)
        let timestampData = withUnsafeBytes(of: timestampUnixSecs) { Data($0) }
        sigData.append(timestampData)
        return sigData
    }
    
    func validated(dm: DeviceIdentityManager) -> ValidatedReassemblyRequest? {
        if UInt64(Date().timeIntervalSince1970) - self.timestampUnixSecs > MAX_REQUEST_AGE {
            print("Timestamp too old")
            return nil
        }
        let isValid = dm.deviceUUIDToIdentity[self.senderDeviceUUID]?.signingPubkey.isValidSignature(self.signature!, for: self.sigData) ?? false
        if !isValid {
            return nil
        }
        return self as ValidatedReassemblyRequest
    }
    
    var record: CKRecord {
        let record = CKRecord(recordType: "ReassemblyRequest")
        record["uuid"] = uuid.uuidString
        record.encryptedValues["secretId"] = secretId.uuidString
        record.encryptedValues["senderDeviceUUID"] = senderDeviceUUID.uuidString
        record.encryptedValues["timestampUnixSecs"] = timestampUnixSecs
        record.encryptedValues["signature"] = signature!.derRepresentation
        return record
    }
    
    init?(from record: CKRecord) throws {
        guard
            let uuid = UUID(uuidString: record["uuid"] as! String),
            let secretId = (record.encryptedValues["secretId"] != nil) ? UUID(uuidString: record.encryptedValues["secretId"] as! String) : nil,
            let senderDeviceUUID = UUID(uuidString: record.encryptedValues["senderDeviceUUID"] as! String) as DeviceUUID?,
            let timestampUnixSecs = record.encryptedValues["timestampUnixSecs"] as UInt64?,
            let signature = (record.encryptedValues["signature"] != nil) ? try P256.Signing.ECDSASignature(derRepresentation: record.encryptedValues["signature"] as! Data) : nil
        else { return nil }
        self = .init(uuid: uuid, secretId: secretId, senderDeviceUUID: senderDeviceUUID, timestampUnixSecs: timestampUnixSecs, signature: signature)
    }
}

struct ReassemblyResponse {
    let uuid: ResponseUUID
    let requestId: RequestUUID
    let secretId: SecretUUID
    let senderDeviceUUID: DeviceUUID
    let encryptedShare: EncryptedSecretShare
}

extension ReassemblyResponse {
    var record: CKRecord {
        let record = CKRecord(recordType: "ReassemblyResponse")
        record["uuid"] = uuid.uuidString
        record.encryptedValues["requestId"] = requestId.uuidString
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
            let requestId = UUID(uuidString: record.encryptedValues["requestId"] as! String),
            let secretId = UUID(uuidString: record.encryptedValues["secretId"] as! String),
            let senderDeviceUUID = UUID(uuidString: record.encryptedValues["senderDeviceUUID"] as! String) as DeviceUUID?,
            let ephemeralPublicKeyData = (record.encryptedValues["ephemeralPublicKeyData"] != nil) ? record.encryptedValues["ephemeralPublicKeyData"] as? Data : nil,
            let ciphertext = (record.encryptedValues["ciphertext"] != nil) ? record.encryptedValues["ciphertext"] as? Data : nil,
            let signature = (record.encryptedValues["signature"] != nil) ? record.encryptedValues["signature"] as? Data : nil
            else { return nil }
            self = .init(uuid: uuid, requestId: requestId, secretId: secretId, senderDeviceUUID: senderDeviceUUID, encryptedShare: EncryptedSecretShare(ephemeralPublicKeyData: ephemeralPublicKeyData, ciphertext: ciphertext, signature: signature))
    }
}


extension SingleSecretManager {
    func makeReassemblyRequest(deviceManager: DeviceIdentityManager) async throws -> UUID {
        let ts = UInt64(Date().timeIntervalSince1970)
        var reassemblyRequest = ReassemblyRequest(uuid: UUID(), secretId: self.secretUUID, senderDeviceUUID: deviceManager.selfIdentity.publicIdentity.deviceUUID, timestampUnixSecs: ts, signature: nil)
        let privKey = try deviceManager.selfIdentity.getSigningPrivkey(usage: "Request secret")
        let sig = try privKey.signature(for: reassemblyRequest.sigData)
        reassemblyRequest.signature = sig
        try await saveCloudKitRecord(reassemblyRequest.record)
        return reassemblyRequest.uuid
    }
    
    func makeReassemblyResponse(req: ReassemblyRequest, deviceManager: DeviceIdentityManager) async throws {
        guard let validatedReq = req.validated(dm: deviceManager) else { throw "Invalid request" }
        
        let decryptedSecretShare = try decrypt(selfEncryptedSecretShare, using: deviceManager.selfIdentity.getEncryptionPrivkey(usage: "Unlock for Reassembly"), from: deviceManager.selfIdentity.publicIdentity.signingPubkey)
        
        let reEncryptedSecretShare = try encrypt(decryptedSecretShare, to: deviceManager.deviceUUIDToIdentity[req.senderDeviceUUID]!.encryptionPubkey, signedBy: deviceManager.selfIdentity.getSigningPrivkey(usage: "Package to send"))
        
        let reassemblyResponse = ReassemblyResponse(uuid: UUID(), requestId: validatedReq.uuid, secretId: validatedReq.secretId, senderDeviceUUID: deviceManager.selfIdentity.publicIdentity.deviceUUID, encryptedShare: reEncryptedSecretShare)
        try await saveCloudKitRecord(reassemblyResponse.record)
    }
    
    func makeReassemblyFinish(resp: ReassemblyResponse, deviceManager: DeviceIdentityManager) throws -> FullSecret {
        let selfEncryptionKey = try deviceManager.selfIdentity.getEncryptionPrivkey(usage: "Finish reassembly")
        let decryptedSecretShareData = try decrypt(resp.encryptedShare, using: selfEncryptionKey, from: deviceManager.deviceUUIDToIdentity[resp.senderDeviceUUID]!.signingPubkey)
        
        let decryptedSecretShare = UnencryptedSecretShare(deviceUUID: resp.senderDeviceUUID, value: BigInt(decryptedSecretShareData))
        
        let ownDecryptedSecretShareData = try decrypt(self.selfEncryptedSecretShare, using: selfEncryptionKey, from: deviceManager.selfIdentity.publicIdentity.signingPubkey)
        
        let ownDecryptedSecretShare = UnencryptedSecretShare(deviceUUID: deviceManager.selfIdentity.publicIdentity.deviceUUID, value: BigInt(ownDecryptedSecretShareData))
        
        let reassembledSecret = reassembleSecret(share_1: decryptedSecretShare, share_2: ownDecryptedSecretShare)
        
        return reassembledSecret
    }
}

extension Notification.Name {
    static let refreshReassemblies = Notification.Name("refreshReassemblies")
}

extension SecretManager {
    private func fetchAllRequests() async throws -> [ReassemblyRequest] {
        let query = CKQuery(recordType: "ReassemblyRequest", predicate: NSPredicate(value: true))
        let result = try await CKContainer.default().privateCloudDatabase.records(matching: query)
        let records = result.matchResults.compactMap { try? $0.1.get() }
        let res = try records.compactMap(ReassemblyRequest.init)
        return res
    }
    
    private func fetchAllResponses(requestIds: [UUID]) async throws -> [ReassemblyResponse] {
        let stringUUIDs = requestIds.map { $0.uuidString }
        let query = CKQuery(recordType: "ReassemblyResponse", predicate: NSPredicate(value: true))
        let result = try await CKContainer.default().privateCloudDatabase.records(matching: query)
        let records = result.matchResults.compactMap { try? $0.1.get() }
        let res = try records.compactMap(ReassemblyResponse.init)
        return res
        // TODO: delete after usage
    }
    
    func refreshCloudReassembly() async throws {
        var newSelfOpenRequests = selfOpenRequests
        var newOthersOpenRequests = othersOpenRequests
        var newSelfFilledResponses = selfFilledResponses
        
        let requests = try await self.fetchAllRequests()
        let responses = try await self.fetchAllResponses(requestIds: requests.map { $0.secretId })
        
        for request in requests {
            if request.senderDeviceUUID == deviceManager.selfIdentity.publicIdentity.deviceUUID {
                if newSelfOpenRequests[request.uuid] == nil {
                    newSelfOpenRequests[request.uuid] = request
                }
            } else {
                if newOthersOpenRequests[request.uuid] == nil {
                    newOthersOpenRequests[request.uuid] = request
                }
            }
        }
        
        for response in responses {
            if newSelfOpenRequests[response.requestId] != nil {
                if newSelfFilledResponses[response.uuid] == nil {
                    newSelfFilledResponses[response.uuid] = response
                    newSelfOpenRequests[response.requestId] = nil
                }
            }
        }
        
        selfOpenRequests = newSelfOpenRequests
        selfFilledResponses = newSelfFilledResponses
        othersOpenRequests = newOthersOpenRequests
    }
    
    func makeNewRequest(secretUUID: SecretUUID) {
        Task {
            try await self.secretShares[secretUUID]!.makeReassemblyRequest(deviceManager: self.deviceManager)
        }
    }
    
    func makeNewResponse(requestUUID: RequestUUID) {
        Task {
            let req = self.othersOpenRequests[requestUUID]!
            try! await self.secretShares[req.secretId]!.makeReassemblyResponse(req: req, deviceManager: self.deviceManager)
        }
    }
    
    func makeReassemblyFinish(responseUUID: ResponseUUID) throws -> String {
        let resp = self.selfFilledResponses[responseUUID]!
        let secret = try self.secretShares[resp.secretId]?.makeReassemblyFinish(resp: resp, deviceManager: self.deviceManager)
        return secret!.stringify()
    }
    
    @objc func syncRefreshCloudReassembly() { // Annoyingly, NotificationCenter needs sync calls
        Task {
            try! await refreshCloudReassembly()
        }
    }
}
