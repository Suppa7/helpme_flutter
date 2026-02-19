import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/medication.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('medications_v2.db');
    return _database!;
  }

  // สร้างไฟล์และเปิดฐานข้อมูล
  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  // สร้างตารางเมื่อเปิดแอปครั้งแรก
  Future _createDB(Database db, int version) async {
    await db.execute('''
    CREATE TABLE pills (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      time TEXT NOT NULL,
      imagePath TEXT,
      description TEXT,
      remainingPills INTEGER NOT NULL,
      isTaken INTEGER NOT NULL
    )
    ''');
  }

  // ================= CRUD Operations =================

  // CREATE: เพิ่มยาใหม่
  Future<int> insertPill(Medication med) async {
    final db = await instance.database;
    return await db.insert('pills', med.toMap());
  }

  // READ: ดึงรายการยาทั้งหมด (เรียงตามเวลา)
  Future<List<Medication>> getPills() async {
    final db = await instance.database;
    final result = await db.query('pills', orderBy: 'time ASC');
    return result.map((json) => Medication.fromMap(json)).toList();
  }

  // UPDATE: อัปเดตสถานะว่ากินยาแล้ว (0 -> 1)
  Future<int> updatePillStatus(int id, int isTaken) async {
    final db = await instance.database;
    return await db.update(
      'pills',
      {'isTaken': isTaken},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // DELETE: ลบยา (เผื่อกรณีกรอกผิด)
  Future<int> deletePill(int id) async {
    final db = await instance.database;
    return await db.delete('pills', where: 'id = ?', whereArgs: [id]);
  }

  // อัปเดตข้อมูลยาทั้งชุด (รวมถึงจำนวนที่เหลือและสถานะ)
  Future<int> updateMedication(Medication med) async {
    final db = await instance.database;
    return await db.update(
      'pills',
      med.toMap(),
      where: 'id = ?',
      whereArgs: [med.id],
    );
  }

  // สำหรับรีเซ็ตสถานะยาทุกตัวให้เป็น "ยังไม่ได้กิน" (0) เมื่อเริ่มวันใหม่
  Future<int> resetAllPillsStatus() async {
    final db = await instance.database;
    return await db.update('pills', {'isTaken': 0});
  }

  // ดึงข้อมูลยา 1 รายการ ตาม ID
  Future<Medication?> getPillById(int id) async {
    final db = await instance.database;
    final maps = await db.query('pills', where: 'id = ?', whereArgs: [id]);

    if (maps.isNotEmpty) {
      return Medication.fromMap(maps.first);
    }
    return null;
  }
}
