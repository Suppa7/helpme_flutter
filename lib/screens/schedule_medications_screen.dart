import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/medication.dart';
import '../models/schedule.dart';
import '../services/database_helper.dart';
import '../services/notification_service.dart';

class ScheduleMedicationsScreen extends StatefulWidget {
  final ScheduleModel schedule;

  const ScheduleMedicationsScreen({super.key, required this.schedule});

  @override
  State<ScheduleMedicationsScreen> createState() =>
      _ScheduleMedicationsScreenState();
}

class _ScheduleMedicationsScreenState extends State<ScheduleMedicationsScreen> {
  List<Medication> _medications = [];
  bool _isLoading = true;
  String _userName = '';

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _refreshMedications();
  }

  Future<void> _loadUserName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('userName') ?? 'ผู้ใช้งาน';
    });
  }

  Future<void> _refreshMedications() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance
        .getMedicationsBySchedule(widget.schedule.scheduleId!);
    setState(() {
      _medications = data;
      _isLoading = false;
    });
  }

  Future<void> _deleteMedication(Medication med) async {
    bool confirm = await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('ยืนยันการลบ'),
            content: const Text('คุณต้องการลบยานี้ออกจากช่วงเวลานี้หรือไม่?'),
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
      // 1. ลบแจ้งเตือนที่เกี่ยวข้องด้วย (ถ้ามี)
      if (med.notificationId != 0) {
         // เราไม่ได้ใช้ flutter_local_notifications ตรงๆ ให้ cancel, ต้องสร้าง method ใน NotificationService ถ้าต้องการ. 
         // ชั่วคราวเราข้ามไปก่อน หรือเพิ่มได้ภายหลัง
      }

      await DatabaseHelper.instance.deleteMedication(med.medId!);
      _refreshMedications();
    }
  }

  Future<void> _showAddMedicationDialog() async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController amountController = TextEditingController();
    final TextEditingController additionalInfoController = TextEditingController();
    String? selectedImagePath;
    String selectedUnit = 'เม็ด';
    String repeatType = 'everyday';
    List<String> selectedDays = [];
    
    final List<String> allDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final Map<String, String> dayNamesTh = {
      'Monday': 'จันทร์', 'Tuesday': 'อังคาร', 'Wednesday': 'พุธ',
      'Thursday': 'พฤหัสบดี', 'Friday': 'ศุกร์', 'Saturday': 'เสาร์', 'Sunday': 'อาทิตย์',
    };

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
                  Icon(Icons.medical_information, color: Colors.green, size: 30),
                  SizedBox(width: 10),
                  Text(
                    'เพิ่มยา',
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
                    // ส่วนเลือกรูปภาพ
                    GestureDetector(
                      onTap: () async {
                         try {
                          final picker = ImagePicker();
                          final XFile? image = await picker.pickImage(
                            source: ImageSource.camera,
                          );
                          if (image != null) {
                            setDialogState(() => selectedImagePath = image.path);
                          }
                        } catch (e) {
                          debugPrint(e.toString());
                        }
                      },
                      child: Container(
                        height: 120,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: selectedImagePath == null
                            ? const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.camera_alt,
                                    size: 40,
                                    color: Colors.green,
                                  ),
                                  Text(
                                    'ถ่ายรูปยา',
                                    style: TextStyle(color: Colors.green),
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
                      decoration: InputDecoration(
                        labelText: 'ชื่อยา',
                        prefixIcon: const Icon(Icons.medication, color: Colors.green),
                        filled: true,
                        fillColor: Colors.green.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: additionalInfoController,
                      decoration: InputDecoration(
                        labelText: 'ข้อมูลเพิ่มเติม (วิธีรับประทาน, ข้อควรระวัง)',
                        prefixIcon: const Icon(Icons.note, color: Colors.green),
                        filled: true,
                        fillColor: Colors.green.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: amountController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'จำนวนยาที่เหลือ',
                              prefixIcon: const Icon(Icons.numbers, color: Colors.green),
                              filled: true,
                              fillColor: Colors.green.shade50,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedUnit,
                            decoration: InputDecoration(
                              labelText: 'หน่วย',
                              filled: true,
                              fillColor: Colors.green.shade50,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'เม็ด', child: Text('เม็ด')),
                              DropdownMenuItem(value: 'แคปซูล', child: Text('แคปซูล')),
                              DropdownMenuItem(value: 'ช้อนโต๊ะ', child: Text('ช้อนโต๊ะ')),
                              DropdownMenuItem(value: 'ช้อนชา', child: Text('ช้อนชา')),
                              DropdownMenuItem(value: 'ซีซี', child: Text('ซีซี')),
                              DropdownMenuItem(value: 'หยด', child: Text('หยด')),
                              DropdownMenuItem(value: 'ซอง', child: Text('ซอง')),
                            ],
                            onChanged: (val) => setDialogState(() => selectedUnit = val!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      initialValue: repeatType,
                      decoration: InputDecoration(
                        labelText: 'วันที่กิน',
                        prefixIcon: const Icon(Icons.calendar_today, color: Colors.green),
                        filled: true,
                        fillColor: Colors.green.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'everyday', child: Text('กินทุกวัน')),
                        DropdownMenuItem(value: 'custom', child: Text('เลือกวัน (จ.-อา.)')),
                      ],
                      onChanged: (val) => setDialogState(() => repeatType = val!),
                    ),
                    if (repeatType == 'custom') ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 4.0,
                        children: allDays.map((day) {
                          return FilterChip(
                            label: Text(dayNamesTh[day]!),
                            selected: selectedDays.contains(day),
                            onSelected: (bool selected) {
                              setDialogState(() {
                                if (selected) {
                                  selectedDays.add(day);
                                } else {
                                  selectedDays.remove(day);
                                }
                              });
                            },
                            selectedColor: Colors.green.shade100,
                            checkmarkColor: Colors.green,
                          );
                        }).toList(),
                      ),
                    ],
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
                    if (nameController.text.isNotEmpty &&
                        amountController.text.isNotEmpty) {
                      
                      final newName = nameController.text.trim();
                      final isDuplicate = _medications.any((m) => m.medName.trim().toLowerCase() == newName.toLowerCase());
                      if (isDuplicate) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('มียาชื่อ "$newName" ในรอบเวลานี้อยู่แล้ว กรุณาแก้ไขรายการเดิมแทน')),
                        );
                        return;
                      }

                      final newMed = Medication(
                        scheduleId: widget.schedule.scheduleId!,
                        userId: widget.schedule.userId,
                        medName: nameController.text,
                        amount: num.tryParse(amountController.text) ?? 1,
                        unit: selectedUnit,
                        imageUrl: selectedImagePath,
                        notificationId: 0,
                        days: repeatType == 'everyday' ? ['Everyday'] : (selectedDays.isEmpty ? ['Everyday'] : selectedDays),
                        additionalInfo: additionalInfoController.text.isNotEmpty ? additionalInfoController.text : null,
                      );

                      final savedMed = await DatabaseHelper.instance
                          .insertMedication(newMed);

                      if (savedMed != null) {
                        try {
                            // ตั้งการแจ้งเตือนกลุ่มสำหรับเวลานี้
                          await NotificationService().scheduleTimeAlerts(
                            scheduleId: widget.schedule.scheduleId!,
                            timeString: widget.schedule.time,
                            userName: _userName,
                          );
                        } catch (e) {
                           debugPrint(e.toString());
                        }
                      }

                      if (!context.mounted) return;
                      Navigator.pop(context);
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

  Future<void> _showEditMedicationDialog(Medication med) async {
    final TextEditingController nameController = TextEditingController(text: med.medName);
    final TextEditingController amountController = TextEditingController(text: med.amount.toString());
    final TextEditingController additionalInfoController = TextEditingController(text: med.additionalInfo ?? '');
    String? selectedImagePath = med.imageUrl;
    String selectedUnit = med.unit;
    String repeatType = med.days.contains('Everyday') ? 'everyday' : 'custom';
    List<String> selectedDays = List.from(med.days);
    
    final List<String> allDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final Map<String, String> dayNamesTh = {
      'Monday': 'จันทร์', 'Tuesday': 'อังคาร', 'Wednesday': 'พุธ',
      'Thursday': 'พฤหัสบดี', 'Friday': 'ศุกร์', 'Saturday': 'เสาร์', 'Sunday': 'อาทิตย์',
    };

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
                  Icon(Icons.edit, color: Colors.orange, size: 30),
                  SizedBox(width: 10),
                  Text(
                    'แก้ไขยา',
                    style: TextStyle(
                      color: Colors.orange,
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
                         try {
                          final picker = ImagePicker();
                          final XFile? image = await picker.pickImage(
                            source: ImageSource.camera,
                          );
                          if (image != null) {
                            setDialogState(() => selectedImagePath = image.path);
                          }
                        } catch (e) {
                          debugPrint(e.toString());
                        }
                      },
                      child: Container(
                        height: 120,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: selectedImagePath == null
                            ? const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.camera_alt,
                                    size: 40,
                                    color: Colors.green,
                                  ),
                                  Text(
                                    'ถ่ายรูปยาใหม่',
                                    style: TextStyle(color: Colors.green),
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
                      decoration: InputDecoration(
                        labelText: 'ชื่อยา',
                        prefixIcon: const Icon(Icons.medication, color: Colors.green),
                        filled: true,
                        fillColor: Colors.green.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: additionalInfoController,
                      decoration: InputDecoration(
                        labelText: 'ข้อมูลเพิ่มเติม (วิธีรับประทาน, ข้อควรระวัง)',
                        prefixIcon: const Icon(Icons.note, color: Colors.green),
                        filled: true,
                        fillColor: Colors.green.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: amountController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'จำนวนยาที่เหลือ',
                              prefixIcon: const Icon(Icons.numbers, color: Colors.green),
                              filled: true,
                              fillColor: Colors.green.shade50,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedUnit,
                            decoration: InputDecoration(
                              labelText: 'หน่วย',
                              filled: true,
                              fillColor: Colors.green.shade50,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'เม็ด', child: Text('เม็ด')),
                              DropdownMenuItem(value: 'แคปซูล', child: Text('แคปซูล')),
                              DropdownMenuItem(value: 'ช้อนโต๊ะ', child: Text('ช้อนโต๊ะ')),
                              DropdownMenuItem(value: 'ช้อนชา', child: Text('ช้อนชา')),
                              DropdownMenuItem(value: 'ซีซี', child: Text('ซีซี')),
                              DropdownMenuItem(value: 'หยด', child: Text('หยด')),
                              DropdownMenuItem(value: 'ซอง', child: Text('ซอง')),
                            ],
                            onChanged: (val) => setDialogState(() => selectedUnit = val!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      initialValue: repeatType,
                      decoration: InputDecoration(
                        labelText: 'วันที่กิน',
                        prefixIcon: const Icon(Icons.calendar_today, color: Colors.green),
                        filled: true,
                        fillColor: Colors.green.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'everyday', child: Text('กินทุกวัน')),
                        DropdownMenuItem(value: 'custom', child: Text('เลือกวัน (จ.-อา.)')),
                      ],
                      onChanged: (val) => setDialogState(() => repeatType = val!),
                    ),
                    if (repeatType == 'custom') ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 4.0,
                        children: allDays.map((day) {
                          return FilterChip(
                            label: Text(dayNamesTh[day]!),
                            selected: selectedDays.contains(day),
                            onSelected: (bool selected) {
                              setDialogState(() {
                                if (selected) {
                                  selectedDays.add(day);
                                } else {
                                  selectedDays.remove(day);
                                }
                              });
                            },
                            selectedColor: Colors.green.shade100,
                            checkmarkColor: Colors.green,
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ยกเลิก', style: TextStyle(color: Colors.red, fontSize: 18)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    if (nameController.text.isNotEmpty &&
                        amountController.text.isNotEmpty) {
                      
                      final newName = nameController.text.trim();
                      final isDuplicate = _medications.any((m) => m.medId != med.medId && m.medName.trim().toLowerCase() == newName.toLowerCase());
                      if (isDuplicate) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('มียาชื่อ "$newName" ในรอบเวลานี้อยู่แล้ว ไม่สามารถใช้ชื่อซ้ำได้')),
                        );
                        return;
                      }

                      med.medName = newName;
                      med.amount = num.tryParse(amountController.text) ?? med.amount;
                      med.unit = selectedUnit;
                      med.imageUrl = selectedImagePath;
                      med.days = repeatType == 'everyday' ? ['Everyday'] : (selectedDays.isEmpty ? ['Everyday'] : selectedDays);
                      med.additionalInfo = additionalInfoController.text.isNotEmpty ? additionalInfoController.text : null;

                      await DatabaseHelper.instance.updateMedication(med);

                      // อัปเดตแจ้งเตือนกลุ่ม
                      try {
                        await NotificationService().scheduleTimeAlerts(
                          scheduleId: widget.schedule.scheduleId!,
                          timeString: widget.schedule.time,
                          userName: _userName,
                        );
                      } catch (e) {
                         debugPrint(e.toString());
                      }

                      if (!context.mounted) return;
                      Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ยาสำหรับเวลา ${widget.schedule.time}'),
        backgroundColor: Colors.green.shade800,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: _showAddMedicationDialog,
              icon: const Icon(Icons.add_circle, size: 30),
              label: const Text(
                'เพิ่มยาในเวลานี้',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 3,
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
                              Icons.medication_outlined,
                              size: 80,
                              color: Colors.green.shade200,
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'ยังไม่มียาในเวลานี้',
                              style:
                                  TextStyle(fontSize: 20, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _medications.length,
                        itemBuilder: (context, index) {
                          final med = _medications[index];
                          final Map<String, String> dayNamesTh = {
                            'Monday': 'จันทร์', 'Tuesday': 'อังคาร', 'Wednesday': 'พุธ',
                            'Thursday': 'พฤหัสบดี', 'Friday': 'ศุกร์', 'Saturday': 'เสาร์', 'Sunday': 'อาทิตย์',
                          };
                          String daysText = med.days.contains('Everyday') ? 'กินทุกวัน' : med.days.map((d) => dayNamesTh[d] ?? d).join(', ');

                          return Card(
                            elevation: 3,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                              side: BorderSide(color: Colors.green.shade100, width: 1),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                children: [
                                  if (med.imageUrl != null)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.file(
                                        File(med.imageUrl!),
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
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.medication,
                                        color: Colors.green,
                                        size: 35,
                                      ),
                                    ),
                                  const SizedBox(width: 15),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          med.medName,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          'จำนวนที่เหลือ: ${med.amount} ${med.unit}\nวันที่: $daysText${(med.additionalInfo != null && med.additionalInfo!.isNotEmpty) ? '\nเพิ่มเติม: ${med.additionalInfo}' : ''}',
                                          style: TextStyle(
                                            color: Colors.orange.shade700,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      color: Colors.orange,
                                      size: 28,
                                    ),
                                    onPressed: () => _showEditMedicationDialog(med),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                      size: 28,
                                    ),
                                    onPressed: () => _deleteMedication(med),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
