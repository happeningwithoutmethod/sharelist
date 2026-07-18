import 'package:shared_models/shared_models.dart';

abstract class MusicProvider {
  String get providerId;

  Future<List<Track>> search(String query);
}
