import 'package:atlas_gui_flutter/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('joinPath uses the host path separator', () {
    expect(joinPath(['ATLAS', 'Backend']), r'ATLAS\Backend');
  });
}
