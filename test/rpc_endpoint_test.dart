import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('RpcEndpoint', () {
    test('accepts secure HTTP and Electrum transports', () {
      expect(RpcEndpoint.parse('https://rpc.example.com').uri.scheme, 'https');
      expect(
        RpcEndpoint.parse('tls://electrum.example.com:50002').uri.scheme,
        'tls',
      );
    });

    test('requires explicit opt-in for clear-text transports', () {
      expect(
        () => RpcEndpoint.parse('http://localhost:8545'),
        throwsA(isA<WalletValidationException>()),
      );
      final endpoint = RpcEndpoint.parse(
        'http://localhost:8545',
        allowInsecureTransport: true,
      );
      expect(endpoint.allowInsecureTransport, isTrue);
    });

    test('rejects embedded credentials and sensitive static headers', () {
      for (final url in <String>[
        'https://user:password@rpc.example.com',
        'https://rpc.example.com?api_key=secret',
      ]) {
        expect(
          () => RpcEndpoint.parse(url),
          throwsA(isA<WalletValidationException>()),
        );
      }
      expect(
        () => RpcEndpoint.parse(
          'https://rpc.example.com',
          headers: const <String, String>{'Authorization': 'secret'},
        ),
        throwsA(isA<WalletValidationException>()),
      );
    });

    test('rejects unsupported schemes behind a stable validation error', () {
      expect(
        () => RpcEndpoint.parse('ftp://rpc.example.com'),
        throwsA(
          isA<WalletValidationException>().having(
            (error) => error.publicCode,
            'publicCode',
            WalletErrorCode.validationInvalidArgument,
          ),
        ),
      );
    });
  });
}
