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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
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
      id: map['id'],
      name: map['name'],
      time: map['time'],
      imagePath: map['imagePath'],
      description: map['description'],
      remainingPills: map['remainingPills'],
      isTaken: map['isTaken'],
    );
  }
}
