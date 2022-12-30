//
//  NalinView.swift
//  Vespass
//
//  Created by Nalin Bhardwaj on 23/12/22.
//  Copyright © 2022 Apple. All rights reserved.
//

import SwiftUI

struct SecretRow: View {
    var secret: SecretIdentifier
    @Binding var selectedRow: UUID?
    
    var body: some View {
        HStack {
            Text(secret.title)
            Spacer()
            if secret.id == selectedRow {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
            }
        }.onTapGesture {
            self.selectedRow = secret.id
            print("yoo", selectedRow, secret.id)
        }
    }
}

struct NalinView: View {
    @EnvironmentObject var tester: KeyTest

    @State private var newTitle: String = "testing"
    
    @State var selectedRow: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            List(tester.secretIdentifiers, id: \.id) {
                secret in SecretRow(secret: secret, selectedRow: $selectedRow)
            }
            
            HStack {
                #if os(iOS)
                Text("Device UUID")
                #endif
            }
            
            HStack {
                TextField("Title", text: $newTitle)
                Button("Add", action: {
                    Task {
                        await tester.addSecret(title: newTitle)
                    }
                })
            }
            HStack {
                Button("Request", action: {
                    Task {
                        try await tester.makeRequest(secretUUID: self.selectedRow)
                    }
                })
                Button("Process", action: {
                    Task {
                        await tester.respondAllRequests()
                    }
                })
                Button("Finish", action: {
                    Task {
                        try await tester.finishParticularRequest(secretUUID: self.selectedRow)
                    }
                })
                Spacer()
                Rectangle()
                    .frame(width: 60, height: 30)
                    .cornerRadius(5)
                    .foregroundColor(.clear)
                    .overlay(Text("OK")
                        .font(Font.body.bold())
                        .foregroundColor(.white)
                    )
            }
            Text("OK")
                .lineLimit(20)
            Spacer()
        }
    }
}

#if DEBUG
struct NalinViewPreviews: PreviewProvider {
    static var previews: some View {
        NalinView().environmentObject(try! KeyTest())
    }
}
#endif
