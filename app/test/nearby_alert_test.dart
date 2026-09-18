import 'package:flutter_test/flutter_test.dart';
import 'package:zenlook/services/nearby_alert.dart';

void main() {
  group('formatDistance', () {
    test('di bawah 1 km memakai meter', () {
      expect(formatDistance(0), '0 m');
      expect(formatDistance(500), '500 m');
      expect(formatDistance(999), '999 m');
    });

    test('1 km ke atas memakai kilometer', () {
      expect(formatDistance(1000), '1.0 km');
      expect(formatDistance(1234), '1.2 km');
    });
  });

  group('clampRadius', () {
    test('di bawah min dibatasi ke min', () {
      expect(clampRadius(50), nearbyRadiusMin);
    });

    test('di atas max dibatasi ke max', () {
      expect(clampRadius(2000), nearbyRadiusMax);
    });

    test('nilai tengah tetap', () {
      expect(clampRadius(500), 500);
      expect(clampRadius(nearbyRadiusDefault), nearbyRadiusDefault);
    });
  });

  group('NearbyAlertInfo.fromFcmData', () {
    const validPayload = <String, dynamic>{
      'type': 'nearby',
      'name': 'Budi',
      'distance_m': '420',
      'latitude': '-6.2',
      'longitude': '106.8',
    };

    test('mengurai payload nearby yang valid', () {
      final info = NearbyAlertInfo.fromFcmData(validPayload);
      expect(info, isNotNull);
      expect(info!.name, 'Budi');
      expect(info.distanceM, 420);
      expect(info.latitude, '-6.2');
      expect(info.longitude, '106.8');
    });

    test('menolak payload tanpa tipe nearby', () {
      final info = NearbyAlertInfo.fromFcmData(const {
        'title': 'Pesan baru',
        'body': 'halo',
      });
      expect(info, isNull);
    });

    test('menolak payload tipe lain', () {
      final info = NearbyAlertInfo.fromFcmData(const {
        'type': 'message',
        'name': 'Budi',
        'distance_m': '420',
      });
      expect(info, isNull);
    });

    test('menolak payload nearby tanpa name/distance valid', () {
      final info = NearbyAlertInfo.fromFcmData(const {
        'type': 'nearby',
        'latitude': '-6.2',
      });
      expect(info, isNull);
    });
  });
}
