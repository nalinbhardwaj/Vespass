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

struct SecretShare {
    var deviceId: DeviceType
    var value: BigInt
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
    return Line(slope: BigInt(BigUInt.randomInteger(lessThan: BigUInt(MODULUS - 2)) + 2), intercept: BigInt(BigUInt.randomInteger(lessThan: BigUInt(MODULUS - 2)) + 2))
}

func createSecret() -> [DeviceType:SecretShare] {
    let line = randomLine()
    print("secret is", line.intercept, line.slope)
    return [
        DeviceType.laptop: SecretShare(deviceId: .laptop, value: line.eval(x: BigInt(DeviceType.laptop.rawValue))),
        DeviceType.mobile: SecretShare(deviceId: .mobile, value: line.eval(x: BigInt(DeviceType.mobile.rawValue))),
        DeviceType.paper: SecretShare(deviceId: .paper, value: line.eval(x: BigInt(DeviceType.paper.rawValue)))
    ]
}

func reassembleSecret(share_1: SecretShare, share_2: SecretShare) -> BigInt {
    let slope_den = mod(BigInt(share_1.deviceId.rawValue) - BigInt(share_2.deviceId.rawValue))
    let slope_den_inv = slope_den.power(MODULUS - 2, modulus: MODULUS)
    let slope_num = mod(share_1.value - share_2.value)
    let slope = mod(slope_num * slope_den_inv)
    
    let intercept = mod(share_1.value - mod(slope * BigInt(share_1.deviceId.rawValue)))

    return intercept
}

//func testSecretSharing() {
//    let secrets = createSecret()
//    let arr_secrets = [secrets.0, secrets.1, secrets.2]
//    let v = reassembleSecret(share_1: secrets.0, share_2: secrets.1)
//    for sec_a in arr_secrets {
//        for sec_b in arr_secrets {
//            if sec_a.deviceId == sec_b.deviceId {
//                continue
//            }
//            assert(v == reassembleSecret(share_1: sec_a, share_2: sec_b))
//        }
//    }
//}
