import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'database_helper.dart';

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
        if (response.payload != null && response.payload!.isNotEmpty) {
          navigatorKey.currentState?.pushNamed(
            '/med_detail',
            arguments: response.payload!, // เป็น scheduleId string
          );
        }
      },
    );
  }

  // นำเข้า DatabaseHelper สำหรับเช็ค amount ของยา
  Future<void> scheduleTimeAlerts({
    required String scheduleId,
    required String timeString,
    required String userName,
  }) async {
    // 1. ตรวจสอบว่ามียาที่ยังไม่หมด (amount > 0) และต้องกินวันนี้
    final meds = await DatabaseHelper.instance.getMedicationsBySchedule(scheduleId);

    // เช็ควันปัจจุบัน (weekday: 1=จันทร์ ... 7=อาทิตย์)
    const dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final todayName = dayNames[DateTime.now().weekday - 1];

    final activeMeds = meds.where((m) =>
      m.amount > 0 &&
      (m.days.contains('Everyday') || m.days.contains(todayName))
    ).toList();
    
    // ถ้าไม่มียาเหลือให้กินเลยสำหรับรอบเวลานี้ ให้ยกเลิกแจ้งเตือนไปเลย (ไม่ปลุก)
    if (activeMeds.isEmpty) {
      await cancelAllAlertsForSchedule(scheduleId);
      return; 
    }

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

    await _scheduleAlarmsWithBaseTime(scheduleId, scheduledTime, timeString, userName);
  }

  Future<void> snoozeScheduleAlerts({
    required String scheduleId,
    required String timeString,
    required String userName,
  }) async {
    // ยกเลิกอันเดิมก่อน
    await cancelAllAlertsForSchedule(scheduleId);
    
    // ตั้งเวลาใหม่จากปัจจุบันไปอีก 15 นาที
    final snoozeTime = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 15));
    await _scheduleAlarmsWithBaseTime(scheduleId, snoozeTime, timeString, userName, isSnooze: true);
  }

  Future<void> _scheduleAlarmsWithBaseTime(
    String scheduleId,
    tz.TZDateTime baseTime,
    String timeString,
    String userName,
    {bool isSnooze = false}
  ) async {
    int schedIdInt = (scheduleId.hashCode.abs() % 100000000);
    final repeat1Time = baseTime.add(const Duration(minutes: 1));
    final repeat2Time = baseTime.add(const Duration(minutes: 2));
    final relativeTime = baseTime.add(const Duration(minutes: 3));

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

    String snoozeText = isSnooze ? ' (เลื่อนเวลามาจาก $timeString น.)' : '';

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        schedIdInt * 10,
        'ถึงเวลากินยาแล้วครับ',
        'คุณ $userName ถึงเวลา $timeString น. แล้วครับ อย่าลืมทานยานะครับ$snoozeText',
        baseTime,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: scheduleId,
      );
      print('✅ [NOTIF] ตั้งปลุกหลัก ID=${schedIdInt * 10} เวลา=$baseTime');
      
      await flutterLocalNotificationsPlugin.zonedSchedule(
        schedIdInt * 10 + 2,
        'ถึงเวลากินยาแล้วครับ (แจ้งเตือนซ้ำ)',
        'เลยเวลามา 1 นาทีแล้ว คุณ $userName อย่าลืมทานยารอบ $timeString น. นะครับ$snoozeText',
        repeat1Time,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: scheduleId,
      );

      await flutterLocalNotificationsPlugin.zonedSchedule(
        schedIdInt * 10 + 3,
        'ถึงเวลากินยาแล้วครับ (แจ้งเตือนซ้ำครั้งสุดท้าย)',
        'เลยเวลามา 2 นาทีแล้ว กรุณาทานยารอบ $timeString น. ด่วนครับ$snoozeText',
        repeat2Time,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: scheduleId,
      );
      print('✅ [NOTIF] ตั้งปลุกซ้ำสำเร็จ schedIdInt=$schedIdInt เวลาตั้ง=$baseTime');
    } catch (e) {
      print('❌ [NOTIF] ตั้งแจ้งเตือนผู้ใช้ล้มเหลว: $e');
    }

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        schedIdInt * 10 + 1,
        '⚠️ แจ้งเตือนญาติ',
        'คุณ $userName ยังไม่ได้กดยืนยันการกินยารอบ $timeString น. (เลยเวลามา 3 นาที)!$snoozeText',
        relativeTime,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      print('❌ [DEBUG] ตั้งแจ้งเตือนญาติล้มเหลว: $e');
    }
  }

  Future<void> cancelPendingAlerts(String scheduleId) async {
    int schedIdInt = (scheduleId.hashCode.abs() % 100000000);
    await flutterLocalNotificationsPlugin.cancel(schedIdInt * 10 + 1); // ญาติ
    await flutterLocalNotificationsPlugin.cancel(schedIdInt * 10 + 2); // ซ้ำครั้งที่ 1
    await flutterLocalNotificationsPlugin.cancel(schedIdInt * 10 + 3); // ซ้ำครั้งที่ 2
  }

  Future<void> cancelAllAlertsForSchedule(String scheduleId) async {
    int schedIdInt = (scheduleId.hashCode.abs() % 100000000);
    await flutterLocalNotificationsPlugin.cancel(schedIdInt * 10);
    await cancelPendingAlerts(scheduleId);
  }
}
