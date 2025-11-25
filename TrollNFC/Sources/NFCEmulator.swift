//
//  NFCEmulator.swift
//  TrollNFC
//
//  NFC卡片模拟器 - 实验性功能
//  警告：NFC模拟在iOS上受到严格限制，此功能可能无法在所有设备上工作
//

import Foundation
import Combine

// MARK: - 模拟状态
enum EmulationState: Equatable {
    case idle
    case preparing
    case active
    case error(String)
}

// MARK: - NFC模拟器
class NFCEmulator: ObservableObject {
    static let shared = NFCEmulator()
    
    @Published var state: EmulationState = .idle
    @Published var currentEmulatingCard: NFCCard?
    @Published var emulationLog: [String] = []
    
    private var hardwareManager: AnyObject?  // NFHardwareManager
    private var secureElementManager: AnyObject?  // NFSecureElementManager
    
    private init() {
        setupPrivateFrameworks()
    }
    
    // MARK: - 设置私有框架
    private func setupPrivateFrameworks() {
        // 尝试加载NFPrivate框架
        // 注意：这只在TrollStore环境下有效
        
        // 动态加载NFHardwareManager
        if let hwManagerClass = NSClassFromString("NFHardwareManager") as? NSObject.Type {
            let selector = NSSelectorFromString("sharedManager")
            if hwManagerClass.responds(to: selector) {
                hardwareManager = hwManagerClass.perform(selector)?.takeUnretainedValue()
                log("NFHardwareManager loaded successfully")
            }
        } else {
            log("NFHardwareManager not available - running in limited mode")
        }
        
        // 动态加载NFSecureElementManager
        if let seManagerClass = NSClassFromString("NFSecureElementManager") as? NSObject.Type {
            let selector = NSSelectorFromString("sharedManager")
            if seManagerClass.responds(to: selector) {
                secureElementManager = seManagerClass.perform(selector)?.takeUnretainedValue()
                log("NFSecureElementManager loaded successfully")
            }
        } else {
            log("NFSecureElementManager not available")
        }
    }
    
    // MARK: - 检查模拟功能是否可用
    var isEmulationAvailable: Bool {
        // 检查硬件管理器
        guard let hwManager = hardwareManager else {
            return false
        }
        
        // 检查是否支持模拟
        let selector = NSSelectorFromString("isEmulationSupported")
        if hwManager.responds(to: selector) {
            let result = hwManager.perform(selector)
            return result != nil
        }
        
        return false
    }
    
    // MARK: - 开始模拟
    func startEmulation(card: NFCCard) {
        guard isEmulationAvailable else {
            state = .error("NFC emulation is not available on this device")
            log("Error: Emulation not available")
            return
        }
        
        state = .preparing
        currentEmulatingCard = card
        log("Preparing to emulate: \(card.displayName)")
        
        // 准备模拟数据
        let emulationData = prepareEmulationData(card: card)
        
        // 使用私有API开始模拟
        if let hwManager = hardwareManager {
            let selector = NSSelectorFromString("startEmulation:")
            if hwManager.responds(to: selector) {
                _ = hwManager.perform(selector, with: emulationData)
                state = .active
                log("Emulation started for UID: \(card.uidString)")
            } else {
                state = .error("startEmulation method not found")
                log("Error: startEmulation method not available")
            }
        }
    }
    
    // MARK: - 停止模拟
    func stopEmulation() {
        guard state == .active else { return }
        
        if let hwManager = hardwareManager {
            let selector = NSSelectorFromString("stopEmulation")
            if hwManager.responds(to: selector) {
                _ = hwManager.perform(selector)
            }
        }
        
        state = .idle
        currentEmulatingCard = nil
        log("Emulation stopped")
    }
    
    // MARK: - 准备模拟数据
    private func prepareEmulationData(card: NFCCard) -> Data {
        var data = Data()
        
        // 基本卡片信息
        data.append(card.uid)
        
        // 根据卡片类型添加额外数据
        switch card.type {
        case .mifareClassic:
            // Mifare Classic模拟数据
            if let atqa = card.atqa {
                data.append(atqa)
            }
            if let sak = card.sak {
                data.append(sak)
            }
            // 添加扇区数据
            if let sectors = card.sectors {
                for sector in sectors {
                    for block in sector.blocks {
                        data.append(block.data)
                    }
                }
            }
            
        case .mifareUltralight:
            // Ultralight模拟数据
            if let rawData = card.rawData {
                data.append(rawData)
            }
            
        case .felica:
            // FeliCa模拟数据
            if let idm = card.idm {
                data.append(idm)
            }
            if let pmm = card.pmm {
                data.append(pmm)
            }
            if let systemCode = card.systemCode {
                data.append(systemCode)
            }
            
        default:
            // 通用数据
            if let rawData = card.rawData {
                data.append(rawData)
            }
        }
        
        return data
    }
    
