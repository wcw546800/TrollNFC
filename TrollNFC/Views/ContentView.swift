//
//  ContentView.swift
//  TrollNFC
//
//  主界面 - 标签页导航
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // 读取标签页
            ReadView()
                .tabItem {
                    Image(systemName: "wave.3.right")
                    Text("Read")
                }
                .tag(0)
            
            // 卡片列表
            CardListView()
                .tabItem {
                    Image(systemName: "creditcard.fill")
                    Text("Cards")
                }
                .tag(1)
            
            // 写入标签页
            WriteView()
                .tabItem {
                    Image(systemName: "square.and.pencil")
                    Text("Write")
                }
                .tag(2)
            
            // 模拟标签页
            EmulateView()
                .tabItem {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Emulate")
                }
                .tag(3)
            
            // 设置
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(4)
        }
        .accentColor(.blue)
    }
}

// MARK: - 读取视图
struct ReadView: View {
    @EnvironmentObject var nfcManager: NFCManager
    @EnvironmentObject var cardStorage: CardStorage
    
    @State private var showingSaveAlert = false
    @State private var cardName = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 状态指示器
                StatusIndicator(state: nfcManager.state)
                
                Spacer()
                
                // NFC图标
                Image(systemName: "wave.3.right.circle.fill")
                    .font(.system(size: 120))
                    .foregroundColor(.blue)
                    .opacity(isScanning ? 0.5 : 1.0)
                    .animation(isScanning ? Animation.easeInOut(duration: 1).repeatForever() : .default, value: isScanning)
                
