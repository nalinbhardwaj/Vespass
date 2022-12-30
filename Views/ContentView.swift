//
//  ContentView.swift
//  Vespass
//
//  Created by Nalin Bhardwaj on 23/12/22.
//  Copyright © 2022 Apple. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tester: KeyTest
        
    var body: some View {
        let view = TabView() {
            NalinView()
                .tabItem { Text("Nalin View") }
                .tag(1)
            DeviceManagerView()
                .tabItem { Text("Device Manager") }
                .tag(2)
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
        ContentView().environmentObject(try! KeyTest())
    }
}
#endif
