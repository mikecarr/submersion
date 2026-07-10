import 'package:shared_preferences/shared_preferences.dart';

/// Which media store this device is attached to. Secret-free; credentials
/// live in the keychain (MediaStoreCredentialsStore). SharedPreferences so
/// a database restore cannot silently re-point the device at a different
/// store (same reasoning as the library-epoch mirror).
class MediaStoreAttachState {
  MediaStoreAttachState({SharedPreferences? prefs}) : _prefs = prefs;

  final SharedPreferences? _prefs;

  static const String storeIdKey = 'media_store_attached_store_id';

  Future<SharedPreferences> get _resolved async =>
      _prefs ?? await SharedPreferences.getInstance();

  Future<String?> attachedStoreId() async =>
      (await _resolved).getString(storeIdKey);

  Future<void> setAttached(String storeId) async =>
      (await _resolved).setString(storeIdKey, storeId);

  Future<void> clear() async {
    await (await _resolved).remove(storeIdKey);
  }
}
