//
//  DeviceManagerView.swift
//  Vespass
//
//  Created by Nalin Bhardwaj on 23/12/22.
//  Copyright © 2022 Vespass. All rights reserved.

import SwiftUI

struct DeviceManagerView: View {
    @EnvironmentObject var backend: Backend

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            Spacer()
            Text("Device Identities").font(.title).frame(maxWidth: .infinity, alignment: .center)
            List {
                ForEach(self.backend.displayedDevices, id: \.deviceName) { deviceIdentity in
                    HStack {
                        Text(deviceIdentity.deviceName)
                        Spacer()
                        Text(deviceIdentity.deviceUUID.uuidString).font(.system(.body, design: .monospaced))
                    }
                }
            }
            HStack(alignment: .center) {
                Button("Refresh", action: {
                    backend.refreshDevices()
                }).buttonStyle(.bordered).frame(maxWidth: .infinity, alignment: .center)
            }
            Spacer()
        }
    }
}

#if DEBUG
struct DeviceManagerViewPreviews: PreviewProvider {
    static var previews: some View {
        DeviceManagerView().environmentObject(try! Backend())
    }
}
#endif
