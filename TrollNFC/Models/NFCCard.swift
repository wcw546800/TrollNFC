//
//  NFCCard.swift
//  TrollNFC
//
//  NFC卡片数据模型
//

import Foundation

// MARK: - 卡片类型枚举
enum NFCCardType: String, Codable, CaseIterable {
    case mifareClassic = "Mifare Classic"
    case mifareUltralight = "Mifare Ultralight"
    case mifareDesfire = "Mifare DESFire"
    case mifarePlus = "Mifare Plus"
    case iso14443A = "ISO 14443-A"
    case iso14443B = "ISO 14443-B"
    case iso15693 = "ISO 15693"
    case felica = "FeliCa"
    case iso7816 = "ISO 7816"
    case ndef = "NDEF"
    case unknown = "Unknown"
    
    var icon: String {
        switch self {
        case .mifareClassic, .mifareUltralight, .mifareDesfire, .mifarePlus:
            return "creditcard.fill"
        case .felica:
            return "tram.fill"
        case .iso7816:
            return "key.fill"
        case .ndef:
            return "tag.fill"
        default:
            return "wave.3.right"
        }
    }
}

// MARK: - Mifare扇区数据
struct MifareSector: Codable, Identifiable {
    var id = UUID()
    var sectorNumber: Int
    var blocks: [MifareBlock]
    var keyA: Data?
    var keyB: Data?
    var accessBits: Data?
    var isUnlocked: Bool = false
}

struct MifareBlock: Codable, Identifiable {
    var id = UUID()
    var blockNumber: Int
    var data: Data
    var isTrailerBlock: Bool
}

// MARK: - NFC卡片主模型
struct NFCCard: Codable, Identifiable, Hashable {
    static func == (lhs: NFCCard, rhs: NFCCard) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    var id = UUID()
    var name: String
    var type: NFCCardType
    var uid: Data
    var atqa: Data?  // ISO14443A Answer To Request Type A
    var sak: UInt8?  // ISO14443A Select Acknowledge
    var ats: Data?   // Answer To Select (ISO14443-4)
    
    // 原始数据
    var rawData: Data?
    
    // Mifare特有数据
    var sectors: [MifareSector]?
    var mifareSize: Int?  // 1K = 1024, 4K = 4096
    
    // FeliCa特有数据
    var idm: Data?  // Manufacture ID
    var pmm: Data?  // Manufacture Parameter
    var systemCode: Data?
    
    // ISO15693特有数据
    var dsfId: UInt8?
    var afi: UInt8?
    var icReference: UInt8?
    
    // NDEF数据
    var ndefMessage: Data?
    var ndefRecords: [NDEFRecord]?
    
    // 元数据
    var createdAt: Date = Date()
    var notes: String = ""
    var isFavorite: Bool = false
    
    // 计算属性
    var uidString: String {
        uid.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
    
    var displayName: String {
        name.isEmpty ? "Card \(uidString.prefix(8))" : name
    }
    
    var sizeDescription: String {
        if let size = mifareSize {
            return size >= 1024 ? "\(size / 1024)K" : "\(size) bytes"
        }
        return "Unknown"
    }
}

// MARK: - NDEF记录
struct NDEFRecord: Codable, Identifiable {
    var id = UUID()
    var tnf: UInt8  // Type Name Format
    var type: Data
    var identifier: Data?
    var payload: Data
    
    var typeString: String {
        String(data: type, encoding: .utf8) ?? type.hexString
    }
    
    var payloadString: String? {
        // 尝试UTF-8解码
        if let text = String(data: payload, encoding: .utf8) {
            return text
        }
        // 尝试移除第一个字节（语言代码长度）后解码
        if payload.count > 1 {
            let langCodeLength = Int(payload[0] & 0x3F)
            if langCodeLength < payload.count - 1 {
                let textData = payload.dropFirst(1 + langCodeLength)
                return String(data: Data(textData), encoding: .utf8)
            }
        }
        return nil
    }
    
    var recordType: NDEFRecordType {
        switch tnf {
        case 0x01: // Well Known
            if typeString == "T" { return .text }
            if typeString == "U" { return .uri }
            if typeString == "Sp" { return .smartPoster }
        case 0x02: // MIME
            return .mime
        case 0x04: // External
            return .external
        default:
            break
        }
        return .unknown
    }
}

enum NDEFRecordType {
    case text
    case uri
    case smartPoster
    case mime
    case external
    case unknown
}

// MARK: - Data扩展
extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
    
    var hexStringWithSpaces: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
    
    init?(hexString: String) {
        let hex = hexString.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ":", with: "")
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
            index = nextIndex
        }
        self = data
    }
}

// MARK: - 卡片存储管理
class CardStorage: ObservableObject {
    @Published var cards: [NFCCard] = []
    
    private let storageKey = "TrollNFC_SavedCards"
    
    init() {
        loadCards()
    }
    
    func saveCard(_ card: NFCCard) {
        if let index = cards.firstIndex(where: { $0.id == card.id }) {
            cards[index] = card
        } else {
            cards.append(card)
        }
        persistCards()
    }
    
    func deleteCard(_ card: NFCCard) {
        cards.removeAll { $0.id == card.id }
        persistCards()
    }
    
    func deleteCard(at indexSet: IndexSet) {
        cards.remove(atOffsets: indexSet)
        persistCards()
    }
    
    private func loadCards() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            cards = try JSONDecoder().decode([NFCCard].self, from: data)
        } catch {
            print("Failed to load cards: \(error)")
        }
    }
    
    private func persistCards() {
        do {
            let data = try JSONEncoder().encode(cards)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save cards: \(error)")
        }
    }
    
    // 导出卡片为JSON
    func exportCard(_ card: NFCCard) -> Data? {
        try? JSONEncoder().encode(card)
    }
    
    // 导入卡片
    func importCard(from data: Data) -> NFCCard? {
        try? JSONDecoder().decode(NFCCard.self, from: data)
    }
    
    // 导出为Flipper Zero格式 (.nfc)
    func exportToFlipperFormat(_ card: NFCCard) -> String {
        var output = "Filetype: Flipper NFC device\n"
        output += "Version: 2\n"
        output += "Device type: \(card.type.rawValue)\n"
        output += "UID: \(card.uid.hexStringWithSpaces)\n"
        
        if let atqa = card.atqa {
            output += "ATQA: \(atqa.hexStringWithSpaces)\n"
        }
        if let sak = card.sak {
            output += "SAK: \(String(format: "%02X", sak))\n"
        }
        
        // Mifare数据
        if let sectors = card.sectors {
            for sector in sectors {
                for block in sector.blocks {
                    output += "Block \(block.blockNumber): \(block.data.hexStringWithSpaces)\n"
                }
            }
        }
        
        return output
    }
}
