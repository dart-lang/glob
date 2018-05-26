import 'package:glob/glob.dart';

final dartFile = new Glob("**.dart");

void main(List<String> arguments) {

  // Print all command-line arguments that are Dart files.
  for (var argument in arguments) {
    if (dartFile.matches(argument)) print(argument);
  }

  // Recursively list all Dart files in the current directory.
  for (var entity in dartFile.listSync()) {
    print(entity.path);
  }
}
