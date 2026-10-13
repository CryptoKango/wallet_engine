import 'dart:io';

Future<void> main() async {
  final file = File('coverage/lcov.info');
  if (!await file.exists()) {
    stderr.writeln(
      'coverage/lcov.info does not exist. Run flutter test --coverage.',
    );
    exitCode = 2;
    return;
  }

  var found = 0;
  var hit = 0;
  for (final line in await file.readAsLines()) {
    if (line.startsWith('LF:')) found += int.parse(line.substring(3));
    if (line.startsWith('LH:')) hit += int.parse(line.substring(3));
  }
  if (found == 0) {
    stderr.writeln('Coverage report contains no executable lines.');
    exitCode = 2;
    return;
  }

  final minimum =
      double.tryParse(Platform.environment['MIN_LINE_COVERAGE'] ?? '') ?? 60;
  final percentage = hit * 100 / found;
  stdout.writeln(
    'Line coverage: ${percentage.toStringAsFixed(2)}% ($hit/$found), '
    'minimum: ${minimum.toStringAsFixed(2)}%',
  );
  if (percentage < minimum) exitCode = 1;
}
