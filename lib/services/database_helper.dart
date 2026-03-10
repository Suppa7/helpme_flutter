import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/medication.dart';

/// DatabaseHelper — ใช้ Cloud Firestore แทน SQLite
/// โครงสร้าง path: users/{relativeCode}/medications/{id}
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  DatabaseHelper._init();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ดึง relativeCode จาก SharedPreferences เพื่อใช้เป็น User's Document ID
  Future<String> _getRelativeCode() async {
    final prefs = await SharedPreferences.getInstance();
    String? code = prefs.getString('relativeCode');
    if (code == null) {
      // สร้างรหัสใหม่ถ้ายังไม่มี (backup — ปกติ HomeScreen สร้างแล้ว)
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final rnd = Random();
      code = String.fromCharCodes(
        Iterable.generate(10, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
      );
      await prefs.setString('relativeCode', code);
    }
    return code;
  }

  // ดึง collection reference ของยาของผู้ใช้คนนี้
  Future<CollectionReference<Map<String, dynamic>>> _medsCollection() async {
    final code = await _getRelativeCode();
    return _db.collection('users').doc(code).collection('medications');
  }

  // ================= CRUD Operations =================

  // CREATE: เพิ่มยาใหม่ → คืนค่า id (int) เพื่อนำไป set Alarm
  Future<int> insertPill(Medication med) async {
    final col = await _medsCollection();
    // สร้าง id เป็น int สุ่ม (ต้องไม่ซ้ำกัน) เพื่อใช้กับ Notification alarm
    final int newId = DateTime.now().millisecondsSinceEpoch % 100000 + Random().nextInt(10000);
    med.id = newId;
    await col.doc(newId.toString()).set(med.toMap());
    return newId;
  }

  // READ: ดึงรายการยาทั้งหมด (เรียงตามเวลา)
  Future<List<Medication>> getPills() async {
    final col = await _medsCollection();
    final snapshot = await col.orderBy('time').get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      // ใส่ id กลับเข้าไปใน map เพื่อให้ fromMap ทำงานได้
      data['id'] = int.tryParse(doc.id) ?? 0;
      return Medication.fromMap(data);
    }).toList();
  }

  // UPDATE: อัปเดตสถานะว่ากินยาแล้ว (0 → 1)
  Future<void> updatePillStatus(int id, int isTaken) async {
    final col = await _medsCollection();
    await col.doc(id.toString()).update({'isTaken': isTaken});
  }

  // DELETE: ลบยา
  Future<void> deletePill(int id) async {
    final col = await _medsCollection();
    await col.doc(id.toString()).delete();
  }

  // อัปเดตข้อมูลยาทั้งชุด (รวมถึงจำนวนที่เหลือและสถานะ)
  Future<void> updateMedication(Medication med) async {
    final col = await _medsCollection();
    await col.doc(med.id.toString()).set(med.toMap(), SetOptions(merge: true));
  }

  // รีเซ็ตสถานะยาทุกตัวให้เป็น "ยังไม่ได้กิน" (0) เมื่อเริ่มวันใหม่
  Future<void> resetAllPillsStatus() async {
    final col = await _medsCollection();
    final snapshot = await col.get();
    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'isTaken': 0});
    }
    await batch.commit();
  }

  // ดึงข้อมูลยา 1 รายการ ตาม ID
  Future<Medication?> getPillById(int id) async {
    final col = await _medsCollection();
    final doc = await col.doc(id.toString()).get();
    if (doc.exists) {
      final data = doc.data()!;
      data['id'] = int.tryParse(doc.id) ?? 0;
      return Medication.fromMap(data);
    }
    return null;
  }
}
