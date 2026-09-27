import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized service for persisting and hydrating screen filter preferences
/// and selected store configurations, scoped per user account.
///
/// Backed by [SharedPreferences] with user-scoped domain keys:
/// - 'filter_prefs_${username}_invoices'
/// - 'filter_prefs_${username}_customers'
/// - 'filter_prefs_${username}_products'
/// - 'selected_store_${username}'
///
/// If [SharedPreferences] is unavailable or throws (e.g. in unmocked tests),
/// the service transparently falls back to an in-memory map.
class FilterStorageService {
  SharedPreferences? _prefs;
  final String? _instanceUsername;
  final String? Function()? _usernameResolver;
  static SharedPreferences? _sharedPrefs;
  static final Map<String, dynamic> _staticInMemoryFallback = {};

  FilterStorageService([
    SharedPreferences? prefs,
    String? username,
    String? Function()? usernameResolver,
  ])  : _prefs = prefs,
        _instanceUsername = username,
        _usernameResolver = usernameResolver {
    if (prefs != null) {
      _sharedPrefs = prefs;
    }
  }

  SharedPreferences? get prefs => _prefs ?? _sharedPrefs;

  String? get username => _instanceUsername ?? _usernameResolver?.call();

  static void setSharedPrefs(SharedPreferences? prefs) {
    _sharedPrefs = prefs;
  }

  static SharedPreferences? get sharedPrefs => _sharedPrefs;

  static void resetSharedPrefs() {
    _sharedPrefs = null;
    _staticInMemoryFallback.clear();
  }

  static const String overviewKey = 'filter_prefs_overview';
  static const String invoicesKey = 'filter_prefs_invoices';
  static const String customersKey = 'filter_prefs_customers';
  static const String productsKey = 'filter_prefs_products';

  /// Sanitizes username for use in storage keys.
  /// Removes leading/trailing whitespace, converts special characters to URI encoding.
  static String sanitizeUsername(String username) {
    final clean = username.trim();
    if (clean.isEmpty) return '';
    return Uri.encodeComponent(clean).replaceAll('.', '%2E');
  }

  /// Resolves store selection key for a given username: 'selected_store_${username}'.
  static String resolveStoreKey(String username) {
    final sanitized = sanitizeUsername(username);
    if (sanitized.isEmpty) return 'selected_store';
    if (sanitized.startsWith('selected_store_')) return sanitized;
    return 'selected_store_$sanitized';
  }

  /// Resolves short domain names ('invoices') or keys to user-scoped keys:
  /// - With username: 'filter_prefs_${username}_${domain}'
  /// - Without username: 'filter_prefs_${domain}'
  /// - For store: 'selected_store_${username}'
  static String resolveKey(String domainOrKey, [String? username]) {
    final cleanUser = (username != null && username.trim().isNotEmpty)
        ? sanitizeUsername(username)
        : null;

    if (domainOrKey == 'selected_store' ||
        domainOrKey.startsWith('selected_store_')) {
      if (cleanUser == null) {
        return domainOrKey;
      }
      return resolveStoreKey(cleanUser);
    }

    if (cleanUser != null) {
      final userPrefix = 'filter_prefs_${cleanUser}_';
      if (domainOrKey.startsWith(userPrefix)) {
        return domainOrKey;
      }
      String domain = domainOrKey;
      if (domain.startsWith('filter_prefs_')) {
        final rest = domain.substring('filter_prefs_'.length);
        final parts = rest.split('_');
        if (parts.length > 1 &&
            (parts.last == 'invoices' ||
                parts.last == 'customers' ||
                parts.last == 'products' ||
                parts.last == 'overview')) {
          domain = parts.last;
        } else {
          domain = rest;
        }
      }
      return 'filter_prefs_${cleanUser}_$domain';
    } else {
      if (domainOrKey.startsWith('filter_prefs_')) {
        return domainOrKey;
      }
      return 'filter_prefs_$domainOrKey';
    }
  }

  static bool _isLegacyUser(String? user) {
    if (user == null || user.isEmpty) return true;
    return user == 'admin' || user == 'supervisor';
  }

