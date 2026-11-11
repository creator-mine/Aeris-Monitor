// Platform barrier for the background monitor.
//
// On platforms with dart:io (Android, desktop) the real implementation is
// used; on web a no-op stub keeps the app compiling.
export 'background_service_stub.dart'
    if (dart.library.io) 'background_service_native.dart';
