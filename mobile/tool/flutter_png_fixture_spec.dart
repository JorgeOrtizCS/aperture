import 'package:aperture/models/api_models.dart';

// The fresh fixture is selected by title as well as the ID assigned at create.
const flutterPngFixtureTitle = 'Aperture synthetic Flutter acceptance PNG';
const flutterPngFixtureMaxViews = 1;
const flutterPngFixtureArchivedIds = {900010, 900011, 900012};

Set<int> parseArchivedPngIds(String value) {
  final ids = <int>{};
  for (final entry in value.split(',')) {
    final id = int.tryParse(entry.trim());
    if (id == null || id <= 0 || id > 0x7fffffff || !ids.add(id)) {
      throw const ApiException(ApiFailure.configuration);
    }
  }
  return Set.unmodifiable(ids);
}
