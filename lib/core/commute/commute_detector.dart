import 'dart:async';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../models/metro_station.dart';
import 'commute_session.dart';

class CommuteDetector {
  final _signals = StreamController<CommuteSignal>.broadcast();
  final _magnitudes = <double>[];
  StreamSubscription<AccelerometerEvent>? _accelerometerSub;
  DateTime _lastLocationSample = DateTime.fromMillisecondsSinceEpoch(0);
  Position? _lastPosition;

  Stream<CommuteSignal> get signals => _signals.stream;

  void start({required List<MetroStation> stations}) {
    if (_accelerometerSub != null) return;
    _accelerometerSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.normalInterval,
    ).listen((event) {
      final magnitude = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      _magnitudes.add(magnitude);
      if (_magnitudes.length > 50) _magnitudes.removeAt(0);
      if (_magnitudes.length < 20) return;

      final vibrationScore = _scoreVibration(_magnitudes);
      if (vibrationScore < 0.45) return;
      _sampleLocation(stations, vibrationScore);
    });
  }

  Future<void> _sampleLocation(
    List<MetroStation> stations,
    double vibrationScore,
  ) async {
    final now = DateTime.now();
    if (now.difference(_lastLocationSample).inSeconds < 20) return;
    _lastLocationSample = now;

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _signals.add(
          CommuteSignal(
            confidenceScore: vibrationScore * 0.45,
            vibrationScore: vibrationScore,
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      ).timeout(const Duration(seconds: 6));
      final speedKmh = _speedKmh(position);
      final station = _nearestStation(position, stations);
      final nearStation = station != null;
      final metroSpeed = speedKmh >= 30 && speedKmh <= 80;
      final confidence =
          (vibrationScore * 0.45) +
          (metroSpeed ? 0.35 : 0) +
          (nearStation ? 0.25 : 0);
      _signals.add(
        CommuteSignal(
          confidenceScore: confidence.clamp(0, 1),
          vibrationScore: vibrationScore,
          speedKmh: speedKmh,
          station: station,
        ),
      );
      _lastPosition = position;
    } catch (_) {
      _signals.add(
        CommuteSignal(
          confidenceScore: vibrationScore * 0.45,
          vibrationScore: vibrationScore,
        ),
      );
    }
  }

  double _scoreVibration(List<double> values) {
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values
            .map((value) => pow(value - mean, 2))
            .reduce((a, b) => a + b)
            .toDouble() /
        values.length;
    final deviation = sqrt(variance);
    return ((deviation - 0.08) / 0.9).clamp(0, 1);
  }

  double _speedKmh(Position position) {
    final reported = position.speed.isFinite ? position.speed * 3.6 : 0.0;
    if (reported > 0) return reported;
    final previous = _lastPosition;
    if (previous == null) return 0;
    final distance = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      position.latitude,
      position.longitude,
    );
    final seconds = position.timestamp.difference(previous.timestamp).inSeconds;
    if (seconds <= 0) return 0;
    return (distance / seconds) * 3.6;
  }

  MetroStation? _nearestStation(
    Position position,
    List<MetroStation> stations,
  ) {
    MetroStation? nearest;
    var nearestMeters = double.infinity;
    for (final station in stations) {
      final meters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        station.latitude,
        station.longitude,
      );
      if (meters < nearestMeters) {
        nearest = station;
        nearestMeters = meters;
      }
    }
    return nearestMeters <= 200 ? nearest : null;
  }

  void dispose() {
    _accelerometerSub?.cancel();
    _accelerometerSub = null;
    _signals.close();
  }
}
