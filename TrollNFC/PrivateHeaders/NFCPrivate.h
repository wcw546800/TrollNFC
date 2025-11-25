//
//  NFCPrivate.h
//  TrollNFC
//
//  私有NFC框架头文件声明
//  这些API来自逆向工程，仅在TrollStore环境下可用
//

#import <Foundation/Foundation.h>
#import <CoreNFC/CoreNFC.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - NFHardwareManager (私有)

// NFC硬件管理器 - 底层NFC控制
@interface NFHardwareManager : NSObject

+ (instancetype)sharedManager;

// 硬件状态
@property (nonatomic, readonly) BOOL isAvailable;
@property (nonatomic, readonly) BOOL isEnabled;
@property (nonatomic, readonly) BOOL isSessionActive;

// 开启/关闭NFC
- (void)setNFCEnabled:(BOOL)enabled;
- (void)startFieldDetect;
- (void)stopFieldDetect;

// 低级命令
- (void)transceive:(NSData *)command 
       completion:(void (^)(NSData * _Nullable response, NSError * _Nullable error))completion;

// 卡片模拟相关
- (void)startEmulation:(NSData *)emulationData;
- (void)stopEmulation;
- (BOOL)isEmulating;

@end

#pragma mark - NFCTagReaderSession扩展

@interface NFCTagReaderSession (Private)

// 连接到任意类型的标签
- (void)connectToAnyTag:(void (^)(id<NFCTag> _Nullable tag, NSError * _Nullable error))completion;

// 获取原始标签句柄
- (void *)rawTagHandle;

// 发送原始命令 (APDU)
- (void)sendRawCommand:(NSData *)command 
            completion:(void (^)(NSData * _Nullable response, NSError * _Nullable error))completion;

@end

#pragma mark - NFCMiFareTag扩展

@interface NSObject (NFCMiFareTagPrivate)

// Mifare Classic 命令
- (void)mifareAuthenticateSector:(uint8_t)sector 
                        keyType:(uint8_t)keyType // 0x60 = Key A, 0x61 = Key B
                            key:(NSData *)key
                     completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

- (void)mifareReadBlock:(uint8_t)block 
             completion:(void (^)(NSData * _Nullable data, NSError * _Nullable error))completion;

- (void)mifareWriteBlock:(uint8_t)block 
                    data:(NSData *)data
              completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

// Mifare Classic 特殊命令
- (void)mifareIncrementBlock:(uint8_t)block 
                       value:(int32_t)value
                  completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

- (void)mifareDecrementBlock:(uint8_t)block 
                       value:(int32_t)value
                  completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

- (void)mifareTransferBlock:(uint8_t)block 
                 completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

- (void)mifareRestoreBlock:(uint8_t)block 
                completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

// 获取完整UID（包括4/7/10字节）
- (NSData *)fullUID;

// 获取SAK
- (uint8_t)sak;

// 获取ATQA
- (NSData *)atqa;

@end

#pragma mark - NFCISO15693Tag扩展

@interface NSObject (NFCISO15693TagPrivate)

// 读取多个块
- (void)extendedReadMultipleBlocksWithRequestFlags:(uint8_t)flags
                                        blockRange:(NSRange)blockRange
                                       completion:(void (^)(NSArray<NSData *> * _Nullable blocks, NSError * _Nullable error))completion;

// 写入多个块
- (void)extendedWriteMultipleBlocksWithRequestFlags:(uint8_t)flags
                                         blockRange:(NSRange)blockRange
                                           dataBlocks:(NSArray<NSData *> *)dataBlocks
                                          completion:(void (^)(NSError * _Nullable error))completion;

// 获取系统信息
- (void)getExtendedSystemInfoWithRequestFlags:(uint8_t)flags
                                   completion:(void (^)(NSDictionary * _Nullable info, NSError * _Nullable error))completion;

// 密码认证
- (void)authenticateWithRequestFlags:(uint8_t)flags
                         cryptoSuiteIdentifier:(uint8_t)csi
                                    message:(NSData *)message
                                 completion:(void (^)(NSData * _Nullable response, NSError * _Nullable error))completion;

@end

#pragma mark - NFCFeliCaTag扩展

@interface NSObject (NFCFeliCaTagPrivate)

// 读取不带加密的块
- (void)readWithoutEncryptionWithServiceCodeList:(NSArray<NSData *> *)serviceCodeList
                                      blockList:(NSArray<NSData *> *)blockList
                                     completion:(void (^)(NSInteger statusFlag1, NSInteger statusFlag2, NSArray<NSData *> * _Nullable blockData, NSError * _Nullable error))completion;

// 写入不带加密的块
- (void)writeWithoutEncryptionWithServiceCodeList:(NSArray<NSData *> *)serviceCodeList
                                       blockList:(NSArray<NSData *> *)blockList
                                       blockData:(NSArray<NSData *> *)blockData
                                      completion:(void (^)(NSInteger statusFlag1, NSInteger statusFlag2, NSError * _Nullable error))completion;

// 获取系统代码列表
- (NSArray<NSData *> *)systemCodeList;

@end

#pragma mark - Secure Element (实验性 - 用于卡片模拟)

// 警告：Secure Element访问受到严格限制，即使在TrollStore环境下也可能无法工作
@interface NFSecureElementManager : NSObject

+ (instancetype)sharedManager;

// 检查SE是否可用
@property (nonatomic, readonly) BOOL isSecureElementAvailable;

// 加载卡片数据到SE
- (BOOL)loadCardData:(NSData *)cardData error:(NSError **)error;

// 开始模拟
- (BOOL)startEmulationWithError:(NSError **)error;

// 停止模拟
- (void)stopEmulation;

// 获取当前模拟状态
@property (nonatomic, readonly) BOOL isEmulating;

@end

#pragma mark - HCE (Host Card Emulation) - 实验性

// 注意：iOS原生不支持HCE，这是通过私有API的实验性尝试
@interface NFCHCESession : NSObject

typedef void (^NFCHCECommandHandler)(NSData *command, void (^respond)(NSData *response));

+ (instancetype)sessionWithAID:(NSData *)aid;

// 设置命令处理器
- (void)setCommandHandler:(NFCHCECommandHandler)handler;

// 开始HCE会话
- (BOOL)startWithError:(NSError **)error;

// 停止HCE会话
- (void)stop;

@end

#pragma mark - 常用Mifare密钥

static const uint8_t MIFARE_KEY_DEFAULT[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
static const uint8_t MIFARE_KEY_MAD[6] = {0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5};
static const uint8_t MIFARE_KEY_NDEF[6] = {0xD3, 0xF7, 0xD3, 0xF7, 0xD3, 0xF7};

#pragma mark - NFC命令常量

// Mifare命令
static const uint8_t MIFARE_CMD_AUTH_KEY_A = 0x60;
static const uint8_t MIFARE_CMD_AUTH_KEY_B = 0x61;
static const uint8_t MIFARE_CMD_READ = 0x30;
static const uint8_t MIFARE_CMD_WRITE = 0xA0;
static const uint8_t MIFARE_CMD_INCREMENT = 0xC1;
static const uint8_t MIFARE_CMD_DECREMENT = 0xC0;
static const uint8_t MIFARE_CMD_TRANSFER = 0xB0;
static const uint8_t MIFARE_CMD_RESTORE = 0xC2;

// ISO14443-4 命令
static const uint8_t ISO14443_CMD_RATS = 0xE0;
static const uint8_t ISO14443_CMD_PPS = 0xD0;
static const uint8_t ISO14443_CMD_DESELECT = 0xC2;

NS_ASSUME_NONNULL_END
