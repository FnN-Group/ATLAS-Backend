import 'dart:io';

import 'package:atlas_gui_flutter/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('managed hotfix source files live under DefaultGame Data', () {
    String normalize(String path) => path.replaceAll('\\', '/');

    expect(
      normalize(BackendPaths.curveTableLinesIni),
      endsWith('/static/hotfixes/DefaultGame Data/CurveTables.ini'),
    );
    expect(
      normalize(BackendPaths.dataTableLinesIni),
      endsWith('/static/hotfixes/DefaultGame Data/DataTables.ini'),
    );
    expect(
      normalize(BackendPaths.straightBloomLinesIni),
      endsWith('/static/hotfixes/DefaultGame Data/StraightBloom.ini'),
    );
    expect(
      normalize(BackendPaths.fixesLinesIni),
      endsWith('/static/hotfixes/DefaultGame Data/Fixes.ini'),
    );
  });

  test('removeDuplicateAssetHotfixHeaders keeps only the first header', () {
    const content = '''
[AssetHotfix]
# DataTables
[AssetHotfix]
# CurveTables
''';

    final normalized = removeDuplicateAssetHotfixHeaders(content);

    expect(
      RegExp(
        r'^\[AssetHotfix\]$',
        multiLine: true,
      ).allMatches(normalized).length,
      1,
    );
    expect(normalized.contains('# DataTables'), isTrue);
    expect(normalized.contains('# CurveTables'), isTrue);
  });

  test(
    'mergeIniSourceAdditions preserves existing lines and adds missing source lines',
    () {
      const target = '''
[SectionA]
Existing=1

[SectionB]
Keep=Yes
''';

      const source = '''
[SectionA]
Existing=1
Added=2

[SectionC]
Fresh=True
''';

      final merged = mergeIniSourceAdditions(
        targetContent: target,
        sourceContent: source,
      );

      expect(merged.contains('Existing=1'), isTrue);
      expect(merged.contains('Added=2'), isTrue);
      expect(merged.contains('[SectionC]'), isTrue);
      expect(merged.contains('Fresh=True'), isTrue);
      expect(RegExp(r'Existing=1').allMatches(merged).length, 1);
    },
  );

  test(
    'ManagedHotfixService.mergeLines de-duplicates while preserving order',
    () {
      final merged = ManagedHotfixService.mergeLines(
        const ['A', 'B', 'A'],
        const ['B', 'C'],
      );

      expect(merged, <String>['A', 'B', 'C']);
    },
  );

  test(
    'customGroupImagePathsToDelete only returns orphaned images in custom-groups',
    () {
      final curveMap = <String, dynamic>{
        '1': <String, dynamic>{
          'isCustom': true,
          'groupId': 'group-a',
          'groupImagePath': r'custom-groups\unique-a.png',
        },
        '2': <String, dynamic>{
          'isCustom': true,
          'groupId': 'group-a',
          'groupImagePath': 'custom-groups/shared.png',
        },
        '3': <String, dynamic>{
          'isCustom': true,
          'groupId': 'group-b',
          'groupImagePath': 'custom-groups/shared.png',
        },
        '4': <String, dynamic>{
          'isCustom': true,
          'groupId': 'group-a',
          'groupImagePath': 'not-custom-groups/leave-alone.png',
        },
      };

      final deletions = customGroupImagePathsToDelete(curveMap, 'group-a');

      expect(deletions, <String>['custom-groups/unique-a.png']);
    },
  );

  test('extractManagedHotfixSnapshot recovers lines from malformed block order', () {
    const straightBloomLine =
        '+DataTable=/Game/Athena/Items/Weapons/AthenaRangedWeapons;RowUpdate;Sniper_Test;Spread;0';
    const dataTableLine =
        '+DataTable=/Game/Athena/Items/Weapons/AthenaRangedWeapons;RowUpdate;Shotgun_Test;DamagePB;250';
    const curveTableLine =
        '+CurveTable=/Game/Athena/Balance/DataTables/AthenaGameData;RowUpdate;Default.GliderRedeploy.CanRedeploy;0;1';
    const fixesLine =
        '+DataTable=/Game/Athena/Items/Weapons/AthenaRangedWeapons;RowUpdate;Adventure_Special_HookGun_Athena_SR_Ore_T03;FiringRate;1.0';
    const content =
        '''
[AssetHotfix]
# DataTables
# Straight Bloom
$straightBloomLine
$dataTableLine
# CurveTables
$curveTableLine
# Fixes
$fixesLine
# DataTables
# Straight Bloom
# CurveTables
''';

    final snapshot = extractManagedHotfixSnapshot(
      content: content,
      straightBloomLines: const [straightBloomLine],
    );

    expect(snapshot.dataTableLines, <String>[dataTableLine]);
    expect(snapshot.hasActiveDataTableLines, isTrue);
    expect(snapshot.straightBloomLines, <String>[straightBloomLine]);
    expect(snapshot.curveTableLines, <String>[curveTableLine]);
    expect(snapshot.hasActiveCurveTableLines, isTrue);
    expect(snapshot.hasActiveStraightBloomLines, isTrue);
    expect(snapshot.fixesLines, <String>[fixesLine]);
  });

  test(
    'extractImportedDataTableAndFixLines keeps Straight Bloom and Fixes separate from DataTables',
    () {
      const straightBloomLine =
          '+DataTable=/Game/Athena/Items/Weapons/AthenaRangedWeapons;RowUpdate;Sniper_Test;Spread;0';
      const dataTableLine =
          '+DataTable=/Game/Athena/Items/Weapons/AthenaRangedWeapons;RowUpdate;Shotgun_Test;DamagePB;250';
      const fixesLine =
          '+DataTable=/Game/Athena/Items/Weapons/AthenaRangedWeapons;RowUpdate;Adventure_Special_HookGun_Athena_SR_Ore_T03;FiringRate;1.0';
      const content =
          '''
[AssetHotfix]
# DataTables
$straightBloomLine
$dataTableLine
# Fixes
$fixesLine
''';

      final imported = extractImportedDataTableAndFixLines(
        content: content,
        knownStraightBloomLines: const [straightBloomLine],
      );

      expect(imported.dataTableLines, <String>[dataTableLine]);
      expect(imported.fixesLines, <String>[fixesLine]);
      expect(imported.straightBloomLines, <String>[straightBloomLine]);
      expect(imported.hasActiveStraightBloomLines, isTrue);
    },
  );

  test(
    'extractImportedDataTableAndFixLines filters known fixes and Straight Bloom when markers are missing',
    () {
      const straightBloomLine =
          '+DataTable=/Game/Athena/Items/Weapons/AthenaRangedWeapons;RowUpdate;Sniper_Test;Spread;0';
      const dataTableLine =
          '+DataTable=/Game/Athena/Items/Weapons/AthenaRangedWeapons;RowUpdate;Shotgun_Test;DamagePB;250';
      const fixesLine =
          '+DataTable=/Game/Athena/Items/Weapons/AthenaRangedWeapons;RowUpdate;Adventure_Special_HookGun_Athena_SR_Ore_T03;FiringRate;1.0';
      const content =
          '''
[AssetHotfix]
$straightBloomLine
$dataTableLine
$fixesLine
''';

      final imported = extractImportedDataTableAndFixLines(
        content: content,
        knownFixLines: const [fixesLine],
        knownStraightBloomLines: const [straightBloomLine],
      );

      expect(imported.dataTableLines, <String>[dataTableLine]);
      expect(imported.fixesLines, <String>[fixesLine]);
      expect(imported.straightBloomLines, <String>[straightBloomLine]);
      expect(imported.hasActiveStraightBloomLines, isTrue);
    },
  );

  test(
    'rebuildManagedHotfixContent canonicalizes managed blocks and preserves fixes',
    () {
      const straightBloomLine =
          '+DataTable=/Game/Athena/Items/Weapons/AthenaRangedWeapons;RowUpdate;Sniper_Test;Spread;0';
      const dataTableLine =
          '+DataTable=/Game/Athena/Items/Weapons/AthenaRangedWeapons;RowUpdate;Shotgun_Test;DamagePB;250';
      const curveTableLine =
          '+CurveTable=/Game/Athena/Balance/DataTables/AthenaGameData;RowUpdate;Default.GliderRedeploy.CanRedeploy;0;1';
      const fixesLine =
          '+DataTable=/Game/Athena/Items/Weapons/AthenaRangedWeapons;RowUpdate;Adventure_Special_HookGun_Athena_SR_Ore_T03;FiringRate;1.0';
      const content =
          '''
[/Script/FortniteGame.FortTextHotfixConfig]
Keep=True
[AssetHotfix]
# DataTables
# Straight Bloom
$straightBloomLine
$dataTableLine
# CurveTables
# Fixes
$fixesLine
# DataTables
# Straight Bloom
# CurveTables
''';

      final rebuilt = rebuildManagedHotfixContent(
        content: content,
        dataTableLines: const [dataTableLine],
        dataTablesEnabled: true,
        straightBloomLines: const [straightBloomLine],
        straightBloomEnabled: true,
        curveTableLines: const [curveTableLine],
        curveTablesEnabled: true,
        fixesLines: const [fixesLine],
      );

      expect(
        RegExp(
          r'^\[AssetHotfix\]$',
          multiLine: true,
        ).allMatches(rebuilt).length,
        1,
      );
      expect(
        RegExp(r'^# DataTables$', multiLine: true).allMatches(rebuilt).length,
        1,
      );
      expect(
        RegExp(
          r'^# Straight Bloom$',
          multiLine: true,
        ).allMatches(rebuilt).length,
        1,
      );
      expect(
        RegExp(r'^# CurveTables$', multiLine: true).allMatches(rebuilt).length,
        1,
      );
      expect(
        rebuilt.indexOf('# DataTables') < rebuilt.indexOf('# Straight Bloom'),
        isTrue,
      );
      expect(
        rebuilt.indexOf('# Straight Bloom') < rebuilt.indexOf('# CurveTables'),
        isTrue,
      );
      expect(
        rebuilt.indexOf('# CurveTables') < rebuilt.indexOf('# Fixes'),
        isTrue,
      );
      expect(rebuilt.contains(dataTableLine), isTrue);
      expect(rebuilt.contains(straightBloomLine), isTrue);
      expect(rebuilt.contains(curveTableLine), isTrue);
      expect(rebuilt.contains(fixesLine), isTrue);
    },
  );

  test(
    'rebuildManagedHotfixContent strips straight bloom and fixes from DataTables block',
    () {
      const straightBloomLine =
          '+DataTable=/Game/Athena/Items/Weapons/AthenaRangedWeapons;RowUpdate;Sniper_Test;Spread;0';
      const dataTableLine =
          '+DataTable=/Game/Athena/Items/Weapons/AthenaRangedWeapons;RowUpdate;Shotgun_Test;DamagePB;250';
      const fixesLine =
          '+DataTable=/Game/Athena/Items/Weapons/AthenaRangedWeapons;RowUpdate;Adventure_Special_HookGun_Athena_SR_Ore_T03;FiringRate;1.0';

      final rebuilt = rebuildManagedHotfixContent(
        content: '[AssetHotfix]\n',
        dataTableLines: const [straightBloomLine, dataTableLine, fixesLine],
        dataTablesEnabled: true,
        straightBloomLines: const [straightBloomLine],
        straightBloomEnabled: true,
        curveTableLines: const [],
        curveTablesEnabled: false,
        fixesLines: const [fixesLine],
      );

      final dataTablesBlock = RegExp(
        r'# DataTables\r?\n(?<block>[\s\S]*?)(?:# Straight Bloom|# Fixes|\[|$)',
      ).firstMatch(rebuilt)!.namedGroup('block')!;

      expect(dataTablesBlock.contains(dataTableLine), isTrue);
      expect(dataTablesBlock.contains(straightBloomLine), isFalse);
      expect(dataTablesBlock.contains(fixesLine), isFalse);
      expect(rebuilt.contains('# Straight Bloom\n$straightBloomLine'), isTrue);
      expect(rebuilt.contains('# Fixes\n$fixesLine'), isTrue);
    },
  );

  test('packaged DefaultGame files start with empty managed hotfix blocks', () {
    File resolveRepoFile(List<String> relativeParts) {
      final direct = File(joinPath([Directory.current.path, ...relativeParts]));
      if (direct.existsSync()) return direct;
      return File(joinPath([Directory.current.path, '..', ...relativeParts]));
    }

    final targets = [
      resolveRepoFile(['static', 'hotfixes', 'DefaultGame.ini']),
      resolveRepoFile([
        'static',
        'hotfixes',
        'DefaultGame Template',
        'DefaultGame.ini',
      ]),
      resolveRepoFile([
        'static',
        'hotfixes',
        'DefaultGame Data',
        'CurveTables.ini',
      ]),
      resolveRepoFile([
        'static',
        'hotfixes',
        'DefaultGame Data',
        'DataTables.ini',
      ]),
      resolveRepoFile([
        'static',
        'hotfixes',
        'DefaultGame Data',
        'StraightBloom.ini',
      ]),
      resolveRepoFile(['static', 'hotfixes', 'DefaultGame Data', 'Fixes.ini']),
    ];

    for (final file in targets.take(2)) {
      expect(file.existsSync(), isTrue, reason: 'Missing ${file.path}');
      final content = file.readAsStringSync();
      final snapshot = extractManagedHotfixSnapshot(content: content);

      expect(snapshot.dataTableLines, isEmpty, reason: file.path);
      expect(snapshot.curveTableLines, isEmpty, reason: file.path);
      expect(snapshot.hasActiveDataTableLines, isFalse, reason: file.path);
      expect(snapshot.hasActiveCurveTableLines, isFalse, reason: file.path);
      expect(
        RegExp(
          r'^\[AssetHotfix\]$',
          multiLine: true,
        ).allMatches(content).length,
        1,
        reason: file.path,
      );
      expect(content.contains('# DataTables'), isTrue, reason: file.path);
      expect(content.contains('# Straight Bloom'), isTrue, reason: file.path);
      expect(content.contains('# CurveTables'), isTrue, reason: file.path);
      expect(content.contains('# Fixes'), isTrue, reason: file.path);
    }

    final curveTablesFile = targets[2];
    final dataTablesFile = targets[3];
    final straightBloomFile = targets[4];
    final fixesFile = targets[5];

    expect(
      curveTablesFile.existsSync(),
      isTrue,
      reason: 'Missing ${curveTablesFile.path}',
    );
    expect(
      curveTablesFile.readAsStringSync().trim(),
      isEmpty,
      reason: curveTablesFile.path,
    );

    expect(
      dataTablesFile.existsSync(),
      isTrue,
      reason: 'Missing ${dataTablesFile.path}',
    );
    expect(
      dataTablesFile.readAsStringSync().trim(),
      isEmpty,
      reason: dataTablesFile.path,
    );

    expect(
      straightBloomFile.existsSync(),
      isTrue,
      reason: 'Missing ${straightBloomFile.path}',
    );
    final straightBloomContent = straightBloomFile.readAsStringSync().trim();
    expect(straightBloomContent, isNotEmpty, reason: straightBloomFile.path);
    expect(
      straightBloomContent.contains(
        '+DataTable=/Game/Athena/Items/Weapons/AthenaRangedWeapons;RowUpdate;',
      ),
      isTrue,
      reason: straightBloomFile.path,
    );
    expect(
      straightBloomContent.contains(';Spread;0'),
      isTrue,
      reason: straightBloomFile.path,
    );

    expect(fixesFile.existsSync(), isTrue, reason: 'Missing ${fixesFile.path}');
    final fixesContent = fixesFile.readAsStringSync().trim();
    expect(fixesContent, isNotEmpty, reason: fixesFile.path);
    expect(
      fixesContent.contains(
        '+DataTable=/Game/Athena/Items/Weapons/AthenaRangedWeapons;RowUpdate;Adventure_Special_HookGun_Athena_SR_Ore_T03;FiringRate;1.0',
      ),
      isTrue,
      reason: fixesFile.path,
    );
  });
}
