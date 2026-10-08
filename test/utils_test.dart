import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_file_manager/core/utils/fuzzy.dart';
import 'package:nexus_file_manager/core/utils/path_utils.dart' as pu;

void main() {
  group('path utils', () {
    test('basename/dirname behave on posix and windows paths', () {
      expect(pu.basename('/home/user/report.pdf'), 'report.pdf');
      expect(pu.basename(r'C:\Users\me\file.txt'), 'file.txt');
      expect(pu.dirname('/home/user/report.pdf'), '/home/user');
      expect(pu.dirname(r'C:\Users\me\file.txt'), r'C:\Users\me');
    });

    test('extension and stem', () {
      expect(pu.ext('archive.tar.gz'), 'gz');
      expect(pu.stem('archive.tar.gz'), 'archive.tar');
      expect(pu.ext('noext'), '');
    });

    test('withCounter produces collision-free names', () {
      expect(pu.withCounter('/a/file.txt', 2), '/a/file (2).txt');
      expect(pu.withCounter('/a/file.txt', 1), '/a/file.txt');
      expect(pu.withCounter('/a/README', 3), '/a/README (3)');
    });

    test('isUnder and naturalKey', () {
      expect(pu.isUnder('/a/b/c', '/a/b'), isTrue);
      expect(pu.isUnder('/a/b', '/a/b/c'), isFalse);
      final names = ['file10', 'file2', 'File1']..sort((a, b) => pu.naturalKey(a).compareTo(pu.naturalKey(b)));
      expect(names.first, 'File1');
      expect(names.last, 'file10');
    });
  });

  group('fuzzy matcher', () {
    test('subsequence matches and ranks prefixes higher', () {
      final a = fuzzyScore('nfm', 'nexus file manager')!;
      final b = fuzzyScore('nfm', 'not for me')!;
      expect(a, isNotNull);
      expect(b.score, greaterThan(a.score));
      expect(fuzzyScore('xyz', 'nexus'), isNull);
    });

    test('fuzzyBest picks the strongest field', () {
      expect(fuzzyBest('read', ['ignore.me', 'README.md']), greaterThan(0));
    });
  });
}
