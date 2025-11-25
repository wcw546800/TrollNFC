//
//  NFCManager.swift
//  TrollNFC
//
//  NFC核心管理器 - 读取、写入、模拟
//

import Foundation
import CoreNFC
import Combine

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
        NFCTagReaderSession.readingAvailable
    }
    
    // MARK: - 读取标签
    func startReading(operation: NFCOperation = .readTag, completion: @escaping (Result<NFCCard, Error>) -> Void) {
        guard isNFCAvailable else {
            completion(.failure(NFCError.notAvailable))
            return
        }
        
        currentOperation = operation
        readCompletion = completion
        state = .scanning
        statusMessage = "Hold your iPhone near the NFC tag"
        
        // 使用TagReaderSession以获取更多标签信息
        tagReaderSession = NFCTagReaderSession(
            pollingOption: [.iso14443, .iso15693, .iso18092],
            delegate: self
        )
        tagReaderSession?.alertMessage = "Hold your iPhone near the NFC tag to read"
        tagReaderSession?.begin()
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
        statusMessage = "Reading Mifare tag..."
        
        let uid = tag.identifier
        var card = NFCCard(
            name: "",
            type: detectMifareType(tag),
            uid: uid
        )
        
        // 获取基本信息
        if let historicalBytes = tag.historicalBytes {
            card.ats = historicalBytes
        }
        
        // 尝试读取扇区
        if case .dumpCard = currentOperation {
            dumpMifareClassic(tag: tag, card: &card) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let dumpedCard):
                        self?.currentCard = dumpedCard
                        session.alertMessage = "Card read successfully!"
                        session.invalidate()
                        self?.state = .idle
                        self?.readCompletion?(.success(dumpedCard))
                    case .failure(let error):
                        // 即使dump失败，也返回基本卡片信息
                        self?.currentCard = card
                        session.alertMessage = "Partial read: \(error.localizedDescription)"
                        session.invalidate()
                        self?.state = .idle
                        self?.readCompletion?(.success(card))
                    }
                }
            }
        } else {
            // 简单读取
            currentCard = card
            session.alertMessage = "Tag read successfully!"
            session.invalidate()
            state = .idle
            readCompletion?(.success(card))
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
                    updatedCard.icReference = info.icReference
                    
                    // 读取数据块
                    self?.readISO15693Blocks(tag: tag, blockCount: info.blockCount) { rawData in
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
        DispatchQueue.main.async {
            self.state = .scanning
            self.statusMessage = "Scanning for NFC tags..."
        }
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async {
            if let nfcError = error as? NFCReaderError,
               nfcError.code != .readerSessionInvalidationErrorUserCanceled {
                self.state = .error(error.localizedDescription)
                self.readCompletion?(.failure(error))
            }
            self.state = .idle
            self.tagReaderSession = nil
        }
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No tag found")
            return
        }
        
        session.connect(to: tag) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                session.invalidate(errorMessage: error.localizedDescription)
                return
            }
            
            switch tag {
            case .miFare(let mifareTag):
                self.handleMifareTag(mifareTag, session: session)
                
            case .iso15693(let iso15693Tag):
                self.handleISO15693Tag(iso15693Tag, session: session)
                
            case .feliCa(let feliCaTag):
                self.handleFeliCaTag(feliCaTag, session: session)
                
            case .iso7816(let iso7816Tag):
                self.handleISO7816Tag(iso7816Tag, session: session)
                
            @unknown default:
                session.invalidate(errorMessage: "Unsupported tag type")
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
