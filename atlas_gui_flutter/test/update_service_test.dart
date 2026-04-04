import 'package:atlas_gui_flutter/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selectReleaseInstallerUrl prefers setup exe over msi assets', () {
    final selected = selectReleaseInstallerUrl([
      {
        'name': 'ATLAS-Backend-1.6.2.msi',
        'browser_download_url': 'https://example.com/atlas.msi',
      },
      {
        'name': 'ATLAS Backend Setup-1.6.2.exe',
        'browser_download_url': 'https://example.com/atlas-setup.exe',
      },
    ]);

    expect(selected, 'https://example.com/atlas-setup.exe');
  });

  test('selectReleaseInstallerUrl falls back to msi when no exe exists', () {
    final selected = selectReleaseInstallerUrl([
      {
        'name': 'ATLAS-Backend-1.6.2.msi',
        'browser_download_url': 'https://example.com/atlas.msi',
      },
    ]);

    expect(selected, 'https://example.com/atlas.msi');
  });
}
