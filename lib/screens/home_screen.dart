import 'dart:async'; // สำหรับ StreamSubscription
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/schedule.dart';
import '../services/database_helper.dart';
import '../services/notification_service.dart';
import '../models/medication_log.dart';
import 'nearby_hospitals_screen.dart';
import 'schedule_medications_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  String _userName = '';
  String _relativeCode = '';
  List<ScheduleModel> _schedules = [];
  bool _isLoading = true;
  final Map<String, bool> _hasEmptyStock = {}; // เก็บสถานะว่าตารางนี้มียาหมดหรือไม่
  StreamSubscription? _alertSub; // ฟังแจ้งเตือนแบบเรียลไทม์
  Timer? _missedCheckTimer; // 🌟 Timer ตรวจสอบยาที่ลืมทานเป็นระยะ

  // state สำหรับหน้าประวัติ
  bool _showingOwnHistory = true;
  String? _selectedPatientUid;
  Future<List<Map<String, dynamic>>>? _historyFuture;

  // ข้อมูลติดตาม
  int _followerCount = 0;
  List<Map<String, dynamic>> _monitoredUsers = [];

  @override
  void initState() {
    super.initState();
    _historyFuture = DatabaseHelper.instance.getSharedTodayMedicationLogs();
    _checkDailyReset();
    _loadUserData();
    _refreshSchedules();
    // 🌟 ตรวจสอบและบันทึก 'missed' สำหรับยาที่ผ่านเวลาไปแล้วแต่ยังไม่ได้ทาน
    DatabaseHelper.instance.checkAndMarkMissedLogs();
    
    // 🌟 ตั้ง Timer ตรวจสอบทุก 1 นาที เพื่อสร้าง MissedMedicationAlerts
    // แม้ผู้ป่วยเปิดแอปก่อนถึงเวลายา ระบบจะคอยเช็คให้จนกว่าจะปิดแอป
    _missedCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      DatabaseHelper.instance.checkAndMarkMissedLogs();
    });
    
    // 🌟 ดักฟังการแจ้งเตือนจากญาติ (Real-time Firestore)
    _listenToRelativeAlerts();
  }

  void _listenToRelativeAlerts() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? uid = prefs.getString('uid');
    if (uid == null) return;

    _alertSub = FirebaseFirestore.instance.collection('MissedMedicationAlerts')
      .where('relativeUids', arrayContains: uid)
      .where('status', isEqualTo: 'pending')
      .snapshots().listen((snapshot) async {
        if (snapshot.docChanges.isEmpty) return;
        
        List<String> notified = prefs.getStringList('notifiedAlerts') ?? [];
        bool prefsUpdated = false;

        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final doc = change.doc;
            final data = doc.data();
            
            // ป้องกันการเด้งแจ้งเตือนซ้ำ (เช็กว่าเคยถูกแจ้งเตือน Alert ID นี้ในเครื่องนี้หรือยัง)
            if (data != null && !notified.contains(doc.id)) {
              
              // ตรวจสอบว่าเก่าเกินไปไหม (เช่น เกิน 1 วันแล้วข้ามไป)
              final createdAt = data['createdAt'] as Timestamp?;
              if (createdAt != null) {
                final diff = DateTime.now().difference(createdAt.toDate());
                if (diff.inDays >= 1) continue;
              }

              final patientName = data['patientName'] ?? 'ผู้ป่วย';
              final medNames = data['medNames'] ?? '';
              final plannedTime = data['plannedTime'] as Timestamp?;
              String timeStr = '';
              if (plannedTime != null) {
                final d = plannedTime.toDate();
                timeStr = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
              }
              
              // สั่งแสดง Local Notification ทันที
              await NotificationService().showRelativeAlert(
                alertId: doc.id,
                patientName: patientName,
                medNames: medNames,
                timeString: timeStr,
              );

              notified.add(doc.id);
              prefsUpdated = true;
            }
          }
        }
        if (prefsUpdated) {
          await prefs.setStringList('notifiedAlerts', notified);
        }
    });
  }

  @override
  void dispose() {
    _alertSub?.cancel(); // อย่าลืมยกเลิกฟัง
    _missedCheckTimer?.cancel(); // 🌟 ยกเลิก Timer ตรวจสอบยาที่ลืมทาน
    super.dispose();
  }

  // ==========================================
  // ลอจิกรีเซ็ตสถานะยาเมื่อขึ้นวันใหม่ (ปิดการลอจิกเก่าไปก่อนเพราะใช้ MedicationLogs ทีหลัง)
  // ==========================================
  Future<void> _checkDailyReset() async {
    // ไม่มี _checkDailyReset แล้ว
  }

  // ==========================================
  // ลอจิกโหลดข้อมูลผู้ใช้และสร้างรหัสญาติ
  // ==========================================
  Future<void> _loadUserData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? uid = prefs.getString('uid');
    
    String savedCode = '';
    String userName = prefs.getString('userName') ?? 'ผู้ใช้งาน';
    int followerCnt = 0;
    List<Map<String, dynamic>> monitored = [];

    if (uid != null && uid.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists) {
          savedCode = doc.data()?['userCode'] ?? '';
          userName = doc.data()?['username'] ?? userName;
          await prefs.setString('userName', userName);
          
          List<dynamic> followers = doc.data()?['followerUids'] ?? [];
          followerCnt = followers.length;
          
          List<dynamic> monitoredList = doc.data()?['monitoredUserUids'] ?? [];
          for (var mUid in monitoredList) {
             if (mUid is String) {
               final mDoc = await FirebaseFirestore.instance.collection('users').doc(mUid).get();
               if (mDoc.exists) {
                 monitored.add({
                   'uid': mUid,
                   'username': mDoc.data()?['username'] ?? 'ผู้ป่วย',
                 });
               }
             }
          }
        }
      } catch (e) {
        debugPrint('Error loading user code: $e');
      }
    }

    setState(() {
      _userName = userName;
      _relativeCode = savedCode;
      _followerCount = followerCnt;
      _monitoredUsers = monitored;
    });
  }

  Future<void> _refreshSchedules() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.getUserSchedules();
    
    final Map<String, bool> emptyStockMap = {};
    for (var sched in data) {
      final meds = await DatabaseHelper.instance.getMedicationsBySchedule(sched.scheduleId!);
      // เช็คว่าในตารางเวลานี้ มียาตัวไหนที่ amount <= 0 หรือไม่
      bool hasEmpty = meds.any((m) => m.amount <= 0);
      emptyStockMap[sched.scheduleId!] = hasEmpty;
    }

    setState(() {
      _schedules = data;
      _hasEmptyStock.clear();
      _hasEmptyStock.addAll(emptyStockMap);
      _isLoading = false;
    });
  }

  Future<void> _deleteSchedule(ScheduleModel sched) async {
    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('ยืนยันการลบ'),
            content: const Text('คุณต้องการลบเวลาแจ้งเตือนนี้ รวมถึงรายการยาทั้งหมดที่อยู่ในเวลานี้ใช่หรือไม่?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ยกเลิก'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('ลบ', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      await NotificationService().cancelAllAlertsForSchedule(sched.scheduleId!);
      await DatabaseHelper.instance.deleteSchedule(sched.scheduleId!);
      _refreshSchedules();
    }
  }

  // ==========================================
  // Dialog เพิ่มตารางเวลา
  // ==========================================
  Future<void> _showAddScheduleDialog() async {
    TimeOfDay selectedTime = TimeOfDay.now();
    
    // ตั้งค่า default
    String selectedMeal = 'morning';
    String selectedInstruction = 'after_meal';

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.access_time, color: Colors.green, size: 30),
                  SizedBox(width: 10),
                  Text(
                    'เพิ่มเวลาแจ้งเตือน',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedMeal,
                      decoration: InputDecoration(
                        labelText: 'มื้ออาหาร',
                        prefixIcon: const Icon(Icons.restaurant, color: Colors.green),
                        filled: true,
                        fillColor: Colors.green.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'morning', child: Text('เช้า')),
                        DropdownMenuItem(value: 'lunch', child: Text('กลางวัน')),
                        DropdownMenuItem(value: 'dinner', child: Text('เย็น')),
                        DropdownMenuItem(value: 'before_bed', child: Text('ก่อนนอน')),
                      ],
                      onChanged: (val) => setDialogState(() => selectedMeal = val!),
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      initialValue: selectedInstruction,
                      decoration: InputDecoration(
                        labelText: 'เงื่อนไขการทาน',
                        prefixIcon: const Icon(Icons.info_outline, color: Colors.green),
                        filled: true,
                        fillColor: Colors.green.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'before_meal', child: Text('ก่อนอาหาร')),
                        DropdownMenuItem(value: 'after_meal', child: Text('หลังอาหาร')),
                      ],
                      onChanged: (val) => setDialogState(() => selectedInstruction = val!),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.schedule, color: Colors.green),
                              const SizedBox(width: 10),
                              Text(
                                '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')} น.',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade900
                                ),
                              ),
                            ],
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              final TimeOfDay? picked = await showTimePicker(
                                context: context,
                                initialTime: selectedTime,
                              );
                              if (picked != null) {
                                setDialogState(() => selectedTime = picked);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                            ),
                            child: const Text('เปลี่ยนเวลา', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'ยกเลิก',
                    style: TextStyle(color: Colors.red, fontSize: 18),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    String formattedTime =
                        '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';

                    bool isDuplicate = _schedules.any((s) =>
                        s.meal == selectedMeal && s.time == formattedTime);

                    if (isDuplicate) {
                      if (!context.mounted) return;
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('ไม่สามารถบันทึกได้'),
                          content: const Text('คุณมีเวลาแจ้งเตือนในมื้ออาหารและเวลานี้อยู่แล้ว'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('ตกลง'),
                            ),
                          ],
                        ),
                      );
                      return;
                    }

                    final newSchedule = ScheduleModel(
                      userId: '', // เดี๋ยว DatabaseHelper เติมให้
                      meal: selectedMeal,
                      time: formattedTime,
                      instruction: selectedInstruction,
                      days: ['Everyday'], 
                      isActive: true
                    );
                    
                    await DatabaseHelper.instance.insertSchedule(newSchedule);

                    if (!context.mounted) return;
                    Navigator.pop(context);
                    _refreshSchedules();
                  },
                  child: const Text('บันทึก', style: TextStyle(fontSize: 18)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================
  // Dialog แก้ไขตารางเวลา
  // ==========================================
  Future<void> _showEditScheduleDialog(ScheduleModel sched) async {
    final timeParts = sched.time.split(':');
    TimeOfDay selectedTime = TimeOfDay(
      hour: int.tryParse(timeParts[0]) ?? 8, 
      minute: int.tryParse(timeParts[1]) ?? 0
    );
    
    // ตั้งค่าเริ่มต้นจากของเดิม
    String selectedMeal = sched.meal;
    String selectedInstruction = sched.instruction;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.edit_calendar, color: Colors.green, size: 30),
                  SizedBox(width: 10),
                  Text(
                    'แก้ไขเวลาแจ้งเตือน',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedMeal,
                      decoration: InputDecoration(
                        labelText: 'มื้ออาหาร',
                        prefixIcon: const Icon(Icons.restaurant, color: Colors.green),
                        filled: true,
                        fillColor: Colors.green.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'morning', child: Text('เช้า')),
                        DropdownMenuItem(value: 'lunch', child: Text('กลางวัน')),
                        DropdownMenuItem(value: 'dinner', child: Text('เย็น')),
                        DropdownMenuItem(value: 'before_bed', child: Text('ก่อนนอน')),
                      ],
                      onChanged: (val) => setDialogState(() => selectedMeal = val!),
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      initialValue: selectedInstruction,
                      decoration: InputDecoration(
                        labelText: 'เงื่อนไขการทาน',
                        prefixIcon: const Icon(Icons.info_outline, color: Colors.green),
                        filled: true,
                        fillColor: Colors.green.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'before_meal', child: Text('ก่อนอาหาร')),
                        DropdownMenuItem(value: 'after_meal', child: Text('หลังอาหาร')),
                      ],
                      onChanged: (val) => setDialogState(() => selectedInstruction = val!),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.schedule, color: Colors.green),
                              const SizedBox(width: 10),
                              Text(
                                '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')} น.',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade900
                                ),
                              ),
                            ],
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              final TimeOfDay? picked = await showTimePicker(
                                context: context,
                                initialTime: selectedTime,
                              );
                              if (picked != null) {
                                setDialogState(() => selectedTime = picked);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                            ),
                            child: const Text('เปลี่ยนเวลา', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'ยกเลิก',
                    style: TextStyle(color: Colors.red, fontSize: 18),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    String formattedTime =
                        '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';

                    bool isDuplicate = _schedules.any((s) =>
                        s.scheduleId != sched.scheduleId &&
                        s.meal == selectedMeal &&
                        s.time == formattedTime);

                    if (isDuplicate) {
                      if (!context.mounted) return;
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('ไม่สามารถบันทึกได้'),
                          content: const Text('คุณมีเวลาแจ้งเตือนในมื้ออาหารและเวลานี้อยู่แล้ว'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('ตกลง'),
                            ),
                          ],
                        ),
                      );
                      return;
                    }

                    final updatedSchedule = ScheduleModel(
                      scheduleId: sched.scheduleId,
                      userId: sched.userId,
                      meal: selectedMeal,
                      time: formattedTime,
                      instruction: selectedInstruction,
                      days: sched.days, 
                      isActive: sched.isActive
                    );
                    
                    await DatabaseHelper.instance.updateSchedule(updatedSchedule);

                    if (!context.mounted) return;
                    Navigator.pop(context);
                    _refreshSchedules();
                  },
                  child: const Text('บันทึก', style: TextStyle(fontSize: 18)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================
  // 1. หน้าตารางเวลา
  // ==========================================
  Widget _buildScheduleView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton.icon(
            onPressed: _showAddScheduleDialog,
            icon: const Icon(Icons.add_alarm, size: 32),
            label: const Text(
              'เพิ่มเวลาแจ้งเตือน',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 70),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              elevation: 5,
            ),
          ),
        ),

        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _schedules.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.more_time,
                        size: 80,
                        color: Colors.green.shade200,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'ยังไม่มีเวลาแจ้งเตือน',
                        style: TextStyle(fontSize: 20, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _schedules.length,
                  itemBuilder: (context, index) {
                    final sched = _schedules[index];
                    
                    String mealText = sched.meal == 'morning' ? 'เช้า' :
                                      sched.meal == 'lunch' ? 'กลางวัน' :
                                      sched.meal == 'dinner' ? 'เย็น' : 'ก่อนนอน';
                                      
                    String instructionText = sched.instruction == 'before_meal' ? 'ก่อนอาหาร' :
                                             sched.instruction == 'after_meal' ? 'หลังอาหาร' : 'ไม่ระบุ';

                    IconData mealIcon;
                    switch (sched.meal) {
                      case 'morning':
                        mealIcon = Icons.wb_sunny;
                        break;
                      case 'lunch':
                        mealIcon = Icons.wb_cloudy; // หรือจะใช้ Icons.restaurant
                        break;
                      case 'dinner':
                        mealIcon = Icons.nights_stay;
                        break;
                      case 'before_bed':
                        mealIcon = Icons.bedtime;
                        break;
                      default:
                        mealIcon = Icons.access_time_filled;
                    }

                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        side: BorderSide(
                          color: Colors.green.shade200,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(15),
                        onTap: () {
                          // ไปหน้ายาในตารางเวลานี้
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ScheduleMedicationsScreen(schedule: sched),
                            ),
                          ).then((_) => _refreshSchedules()); // refresh in case deleted/updated
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: Icon(
                                  mealIcon,
                                  color: Colors.green,
                                  size: 35,
                                ),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          sched.time,
                                          style: TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green.shade900,
                                          ),
                                        ),
                                        if (_hasEmptyStock[sched.scheduleId] == true) ...[
                                          const SizedBox(width: 8),
                                          const Tooltip(
                                            message: 'มียาที่หมดแล้ว',
                                            child: Icon(Icons.warning, color: Colors.red),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'มื้อ: $mealText ($instructionText)',
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  color: Colors.orange,
                                  size: 30,
                                ),
                                onPressed: () => _showEditScheduleDialog(sched),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                  size: 30,
                                ),
                                onPressed: () => _deleteSchedule(sched),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: Colors.grey,
                                size: 30,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ==========================================
  // 2. หน้าประวัติการทานยา (แสดงรวมของตัวเองและคนที่ติดตามอยู่)
  // ==========================================
  Widget _buildHistoryView() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.green.shade50,
          child: const Text(
            'ประวัติการทานยาวันนี้',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _historyFuture ?? DatabaseHelper.instance.getSharedTodayMedicationLogs(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}'));
              }
              final fullList = snapshot.data ?? <Map<String, dynamic>>[];
              
              if (fullList.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history_toggle_off,
                        size: 80,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'ไม่พบประวัติการทานยา',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              final myLogMap = fullList.isNotEmpty ? fullList[0] : null;
              final otherLogs = fullList.length > 1 ? List<Map<String, dynamic>>.from(fullList.sublist(1)) : <Map<String, dynamic>>[];

              return Column(
                children: [
                  // เมนูเลือกประวัติของฉันหรือผู้ป่วยอื่น
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ChoiceChip(
                          label: Text('ประวัติของฉัน', style: TextStyle(color: _showingOwnHistory ? Colors.white : Colors.green.shade800)),
                          labelPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                          selected: _showingOwnHistory,
                          selectedColor: Colors.green.shade700,
                          backgroundColor: Colors.green.shade50,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.green.shade700)),
                          onSelected: (val) {
                            setState(() {
                              _showingOwnHistory = true;
                            });
                          },
                        ),
                        const SizedBox(width: 10),
                        ChoiceChip(
                          label: Text('ผู้ป่วยอื่น', style: TextStyle(color: !_showingOwnHistory ? Colors.white : Colors.orange.shade800)),
                          labelPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                          selected: !_showingOwnHistory,
                          selectedColor: Colors.orange.shade700,
                          backgroundColor: Colors.orange.shade50,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.orange.shade700)),
                          onSelected: (val) {
                            if (otherLogs.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('คุณยังไม่ได้ติดตามผู้ป่วยคนใด')),
                              );
                              return;
                            }
                            setState(() {
                              _showingOwnHistory = false;
                              // ถ้ายังไม่ได้เลือกให้ใช้พรีเซตคนแรกเป็นค่าตั้งต้น
                              if ((_selectedPatientUid == null || !otherLogs.any((element) => element['uid'] == _selectedPatientUid)) && otherLogs.isNotEmpty) {
                                _selectedPatientUid = otherLogs[0]['uid'];
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                  // Dropdown ถ้าเลือกผู้ป่วยอื่น (กรณีที่มี > 0 หรือ > 1) 
                  if (!_showingOwnHistory && otherLogs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: 'เลือกผู้ป่วย', 
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                          prefixIcon: const Icon(Icons.people, color: Colors.orange),
                        ),
                        value: _selectedPatientUid,
                        items: otherLogs.map((item) {
                          return DropdownMenuItem<String>(
                            value: item['uid'],
                            child: Text(item['username']),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedPatientUid = val;
                          });
                        },
                      ),
                    ),

                  // ส่วนแสดงผลประวัติ
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        Map<String, dynamic>? selectedItem;
                        if (_showingOwnHistory) {
                          selectedItem = myLogMap;
                        } else {
                          // ให้แน่ใจว่าได้คนจากลิสต์ที่เลือก
                          selectedItem = otherLogs.firstWhere(
                            (el) => el['uid'] == _selectedPatientUid,
                            orElse: () => otherLogs.first,
                          );
                        }

                        if (selectedItem == null) {
                          return const Center(child: Text('ไม่พบข้อมูล'));
                        }

                        final String username = selectedItem['username'];
                        final List<MedicationLog> logs = selectedItem['logs'];
                        final bool isMe = _showingOwnHistory;

                        return ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Row(
                                children: [
                                  Icon(isMe ? Icons.person : Icons.people_outline, color: isMe ? Colors.green : Colors.orange),
                                  const SizedBox(width: 8),
                                  Text(
                                    isMe ? 'ประวัติของฉัน ($username)' : 'ประวัติของ $username',
                                    style: TextStyle(
                                      fontSize: 18, 
                                      fontWeight: FontWeight.bold,
                                      color: isMe ? Colors.green.shade800 : Colors.orange.shade800
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (logs.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 32.0, bottom: 16.0),
                                child: Text('ยังไม่มีประวัติการทานยาวันนี้', style: TextStyle(color: Colors.grey.shade600)),
                              )
                            else
                              ...logs.map((log) {
                                String statusText = '';
                                Color statusColor = Colors.grey;
                                IconData statusIcon = Icons.help_outline;

                                if (log.status == 'taken') {
                                  statusText = 'ทานแล้ว';
                                  statusColor = Colors.green;
                                  statusIcon = Icons.check_circle;
                                } else if (log.status == 'skipped') {
                                  statusText = 'ข้าม';
                                  statusColor = Colors.orange;
                                  statusIcon = Icons.skip_next;
                                } else if (log.status == 'missed') {
                                  statusText = 'เลยเวลา/ไม่ทาน';
                                  statusColor = Colors.red;
                                  statusIcon = Icons.cancel;
                                }

                                String actualTimeStr = '${(log.actualTimestamp ?? log.plannedTimestamp).hour.toString().padLeft(2, '0')}:${(log.actualTimestamp ?? log.plannedTimestamp).minute.toString().padLeft(2, '0')} น.';
                                String plannedTimeStr = '${log.plannedTimestamp.hour.toString().padLeft(2, '0')}:${log.plannedTimestamp.minute.toString().padLeft(2, '0')} น.';

                                return Card(
                                  elevation: 2,
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                    side: BorderSide(color: statusColor.withValues(alpha: 0.5)),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.all(16),
                                    leading: Icon(statusIcon, color: statusColor, size: 40),
                                    title: Text(
                                      log.medName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 4),
                                        Text('แผน: $plannedTimeStr'),
                                        Text('เวลาบันทึก: $actualTimeStr', style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    trailing: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        statusText,
                                        style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            const SizedBox(height: 16),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ==========================================
  // ฟังก์ชันหาญาติและเพิ่มการเชื่อมต่อ
  // ==========================================
  Future<void> _connectToRelative(String code) async {
    if (code.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกรหัสเชื่อมต่อ')),
      );
      return;
    }
    if (code.trim() == _relativeCode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเชื่อมต่อกับตัวเองได้')),
      );
      return;
    }

    try {
      // ค้นหาผู้ใช้เป้าหมายที่รหัสตรงกัน
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('userCode', isEqualTo: code.trim())
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่พบผู้ใช้ที่ใช้รหัสนี้')),
        );
        return;
      }

      final targetDoc = query.docs.first;
      final targetUid = targetDoc.id;

      SharedPreferences prefs = await SharedPreferences.getInstance();
      final myUid = prefs.getString('uid');

      if (myUid == null) return;

      // ก่อนเพิ่มเป้าหมาย เช็ค limit เราก่อน
      final myDoc = await FirebaseFirestore.instance.collection('users').doc(myUid).get();
      List<dynamic> myMonitored = myDoc.data()?['monitoredUserUids'] ?? [];
      // ตรวจสอบว่าเคยติดตามอยู่แล้วหรือไม่
      if (myMonitored.contains(targetUid)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('คุณติดตามผู้ป่วยคนนี้อยู่แล้ว')),
        );
        return;
      }
      if (myMonitored.length >= 2) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('คุณติดตามผู้ป่วยครบ 2 คนแล้ว ไม่สามารถติดตามเพิ่มได้')),
        );
        return;
      }

      // เช็ค limit เป้าหมาย
      List<dynamic> targetFollowers = targetDoc.data()['followerUids'] ?? [];
      if (targetFollowers.length >= 2) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ผู้ป่วยท่านนี้มีญาติติดตามครบ 2 คนแล้ว')),
        );
        return;
      }

      // เพิ่มเป้าหมายใน monitoredUserUids ของเรา (เพื่อติดตามสถานะยาของ target)
      await FirebaseFirestore.instance.collection('users').doc(myUid).update({
        'monitoredUserUids': FieldValue.arrayUnion([targetUid])
      });
      // เพิ่มเราใน followerUids ของเป้าหมาย (ให้เค้ารู้ว่าเรากำลังติดตามอยู่)
      await FirebaseFirestore.instance.collection('users').doc(targetUid).update({
        'followerUids': FieldValue.arrayUnion([myUid])
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เชื่อมต่อกับคุณ "${targetDoc.data()['username']}" สำเร็จ!')),
      );

      _loadUserData();
      _historyFuture = DatabaseHelper.instance.getSharedTodayMedicationLogs();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาดในการเชื่อมต่อ: $e')),
      );
    }
  }

  // ฟังก์ชันยกเลิกการติดตาม
  Future<void> _unfollowPatient(String targetUid, String targetName) async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยกเลิกการติดตาม'),
        content: Text('คุณต้องการยกเลิกการติดตามข้อมูลของ "$targetName" ใช่หรือไม่?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ไม่ใช่')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('ใช่, ยกเลิก', style: TextStyle(color: Colors.red))
          ),
        ]
      )
    ) ?? false;
    
    if (!confirm) return;

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      final myUid = prefs.getString('uid');
      if (myUid == null) return;

      await FirebaseFirestore.instance.collection('users').doc(myUid).update({
        'monitoredUserUids': FieldValue.arrayRemove([targetUid])
      });
      await FirebaseFirestore.instance.collection('users').doc(targetUid).update({
        'followerUids': FieldValue.arrayRemove([myUid])
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ยกเลิกการติดตาม "$targetName" แล้ว')),
      );
      
      _loadUserData();
      _historyFuture = DatabaseHelper.instance.getSharedTodayMedicationLogs();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
      );
    }
  }

  // ==========================================
  // 3. หน้าโปรไฟล์ (เพิ่ม Card เปลี่ยนชื่อ และ รหัสญาติ)
  // ==========================================
  Widget _buildProfileView() {
    TextEditingController nameController = TextEditingController(
      text: _userName,
    );
    TextEditingController relativeController = TextEditingController();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 🌟 Card เปลี่ยนชื่อ
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.person, color: Colors.green),
                    SizedBox(width: 10),
                    Text(
                      'ข้อมูลผู้ใช้งาน',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อผู้ใช้งาน',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      SharedPreferences prefs =
                          await SharedPreferences.getInstance();
                      await prefs.setString('userName', nameController.text);
                      setState(() {
                        _userName = nameController.text;
                      });
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('บันทึกชื่อเรียบร้อยแล้ว'),
                        ),
                      );
                    },
                    child: const Text(
                      'บันทึกการเปลี่ยนแปลง',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 🌟 Card ดูรหัสญาติ
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.family_restroom, color: Colors.orange),
                    SizedBox(width: 10),
                    Text(
                      'รหัสเชื่อมต่อสำหรับญาติ',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'ให้ญาตินำรหัสนี้ไปกรอกในแอปบนเครื่องของญาติ เพื่อรับการแจ้งเตือนหากลืมทานยา (สูงสุดบัญชีละ 2 คน)',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 15),
                if (_followerCount >= 2)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: const Text(
                      'จำนวนญาติเต็มแล้ว',
                      style: TextStyle(fontSize: 18, color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 20,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _relativeCode,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 3,
                            color: Colors.orange.shade800,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.copy,
                            color: Colors.orange,
                            size: 30,
                          ),
                          onPressed: () {
                            // ฟังก์ชันก๊อปปี้ลง Clipboard
                            Clipboard.setData(ClipboardData(text: _relativeCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('คัดลอกรหัสเชื่อมต่อแล้ว!'),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        
        // 🌟 Card กรอกรหัสเชื่อมต่อผู้ป่วย
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.link, color: Colors.green),
                    SizedBox(width: 10),
                    Text(
                      'เชื่อมต่อเพื่อติดตามการทานยา',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'กรอกรหัสเชื่อมต่อของผู้ป่วยที่คุณต้องการติดตามสถานะการทานยา',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: relativeController,
                  decoration: const InputDecoration(
                    labelText: 'รหัสผู้ป่วย/ญาติ 6 หลัก',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_search),
                  ),
                  maxLength: 6,
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      _connectToRelative(relativeController.text);
                      relativeController.clear();
                    },
                    child: const Text(
                      'เชื่อมต่อ',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 🌟 Card รายชื่อผู้ป่วยที่ติดตาม
        if (_monitoredUsers.isNotEmpty) ...[
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.people, color: Colors.blue),
                      SizedBox(width: 10),
                      Text(
                        'ผู้ป่วยที่กำลังติดตาม',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ..._monitoredUsers.map((user) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.person, color: Colors.white)),
                    title: Text(user['username'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: TextButton(
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () => _unfollowPatient(user['uid'].toString(), user['username'].toString()),
                      child: const Text('ยกเลิกติดตาม'),
                    ),
                  )).toList(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // 🌟 Card ค้นหาโรงพยาบาลใกล้เคียง
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const NearbyHospitalsScreen()),
              );
            },
            borderRadius: BorderRadius.circular(15),
            child: const Padding(
              padding: EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(Icons.local_hospital, color: Colors.green, size: 40),
                  SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ค้นหาโรงพยาบาลใกล้ฉัน',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        Text(
                          'อ้างอิงจากแผนที่รัศมี 10 กม.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, color: Colors.grey),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildScheduleView(),
      _buildHistoryView(),
      _buildProfileView(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/images/logo_helpme.png', height: 40),
            const SizedBox(width: 10),
            Expanded(child: Text('สวัสดีคุณ $_userName', overflow: TextOverflow.ellipsis)),
          ],
        ),
        backgroundColor: Colors.green.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
            // พอสลับมาหน้าประวัติ ให้รีเฟรชข้อมูลล่าสุดสักรอบ
            if (index == 1) {
              _historyFuture = DatabaseHelper.instance.getSharedTodayMedicationLogs();
            }
          });
        },
        selectedItemColor: Colors.green.shade800,
        unselectedItemColor: Colors.grey,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month, size: 28),
            label: 'ตารางยา',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history, size: 28),
            label: 'ประวัติ',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person, size: 28),
            label: 'โปรไฟล์',
          ),
        ],
      ),
    );
  }
} // ปิดคลาส _HomeScreenState
