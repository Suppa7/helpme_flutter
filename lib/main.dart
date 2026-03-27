import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/models/medication.dart';
import 'package:test/models/medication_log.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';
import 'services/database_helper.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await NotificationService().init();

  // เช็กว่ามีข้อมูล UID หรือยัง (Custom Auth)
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? uid = prefs.getString('uid');

  runApp(MyApp(initialRoute: uid == null ? '/login' : '/home'));
}

// คลาส MyApp แก้ให้ใส่ navigatorKey และเพิ่ม route เข้าไป
class MyApp extends StatelessWidget {
  final String initialRoute;
  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'แอพเตือนกินยา',
      theme: ThemeData(primarySwatch: Colors.blue),
      navigatorKey:
          navigatorKey, // 🌟 สำคัญ: เพื่อให้ Notification เปลี่ยนหน้าได้
      initialRoute: initialRoute,
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => const HomeScreen(),
        '/med_detail': (context) =>
            const MedicationDetailScreen(), // 🌟 หน้าใหม่
      },
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', 'US'), // ภาษาอังกฤษ
        Locale('th', 'TH'), // ภาษาไทย
      ],
    );
  }
}

// ==========================================
// 🌟 หน้าจอใหม่: แสดงรายละเอียดเมื่อกดจากการแจ้งเตือน
// ==========================================
class MedicationDetailScreen extends StatefulWidget {
  const MedicationDetailScreen({super.key});

  @override
  State<MedicationDetailScreen> createState() => _MedicationDetailScreenState();
}

