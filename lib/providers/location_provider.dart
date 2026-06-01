import 'package:flutter/cupertino.dart';
import 'package:geolocator/geolocator.dart';

import '../models/metro_station.dart';

class LocationProvider extends ChangeNotifier {
  bool _isLoading = true;
  Position? _currentPosition;
  List<MetroStation> _nearbyStations = [];

  bool get isLoading => _isLoading;
  Position? get currentPosition => _currentPosition;
  List<MetroStation> get nearbyStations => _nearbyStations;

  Future<void> getCurrentLocation() async {
    try {
      _isLoading = true;
      notifyListeners();

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _currentPosition = position;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      debugPrint('Error getting location: $e');
    }
  }

  void setNearbyStations(List<MetroStation> stations) {
    _nearbyStations = stations;
    _isLoading = false;
    notifyListeners();
  }
}
