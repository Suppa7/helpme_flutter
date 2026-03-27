# ภาพรวมของโปรเจกต์ (Project Context & Overview)

## 1. ข้อมูลทั่วไป
- **ชื่อโปรเจกต์:** test (แอปพลิเคชันเตือนการทานยา)
- **ประเภท:** Flutter Application
- **จุดประสงค์:** เป็นแอปพลิเคชันสำหรับผู้ป่วยและญาติ(ผู้ดูแล) เพื่อช่วยแจ้งเตือนการทานยา มีระบบติดตามและบันทึกประวัติการทานยา
- **ภาษาที่รองรับ (Localization):** รองรับภาษาอังกฤษ (en_US) และภาษาไทย (th_TH) ควบคุมผ่านแพ็กเกจ `flutter_localizations`

## 2. โครงสร้างและไลบรารีที่สำคัญ (Dependencies)
อ้างอิงจากไฟล์ `pubspec.yaml` มีแพ็กเกจหลักๆ ดังนี้:
- **`cloud_firestore` & `firebase_core`**: จัดการฐานข้อมูลแบบ NoSQL บน **Cloud Firestore**
- **`firebase_messaging`**: รองรับ Push Notification ผ่าน FCM
- **`shared_preferences`**: ใช้เก็บข้อมูลเบสิกของผู้ใช้ในเครื่อง (เช่น Cache ของ `uid` และ `userName`) เพื่อข้ามหน้าล็อกอินไม่ต้องกรอกใหม่ทุกครั้ง
- **`flutter_local_notifications` & `timezone`**: ทำหน้าที่สร้างกลไกระบบแจ้งเตือน (Local Notification / Alarm) ภายในอุปกรณ์
- **`image_picker`**: ใช้สำหรับแนบหรือถ่ายรูปภาพยา
- **`flutter_localizations`**: รองรับภาษาไทยใน DatePicker หรือ Widget พื้นฐานต่างๆ 

## 3. โครงสร้างโค้ด (Project Structure)
- **`main.dart`**: จุดเริ่มต้นของแอปพลิเคชัน Initialize Firebase, ตั้งค่า Localization, ควบคุม Routing (`/login`, `/register`, `/home`, `/med_detail`) และดูแลสเตตัสในหน้าจัดการยาเมื่อเปิดจากการแจ้งเตือน (`MedicationDetailScreen`)
- **`firebase_options.dart`**: ไฟล์ตั้งค่า Firebase สำหรับแต่ละ Platform 
- **`lib/models/`**: โฟลเดอร์เก็บคลาสโครงสร้างข้อมูล (Data Models) เช่น `medication.dart`
- **`lib/screens/`**: หน้า UI แอปพลิเคชัน เช่น `home_screen.dart`
- **`lib/services/`**: ตัวจัดการ Service ต่างๆ ของแอป เช่น 
  - `database_helper.dart` (รับผิดชอบ CRUD คุยกับ Firestore) 
  - `notification_service.dart` (รับผิดชอบการตั้งปลุก, Snooze, ยกเลิกคิว)

## 4. โครงสร้างข้อมูลใน Firestore (ปัจจุบันแบบ Relational-like)
ระบบได้ยกเครื่องโครงสร้างจากรูปแบบเดิมมาเป็นแบบ Relational-like เพื่อรองรับระบบญาติและการตั้งเวลาให้ยืดหยุ่น (มีใช้งานจริงแล้ว):
- **`users`**: เก็บข้อมูลผู้ใช้ (uid, phoneNumber, password, userCode, monitoredUserUids, followerUids, fcmToken)
- **`Schedules`**: เก็บรายละเอียดกำหนดการ/ช่วงเวลาทานยา (scheduleId, userId, meal, time, instruction, isActive)
- **`Medications`**: เก็บระเบียนตัวยาแต่ละชนิด (medId, scheduleId, medName, amount, unit, imageUrl, days) โดยผูกกับ Schedules
- **`MedicationLogs`**: เป็น Transaction Log บันทึกประวัติการทานยารายครั้งอย่างละเอียด (plannedTimestamp, actualTimestamp, status: taken/skipped/missed, snoozeCount)

## 5. ลำดับการทำงานหลัก (Main Application Flow)
1. **การลงทะเบียน/ล็อกอิน (Authentication via Phone):** แอปพลิเคชันตรวจสอบตัวแปร `uid` ใน `SharedPreferences` หากไม่พบ จะพาไปเข้าสู่ระบบ `/login` หรือสมัครสมาชิก `/register` โดยใช้เบอร์โทรศัพท์เป็นหลักในการจำแนกผู้ใช้
2. **หน้าจอหลัก (Home Screen):** เมื่อมี UID แล้ว แอปจะส่งไป `/home` เพื่อโหลดข้อมูล Schedule และ Medication ของผู้ใช้นั้นมาแสดงผล
3. **การเพิ่มยาและตั้งเวลา:** ผู้ใช้สร้าง Schedule ใหม่ (เลือกเวลา และวันเช่น Everyday หรือบางวัน) จากนั้นก็เพิ่ม Medication เข้าไปผูกที่เวลานั้น ระบบจะสั่งสร้าง Local Notification ตามเงื่อนไขวันที่เลือก
4. **แจ้งเตือนและแอคชันควบคุม (Grouped Noti & Snooze):**
   - เมื่อถึงเวลา แจ้งเตือนจะดังขึ้น (หากปล่อยทิ้งไว้ จะเตือนซ้ำทุกๆ 1 นาที เป็นจำนวน 2 ครั้ง)
   - เมื่อกดที่ Notification จะเปิดหน้า `/med_detail` ขึ้นมา แสดงรายการยา "**ทั้งหมด**" ที่กำหนดให้ต้องทานในรอบเวลานั้น
   - ผู้ใช้มีทางเลือก 3 อย่าง คือ:
     - กดยืนยันทานยา "**รายตัว**" 
     - กดยืนยัน "**รับประทานยาทั้งหมด**" ทีเดียว
     - กดปุ่ม "**เลื่อนเวลา (Snooze)**" ให้เตือนใหม่ในอีก 15 นาที
   - เมื่อยืนยันทานยาตัวใดไปแล้ว ระบบจะจัดการลดจำนวนคงเหลือของยา (amount) ให้ใน Firestore ทันที

## 6. สิ่งที่กำลังพัฒนาต่อ (Future Plans / WIP)
(อ้างอิงจากเอกสาร `Planning.md`)
- การพัฒนา UI หน้าจอแสดง **ประวัติการกินยาในแต่ละวัน** เพื่อให้เห็นการทำงานของ History ที่ชัดเจน
- ปรับปรุงและเปิดใช้ **ระบบติดตามญาติ (Follower/Following)** ในหน้า UI อย่างสมบูรณ์ รวมถึงการส่งข้อมูลและเตือนข้ามเครื่องผ่านแพ็กเกจ Firebase Cloud Messaging ทันทีที่ผู้ป่วยละเลยการทานยา

## 7. ประเด็นที่ควรระวัง (Known Issues / Watchouts)
- เคยพบปัญหาแอปพลิเคชันค้าง (Hang) หรือบิลด์ (Build) ช้ามากผิดปกติในบางสภาพแวดล้อม ภายหลังจากมีการเพื่ม Support แพ็กเกจภาษาไทย (Thai Localization)
