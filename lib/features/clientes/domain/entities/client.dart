import 'package:equatable/equatable.dart';

class Client extends Equatable {
  const Client({
    required this.id,
    required this.fullName,
    required this.address,
    required this.createdAt,
    required this.updatedAt,
    this.phones = const [],
    this.dpi,
    this.dpiFolder,
    this.alias,
    this.photoPath,
    this.latitude,
    this.longitude,
    this.activeCardsCount = 0,
  });

  final String id;
  final String fullName;
  final String address;
  final List<String> phones;
  final String? dpi;
  final String? dpiFolder;
  final String? alias;
  final String? photoPath;
  final double? latitude;
  final double? longitude;
  final int activeCardsCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  String? get primaryPhone => phones.isEmpty ? null : phones.first;

  Client copyWith({
    String? fullName,
    String? address,
    List<String>? phones,
    String? dpi,
    String? dpiFolder,
    String? alias,
    String? photoPath,
    bool clearPhotoPath = false,
    double? latitude,
    double? longitude,
    bool clearLocation = false,
    int? activeCardsCount,
    DateTime? updatedAt,
  }) {
    return Client(
      id: id,
      fullName: fullName ?? this.fullName,
      address: address ?? this.address,
      phones: phones ?? this.phones,
      dpi: dpi ?? this.dpi,
      dpiFolder: dpiFolder ?? this.dpiFolder,
      alias: alias ?? this.alias,
      photoPath: clearPhotoPath ? null : photoPath ?? this.photoPath,
      latitude: clearLocation ? null : latitude ?? this.latitude,
      longitude: clearLocation ? null : longitude ?? this.longitude,
      activeCardsCount: activeCardsCount ?? this.activeCardsCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    fullName,
    address,
    phones,
    dpi,
    dpiFolder,
    alias,
    photoPath,
    latitude,
    longitude,
    activeCardsCount,
    createdAt,
    updatedAt,
  ];
}
