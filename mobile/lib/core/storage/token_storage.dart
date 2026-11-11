import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the API token lives. On Android this is backed by the Keystore.
abstract class TokenStorage {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'api_token';
  final FlutterSecureStorage _storage;

  // Read once, then served from memory: the token is needed on every request.
  String? _cached;
  bool _loaded = false;

  @override
  Future<String?> read() async {
    if (!_loaded) {
      _cached = await _storage.read(key: _key);
      _loaded = true;
    }
    return _cached;
  }

  @override
  Future<void> write(String token) async {
    await _storage.write(key: _key, value: token);
    _cached = token;
    _loaded = true;
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _key);
    _cached = null;
    _loaded = true;
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) => SecureTokenStorage());
