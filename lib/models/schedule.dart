class ScheduleModel {
  String? scheduleId;
  String userId;
  String meal; // 'morning', 'lunch', 'dinner', 'before_bed'
  String time; // '08:00'
  String instruction; // 'before_meal', 'after_meal', 'none'
  List<String> days; // ['Monday', 'Tuesday', ...]
  bool isActive;

  ScheduleModel({
    this.scheduleId,
    required this.userId,
    required this.meal,
    required this.time,
    required this.instruction,
    required this.days,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'meal': meal,
      'time': time,
      'instruction': instruction,
      'days': days,
      'isActive': isActive,
    };
  }

  factory ScheduleModel.fromMap(String id, Map<String, dynamic> map) {
    return ScheduleModel(
      scheduleId: id,
      userId: map['userId'] ?? '',
      meal: map['meal'] ?? '',
      time: map['time'] ?? '',
      instruction: map['instruction'] ?? '',
      days: List<String>.from(map['days'] ?? []),
      isActive: map['isActive'] ?? true,
    );
  }
}
