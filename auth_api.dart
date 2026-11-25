import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class AuthException implements Exception {
  const AuthException(
    this.message, {
    this.unauthorized = false,
    this.accountState,
    this.accountReason,
    this.supportEmail,
  });

  final String message;
  final bool unauthorized;
  final String? accountState;
  final String? accountReason;
  final String? supportEmail;

  @override
  String toString() => message;
}

class AuthResult {
  const AuthResult({
    required this.token,
    required this.user,
    this.challengeToken,
  });

  final String token;
  final Map<String, dynamic> user;
  final String? challengeToken;
  bool get requiresTwoFactor =>
      challengeToken != null && challengeToken!.isNotEmpty;
}

class CountryOption {
  const CountryOption({
    required this.code,
    required this.name,
    this.currency,
    this.dialCode = '',
    this.flag = '🌐',
  });

  final String code;
  final String name;
  final String? currency;
  final String dialCode;
  final String flag;

  factory CountryOption.fromJson(Map<String, dynamic> json) => CountryOption(
    code: (json['code'] as String).toUpperCase(),
    name: json['name'] as String,
    currency: json['default_currency'] as String?,
    dialCode:
        _dialCodeFromJson(json) ??
        _dialCodes[(json['code'] as String).toUpperCase()] ??
        '',
    flag: _flagForCountryCode(json['code'] as String),
  );
}

const _dialCodes = <String, String>{
  'AE': '+971',
  'AU': '+61',
  'BR': '+55',
  'CA': '+1',
  'CN': '+86',
  'GB': '+44',
  'GH': '+233',
  'IN': '+91',
  'JP': '+81',
  'KE': '+254',
  'NG': '+234',
  'NZ': '+64',
  'RW': '+250',
  'SA': '+966',
  'TZ': '+255',
  'UG': '+256',
  'US': '+1',
  'ZA': '+27',
  'ZM': '+260',
};

String? _dialCodeFromJson(Map<String, dynamic> json) {
  for (final key in const [
    'dial_code',
    'dialing_code',
    'calling_code',
    'phone_code',
  ]) {
    final value = json[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value.startsWith('+') ? value : '+$value';
    }
  }
  return null;
}

String _flagForCountryCode(String countryCode) {
  final code = countryCode.trim().toUpperCase();
  if (code.length != 2 ||
      code.codeUnits.any((unit) => unit < 65 || unit > 90)) {
    return '🏳️';
  }
  return String.fromCharCodes(
    code.codeUnits.map((unit) => 0x1F1E6 + unit - 65),
  );
}

class AuthApi {
  AuthApi({http.Client? client, FlutterSecureStorage? storage})
    : _client = client ?? http.Client(),
      _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;
  static const _sessionKey = 'trustlens.auth.session';
  static const _reviewProgressPrefix = 'trustlens.review.progress.v1';
  static const _spotlightsCacheKey = 'trustlens.spotlights.response.v1';
  static const _spotlightsCachedAtKey = 'trustlens.spotlights.cached_at.v1';
  static const _spotlightsCacheDuration = Duration(minutes: 60);
  static const _frontendCacheKey = 'trustlens.frontend.response.v1';
  static const _frontendCachedAtKey = 'trustlens.frontend.cached_at.v1';
  static const _frontendCacheDuration = Duration(minutes: 10);

  static const _countriesCacheKey = 'trustlens.countries.response.v1';
  static const _countriesCachedAtKey = 'trustlens.countries.cached_at.v1';
  static const _countriesCacheDuration = Duration(hours: 24);

  static const _currenciesCacheDuration = Duration(minutes: 1440);
  static const _currenciesCacheKey = 'trustlens.currencies.response.v1';
  static const _currenciesCachedAtKey = 'trustlens.currencies.cached_at.v1';

  static const _legalCacheDuration = Duration(hours: 24);
  static const _faqCacheDuration = Duration(hours: 24);
  Map<String, double>? _usdRates;
  DateTime? _ratesLoadedAt;
  Future<Map<String, dynamic>>? _spotlightsInFlight;
  Future<Map<String, dynamic>>? _frontendInFlight;
  Future<List<CountryOption>>? _countriesInFlight;
  Future<Map<String, dynamic>>? _currenciesInFlight;
  final Map<String, Future<Map<String, dynamic>>> _legalInFlight = {};
  Future<List<Map<String, dynamic>>>? _faqsInFlight;
  String _preferredCurrency = 'USD';

  // VAS catalog and order responses can stay warm while provider data remains
  // stable. Wallet balances are always fetched live because they can change
  // after rewards, admin adjustments, transfers, or payments.
  static const _vasCacheTtl = Duration(hours: 12);
  static const _vasCacheIndexKey = 'trustlens.vas.cache.index.v1';
  final Map<String, _CacheEntry> _vasCache = {};
  Set<String>? _vasCacheIndex;
  String _cachePrincipal = 'anonymous';

  String get preferredCurrency => _preferredCurrency;

  void setPreferredCurrency(String currency) {
    final normalized = currency.trim().toUpperCase();
    if (normalized.isNotEmpty) _preferredCurrency = normalized;
  }

