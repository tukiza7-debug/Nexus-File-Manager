/// Audit item 49: Teleport discovery-protocol fuzzing (items 24/25). The
/// parser must accept only well-formed hello datagrams and reject every
/// malformed variant without throwing.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_file_manager/core/services/teleport_service.dart';

void main() {
  group('teleport parseHello fuzzing', () {
    test('accepts valid ANNOUNCE and REPLY', () {
      final a = TeleportService.parseHello(
          'NEXUS_TP_V2|ANNOUNCE|device-1|Laptop|linux');
      expect(a, isNotNull);
      expect(a!.type, 'ANNOUNCE');
      expect(a.peerId, 'device-1');
      expect(a.name, 'Laptop');
      expect(a.platform, 'linux');

      final r = TeleportService.parseHello(
          'NEXUS_TP_V2|REPLY|device-2|Phone|android');
      expect(r, isNotNull);
      expect(r!.type, 'REPLY');
    });

    test('rejects wrong magic and wrong types', () {
      expect(TeleportService.parseHello('HELLO|ANNOUNCE|id|n|os'), isNull);
      expect(TeleportService.parseHello('NEXUS_TP_V2|PING|id|n|os'), isNull);
      expect(
        TeleportService.parseHello('NEXUS_TP_V2|ANNOUNCEMENT|id|n|os'),
        isNull,
      );
    });

    test('rejects short, empty and garbage frames', () {
      expect(TeleportService.parseHello(''), isNull);
      expect(TeleportService.parseHello('|'), isNull);
      expect(TeleportService.parseHello('NEXUS_TP_V2'), isNull);
      expect(TeleportService.parseHello('NEXUS_TP_V2|ANNOUNCE'), isNull);
      expect(TeleportService.parseHello('NEXUS_TP_V2|ANNOUNCE|id'), isNull);
      expect(TeleportService.parseHello('\x00\x01\x02garbage'), isNull);
    });

    test('rejects empty peer ids and empty/undecodable names', () {
      expect(TeleportService.parseHello('NEXUS_TP_V2|ANNOUNCE||n|os'), isNull);
      // A malformed percent-escape cannot decode to a name.
      expect(TeleportService.parseHello('NEXUS_TP_V2|ANNOUNCE|id|%ZZ|os'),
          isNull);
      expect(TeleportService.parseHello('NEXUS_TP_V2|ANNOUNCE|id||os'), isNull);
    });

    test('device names with separators and unicode round-trip', () {
      // "Ada|Lovelace" is wire-escaped so the pipe cannot split fields.
      final escaped = Uri.encodeComponent('Ada|Lovelace');
      final parsed = TeleportService.parseHello(
          'NEXUS_TP_V2|ANNOUNCE|dev-7|$escaped|macos');
      expect(parsed, isNotNull);
      expect(parsed!.name, 'Ada|Lovelace');

      final unicode = Uri.encodeComponent('Lim 中文 通信');
      final p2 = TeleportService.parseHello(
          'NEXUS_TP_V2|ANNOUNCE|dev-8|$unicode|windows');
      expect(p2, isNotNull);
      expect(p2!.name, 'Lim 中文 通信');
    });

    test('random hostile bytes never throw', () {
      final rng = _Lcg(42);
      for (var i = 0; i < 2000; i++) {
        final len = rng.nextInt(80);
        final sb = StringBuffer();
        for (var j = 0; j < len; j++) {
          // Bias towards the wire alphabet so many inputs get past the
          // magic check and stress the rest of the parser.
          const alphabet = 'NEXUS_TP_V2|ARNOUNCECaidlmnoprsutw%0- \x00\xff';
          sb.write(alphabet[rng.nextInt(alphabet.length)]);
        }
        expect(
          () => TeleportService.parseHello(sb.toString()),
          returnsNormally,
          reason: 'input: ${sb.toString()}',
        );
      }
    });
  });
}

/// Deterministic LCG so the fuzz corpus is reproducible across runs.
class _Lcg {
  _Lcg(this._seed);
  int _seed;
  int nextInt(int max) {
    _seed = (_seed * 1103515245 + 12345) & 0x7FFFFFFF;
    return _seed % max;
  }
}