    // MARK: - HCE模拟（实验性）
    func startHCEEmulation(card: NFCCard, aid: Data) {
        log("Starting HCE emulation with AID: \(aid.hexString)")
        
        // 尝试使用HCE（Host Card Emulation）
        // 注意：iOS原生不支持HCE，这是实验性功能
        
        if let hceSessionClass = NSClassFromString("NFCHCESession") as? NSObject.Type {
            let selector = NSSelectorFromString("sessionWithAID:")
            if hceSessionClass.responds(to: selector) {
                let session = hceSessionClass.perform(selector, with: aid)?.takeUnretainedValue()
                
                // 设置命令处理器
                let handlerSelector = NSSelectorFromString("setCommandHandler:")
                if let session = session, session.responds(to: handlerSelector) {
                    // 创建命令处理block
                    let handler: @convention(block) (Data, @escaping (Data) -> Void) -> Void = { [weak self] command, respond in
                        self?.handleHCECommand(command: command, card: card, respond: respond)
                    }
                    _ = session.perform(handlerSelector, with: handler)
                    
                    // 启动会话
                    let startSelector = NSSelectorFromString("start")
                    if session.responds(to: startSelector) {
                        _ = session.perform(startSelector)
                        state = .active
                        currentEmulatingCard = card
                        log("HCE emulation started")
                    }
                }
            }
        } else {
            state = .error("HCE is not supported on this device")
            log("Error: NFCHCESession class not found")
        }
    }
    
    // MARK: - 处理HCE命令
    private func handleHCECommand(command: Data, card: NFCCard, respond: @escaping (Data) -> Void) {
        log("Received APDU: \(command.hexString)")
        
        // 解析APDU命令
        guard command.count >= 4 else {
            respond(Data([0x6F, 0x00]))  // 通用错误
            return
        }
        
        let ins = command[1]
        
        // 处理常见命令
        switch ins {
        case 0xA4:  // SELECT
            log("SELECT command received")
            respond(Data([0x90, 0x00]))  // Success
            
        case 0xB0:  // READ BINARY
            log("READ BINARY command received")
            if let rawData = card.rawData {
                var response = rawData
                response.append(contentsOf: [0x90, 0x00])
                respond(response)
            } else {
                respond(Data([0x6A, 0x82]))  // File not found
            }
            
        case 0xB2:  // READ RECORD
            log("READ RECORD command received")
            respond(Data([0x90, 0x00]))
            
        default:
            log("Unknown command: \(String(format: "%02X", ins))")
            respond(Data([0x6D, 0x00]))  // Instruction not supported
        }
    }
    
    // MARK: - Secure Element模拟
    func loadToSecureElement(card: NFCCard) -> Bool {
        guard let seManager = secureElementManager else {
            log("Secure Element not available")
            return false
        }
        
        log("Attempting to load card to Secure Element...")
        
        let emulationData = prepareEmulationData(card: card)
        let selector = NSSelectorFromString("loadCardData:")
        
        if seManager.responds(to: selector) {
            _ = seManager.perform(selector, with: emulationData)
            log("Card loaded to Secure Element")
            return true
        }
        
        log("loadCardData method not available")
        return false
    }
    
    // MARK: - 日志
    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logEntry = "[\(timestamp)] \(message)"
        DispatchQueue.main.async {
            self.emulationLog.append(logEntry)
            // 保持日志不超过100条
            if self.emulationLog.count > 100 {
                self.emulationLog.removeFirst()
            }
        }
        print("NFCEmulator: \(message)")
    }
    
    // MARK: - 清除日志
    func clearLog() {
        emulationLog.removeAll()
    }
}

// MARK: - 模拟配置
struct EmulationConfig {
    var autoRespond: Bool = true
    var responseDelay: TimeInterval = 0
    var logAPDU: Bool = true
    var uid: Data
    var atqa: Data?
    var sak: UInt8?
    var ats: Data?
}
