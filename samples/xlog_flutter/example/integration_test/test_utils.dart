import 'dart:io';
import 'package:xlog_flutter/xlog_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// 共享测试工具类，处理临时目录和清理
class XlogTestUtils {
  static late Directory tempLogDir;
  
  /// 初始化测试环境
  static Future<void> setUp() async {
    tempLogDir = await getTemporaryDirectory();
  }
  
  /// 清理测试环境（释放实例、删除临时文件）
  static Future<void> tearDown(String nameprefix) async {
    // Release the instance
    if (XLog.has(nameprefix)) {
      XLog.release(nameprefix);
    }
    
    // Give native layer time to close files
    await Future.delayed(Duration(milliseconds: 100));
  }
  
  /// 验证文件魔数（用于压缩/加密验证）
  static Future<bool> hasZlibMagic(File file) async {
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    if (bytes.length < 2) return false;
    // zlib: 0x78 0x9C
    return bytes[0] == 0x78 && bytes[1] == 0x9C;
  }
  
  static Future<bool> hasZstdMagic(File file) async {
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    if (bytes.length < 4) return false;
    // zstd: 0x28 0xB5 0x2F 0xFD
    return bytes[0] == 0x28 && bytes[1] == 0xB5 && 
           bytes[2] == 0x2F && bytes[3] == 0xFD;
  }
  
  static Future<bool> isEncrypted(File file) async {
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    if (bytes.length < 100) return false;
    
    // Encrypted files typically don't start with common magic bytes
    // and have random-looking header
    final header = bytes.sublist(0, 20);
    // Simple check: no obvious text or compression magic
    for (int b in header) {
      if (b < 32 && b != 9 && b != 10 && b != 13) {
        // Non-printable byte (good sign of encryption)
        return true;
      }
    }
    return false;
  }
  
  /// 获取实例的日志文件列表
  static Future<List<File>> getLogFiles(XLogInstance instance) async {
    final logPath = instance.logPath;
    if (logPath == null) return [];
    final logDir = Directory(logPath);
    
    if (!await logDir.exists()) return [];
    
    final files = <File>[];
    await for (final entity in logDir.list()) {
      if (entity is File) {
        files.add(entity);
      }
    }
    return files;
  }
  
  /// 获取文件大小
  static Future<int> getFileSize(File file) async {
    if (!await file.exists()) return 0;
    return await file.length();
  }
}
