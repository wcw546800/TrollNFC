//
//  TrollNFCApp.swift
//  TrollNFC
//
//  Main application entry point
//

import SwiftUI

@main
struct TrollNFCApp: App {
    @StateObject private var cardStorage = CardStorage()
    @StateObject private var nfcManager = NFCManager.shared
    @StateObject private var emulator = NFCEmulator.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cardStorage)
                .environmentObject(nfcManager)
                .environmentObject(emulator)
        }
    }
}
