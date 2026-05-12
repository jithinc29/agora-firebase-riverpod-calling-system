const express = require('express');
const cors = require('cors');
const admin = require('firebase-admin');

const app = express();
app.use(cors({ origin: '*' }));
app.use(express.json());

// Initialize Firebase Admin
// Note: You need to set GOOGLE_APPLICATION_CREDENTIALS or use serviceAccountKey.json
// Initialize Firebase Admin using environment variables
if (!admin.apps.length) {
    try {
        admin.initializeApp({
            credential: admin.credential.cert({
                projectId: process.env.FIREBASE_PROJECT_ID?.trim().replace(/^"|"$/g, ''),
                clientEmail: process.env.FIREBASE_CLIENT_EMAIL?.trim().replace(/^"|"$/g, ''),
                // Robust private key cleaning
                privateKey: process.env.FIREBASE_PRIVATE_KEY
                    ?.trim()
                    ?.replace(/^"|"$/g, '')
                    ?.replace(/\\n/g, '\n'),
            }),
        });
    } catch (e) {
        console.error('Firebase Admin Init Error:', e);
    }
}

const db = admin.firestore();

app.post('/api/initiate_call', async (req, res) => {
    console.log('--- New Signaling Request ---');
    console.log('Body:', JSON.stringify(req.body));
    
    // We expect receiverToken and a 'cid' (channelId) for logging, 
    // but we will forward EVERYTHING in the body to the FCM data payload.
    const { receiverToken, cid, receiverId } = req.body;

    if (!receiverToken && !receiverId) {
        console.error('Error: Missing receiverToken or receiverId');
        return res.status(400).json({ error: 'Missing receiverToken or receiverId' });
    }

    try {
        let fcmToken = receiverToken;
        if (!fcmToken && receiverId) {
            console.log('Fetching token for receiver:', receiverId);
            const receiverDoc = await db.collection('users').doc(receiverId).get();
            fcmToken = receiverDoc.exists ? receiverDoc.data().fcmToken : null;
        }

        if (fcmToken) {
            // Prepare the data payload by including everything except the token itself
            const fcmData = { ...req.body };
            delete fcmData.receiverToken;
            
            // Ensure all values are strings for FCM
            Object.keys(fcmData).forEach(key => {
                fcmData[key] = String(fcmData[key]);
            });

            console.log('Forwarding signaling to token:', fcmToken.substring(0, 10) + '...');
            
            const message = {
                token: fcmToken,
                data: fcmData,
                android: {
                    priority: 'high',
                    ttl: 0,
                    direct_boot_ok: true,
                },
                apns: {
                    headers: {
                        'apns-priority': '10',
                        'apns-push-type': 'alert',
                    },
                    payload: {
                        aps: {
                            contentAvailable: true,
                        },
                    },
                },
            };

            await admin.messaging().send(message);
            console.log('FCM sent successfully');
        }

        return res.json({ success: true });
    } catch (error) {
        console.error('Signaling Error:', error);
        return res.status(500).json({ error: error.toString() });
    }
});

module.exports = app;
