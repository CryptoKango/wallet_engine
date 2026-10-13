import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_engine/wallet_engine.dart';

void main() {
  group('Bip39WordList.english', () {
    final words = Bip39WordList.english;

    test('exposes the canonical immutable 2,048-word list', () {
      expect(words.languageCode, 'en');
      expect(words.languageName, 'english');
      expect(words.length, Bip39WordList.standardLength);
      expect(words.wordAt(0), 'abandon');
      expect(words.wordAt(2047), 'zoo');
      expect(words.words.toSet(), hasLength(Bip39WordList.standardLength));
      expect(() => words.words.add('wallet'), throwsUnsupportedError);
      expect(() => words.wordAt(2048), throwsRangeError);
    });

    test('provides normalized membership and index lookup', () {
      expect(words.indexOf('abandon'), 0);
      expect(words.indexOf(' ZOO '), 2047);
      expect(words.contains('Ability'), isTrue);
      expect(words.contains('wallet-engine'), isFalse);
      expect(words.indexOf('wallet-engine'), -1);
    });

    test('provides bounded immutable prefix suggestions', () {
      final matches = words.wordsStartingWith(' AB ', limit: 4);

      expect(matches, <String>['abandon', 'ability', 'able', 'about']);
      expect(() => matches.add('above'), throwsUnsupportedError);
      expect(words.wordsStartingWith('z', limit: 0), isEmpty);
      expect(() => words.wordsStartingWith('z', limit: -1), throwsRangeError);
    });
  });
}
