import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/models/medication.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';
import '../services/database_helper.dart';

void main() async {
  // ต้องมีคำสั่งนี้เพื่อให้ Flutter ผูกกับ Native code ก่อนเรียกใช้ SharedPreferences
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService().init();

  // เช็กว่ามีข้อมูลชื่อผู้ใช้ในระบบหรือยัง
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? userName = prefs.getString('userName');

  runApp(MyApp(initialRoute: userName == null ? '/register' : '/home'));
}

// คลาส MyApp แก้ให้ใส่ navigatorKey และเพิ่ม route เข้าไป
class MyApp extends StatelessWidget {
  final String initialRoute;
  const MyApp({Key? key, required this.initialRoute}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'แอพเตือนกินยา',
      theme: ThemeData(primarySwatch: Colors.blue),
      navigatorKey:
          navigatorKey, // 🌟 สำคัญ: เพื่อให้ Notification เปลี่ยนหน้าได้
      initialRoute: initialRoute,
      routes: {
        '/register': (context) => const RegisterScreen(), // (หน้าเดิมของคุณ)
        '/home': (context) => const HomeScreen(), // (หน้าเดิมของคุณ)
        '/med_detail': (context) =>
            const MedicationDetailScreen(), // 🌟 หน้าใหม่
      },
    );
  }
}

// ==========================================
// 🌟 หน้าจอใหม่: แสดงรายละเอียดเมื่อกดจากการแจ้งเตือน
// ==========================================
class MedicationDetailScreen extends StatefulWidget {
  const MedicationDetailScreen({Key? key}) : super(key: key);

  @override
  State<MedicationDetailScreen> createState() => _MedicationDetailScreenState();
}

class _MedicationDetailScreenState extends State<MedicationDetailScreen> {
  Medication? _med;
  bool _isLoading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // รับ ID ของยาที่ส่งมาจาก Notification Payload
    final int medId = ModalRoute.of(context)!.settings.arguments as int;
    _loadMedication(medId);
  }

  Future<void> _loadMedication(int id) async {
    final med = await DatabaseHelper.instance.getPillById(id);
    setState(() {
      _med = med;
      _isLoading = false;
    });
  }

  Future<void> _confirmTaken() async {
    if (_med != null) {
      int newRemaining = _med!.remainingPills;
      if (_med!.isTaken == 0) {
        if (newRemaining > 0) {
          newRemaining -= 1; // หักยา 1 เม็ด
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ยารายการนี้หมดแล้ว!'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      _med!.isTaken = 1;
      _med!.remainingPills = newRemaining;

      // อัปเดตข้อมูลลงฐานข้อมูล
      await DatabaseHelper.instance.updateMedication(_med!);
      // ยกเลิกการแจ้งเตือนของญาติ
      await NotificationService().cancelRelativeAlert(_med!.id!);

      // กลับไปหน้า Home
      if (mounted) {
        // ใช้ pushNamedAndRemoveUntil เพื่อล้าง stack กลับไปหน้า Home แบบสะอาดๆ
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_med == null)
      return const Scaffold(body: Center(child: Text('ไม่พบข้อมูลยา')));

    return Scaffold(
      backgroundColor: Colors.blue.shade50,
      appBar: AppBar(
        title: const Text('ยืนยันการทานยา'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // แสดงรูปภาพ หรือ ไอคอน
            if (_med!.imagePath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.file(
                  File(_med!.imagePath!),
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                ),
              )
            else
              Icon(Icons.medication, size: 150, color: Colors.blue.shade300),

            const SizedBox(height: 30),
            Text(
              _med!.time,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            Text(
              _med!.name,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
            ),

            if (_med!.description != null && _med!.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 15),
                child: Text(
                  _med!.description!,
                  style: const TextStyle(fontSize: 20, color: Colors.grey),
                ),
              ),

            const SizedBox(height: 40),

            // ปุ่มกดยืนยันกินยา
            ElevatedButton.icon(
              onPressed: _med!.isTaken == 1 ? null : _confirmTaken,
              icon: const Icon(Icons.check_circle, size: 40),
              label: Text(
                _med!.isTaken == 1 ? 'ทานยานี้ไปแล้ว' : 'ฉันทานยานี้แล้ว',
                style: const TextStyle(fontSize: 24),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey,
                minimumSize: const Size(double.infinity, 80),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// หน้าจอสำหรับกรอกชื่อและอายุ (ทำครั้งเดียวตอนโหลดแอปใหม่)
// ==========================================
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();

  Future<void> _saveUserData() async {
    if (_nameController.text.isEmpty || _ageController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกข้อมูลให้ครบถ้วนครับ')),
      );
      return;
    }

    // บันทึกข้อมูลลงเครื่อง
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', _nameController.text);
    await prefs.setInt('userAge', int.parse(_ageController.text));

    // เปลี่ยนไปหน้าหลักและลบหน้าลงทะเบียนทิ้ง (ไม่ให้กดย้อนกลับมาได้)
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ยินดีต้อนรับ')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'ข้อมูลสำหรับดูแลผู้ใช้งาน',
              style: TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'ชื่อผู้ใช้งาน (เช่น คุณตา สมชาย)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _ageController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'อายุ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saveUserData,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text(
                'เริ่มต้นใช้งาน',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