  Future<void> loadExchangeRates(String token) async {
    if (_usdRates != null &&
        _ratesLoadedAt != null &&
        DateTime.now().difference(_ratesLoadedAt!) <
            const Duration(minutes: 30))
      return;
    try {
      final response = await get('exchange-rates?base=USD', token);
      final data = response['data'];
      if (data is List) {
        final rates = <String, double>{'USD': 1};
        for (final row in data.whereType<Map<String, dynamic>>()) {
          final quote = row['quote_currency']?.toString().toUpperCase();
          final rate = double.tryParse(row['rate']?.toString() ?? '');
          if (quote != null && rate != null && rate > 0) rates[quote] = rate;
        }
        _usdRates = rates;
        _ratesLoadedAt = DateTime.now();
      }
    } on AuthException {
      // Currency conversion is optional when rates are temporarily unavailable.
    }
  }

  double? convertMajor(double amount, String from, String to) {
    if (from.toUpperCase() == to.toUpperCase()) return amount;
    final rates = _usdRates;
    if (rates == null) return null;
    final sourceRate = rates[from.toUpperCase()];
    final targetRate = rates[to.toUpperCase()];
    if (sourceRate == null || targetRate == null || sourceRate == 0)
      return null;
    return amount / sourceRate * targetRate;
  }

  Future<AuthResult?> restoreSession() async {
    final saved = await _storage.read(key: _sessionKey);
    if (saved == null) return null;
    try {
      final session = jsonDecode(saved) as Map<String, dynamic>;
      final token = session['token'] as String;
      final profile = session['user'] as Map<String, dynamic>;
      setPreferredCurrency(profile['preferred_currency']?.toString() ?? 'USD');
      _cachePrincipal = _principalFor(profile);
      try {
        final response = await _request('GET', 'me', token: token);
        final user = response['data'];
        if (user is Map<String, dynamic>) {
          final restored = AuthResult(token: token, user: user);
          await _saveSession(restored);
          return restored;
        }
      } on AuthException catch (error) {
        if (error.unauthorized) {
          await clearSession();
          return null;
        }
        // Keep a valid saved session available when the device is temporarily offline.
      }
      final restored = AuthResult(token: token, user: profile);
      _preferredCurrency = (profile['preferred_currency']?.toString() ?? 'USD')
          .toUpperCase();
      return restored;
    } on FormatException {
      await clearSession();
      return null;
    } on TypeError {
      await clearSession();
      return null;
    }
  }

  Future<void> _saveSession(AuthResult result) async {
    setPreferredCurrency(
      result.user['preferred_currency']?.toString() ?? 'USD',
    );
    _cachePrincipal = _principalFor(result.user);
    await _storage.write(
      key: _sessionKey,
      value: jsonEncode({'token': result.token, 'user': result.user}),
    );
  }

  Future<void> clearSession() async {
    _preferredCurrency = 'USD';
    _usdRates = null;
    _ratesLoadedAt = null;
    _cachePrincipal = 'anonymous';
    await _clearVasCache();
    await _storage.delete(key: _sessionKey);
  }

  Future<Map<String, dynamic>?> readReviewProgress({
    required Object userId,
    required Object taskId,
  }) async {
    try {
      final raw = await _storage.read(key: _reviewProgressKey(userId, taskId));
      if (raw == null || raw.isEmpty) return null;
      final value = jsonDecode(raw);
      return value is Map
          ? value.map((key, value) => MapEntry(key.toString(), value))
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveReviewProgress({
    required Object userId,
    required Object taskId,
    required Map<String, dynamic> progress,
  }) async {
    try {
      await _storage.write(
        key: _reviewProgressKey(userId, taskId),
        value: jsonEncode(progress),
      );
    } catch (_) {
      // Continue the review even when secure local storage is unavailable.
    }
  }

  Future<void> clearReviewProgress({
    required Object userId,
    required Object taskId,
  }) async {
    try {
      await _storage.delete(key: _reviewProgressKey(userId, taskId));
    } catch (_) {
      // A stale local draft is harmless after a successful submission.
    }
  }

  String _reviewProgressKey(Object userId, Object taskId) =>
      '$_reviewProgressPrefix.${userId.toString().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.${taskId.toString().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';

  Future<Map<String, dynamic>> requestPasswordReset(String email) =>
      postPublic('auth/forgot-password', {'email': email.trim()});

  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String token,
    required String password,
  }) => postPublic('auth/reset-password', {
    'email': email.trim(),
    'token': token.trim(),
    'password': password,
    'password_confirmation': password,
  });

  Future<List<CountryOption>> countries() {
    final pending = _countriesInFlight;
    if (pending != null) return pending;
    final request = _loadCountries();
    _countriesInFlight = request;
    return request.whenComplete(() {
      if (identical(_countriesInFlight, request)) _countriesInFlight = null;
    });
  }

