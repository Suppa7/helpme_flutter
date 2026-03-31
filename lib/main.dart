import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/models/medication.dart';
import 'package:test/models/medication_log.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
      theme: ThemeData(primarySwatch: Colors.green),
      navigatorKey:
          navigatorKey, // 🌟 สำคัญ: เพื่อให้ Notification เปลี่ยนหน้าได้
      initialRoute: initialRoute,
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => const HomeScreen(),
        '/med_detail': (context) =>
            const MedicationDetailScreen(), // 🌟 หน้ากดยืนยันกินยาด้วยตัวเอง
        '/alert_detail': (context) =>
            const AlertDetailScreen(), // 🌟 หน้าสำหรับญาติ กดยืนยันการแจ้งเตือน
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
    final logs = await DatabaseHelper.instance.getTodayMedicationLogs();
    
    // ยาที่เพิ่งกินไปใน schedule นี้วันนี้
    final takenTodayInThisSchedule = logs
        .where((log) => log.scheduleId == schedId && log.status == 'taken')
        .map((log) => log.medId)
        .toSet();

    // กรองเอาเฉพาะยาที่ amount > 0 และยังไม่ได้ทานในรอบวันนี้
    final meds = allMeds.where((m) => m.amount > 0 && !takenTodayInThisSchedule.contains(m.medId)).toList();
    
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

  void _toggleMedication(String medId) {
    setState(() {
      if (_takenMedIds.contains(medId)) {
        _takenMedIds.remove(medId);
      } else {
        _takenMedIds.add(medId);
      }
    });
  }

  Future<void> _processTakenMeds(Set<String> medIdsToProcess) async {
    if (medIdsToProcess.isEmpty) return;

    final now = DateTime.now();
    final parts = _scheduleTime.split(':');
    DateTime plannedTime = now;
    if (parts.length == 2) {
      int h = int.tryParse(parts[0]) ?? now.hour;
      int m = int.tryParse(parts[1]) ?? now.minute;
      plannedTime = DateTime(now.year, now.month, now.day, h, m);
    }

    for (var medId in medIdsToProcess) {
      final med = _meds.firstWhere((m) => m.medId == medId);
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

  // ยืนยันเฉพาะยาที่เลือก หรือ ยืนยันทั้งหมด
  Future<void> _confirmAllTaken() async {
    Set<String> medsToTake = {};
    if (_takenMedIds.isEmpty) {
      // ถ้าไม่ได้เลือกรายตัว ให้หมายถึงกินทั้งหมด
      medsToTake = _meds.map((m) => m.medId!).toSet();
    } else {
      // ถ้าเลือกบางตัว ให้ประมวลผลเฉพาะตัวที่เลือก
      medsToTake = _takenMedIds;
    }
    
    await _processTakenMeds(medsToTake);
    
    // ยกเลิกข้อความแจ้งเตือนทั้งหมดในรอบเวลานี้
    await NotificationService().cancelAllAlertsForSchedule(_scheduleId);

    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    }
  }

  Future<void> _snoozeAlert() async {
    // 🌟 ให้ผู้ใช้เลือกระยะเวลาเลื่อน
    final int? selectedMinutes = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.access_time_filled, color: Colors.orange, size: 28),
            SizedBox(width: 10),
            Text('เลือกระยะเวลาเลื่อน', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.timer, color: Colors.orange),
              title: const Text('30 นาที', style: TextStyle(fontSize: 18)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              tileColor: Colors.orange.shade50,
              onTap: () => Navigator.pop(ctx, 30),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.timer, color: Colors.deepOrange),
              title: const Text('1 ชั่วโมง', style: TextStyle(fontSize: 18)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              tileColor: Colors.orange.shade50,
              onTap: () => Navigator.pop(ctx, 60),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );

    if (selectedMinutes == null) return; // ผู้ใช้กดยกเลิก

    // 🌟 ถ้ามีการติ๊กถูกยาบางตัวไว้ โพรเซสตัวที่ถูกกินไปแล้วก่อน
    if (_takenMedIds.isNotEmpty) {
      await _processTakenMeds(_takenMedIds);
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String userName = prefs.getString('userName') ?? 'ผู้ใช้งาน';

    setState(() => _snoozeCount++);

    await NotificationService().snoozeScheduleAlerts(
      scheduleId: _scheduleId,
      timeString: _scheduleTime.isEmpty ? 'ไม่ระบุเวลา' : _scheduleTime,
      userName: userName,
      snoozeDurationMinutes: selectedMinutes,
    );
    if (mounted) {
      final label = selectedMinutes == 60 ? '1 ชั่วโมง' : '$selectedMinutes นาที';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('บันทึกยาที่ทานแล้ว และเลื่อนเวลาปลุกตัวที่เหลืออีก $label')),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    }
  }

  // 🌟 ข้ามมื้อนี้ (ลืมพกยา) — บันทึกสถานะ skipped โดยไม่แจ้งญาติ
  Future<void> _skipMeal() async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: Colors.red, size: 28),
            SizedBox(width: 10),
            Text('ยืนยันการข้ามมื้อนี้', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'ระบบจะบันทึกว่าคุณข้ามการทานยามื้อนี้ (เช่น ลืมพกยา)\nจะไม่มีการแจ้งเตือนไปยังญาติ',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('ยืนยันข้ามมื้อนี้'),
          ),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    final now = DateTime.now();
    final parts = _scheduleTime.split(':');
    DateTime plannedTime = now;
    if (parts.length == 2) {
      int h = int.tryParse(parts[0]) ?? now.hour;
      int m = int.tryParse(parts[1]) ?? now.minute;
      plannedTime = DateTime(now.year, now.month, now.day, h, m);
    }

    // บันทึก log สถานะ 'skipped' สำหรับยาทุกตัวที่ยังไม่ได้ทาน
    for (var med in _meds) {
      if (!_takenMedIds.contains(med.medId)) {
        final log = MedicationLog(
          userId: '',
          medId: med.medId ?? '',
          scheduleId: _scheduleId,
          medName: med.medName,
          plannedTimestamp: plannedTime,
          actualTimestamp: now,
          status: 'skipped',
          snoozeCount: _snoozeCount,
        );
        await DatabaseHelper.instance.insertMedicationLog(log);
      }
    }

    // ถ้ามียาที่ติ๊กทานไว้แล้ว ให้บันทึกเป็น taken ด้วย
    if (_takenMedIds.isNotEmpty) {
      await _processTakenMeds(_takenMedIds);
    }

    // ยกเลิกแจ้งเตือนทั้งหมดสำหรับรอบนี้ (ไม่ต้องแจ้งญาติเพราะเป็นความตั้งใจ)
    await NotificationService().cancelAllAlertsForSchedule(_scheduleId);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกการข้ามมื้อนี้เรียบร้อย')),
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
      backgroundColor: Colors.green.shade50,
      appBar: AppBar(
        title: Text('รอบเวลา ${_scheduleTime.isNotEmpty ? _scheduleTime : "ไม่ระบุ"}'),
        backgroundColor: Colors.green.shade800,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            width: double.infinity,
            color: Colors.green.shade100,
            child: Text(
              'เลือกทานเฉพาะยา หรือกดยืนยันทั้งหมดด้านล่าง',
              style: TextStyle(fontSize: 16, color: Colors.green.shade900, fontWeight: FontWeight.bold),
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
                          Icon(Icons.medication, size: 60, color: Colors.green.shade300),
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
                              const SizedBox(height: 3),
                              Text(
                                'เพิ่มเติม: ${(med.additionalInfo != null && med.additionalInfo!.isNotEmpty) ? med.additionalInfo! : '-'}',
                                style: TextStyle(fontSize: 14, color: Colors.blue.shade600),
                              ),
                            ],
                          ),
                        ),
                        isTaken
                            ? OutlinedButton.icon(
                                onPressed: () => _toggleMedication(med.medId!),
                                icon: const Icon(Icons.check_circle, color: Colors.green),
                                label: const Text('ยกเลิก'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.green,
                                  side: const BorderSide(color: Colors.green),
                                ),
                              )
                            : OutlinedButton(
                                onPressed: () => _toggleMedication(med.medId!),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.grey,
                                  side: const BorderSide(color: Colors.grey),
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
                  label: Text(
                    _takenMedIds.isEmpty 
                        ? 'รับประทานยาทั้งหมด' 
                        : (_takenMedIds.length == _meds.length ? 'ยืนยันการทานยาทั้งหมด' : 'ยืนยันทานเฉพาะยาที่เลือก'),
                    style: const TextStyle(fontSize: 20),
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
                    'เลื่อนเวลา',
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
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _skipMeal,
                  icon: const Icon(Icons.cancel_outlined, size: 28),
                  label: const Text(
                    'ข้ามมื้ออาหารนี้ (ลืมพกยา)',
                    style: TextStyle(fontSize: 20),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade400,
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

        // 🌟 ขอสิทธิ์แจ้งเตือนสำหรับ FCM และอัปเดต Token
        FirebaseMessaging messaging = FirebaseMessaging.instance;
        await messaging.requestPermission();
        String? fcmToken = await messaging.getToken();
        if (fcmToken != null) {
          await FirebaseFirestore.instance.collection('users').doc(uid).update({
            'fcmToken': fcmToken,
          });
        }

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
      backgroundColor: Colors.green.shade50,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Image.asset('assets/images/logo_helpme.png', height: 120),
              const SizedBox(height: 20),
              Text(
                'ยินดีต้อนรับ',
                style: TextStyle(
                  fontSize: 28, 
                  fontWeight: FontWeight.bold, 
                  color: Colors.green.shade800
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'เข้าสู่ระบบเพื่อจัดการ+12ทานยาของคุณ',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 30),
              
              // Auth Card
              Card(
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: _phoneController,
                        decoration: InputDecoration(
                          labelText: 'เบอร์โทรศัพท์',
                          prefixIcon: const Icon(Icons.phone, color: Colors.green),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15), 
                            borderSide: const BorderSide(color: Colors.green, width: 2)
                          ),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: 'รหัสผ่าน',
                          prefixIcon: const Icon(Icons.lock, color: Colors.green),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15), 
                            borderSide: const BorderSide(color: Colors.green, width: 2)
                          ),
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 25),
                      _isLoading
                          ? const CircularProgressIndicator()
                          : ElevatedButton(
                              onPressed: _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 55),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                elevation: 3,
                              ),
                              child: const Text('เข้าสู่ระบบ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pushReplacementNamed(context, '/register'),
                child: RichText(
                  text: TextSpan(
                    text: 'ยังไม่มีบัญชี? ',
                    style: const TextStyle(color: Colors.grey, fontSize: 16),
                    children: [
                      TextSpan(
                        text: 'สมัครสมาชิก',
                        style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold),
                      )
                    ],
                  ),
                ),
              )
            ],
          ),
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

      // 🌟 ขอสิทธิ์แจ้งเตือนสำหรับ FCM และขอ Token
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      String? fcmToken = await messaging.getToken();

      // บันทึกข้อมูลลง Firestore ใน Collection users
      final docRef = await FirebaseFirestore.instance.collection('users').add({
        'username': _nameController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
        'password': _passwordController.text.trim(),
        'userCode': userCode,
        'monitoredUserUids': [],
        'followerUids': [],
        'fcmToken': fcmToken ?? '',
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
      backgroundColor: Colors.green.shade50,
      appBar: AppBar(
        title: const Text(''), // ไม่แสดง title เพื่อให้ layout สะอาดตา
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.green.shade800,
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/logo_helpme.png', height: 100),
              const SizedBox(height: 15),
              Text(
                'สร้างบัญชีผู้ใช้ใหม่',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.green.shade800),
              ),
              const SizedBox(height: 25),
              
              Card(
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: _nameController, 
                        decoration: InputDecoration(
                          labelText: 'ชื่อ-นามสกุล', 
                          prefixIcon: const Icon(Icons.person, color: Colors.green),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15), 
                            borderSide: const BorderSide(color: Colors.green, width: 2)
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: _phoneController, 
                        decoration: InputDecoration(
                          labelText: 'เบอร์โทรศัพท์', 
                          prefixIcon: const Icon(Icons.phone, color: Colors.green),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15), 
                            borderSide: const BorderSide(color: Colors.green, width: 2)
                          ),
                        ), 
                        keyboardType: TextInputType.phone
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: _passwordController, 
                        decoration: InputDecoration(
                          labelText: 'รหัสผ่าน', 
                          prefixIcon: const Icon(Icons.lock, color: Colors.green),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15), 
                            borderSide: const BorderSide(color: Colors.green, width: 2)
                          ),
                        ), 
                        obscureText: true
                      ),
                      const SizedBox(height: 25),
                      _isLoading
                          ? const CircularProgressIndicator()
                          : ElevatedButton(
                              onPressed: _register,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 55),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                elevation: 3,
                              ),
                              child: const Text('ลงทะเบียน', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                child: RichText(
                  text: TextSpan(
                    text: 'มีบัญชีอยู่แล้ว? ',
                    style: const TextStyle(color: Colors.grey, fontSize: 16),
                    children: [
                      TextSpan(
                        text: 'เข้าสู่ระบบ',
                        style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold),
                      )
                    ],
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 🚨 หน้าการแจ้งเตือนสำหรับญาติ (รับทราบการขาดทานยา)
// ==========================================
class AlertDetailScreen extends StatefulWidget {
  const AlertDetailScreen({super.key});

  @override
  State<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends State<AlertDetailScreen> {
  String _alertId = '';
  Map<String, dynamic>? _alertData;
  bool _isLoading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)!.settings.arguments;
    if (args is String) {
      _alertId = args;
      _loadAlert(_alertId);
    }
  }

  Future<void> _loadAlert(String id) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('MissedMedicationAlerts').doc(id).get();
      if (doc.exists) {
        setState(() => _alertData = doc.data());
      }
    } catch (e) {
      debugPrint('Error loading alert: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _acknowledge() async {
    try {
      // 1. อัปเดตสถานะเป็น 'acknowledged'
      await FirebaseFirestore.instance.collection('MissedMedicationAlerts').doc(_alertId).update({
        'status': 'acknowledged'
      });

      // 2. ยกเลิก Notification ใน StatusBar แบบ Manual
      int schedIdInt = (_alertId.hashCode.abs() % 100000);
      await NotificationService().flutterLocalNotificationsPlugin.cancel(schedIdInt);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('คุณได้รับทราบการแจ้งเตือนแล้ว')));
        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_alertData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('การแจ้งเตือนผู้ป่วย')),
        body: const Center(child: Text('ไม่พบข้อมูลการแจ้งเตือนนี้ หรือถูกรับทราบไปแล้ว')),
      );
    }

    final String patientName = _alertData!['patientName'] ?? 'ผู้ป่วย';
    final String medNames = _alertData!['medNames'] ?? '';
    final String status = _alertData!['status'] ?? 'pending';

    String timeStr = '';
    if (_alertData!['plannedTime'] != null) {
      final d = (_alertData!['plannedTime'] as Timestamp).toDate();
      timeStr = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} น.';
    }

    return Scaffold(
      backgroundColor: Colors.red.shade50,
      appBar: AppBar(
        title: const Text('⚠️ แจ้งเตือน: ลืมทานยา'),
        backgroundColor: Colors.red.shade800,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 100, color: Colors.redAccent),
            const SizedBox(height: 20),
            Text(
              'ถึงเวลาทานยา แต่ผู้ป่วยยังไม่ได้ทาน!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red.shade900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow(Icons.person, 'ชื่อผู้ป่วย:', patientName),
                    const Divider(),
                    _buildInfoRow(Icons.access_time_filled, 'เวลาที่กำหนด:', timeStr),
                    const Divider(),
                    _buildInfoRow(Icons.medication, 'รายการยา:', medNames),
                  ],
                ),
              ),
            ),
            const Spacer(),
            if (status == 'pending')
              ElevatedButton.icon(
                onPressed: _acknowledge,
                icon: const Icon(Icons.check_circle_outline, size: 28),
                label: const Text('รับทราบการแจ้งเตือน', style: TextStyle(fontSize: 20)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(15)),
                child: const Text('รับทราบแล้ว', textAlign: TextAlign.center, style: TextStyle(color: Colors.green, fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false),
              child: const Text('กลับสู่หน้าหลัก', style: TextStyle(fontSize: 18, color: Colors.black54)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.red.shade300, size: 28),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: Colors.grey.shade700, fontSize: 16)),
                Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
