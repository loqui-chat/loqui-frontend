// Base urls. Override at build time with:
//  flutter run --dart-define=LOQUI_API_BASE=<url_here>
// (android emulator reaches host at 10.0.2.2)
const apiBaseUrl = String.fromEnvironment(
  'LOQUI_API_BASE',
  defaultValue: 'http://localhost:8080',
);

// websocket base derived from api base (http-> ws, https->wss)
final gatewayBaseUrl = apiBaseUrl.replaceFirst(RegExp(r'^http'), 'ws');

class Endpoints {
  static const register = '/register';
  static const login = '/login';
  static const refresh = '/refresh';
  static const logout = '/logout';
  static const me = '/me';
  static const channels = '/channels';
  static String channelMessages(String id) => '/channels/$id/messages';
  static const gateway = '/gateway';
}