  Future<List<CountryOption>> _loadCountries() async {
    String? cachedJson;
    String? cachedAtText;
    try {
      cachedJson = await _storage.read(key: _countriesCacheKey);
      cachedAtText = await _storage.read(key: _countriesCachedAtKey);
    } catch (_) {
      // Use the network if persistent storage is unavailable.
    }

    final cachedCountries = _decodeCountries(cachedJson);
    final cachedAt = DateTime.tryParse(cachedAtText ?? '')?.toUtc();
    final cacheAge = cachedAt == null
        ? null
        : DateTime.now().toUtc().difference(cachedAt);
    if (cachedCountries != null &&
        cacheAge != null &&
        !cacheAge.isNegative &&
        cacheAge < _countriesCacheDuration) {
      return cachedCountries;
    }

    try {
      final response = await _request('GET', 'countries');
      final countries = _decodeCountries(jsonEncode(response['data']));
      if (countries == null) return const [];
      try {
        await _storage.write(
          key: _countriesCacheKey,
          value: jsonEncode(response['data']),
        );
        await _storage.write(
          key: _countriesCachedAtKey,
          value: DateTime.now().toUtc().toIso8601String(),
        );
      } catch (_) {
        // Return the fetched list even if it cannot be cached.
      }
      return countries;
    } on AuthException {
      if (cachedCountries != null) return cachedCountries;
      rethrow;
    }
  }

