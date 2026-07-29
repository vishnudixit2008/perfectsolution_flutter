import '../../ui/shared/photo_attachment_widget.dart';

class CallModel {
  final int id;
  final DateTime date;
  final String name;
  final String? mobileNo;
  final String? address;
  final String? query;
  final String assignedTo;
  final String? estimate;
  final String status;
  final String? notes;
  final String? photo;

  CallModel({
    required this.id,
    required this.date,
    required this.name,
    this.mobileNo,
    this.address,
    this.query,
    required this.assignedTo,
    this.estimate,
    this.status = 'Pending',
    this.notes,
    this.photo,
  });

  List<String> get photoList => PhotoAttachmentWidget.parsePhotoUrls(photo);

  factory CallModel.fromJson(Map<String, dynamic> json) {
    return CallModel(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? '') ?? 0,
      date: json['date'] != null
          ? DateTime.tryParse(json['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      name: json['name'] ?? '',
      mobileNo: json['mobile_no']?.toString(),
      address: json['address']?.toString(),
      query: json['query']?.toString(),
      assignedTo: json['assigned_to'] ?? '',
      estimate: json['estimate']?.toString(),
      status: json['status'] ?? 'Pending',
      notes: json['notes']?.toString(),
      photo: json['photo']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'name': name,
      'mobile_no': mobileNo,
      'address': address,
      'query': query,
      'assigned_to': assignedTo,
      'estimate': estimate,
      'status': status,
      'notes': notes,
      'photo': photo,
    };
  }

  CallModel copyWith({
    int? id,
    DateTime? date,
    String? name,
    String? mobileNo,
    String? address,
    String? query,
    String? assignedTo,
    String? estimate,
    String? status,
    String? notes,
    String? photo,
  }) {
    return CallModel(
      id: id ?? this.id,
      date: date ?? this.date,
      name: name ?? this.name,
      mobileNo: mobileNo ?? this.mobileNo,
      address: address ?? this.address,
      query: query ?? this.query,
      assignedTo: assignedTo ?? this.assignedTo,
      estimate: estimate ?? this.estimate,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      photo: photo ?? this.photo,
    );
  }
}
