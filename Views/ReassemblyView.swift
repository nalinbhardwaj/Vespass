//
//  SecretView.swift
//  Vespass
//
//  Created by Nalin Bhardwaj on 23/12/22.
//  Copyright © 2022 Vespass. All rights reserved.
//

import SwiftUI

struct RequestRow: View {
    var req: ReassemblyRequest
    var reqSecret: SingleSecretManager
    @Binding var selectedReq: RequestUUID?
    
    var body: some View {
        HStack {
            Text(reqSecret.title)
            Spacer()
            if req.uuid == selectedReq {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
            }
        }.onTapGesture {
            self.selectedReq = req.uuid
        }
    }
}

struct ResponseRow: View {
    var resp: ReassemblyResponse
    var respSecret: SingleSecretManager
    @Binding var selectedResp: ResponseUUID?
    
    var body: some View {
        HStack {
            Text(respSecret.title)
            Spacer()
            if resp.uuid == selectedResp {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
            }
        }.onTapGesture {
            self.selectedResp = resp.uuid
        }
    }
}

struct ReassemblyView: View {
    @EnvironmentObject var backend: Backend
    @State var selectedReq: RequestUUID?
    @State var selectedResp: ResponseUUID?
    @State var didFinish = false
    @State var finishedSecret = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            List(backend.openOthersRequests, id: \.uuid) {
                req in RequestRow(req: req, reqSecret: backend.secretManager.secretShares[req.secretId]!, selectedReq: $selectedReq)
            }
            HStack {
                Button("Respond", action: {
                    Task {
                        backend.makeResponse(requestUUID: self.selectedReq!)
                    }
                })
            }
            Spacer()
            List(backend.filledSelfResponses, id: \.uuid) {
                resp in ResponseRow(resp: resp, respSecret: backend.secretManager.secretShares[resp.secretId]!, selectedResp: $selectedResp)
            }
            HStack {
                Button("Finish", action: {
                    Task {
                        self.finishedSecret = backend.makeReassemblyFinish(responseUUID: self.selectedResp!)
                        self.didFinish = true
                    }
                }).alert("Copy secret", isPresented: $didFinish, presenting: finishedSecret, actions: {
                    secret in Button("Copy") {
                        UIPasteboard.general.string = finishedSecret
                    }
                    Button("Close") {
                        finishedSecret = ""
                        didFinish = false
                    }
                })
            }
            HStack {
                Button("Refresh", action: {
                    backend.refreshReassemblies()
                })
            }
        }
    }
}

#if DEBUG
struct ReassemblyViewPreviews: PreviewProvider {
    static var previews: some View {
        ReassemblyView().environmentObject(try! Backend())
    }
}
#endif
