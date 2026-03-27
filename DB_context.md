ผมออกแบบให้เป็นแบบ Relational-like ใน Firestore เพื่อความยืดหยุ่นครับ

[Collection] users
เก็บข้อมูลผู้ใช้และระบบญาติ

uid: string (Auto-generated Document ID จาก Firestore)

username: string

phoneNumber: string

password: string (เก็บรหัสผ่านสำหรับล็อกอินด้วยเบอร์โทร)

userCode: string (เช่น RX-9981 ใช้สำหรับให้คนอื่นค้นหาเรา)

monitoredUserUids: array [uid_1, uid_2] — เก็บ UID ของ "คนที่เราไปกดติดตาม" (เราเป็นญาติเขา)

followerUids: array [uid_3, uid_4] — เก็บ UID ของ "คนมาที่ติดตามเรา" (เขาเป็นญาติเรา)

[Collection] Schedules
เก็บ "เวลา" และ "เงื่อนไข" การกินยา (ตามข้อ 3)

scheduleId (Document ID): string

userId: string (เจ้าของตาราง)

meal: string ('morning', 'lunch', 'dinner', 'before_bed')

time: string ('08:00')

instruction: string ('before_meal', 'after_meal')

isActive: boolean

[Collection] Medications
เก็บรายละเอียดตัวยา (ตามข้อ 4 และ 5)

medId (Document ID): string

scheduleId: string (Reference ไปยังตารางเวลา)

userId: string

medName: string

amount: number (เช่น 2)

unit: string (เช่น เม็ด, ช้อนโต๊ะ)

imageUrl: string (URL จาก Firebase Storage)

days: array ['Monday', 'Tuesday', ...] (วันที่จะกินยา)

โครงสร้าง Collection: MedicationLogs (Firestore)
แทนที่จะเก็บแค่สถานะปัจจุบัน เราจะใช้ตัวนี้เป็น "บันทึกรายรายการ" (Transaction Log) ครับ

logId (Document ID): string

userId (Index): string — UID ของผู้ป่วย (เพื่อให้ Query ตามรายคนได้เร็ว)

medId : string — ID ของยา

scheduleId: string — ID ของรอบเวลา

medName: string — (Denormalization) เก็บชื่อยาไว้ที่นี่เลย เผื่อผู้ใช้ลบยาตัวนั้นไปแล้ว ประวัติจะได้ยังเห็นชื่อยาอยู่

plannedTimestamp (Index): timestamp — วัน/เวลาที่ระบบควรจะเตือนตามแผน

actualTimestamp: timestamp — วัน/เวลาที่กด "กินยาแล้ว" จริงๆ

status: string — 'taken' (กินแล้ว), 'skipped' (ข้าม), 'missed' (ลืมกิน/เลยเวลาแล้วไม่กด)

note: string — บันทึกเพิ่มเติม เช่น "กินแล้วคลื่นไส้" หรือ "ลืมเพราะอยู่นอกบ้าน"

takenBy: string — UID ของคนที่กดบันทึก (กรณีญาติเป็นคนกดให้ตอนอยู่ด้วยกัน)

snoozeCount: number (เก็บว่าเลื่อนไปกี่ครั้ง)