class _MedicationDetailScreenState extends State<MedicationDetailScreen> {
  List<Medication> _meds = [];
  bool _isLoading = true;
  String _scheduleId = '';
  String _scheduleTime = '';
  final Set<String> _takenMedIds = {};
  int _snoozeCount = 0; // 🌟 นับจำนวนครั้งที่กด Snooze

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)!.settings.arguments;
    if (args is String) {
      _scheduleId = args;
      _loadMedications(_scheduleId);
    }
  }

  Future<void> _loadMedications(String schedId) async {
    final allMeds = await DatabaseHelper.instance.getMedicationsBySchedule(schedId);
    
    // กรองเอาเฉพาะยาที่ amount > 0 มาแสดงให้กดทาน
    final meds = allMeds.where((m) => m.amount > 0).toList();
    
    // Fetch target Schedule for its time
    final schedDoc = await FirebaseFirestore.instance.collection('Schedules').doc(schedId).get();
    String timeStr = '';
    if (schedDoc.exists) {
      timeStr = schedDoc.data()?['time'] ?? '';
    }

    // ถ้าไม่มียาที่ยังไม่หมดเหลืออยู่เลย (แต่อาจแจ้งเตือนค้างมา) ให้ยกเลิกแจ้งเตือนซะ
    if (meds.isEmpty) {
      await NotificationService().cancelAllAlertsForSchedule(schedId);
    }

    setState(() {
      _meds = meds;
      _scheduleTime = timeStr;
      _isLoading = false;
    });
  }

  // กินเฉพาะบางตัว
  Future<void> _takeIndividual(Medication med) async {
    if (_takenMedIds.contains(med.medId)) return;

    if (med.amount >= 1) {
      med.amount -= 1;
    } else {
      med.amount = 0;
    }
    await DatabaseHelper.instance.updateMedication(med);

    // 🌟 สร้าง Log
    final now = DateTime.now();
    final parts = _scheduleTime.split(':');
    DateTime plannedTime = now;
    if (parts.length == 2) {
      int h = int.tryParse(parts[0]) ?? now.hour;
      int m = int.tryParse(parts[1]) ?? now.minute;
      plannedTime = DateTime(now.year, now.month, now.day, h, m);
    }
    
    final log = MedicationLog(
      userId: '', // เดี๋ยว Helper จัดการให้
      medId: med.medId ?? '',
      scheduleId: _scheduleId,
      medName: med.medName,
      plannedTimestamp: plannedTime,
      actualTimestamp: now,
      status: 'taken',
      snoozeCount: _snoozeCount,
    );
    await DatabaseHelper.instance.insertMedicationLog(log);

    setState(() {
      _takenMedIds.add(med.medId!);
    });

    // ถ้ากดครบทุกตัวแล้ว
    if (_takenMedIds.length >= _meds.length) {
      await _confirmAllTaken(deductAmount: false); // หักไปแล้วทีละตัว
    }
  }

  // กินทั้งหมดรวดเดียว
  Future<void> _confirmAllTaken({bool deductAmount = true}) async {
    // หักจำนวน
    if (deductAmount) {
      final now = DateTime.now();
      final parts = _scheduleTime.split(':');
      DateTime plannedTime = now;
      if (parts.length == 2) {
        int h = int.tryParse(parts[0]) ?? now.hour;
        int m = int.tryParse(parts[1]) ?? now.minute;
        plannedTime = DateTime(now.year, now.month, now.day, h, m);
      }

      for (var med in _meds) {
        if (!_takenMedIds.contains(med.medId)) {
          if (med.amount >= 1) {
            med.amount -= 1;
          } else {
            med.amount = 0;
          }
          await DatabaseHelper.instance.updateMedication(med);

          final log = MedicationLog(
            userId: '',
            medId: med.medId ?? '',
            scheduleId: _scheduleId,
            medName: med.medName,
            plannedTimestamp: plannedTime,
            actualTimestamp: now,
            status: 'taken',
            snoozeCount: _snoozeCount,
          );
          await DatabaseHelper.instance.insertMedicationLog(log);
        }
      }
    }
    
    // ยกเลิกข้อความแจ้งเตือนทั้งหมด
    await NotificationService().cancelAllAlertsForSchedule(_scheduleId);

    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    }
  }

  Future<void> _snoozeAlert() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String userName = prefs.getString('userName') ?? 'ผู้ใช้งาน';

    // นับจำนวน Snooze ก่อน ค่อย navigate ออกไป
    setState(() => _snoozeCount++);

    await NotificationService().snoozeScheduleAlerts(
      scheduleId: _scheduleId,
      timeString: _scheduleTime.isEmpty ? 'ไม่ระบุเวลา' : _scheduleTime,
      userName: userName,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เลื่อนเวลาปลุกไปอีก 15 นาที (Snooze ครั้งที่ $_snoozeCount)')),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_meds.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('รายการยา')),
        body: const Center(child: Text('ไม่พบรายการยาในรอบเวลานี้')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.blue.shade50,
      appBar: AppBar(
        title: Text('รอบเวลา ${_scheduleTime.isNotEmpty ? _scheduleTime : "ไม่ระบุ"}'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            color: Colors.blue.shade100,
            child: Text(
              'เลือกทานเฉพาะยา หรือกดยืนยันทั้งหมดด้านล่าง',
              style: TextStyle(fontSize: 16, color: Colors.blue.shade900, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _meds.length,
              itemBuilder: (context, index) {
                final med = _meds[index];
                final isTaken = _takenMedIds.contains(med.medId);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  color: isTaken ? Colors.green.shade50 : Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        if (med.imageUrl != null)
                          GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => Dialog(
                                  backgroundColor: Colors.transparent,
                                  surfaceTintColor: Colors.transparent,
                                  insetPadding: const EdgeInsets.all(10),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      InteractiveViewer(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(15),
                                          child: Image.file(
                                            File(med.imageUrl!),
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 0,
                                        right: 0,
                                        child: IconButton(
                                          icon: const Icon(Icons.cancel, color: Colors.redAccent, size: 35),
                                          onPressed: () => Navigator.of(ctx).pop(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(
                                File(med.imageUrl!),
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                              ),
                            ),
                          )
                        else
                          Icon(Icons.medication, size: 60, color: Colors.blue.shade300),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                med.medName,
                                style: TextStyle(
                                  fontSize: 20, 
                                  fontWeight: FontWeight.bold,
                                  decoration: isTaken ? TextDecoration.lineThrough : null,
                                  color: isTaken ? Colors.grey : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'ยาที่เหลือ: ${med.amount} ${med.unit}',
                                style: const TextStyle(fontSize: 16, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        isTaken
                            ? const Icon(Icons.check_circle, color: Colors.green, size: 32)
                            : OutlinedButton(
                                onPressed: () => _takeIndividual(med),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.blue,
                                  side: const BorderSide(color: Colors.blue),
                                ),
                                child: const Text('ทานยานี้'),
                              ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _confirmAllTaken(),
                  icon: const Icon(Icons.checklist, size: 28),
                  label: const Text(
                    'รับประทานยาทั้งหมด',
                    style: TextStyle(fontSize: 20),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _snoozeAlert,
                  icon: const Icon(Icons.access_time_filled, size: 28),
                  label: const Text(
                    'เลื่อนเวลา (15 นาที)',
                    style: TextStyle(fontSize: 20),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 🔐 หน้าเข้าสู่ระบบ (Login)
// ==========================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    if (_phoneController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณากรอกเบอร์โทรศัพท์และรหัสผ่าน')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: _phoneController.text.trim())
          .where('password', isEqualTo: _passwordController.text.trim())
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        // ล็อกอินสำเร็จ: ดึง UID มาบันทึกลง SharedPreferences
        final userDoc = querySnapshot.docs.first;
        final uid = userDoc.id;

        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('uid', uid);
        await prefs.setString('userName', userDoc.data()['username'] ?? '');

        if (mounted) Navigator.pushReplacementNamed(context, '/home');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('เบอร์โทรศัพท์หรือรหัสผ่านไม่ถูกต้อง')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เข้าสู่ระบบล้มเหลว: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('เข้าสู่ระบบ')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'เบอร์โทรศัพท์', border: OutlineInputBorder()),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'รหัสผ่าน', border: OutlineInputBorder()),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _login,
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                    child: const Text('เข้าสู่ระบบ', style: TextStyle(fontSize: 18)),
                  ),
            TextButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/register'),
              child: const Text('ยังไม่มีบัญชี? สมัครสมาชิก'),
            )
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 📝 หน้าสมัครสมาชิก (Register) สอดคล้องกับ DB_context.md ใหม่
// ==========================================
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLoading = false;

  String _generateUserCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(6, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  Future<void> _register() async {
    if (_nameController.text.isEmpty || _phoneController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณากรอกข้อมูลให้ครบถ้วน')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      // ตรวจสอบก่อนว่าเบอร์โทรนี้เคยสมัครหรือยัง
      final existingUsers = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: _phoneController.text.trim())
          .get();

      if (existingUsers.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('เบอร์โทรศัพท์นี้ถูกใช้งานแล้ว')));
        }
        return;
      }

      final userCode = _generateUserCode();

      // บันทึกข้อมูลลง Firestore ใน Collection users
      final docRef = await FirebaseFirestore.instance.collection('users').add({
        'username': _nameController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
        'password': _passwordController.text.trim(),
        'userCode': userCode,
        'monitoredUserUids': [],
        'followerUids': [],
        'fcmToken': '', // เตรียมไว้สำหรับแจ้งเตือนภายหลัง
        'createdAt': FieldValue.serverTimestamp(),
      });

      // นำ Document ID ที่ได้มาใช้เป็น uid ในเครื่อง
      final uid = docRef.id;

      // บันทึก Document ID ลง Shared Preferences
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('uid', uid);
      await prefs.setString('userName', _nameController.text.trim());

      // ไปหน้าหลัก
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('สมัครสมาชิกไม่สำเร็จ: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('สมัครสมาชิกใหม่')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(controller: _phoneController, decoration: const InputDecoration(labelText: 'เบอร์โทรศัพท์', border: OutlineInputBorder()), keyboardType: TextInputType.phone),
            const SizedBox(height: 15),
            TextField(controller: _passwordController, decoration: const InputDecoration(labelText: 'รหัสผ่าน', border: OutlineInputBorder()), obscureText: true),
            const SizedBox(height: 15),
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'ชื่อ-นามสกุล', border: OutlineInputBorder())),
            const SizedBox(height: 25),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _register,
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                    child: const Text('ลงทะเบียน', style: TextStyle(fontSize: 18)),
                  ),
            TextButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
              child: const Text('มีบัญชีอยู่แล้ว? เข้าสู่ระบบ'),
            )
          ],
        ),
      ),
    );
  }
}
