class Medication {
  int? id;
  String name;
  String time;
  String? imagePath; // เก็บที่อยู่รูปภาพ (Path)
  String? description; // คำอธิบาย
  int remainingPills; // จำนวนเม็ดที่เหลือ
  int isTaken;

  Medication({
    this.id,
    required this.name,
    required this.time,
    this.imagePath,
    this.description,
    this.remainingPills = 0,
    this.isTaken = 0,
  });

  // toMap ไม่รวม 'id' เพราะใช้ Firestore Document ID แทน
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'time': time,
      'imagePath': imagePath,
      'description': description,
      'remainingPills': remainingPills,
      'isTaken': isTaken,
    };
  }

  factory Medication.fromMap(Map<String, dynamic> map) {
    return Medication(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      time: map['time'] as String? ?? '',
      imagePath: map['imagePath'] as String?,
      description: map['description'] as String?,
      remainingPills: (map['remainingPills'] as num?)?.toInt() ?? 0,
      isTaken: (map['isTaken'] as num?)?.toInt() ?? 0,
    );
  }
}