  List<CountryOption>? _decodeCountries(String? json) {
    if (json == null) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(CountryOption.fromJson)
          .toList(growable: false);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<Map<String, dynamic>> legalDocument(String slug) {
    if (slug != 'privacy' && slug != 'terms') {
      throw ArgumentError.value(slug, 'slug', 'Expected privacy or terms.');
    }
    final pending = _legalInFlight[slug];
    if (pending != null) return pending;
    final request = _loadLegalDocument(slug);
    _legalInFlight[slug] = request;
    return request.whenComplete(() {
      if (identical(_legalInFlight[slug], request)) {
        _legalInFlight.remove(slug);
      }
    });
  }

  Future<Map<String, dynamic>> _loadLegalDocument(String slug) async {
    final host = Uri.parse(ApiConfig.baseUrl).host.toLowerCase();
    final cacheKey = 'trustlens.legal.$host.$slug.v1';
    final cachedAtKey = '$cacheKey.cached_at';
    String? cachedJson;
    String? cachedAtText;
    try {
      cachedJson = await _storage.read(key: cacheKey);
      cachedAtText = await _storage.read(key: cachedAtKey);
    } catch (_) {
      // The network remains available if local storage is unavailable.
    }

    Map<String, dynamic>? cached;
    try {
      final value = cachedJson == null ? null : jsonDecode(cachedJson);
      if (value is Map<String, dynamic>) cached = value;
    } on FormatException {
      // Ignore an invalid local entry and fetch a fresh document.
    }
    final cachedAt = DateTime.tryParse(cachedAtText ?? '')?.toUtc();
    final cacheAge = cachedAt == null
        ? null
        : DateTime.now().toUtc().difference(cachedAt);
    if (cached != null &&
        cacheAge != null &&
        !cacheAge.isNegative &&
        cacheAge < _legalCacheDuration) {
      return cached;
    }

    try {
      final response = await _request('GET', 'legal/$slug');
      final document = response['data'];
      if (document is! Map<String, dynamic>) {
        throw const AuthException(
          'The server returned an invalid legal document.',
        );
      }
      try {
        await _storage.write(key: cacheKey, value: jsonEncode(document));
        await _storage.write(
          key: cachedAtKey,
          value: DateTime.now().toUtc().toIso8601String(),
        );
      } catch (_) {
        // Display the response even if it cannot be cached on this device.
      }
      return document;
    } on AuthException {
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> faqs() {
    final pending = _faqsInFlight;
    if (pending != null) return pending;
    final request = _loadFaqs();
    _faqsInFlight = request;
    return request.whenComplete(() {
      if (identical(_faqsInFlight, request)) _faqsInFlight = null;
    });
  }

  Future<List<Map<String, dynamic>>> _loadFaqs() async {
    final host = Uri.parse(ApiConfig.baseUrl).host.toLowerCase();
    final cacheKey = 'trustlens.faqs.$host.v1';
    final cachedAtKey = '$cacheKey.cached_at';
    String? cachedJson;
    String? cachedAtText;
    try {
      cachedJson = await _storage.read(key: cacheKey);
      cachedAtText = await _storage.read(key: cachedAtKey);
    } catch (_) {
      // Use the network if local storage is unavailable.
    }

    final cached = _decodeFaqs(cachedJson);
    final cachedAt = DateTime.tryParse(cachedAtText ?? '')?.toUtc();
    final cacheAge = cachedAt == null
        ? null
        : DateTime.now().toUtc().difference(cachedAt);
    if (cached != null &&
        cacheAge != null &&
        !cacheAge.isNegative &&
        cacheAge < _faqCacheDuration) {
      return cached;
    }

    try {
      final response = await _request('GET', 'faqs');
      final faqs = _decodeFaqs(jsonEncode(response['data']));
      if (faqs == null) {
        throw const AuthException('The server returned an invalid FAQ list.');
      }
      try {
        await _storage.write(key: cacheKey, value: jsonEncode(faqs));
        await _storage.write(
          key: cachedAtKey,
          value: DateTime.now().toUtc().toIso8601String(),
        );
      } catch (_) {
        // Keep the live response usable if persistent caching fails.
      }
      return faqs;
    } on AuthException {
      if (cached != null) return cached;
      rethrow;
    }
  }

  List<Map<String, dynamic>>? _decodeFaqs(String? json) {
    if (json == null) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<Map<String, dynamic>> spotlights() {
    final pending = _spotlightsInFlight;
    if (pending != null) return pending;
    final request = _loadSpotlights();
    _spotlightsInFlight = request;
    return request.whenComplete(() {
      if (identical(_spotlightsInFlight, request)) _spotlightsInFlight = null;
    });
  }

  Future<List<Map<String, dynamic>>> socialHandles(String token) async {
    final response = await get('me/social-handles', token);
    final data = response['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, String>> socialAccounts(String token) async {
    final response = await get('me/social-accounts', token);
    final data = response['data'];
    if (data is! Map) return const {};
    return data.map((key, value) => MapEntry(key.toString(), value.toString()));
  }

  Future<Map<String, dynamic>> setSocialAccount(
    String token,
    String platform,
    String handle,
  ) => put('me/social-accounts/${Uri.encodeComponent(platform)}', token, {
    'handle': handle,
  });

  Future<List<Map<String, dynamic>>> banks(
    String token, {
    required String country,
    String? search,
    String? type,
  }) async {
    final query = <String, String>{'country': country};
    if (search != null && search.trim().isNotEmpty)
      query['search'] = search.trim();
    if (type != null && type.isNotEmpty) query['type'] = type;
    final response = await get(
      'banks?${Uri(queryParameters: query).query}',
      token,
    );
    final data = response['data'];
    return data is List
        ? data
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : const [];
  }

  Future<Map<String, dynamic>> dailyTasks(
    String token,
    String type, {
    String? search,
  }) => get(
    'me/daily-tasks/$type${search == null || search.trim().isEmpty ? '' : '?search=${Uri.encodeQueryComponent(search.trim())}'}',
    token,
  );

  Future<Map<String, dynamic>> claimSocialFollow(String token, int handleId) =>
      post('me/social-handles/$handleId/follow', token, const {});

  Future<Map<String, dynamic>> _loadSpotlights() async {
    String? cachedJson;
    String? cachedAtText;
    try {
      cachedJson = await _storage.read(key: _spotlightsCacheKey);
      cachedAtText = await _storage.read(key: _spotlightsCachedAtKey);
    } catch (_) {
      // The network response remains available if the platform cache fails.
    }
    final cachedAt = DateTime.tryParse(cachedAtText ?? '')?.toUtc();
    final cacheAge = cachedAt == null
        ? null
        : DateTime.now().toUtc().difference(cachedAt);
    if (cachedJson != null &&
        cacheAge != null &&
        !cacheAge.isNegative &&
        cacheAge < _spotlightsCacheDuration) {
      try {
        final decoded = jsonDecode(cachedJson);
        if (decoded is Map<String, dynamic>) return decoded;
      } on FormatException {
        // Discard malformed cache content and load a fresh response.
      }
    }

    final response = await _request('GET', 'spotlights');
    try {
      await _storage.write(
        key: _spotlightsCacheKey,
        value: jsonEncode(response),
      );
      await _storage.write(
        key: _spotlightsCachedAtKey,
        value: DateTime.now().toUtc().toIso8601String(),
      );
    } catch (_) {
      // Return successful content even if it could not be persisted.
    }
    return response;
  }

  Future<Map<String, dynamic>> appCurrencies() {
    final pending = _currenciesInFlight;
    if (pending != null) return pending;
    final request = _loadCurrencies();
    _currenciesInFlight = request;
    return request.whenComplete(() {
      if (identical(_currenciesInFlight, request)) _currenciesInFlight = null;
    });
  }

  Future<Map<String, dynamic>> _loadCurrencies() async {
    String? cachedJson;
    String? cachedAtText;
    try {
      cachedJson = await _storage.read(key: _currenciesCacheKey);
      cachedAtText = await _storage.read(key: _currenciesCachedAtKey);
    } catch (_) {
      // The network response remains available if the platform cache fails.
    }
    final cachedAt = DateTime.tryParse(cachedAtText ?? '')?.toUtc();
    final cacheAge = cachedAt == null
        ? null
        : DateTime.now().toUtc().difference(cachedAt);
    if (cachedJson != null &&
        cacheAge != null &&
        !cacheAge.isNegative &&
        cacheAge < _currenciesCacheDuration) {
      try {
        final decoded = jsonDecode(cachedJson);
        if (decoded is Map<String, dynamic>) return decoded;
      } on FormatException {
        // Discard malformed cache content and load a fresh response.
      }
    }

    final response = await _request('GET', 'currencies');
    try {
      await _storage.write(
        key: _currenciesCacheKey,
        value: jsonEncode(response),
      );
      await _storage.write(
        key: _currenciesCachedAtKey,
        value: DateTime.now().toUtc().toIso8601String(),
      );
    } catch (_) {
      // Return successful content even if it could not be persisted.
    }
    return response;
  }

  Future<Map<String, dynamic>> getPublic(String path) => _request('GET', path);

  Future<Map<String, dynamic>> frontend() {
    final pending = _frontendInFlight;
    if (pending != null) return pending;
    final request = _loadFrontend();
    _frontendInFlight = request;
    return request.whenComplete(() {
      if (identical(_frontendInFlight, request)) _frontendInFlight = null;
    });
  }

  Future<Map<String, dynamic>> _loadFrontend() async {
    String? cachedJson;
    String? cachedAtText;
    try {
      cachedJson = await _storage.read(key: _frontendCacheKey);
      cachedAtText = await _storage.read(key: _frontendCachedAtKey);
    } catch (_) {
      // The network response remains available if storage is unavailable.
    }

    final cachedAt = DateTime.tryParse(cachedAtText ?? '')?.toUtc();
    final cacheAge = cachedAt == null
        ? null
        : DateTime.now().toUtc().difference(cachedAt);
    if (cachedJson != null &&
        cacheAge != null &&
        !cacheAge.isNegative &&
        cacheAge < _frontendCacheDuration) {
      try {
        final decoded = jsonDecode(cachedJson);
        if (decoded is Map<String, dynamic>) return decoded;
      } on FormatException {
        // Discard malformed cache data and fetch a fresh response.
      }
    }

    final response = await getPublic('frontend');
    try {
      await _storage.write(key: _frontendCacheKey, value: jsonEncode(response));
      await _storage.write(
        key: _frontendCachedAtKey,
        value: DateTime.now().toUtc().toIso8601String(),
      );
    } catch (_) {
      // Return the live response even if it could not be cached.
    }
    return response;
  }

  Future<Map<String, dynamic>> about() => getPublic('about');

  Future<Map<String, dynamic>> refreshUser(String token) async {
    final response = await get('me', token);
    final user = response['data'];
    if (user is! Map<String, dynamic>) {
      throw const AuthException(
        'The server returned an invalid account snapshot.',
      );
    }
    await _saveSession(AuthResult(token: token, user: user));
    return user;
  }

  Future<Map<String, dynamic>> purchaseSubscriptionWithFunds({
    required String token,
    required int planId,
    required String idempotencyKey,
  }) => post('subscriptions', token, {
    'subscription_plan_id': planId,
    'idempotency_key': idempotencyKey,
  });

  Future<Map<String, dynamic>> checkoutSubscription({
    required String token,
    required int planId,
    required String gateway,
    required String currency,
    required String idempotencyKey,
  }) => post('subscriptions/checkout', token, {
    'subscription_plan_id': planId,
    'gateway': gateway,
    'currency': currency,
    'idempotency_key': idempotencyKey,
  });

  Future<Map<String, dynamic>> submitSubscriptionQuestionnaire({
    required String token,
    required String groupKey,
    required Map<String, dynamic> answers,
  }) => post('me/subscription-questionnaire', token, {
    'group_key': groupKey,
    'answers': answers,
  });

  Future<Map<String, dynamic>> checkSubscriptionPayment(
    String token,
    Object intentId,
  ) => post('subscriptions/$intentId/check', token, const {});

  Future<Map<String, dynamic>> reviewAddonCheck(String token, Object taskId) =>
      get('review-tasks/$taskId/addon-check', token);

  Future<Map<String, dynamic>> purchasePackageAddonWithFunds({
    required String token,
    required int addonId,
    required String idempotencyKey,
  }) => post('package-addons/$addonId/purchase', token, {
    'idempotency_key': idempotencyKey,
  });

  Future<Map<String, dynamic>> checkoutPackageAddon({
    required String token,
    required int addonId,
    required String gateway,
    required String currency,
    required String idempotencyKey,
  }) => post('package-addons/checkout', token, {
    'package_addon_id': addonId,
    'gateway': gateway,
    'currency': currency,
    'idempotency_key': idempotencyKey,
  });

  Future<Map<String, dynamic>> checkPackageAddonPayment(
    String token,
    Object intentId,
  ) => post('package-addons/$intentId/check', token, const {});

  Future<Map<String, dynamic>> get(String path, String token) =>
      _request('GET', path, token: token);

  /// VAS catalog (services, providers and pricing mode).
  ///
  /// Responses are persisted for an hour, because provider prices do not change
  /// in short intervals. Pass [forceRefresh] for an explicit user refresh.
  Future<Map<String, dynamic>> vasCatalog(
    String token, {
    bool forceRefresh = false,
  }) async {
    final value = await _cachedValue(
      _vasCacheKey('vas.catalog'),
      () => _request('GET', 'vas/catalog', token: token),
      forceRefresh: forceRefresh,
    );
    return _asJsonObject(value);
  }

  Future<Map<String, dynamic>> unreadNotificationCount(String token) =>
      get('notifications/unread-count', token);

  /// Plans for a service/provider pair, cached for an hour per provider.
  Future<Map<String, dynamic>> vasPlans(
    String token, {
    required String service,
    required String serviceId,
    bool forceRefresh = false,
  }) async {
    final value = await _cachedValue(
      _vasCacheKey('vas.plans.$service.$serviceId'),
      () => _request(
        'GET',
        'vas/services/$service/plans?service_id=${Uri.encodeQueryComponent(serviceId)}',
        token: token,
      ),
      forceRefresh: forceRefresh,
    );
    return _asJsonObject(value);
  }

  Future<Map<String, dynamic>> verifyVasRecipient(
    String token,
    Map<String, dynamic> data,
  ) => post('vas/verify', token, data);

  Future<Map<String, dynamic>> purchaseVas(
    String token,
    Map<String, dynamic> data,
  ) async {
    final response = await post('vas/purchases', token, data);
    // A purchase moves the wallet balance and creates an order. Provider prices
    // are unchanged, so the catalog and plan caches remain valid.
    await _clearVasCache(where: _isVasActivityKey);
    return response;
  }

  Future<Map<String, dynamic>> vasOrders(
    String token, {
    int perPage = 20,
    bool forceRefresh = false,
  }) async {
    final value = await _cachedValue(
      _vasCacheKey('vas.orders.$perPage'),
      () => _request('GET', 'me/vas-orders?per_page=$perPage', token: token),
      forceRefresh: forceRefresh,
    );
    return _asJsonObject(value);
  }

  Future<Map<String, dynamic>> checkVasOrder(
    String token,
    Object orderId,
  ) async {
    final response = await post(
      'me/vas-orders/$orderId/check',
      token,
      const {},
    );
    final status = _asJsonObject(response['data'])['status']?.toString();
    if (status != null && status.isNotEmpty && status != 'pending') {
      // A settled order can refund reserved funds, so balances must re-sync.
      await _clearVasCache(where: _isVasActivityKey);
    }
    return response;
  }

  /// Drops every cached VAS response. Call after a wallet top-up, transfer or
  /// any balance change made outside the VAS flow.
  Future<void> invalidateVasCache() => _clearVasCache();

  /// Drops cached wallet balances and order activity, keeping catalog and plan
  /// prices warm. Used after a purchase completes.
  Future<void> invalidateVasActivityCache() =>
      _clearVasCache(where: _isVasActivityKey);

  /// Age of the cached catalog (or another scope), handy for "updated 5m ago".
  Duration? vasCacheAge([String scope = 'vas.catalog']) {
    final entry = _vasCache[_vasCacheKey(scope)];
    if (entry == null) return null;
    return DateTime.now().toUtc().difference(entry.storedAt);
  }

  String _vasCacheKey(String scope) => '$scope::$_cachePrincipal';

  static bool _isVasActivityKey(String storageKey) =>
      storageKey.contains('vas.wallets') || storageKey.contains('vas.orders');

  String _principalFor(Map<String, dynamic>? user) {
    final raw =
        '${user?['id'] ?? user?['user_id'] ?? user?['uuid'] ?? user?['email'] ?? ''}'
            .trim();
    if (raw.isEmpty) return 'anonymous';
    return raw.replaceAll(RegExp(r'[^A-Za-z0-9@._-]'), '_');
  }

  Future<Object?> _cachedValue(
    String key,
    Future<Object?> Function() load, {
    bool forceRefresh = false,
    Duration ttl = _vasCacheTtl,
  }) async {
    var cached = _vasCache[key];
    cached ??= await _readCacheEntry(key);
    if (!forceRefresh && cached != null && cached.isFresh(ttl)) {
      return cached.value;
    }
    try {
      final value = await load();
      final entry = _CacheEntry(value, DateTime.now().toUtc());
      _vasCache[key] = entry;
      await _writeCacheEntry(key, entry);
      return value;
    } on AuthException catch (error) {
      // Serve the last known response when the device is offline, but never
      // mask an expired session.
      if (!error.unauthorized && cached != null) return cached.value;
      rethrow;
    }
  }

  String _cacheStorageKey(String key) {
    final host = Uri.tryParse(ApiConfig.baseUrl)?.host.toLowerCase() ?? 'api';
    final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9@._-]'), '_');
    return 'trustlens.vas.cache.v1.$host.$safe';
  }

  Future<_CacheEntry?> _readCacheEntry(String key) async {
    final storageKey = _cacheStorageKey(key);
    try {
      final storedAtText = await _storage.read(key: '$storageKey.at');
      final storedAt = DateTime.tryParse(storedAtText ?? '')?.toUtc();
      if (storedAt == null) return null;
      final body = await _storage.read(key: storageKey);
      if (body == null || body.isEmpty) return null;
      final entry = _CacheEntry(jsonDecode(body), storedAt);
      _vasCache[key] = entry;
      return entry;
    } catch (_) {
      // Unreadable or unavailable storage behaves like a cache miss.
      return null;
    }
  }

  Future<void> _writeCacheEntry(String key, _CacheEntry entry) async {
    final storageKey = _cacheStorageKey(key);
    try {
      await _storage.write(key: storageKey, value: jsonEncode(entry.value));
      await _storage.write(
        key: '$storageKey.at',
        value: entry.storedAt.toIso8601String(),
      );
      final index = await _cacheIndex();
      if (index.add(storageKey)) await _saveCacheIndex(index);
    } catch (_) {
      // The live response is still returned when caching is unavailable.
    }
  }

  Future<Set<String>> _cacheIndex() async {
    final existing = _vasCacheIndex;
    if (existing != null) return existing;
    final index = <String>{};
    _vasCacheIndex = index;
    try {
      final raw = await _storage.read(key: _vasCacheIndexKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final value in decoded) {
            final text = value?.toString();
            if (text != null && text.isNotEmpty) index.add(text);
          }
        }
      }
    } catch (_) {
      // Start a fresh index when the previous one cannot be read.
    }
    return index;
  }

  Future<void> _saveCacheIndex(Set<String> index) async {
    try {
      await _storage.write(
        key: _vasCacheIndexKey,
        value: jsonEncode(index.toList()),
      );
    } catch (_) {
      // Losing the index only leaves stale keys behind; requests stay correct.
    }
  }

  Future<void> _clearVasCache({bool Function(String storageKey)? where}) async {
    _vasCache.removeWhere((key, _) {
      final storageKey = _cacheStorageKey(key);
      return where == null || where(storageKey);
    });
    final index = await _cacheIndex();
    final dropped = <String>[];
    for (final storageKey in index.toList()) {
      if (where == null || where(storageKey)) {
        index.remove(storageKey);
        dropped.add(storageKey);
      }
    }
    for (final storageKey in dropped) {
      try {
        await _storage.delete(key: storageKey);
        await _storage.delete(key: '$storageKey.at');
      } catch (_) {
        // A locked keychain must not block a purchase or a sign-out.
      }
    }
    if (dropped.isNotEmpty) await _saveCacheIndex(index);
  }

  Future<http.Response> download(String path, String token) async {
    try {
      final response = await http
          .get(
            ApiConfig.endpoint(path),
            headers: {'Accept': '*/*', 'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 45));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      String message = 'Could not download the evidence file.';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['message'] != null) {
          message = body['message'].toString();
        }
      } catch (_) {
        // Keep a safe generic message for non-JSON error bodies.
      }
      throw AuthException(message, unauthorized: response.statusCode == 401);
    } on AuthException {
      rethrow;
    } on TimeoutException {
      throw const AuthException('The evidence download timed out.');
    } on FormatException {
      throw const AuthException('The evidence URL is invalid.');
    } catch (_) {
      throw const AuthException('Could not download the evidence file.');
    }
  }

  Future<Map<String, dynamic>> post(
    String path,
    String token,
    Map<String, dynamic> body,
  ) => _request('POST', path, token: token, body: body);

  Future<Map<String, dynamic>> postPublic(
    String path,
    Map<String, dynamic> body,
  ) => _request('POST', path, body: body);

  Future<Map<String, dynamic>> postMultipart({
    required String path,
    required String token,
    required Map<String, String> fields,
    required String fileField,
    required Uint8List fileBytes,
    required String fileName,
    String method = 'POST',
  }) async {
    try {
      final request = http.MultipartRequest(method, ApiConfig.endpoint(path))
        ..headers['Accept'] = 'application/json'
        ..headers['Authorization'] = 'Bearer $token'
        ..fields.addAll(fields)
        ..files.add(
          http.MultipartFile.fromBytes(
            fileField,
            fileBytes,
            filename: fileName,
          ),
        );
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 15));
      return _decodeResponse(
        await http.Response.fromStream(streamed)
            .timeout(const Duration(seconds: 30)),
      );
    } on http.ClientException {
      throw const AuthException(
        'Could not reach TrustLens. Check your connection and try again.',
      );
    } on TimeoutException {
      throw const AuthException('The upload timed out. Please try again.');
    } on FormatException {
      throw const AuthException('The server returned an unreadable response.');
    }
  }

