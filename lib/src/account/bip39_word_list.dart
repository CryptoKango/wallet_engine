import 'package:blockchain_utils/blockchain_utils.dart' show Bip39Languages;

/// An immutable BIP-39 word list exposed by wallet_engine.
///
/// Use [english] for the canonical 2,048-word English list. Lookup helpers
/// trim whitespace and ignore ASCII letter case, while every returned word is
/// the canonical lowercase spelling.
final class Bip39WordList {
  Bip39WordList._({
    required this.languageCode,
    required this.languageName,
    required List<String> source,
  }) : words = List<String>.unmodifiable(source),
       _indexes = Map<String, int>.unmodifiable(<String, int>{
         for (var index = 0; index < source.length; index++)
           source[index]: index,
       }) {
    if (words.length != standardLength || _indexes.length != standardLength) {
      throw StateError('The BIP-39 word list must contain 2,048 unique words.');
    }
  }

  /// Canonical BIP-39 English word list.
  static final Bip39WordList english = Bip39WordList._(
    languageCode: 'en',
    languageName: 'english',
    source: Bip39Languages.english.wordList,
  );

  /// Number of words required by every BIP-39 language list.
  static const int standardLength = 2048;

  /// BCP-47-compatible language code.
  final String languageCode;

  /// Stable lowercase language name.
  final String languageName;

  /// Canonical ordered words. The list cannot be mutated by callers.
  final List<String> words;

  final Map<String, int> _indexes;

  int get length => words.length;

  /// Returns the canonical word at the BIP-39 [index].
  ///
  /// Throws [RangeError] when [index] is outside `0..2047`.
  String wordAt(int index) => words[index];

  /// Returns the BIP-39 index for [word], or `-1` when it is not present.
  int indexOf(String word) => _indexes[_normalize(word)] ?? -1;

  /// Whether [word] belongs to this list.
  bool contains(String word) => indexOf(word) >= 0;

  /// Returns up to [limit] canonical words starting with [prefix].
  ///
  /// An empty prefix returns the first [limit] words. The returned list is
  /// immutable. This helper is suitable for local autocomplete and performs
  /// no network or storage access.
  List<String> wordsStartingWith(String prefix, {int limit = 20}) {
    if (limit < 0) {
      throw RangeError.value(limit, 'limit', 'Must not be negative.');
    }
    if (limit == 0) return const <String>[];

    final normalizedPrefix = _normalize(prefix);
    final matches = <String>[];
    for (final word in words) {
      if (!word.startsWith(normalizedPrefix)) continue;
      matches.add(word);
      if (matches.length == limit) break;
    }
    return List<String>.unmodifiable(matches);
  }

  static String _normalize(String value) => value.trim().toLowerCase();
}
