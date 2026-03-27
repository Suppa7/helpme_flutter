import 'schedule.dart';

class Medication {
  String? medId;
  String scheduleId;
  String userId;
  String medName;
  num amount;
  String unit;
  String? imageUrl;
  int notificationId;
  List<String> days;
  String? additionalInfo;

  // สำหรับใช้ใน UI เพื่อจับคู่กับเวลา (ไม่ถูกเซฟลง Firestore ฐานข้อมูลนี้)
  ScheduleModel? schedule;

  Medication({
    this.medId,
    required this.scheduleId,
    required this.userId,
    required this.medName,
    required this.amount,
    required this.unit,
    this.imageUrl,
    required this.notificationId,
    this.days = const ['Everyday'],
    this.additionalInfo,
    this.schedule,
  });

  Map<String, dynamic> toMap() {
    return {
      'scheduleId': scheduleId,
      'userId': userId,
      'medName': medName,
      'amount': amount,
      'unit': unit,
      'imageUrl': imageUrl,
      'notificationId': notificationId,
      'days': days,
      'additionalInfo': additionalInfo,
    };
  }

  factory Medication.fromMap(String id, Map<String, dynamic> map) {
    return Medication(
      medId: id,
      scheduleId: map['scheduleId'] ?? '',
      userId: map['userId'] ?? '',
      medName: map['medName'] ?? '',
      amount: map['amount'] ?? 0,
      unit: map['unit'] ?? '',
      imageUrl: map['imageUrl'],
      notificationId: (map['notificationId'] as num?)?.toInt() ?? 0,
      days: List<String>.from(map['days'] ?? ['Everyday']),
      additionalInfo: map['additionalInfo'],
    );
  }
}
