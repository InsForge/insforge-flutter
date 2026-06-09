// packages/insforge_core/lib/src/options.dart

/// Verbosity of SDK request/response logging.
enum LogLevel { none, error, info, debug, verbose }

/// Tunable client behavior shared across modules.
class InsforgeOptions {
  const InsforgeOptions({
    this.logLevel = LogLevel.none,
    this.customHeaders = const <String, String>{},
    this.connectTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 60),
  });

  final LogLevel logLevel;
  final Map<String, String> customHeaders;
  final Duration connectTimeout;
  final Duration receiveTimeout;
}
