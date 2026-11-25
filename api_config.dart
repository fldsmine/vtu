class ApiConfig {
  ApiConfig._();

  static const String websiteBaseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://tlstore.org',
  );

  static const String webAppBaseUrl = String.fromEnvironment(
    'WEB_APP_URL',
    defaultValue: 'https://web.tlstore.org',
  );

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://tlstore.org/api/v1/',
  );

  static Uri endpoint(String path) {
    final base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
    return base.resolve(path);
  }

  static bool isAppWebsiteLink(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;

    final configuredHosts = <String>{
      Uri.parse(websiteBaseUrl).host.toLowerCase(),
      Uri.parse(baseUrl).host.toLowerCase(),
      Uri.parse(webAppBaseUrl).host.toLowerCase(),
    }..removeWhere((host) => host.isEmpty);

    return configuredHosts.contains(uri.host.toLowerCase());
  }
}
