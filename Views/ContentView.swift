//
//  ContentView.swift
//  Vespass
//
//  Created by Nalin Bhardwaj on 23/12/22.
//  Copyright © 2022 Vespass. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var backend: Backend
        
    var body: some View {
        let view = TabView() {
            SecretView()
                .tabItem { Text("Secrets") }
                .tag(1)
            ReassemblyView()
                .tabItem { Text("Reassembly") }
                .tag(2)
            DeviceManagerView()
                .tabItem { Text("Device Manager") }
                .tag(3)
        }
        
        #if os(macOS)
        return view.padding(EdgeInsets(top: 30, leading: 15, bottom: 15, trailing: 15))
        #else
        return view
        #endif
    }
}

#if DEBUG
struct ContentViewPreviews: PreviewProvider {
    static var previews: some View {
        ContentView().environmentObject(try! Backend())
    }
}
#endif