  Future<Map<String, dynamic>> patch(
    String path,
    String token,
    Map<String, dynamic> body,
  ) => _request('PATCH', path, token: token, body: body);

  Future<Map<String, dynamic>> delete(
    String path,
    String token, {
    Map<String, dynamic>? body,
  }) => _request('DELETE', path, token: token, body: body);

  Future<Map<String, dynamic>> put(
    String path,
    String token,
    Map<String, dynamic> body,
  ) => _request('PUT', path, token: token, body: body);

  Future<Map<String, dynamic>> uploadProfileImage(
    String token,
    String type,
    PlatformFile file,
  ) async {
    final bytes = file.bytes;
    if (bytes == null)
      throw const AuthException('Could not read the selected image.');
    return postMultipart(
      path: 'me/media/$type',
      token: token,
      fields: const {},
      fileField: 'image',
      fileBytes: bytes,
      fileName: file.name,
    );
  }

  Future<Map<String, dynamic>> _decodeResponse(http.Response response) async {
    final responseBody = response.body;
    final decoded = responseBody.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(responseBody);
    if (decoded is! Map<String, dynamic>)
      throw const AuthException('The server returned an invalid response.');
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw AuthException(
        _messageFrom(decoded),
        unauthorized: response.statusCode == 401,
      );
    return decoded;
  }

