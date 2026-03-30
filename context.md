# ภาพรวมของโปรเจกต์ (Project Context & Overview)

## 1. ข้อมูลทั่วไป
- **ชื่อโปรเจกต์:** test (แอปพลิเคชันเตือนการทานยา)
- **ประเภท:** Flutter Application
- **จุดประสงค์:** เป็นแอปพลิเคชันสำหรับผู้ป่วยและญาติ(ผู้ดูแล) เพื่อช่วยแจ้งเตือนการทานยา มีระบบติดตาม เลื่อนเวลา(Snooze) และบันทึกประวัติการทานยาแบบ Real-time
- **ภาษาที่รองรับ (Localization):** รองรับภาษาอังกฤษ (en_US) และภาษาไทย (th_TH) ควบคุมผ่านแพ็กเกจ `flutter_localizations`

## 2. โครงสร้างและไลบรารีที่สำคัญ (Dependencies)
อ้างอิงจากไฟล์ `pubspec.yaml` มีแพ็กเกจหลักๆ ดังนี้:
- **`cloud_firestore` & `firebase_core`**: จัดการฐานข้อมูลแบบ NoSQL บน **Cloud Firestore** พร้อมระบบ Listener แบบ Real-time
- **`firebase_messaging`**: รองรับ Push Notification (FCM)
- **`shared_preferences`**: ใช้เก็บข้อมูลผู้ใช้ในเครื่อง (`uid`, `userName`) เพื่อการเชื่อมต่อและการล็อกอินอัตโนมัติ
- **`flutter_local_notifications` & `timezone`**: สร้างระบบแจ้งเตือน (Local Notification / Alarm) ภายในอุปกรณ์
- **`image_picker`**: ใช้สำหรับตลึงภาพยา พร้อมระบบ Preview รูปภาพขยายแบบ Interactive
- **`flutter_localizations`**: รองรับภาษาไทยใน DatePicker หรือ Widget พื้นฐานต่างๆ 

## 3. โครงสร้างโค้ด (Project Structure)
- **`main.dart`**: จุดเริ่มต้นของแอปพลิเคชัน Initialize Firebase, ตั้งค่า Localization, ควบคุม Routing (`/login`, `/register`, `/home`, `/med_detail`, `/alert_detail`)
- **`firebase_options.dart`**: ไฟล์ตั้งค่า Firebase สำหรับแต่ละ Platform 
- **`lib/models/`**: โฟลเดอร์เก็บคลาสโครงสร้างข้อมูล (Data Models) เช่น `medication.dart`, `medication_log.dart`
- **`lib/screens/`**: หน้า UI แอปพลิเคชัน เช่น `home_screen.dart`, หน้า `MedicationDetailScreen` (กดรับลดยาจากตารางกลุ่ม), หน้า `AlertDetailScreen` (หน้าสำหรับญาติในการกดยืนยันรับทราบกรณีผู้ป่วยขาดยา)
- **`lib/services/`**: ตัวจัดการ Service ต่างๆ ของแอป เช่น 
  - `database_helper.dart` (รับผิดชอบ CRUD คุยกับ Firestore มีการ Query เชิงลึก) 
  - `notification_service.dart` (รับผิดชอบการตั้งปลุก แจ้งเตือนกลุ่ม และฟังก์ชัน เลื่อนเวลา Snooze)

## 4. โครงสร้างข้อมูลใน Firestore (แบบ Relational-like)
ระบบเพิ่งอัปเกรดโครงสร้างฐานข้อมูลมารองรับญาติและการแจ้งเตือนรายครั้ง:
- **`users`**: เก็บข้อมูลผู้ใช้และรหัสเชื่อมต่อญาติ (uid, phoneNumber, password, userCode, monitoredUserUids, followerUids, fcmToken)
- **`Schedules`**: เก็บรายละเอียดกำหนดการทานยา (scheduleId, userId, meal, time, instruction, isActive)
- **`Medications`**: เก็บชนิดยา (medId, scheduleId, medName, amount, unit, imageUrl, days) ผูกเวลา
- **`MedicationLogs`**: บันทึกประวัติการทานยา Transaction Log (plannedTimestamp, actualTimestamp, status: taken/skipped/missed, snoozeCount)
- **`MissedMedicationAlerts`**: (หน้าใหม่) แจ้งเตือนผู้ป่วยลืมทานยาสำหรับระบบติดตามของญาติ (แบบ Real-time snapshot listener)

## 5. ลำดับการทำงานหลัก (Main Application Flow)
1. **การเข้าสู่ระบบ:** เช็ค `uid` ใน `SharedPreferences` เพื่อไปยัง `/home` สลับกับการสมัครแบบเบอร์โทรศัพท์และรหัส `userCode`
2. **จัดการยาและตาราง:** ผู้ใช้สร้าง Schedule เวลา และเพิ่ม Medication ผูกเวลา
3. **แจ้งเตือนกลุ่มและการยืนยัน (Grouped System):**
   - เมื่อถึงเวลา Local Notification จะเด้งขึ้นรวมเป็นก้อน หากทิ้งไว้จะดังซ้ำ 2 รอบ
   - แตะที่แจ้งเตือนเปิดไปที่หน้า (`/med_detail`) สามารถทานรายตัว, ทานทั้งหมด, เรียกดูรูปยา หรือเลื่อน 15 นาที (Snooze)
   - เมื่อยืนยันทานยา ระบบจะตัดยอดยาคงเหลือ (`amount`) และบันทึกสถานะ `taken` เข้า Logs
4. **ระบบรับทราบสถานะญาติ (Relative Monitoring):** 
   - ญาติสามารถใส่รหัสติดตามตัว (`userCode`) ในหน้า Home 
   - เมื่อผู้ป่วยลืมทานยาถึงเวลาที่กำหนด (missed) ข้อมูลจะส่งเข้าคอลเลกชัน `MissedMedicationAlerts` 
   - ระบบของญาติใช้วิธีดักจับ Snapshot Listener แจ้งญาติให้สามารถกดรับทราบ (`/alert_detail`) เข้าไปอัปเดตสถานะการตามจิกผู้ป่วยบน Firestore ได้อย่างทันทีทันใด

## 6. สิ่งที่เพิ่งอัปเดต (Recent Updates)
- ปรับปรุงวิธีการแจ้งเตือนญาติมาเป็นการดักจับ Snapshot จาก `MissedMedicationAlerts` ด้วย Real-time Listener แก้ปัญหาความน่าเชื่อถือ
- ใช้งานระบบ Logging Status ใหม่ทั้งหมด (`snoozed`, `taken`, `missed`)
- อัปเกรด UI ด้วยระบบโชว์รูปถ่ายยาขยาย และ Notification Group List
- แก้ไข Analyzer Warnings เก็บกวาดแจ้งเตือนเกี่ยวกับการใช้ mounted ข้ามบริบท

## 7. สิ่งที่กำลังพัฒนาต่อ (Future Plans / WIP)
- ปรับปรุง UI และ UX ให้สวยงาม แข็งแรงมากยิ่งขึ้นในขั้นตอนสู่ Production

## 8. คำสั่งที่ผ่าน terminal ให้ list ไว้ให้ฉันรันด้วยตนเอง