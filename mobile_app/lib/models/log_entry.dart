import 'package:equatable/equatable.dart';

class LogEntry extends Equatable {
  final int ts;
  final String tag;
  final String msg;

  const LogEntry({
    required this.ts,
    required this.tag,
    required this.msg,
  });

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      ts: (json['ts'] as num?)?.toInt() ?? 0,
      tag: (json['tag'] as String?) ?? '',
      msg: (json['msg'] as String?) ?? '',
    );
  }

  @override
  List<Object?> get props => [ts, tag, msg];
}