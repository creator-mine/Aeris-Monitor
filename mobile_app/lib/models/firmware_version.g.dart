// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'firmware_version.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FirmwareVersionAdapter extends TypeAdapter<FirmwareVersion> {
  @override
  final int typeId = 10;

  @override
  FirmwareVersion read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FirmwareVersion(
      id: fields[0] as String,
      version: fields[1] as String,
      deviceType: fields[2] as String,
      sourcePath: fields[3] as String,
      buildDate: fields[4] as DateTime,
      buildHash: fields[5] as String?,
      isBuilt: fields[6] as bool,
      firmwarePath: fields[7] as String?,
      lastUploadPort: fields[8] as String?,
      lastUploadDate: fields[9] as DateTime?,
      configSnapshot: (fields[10] as Map?)?.cast<String, dynamic>(),
      fileHashes: (fields[11] as Map?)?.cast<String, String>(),
    );
  }

  @override
  void write(BinaryWriter writer, FirmwareVersion obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.version)
      ..writeByte(2)
      ..write(obj.deviceType)
      ..writeByte(3)
      ..write(obj.sourcePath)
      ..writeByte(4)
      ..write(obj.buildDate)
      ..writeByte(5)
      ..write(obj.buildHash)
      ..writeByte(6)
      ..write(obj.isBuilt)
      ..writeByte(7)
      ..write(obj.firmwarePath)
      ..writeByte(8)
      ..write(obj.lastUploadPort)
      ..writeByte(9)
      ..write(obj.lastUploadDate)
      ..writeByte(10)
      ..write(obj.configSnapshot)
      ..writeByte(11)
      ..write(obj.fileHashes);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FirmwareVersionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
