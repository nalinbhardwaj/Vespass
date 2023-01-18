//
//  CloudkitHelpers.swift
//  Vespass
//
//  Created by Nalin Bhardwaj on 23/12/22.
//  Copyright © 2022 Vespass. All rights reserved.
//

import CloudKit

func checkCloudKitAccountStatus() async throws -> CKAccountStatus {
    try await CKContainer.default().accountStatus()
}

func saveCloudKitRecord(_ record: CKRecord) async throws {
    try await CKContainer.default().privateCloudDatabase.save(record)
}
