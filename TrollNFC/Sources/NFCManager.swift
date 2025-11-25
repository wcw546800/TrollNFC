//
//  NFCManager.swift
//  TrollNFC
//
//  NFC核心管理器 - 读取、写入、模拟
//

import Foundation
import CoreNFC
import Combine
import UIKit

// MARK: - 私有NFC API声明

// NFHardwareManager - 底层NFC硬件控制
@objc protocol NFHardwareManagerProtocol {
    static func sharedManager() -> AnyObject?
    var isAvailable: Bool { get }
    var isEnabled: Bool { get }
    func setNFCEnabled(_ enabled: Bool)
    func transceive(_ command: Data, completion: @escaping (Data?, Error?) -> Void)
    func startFieldDetect()
    func stopFieldDetect()
}

// NFCTagReaderSession私有扩展
@objc protocol NFCTagReaderSessionPrivate {
    func restartPolling()
}

// MARK: - NFC操作状态
enum NFCOperationState {
    case idle
    case scanning
    case reading
    case writing
    case emulating
    case error(String)
}

// MARK: - NFC操作类型
enum NFCOperation {
    case readNDEF
    case readTag
    case readMifare
    case writeNDEF(Data)
    case writeMifare(sectors: [MifareSector])
    case dumpCard
}

// MARK: - NFCManager
class NFCManager: NSObject, ObservableObject {
    static let shared = NFCManager()
    
    // Published状态
    @Published var state: NFCOperationState = .idle
    @Published var currentCard: NFCCard?
    @Published var scanProgress: Double = 0
    @Published var statusMessage: String = ""
    @Published var debugLog: [String] = []  // 调试日志
    
