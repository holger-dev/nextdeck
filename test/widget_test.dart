import 'package:flutter_test/flutter_test.dart';
import 'package:nextdeck/version.dart';

void main() {
  test('app version is 1.8', () {
    expect(kAppVersion, '1.8.0+8');
  });
}
