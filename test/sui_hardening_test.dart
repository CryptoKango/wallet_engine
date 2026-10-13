import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('Sui hardening', () {
    test('computes a deterministic local digest', () {
      final txBytes = base64Encode(<int>[1, 2, 3, 4]);

      final first = SuiChainSession.digestFromTxBytes(txBytes);
      final second = SuiChainSession.digestFromTxBytes(txBytes);

      expect(first, isNotEmpty);
      expect(second, first);
    });

    test('rejects malformed transaction bytes', () {
      expect(
        () => SuiChainSession.digestFromTxBytes('not-base64!'),
        throwsA(
          isA<WalletValidationException>().having(
            (error) => error.context['field'],
            'field',
            'txBytes',
          ),
        ),
      );
    });

    test('maps object conflicts to a stable public code', () {
      final error = SuiRpcException.fromNode(
        -32000,
        'Object version mismatch caused a ConflictingTransaction',
        false,
        const <String, Object?>{'rpcCode': -32000},
      );

      expect(error.publicCode, WalletErrorCode.chainSuiObjectVersionConflict);
      expect(error.retryable, isFalse);
    });

    test('recognizes transaction-not-found without exposing the node body', () {
      final error = SuiRpcException.fromNode(
        -32000,
        'Could not find the referenced transaction secret-digest',
        false,
        const <String, Object?>{'rpcCode': -32000},
      );

      expect(error.transactionNotFound, isTrue);
      expect(error.toString(), isNot(contains('secret-digest')));
    });
  });
}
