import 'dart:convert';

/// Builds the `Authorization` header used by the server API.
///
/// The HTTP API reuses the MQTT logins (HTTP Basic): apps authenticate as
/// `app`, devices as `device`. No separate API token exists, so an empty
/// password simply means "not configured" and yields no header.
String? basicAuthHeader(String username, String password) {
  if (password.isEmpty) return null;
  final raw = base64Encode(utf8.encode('$username:$password'));
  return 'Basic $raw';
}
