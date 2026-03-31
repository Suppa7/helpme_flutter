import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class NearbyHospitalsScreen extends StatefulWidget {
  const NearbyHospitalsScreen({super.key});

  @override
  State<NearbyHospitalsScreen> createState() => _NearbyHospitalsScreenState();
}

class _NearbyHospitalsScreenState extends State<NearbyHospitalsScreen> {
  // TODO: ใส่ Google Maps API Key ของคุณที่นี่
  final String _googleApiKey = 'AIzaSyA0BQbq4ciT6ZHivxnOC4dc6s6Smo0u8RU';

  bool _isLoading = true;
  String _errorMessage = '';
  List<dynamic> _hospitals = [];

  @override
  void initState() {
    super.initState();
    _fetchNearbyHospitals();
  }

  Future<void> _fetchNearbyHospitals() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // 1. เช็คสิทธิ์และดึงพิกัด Location ของผู้ใช้
      bool serviceEnabled;
      LocationPermission permission;

      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('กรุณาเปิดการใช้งาน Location Service ในเครื่องของคุณ');
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('ไม่ได้รับอนุญาตให้เข้าถึงตำแหน่งปัจจุบัน');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('สิทธิ์เข้าถึงตำแหน่งถูกปฏิเสธอย่างถาวร กรุณาไปเปิดสิทธิ์ในตั้งค่าเครื่อง');
      }

      // 2. ดึงตำแหน่งปัจจุบัน
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      // 3. ยิง Google Places API (Nearby Search)
      final String url =
          'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
          '?location=${position.latitude},${position.longitude}'
          '&radius=10000' // รัศมี 10 km
          '&type=hospital'
          '&language=th'
          '&key=$_googleApiKey';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          setState(() {
            _hospitals = data['results'];
          });
        } else if (data['status'] == 'REQUEST_DENIED') {
          throw Exception('เกิดข้อผิดพลาดจาก Google Maps: ตรวจสอบ API Key หรือ Billing');
        } else if (data['status'] == 'ZERO_RESULTS') {
          setState(() {
            _hospitals = [];
          });
        } else {
          throw Exception('เกิดข้อผิดพลาดในการดึงข้อมูล: ${data['status']}');
        }
      } else {
        throw Exception('เกิดข้อผิดพลาดในการเชื่อมต่อเซิร์ฟเวอร์');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // เรียกใช้ Place Details API สำหรับบางสถานที่ถ้าอยากได้เบอร์โทรศัพท์ (ถ้า Nearby คืนค่ามาไม่ครบ)
  // แต่เบื้องต้นเปิดผ่าน Google Maps App ได้เลยจะง่ายกว่าและสะดวกกับผู้ใช้
  Future<void> _openGoogleMapsApp(double lat, double lng, String placeId) async {
    final String googleMapsUrl = "https://www.google.com/maps/search/?api=1&query=$lat,$lng&query_place_id=$placeId";
    if (await canLaunchUrl(Uri.parse(googleMapsUrl))) {
      await launchUrl(Uri.parse(googleMapsUrl), mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเปิดแอปแผนที่ได้')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('โรงพยาบาลใกล้ฉัน (10 กม.)'),
        backgroundColor: Colors.green.shade800,
        foregroundColor: Colors.white,
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _fetchNearbyHospitals,
        backgroundColor: Colors.green.shade600,
        child: const Icon(Icons.refresh, color: Colors.white),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.green),
            SizedBox(height: 16),
            Text('กำลังค้นหาตำแหน่งและโรงพยาบาล...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 60, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.red),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      );
    }

    if (_hospitals.isEmpty) {
      return const Center(
        child: Text(
          'ไม่พบโรงพยาบาลในรัศมี 10 กิโลเมตร',
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _hospitals.length,
      itemBuilder: (context, index) {
        final hospital = _hospitals[index];
        final name = hospital['name'] ?? 'ไม่มีชื่อ';
        final address = hospital['vicinity'] ?? 'ไม่มีที่อยู่';
        final Map<String, dynamic>? geometry = hospital['geometry'];
        final Map<String, dynamic>? location = geometry?['location'];
        final double? lat = location?['lat'];
        final double? lng = location?['lng'];
        final String placeId = hospital['place_id'] ?? '';
        
        // Nearby API ปกติไม่มี formatted_phone_number ต้องดึงจาก Place Details
        // แต่เพื่อความไว เราจะให้ปุ่มสามารถเปิด Google Maps ไปดูรีวิว เบอร์โทร และเบาะแสได้เลย

        return Card(
          elevation: 3,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.green.shade100,
                  radius: 30,
                  child: Icon(Icons.local_hospital, color: Colors.green.shade800, size: 30),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade900),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        address,
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: () {
                          if (lat != null && lng != null) {
                            _openGoogleMapsApp(lat, lng, placeId);
                          }
                        },
                        icon: const Icon(Icons.map_outlined, size: 20),
                        label: const Text('นำทาง / ข้อมูลเพิ่มเติม'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade50,
                          foregroundColor: Colors.green.shade800,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: Colors.green.shade200),
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
