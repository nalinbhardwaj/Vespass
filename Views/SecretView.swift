//
//  SecretView.swift
//  Vespass
//
//  Created by Nalin Bhardwaj on 23/12/22.
//  Copyright © 2022 Vespass. All rights reserved.
//

import SwiftUI

struct SecretRow: View {
    var secretManager: SingleSecretManager
    @Binding var selectedRow: SecretUUID?
    
    var body: some View {
        HStack {
            Text(secretManager.title)
            Spacer()
            if secretManager.secretUUID == selectedRow {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
            }
        }.onTapGesture {
            self.selectedRow = secretManager.secretUUID
        }
    }
}

struct SecretView: View {
    @EnvironmentObject var backend: Backend

    @State private var newTitle: String = "testing"
    
    @State var selectedRow: SecretUUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            List(backend.secrets, id: \.secretUUID) {
                secretManager in SecretRow(secretManager: secretManager, selectedRow: $selectedRow)
            }
            
            HStack {
                TextField("Title", text: $newTitle)
                Button("Add", action: {
                    Task {
                        try backend.addSecret(title: newTitle)
                    }
                })
            }
            HStack {
                Button("Request", action: {
                    Task {
                        backend.makeRequest(secretUUID: self.selectedRow!)
                    }
                })
                Spacer()
                Button("Refresh", action: {
                    backend.refreshSecrets()
                })
            }
            Spacer()
        }
    }
}

#if DEBUG
struct SecretViewPreviews: PreviewProvider {
    static var previews: some View {
        SecretView().environmentObject(try! Backend())
    }
}
#endif
