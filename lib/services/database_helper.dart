import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/medication.dart';
import '../models/schedule.dart';
import '../models/medication_log.dart';

/// DatabaseHelper — จัดการข้อมูลบน Root Collections 'Schedules' และ 'Medications'
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  DatabaseHelper._init();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ดึง UID ของผู้ใช้ปัจจุบัน
  Future<String?> _getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('uid');
  }

  // ================= CRUD Operations สำหรับยาและตาราง =================

  // CREATE: เพิ่มยาพร้อมตารางเวลาแบบ Batch Write
  Future<Medication?> insertMedicationWithSchedule(ScheduleModel sched, Medication med) async {
    final uid = await _getUserId();
    if (uid == null) return null;

    sched.userId = uid;
    med.userId = uid;

    final schedRef = _db.collection('Schedules').doc();
    sched.scheduleId = schedRef.id;
    
    final medRef = _db.collection('Medications').doc();
    med.medId = medRef.id;
    med.scheduleId = sched.scheduleId!; // เชื่อมโยงกัน

    // สร้าง notificationId เป็น int สุ่มให้ใช้งานกับ flutter_local_notifications ได้
    med.notificationId = DateTime.now().millisecondsSinceEpoch % 1000000;

    final batch = _db.batch();
    batch.set(schedRef, sched.toMap());
    batch.set(medRef, med.toMap());
    
    await batch.commit();
    return med;
  }

  // READ: ดึงยาและตารางทั้งหมดของผู้ป่วย
  Future<List<Medication>> getUserMedicationsWithSchedules() async {
    final uid = await _getUserId();
    if (uid == null) return [];

    // ดึงตารางเวลาทั้งหมดของผู้ใช้
    final schedSnapshot = await _db.collection('Schedules').where('userId', isEqualTo: uid).get();
    Map<String, ScheduleModel> scheduleMap = {};
    for (var doc in schedSnapshot.docs) {
      scheduleMap[doc.id] = ScheduleModel.fromMap(doc.id, doc.data());
    }
    
    // ดึงยาทั้งหมดของผู้ใช้
    final medSnapshot = await _db.collection('Medications').where('userId', isEqualTo: uid).get();
    List<Medication> meds = [];
    
    for (var doc in medSnapshot.docs) {
      final med = Medication.fromMap(doc.id, doc.data());
      med.schedule = scheduleMap[med.scheduleId]; // ผูกกับตาราง
      
      // เก็บเฉพาะยาที่มีตารางสมบูรณ์
      if (med.schedule != null && med.schedule!.isActive) {
        meds.add(med);
      }
    }
    
    // เรียงตามเวลา
    meds.sort((a, b) => a.schedule!.time.compareTo(b.schedule!.time));
    return meds;
  }

  // DELETE: ลบยาและตารางพร้อมกัน
  Future<void> deleteMedicationAndSchedule(Medication med) async {
    final batch = _db.batch();
    
    if (med.medId != null) {
      batch.delete(_db.collection('Medications').doc(med.medId));
    }
    if (med.scheduleId.isNotEmpty) {
      batch.delete(_db.collection('Schedules').doc(med.scheduleId));
    }
    
    await batch.commit();
  }

  // READ: ดึงยาจาก notificationId (ใช้ตอนกดแจ้งเตือน)
  Future<Medication?> getMedicationByNotificationId(int id) async {
    final medSnapshot = await _db.collection('Medications').where('notificationId', isEqualTo: id).limit(1).get();
    if (medSnapshot.docs.isEmpty) return null;
    
    final doc = medSnapshot.docs.first;
    final med = Medication.fromMap(doc.id, doc.data());
    
    final schedDoc = await _db.collection('Schedules').doc(med.scheduleId).get();
    if (schedDoc.exists) {
      med.schedule = ScheduleModel.fromMap(schedDoc.id, schedDoc.data()!);
    }
    return med;
  }

  // ================= CRUD Operations สำหรับ Schedule เดี่ยว ๆ =================

  // CREATE: เพิ่มกำหนดการเวลา
  Future<ScheduleModel?> insertSchedule(ScheduleModel sched) async {
    final uid = await _getUserId();
    if (uid == null) return null;

    sched.userId = uid;
    final schedRef = _db.collection('Schedules').doc();
    sched.scheduleId = schedRef.id;

    await schedRef.set(sched.toMap());
    return sched;
  }

  // UPDATE: แก้ไขกำหนดการเวลา
  Future<void> updateSchedule(ScheduleModel sched) async {
    if (sched.scheduleId == null) return;
    await _db.collection('Schedules').doc(sched.scheduleId).update(sched.toMap());
  }

  // READ: ดึงตารางเวลาทั้งหมดของผู้ใช้
  Future<List<ScheduleModel>> getUserSchedules() async {
    final uid = await _getUserId();
    if (uid == null) return [];

    final schedSnapshot = await _db.collection('Schedules').where('userId', isEqualTo: uid).get();
    List<ScheduleModel> schedules = [];
    
    for (var doc in schedSnapshot.docs) {
      schedules.add(ScheduleModel.fromMap(doc.id, doc.data()));
    }
    
    // เรียงเวลาจากน้อยไปมาก
    schedules.sort((a, b) => a.time.compareTo(b.time));
    return schedules;
  }

  // DELETE: ลบตารางเวลาและยาที่อยู่ในตารางนี้ทั้งหมด
  Future<void> deleteSchedule(String scheduleId) async {
    final batch = _db.batch();
    
    // 1. ลบยาที่อ้างอิงถึง scheduleId นี้
    final medsSnapshot = await _db.collection('Medications').where('scheduleId', isEqualTo: scheduleId).get();
    for (var doc in medsSnapshot.docs) {
      batch.delete(doc.reference);
    }
    
    // 2. ลบ Schedule ตัวเอง
    batch.delete(_db.collection('Schedules').doc(scheduleId));
    
    await batch.commit();
  }

  // ================= CRUD Operations สำหรับยาในตาราง =================

  // UPDATE: แก้ไขรายละเอียดยา
  Future<void> updateMedication(Medication med) async {
    if (med.medId == null) return;
    await _db.collection('Medications').doc(med.medId).update(med.toMap());
  }

  // CREATE: เพิ่มยาเข้าไปในตารางเวลาที่มีอยู่แล้ว
  Future<Medication?> insertMedication(Medication med) async {
    final uid = await _getUserId();
    if (uid == null) return null;

    med.userId = uid;

    final medRef = _db.collection('Medications').doc();
    med.medId = medRef.id;
    med.notificationId = DateTime.now().millisecondsSinceEpoch % 1000000;

    await medRef.set(med.toMap());
    return med;
  }

  // READ: ดึงรายการยาทั้งหมดที่อยู่ในตารางเวลานี้
  Future<List<Medication>> getMedicationsBySchedule(String scheduleId) async {
    final uid = await _getUserId();
    if (uid == null) return [];

    final medSnapshot = await _db.collection('Medications')
        .where('userId', isEqualTo: uid)
        .where('scheduleId', isEqualTo: scheduleId)
        .get();
        
    List<Medication> meds = [];
    for (var doc in medSnapshot.docs) {
      meds.add(Medication.fromMap(doc.id, doc.data()));
    }
    return meds;
  }

  // DELETE: ลบยาเดี่ยวๆ
  Future<void> deleteMedication(String medId) async {
    await _db.collection('Medications').doc(medId).delete();
  }

  // ================= CRUD Operations สำหรับ MedicationLogs =================

  // CREATE: บันทึกประวัติการกินยา
  Future<void> insertMedicationLog(MedicationLog log) async {
    final uid = await _getUserId();
    if (uid == null) return;
    
    log.userId = uid;
    final logRef = _db.collection('MedicationLogs').doc();
    log.logId = logRef.id;
    
    await logRef.set(log.toMap());
  }

  // READ: ดึงประวัติการกินยาของวันนี้
  Future<List<MedicationLog>> getTodayMedicationLogs() async {
    final uid = await _getUserId();
    if (uid == null) return [];

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    // Query เฉพาะ userId เท่านั้น (ไม่ใช้ range filter เพื่อหลีกเลี่ยง Composite Index)
    final snapshot = await _db.collection('MedicationLogs')
        .where('userId', isEqualTo: uid)
        .get();

    // Filter วันที่ฝั่ง Client
    List<MedicationLog> logs = [];
    for (var doc in snapshot.docs) {
      final log = MedicationLog.fromMap(doc.data(), doc.id);
      final actual = log.actualTimestamp ?? log.plannedTimestamp;
      if (!actual.isBefore(startOfDay) && !actual.isAfter(endOfDay)) {
        logs.add(log);
      }
    }

    // เรียงจากใหม่ → เก่า ฝั่ง Client
    logs.sort((a, b) {
      final aTime = a.actualTimestamp ?? a.plannedTimestamp;
      final bTime = b.actualTimestamp ?? b.plannedTimestamp;
      return bTime.compareTo(aTime);
    });

    return logs;
  }

  // WRITE: ตรวจและบันทึก 'missed' สำหรับยาที่ไม่ได้ทานในรอบที่ผ่านมาวันนี้
  Future<void> checkAndMarkMissedLogs() async {
    final uid = await _getUserId();
    if (uid == null) return;

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    // ดึงตาราง Schedule ทั้งหมดของผู้ใช้
    final schedSnapshot = await _db.collection('Schedules')
        .where('userId', isEqualTo: uid)
        .where('isActive', isEqualTo: true)
        .get();

    for (var schedDoc in schedSnapshot.docs) {
      final scheduleId = schedDoc.id;
      final timeStr = schedDoc.data()['time'] as String? ?? '';
      final parts = timeStr.split(':');
      if (parts.length != 2) continue;

      final schedHour = int.tryParse(parts[0]) ?? 0;
      final schedMin = int.tryParse(parts[1]) ?? 0;
      final plannedTime = DateTime(now.year, now.month, now.day, schedHour, schedMin);

      // ข้ามถ้าเวลายังไม่ถึง (+5 นาที buffer ให้ผู้ใช้ทัน)
      if (now.isBefore(plannedTime.add(const Duration(minutes: 5)))) continue;

      // ดึงยาในตารางนี้
      final medSnapshot = await _db.collection('Medications')
          .where('userId', isEqualTo: uid)
          .where('scheduleId', isEqualTo: scheduleId)
          .get();

      // ดึง Log ของวันนี้สำหรับ scheduleId นี้ (filter client-side)
      final logSnapshot = await _db.collection('MedicationLogs')
          .where('userId', isEqualTo: uid)
          .where('scheduleId', isEqualTo: scheduleId)
          .get();

      final loggedMedIds = <String>{};
      for (var logDoc in logSnapshot.docs) {
        final actualTs = logDoc.data()['actualTimestamp'];
        if (actualTs != null) {
          final actualDate = (actualTs as Timestamp).toDate();
          if (!actualDate.isBefore(startOfDay)) {
            loggedMedIds.add(logDoc.data()['medId'] as String? ?? '');
          }
        }
      }

      // บันทึก 'missed' สำหรับยาที่ยังไม่มี Log วันนี้
      final batch = _db.batch();
      bool hasMissed = false;
      for (var medDoc in medSnapshot.docs) {
        final medId = medDoc.id;
        final medName = medDoc.data()['medName'] as String? ?? '';
        if (!loggedMedIds.contains(medId)) {
          final logRef = _db.collection('MedicationLogs').doc();
          batch.set(logRef, MedicationLog(
            logId: logRef.id,
            userId: uid,
            medId: medId,
            scheduleId: scheduleId,
            medName: medName,
            plannedTimestamp: plannedTime,
            actualTimestamp: plannedTime, // ไม่ได้ทาน ใช้เวลาที่ควรทานเป็น reference
            status: 'missed',
          ).toMap());
          hasMissed = true;
        }
      }
      if (hasMissed) await batch.commit();
    }
  }
}