    // 添加日志
    func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logMessage = "[\(timestamp)] \(message)"
        print(logMessage)
        DispatchQueue.main.async {
            self.debugLog.append(logMessage)
            // 保留最近50条
            if self.debugLog.count > 50 {
                self.debugLog.removeFirst()
            }
        }
    }
    
    // NFC会话
    private var tagReaderSession: NFCTagReaderSession?
    private var ndefReaderSession: NFCNDEFReaderSession?
    
    // 回调
    private var readCompletion: ((Result<NFCCard, Error>) -> Void)?
    private var writeCompletion: ((Result<Void, Error>) -> Void)?
    
    // 当前操作
    private var currentOperation: NFCOperation = .readTag
    
    // Mifare密钥列表（用于尝试认证）
    private let commonKeys: [Data] = [
        Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),  // 默认密钥
        Data([0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5]),  // MAD密钥
        Data([0xD3, 0xF7, 0xD3, 0xF7, 0xD3, 0xF7]),  // NDEF密钥
        Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),  // 空密钥
        Data([0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5]),  // 常见密钥
        Data([0x4D, 0x3A, 0x99, 0xC3, 0x51, 0xDD]),  // 某些门禁卡
        Data([0x1A, 0x98, 0x2C, 0x7E, 0x45, 0x9A]),  // 某些门禁卡
    ]
    
    private override init() {
        super.init()
    }
    
    // MARK: - 检查NFC是否可用
    var isNFCAvailable: Bool {
        // 先检查官方API
        if NFCTagReaderSession.readingAvailable {
            return true
        }
        // 尝试私有API
        if let _ = getPrivateNFCManager() {
            return true
        }
        return false
    }
    
    // 私有NFC管理器实例
    private var privateNFCManager: AnyObject?
    
    // iOS 16+ 可能的NFC私有类名
    private let possibleNFCClasses = [
        "NFCHardwareManager",  // iOS 16+ 主要类
        "NFHardwareManager",
        "NFCManager",
        "NFDriver",
        "NFCDriver",
        "NFHardwareController",
        "NFCHardwareController",
        "NFReaderSession",
        "NFCReaderManager",
        "NFCFieldDetectManager",
        "NFFieldManager",
        "NFCC",
        "NFController",
        "NFCController"
    ]
    
    private let possibleSingletonMethods = [
        "sharedHardwareManager",  // iOS 16+ NFCHardwareManager使用这个
        "sharedManager",
        "sharedInstance", 
        "shared",
        "manager",
        "defaultManager",
        "currentManager"
    ]
    
    // 复制日志到剪贴板
    func copyLogToClipboard() {
        let logText = debugLog.joined(separator: "\n")
        UIPasteboard.general.string = logText
        log("✅ 日志已复制到剪贴板")
    }
    
    // 探测所有NFC相关私有类
    func discoverPrivateNFCClasses() {
        log("开始探测NFC私有类...")
        
        for className in possibleNFCClasses {
            if let cls = NSClassFromString(className) {
                log("✅ 发现类: \(className)")
                
                // 列出类方法
                var classMethodCount: UInt32 = 0
                if let classMethods = class_copyMethodList(object_getClass(cls), &classMethodCount) {
                    log("  类方法:")
                    for i in 0..<Int(classMethodCount) {
                        let method = classMethods[i]
                        let name = NSStringFromSelector(method_getName(method))
                        // 打印所有方法，不过滤
                        log("    + \(name)")
                    }
                    free(classMethods)
                }
                
                // 列出实例方法
                var methodCount: UInt32 = 0
                if let methods = class_copyMethodList(cls, &methodCount) {
                    log("  实例方法:")
                    for i in 0..<Int(methodCount) {
                        let method = methods[i]
                        let name = NSStringFromSelector(method_getName(method))
                        // 打印所有方法
                        log("    - \(name)")
                    }
                    free(methods)
                }
            }
        }
        
        log("探测完成")
    }
    
    // 获取私有NFC管理器
    private func getPrivateNFCManager() -> AnyObject? {
        if let manager = privateNFCManager {
            return manager
        }
        
        // 尝试所有可能的类名和方法
        for className in possibleNFCClasses {
            if let managerClass = NSClassFromString(className) {
                for methodName in possibleSingletonMethods {
                    let selector = NSSelectorFromString(methodName)
                    if let method = class_getClassMethod(managerClass, selector) {
                        let impl = method_getImplementation(method)
                        typealias Function = @convention(c) (AnyClass, Selector) -> AnyObject?
                        let function = unsafeBitCast(impl, to: Function.self)
                        if let manager = function(managerClass, selector) {
                            privateNFCManager = manager
                            log("✅ \(className).\(methodName) 获取成功")
                            return manager
                        }
                    }
                }
            }
        }
        
        log("❌ 无法获取任何NFC私有管理器")
        return nil
    }
    
    // MARK: - 私有API读取（无系统弹窗）
    func startPrivateReading(completion: @escaping (Result<NFCCard, Error>) -> Void) {
        log("开始私有API读取模式...")
        log("iOS版本: \(UIDevice.current.systemVersion)")
        
        // 先探测有哪些私有类可用
        discoverPrivateNFCClasses()
        
        guard let manager = getPrivateNFCManager() else {
            log("无法获取私有NFC管理器")
            log("回退到标准CoreNFC模式...")
            startReading(completion: completion)
            return
        }
        
        readCompletion = completion
        state = .scanning
        statusMessage = "私有模式 - 请将卡片靠近iPhone顶部"
        
        // 检查可用方法
        log("检查管理器方法...")
        
        // 尝试使用 queueReaderSession:sessionConfig:completionHandler:
        let queueSelector = NSSelectorFromString("queueReaderSession:sessionConfig:completionHandler:")
        if manager.responds(to: queueSelector) {
            log("✅ 支持 queueReaderSession")
            tryQueueReaderSession(manager: manager)
        } else {
            log("❌ 不支持 queueReaderSession")
            
            // 尝试其他方法
            let areFeaturesSelector = NSSelectorFromString("areFeaturesSupported:outError:")
            if manager.responds(to: areFeaturesSelector) {
                log("✅ 支持 areFeaturesSupported")
            }
            
            // 回退到标准模式
            log("回退到标准模式")
            startReading(completion: completion)
        }
    }
    
    private func tryQueueReaderSession(manager: AnyObject) {
        log("尝试创建Reader Session...")
        
        // 创建一个简单的session配置
        // 这里需要根据实际API调整
        let sessionConfig: [String: Any] = [
            "pollingOption": 7,  // ISO14443 | ISO15693 | ISO18092
            "alertMessage": "请将卡片放在iPhone顶部"
        ]
        
        // 使用完成回调
        let completionHandler: @convention(block) (AnyObject?, Error?) -> Void = { [weak self] session, error in
            guard let self = self else { return }
            
            if let error = error {
                self.log("❌ Session错误: \(error.localizedDescription)")
                self.state = .idle
                self.readCompletion?(.failure(error))
                return
            }
            
            if let session = session {
                self.log("✅ Session创建成功: \(type(of: session))")
                self.handlePrivateSession(session)
            } else {
                self.log("❌ Session为nil")
                self.state = .idle
            }
        }
        
        // 调用私有方法
        // 注意：这里的参数格式可能需要调整
        let selector = NSSelectorFromString("queueReaderSession:sessionConfig:completionHandler:")
        
        if manager.responds(to: selector) {
            // 由于参数类型复杂，我们需要使用NSInvocation或直接尝试
            log("调用 queueReaderSession...")
            
            // 先用标准方式测试
            startReading { [weak self] result in
                self?.log("标准读取结果已返回")
            }
        }
    }
    
    private func handlePrivateSession(_ session: AnyObject) {
        log("处理私有Session: \(type(of: session))")
        
        // 列出session的方法
        let cls: AnyClass = type(of: session)
        var methodCount: UInt32 = 0
        if let methods = class_copyMethodList(cls, &methodCount) {
            for i in 0..<min(Int(methodCount), 20) {
                let method = methods[i]
                let name = NSStringFromSelector(method_getName(method))
                log("  Session方法: \(name)")
            }
            free(methods)
        }
    }
    
    private func startPollingForTag(manager: AnyObject) {
        log("开始轮询标签...")
        
        // 尝试发送REQA命令 (ISO14443-3A)
        // REQA = 0x26, 用于激活卡片
        let reqaCommand = Data([0x26])
        
        let transceiveSelector = NSSelectorFromString("transceive:completion:")
        if manager.responds(to: transceiveSelector) {
            log("发送REQA命令...")
            
            // 使用定时器轮询
            pollForCard(manager: manager, attempts: 0, maxAttempts: 30)
        } else {
            log("私有管理器不支持transceive")
            // 回退到标准模式
            startReading(completion: readCompletion ?? { _ in })
        }
    }
    
    private func pollForCard(manager: AnyObject, attempts: Int, maxAttempts: Int) {
        guard attempts < maxAttempts else {
            log("轮询超时，未检测到卡片")
            state = .idle
            statusMessage = "未检测到卡片"
            readCompletion?(.failure(NFCError.tagNotFound))
            return
        }
        
        // 发送ISO14443 REQA/WUPA命令
        sendPrivateCommand(manager: manager, command: Data([0x52])) { [weak self] response, error in
            guard let self = self else { return }
            
            if let response = response, !response.isEmpty {
                // 收到响应，检测到卡片!
                self.log("✅ 检测到卡片! ATQA: \(response.hexString)")
                self.handlePrivateTagDetection(manager: manager, atqa: response)
            } else {
                // 继续轮询
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.pollForCard(manager: manager, attempts: attempts + 1, maxAttempts: maxAttempts)
                }
            }
        }
    }
    
    private func sendPrivateCommand(manager: AnyObject, command: Data, completion: @escaping (Data?, Error?) -> Void) {
        // 使用NSInvocation调用私有方法
        let selector = NSSelectorFromString("transceive:completion:")
        
        guard manager.responds(to: selector) else {
            completion(nil, NFCError.unsupportedTag)
            return
        }
        
        // 简化处理 - 直接调用
        let methodIMP = manager.method(for: selector)
        typealias TransceiveFunc = @convention(c) (AnyObject, Selector, Data, @escaping (Data?, Error?) -> Void) -> Void
        let transceive = unsafeBitCast(methodIMP, to: TransceiveFunc.self)
        transceive(manager, selector, command, completion)
    }
    
    private func handlePrivateTagDetection(manager: AnyObject, atqa: Data) {
        state = .reading
        statusMessage = "正在读取卡片..."
        
        // 发送防冲突命令获取UID
        // ANTICOLLISION = 0x93 0x20
        sendPrivateCommand(manager: manager, command: Data([0x93, 0x20])) { [weak self] response, error in
            guard let self = self else { return }
            
            if let uid = response, uid.count >= 4 {
                self.log("✅ UID: \(uid.hexString)")
                
                // 创建卡片对象
                var card = NFCCard(
                    name: "",
                    type: .mifareClassic,
                    uid: uid
                )
                card.atqa = atqa
                
                // 尝试获取SAK
                self.selectCard(manager: manager, uid: uid, card: &card)
            } else {
                self.log("获取UID失败")
                self.state = .idle
                self.readCompletion?(.failure(NFCError.readFailed))
            }
        }
    }
    
    private func selectCard(manager: AnyObject, uid: Data, card: inout NFCCard) {
        var mutableCard = card
        
        // SELECT命令 = 0x93 0x70 + UID(4字节) + BCC
        var selectCmd = Data([0x93, 0x70])
        selectCmd.append(uid.prefix(4))
        
        // 计算BCC
        var bcc: UInt8 = 0
        for byte in uid.prefix(4) {
            bcc ^= byte
        }
        selectCmd.append(bcc)
        
        sendPrivateCommand(manager: manager, command: selectCmd) { [weak self] response, error in
            guard let self = self else { return }
            
            if let sak = response?.first {
                self.log("✅ SAK: 0x\(String(format: "%02X", sak))")
                mutableCard.sak = sak
            }
            
            // 完成读取
            self.currentCard = mutableCard
            self.state = .idle
            self.statusMessage = "读取成功!"
            self.log("✅ 卡片读取完成")
            self.readCompletion?(.success(mutableCard))
            
            // 停止场检测
            let stopSelector = NSSelectorFromString("stopFieldDetect")
            if manager.responds(to: stopSelector) {
                _ = manager.perform(stopSelector)
            }
        }
    }
    
    // MARK: - 读取标签
    func startReading(operation: NFCOperation = .readTag, completion: @escaping (Result<NFCCard, Error>) -> Void) {
        log("开始读取...")
        
        guard isNFCAvailable else {
            log("错误: NFC不可用")
            statusMessage = "NFC不可用"
            completion(.failure(NFCError.notAvailable))
            return
        }
        
        log("NFC可用，启动会话...")
        log("轮询选项: ISO14443 + ISO15693 + ISO18092")
        currentOperation = operation
        readCompletion = completion
        state = .scanning
        statusMessage = "请将卡片放在iPhone顶部"
        
        // 使用所有可用的轮询选项
        // iso14443: Mifare, ISO-DEP (Type A/B)
        // iso15693: Vicinity cards  
        // iso18092: FeliCa, NFC-F
        tagReaderSession = NFCTagReaderSession(
            pollingOption: [.iso14443, .iso15693, .iso18092],
            delegate: self
        )
        tagReaderSession?.alertMessage = "请将卡片放在iPhone顶部\n保持静止直到读取完成"
        tagReaderSession?.begin()
        log("NFC会话已启动，等待检测标签...")
    }
    
    // MARK: - 使用原始ISO14443读取（尝试读取更多类型的卡）
    func startRawReading(completion: @escaping (Result<NFCCard, Error>) -> Void) {
        log("开始原始读取模式...")
        
        guard isNFCAvailable else {
            completion(.failure(NFCError.notAvailable))
            return
        }
        
        currentOperation = .readTag
        readCompletion = completion
        state = .scanning
        statusMessage = "原始模式 - 请将卡片放在iPhone顶部"
        
        // 只使用ISO14443，更精确的轮询
        tagReaderSession = NFCTagReaderSession(
            pollingOption: [.iso14443],
            delegate: self
        )
        tagReaderSession?.alertMessage = "原始ISO14443模式\n请将卡片放在iPhone顶部"
        tagReaderSession?.begin()
        log("ISO14443会话已启动")
    }
    
    // MARK: - 读取NDEF
    func readNDEF(completion: @escaping (Result<NFCCard, Error>) -> Void) {
        guard isNFCAvailable else {
            completion(.failure(NFCError.notAvailable))
            return
        }
        
        currentOperation = .readNDEF
        readCompletion = completion
        state = .scanning
        
        ndefReaderSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        ndefReaderSession?.alertMessage = "Hold your iPhone near the tag to read NDEF data"
        ndefReaderSession?.begin()
    }
    
    // MARK: - 写入NDEF
    func writeNDEF(_ message: NFCNDEFMessage, completion: @escaping (Result<Void, Error>) -> Void) {
        guard isNFCAvailable else {
            completion(.failure(NFCError.notAvailable))
            return
        }
        
        writeCompletion = completion
        state = .writing
        
        tagReaderSession = NFCTagReaderSession(
            pollingOption: [.iso14443],
            delegate: self
        )
        
        currentOperation = .writeNDEF(message.records.first?.payload ?? Data())
        tagReaderSession?.alertMessage = "Hold your iPhone near the tag to write"
        tagReaderSession?.begin()
    }
    
    // MARK: - Dump整张卡
    func dumpCard(completion: @escaping (Result<NFCCard, Error>) -> Void) {
        currentOperation = .dumpCard
        startReading(operation: .dumpCard, completion: completion)
    }
    
    // MARK: - 停止扫描
    func stopScanning() {
        tagReaderSession?.invalidate()
        ndefReaderSession?.invalidate()
        tagReaderSession = nil
        ndefReaderSession = nil
        state = .idle
        statusMessage = ""
    }
    
    // MARK: - 私有方法 - 处理Mifare标签
    private func handleMifareTag(_ tag: NFCMiFareTag, session: NFCTagReaderSession) {
        state = .reading
        log("正在读取Mifare标签...")
        statusMessage = "正在读取Mifare标签..."
        
        let uid = tag.identifier
        let uidString = uid.map { String(format: "%02X", $0) }.joined(separator: ":")
        log("UID: \(uidString)")
        
        var card = NFCCard(
            name: "",
            type: detectMifareType(tag),
            uid: uid
        )
        
        // 获取基本信息
        if let historicalBytes = tag.historicalBytes {
            card.ats = historicalBytes
            log("ATS: \(historicalBytes.map { String(format: "%02X", $0) }.joined())")
        }
        
        // 尝试获取SAK和ATQA（通过私有API）
        tryGetExtendedInfo(tag: tag, card: &card)
        
        // 尝试读取扇区
        if case .dumpCard = currentOperation {
            log("开始完整读取...")
            dumpMifareClassic(tag: tag, card: &card) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let dumpedCard):
                        self?.log("卡片读取成功!")
                        self?.currentCard = dumpedCard
                        session.alertMessage = "卡片读取成功!"
                        session.invalidate()
                        self?.state = .idle
                        self?.readCompletion?(.success(dumpedCard))
                    case .failure(let error):
                        self?.log("部分读取: \(error.localizedDescription)")
                        self?.currentCard = card
                        session.alertMessage = "部分读取成功"
                        session.invalidate()
                        self?.state = .idle
                        self?.readCompletion?(.success(card))
                    }
                }
            }
        } else {
            // 快速读取 - 只读取基本信息
            log("快速读取完成")
            currentCard = card
            session.alertMessage = "读取成功!"
            session.invalidate()
            state = .idle
            readCompletion?(.success(card))
        }
    }
    
    // MARK: - 尝试获取扩展信息（私有API）
    private func tryGetExtendedInfo(tag: NFCMiFareTag, card: inout NFCCard) {
        // 尝试通过反射获取SAK
        let tagObject = tag as AnyObject
        
        // 尝试获取SAK
        let sakSelector = NSSelectorFromString("sak")
        if tagObject.responds(to: sakSelector) {
            if let result = tagObject.perform(sakSelector) {
                let sak = UInt8(truncatingIfNeeded: Int(bitPattern: result.toOpaque()))
                card.sak = sak
                log("SAK: 0x\(String(format: "%02X", sak))")
            }
        }
        
        // 尝试获取ATQA
        let atqaSelector = NSSelectorFromString("atqa")
        if tagObject.responds(to: atqaSelector) {
            if let result = tagObject.perform(atqaSelector)?.takeUnretainedValue() as? Data {
                card.atqa = result
                log("ATQA: \(result.map { String(format: "%02X", $0) }.joined())")
            }
        }
    }
    
    // MARK: - Dump Mifare Classic
    private func dumpMifareClassic(tag: NFCMiFareTag, card: inout NFCCard, completion: @escaping (Result<NFCCard, Error>) -> Void) {
        var mutableCard = card
        let sectorCount = detectSectorCount(tag)
        mutableCard.mifareSize = sectorCount * 1024 / 16  // 粗略估算
        
        var sectors: [MifareSector] = []
        let group = DispatchGroup()
        
        for sectorNum in 0..<sectorCount {
            group.enter()
            
            readSector(tag: tag, sectorNumber: sectorNum) { result in
                switch result {
                case .success(let sector):
                    sectors.append(sector)
                case .failure:
                    // 创建空扇区（未能读取）
                    let emptyBlocks = (0..<4).map { blockNum -> MifareBlock in
                        MifareBlock(
                            blockNumber: sectorNum * 4 + blockNum,
                            data: Data(repeating: 0, count: 16),
                            isTrailerBlock: blockNum == 3
                        )
                    }
                    let emptySector = MifareSector(
                        sectorNumber: sectorNum,
                        blocks: emptyBlocks,
                        isUnlocked: false
                    )
                    sectors.append(emptySector)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            mutableCard.sectors = sectors.sorted { $0.sectorNumber < $1.sectorNumber }
            completion(.success(mutableCard))
        }
    }
    
    // MARK: - 读取单个扇区
    private func readSector(tag: NFCMiFareTag, sectorNumber: Int, completion: @escaping (Result<MifareSector, Error>) -> Void) {
        let firstBlock = sectorNumber * 4
        
        // 尝试用不同密钥认证
        tryAuthenticate(tag: tag, sector: sectorNumber, keyIndex: 0) { [weak self] authResult in
            guard let self = self else { return }
            
            switch authResult {
            case .success(let key):
                // 认证成功，读取块
                self.readBlocks(tag: tag, sectorNumber: sectorNumber, firstBlock: firstBlock, key: key, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - 尝试认证
    private func tryAuthenticate(tag: NFCMiFareTag, sector: Int, keyIndex: Int, completion: @escaping (Result<Data, Error>) -> Void) {
        guard keyIndex < commonKeys.count else {
            completion(.failure(NFCError.authenticationFailed))
            return
        }
        
        let key = commonKeys[keyIndex]
        let block = UInt8(sector * 4)
        
        // Mifare认证命令: 60 + block + uid(4) + key(6)
        var authCommand = Data([0x60, block])
        authCommand.append(tag.identifier.prefix(4))
        authCommand.append(key)
        
        tag.sendMiFareCommand(commandPacket: authCommand) { [weak self] response, error in
            if error == nil {
                completion(.success(key))
            } else {
                // 尝试下一个密钥
                self?.tryAuthenticate(tag: tag, sector: sector, keyIndex: keyIndex + 1, completion: completion)
            }
        }
    }
    
    // MARK: - 读取块
    private func readBlocks(tag: NFCMiFareTag, sectorNumber: Int, firstBlock: Int, key: Data, completion: @escaping (Result<MifareSector, Error>) -> Void) {
        var blocks: [MifareBlock] = []
        let group = DispatchGroup()
        
        for i in 0..<4 {
            let blockNumber = firstBlock + i
            group.enter()
            
            // 读取命令: 30 + block
            let readCommand = Data([0x30, UInt8(blockNumber)])
            
            tag.sendMiFareCommand(commandPacket: readCommand) { response, error in
                if error == nil {
                    let block = MifareBlock(
                        blockNumber: blockNumber,
                        data: response,
                        isTrailerBlock: i == 3
                    )
                    blocks.append(block)
                } else {
                    // 创建空块
                    let block = MifareBlock(
                        blockNumber: blockNumber,
                        data: Data(repeating: 0, count: 16),
                        isTrailerBlock: i == 3
                    )
                    blocks.append(block)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            let sector = MifareSector(
                sectorNumber: sectorNumber,
                blocks: blocks.sorted { $0.blockNumber < $1.blockNumber },
                keyA: key,
                isUnlocked: true
            )
            completion(.success(sector))
        }
    }
    
    // MARK: - 检测Mifare类型
    private func detectMifareType(_ tag: NFCMiFareTag) -> NFCCardType {
        switch tag.mifareFamily {
        case .desfire:
            return .mifareDesfire
        case .ultralight:
            return .mifareUltralight
        case .plus:
            return .mifarePlus
        case .unknown:
            // 尝试通过UID长度判断
            if tag.identifier.count == 4 {
                return .mifareClassic
            }
            return .iso14443A
        @unknown default:
            return .unknown
        }
    }
    
    // MARK: - 检测扇区数量
    private func detectSectorCount(_ tag: NFCMiFareTag) -> Int {
        // Mifare Classic 1K: 16扇区
        // Mifare Classic 4K: 40扇区 (32 * 4块 + 8 * 16块)
        // 默认假设1K
        return 16
    }
    
    // MARK: - 处理ISO15693标签
    private func handleISO15693Tag(_ tag: NFCISO15693Tag, session: NFCTagReaderSession) {
        state = .reading
        statusMessage = "Reading ISO15693 tag..."
        
        var card = NFCCard(
            name: "",
            type: .iso15693,
            uid: tag.identifier
        )
        
        card.icReference = UInt8(tag.icManufacturerCode)
        
        // 读取系统信息
        tag.getSystemInfo(requestFlags: [.highDataRate]) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    var updatedCard = card
                    updatedCard.dsfId = UInt8(info.dataStorageFormatIdentifier)
                    updatedCard.afi = UInt8(info.applicationFamilyIdentifier)
                    updatedCard.icReference = UInt8(info.icReference)
                    
                    // 读取数据块
                    self?.readISO15693Blocks(tag: tag, blockCount: info.totalBlocks) { rawData in
                        updatedCard.rawData = rawData
                        self?.currentCard = updatedCard
                        session.alertMessage = "Tag read successfully!"
                        session.invalidate()
                        self?.state = .idle
                        self?.readCompletion?(.success(updatedCard))
                    }
                    
                case .failure:
                    self?.currentCard = card
                    session.alertMessage = "Tag read (partial)"
                    session.invalidate()
                    self?.state = .idle
                    self?.readCompletion?(.success(card))
                }
            }
        }
    }
    
    // MARK: - 读取ISO15693块
    private func readISO15693Blocks(tag: NFCISO15693Tag, blockCount: Int, completion: @escaping (Data) -> Void) {
        var rawData = Data()
        let group = DispatchGroup()
        let lock = NSLock()
        
        for block in 0..<min(blockCount, 64) {
            group.enter()
            tag.readSingleBlock(requestFlags: [.highDataRate], blockNumber: UInt8(block)) { result in
                if case .success(let data) = result {
                    lock.lock()
                    rawData.append(data)
                    lock.unlock()
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(rawData)
        }
    }
    
    // MARK: - 处理FeliCa标签
    private func handleFeliCaTag(_ tag: NFCFeliCaTag, session: NFCTagReaderSession) {
        state = .reading
        statusMessage = "Reading FeliCa tag..."
        
        var card = NFCCard(
            name: "",
            type: .felica,
            uid: tag.currentIDm
        )
        
        card.idm = tag.currentIDm
        card.systemCode = tag.currentSystemCode
        
        currentCard = card
        session.alertMessage = "FeliCa tag read successfully!"
        session.invalidate()
        state = .idle
        readCompletion?(.success(card))
    }
    
    // MARK: - 处理ISO7816标签
    private func handleISO7816Tag(_ tag: NFCISO7816Tag, session: NFCTagReaderSession) {
        state = .reading
        statusMessage = "Reading ISO7816 tag..."
        
        var card = NFCCard(
            name: "",
            type: .iso7816,
            uid: tag.identifier
        )
        
        if let historicalBytes = tag.historicalBytes {
            card.ats = historicalBytes
        }
        
        currentCard = card
        session.alertMessage = "Tag read successfully!"
        session.invalidate()
        state = .idle
        readCompletion?(.success(card))
    }
}

// MARK: - NFCTagReaderSessionDelegate
extension NFCManager: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        log("会话已激活，等待扫描...")
        DispatchQueue.main.async {
            self.state = .scanning
            self.statusMessage = "正在扫描NFC标签..."
        }
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        log("会话结束: \(error.localizedDescription)")
        DispatchQueue.main.async {
            if let nfcError = error as? NFCReaderError,
               nfcError.code != .readerSessionInvalidationErrorUserCanceled {
                self.state = .error(error.localizedDescription)
                self.statusMessage = "错误: \(error.localizedDescription)"
                self.readCompletion?(.failure(error))
            }
            self.state = .idle
            self.tagReaderSession = nil
        }
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        log("检测到 \(tags.count) 个标签!")
        guard let tag = tags.first else {
            log("错误: 未找到标签")
            session.invalidate(errorMessage: "未找到标签")
            return
        }
        
        log("正在连接标签...")
        session.connect(to: tag) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                self.log("连接失败: \(error.localizedDescription)")
                session.invalidate(errorMessage: error.localizedDescription)
                return
            }
            
            self.log("连接成功，识别标签类型...")
            switch tag {
            case .miFare(let mifareTag):
                let uid = mifareTag.identifier.map { String(format: "%02X", $0) }.joined(separator: ":")
                self.log("Mifare标签, UID: \(uid)")
                self.handleMifareTag(mifareTag, session: session)
                
            case .iso15693(let iso15693Tag):
                self.log("ISO15693标签")
                self.handleISO15693Tag(iso15693Tag, session: session)
                
            case .feliCa(let feliCaTag):
                self.log("FeliCa标签")
                self.handleFeliCaTag(feliCaTag, session: session)
                
            case .iso7816(let iso7816Tag):
                self.log("ISO7816标签")
                self.handleISO7816Tag(iso7816Tag, session: session)
                
            @unknown default:
                self.log("未知标签类型")
                session.invalidate(errorMessage: "不支持的标签类型")
            }
        }
    }
}

// MARK: - NFCNDEFReaderSessionDelegate
extension NFCManager: NFCNDEFReaderSessionDelegate {
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            if let nfcError = error as? NFCReaderError,
               nfcError.code != .readerSessionInvalidationErrorUserCanceled,
               nfcError.code != .readerSessionInvalidationErrorFirstNDEFTagRead {
                self.state = .error(error.localizedDescription)
                self.readCompletion?(.failure(error))
            }
            self.state = .idle
            self.ndefReaderSession = nil
        }
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        guard let message = messages.first else { return }
        
        DispatchQueue.main.async {
            var card = NFCCard(
                name: "NDEF Tag",
                type: .ndef,
                uid: Data()
            )
            
            // 解析NDEF记录
            var records: [NDEFRecord] = []
            for record in message.records {
                let ndefRecord = NDEFRecord(
                    tnf: record.typeNameFormat.rawValue,
                    type: record.type,
                    identifier: record.identifier,
                    payload: record.payload
                )
                records.append(ndefRecord)
            }
            card.ndefRecords = records
            
            self.currentCard = card
            self.state = .idle
            self.readCompletion?(.success(card))
        }
    }
    
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        DispatchQueue.main.async {
            self.state = .scanning
        }
    }
}

// MARK: - NFC错误
enum NFCError: LocalizedError {
    case notAvailable
    case sessionFailed
    case tagNotFound
    case authenticationFailed
    case readFailed
    case writeFailed
    case unsupportedTag
    case emulationNotSupported
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "NFC is not available on this device"
        case .sessionFailed:
            return "NFC session failed"
        case .tagNotFound:
            return "No NFC tag found"
        case .authenticationFailed:
            return "Failed to authenticate with the tag"
        case .readFailed:
            return "Failed to read tag data"
        case .writeFailed:
            return "Failed to write to tag"
        case .unsupportedTag:
            return "This tag type is not supported"
        case .emulationNotSupported:
            return "NFC emulation is not supported"
        }
    }
}
