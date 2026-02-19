import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/medication.dart';
import '../services/database_helper.dart';
import '../services/notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  String _userName = '';
  String _relativeCode = '';
  List<Medication> _medications =
      []; // ให้แน่ใจว่า import Medication model แล้ว
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkDailyReset();
    _loadUserData();
    _refreshMedications();
  }

  // ==========================================
  // ลอจิกรีเซ็ตสถานะยาเมื่อขึ้นวันใหม่
  // ==========================================
  Future<void> _checkDailyReset() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    // ดึงวันที่ปัจจุบัน (เช่น 2026-02-17)
    String today = DateTime.now().toIso8601String().split('T')[0];
    String? lastOpenDate = prefs.getString('lastOpenDate');

    // ถ้าวันที่เปิดแอป ไม่ตรงกับวันที่บันทึกไว้ล่าสุด (แปลว่าขึ้นวันใหม่)
    if (lastOpenDate != today) {
      await DatabaseHelper.instance
          .resetAllPillsStatus(); // สั่งรีเซ็ตสถานะยาทุกตัวเป็น 0
      await prefs.setString('lastOpenDate', today); // อัปเดตวันที่ล่าสุด
    }
  }

  // ==========================================
  // ลอจิกโหลดข้อมูลผู้ใช้และสร้างรหัสญาติ
  // ==========================================
  Future<void> _loadUserData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedCode = prefs.getString('relativeCode');

    // ถ้าย้งไม่มีรหัสญาติ ให้สุ่มรหัส 10 หลัก
    if (savedCode == null) {
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      Random rnd = Random();
      savedCode = String.fromCharCodes(
        Iterable.generate(
          10,
          (_) => chars.codeUnitAt(rnd.nextInt(chars.length)),
        ),
      );
      await prefs.setString('relativeCode', savedCode);
    }
    setState(() {
      _userName = prefs.getString('userName') ?? 'ผู้ใช้งาน';
      _relativeCode = savedCode!;
    });
  }

  Future<void> _refreshMedications() async {
    setState(() => _isLoading = true);
    // ให้แน่ใจว่า import DatabaseHelper แล้ว
    final data = await DatabaseHelper.instance.getPills();
    setState(() {
      _medications = data;
      _isLoading = false;
    });
  }

  Future<void> _deleteMedication(int id) async {
    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('ยืนยันการลบ'),
            content: const Text('คุณต้องการลบรายการยานี้ออกจากระบบใช่หรือไม่?'),
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
      await DatabaseHelper.instance.deletePill(id);
      _refreshMedications();
    }
  }

  // ==========================================
  // Dialog เพิ่มยา
  // ==========================================
  Future<void> _showAddMedicationDialog() async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController descController = TextEditingController();
    final TextEditingController amountController = TextEditingController();
    TimeOfDay selectedTime = TimeOfDay.now();
    String? selectedImagePath;

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
                  Icon(Icons.medical_information, color: Colors.blue, size: 30),
                  SizedBox(width: 10),
                  Text(
                    'เพิ่มรายการยา',
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
                    // ส่วนเลือกรูปภาพ
                    GestureDetector(
                      onTap: () async {
                        final picker = ImagePicker();
                        final XFile? image = await picker.pickImage(
                          source: ImageSource.camera,
                        );
                        if (image != null) {
                          setDialogState(() => selectedImagePath = image.path);
                        }
                      },
                      child: Container(
                        height: 120,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: selectedImagePath == null
                            ? const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.camera_alt,
                                    size: 40,
                                    color: Colors.blue,
                                  ),
                                  Text(
                                    'ถ่ายรูปยา',
                                    style: TextStyle(color: Colors.blue),
                                  ),
                                ],
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(15),
                                child: Image.file(
                                  File(selectedImagePath!),
                                  fit: BoxFit.cover,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'ชื่อยา',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(
                        labelText: 'คำอธิบาย (เช่น ทานหลังอาหาร)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'จำนวนเม็ดที่มี',
                        border: OutlineInputBorder(),
                      ),
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
                            if (picked != null)
                              setDialogState(() => selectedTime = picked);
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
                    if (nameController.text.isNotEmpty &&
                        amountController.text.isNotEmpty) {
                      String formattedTime =
                          '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';

                      final newMed = Medication(
                        name: nameController.text,
                        time: formattedTime,
                        imagePath: selectedImagePath,
                        description: descController.text,
                        remainingPills: int.parse(amountController.text),
                        isTaken: 0,
                      );
                      final savedMed = await DatabaseHelper.instance.insertPill(
                        newMed,
                      );

                      // 🌟 ตั้งการแจ้งเตือนหลังบันทึกยา (นี่คือสาเหตุที่ print ไม่ทำงาน — ต้องเรียก method นี้ด้วย)
                      await NotificationService().scheduleMedicationAlerts(
                        medId: savedMed,
                        medName: nameController.text,
                        timeString: formattedTime,
                        userName: _userName,
                      );

                      if (mounted) Navigator.pop(context);
                      _refreshMedications();
                    }
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
  // 1. หน้าตารางยา (เพิ่มลอจิกตัดสต็อก)
  // ==========================================
  Widget _buildScheduleView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton.icon(
            onPressed: _showAddMedicationDialog,
            icon: const Icon(Icons.add_alert, size: 32),
            label: const Text(
              'เพิ่มรายการยาใหม่',
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

        // 🔔 ปุ่มทดสอบแจ้งเตือนทันที (สำหรับ Debug)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: ElevatedButton.icon(
            onPressed: () async {
              const androidDetails = AndroidNotificationDetails(
                'test_channel',
                'Test',
                importance: Importance.max,
                priority: Priority.high,
              );
              await NotificationService().flutterLocalNotificationsPlugin.show(
                999,
                '🔔 เทสต์ระบบแจ้งเตือน',
                'ถ้านี่เด้ง แปลว่าสิทธิ์แจ้งเตือนผ่านแล้ว ปัญหาอยู่ที่การตั้งเวลา!',
                const NotificationDetails(android: androidDetails),
              );
            },
            icon: const Icon(Icons.notifications_active, size: 24),
            label: const Text(
              'ทดสอบแจ้งเตือนทันที',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),

        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _medications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.medication_liquid,
                        size: 80,
                        color: Colors.blue.shade200,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'ยังไม่มีรายการยาในวันนี้',
                        style: TextStyle(fontSize: 20, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _medications.length,
                  itemBuilder: (context, index) {
                    final med = _medications[index];
                    final isTaken = med.isTaken == 1;

                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        side: BorderSide(
                          color: isTaken
                              ? Colors.grey.shade300
                              : Colors.blue.shade200,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            if (med.imagePath != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  File(med.imagePath!),
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                ),
                              )
                            else
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.medication,
                                  color: Colors.blue,
                                  size: 35,
                                ),
                              ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    med.time,
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: isTaken
                                          ? Colors.grey
                                          : Colors.blue.shade900,
                                    ),
                                  ),
                                  Text(
                                    med.name,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (med.description != null &&
                                      med.description!.isNotEmpty)
                                    Text(
                                      med.description!,
                                      style: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                    ),
                                  Text(
                                    'เหลือ: ${med.remainingPills} เม็ด',
                                    style: TextStyle(
                                      color: Colors.orange.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // 🌟 ส่วนของปุ่มกดที่เพิ่มลอจิกตัดสต็อกยา 🌟

                            // 🌟 ส่วนของปุ่มต่างๆ (ลบ และ เช็กสถานะ) 🌟
                            Column(
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                    size: 28,
                                  ),
                                  onPressed: () => _deleteMedication(med.id!),
                                ),
                                IconButton(
                                  icon: Icon(
                                    isTaken
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked,
                                    color: isTaken ? Colors.green : Colors.grey,
                                    size: 45,
                                  ),
                                  onPressed: () async {
                                    int newRemaining = med.remainingPills;

                                    // กรณียังไม่ได้กิน แล้วจะกดยืนยันว่า "กินแล้ว"
                                    if (!isTaken) {
                                      if (newRemaining > 0) {
                                        newRemaining -= 1; // หักยา 1 เม็ด
                                      } else {
                                        // ถ้ายาหมด แจ้งเตือนและไม่อนุญาตให้กด
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'ยารายการนี้หมดแล้ว กรุณาเติมยาครับ!',
                                            ),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                        return;
                                      }
                                    }
                                    // กรณีกินไปแล้ว แต่อยากกดยกเลิก (เผื่อผู้สูงอายุกดผิด)
                                    else {
                                      newRemaining += 1; // คืนยา 1 เม็ด
                                    }

                                    // อัปเดตข้อมูลลง Model
                                    med.isTaken = isTaken ? 0 : 1;
                                    med.remainingPills = newRemaining;

                                    // บันทึกลง Database
                                    await DatabaseHelper.instance
                                        .updateMedication(med);

                                    // (ออปชันเสริม) ถ้ายืนยันว่ากินแล้ว ให้ยกเลิกการแจ้งเตือนของญาติ
                                    if (med.isTaken == 1)
                                      await NotificationService()
                                          .cancelRelativeAlert(med.id!);

                                    _refreshMedications(); // รีเฟรชหน้าจอ
                                  },
                                ),
                              ],
                            ),
                          ],
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
    // กรองเอาเฉพาะยาที่ isTaken == 1 (กินแล้ว)
    final historyList = _medications.where((med) => med.isTaken == 1).toList();

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
          child: historyList.isEmpty
              ? Center(
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
                        'ยังไม่มีประวัติการทานยา',
                        style: TextStyle(fontSize: 20, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: historyList.length,
                  itemBuilder: (context, index) {
                    final med = historyList[index];
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.green,
                          child: Icon(Icons.check, color: Colors.white),
                        ),
                        title: Text(
                          med.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          'เวลาที่ต้องทาน: ${med.time}',
                          style: const TextStyle(fontSize: 16),
                        ),
                        trailing: const Text(
                          'ทานแล้ว',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
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
  // 3. หน้าโปรไฟล์ (เพิ่ม Card เปลี่ยนชื่อ และ รหัสญาติ)
  // ==========================================
  Widget _buildProfileView() {
    TextEditingController nameController = TextEditingController(
      text: _userName,
    );

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
