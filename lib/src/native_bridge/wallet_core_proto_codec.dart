import 'dart:convert';
import 'dart:typed_data';

/// Minimal, audited protobuf wire codec for the Wallet Core messages used by
/// this package. Schema field numbers are pinned to Wallet Core 4.8.4.
final class WalletCoreProtoWriter {
  final List<int> _bytes = <int>[];

  void uint32(int field, int value) => uint64(field, BigInt.from(value));

  void uint64(int field, BigInt value) {
    if (value.isNegative || value > _maxUint64) {
      throw ArgumentError.value(value, 'value', 'Must fit uint64.');
    }
    _tag(field, 0);
    _varint(value);
  }

  void int64(int field, BigInt value) {
    if (value < _minInt64 || value > _maxInt64) {
      throw ArgumentError.value(value, 'value', 'Must fit int64.');
    }
    _tag(field, 0);
    _varint(value.isNegative ? value + (BigInt.one << 64) : value);
  }

  void bytes(int field, List<int> value) {
    _tag(field, 2);
    _varint(BigInt.from(value.length));
    _bytes.addAll(value);
  }

  void string(int field, String value) => bytes(field, utf8.encode(value));

  void message(int field, WalletCoreProtoWriter value) {
    final encoded = value.takeBytes();
    try {
      bytes(field, encoded);
    } finally {
      encoded.fillRange(0, encoded.length, 0);
    }
  }

  void packedUint64(int field, Iterable<BigInt> values) {
    final packed = WalletCoreProtoWriter();
    for (final value in values) {
      if (value.isNegative || value > _maxUint64) {
        throw ArgumentError.value(value, 'value', 'Must fit uint64.');
      }
      packed._varint(value);
    }
    final encoded = packed.takeBytes();
    try {
      bytes(field, encoded);
    } finally {
      encoded.fillRange(0, encoded.length, 0);
    }
  }

  Uint8List takeBytes() {
    final result = Uint8List.fromList(_bytes);
    _bytes.fillRange(0, _bytes.length, 0);
    _bytes.clear();
    return result;
  }

  void _tag(int field, int wireType) {
    if (field <= 0 || field > 0x1fffffff) {
      throw RangeError.range(field, 1, 0x1fffffff, 'field');
    }
    _varint(BigInt.from((field << 3) | wireType));
  }

  void _varint(BigInt value) {
    var remaining = value;
    do {
      var byte = (remaining & BigInt.from(0x7f)).toInt();
      remaining >>= 7;
      if (remaining != BigInt.zero) byte |= 0x80;
      _bytes.add(byte);
    } while (remaining != BigInt.zero);
  }

  static final BigInt _maxUint64 = (BigInt.one << 64) - BigInt.one;
  static final BigInt _minInt64 = -(BigInt.one << 63);
  static final BigInt _maxInt64 = (BigInt.one << 63) - BigInt.one;
}

final class WalletCoreProtoField {
  const WalletCoreProtoField._(this.number, this.wireType, this.value);

  final int number;
  final int wireType;
  final Object value;

  BigInt get varint => value as BigInt;
  Uint8List get bytes => value as Uint8List;
  String get string => utf8.decode(bytes, allowMalformed: false);
}

final class WalletCoreProtoReader {
  WalletCoreProtoReader(Uint8List bytes) : _bytes = bytes;

  final Uint8List _bytes;
  int _offset = 0;

  Iterable<WalletCoreProtoField> readFields() sync* {
    while (_offset < _bytes.length) {
      final tag = _readVarint();
      final number = (tag >> 3).toInt();
      final wireType = (tag & BigInt.from(7)).toInt();
      if (number <= 0) throw const FormatException('Invalid protobuf tag.');
      switch (wireType) {
        case 0:
          yield WalletCoreProtoField._(number, wireType, _readVarint());
        case 1:
          yield WalletCoreProtoField._(number, wireType, _readFixed(8));
        case 2:
          final length = _readVarint().toInt();
          yield WalletCoreProtoField._(number, wireType, _readFixed(length));
        case 5:
          yield WalletCoreProtoField._(number, wireType, _readFixed(4));
        default:
          throw FormatException('Unsupported protobuf wire type $wireType.');
      }
    }
  }

  BigInt _readVarint() {
    var result = BigInt.zero;
    var shift = 0;
    for (var count = 0; count < 10; count += 1) {
      if (_offset >= _bytes.length) {
        throw const FormatException('Truncated protobuf varint.');
      }
      final byte = _bytes[_offset++];
      result |= BigInt.from(byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) return result;
      shift += 7;
    }
    throw const FormatException('Protobuf varint exceeds 64 bits.');
  }

  Uint8List _readFixed(int length) {
    if (length < 0 || length > _bytes.length - _offset) {
      throw const FormatException('Truncated protobuf field.');
    }
    final result = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return result;
  }
}