  Future<SharedPreferences?> _getPrefs() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      try {
        await prefs.reload();
      } catch (_) {}
      _prefs = prefs;
      return prefs;
    } catch (_) {
      // In unmocked tests or MissingPluginException environments
      return _prefs ?? _sharedPrefs;
    }
  }

  /// Persists a filter map for a given screen domain and user.
  Future<bool> saveFilter(
    String domainOrKey,
    Map<String, dynamic> filters, [
    String? user,
  ]) async {
    final effectiveUser = user ?? username;
    final key = resolveKey(domainOrKey, effectiveUser);
    _staticInMemoryFallback[key] = Map<String, dynamic>.from(filters);
    if (_isLegacyUser(effectiveUser)) {
      final legacyKey = resolveKey(domainOrKey, null);
      _staticInMemoryFallback[legacyKey] = Map<String, dynamic>.from(filters);
    }
    try {
      final prefs = await _getPrefs();
      if (prefs != null) {
        await prefs.setString(key, jsonEncode(filters));
        if (_isLegacyUser(effectiveUser)) {
          final legacyKey = resolveKey(domainOrKey, null);
          await prefs.setString(legacyKey, jsonEncode(filters));
        }
        return true;
      }
    } catch (_) {
      // Transparent fallback to in-memory
    }
    return true;
  }

  /// Loads the persisted filter map asynchronously.
  Future<Map<String, dynamic>?> loadFilter(
    String domainOrKey, [
    String? user,
  ]) async {
    final effectiveUser = user ?? username;
    final key = resolveKey(domainOrKey, effectiveUser);
    try {
      final prefs = await _getPrefs();
      if (prefs != null) {
        String? raw = prefs.getString(key);
        if (raw == null && _isLegacyUser(effectiveUser)) {
          final legacyKey = resolveKey(domainOrKey, null);
          raw = prefs.getString(legacyKey);
        }
        if (raw != null && raw.isNotEmpty) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map<String, dynamic>) {
              _staticInMemoryFallback[key] = decoded;
              return decoded;
            } else {
              // Self-heal corrupt non-map value on disk
              await prefs.remove(key);
            }
          } catch (_) {
            // Self-heal corrupt JSON syntax on disk
            await prefs.remove(key);
          }
        }
        return null;
      }
    } catch (_) {
      // Fall through to in-memory fallback
    }
    final fallback = _staticInMemoryFallback[key];
    if (fallback is Map<String, dynamic>) return fallback;
    return null;
  }

  /// Loads the persisted filter map synchronously from memory or loaded SharedPreferences.
  Map<String, dynamic>? loadFilterSync(
    String domainOrKey, [
    String? user,
  ]) {
    final effectiveUser = user ?? username;
    final key = resolveKey(domainOrKey, effectiveUser);
    final prefs = _prefs ?? _sharedPrefs;
    if (prefs != null) {
      try {
        String? raw = prefs.getString(key);
        if (raw == null && _isLegacyUser(effectiveUser)) {
          final legacyKey = resolveKey(domainOrKey, null);
          raw = prefs.getString(legacyKey);
        }
        if (raw != null && raw.isNotEmpty) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map<String, dynamic>) {
              return decoded;
            } else {
              prefs.remove(key);
            }
          } catch (_) {
            prefs.remove(key);
          }
        }
        return null;
      } catch (_) {}
    }
    final fallback = _staticInMemoryFallback[key];
    if (fallback is Map<String, dynamic>) return fallback;
    return null;
  }

  /// Clears persisted filter state for a given screen domain.
  Future<bool> clearFilter(
    String domainOrKey, [
    String? user,
  ]) async {
    final effectiveUser = user ?? username;
    final key = resolveKey(domainOrKey, effectiveUser);
    _staticInMemoryFallback.remove(key);
    if (_isLegacyUser(effectiveUser)) {
      final legacyKey = resolveKey(domainOrKey, null);
      _staticInMemoryFallback.remove(legacyKey);
    }
    try {
      final prefs = await _getPrefs();
      if (prefs != null) {
        await prefs.remove(key);
        if (_isLegacyUser(effectiveUser)) {
          final legacyKey = resolveKey(domainOrKey, null);
          await prefs.remove(legacyKey);
        }
        return true;
      }
    } catch (_) {
      // Fallback
    }
    return true;
  }

  /// Persists the selected store ID for the current user.
  Future<bool> saveSelectedStore(String storeId, [String? user]) async {
    final effectiveUser = (user != null && user.trim().isNotEmpty)
        ? user.trim()
        : (username != null && username!.trim().isNotEmpty
            ? username!.trim()
            : null);
    if (effectiveUser == null || effectiveUser.isEmpty) return false;
    final key = resolveStoreKey(effectiveUser);
    _staticInMemoryFallback[key] = {'storeId': storeId};
    if (effectiveUser == 'admin') {
      _staticInMemoryFallback['selected_store'] = {'storeId': storeId};
    }
    try {
      final prefs = await _getPrefs();
      if (prefs != null) {
        final result = await prefs.setString(key, storeId);
        if (effectiveUser == 'admin') {
          await prefs.setString('selected_store', storeId);
        }
        return result;
      }
    } catch (_) {}
    return true;
  }

  /// Loads the selected store asynchronously.
  Future<String?> loadSelectedStore([String? user]) async {
    final effectiveUser = (user != null && user.trim().isNotEmpty)
        ? user.trim()
        : (username != null && username!.trim().isNotEmpty
            ? username!.trim()
            : null);
    if (effectiveUser == null || effectiveUser.isEmpty) return null;
    final key = resolveStoreKey(effectiveUser);
    try {
      final prefs = await _getPrefs();
      if (prefs != null) {
        var raw = prefs.getString(key);
        if (raw == null && effectiveUser == 'admin') {
          raw = prefs.getString('selected_store');
        }
        if (raw != null && raw.isNotEmpty) {
          _staticInMemoryFallback[key] = {'storeId': raw};
          return raw;
        }
        return null;
      }
    } catch (_) {
      // Fall through to in-memory fallback
    }
    final fallback = _staticInMemoryFallback[key];
    if (fallback is Map && fallback['storeId'] != null) {
      return fallback['storeId'].toString();
    }
    return null;
  }

  /// Loads the selected store synchronously.
  String? loadSelectedStoreSync([String? user]) {
    final effectiveUser = (user != null && user.trim().isNotEmpty)
        ? user.trim()
        : (username != null && username!.trim().isNotEmpty
            ? username!.trim()
            : null);
    if (effectiveUser == null || effectiveUser.isEmpty) return null;
    final key = resolveStoreKey(effectiveUser);
    final prefs = _prefs ?? _sharedPrefs;
    if (prefs != null) {
      try {
        var raw = prefs.getString(key);
        if (raw == null && effectiveUser == 'admin') {
          raw = prefs.getString('selected_store');
        }
        if (raw != null && raw.isNotEmpty) {
          return raw;
        }
        return null;
      } catch (_) {}
    }
    final fallback = _staticInMemoryFallback[key];
    if (fallback is Map && fallback['storeId'] != null) {
      return fallback['storeId'].toString();
    }
    return null;
  }

  /// Clears the persisted selected store.
  Future<bool> clearSelectedStore([String? user]) async {
    final effectiveUser = (user != null && user.trim().isNotEmpty)
        ? user.trim()
        : (username != null && username!.trim().isNotEmpty
            ? username!.trim()
            : null);
    if (effectiveUser == null || effectiveUser.isEmpty) return false;
    final key = resolveStoreKey(effectiveUser);
    _staticInMemoryFallback.remove(key);
    if (effectiveUser == 'admin') {
      _staticInMemoryFallback.remove('selected_store');
    }
    try {
      final prefs = await _getPrefs();
      if (prefs != null) {
        final removed = await prefs.remove(key);
        if (effectiveUser == 'admin') {
          await prefs.remove('selected_store');
        }
        return removed;
      }
    } catch (_) {}
    return true;
  }

  // Aliases for convenience
  Future<bool> saveFilters(
    String domainOrKey,
    Map<String, dynamic> filters, [
    String? user,
  ]) =>
      saveFilter(domainOrKey, filters, user);

  Map<String, dynamic>? getFilters(String domainOrKey, [String? user]) =>
      loadFilterSync(domainOrKey, user);

  Future<bool> clearFilters(String domainOrKey, [String? user]) =>
      clearFilter(domainOrKey, user);

  void clearInMemory([String? user]) {
    try {
      final effectiveUser = user ?? _instanceUsername;
      if (effectiveUser != null && effectiveUser.isNotEmpty) {
        final sanitized = sanitizeUsername(effectiveUser);
        final filterPrefix = 'filter_prefs_${sanitized}_';
        final storeKey = resolveStoreKey(effectiveUser);
        _staticInMemoryFallback.removeWhere(
          (key, _) => key.startsWith(filterPrefix) || key == storeKey,
        );
        if (effectiveUser == 'admin') {
          _staticInMemoryFallback.remove('selected_store');
          _staticInMemoryFallback.remove('filter_prefs_overview');
          _staticInMemoryFallback.remove('filter_prefs_invoices');
          _staticInMemoryFallback.remove('filter_prefs_customers');
          _staticInMemoryFallback.remove('filter_prefs_products');
        }
      } else {
        _staticInMemoryFallback.clear();
      }
    } catch (_) {
      _staticInMemoryFallback.clear();
    }
  }
}

typedef UsernameProviderCallback = String? Function(Ref ref);

/// Optional callback to dynamically resolve the current user's username without circular dependency.
UsernameProviderCallback? filterStorageUsernameResolver;

/// Riverpod provider for [FilterStorageService].
final filterStorageServiceProvider = Provider<FilterStorageService>((ref) {
  final service = FilterStorageService(
    null,
    null,
    () {
      try {
        return filterStorageUsernameResolver?.call(ref);
      } catch (_) {
        return null;
      }
    },
  );
  service._getPrefs();
  ref.onDispose(() {
    FilterStorageService.resetSharedPrefs();
  });
  return service;
});
