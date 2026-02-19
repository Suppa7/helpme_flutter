import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// 🌟 สร้าง GlobalKey เพื่อใช้สั่งเปลี่ยนหน้าจอจาก Service
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Bangkok'));

    final androidImplementation = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    // ขอสิทธิ์แจ้งเตือน และสิทธิ์ตั้งเวลา (สำคัญมากสำหรับ Android รุ่นใหม่)
    await androidImplementation?.requestNotificationsPermission();
    await androidImplementation?.requestExactAlarmsPermission();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    // 🌟 ดักจับอีเวนต์เมื่อผู้ใช้ "กดที่การแจ้งเตือน"
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          int? medId = int.tryParse(response.payload!);
          if (medId != null) {
            // สั่งให้แอปเด้งไปหน้า รายละเอียดการกินยา พร้อมส่ง ID ไปด้วย
            navigatorKey.currentState?.pushNamed(
              '/med_detail',
              arguments: medId,
            );
          }
        }
      },
    );
  }

  Future<void> scheduleMedicationAlerts({
    required int medId,
    required String medName,
    required String timeString,
    required String userName,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    final parts = timeString.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);

    var scheduledTime = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }
    // 🌟 เพิ่ม 2 บรรทัดนี้เพื่อ Debug ดูใน Terminal
    print('🕒 [DEBUG] เวลาปัจจุบันของระบบ: $now');
    print('⏰ [DEBUG] เวลาที่ตั้งปลุกจริง: $scheduledTime');

    final relativeTime = scheduledTime.add(const Duration(minutes: 2));

    const androidDetails = AndroidNotificationDetails(
      'medication_channel',
      'การแจ้งเตือนกินยา',
      channelDescription: 'แจ้งเตือนเวลาทานยาสำหรับผู้ใช้และญาติ',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    const platformDetails = NotificationDetails(android: androidDetails);

    // แจ้งเตือนผู้ใช้ 🌟 แนบ payload เป็น medId เพื่อให้รู้ว่ากดยาตัวไหน
    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        medId * 10,
        'ถึงเวลากินยาแล้วครับ',
        'คุณ $userName ถึงเวลาทานยา $medName แล้วครับ',
        scheduledTime,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: medId.toString(),
      );
      print(
        '✅ [DEBUG] ตั้งแจ้งเตือนผู้ใช้สำเร็จ (ID: ${medId * 10}) เวลา: $scheduledTime',
      );
    } catch (e) {
      print('❌ [DEBUG] ตั้งแจ้งเตือนผู้ใช้ล้มเหลว: $e');
    }

    // แจ้งเตือนญาติ (ไม่ต้องมี payload เพราะจำลองส่งไปหาญาติ)
    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        medId * 10 + 1,
        '⚠️ แจ้งเตือนญาติ',
        'คุณ $userName ยังไม่ได้กดยืนยันการกินยา $medName!',
        relativeTime,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      print(
        '✅ [DEBUG] ตั้งแจ้งเตือนญาติสำเร็จ (ID: ${medId * 10 + 1}) เวลา: $relativeTime',
      );
    } catch (e) {
      print('❌ [DEBUG] ตั้งแจ้งเตือนญาติล้มเหลว: $e');
    }
  }

  Future<void> cancelRelativeAlert(int medId) async {
    await flutterLocalNotificationsPlugin.cancel(medId * 10 + 1);
  }

  Future<void> cancelAllAlertsForMed(int medId) async {
    await flutterLocalNotificationsPlugin.cancel(medId * 10);
    await flutterLocalNotificationsPlugin.cancel(medId * 10 + 1);
  }
}
