//
//  SecretSharingHelpers.swift
//  Vespass
//
//  Created by Nalin Bhardwaj on 22/12/22.
//  Copyright © 2022 Vespass. All rights reserved.
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
    var res: [DeviceUUID: UnencryptedSecretShare] = [:]
    for deviceUUID in deviceUUIDs {
        res[deviceUUID] = UnencryptedSecretShare(deviceUUID: deviceUUID, value: line.eval(x: BigInt(deviceUUID.uuidString.hash))) // TODO: Does this hash introduce any attack vector?
    }
    return res
}

struct FullSecret {
    let value: BigInt
    
    func stringify(upper: Bool = true, lower: Bool = true, digits: Bool = true, special: Bool = true) -> String {
        var availableOptions: String = ""
        if upper {
            availableOptions.append("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        }
        if lower {
            availableOptions.append("abcdefghijklmnopqrstuvwxyz")
        }
        if digits {
            availableOptions.append("0123456789")
        }
        if special {
            availableOptions.append("-~!@#$%^&*_+=`|(){}[:;\"'<>,.? ] ")
        }
        
        assert(!availableOptions.isEmpty)
        
        var convert = value
        let optionCount = BigInt(availableOptions.count)
        var res = ""
        while convert > 0 {
            let index = availableOptions.index(availableOptions.startIndex, offsetBy: Int(convert % optionCount))
            res.append(availableOptions[index])
            convert = convert / optionCount
        }
        return res
    }
}

func reassembleSecret(share_1: UnencryptedSecretShare, share_2: UnencryptedSecretShare) -> FullSecret {
    let slope_den = mod(BigInt(share_1.deviceUUID.uuidString.hash) - BigInt(share_2.deviceUUID.uuidString.hash))
    let slope_den_inv = slope_den.power(MODULUS - 2, modulus: MODULUS)
    let slope_num = mod(share_1.value - share_2.value)
    let slope = mod(slope_num * slope_den_inv)
    
    let intercept = mod(share_1.value - mod(slope * BigInt(share_1.deviceUUID.uuidString.hash)))

    return FullSecret(value: intercept)
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
            assert(v.value == reassembleSecret(share_1: sec_a, share_2: sec_b).value)
        }
    }
}
