import 'package:latlong2/latlong.dart';

/// Data untuk satu teman di peta (nama, avatar, posisi, status, update time).
class FriendData {
  FriendData({required this.name});

  final String name;
  String? avatar;
  LatLng? position;
  String status = 'offline';
  DateTime? updatedAt;
}
