import 'package:cloud_firestore/cloud_firestore.dart';

class MedicationLog {
  String? logId;
  String userId;
  String medId;
  String scheduleId;
  String medName;
  DateTime plannedTimestamp;
  DateTime? actualTimestamp;
  String status; // 'taken', 'skipped', 'missed'
  String? note;
  String? takenBy;
  int snoozeCount;

  MedicationLog({
    this.logId,
    required this.userId,
    required this.medId,
    required this.scheduleId,
    required this.medName,
    required this.plannedTimestamp,
    this.actualTimestamp,
    required this.status,
    this.note,
    this.takenBy,
    this.snoozeCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'medId': medId,
      'scheduleId': scheduleId,
      'medName': medName,
      'plannedTimestamp': Timestamp.fromDate(plannedTimestamp),
      if (actualTimestamp != null) 'actualTimestamp': Timestamp.fromDate(actualTimestamp!),
      'status': status,
      if (note != null) 'note': note,
      if (takenBy != null) 'takenBy': takenBy,
      'snoozeCount': snoozeCount,
    };
  }

  factory MedicationLog.fromMap(Map<String, dynamic> map, String id) {
    return MedicationLog(
      logId: id,
      userId: map['userId'] as String? ?? '',
      medId: map['medId'] as String? ?? '',
      scheduleId: map['scheduleId'] as String? ?? '',
      medName: map['medName'] as String? ?? '',
      plannedTimestamp: (map['plannedTimestamp'] as Timestamp).toDate(),
      actualTimestamp: map['actualTimestamp'] != null 
          ? (map['actualTimestamp'] as Timestamp).toDate() 
          : null,
      status: map['status'] as String? ?? 'missed',
      note: map['note'] as String?,
      takenBy: map['takenBy'] as String?,
      snoozeCount: (map['snoozeCount'] as num?)?.toInt() ?? 0,
    );
  }
}
