import 'dart:io';

void main() {
  final files = ['lib/main.dart', 'lib/screens/home_screen.dart'];
  for (var file in files) {
    if (File(file).existsSync()) {
      var content = File(file).readAsStringSync();
      content = content.replaceAll('Colors.blue', 'Colors.green');
      File(file).writeAsStringSync(content);
      print('Replaced Colors.blue to Colors.green in $file');
    }
  }
}
