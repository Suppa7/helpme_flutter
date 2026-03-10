# ภาพรวมของโปรเจกต์ (Project Context & Overview)

## 1. ข้อมูลทั่วไป
- **ชื่อโปรเจกต์:** test (แอปพลิเคชันเตือนการทานยา)
- **ประเภท:** Flutter Application
- **จุดประสงค์:** เป็นแอปพลิเคชันสำหรับผู้สูงอายุหรือผู้ใช้ทั่วไปเพื่อช่วยแจ้งเตือนการทานยาและบันทึกประวัติเพื่อช่วยให้การทานยาเป็นไปอย่างสม่ำเสมอ

## 2. โครงสร้างและไลบรารีที่สำคัญ (Dependencies)
อ้างอิงจากไฟล์ `pubspec.yaml` มีแพ็กเกจหลักๆ ดังนี้:
- **`cloud_firestore` & `firebase_core`**: จัดการฐานข้อมูลบน **Cloud Firestore** (NoSQL) เพื่อทำ CRUD ข้อมูลยา (ชื่อยา, เวลาทาน, จำนวนที่เหลือ, สถานะการทาน) รวมถึงอัปเดตข้อมูลแบบ Real-time ข้ามอุปกรณ์ (สำหรับแอปพลิเคชันญาติ)
- **`firebase_messaging`**: รองรับ Push Notification ผ่าน FCM
- **`shared_preferences`**: ใช้เก็บข้อมูลเบื้องต้นของผู้ใช้งานในเครื่อง เช่น ชื่อ, และ **รหัสญาติ (relativeCode)** ที่ใช้เป็น Document ID ใน Firestore
- **`flutter_local_notifications` & `timezone`**: ทำหน้าที่สร้างระบบแจ้งเตือน (Local Notification / Alarm) เมื่อถึงกำหนดเวลาทานยา
- **`image_picker`**: ใช้สำหรับถ่ายรูปยาเพื่อให้ผู้สูงอายุเห็นภาพยาที่ชัดเจน

## 3. โครงสร้างโค้ด (Project Structure)
โฟลเดอร์แอพหลักซอร์สโค้ด `lib/` ถูกแบ่งออกเป็นสัดส่วนชัดเจน:
- **`main.dart`**: จุดเริ่มต้นของแอปพลิเคชัน Initialize Firebase, ตั้งค่า `MaterialApp` และ Routing (`/register`, `/home`, `/med_detail`) อีกทั้งยังทำหน้าที่รอรับการกด Notification (NavigatorKey) เพื่อพาไปยังหน้ายืนยันการทานยา และเป็นที่ตั้งของหน้าลงทะเบียน (`RegisterScreen`) และหน้ายืนยันยา (`MedicationDetailScreen`)
- **`firebase_options.dart`**: ไฟล์ที่สร้างโดย FlutterFire CLI เก็บ config ทุก platform สำหรับเชื่อมต่อ Firebase Project `flutter-notification-f1eea`
- **`models/medication.dart`**: Model class กำหนดโครงสร้างข้อมูลยาแต่ละชนิด มีเมธอด `toMap()` และ `fromMap()` สำหรับแปลงข้อมูลกับ Firestore
- **`screens/home_screen.dart`**: หน้าจอหลักของแอป แสดง 3 Tab: ตารางยา, ประวัติการทาน, โปรไฟล์ผู้ใช้
- **`services/database_helper.dart`**: ตัวจัดการ CRUD ผ่าน **Cloud Firestore** (ไม่ใช่ SQLite) โครงสร้าง path: `users/{relativeCode}/medications/{id}`
- **`services/notification_service.dart`**: ตัวจัดการการตั้งเวลาและเปิด-ปิด Local Notification

## 4. โครงสร้างข้อมูลใน Firestore
```
Firestore Root
└── users/
    └── {relativeCode}/          ← Document ID คือรหัสญาติ (สุ่ม 10 หลัก)
        └── medications/
            └── {medicationId}/  ← Document ID คือ int (timestamp-based)
                ├── name: String
                ├── time: String (HH:mm)
                ├── imagePath: String?
                ├── description: String?
                ├── remainingPills: int
                └── isTaken: int (0=ยังไม่ได้กิน, 1=กินแล้ว)
```

## 5. โฟลว์การทำงานหลัก (Main Application Flow)
1. **การลงทะเบียนใช้งาน (First Launch):** แอปจะเช็กตัวแปรชื่อใน `SharedPreferences` หากไม่เจอ จะพาเข้าไปกรอกตัวตนครั้งแรกในหน้า `/register`
2. **หน้าจอหลัก (Home Screen):** เมื่อมีข้อมูลผู้ใช้แล้ว จะเข้าสู่ `/home` ที่โหลดรายการยาจาก Firestore
3. **เพิ่มยา:** กดปุ่ม เพิ่มรายการยาใหม่ → กรอกข้อมูล → บันทึกลง Firestore → ตั้ง Local Notification
4. **แจ้งเตือนและยืนยัน (Notification & Confirmation):**
   - เมื่อถึงเวลา ระบบแจ้งเตือนตามที่ตั้งไว้จะเด้งขึ้นมา
   - Payload จาก Notification พา Navigator ไปที่ `/med_detail` (MedicationDetailScreen)
   - กดยืนยัน "ฉันทานยานี้แล้ว" → อัปเดต Firestore (ลดจำนวนยา, isTaken=1) → ยกเลิก Notification ญาติ
5. **รีเซ็ตรายวัน:** ทุกครั้งที่เปิดแอปในวันใหม่ จะรีเซ็ต `isTaken` ของทุกยากลับเป็น 0 ผ่าน Firestore Batch Write

## 6. สรุป
โปรเจกต์นี้ใช้ **Cloud Firestore เป็นฐานข้อมูลหลัก** (ไม่ได้ใช้ SQLite) ควบคู่กับ Local Notifications สำหรับการเตือน ข้อมูลทั้งหมดถูกเชื่อมเข้าหา Document รหัสญาติแบบเฉพาะบุคคล เพื่อรองรับสเกลแอปญาติ (Relative App) ในอนาคต
