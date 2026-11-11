/// Build-time configuration, supplied with --dart-define.
///
///   flutter run --dart-define=API_BASE_URL=https://api.example.com/api/v1
class Env {
  const Env._();

  /// Defaults to the Android emulator's alias for the development machine.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );
}
