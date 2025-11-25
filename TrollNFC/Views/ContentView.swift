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
                    Text("读取")
                }
                .tag(0)
            
            // 卡片列表
            CardListView()
                .tabItem {
                    Image(systemName: "creditcard.fill")
                    Text("卡片")
                }
                .tag(1)
            
            // 写入标签页
            WriteView()
                .tabItem {
                    Image(systemName: "square.and.pencil")
                    Text("写入")
                }
                .tag(2)
            
            // 模拟标签页
            EmulateView()
                .tabItem {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("模拟")
                }
                .tag(3)
            
            // 设置
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("设置")
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
                Text(nfcManager.statusMessage.isEmpty ? "准备就绪" : nfcManager.statusMessage)
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // 扫描按钮
                VStack(spacing: 12) {
                    Button(action: startQuickRead) {
                        HStack {
                            Image(systemName: "wave.3.right")
                            Text("快速读取")
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
                            Text("完整读取")
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
                            Text("读取NDEF")
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
            .alert("保存卡片", isPresented: $showingSaveAlert) {
                TextField("卡片名称", text: $cardName)
                Button("取消", role: .cancel) {}
                Button("保存") {
                    saveCurrentCard()
                }
            } message: {
                Text("请输入卡片名称")
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
        case .idle: return "就绪"
        case .scanning: return "扫描中..."
        case .reading: return "读取中..."
        case .writing: return "写入中..."
        case .emulating: return "模拟中..."
        case .error(let msg): return "错误: \(msg)"
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
                    Text("暂无保存的卡片")
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
            .navigationTitle("已保存卡片")
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
            Section("基本信息") {
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
                Section("扇区 (\(sectors.count))") {
                    ForEach(sectors) { sector in
                        DisclosureGroup("扇区 \(sector.sectorNumber)") {
                            ForEach(sector.blocks) { block in
                                VStack(alignment: .leading) {
                                    Text("块 \(block.blockNumber)")
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
                Section("NDEF记录") {
                    ForEach(records) { record in
                        VStack(alignment: .leading) {
                            Text("类型: \(record.typeString)")
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
            Section("操作") {
                Button(action: { emulator.startEmulation(card: card) }) {
                    Label("模拟卡片", systemImage: "antenna.radiowaves.left.and.right")
                }
                
                Button(action: { showingExportSheet = true }) {
                    Label("导出", systemImage: "square.and.arrow.up")
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
                    Label("导出为JSON", systemImage: "doc.text")
                }
                
                Button(action: exportFlipper) {
                    Label("导出为Flipper Zero格式", systemImage: "wave.3.forward")
                }
            }
            .navigationTitle("导出")
            .toolbar {
                Button("完成") { dismiss() }
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
        case text = "文本"
        case url = "网址"
        case raw = "原始数据"
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("写入模式") {
                    Picker("模式", selection: $writeMode) {
                        ForEach(WriteMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("数据") {
                    switch writeMode {
                    case .text:
                        TextField("输入文本", text: $ndefText)
                    case .url:
                        TextField("输入网址", text: $ndefURL)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                    case .raw:
                        Text("原始写入功能即将推出...")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button(action: writeTag) {
                        HStack {
                            Spacer()
                            Image(systemName: "square.and.pencil")
                            Text("写入到标签")
                            Spacer()
                        }
                    }
                    .disabled(!canWrite)
                }
            }
            .navigationTitle("写入")
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
                    Text("没有可模拟的卡片")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    Picker("选择卡片", selection: $selectedCard) {
                        Text("无").tag(nil as NFCCard?)
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
                            Text("停止模拟")
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
                            Text("开始模拟")
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
                        Text("日志")
                            .font(.headline)
                        Spacer()
                        Button("清除") {
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
                Text("⚠️ NFC模拟功能为实验性功能，可能无法在所有设备上正常工作")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .navigationTitle("模拟")
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
        case .idle: return "未模拟"
        case .preparing: return "准备中..."
        case .active: return "模拟中"
        case .error(let msg): return "错误: \(msg)"
        }
    }
}

// MARK: - 设置视图
struct SettingsView: View {
    @State private var showDebugInfo = false
    
    var body: some View {
        NavigationView {
            List {
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("构建")
                        Spacer()
                        Text("TrollStore")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("NFC") {
                    Toggle("显示调试信息", isOn: $showDebugInfo)
                    
                    NavigationLink("常用密钥") {
                        KeysView()
                    }
                }
                
                Section("数据") {
                    Button(role: .destructive) {
                        // 清除所有数据
                    } label: {
                        Text("清除所有卡片")
                    }
                }
                
                Section {
                    Link("GitHub仓库", destination: URL(string: "https://github.com")!)
                    Link("报告问题", destination: URL(string: "https://github.com")!)
                }
            }
            .navigationTitle("设置")
        }
    }
}

// MARK: - 密钥视图
struct KeysView: View {
    let commonKeys = [
        ("默认密钥", "FF FF FF FF FF FF"),
        ("MAD密钥", "A0 A1 A2 A3 A4 A5"),
        ("NDEF密钥", "D3 F7 D3 F7 D3 F7"),
        ("空密钥", "00 00 00 00 00 00"),
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
        .navigationTitle("常用密钥")
    }
}

#Preview {
    ContentView()
        .environmentObject(CardStorage())
        .environmentObject(NFCManager.shared)
        .environmentObject(NFCEmulator.shared)
}
