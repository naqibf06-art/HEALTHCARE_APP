import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecurityService {
  static final _storage = FlutterSecureStorage();
  static const _keyName = "secure_aes_key";

  static Future<encrypt.Key> _getKey() async {
    String? storedKey = await _storage.read(key: _keyName);

    if (storedKey == null) {
      final key = encrypt.Key.fromSecureRandom(32);
      await _storage.write(key: _keyName, value: key.base64);
      return key;
    }

    return encrypt.Key.fromBase64(storedKey);
  }

  static Future<String> encryptData(String plainText) async {
    if (plainText.isEmpty) return plainText;

    final key = await _getKey();
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));

    final encrypted = encrypter.encrypt(plainText, iv: iv);

    return "${iv.base64}:${encrypted.base64}";
  }

  static Future<String> decryptData(String encryptedText) async {
    if (encryptedText.isEmpty) return encryptedText;

    try {
      final key = await _getKey();
      final parts = encryptedText.split(":");

      final iv = encrypt.IV.fromBase64(parts[0]);
      final encryptedData = parts[1];

      final encrypter = encrypt.Encrypter(encrypt.AES(key));

      return encrypter.decrypt64(encryptedData, iv: iv);
    } catch (e) {
      return "Decryption Error";
    }
  }
}
