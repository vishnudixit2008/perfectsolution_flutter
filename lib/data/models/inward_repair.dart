import '../../ui/shared/photo_attachment_widget.dart';

class InwardRepair {
  final int jobNo;
  final DateTime date;
  final String name;
  final String? mobileNo;
  final String devices;
  final String? query;
  final String? purchasedFrom;
  final String? notes;
  final String status; // Pre-complete, LAPTOP, Completed, etc.
  final DateTime? completionDate;
  final String? photo;

  InwardRepair({
    required this.jobNo,
    required this.date,
    required this.name,
    this.mobileNo,
    required this.devices,
    this.query,
    this.purchasedFrom,
    this.notes,
    this.status = 'Pre-complete',
    this.completionDate,
    this.photo,
  });

  List<String> get photoList => PhotoAttachmentWidget.parsePhotoUrls(photo);

  factory InwardRepair.fromJson(Map<String, dynamic> json) {
    return InwardRepair(
      jobNo: json['job_no'] is int
          ? json['job_no']
          : int.tryParse(json['job_no']?.toString() ?? '') ?? 0,
      date: json['date'] != null
          ? DateTime.tryParse(json['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      name: json['name'] ?? '',
      mobileNo: json['mobile_no']?.toString(),
      devices: json['devices'] ?? '',
      query: json['query']?.toString(),
      purchasedFrom: json['purchased_from']?.toString(),
      notes: json['notes']?.toString(),
      status: json['status'] ?? 'Pre-complete',
      completionDate: json['completion_date'] != null
          ? DateTime.tryParse(json['completion_date'].toString())
          : null,
      photo: json['photo']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'job_no': jobNo,
      'date': date.toIso8601String(),
      'name': name,
      'mobile_no': mobileNo,
      'devices': devices,
      'query': query,
      'purchased_from': purchasedFrom,
      'notes': notes,
      'status': status,
      'completion_date': completionDate?.toIso8601String(),
      'photo': photo,
    };
  }

  InwardRepair copyWith({
    int? jobNo,
    DateTime? date,
    String? name,
    String? mobileNo,
    String? devices,
    String? query,
    String? purchasedFrom,
    String? notes,
    String? status,
    DateTime? completionDate,
    String? photo,
  }) {
    return InwardRepair(
      jobNo: jobNo ?? this.jobNo,
      date: date ?? this.date,
      name: name ?? this.name,
      mobileNo: mobileNo ?? this.mobileNo,
      devices: devices ?? this.devices,
      query: query ?? this.query,
      purchasedFrom: purchasedFrom ?? this.purchasedFrom,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      completionDate: completionDate ?? this.completionDate,
      photo: photo ?? this.photo,
    );
  }
}
