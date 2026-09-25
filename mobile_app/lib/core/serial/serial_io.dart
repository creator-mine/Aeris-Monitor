// Platform barrier for serial I/O.
//
// On platforms with `dart:library.io` the real FFI-backed implementation
// (libserialport) is used; elsewhere (e.g. web) a no-op stub is exported so
// the app still compiles and simply reports no ports.
export 'serial_io_stub.dart'
    if (dart.library.io) 'serial_io_native.dart';