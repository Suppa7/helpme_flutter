const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

exports.notifyRelativeOnMissedMedication = onDocumentCreated("MedicationLogs/{logId}", async (event) => {
    const data = event.data.data();
    if (!data || data.status !== 'missed') {
        return;
    }

    const { userId, medName, plannedTimestamp } = data;
    if (!userId) {
        console.log('No userId found in MedicationLog');
        return;
    }

    try {
        // 1. ดึงข้อมูลผู้ป่วย (เพื่อเอา username และ followerUids)
        const patientSnap = await admin.firestore().collection('users').doc(userId).get();
        if (!patientSnap.exists) {
            console.log(`Patient users/${userId} not found`);
            return;
        }

        const patientData = patientSnap.data();
        const patientName = patientData.username || 'ผู้ป่วย';
        const followerUids = patientData.followerUids || [];

        if (followerUids.length === 0) {
            console.log(`Patient ${patientName} has no followers. Skipping notification.`);
            return;
        }

        // 2. จัดรูปแบบเวลา (เพิ่ม 7 ชม. เป็น GMT+7)
        let timeStr = 'รอบเวลาที่กำหนด';
        if (plannedTimestamp) {
            const date = plannedTimestamp.toDate();
            const thTime = new Date(date.getTime() + (7 * 60 * 60 * 1000));
            timeStr = `${String(thTime.getUTCHours()).padStart(2, '0')}:${String(thTime.getUTCMinutes()).padStart(2, '0')} น.`;
        }

        // 3. เตรียม Payload ข้อความแจ้งเตือน
        const payload = {
            notification: {
                title: '⚠️ แจ้งเตือนด่วน: ลืมทานยา',
                body: `คุณ ${patientName} ยังไม่ได้ทานยา ${medName} (${timeStr})!`
            }
        };

        // 4. ดึง FCM Token ของตัวญาติแต่ละคน
        const tokens = [];
        for (const uid of followerUids) {
            const followerSnap = await admin.firestore().collection('users').doc(uid).get();
            if (followerSnap.exists) {
                const token = followerSnap.data().fcmToken;
                if (token && token !== '') {
                    tokens.push(token);
                }
            }
        }

        // 5. ส่ง Push Notification รอบเดียวไปยังทุกคน (Multicast)
        if (tokens.length > 0) {
            const response = await admin.messaging().sendEachForMulticast({
                tokens: tokens,
                notification: payload.notification
            });
            console.log(`Sent missed med notification to ${response.successCount} relatives for patient ${patientName}.`);
        } else {
            console.log(`No valid FCM tokens found for followers of patient ${patientName}.`);
        }

    } catch (error) {
        console.error("Error sending relative notification:", error);
    }
});
