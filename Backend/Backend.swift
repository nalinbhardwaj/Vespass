//
//  Backend.swift
//  Vespass
//
//  Created by Nalin Bhardwaj on 22/12/22.
//  Copyright © 2022 Vespass. All rights reserved.
//
//  A mechanism for demonstrating project vespass.

import Foundation
import CryptoKit
import SwiftUI
import Combine
import BigInt

class Backend: ObservableObject {
    var deviceManager: DeviceIdentityManager
    var secretManager: SecretManager
    
    @Published var displayedDevices: [DeviceIdentity]
    @Published var secrets: [SingleSecretManager]
    @Published var filledSelfResponses: [ReassemblyResponse]
    @Published var openOthersRequests: [ReassemblyRequest]
    
    func addSecret(title: String) throws {
        try secretManager.createNewSecret(secretTitle: title)
        secrets = Array(secretManager.secretShares.values)
    }
    
    func makeRequest(secretUUID: SecretUUID) {
        secretManager.makeNewRequest(secretUUID: secretUUID)
    }
    
    func makeResponse(requestUUID: RequestUUID) {
        secretManager.makeNewResponse(requestUUID: requestUUID)
    }
    
    func makeReassemblyFinish(responseUUID: ResponseUUID) -> String {
        return try! secretManager.makeReassemblyFinish(responseUUID: responseUUID)
    }
    
    init() throws {
        deviceManager = try DeviceIdentityManager()
        secretManager = try SecretManager(dm: deviceManager)
        displayedDevices = Array(deviceManager.deviceUUIDToIdentity.values)
        secrets = Array(secretManager.secretShares.values)
        filledSelfResponses = Array(secretManager.selfFilledResponses.values)
        openOthersRequests = Array(secretManager.othersOpenRequests.values)
    }
    
    func refreshDevices() {
        NotificationCenter.default.post(name: .refreshIdentities, object: nil, userInfo: nil)
        displayedDevices = Array(deviceManager.deviceUUIDToIdentity.values)
    }
    
    func refreshSecrets() {
        NotificationCenter.default.post(name: .refreshSecrets, object: nil, userInfo: nil)
        secrets = Array(secretManager.secretShares.values)
    }
    
    func refreshReassemblies() {
        testSecretSharing()
        NotificationCenter.default.post(name: .refreshReassemblies, object: nil, userInfo: nil)
        filledSelfResponses = Array(secretManager.selfFilledResponses.values)
        openOthersRequests = Array(secretManager.othersOpenRequests.values)
    }
    // TODO: automatically watch cloudkit via a subscription for notification center updates
}
