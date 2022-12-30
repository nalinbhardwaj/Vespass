//
//  UUID+Extensions.swift
//  Vespass
//
//  Created by Nalin Bhardwaj on 29/12/22.
//  Copyright © 2022 Apple. All rights reserved.
//

import Foundation

extension UUID {
    // UUID is 128-bit, we need two 64-bit values to represent it
    var integers: (Int64, Int64) {
        var a: UInt64 = 0
        a |= UInt64(self.uuid.0)
        a |= UInt64(self.uuid.1) << 8
        a |= UInt64(self.uuid.2) << (8 * 2)
        a |= UInt64(self.uuid.3) << (8 * 3)
        a |= UInt64(self.uuid.4) << (8 * 4)
        a |= UInt64(self.uuid.5) << (8 * 5)
        a |= UInt64(self.uuid.6) << (8 * 6)
        a |= UInt64(self.uuid.7) << (8 * 7)
        
        var b: UInt64 = 0
        b |= UInt64(self.uuid.8)
        b |= UInt64(self.uuid.9) << 8
        b |= UInt64(self.uuid.10) << (8 * 2)
        b |= UInt64(self.uuid.11) << (8 * 3)
        b |= UInt64(self.uuid.12) << (8 * 4)
        b |= UInt64(self.uuid.13) << (8 * 5)
        b |= UInt64(self.uuid.14) << (8 * 6)
        b |= UInt64(self.uuid.15) << (8 * 7)

        return (Int64(bitPattern: a), Int64(bitPattern: b))
    }
    
    static func from(integers: (Int64, Int64)) -> UUID {
        let a = UInt64(bitPattern: integers.0)
        let b = UInt64(bitPattern: integers.1)
        return UUID(uuid: (
            UInt8(a & 0xFF),
            UInt8((a >> 8) & 0xFF),
            UInt8((a >> (8 * 2)) & 0xFF),
            UInt8((a >> (8 * 3)) & 0xFF),
            UInt8((a >> (8 * 4)) & 0xFF),
            UInt8((a >> (8 * 5)) & 0xFF),
            UInt8((a >> (8 * 6)) & 0xFF),
            UInt8((a >> (8 * 7)) & 0xFF),
            UInt8(b & 0xFF),
            UInt8((b >> 8) & 0xFF),
            UInt8((b >> (8 * 2)) & 0xFF),
            UInt8((b >> (8 * 3)) & 0xFF),
            UInt8((b >> (8 * 4)) & 0xFF),
            UInt8((b >> (8 * 5)) & 0xFF),
            UInt8((b >> (8 * 6)) & 0xFF),
            UInt8((b >> (8 * 7)) & 0xFF)
        ))
    }
    
    var data: Data {
        var data = Data(count: 16)
        // uuid is a tuple type which doesn't have dynamic subscript access...
        data[0] = self.uuid.0
        data[1] = self.uuid.1
        data[2] = self.uuid.2
        data[3] = self.uuid.3
        data[4] = self.uuid.4
        data[5] = self.uuid.5
        data[6] = self.uuid.6
        data[7] = self.uuid.7
        data[8] = self.uuid.8
        data[9] = self.uuid.9
        data[10] = self.uuid.10
        data[11] = self.uuid.11
        data[12] = self.uuid.12
        data[13] = self.uuid.13
        data[14] = self.uuid.14
        data[15] = self.uuid.15
        return data
    }
    
    static func from(data: Data?) -> UUID? {
        guard data?.count == MemoryLayout<uuid_t>.size else {
            return nil
        }
        return data?.withUnsafeBytes{
            guard let baseAddress = $0.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }
            return NSUUID(uuidBytes: baseAddress) as UUID
        }
    }
}