  /// Wallet balances are financial state and must come from the API on every
  /// read. Do not serve an old cached balance after rewards or admin changes.
  Future<List<Map<String, dynamic>>> wallets(
    String token, {
    bool forceRefresh = false,
  }) async {
    final value = await _request('GET', 'wallets', token: token);
    return _asJsonRows(_asJsonObject(value)['data']);
  }

  Future<Map<String, dynamic>> accountHistory(
    String token, {
    int page = 1,
    int perPage = 5,
    String category = 'all',
    String status = 'all',
    DateTime? fromDate,
    DateTime? toDate,
  }) => _request(
    'GET',
    Uri(
      path: 'me/account-history',
      queryParameters: {
        'page': '$page',
        'per_page': '$perPage',
        'category': category,
        'status': status,
        if (fromDate != null) 'from_date': _dateQuery(fromDate),
        if (toDate != null) 'to_date': _dateQuery(toDate),
      },
    ).toString(),
    token: token,
  );

  String _dateQuery(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<List<Map<String, dynamic>>> walletLedger(
    String token,
    int walletId,
  ) async {
    final response = await walletLedgerPage(token, walletId);
    final data = response['data'];
    final rows = data is Map<String, dynamic> ? data['data'] : data;
    return rows is List
        ? rows.whereType<Map<String, dynamic>>().toList()
        : const [];
  }

  Future<Map<String, dynamic>> walletLedgerPage(
    String token,
    int walletId, {
    int page = 1,
  }) => _request('GET', 'wallets/$walletId/ledger?page=$page', token: token);

  Future<AuthResult> login({
    required String identifier,
    required String password,
  }) async {
    return _authRequest('auth/login', {
      'identifier': identifier.trim(),
      'password': password,
    });
  }

  Future<AuthResult> verifyTwoFactorChallenge({
    required String challengeToken,
    required String code,
  }) async {
    final json = await _request(
      'POST',
      'auth/two-factor/challenge',
      token: challengeToken,
      body: {'code': code.trim()},
    );
    final data = json['data'];
    final token = json['token'];
    if (data is! Map<String, dynamic> || token is! String) {
      throw const AuthException(
        'The server returned an invalid verification response.',
      );
    }
    final result = AuthResult(token: token, user: data);
    await _saveSession(result);
    return result;
  }

  Future<AuthResult> register({
    required String fullName,
    required String username,
    required String email,
    required String password,
    required String countryCode,
    String? phone,
    String? referralCode,
  }) async {
    return _authRequest('auth/register', {
      'full_name': fullName.trim(),
      'username': username.trim(),
      'email': email.trim(),
      'password': password,
      'password_confirmation': password,
      'country_code': countryCode,
      if (referralCode != null && referralCode.trim().isNotEmpty)
        'referral_code': referralCode.trim().toUpperCase(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
    });
  }

  Future<Map<String, dynamic>> socialProviderConfig() =>
      getPublic('auth/social-config');

  Future<AuthResult> socialLogin({
    required String provider,
    required Map<String, dynamic> credentials,
    String? countryCode,
  }) => _authRequest('auth/social/$provider', {
    ...credentials,
    if (countryCode != null) 'country_code': countryCode,
  });

  Future<void> logout(String token) async {
    try {
      await _request('POST', 'auth/logout', token: token);
    } finally {
      await clearSession();
    }
  }

  Future<AuthResult> _authRequest(
    String path,
    Map<String, dynamic> body,
  ) async {
    final json = await _request('POST', path, body: body);
    if (json['two_factor_required'] == true) {
      final challengeToken = json['challenge_token'];
      if (challengeToken is! String || challengeToken.isEmpty) {
        throw const AuthException(
          'The server did not return an authenticator challenge.',
        );
      }
      await clearSession();
      return AuthResult(
        token: '',
        user: const {},
        challengeToken: challengeToken,
      );
    }
    final data = json['data'];
    final token = json['token'];
    if (data is! Map<String, dynamic> || token is! String) {
      throw const AuthException(
        'The server returned an unexpected sign-in response.',
      );
    }
    final result = AuthResult(token: token, user: data);
    await _saveSession(result);
    return result;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    try {
      final request = http.Request(method, ApiConfig.endpoint(path))
        ..headers['Accept'] = 'application/json'
        ..headers['Content-Type'] = 'application/json';
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      if (body != null) request.body = jsonEncode(body);

      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 20));
      final responseBody = response.body;
      final decoded = responseBody.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) {
        throw const AuthException('The server returned an invalid response.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AuthException(
          _messageFrom(decoded),
          unauthorized: response.statusCode == 401,
          accountState: decoded['account_state']?.toString(),
          accountReason: decoded['account_reason']?.toString(),
          supportEmail: decoded['support_email']?.toString(),
        );
      }
      return decoded;
    } on http.ClientException {
      throw const AuthException(
        'Could not reach TrustLens. Check your connection and try again.',
      );
    } on TimeoutException {
      throw const AuthException('The request timed out. Please try again.');
    } on FormatException {
      throw const AuthException('The server returned an unreadable response.');
    }
  }

  String _messageFrom(Map<String, dynamic> json) {
    final errors = json['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
    }
    return json['message']?.toString() ??
        'Something went wrong. Please try again.';
  }
}

Map<String, dynamic> _asJsonObject(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<Map<String, dynamic>> _asJsonRows(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false)
    : const <Map<String, dynamic>>[];

class _CacheEntry {
  const _CacheEntry(this.value, this.storedAt);

  final Object? value;
  final DateTime storedAt;

  bool isFresh(Duration ttl) {
    final age = DateTime.now().toUtc().difference(storedAt);
    return !age.isNegative && age < ttl;
  }
}
