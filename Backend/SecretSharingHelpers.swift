//
//  SecretSharing.swift
//  Vespass
//
//  Created by Nalin Bhardwaj on 22/12/22.
//  Copyright © 2022 Apple. All rights reserved.
//

import Foundation
import BigInt
import CryptoKit

struct UnencryptedSecretShare {
    let deviceUUID: DeviceUUID
    let value: BigInt
}

let MODULUS = BigInt(stringLiteral: "28948022309329048855892746252171976963363056481941560715954676764349967630337")

func mod(_ x: BigInt) -> BigInt {
    return (x + MODULUS) % MODULUS
}

class Line {
    let slope: BigInt
    let intercept: BigInt
    
    init(slope: BigInt, intercept: BigInt) {
        self.slope = slope
        self.intercept = intercept
    }
    
    func eval(x: BigInt) -> BigInt {
        return mod(mod(slope * x) + intercept)
    }
}

func randomLine() -> Line {
    // This appears to track down to calls to arc4random_buf on Apple systems, which appears to be
    // cryptographically secure.
    // https://github.com/apple/swift/blob/main/stdlib/public/stubs/Random.cpp#L61
    return Line(slope: BigInt(BigUInt.randomInteger(lessThan: BigUInt(MODULUS - 2)) + 2), intercept: BigInt(BigUInt.randomInteger(lessThan: BigUInt(MODULUS - 2)) + 2))
}

func createSecret(deviceUUIDs: [DeviceUUID]) -> [DeviceUUID: UnencryptedSecretShare] {
    let line = randomLine()
    print("secret is", line.intercept, line.slope)
    var res: [DeviceUUID: UnencryptedSecretShare] = [:]
    for deviceUUID in deviceUUIDs {
        res[deviceUUID] = UnencryptedSecretShare(deviceUUID: deviceUUID, value: line.eval(x: BigInt(deviceUUID.uuidString.hash))) // TODO: Does this hash introduce any attack vector?
    }
    return res
}

func reassembleSecret(share_1: UnencryptedSecretShare, share_2: UnencryptedSecretShare) -> BigInt {
    let slope_den = mod(BigInt(share_1.deviceUUID.uuidString.hash) - BigInt(share_2.deviceUUID.uuidString.hash))
    let slope_den_inv = slope_den.power(MODULUS - 2, modulus: MODULUS)
    let slope_num = mod(share_1.value - share_2.value)
    let slope = mod(slope_num * slope_den_inv)
    
    let intercept = mod(share_1.value - mod(slope * BigInt(share_1.deviceUUID.uuidString.hash)))

    return intercept
}

func testSecretSharing() {
    let deviceUUIDs = [UUID(), UUID(), UUID()]
    let secrets = createSecret(deviceUUIDs: deviceUUIDs)
    let arr_secrets = [secrets[deviceUUIDs[0]]!, secrets[deviceUUIDs[1]]!, secrets[deviceUUIDs[2]]!]
    let v = reassembleSecret(share_1: arr_secrets[0], share_2: arr_secrets[1])
    for sec_a in arr_secrets {
        for sec_b in arr_secrets {
            if sec_a.deviceUUID.uuidString == sec_b.deviceUUID.uuidString {
                continue
            }
            assert(v == reassembleSecret(share_1: sec_a, share_2: sec_b))
        }
    }
}
