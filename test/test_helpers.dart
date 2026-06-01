import 'package:geolocator/geolocator.dart';
import 'package:metrosafar/models/metro_station.dart';
import 'package:metrosafar/services/backend_service.dart';
import 'package:metrosafar/services/location_service.dart';

class FakeBackendService extends BackendService {
  @override
  Future<List<MetroStation>> getStations({String? cityId}) async {
    return [
      MetroStation(
        id: '1',
        name: 'Miyapur',
        line: 'Red Line',
        distance: 0,
        latitude: 17.4969,
        longitude: 78.3951,
      ),
      MetroStation(
        id: '11',
        name: 'Ameerpet',
        line: 'Red & Blue Line',
        distance: 0,
        latitude: 17.4337,
        longitude: 78.4464,
      ),
    ];
  }
}

class FakeLocationService extends LocationService {
  @override
  Future<Position> getCurrentLocation() async {
    return Position(
      latitude: 17.4969,
      longitude: 78.3951,
      timestamp: DateTime.now(),
      accuracy: 1,
      altitude: 0,
      altitudeAccuracy: 1,
      heading: 0,
      headingAccuracy: 1,
      speed: 0,
      speedAccuracy: 1,
    );
  }
}
