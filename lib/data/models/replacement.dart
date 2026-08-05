import '../../ui/shared/photo_attachment_widget.dart';

class Replacement {
  final String jobNo; // Alphanumeric with 'Z' prefix (e.g. Z222)
  final DateTime date;
  final String name;
  final String? mobileNo;
  final String item;
  final String? assignedTo;
  final DateTime? depositDate;
  final DateTime? receiveDate;
  final String status; // Pending, Recieved, Pre-Complete, Complete
  final String? photo;
  final DateTime updatedAt;

  Replacement({
    required this.jobNo,
    required this.date,
    required this.name,
    this.mobileNo,
    required this.item,
    this.assignedTo,
    this.depositDate,
    this.receiveDate,
    this.status = 'Pending',
    this.photo,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  List<String> get photoList => PhotoAttachmentWidget.parsePhotoUrls(photo);

  factory Replacement.fromJson(Map<String, dynamic> json) {
    return Replacement(
      jobNo: json['job_no']?.toString() ?? '',
      date: json['date'] != null
          ? DateTime.tryParse(json['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      name: json['name'] ?? '',
      mobileNo: json['mobile_no']?.toString(),
      item: json['item'] ?? '',
      assignedTo: json['assigned_to']?.toString(),
      depositDate: json['deposit_date'] != null
          ? DateTime.tryParse(json['deposit_date'].toString())
          : null,
      receiveDate: json['receive_date'] != null
          ? DateTime.tryParse(json['receive_date'].toString())
          : null,
      status: json['status'] ?? 'Pending',
      photo: json['photo']?.toString(),
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now() : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'job_no': jobNo,
      'date': date.toIso8601String(),
      'name': name,
      'mobile_no': mobileNo,
      'item': item,
      'assigned_to': assignedTo,
      'deposit_date': depositDate?.toIso8601String(),
      'receive_date': receiveDate?.toIso8601String(),
      'status': status,
      'photo': photo,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Replacement copyWith({
    String? jobNo,
    DateTime? date,
    String? name,
    String? mobileNo,
    String? item,
    String? assignedTo,
    DateTime? depositDate,
    DateTime? receiveDate,
    String? status,
    String? photo,
    DateTime? updatedAt,
  }) {
    return Replacement(
      jobNo: jobNo ?? this.jobNo,
      date: date ?? this.date,
      name: name ?? this.name,
      mobileNo: mobileNo ?? this.mobileNo,
      item: item ?? this.item,
      assignedTo: assignedTo ?? this.assignedTo,
      depositDate: depositDate ?? this.depositDate,
      receiveDate: receiveDate ?? this.receiveDate,
      status: status ?? this.status,
      photo: photo ?? this.photo,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
