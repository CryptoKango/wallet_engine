import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('WalletLogger', () {
    test('filters by minimum level and emits JSON-compatible events', () {
      final events = <WalletLogEvent>[];
      final logger = WalletLogger(
        sink: events.add,
        minimumLevel: WalletLogLevel.warning,
        clock: () => DateTime.utc(2026, 10, 13, 12),
      );

      logger.log(
        level: WalletLogLevel.info,
        category: WalletLogCategory.lifecycle,
        operation: 'ignored',
        message: 'ignored',
      );
      logger.log(
        level: WalletLogLevel.warning,
        category: WalletLogCategory.rpc,
        operation: 'rpc.failure',
        message: 'RPC request failed.',
        chainKey: 'ethereum',
        duration: const Duration(milliseconds: 12),
      );

      expect(events, hasLength(1));
      expect(events.single.toDiagnosticMap(), <String, Object?>{
        'timestamp': '2026-10-13T12:00:00.000Z',
        'level': 'warning',
        'category': 'rpc',
        'operation': 'rpc.failure',
        'message': 'RPC request failed.',
        'chainKey': 'ethereum',
        'durationMs': 12,
      });
    });

    test('redacts sensitive context recursively', () {
      final events = <WalletLogEvent>[];
      final logger = WalletLogger(
        sink: events.add,
        minimumLevel: WalletLogLevel.debug,
      );

      logger.log(
        level: WalletLogLevel.error,
        category: WalletLogCategory.signing,
        operation: 'sign',
        message: 'Signing failed.',
        context: <String, Object?>{
          'privateKey': 'deadbeef',
          'nested': <String, Object?>{
            'mnemonic': 'never expose this phrase',
            'coinType': 60,
          },
        },
      );

      expect(events.single.context['privateKey'], '<redacted>');
      expect(events.single.context['nested'], <String, Object?>{
        'mnemonic': '<redacted>',
        'coinType': 60,
      });
      expect(events.single.toString(), isNot(contains('deadbeef')));
      expect(events.single.toString(), isNot(contains('never expose')));
    });

    test('never lets a host sink failure alter SDK execution', () {
      final logger = WalletLogger(
        sink: (_) => throw StateError('host logger failed'),
      );

      expect(
        () => logger.log(
          level: WalletLogLevel.error,
          category: WalletLogCategory.lifecycle,
          operation: 'test',
          message: 'Test event.',
        ),
        returnsNormally,
      );
    });

    test('maps legacy RPC events into the common stream', () {
      final events = <WalletLogEvent>[];
      final logger = WalletLogger(
        sink: events.add,
        minimumLevel: WalletLogLevel.debug,
      );

      logger.recordRpc(
        const RpcLogEvent(
          type: RpcLogEventType.success,
          chainKey: 'solana',
          operation: 'getBalance',
          endpointHost: 'rpc.example.com',
          attempt: 1,
          endpointCount: 2,
          duration: Duration(milliseconds: 8),
        ),
      );

      expect(events.single.category, WalletLogCategory.rpc);
      expect(events.single.operation, 'rpc.success');
      expect(events.single.context['rpcOperation'], 'getBalance');
      expect(events.single.context['endpointHost'], 'rpc.example.com');
    });
  });
}
