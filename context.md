# ภาพรวมของโปรเจกต์ (Project Context & Overview)

## 1. ข้อมูลทั่วไป
- **ชื่อโปรเจกต์:** test (แอปพลิเคชันเตือนการทานยา)
- **ประเภท:** Flutter Application
- **จุดประสงค์:** เป็นแอปพลิเคชันสำหรับผู้ป่วยและญาติ(ผู้ดูแล) เพื่อช่วยแจ้งเตือนการทานยา มีระบบติดตาม เลื่อนเวลา(Snooze) ข้ามมื้อยา(Skip) ค้นหาโรงพยาบาลใกล้เคียง และบันทึกประวัติการทานยาแบบ Real-time
- **ภาษาที่รองรับ (Localization):** รองรับภาษาอังกฤษ (en_US) และภาษาไทย (th_TH) ควบคุมผ่านแพ็กเกจ `flutter_localizations`

## 2. โครงสร้างและไลบรารีที่สำคัญ (Dependencies)
อ้างอิงจากไฟล์ `pubspec.yaml` มีแพ็กเกจหลักๆ ดังนี้:
- **`cloud_firestore` & `firebase_core`**: จัดการฐานข้อมูลแบบ NoSQL บน **Cloud Firestore** พร้อมระบบ Listener แบบ Real-time
- **`firebase_messaging`**: รองรับ Push Notification (FCM)
- **`shared_preferences`**: ใช้เก็บข้อมูลผู้ใช้ในเครื่อง (`uid`, `userName`) เพื่อการเชื่อมต่อและการล็อกอินอัตโนมัติ
- **`flutter_local_notifications` & `timezone`**: สร้างระบบแจ้งเตือน (Local Notification / Alarm) ภายในอุปกรณ์
- **`image_picker`**: ใช้สำหรับตลึงภาพยา พร้อมระบบ Preview รูปภาพขยายแบบ Interactive
- **`flutter_localizations`**: รองรับภาษาไทยใน DatePicker หรือ Widget พื้นฐานต่างๆ 
- **`geolocator`, `http`, `url_launcher`, `permission_handler`**: ใช้ดึงพิกัด Location และเชื่อมโยง Google Places API ค้นหาโรงพยาบาลและเปิดแอปพลิเคชัน Google Maps

## 3. โครงสร้างโค้ด (Project Structure)
- **`main.dart`**: จุดเริ่มต้นของแอปพลิเคชัน Initialize Firebase, ตั้งค่า Localization, ควบคุม Routing
- **`firebase_options.dart`**: ไฟล์ตั้งค่า Firebase สำหรับแต่ละ Platform 
- **`lib/models/`**: โฟลเดอร์เก็บคลาสโครงสร้างข้อมูล (Data Models) เช่น `medication.dart`, `medication_log.dart`, `schedule.dart`
- **`lib/repositories/`**: โฟลเดอร์แยกส่วนเชื่อมต่อฐานข้อมูล (Data Access Layer) เช่น `medication_log_repository.dart`
- **`lib/screens/`**: หน้า UI แอปพลิเคชัน เช่น `home_screen.dart`, `schedule_medications_screen.dart`, `nearby_hospitals_screen.dart`
- **`lib/services/`**: ตัวจัดการ Service หลักของแอป เช่น 
  - `database_helper.dart` (ดูแล CRUD และ Firestore Logic หลัก)
  - `notification_service.dart` (ตั้งปลุก แจ้งเตือนกลุ่ม และฟังก์ชัน Snooze)

