/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A mechanism for demonstrating project vespass.
*/

import Foundation
import CryptoKit
import SwiftUI
import Combine
import BigInt

struct SecretIdentifier {
    let id: UUID
    var title: String
}

class KeyTest: ObservableObject {

    #if os(iOS)
    var selfDevice = DeviceType.mobile
    #else
    var selfDevice = DeviceType.laptop
    #endif

    var store = GenericPasswordStore()
    
    var ckStore = CloudKitService()
    
    var deviceManager: DeviceKeyManager? = nil
    
    var activeRequests: [ReassemblyRequest] = []
    
    @Published var secretIdentifiers: [SecretIdentifier] = [SecretIdentifier]()
    
    func disperseSecretShares(secretIdentifier: SecretIdentifier, shares: [DeviceType: SecretShare]) async throws {
        for (deviceType, share) in shares {
            let receiverEncryptionPublicKey = deviceManager!.deviceTypeToEncryptionKey[deviceType]
            if receiverEncryptionPublicKey == nil {
                continue
            }
            let senderSigningKey = deviceManager!.selfSigningPrivKey
            let message = share.value.serialize()
            let sealedShare = try! encrypt(message, to: receiverEncryptionPublicKey!, signedBy: senderSigningKey)
            
            if deviceType == selfDevice {
                try storeSecretIdentifierEncryptedShare(secretIdentifier: secretIdentifier, encryptedShare: sealedShare)
            } else {
                // TODO: Send OTA
                let sharePacket = NewShareTransferPacket(uuid: UUID(), secretId: secretIdentifier.id, secretTitle: secretIdentifier.title, receiverDeviceType: deviceType, encryptedShare: sealedShare)
                try! await ckStore.save(sharePacket.record)
            }
        }
    }
    
    func addSecret(title: String) async {
        let uuid = UUID()
        let secretIdentifier = SecretIdentifier(id: uuid, title: title)
        
        try! addSecretIdentifierTitle(secretIdentifier: secretIdentifier)
        let uuids = secretIdentifiers.map { $0.id } + [uuid]
        setUUIDs(uuids: uuids)
        
        secretIdentifiers.append(secretIdentifier)
        
        let shares = createSecret()
        print("share values", shares)
        try! await disperseSecretShares(secretIdentifier: secretIdentifier, shares: shares)
    }
    
    init() {
        Task {
            secretIdentifiers = readSecretIdentifiers()
            deviceManager = try! await DeviceKeyManager(deviceType: selfDevice)
            try! await processNewShareTransferPackets()
        }
    }
    
    func processNewShareTransferPackets() async throws {
        let relevantShares = try await ckStore.fetchRelevantShares(deviceType: selfDevice)
        for share in relevantShares {
            if secretIdentifiers.contains(where: {$0.id == share.secretId}) {
                continue
            }
            let secretIdentifier = SecretIdentifier(id: share.secretId, title: share.secretTitle)
            try! addSecretIdentifierTitle(secretIdentifier: secretIdentifier)
            let uuids = secretIdentifiers.map { $0.id } + [secretIdentifier.id]
            setUUIDs(uuids: uuids)
            
            secretIdentifiers.append(secretIdentifier)
            
            try storeSecretIdentifierEncryptedShare(secretIdentifier: secretIdentifier, encryptedShare: share.encryptedShare)
        }
    }
    
    /// Tests for Nalin.
    func makeRequest(secretUUID: UUID?) async throws {
        guard secretUUID != nil else {
            return
        }
        
        
        let secretIdentifier = self.secretIdentifiers[self.secretIdentifiers.firstIndex(where: {$0.id == secretUUID})!]
        
        let reassemblyUUID = UUID()
        var sigData = reassemblyUUID.uuidString.data(using: .utf8)!
        sigData.append(secretIdentifier.id.uuidString.data(using: .utf8)!)
        print("sigData", sigData)
        let sig = try deviceManager!.selfSigningPrivKey.signature(for: sigData)
        let reassemblyRequest = ReassemblyRequest(uuid: reassemblyUUID, secretId: secretIdentifier.id, senderDeviceType: selfDevice, signature: sig)
        try! await ckStore.save(reassemblyRequest.record)
        activeRequests.append(reassemblyRequest)
    }
    
    func respondRequest(reassemblyRequest: ReassemblyRequest) async throws {
        if !validateReassemblyRequest(dm: deviceManager!, req: reassemblyRequest) {
            return
        }
        
        let secretIdentifier = self.secretIdentifiers.first(where: {$0.id == reassemblyRequest.secretId})
        if secretIdentifier == nil {
            print("nil secret")
            return
        }
        let encryptedSelfShare = try retrieveSecretIdentifierEncryptedShare(secretIdentifier: secretIdentifier!)
        let selfEncryptionKey = deviceManager!.selfEncryptionPrivKey
        let selfSigningPubKey = deviceManager!.selfSigningPubKey
        let share = try decrypt(encryptedSelfShare, using: selfEncryptionKey, from: deviceManager!.deviceTypeToSigningKey[.laptop]!)
        
        let receivingEncryptionKey = deviceManager!.deviceTypeToEncryptionKey[reassemblyRequest.senderDeviceType]!
        let selfSigningPrivKey = deviceManager!.selfSigningPrivKey
        let encryptedShare = try encrypt(share, to: receivingEncryptionKey, signedBy: selfSigningPrivKey)
        
        let reassemblyResponse = ReassemblyResponse(uuid: UUID(), requestId: reassemblyRequest.uuid, secretId: reassemblyRequest.secretId, senderDeviceType: selfDevice, encryptedShare: encryptedShare)
        try! await ckStore.save(reassemblyResponse.record)
    }
    
    func respondAllRequests() async {
        let allRequests = try! await ckStore.fetchAllRequests(deviceType: selfDevice)
        for request in allRequests {
            try! await respondRequest(reassemblyRequest: request)
        }
    }
    
    func finishRequest(reassemblyResponse: ReassemblyResponse) throws {
        let request = activeRequests.first(where: {$0.uuid == reassemblyResponse.requestId})!
        let secretIdentifier = secretIdentifiers.first(where: {$0.id == request.secretId})!
        
        // decrypt their secret
        let encryptedTheirShare = reassemblyResponse.encryptedShare
        let selfEncryptionKey = deviceManager!.selfEncryptionPrivKey
        let theirSigningKey = deviceManager!.deviceTypeToSigningKey[reassemblyResponse.senderDeviceType]!
        let theirShare = try decrypt(encryptedTheirShare, using: selfEncryptionKey, from: theirSigningKey)

        // Compute self secret
        let encryptedSelfShare = try retrieveSecretIdentifierEncryptedShare(secretIdentifier: secretIdentifier)
        let selfSigningPubKey = deviceManager!.selfSigningPubKey
        let selfShare = try decrypt(encryptedSelfShare, using: selfEncryptionKey, from: deviceManager!.deviceTypeToSigningKey[selfDevice]!)
        
        let theirSS = SecretShare(deviceId: reassemblyResponse.senderDeviceType, value: BigInt(theirShare))
        let selfSS = SecretShare(deviceId: selfDevice, value: BigInt(selfShare))
        
        let secret = reassembleSecret(share_1: theirSS, share_2: selfSS)
        print("assembled", secret)
    }
    
    func finishParticularRequest(secretUUID: UUID?) async throws {
        let responses = try await ckStore.fetchAllResponses(requestIds: activeRequests.map({ $0.uuid }))
        for response in responses {
            try finishRequest(reassemblyResponse: response)
        }
    }
}