                // 状态文本
                Text(nfcManager.statusMessage.isEmpty ? "Ready to scan" : nfcManager.statusMessage)
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // 扫描按钮
                VStack(spacing: 12) {
                    Button(action: startQuickRead) {
                        HStack {
                            Image(systemName: "wave.3.right")
                            Text("Quick Read")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    
                    Button(action: startFullDump) {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                            Text("Full Dump")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    
                    Button(action: readNDEF) {
                        HStack {
                            Image(systemName: "tag")
                            Text("Read NDEF")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .disabled(isScanning)
                
                // 最近读取的卡片
                if let card = nfcManager.currentCard {
                    RecentCardView(card: card, onSave: {
                        showingSaveAlert = true
                    })
                    .padding()
                }
            }
            .navigationTitle("TrollNFC")
            .alert("Save Card", isPresented: $showingSaveAlert) {
                TextField("Card Name", text: $cardName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    saveCurrentCard()
                }
            } message: {
                Text("Enter a name for this card")
            }
        }
    }
    
    private var isScanning: Bool {
        if case .scanning = nfcManager.state { return true }
        if case .reading = nfcManager.state { return true }
        return false
    }
    
    private func startQuickRead() {
        nfcManager.startReading { result in
            // 结果已通过@Published处理
        }
    }
    
    private func startFullDump() {
        nfcManager.dumpCard { result in
            // 结果已通过@Published处理
        }
    }
    
    private func readNDEF() {
        nfcManager.readNDEF { result in
            // 结果已通过@Published处理
        }
    }
    
    private func saveCurrentCard() {
        guard var card = nfcManager.currentCard else { return }
        card.name = cardName
        cardStorage.saveCard(card)
        cardName = ""
    }
}

// MARK: - 状态指示器
struct StatusIndicator: View {
    let state: NFCOperationState
    
    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
        .cornerRadius(20)
    }
    
    private var statusColor: Color {
        switch state {
        case .idle: return .gray
        case .scanning: return .blue
        case .reading: return .orange
        case .writing: return .purple
        case .emulating: return .green
        case .error: return .red
        }
    }
    
    private var statusText: String {
        switch state {
        case .idle: return "Ready"
        case .scanning: return "Scanning..."
        case .reading: return "Reading..."
        case .writing: return "Writing..."
        case .emulating: return "Emulating..."
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - 最近卡片视图
struct RecentCardView: View {
    let card: NFCCard
    let onSave: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: card.type.icon)
                    .foregroundColor(.blue)
                Text(card.type.rawValue)
                    .font(.headline)
                Spacer()
                Button(action: onSave) {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            
            Divider()
            
            HStack {
                Text("UID:")
                    .foregroundColor(.secondary)
                Text(card.uidString)
                    .font(.system(.body, design: .monospaced))
            }
            
            if let sak = card.sak {
                HStack {
                    Text("SAK:")
                        .foregroundColor(.secondary)
                    Text(String(format: "0x%02X", sak))
                        .font(.system(.body, design: .monospaced))
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - 卡片列表视图
struct CardListView: View {
    @EnvironmentObject var cardStorage: CardStorage
    
    var body: some View {
        NavigationView {
            List {
                if cardStorage.cards.isEmpty {
                    Text("No saved cards")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(cardStorage.cards) { card in
                        NavigationLink(destination: CardDetailView(card: card)) {
                            CardRowView(card: card)
                        }
                    }
                    .onDelete(perform: cardStorage.deleteCard)
                }
            }
            .navigationTitle("Saved Cards")
            .toolbar {
                EditButton()
            }
        }
    }
}

// MARK: - 卡片行视图
struct CardRowView: View {
    let card: NFCCard
    
    var body: some View {
        HStack {
            Image(systemName: card.type.icon)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            VStack(alignment: .leading) {
                Text(card.displayName)
                    .font(.headline)
                Text(card.uidString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if card.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 卡片详情视图
struct CardDetailView: View {
    @EnvironmentObject var cardStorage: CardStorage
    @EnvironmentObject var emulator: NFCEmulator
    
    let card: NFCCard
    @State private var showingExportSheet = false
    
    var body: some View {
        List {
            // 基本信息
            Section("Basic Info") {
                InfoRow(label: "Type", value: card.type.rawValue)
                InfoRow(label: "UID", value: card.uidString)
                if let sak = card.sak {
                    InfoRow(label: "SAK", value: String(format: "0x%02X", sak))
                }
                if let atqa = card.atqa {
                    InfoRow(label: "ATQA", value: atqa.hexString)
                }
            }
            
            // Mifare数据
            if let sectors = card.sectors, !sectors.isEmpty {
                Section("Sectors (\(sectors.count))") {
                    ForEach(sectors) { sector in
                        DisclosureGroup("Sector \(sector.sectorNumber)") {
                            ForEach(sector.blocks) { block in
                                VStack(alignment: .leading) {
                                    Text("Block \(block.blockNumber)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(block.data.hexStringWithSpaces)
                                        .font(.system(.caption, design: .monospaced))
                                }
                            }
                        }
                    }
                }
            }
            
            // NDEF数据
            if let records = card.ndefRecords, !records.isEmpty {
                Section("NDEF Records") {
                    ForEach(records) { record in
                        VStack(alignment: .leading) {
                            Text("Type: \(record.typeString)")
                                .font(.caption)
                            if let text = record.payloadString {
                                Text(text)
                            } else {
                                Text(record.payload.hexString)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                }
            }
            
            // 操作
            Section("Actions") {
                Button(action: { emulator.startEmulation(card: card) }) {
                    Label("Emulate Card", systemImage: "antenna.radiowaves.left.and.right")
                }
                
                Button(action: { showingExportSheet = true }) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle(card.displayName)
        .sheet(isPresented: $showingExportSheet) {
            ExportSheet(card: card)
        }
    }
}

// MARK: - 信息行
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}

// MARK: - 导出表单
struct ExportSheet: View {
    @Environment(\.dismiss) var dismiss
    let card: NFCCard
    
    var body: some View {
        NavigationView {
            List {
                Button(action: exportJSON) {
                    Label("Export as JSON", systemImage: "doc.text")
                }
                
                Button(action: exportFlipper) {
                    Label("Export for Flipper Zero", systemImage: "wave.3.forward")
                }
            }
            .navigationTitle("Export")
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
    
    private func exportJSON() {
        // 实现JSON导出
    }
    
    private func exportFlipper() {
        // 实现Flipper格式导出
    }
}

// MARK: - 写入视图
struct WriteView: View {
    @EnvironmentObject var nfcManager: NFCManager
    @State private var ndefText = ""
    @State private var ndefURL = ""
    @State private var writeMode: WriteMode = .text
    
    enum WriteMode: String, CaseIterable {
        case text = "Text"
        case url = "URL"
        case raw = "Raw"
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Write Mode") {
                    Picker("Mode", selection: $writeMode) {
                        ForEach(WriteMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Data") {
                    switch writeMode {
                    case .text:
                        TextField("Enter text", text: $ndefText)
                    case .url:
                        TextField("Enter URL", text: $ndefURL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                    case .raw:
                        Text("Raw write coming soon...")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button(action: writeTag) {
                        HStack {
                            Spacer()
                            Image(systemName: "square.and.pencil")
                            Text("Write to Tag")
                            Spacer()
                        }
                    }
                    .disabled(!canWrite)
                }
            }
            .navigationTitle("Write")
        }
    }
    
    private var canWrite: Bool {
        switch writeMode {
        case .text: return !ndefText.isEmpty
        case .url: return !ndefURL.isEmpty
        case .raw: return false
        }
    }
    
    private func writeTag() {
        // 实现写入功能
    }
}

// MARK: - 模拟视图
struct EmulateView: View {
    @EnvironmentObject var emulator: NFCEmulator
    @EnvironmentObject var cardStorage: CardStorage
    
    @State private var selectedCard: NFCCard?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 状态
                EmulationStatusView(state: emulator.state)
                
                // 选择卡片
                if cardStorage.cards.isEmpty {
                    Text("No cards available to emulate")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    Picker("Select Card", selection: $selectedCard) {
                        Text("None").tag(nil as NFCCard?)
                        ForEach(cardStorage.cards) { card in
                            Text(card.displayName).tag(card as NFCCard?)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding()
                }
                
                // 模拟按钮
                if case .active = emulator.state {
                    Button(action: { emulator.stopEmulation() }) {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("Stop Emulation")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding()
                } else {
                    Button(action: startEmulation) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Start Emulation")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedCard != nil ? Color.green : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(selectedCard == nil)
                    .padding()
                }
                
                // 日志
                VStack(alignment: .leading) {
                    HStack {
                        Text("Log")
                            .font(.headline)
                        Spacer()
                        Button("Clear") {
                            emulator.clearLog()
                        }
                        .font(.caption)
                    }
                    
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(emulator.emulationLog, id: \.self) { log in
                                Text(log)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                .padding()
                
                Spacer()
                
                // 警告
                Text("⚠️ NFC emulation is experimental and may not work on all devices")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .navigationTitle("Emulate")
        }
    }
    
    private func startEmulation() {
        guard let card = selectedCard else { return }
        emulator.startEmulation(card: card)
    }
}

// MARK: - 模拟状态视图
struct EmulationStatusView: View {
    let state: EmulationState
    
    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
            Text(statusText)
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(20)
    }
    
    private var statusColor: Color {
        switch state {
        case .idle: return .gray
        case .preparing: return .orange
        case .active: return .green
        case .error: return .red
        }
    }
    
    private var statusText: String {
        switch state {
        case .idle: return "Not emulating"
        case .preparing: return "Preparing..."
        case .active: return "Emulating"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - 设置视图
struct SettingsView: View {
    @State private var showDebugInfo = false
    
    var body: some View {
        NavigationView {
            List {
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("TrollStore")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("NFC") {
                    Toggle("Show Debug Info", isOn: $showDebugInfo)
                    
                    NavigationLink("Common Keys") {
                        KeysView()
                    }
                }
                
                Section("Data") {
                    Button(role: .destructive) {
                        // 清除所有数据
                    } label: {
                        Text("Clear All Cards")
                    }
                }
                
                Section {
                    Link("GitHub Repository", destination: URL(string: "https://github.com")!)
                    Link("Report Issue", destination: URL(string: "https://github.com")!)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - 密钥视图
struct KeysView: View {
    let commonKeys = [
        ("Default", "FF FF FF FF FF FF"),
        ("MAD", "A0 A1 A2 A3 A4 A5"),
        ("NDEF", "D3 F7 D3 F7 D3 F7"),
        ("Empty", "00 00 00 00 00 00"),
    ]
    
    var body: some View {
        List {
            ForEach(commonKeys, id: \.0) { key in
                HStack {
                    Text(key.0)
                    Spacer()
                    Text(key.1)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Common Keys")
    }
}

#Preview {
    ContentView()
        .environmentObject(CardStorage())
        .environmentObject(NFCManager.shared)
        .environmentObject(NFCEmulator.shared)
}
