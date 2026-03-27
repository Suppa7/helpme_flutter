import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/medication_log.dart';

class MedicationLogRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _collectionPath = 'MedicationLogs';

  // อ้างอิงไปยัง Collection MedicationLogs
  CollectionReference get _collection => _db.collection(_collectionPath);

  // 1. สร้าง (Create) บันทึกการทานยาใหม่
  Future<String> createLog(MedicationLog log) async {
    final docRef = await _collection.add(log.toMap());
    log.logId = docRef.id;
    return docRef.id;
  }

  // 2. อ่าน (Read) บันทึกรายรายการจาก ID
  Future<MedicationLog?> getLogById(String logId) async {
    final docSnapshot = await _collection.doc(logId).get();
    if (docSnapshot.exists && docSnapshot.data() != null) {
      return MedicationLog.fromMap(
          docSnapshot.data() as Map<String, dynamic>, docSnapshot.id);
    }
    return null;
  }

  // 3. อ่าน (Read) ประวัติการทานยาของผู้ป่วยตาม userId เรียงตามเวลาแผนการทานยา
  Future<List<MedicationLog>> getLogsByUserId(String userId) async {
    final querySnapshot = await _collection
        .where('userId', isEqualTo: userId)
        .orderBy('plannedTimestamp', descending: true)
        .get();

    return querySnapshot.docs.map((doc) {
      return MedicationLog.fromMap(doc.data() as Map<String, dynamic>, doc.id);
    }).toList();
  }

  // 4. อัปเดต (Update) สถานะและข้อมูลการทานยา (เช่น กรณีกด "กินยาแล้ว" หรืออัปเดต Note)
  Future<void> updateLog(MedicationLog log) async {
    if (log.logId == null) {
      throw Exception('Log ID is missing');
    }
    await _collection.doc(log.logId).update(log.toMap());
  }

  // 5. ลบ (Delete) บันทึก (หากจำเป็นต้องใช้)
  Future<void> deleteLog(String logId) async {
    await _collection.doc(logId).delete();
  }

  // 6. Query เฉพาะช่วงเวลา (ตัวอย่างเช่น ดึงประวัติของวันนี้ หรือ 7 วันที่ผ่านมา)
  Future<List<MedicationLog>> getLogsForDateRange(String userId, DateTime start, DateTime end) async {
    final querySnapshot = await _collection
        .where('userId', isEqualTo: userId)
        .where('plannedTimestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('plannedTimestamp', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('plannedTimestamp', descending: true)
        .get();

    return querySnapshot.docs.map((doc) {
      return MedicationLog.fromMap(doc.data() as Map<String, dynamic>, doc.id);
    }).toList();
  }

  // 7. สร้าง (Create) บันทึกหลายรายการพร้อมกันด้วย Batch Write (เช่น สร้างล่วงหน้า 1 สัปดาห์)
  // หมายเหตุ: Firestore Batch Write รองรับสูงสุด 500 operations ต่อ 1 batch
  Future<void> createLogsBatch(List<MedicationLog> logs) async {
    if (logs.isEmpty) return;

    final WriteBatch batch = _db.batch();

    for (final log in logs) {
      // สร้าง Document Reference ใหม่โดยให้ Firestore gen ID ให้เลย
      final docRef = _collection.doc();
      log.logId = docRef.id;
      
      // เพิ่มคำสั่ง set ลงใน batch
      batch.set(docRef, log.toMap());
    }

    // สั่ง execute ทุกคำสั่งพร้อมกันทั้งหมดรวดเดียว
    await batch.commit();
  }
}