## 4. โครงสร้างข้อมูลใน Firestore (แบบ Relational-like)
ระบบอัปเกรดโครงสร้างฐานข้อมูลรองรับญาติและการกระทำแบบเป็นประวัติต่อรอบ:
- **`users`**: เก็บข้อมูลผู้ใช้และรหัสเชื่อมต่อญาติ (uid, phoneNumber, password, userCode, monitoredUserUids, followerUids, fcmToken)
- **`Schedules`**: เก็บกำหนดการทานยา (scheduleId, userId, meal, time, instruction, isActive)
- **`Medications`**: เก็บชนิดยา (medId, scheduleId, medName, amount, unit, imageUrl, days) ผูกเข้ากับตาราง
- **`MedicationLogs`**: บันทึกประวัติ Transaction การทานยา (plannedTimestamp, actualTimestamp, status: taken/skipped/missed, snoozeCount)
- **`MissedMedicationAlerts`**: แจ้งเตือนผู้ป่วยลืมทานยา เพื่อส่งต่อไปยังระบบติดตามหน้าแจ้งเตือนของญาติ

## 5. ลำดับการทำงานหลัก (Main Application Flow)
1. **การเข้าสู่ระบบ:** ดึงจาก `uid` ใน Cache เข้าสู่แอป หรือลงทะเบียนล็อกอินด้วยเบอร์โทร + `userCode`
2. **จัดการยาและตาราง:** ผู้ป่วยสร้าง Schedule และ Medication ผูกกับเวลาที่กำหนด
3. **การแจ้งเตือนและการจัดการ (Medication Alerts):**
   - เตือนแบบ Local Notification แจ้งรวมกลุ่มเป็นรอบเวลาเดียว (Grouped Alert)
   - หน้าแจ้งเตือนสามารถ กดยืนยันทานยา (Taken), ข้ามการทาน (Skip), เลื่อนด่วน (Snooze 30 นาที/1 ชั่วโมง)
   - ตัดสต๊อกปริมาณยาคงเหลือและบันทึกประวัติลง `MedicationLogs`
4. **การตรวจสอบสถานะของระดับญาติ (Relative Monitoring):** 
   - ญาติลงทะเบียนติดตามผู้ป่วยผ่านรหัส `userCode`
   - เมื่อผู้ป่วยเกิดสถานการณ์ขาดยา (Missed) ระบบจะอัปเดตแจ้งเตือนและยิงให้ญาติตาม Listener ในหน้าแจ้งเตือน
5. **โรงพยาบาลใกล้เคียง (Nearby Hospitals):** 
   - ดึงพิกัด Location ของเครื่อง และเรียก Google Places API โชว์โรงพยาบาลในรัศมี 10 กม. นำทางได้อย่างทันใจ

## 6. สิ่งที่เพิ่งอัปเดต (Recent Updates)
- เพิ่มฟีเจอร์ **"ค้นหาโรงพยาบาลใกล้ฉัน" (Nearby Hospitals)** ผ่านระบบ GPS และ Google Maps API
- ปรับโครงสร้างนำ Repository Pattern เข้ามาใช้ (`medication_log_repository.dart`) แยกโค้ดออกจาก UI เพื่อความเป็นระเบียบ
- สร้างฟังก์ชัน **"ข้ามมื้อยา (Skip this meal)"** สำหรับผู้ป่วยที่ไม่ได้เอายาติดตัว ไม่ให้ตัวแอปแจ้งเตือนกวนญาติมิตร
- พัฒนาระบบ **Snooze** ให้ยืดหยุ่นด้วยตัวเลือกกำหนดเวลาได้เอง (30 นาที เลื่อน 1 ชม. ฯลฯ)
- อัปเกรด Listener แจ้งผู้ดูแล ตรวจจับยา (Missed) เรียลไทม์อย่างมีประสิทธิภาพ

## 7. สิ่งที่กำลังพัฒนาต่อ (Future Plans / WIP)
- ปรับปรุง UI และ UX ให้มีความกลมกลืน ดูทันสมัย ยกระดับแอปไปสู่ความเรียบร้อยระดับใช้งานจริง (Production)
- นำประวัติ `MedicationLogs` มาสร้างกราฟ หรือ Summary Analytics แจ้งอัตราการรับประทานยา

## 8. คำสั่งที่ผ่าน terminal ให้ list ไว้ให้ฉันรันด้วยตนเอง