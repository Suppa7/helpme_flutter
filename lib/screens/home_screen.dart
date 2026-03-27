import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/schedule.dart';
import '../services/database_helper.dart';
import '../services/notification_service.dart';
import '../models/medication_log.dart';
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

  @override
  void initState() {
    super.initState();
    _checkDailyReset();
    _loadUserData();
    _refreshSchedules();
    // 🌟 ตรวจสอบและบันทึก 'missed' สำหรับยาที่ผ่านเวลาไปแล้วแต่ยังไม่ได้ทาน
    DatabaseHelper.instance.checkAndMarkMissedLogs();
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

    if (uid != null && uid.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (doc.exists) {
          savedCode = doc.data()?['userCode'] ?? '';
          userName = doc.data()?['username'] ?? userName;
          await prefs.setString('userName', userName);
        }
      } catch (e) {
        print('Error loading user code: $e');
      }
    }

    setState(() {
      _userName = userName;
      _relativeCode = savedCode;
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
    String _selectedMeal = 'morning';
    String _selectedInstruction = 'after_meal';

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
                  Icon(Icons.access_time, color: Colors.blue, size: 30),
                  SizedBox(width: 10),
                  Text(
                    'เพิ่มเวลาแจ้งเตือน',
                    style: TextStyle(
                      color: Colors.blue,
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
                      value: _selectedMeal,
                      decoration: const InputDecoration(labelText: 'มื้ออาหาร', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'morning', child: Text('เช้า')),
                        DropdownMenuItem(value: 'lunch', child: Text('กลางวัน')),
                        DropdownMenuItem(value: 'dinner', child: Text('เย็น')),
                        DropdownMenuItem(value: 'before_bed', child: Text('ก่อนนอน')),
                      ],
                      onChanged: (val) => setDialogState(() => _selectedMeal = val!),
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      value: _selectedInstruction,
                      decoration: const InputDecoration(labelText: 'เงื่อนไข', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'before_meal', child: Text('ก่อนอาหาร')),
                        DropdownMenuItem(value: 'after_meal', child: Text('หลังอาหาร')),
                      ],
                      onChanged: (val) => setDialogState(() => _selectedInstruction = val!),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'เวลา: ${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')} น.',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final TimeOfDay? picked = await showTimePicker(
                              context: context,
                              initialTime: selectedTime,
                            );
                            if (picked != null) {
                              setDialogState(() => selectedTime = picked);
                            }
                          },
                          icon: const Icon(Icons.access_time),
                          label: const Text('ตั้งเวลา'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade100,
                            foregroundColor: Colors.blue.shade900,
                          ),
                        ),
                      ],
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
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    String formattedTime =
                        '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';

                    final newSchedule = ScheduleModel(
                      userId: '', // เดี๋ยว DatabaseHelper เติมให้
                      meal: _selectedMeal,
                      time: formattedTime,
                      instruction: _selectedInstruction,
                      days: ['Everyday'], 
                      isActive: true
                    );
                    
                    await DatabaseHelper.instance.insertSchedule(newSchedule);

                    if (mounted) Navigator.pop(context);
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
    String _selectedMeal = sched.meal;
    String _selectedInstruction = sched.instruction;

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
                  Icon(Icons.edit_calendar, color: Colors.blue, size: 30),
                  SizedBox(width: 10),
                  Text(
                    'แก้ไขเวลาแจ้งเตือน',
                    style: TextStyle(
                      color: Colors.blue,
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
                      value: _selectedMeal,
                      decoration: const InputDecoration(labelText: 'มื้ออาหาร', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'morning', child: Text('เช้า')),
                        DropdownMenuItem(value: 'lunch', child: Text('กลางวัน')),
                        DropdownMenuItem(value: 'dinner', child: Text('เย็น')),
                        DropdownMenuItem(value: 'before_bed', child: Text('ก่อนนอน')),
                      ],
                      onChanged: (val) => setDialogState(() => _selectedMeal = val!),
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      value: _selectedInstruction,
                      decoration: const InputDecoration(labelText: 'เงื่อนไข', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'before_meal', child: Text('ก่อนอาหาร')),
                        DropdownMenuItem(value: 'after_meal', child: Text('หลังอาหาร')),
                      ],
                      onChanged: (val) => setDialogState(() => _selectedInstruction = val!),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'เวลา: ${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')} น.',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final TimeOfDay? picked = await showTimePicker(
                              context: context,
                              initialTime: selectedTime,
                            );
                            if (picked != null) {
                              setDialogState(() => selectedTime = picked);
                            }
                          },
                          icon: const Icon(Icons.access_time),
                          label: const Text('ตั้งเวลา'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade100,
                            foregroundColor: Colors.blue.shade900,
                          ),
                        ),
                      ],
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
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    String formattedTime =
                        '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';

                    final updatedSchedule = ScheduleModel(
                      scheduleId: sched.scheduleId,
                      userId: sched.userId,
                      meal: _selectedMeal,
                      time: formattedTime,
                      instruction: _selectedInstruction,
                      days: sched.days, 
                      isActive: sched.isActive
                    );
                    
                    await DatabaseHelper.instance.updateSchedule(updatedSchedule);

                    if (mounted) Navigator.pop(context);
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
              backgroundColor: Colors.blue.shade700,
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
                        color: Colors.blue.shade200,
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
                          color: Colors.blue.shade200,
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
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: Icon(
                                  mealIcon,
                                  color: Colors.blue,
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
                                            color: Colors.blue.shade900,
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
  // 2. หน้าประวัติการทานยา (แสดงเฉพาะยาที่กินแล้ว)
  // ==========================================
  Widget _buildHistoryView() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.blue.shade50,
          child: const Text(
            'ประวัติการทานยาวันนี้',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: FutureBuilder<List<MedicationLog>>(
            future: DatabaseHelper.instance.getTodayMedicationLogs(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}'));
              }
              final historyList = snapshot.data ?? [];
              
              if (historyList.isEmpty) {
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
                        'ยังไม่มีประวัติการทานยาวันนี้',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: historyList.length,
                itemBuilder: (context, index) {
                  final log = historyList[index];
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

                  String actualTimeStr = '${log.actualTimestamp?.hour.toString().padLeft(2, '0')}:${log.actualTimestamp?.minute.toString().padLeft(2, '0')} น.';
                  String plannedTimeStr = '${log.plannedTimestamp.hour.toString().padLeft(2, '0')}:${log.plannedTimestamp.minute.toString().padLeft(2, '0')} น.';

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(color: statusColor.withOpacity(0.5)),
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
                          Text('เวลาทานจริง: $actualTimeStr', style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          statusText,
                          style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  );
                },
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

      // เพิ่มเป้าหมายใน monitoredUserUids ของเรา (เพื่อติดตามสถานะยาของ target)
      await FirebaseFirestore.instance.collection('users').doc(myUid).update({
        'monitoredUserUids': FieldValue.arrayUnion([targetUid])
      });
      // เพิ่มเราใน followerUids ของเป้าหมาย (ให้เค้ารู้ว่าเรากำลังติดตามอยู่)
      await FirebaseFirestore.instance.collection('users').doc(targetUid).update({
        'followerUids': FieldValue.arrayUnion([myUid])
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เชื่อมต่อกับคุณ "${targetDoc.data()['username']}" สำเร็จ!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาดในการเชื่อมต่อ: $e')),
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
                    Icon(Icons.person, color: Colors.blue),
                    SizedBox(width: 10),
                    Text(
                      'ข้อมูลผู้ใช้งาน',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
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
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      SharedPreferences prefs =
                          await SharedPreferences.getInstance();
                      await prefs.setString('userName', nameController.text);
                      setState(() {
                        _userName = nameController.text;
                      });
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
                  'ให้ญาตินำรหัสนี้ไปกรอกในแอปบนเครื่องของญาติ เพื่อรับการแจ้งเตือนหากลืมทานยา',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 15),
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
        title: Text('สวัสดีคุณ $_userName'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: Colors.blue.shade800,
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
