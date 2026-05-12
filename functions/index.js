const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');
const { RtcTokenBuilder, RtcRole } = require('agora-token');

admin.initializeApp();
const db = admin.firestore();

// Agora Config (Sync with lib/core/config/agora_config.dart)
const APP_ID = '6554a053a9454af59285b9ec5177fade';
const APP_CERTIFICATE = 'a277026fa1c84711a3210c157d48ec3a';

/**
 * Generate Agora RTC Token
 */
exports.generateToken = functions.region('us-central1').https.onCall((data, context) => {
    const channelName = data.channelName;
    const uid = data.uid || 0;
    const role = RtcRole.PUBLISHER;
    const expirationTimeInSeconds = 3600;
    const currentTimestamp = Math.floor(Date.now() / 1000);
    const privilegeExpiredTs = currentTimestamp + expirationTimeInSeconds;

    const token = RtcTokenBuilder.buildTokenWithUid(
        APP_ID,
        APP_CERTIFICATE,
        channelName,
        uid,
        role,
        privilegeExpiredTs,
        privilegeExpiredTs
    );

    return { token };
});

/**
 * Initiate Call Signaling
 */
exports.initiateCall = functions.region('us-central1').https.onCall(async (data, context) => {
    const { callerId, callerName, receiverId, receiverName, channelId, isAudioCall } = data;

    const callData = {
        callerId,
        callerName,
        receiverId,
        receiverName,
        channelId,
        status: 'dialing', 
        isAudioCall: isAudioCall || false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    // Store signaling in both docs for easy listening
    await db.collection('calls').doc(receiverId).set(callData);
    await db.collection('calls').doc(callerId).set(callData);
    
    // Also store by channelId for the Webhook to find it
    await db.collection('calls').doc(channelId).set(callData);

    const receiverDoc = await db.collection('users').doc(receiverId).get();
    const fcmToken = receiverDoc.data() ? receiverDoc.data().fcmToken : null;

    if (fcmToken) {
        const message = {
            token: fcmToken,
            data: {
                type: 'call',
                callerName: callerName,
                channelId: channelId,
                callerId: callerId,
                isAudioCall: String(isAudioCall || false),
            },
            android: { priority: 'high' },
        };
        await admin.messaging().send(message);
    }

    return { success: true };
});

/**
 * Agora Webhook Handler
 */
exports.agoraWebhook = functions.region('us-central1').https.onRequest(async (req, res) => {
    const event = req.body;
    const { eventType, payload } = event;
    const channelName = payload ? payload.channelName : null;

    if (!channelName) return res.status(200).send('No channel');

    try {
        const callDoc = await db.collection('calls').doc(channelName).get();
        if (!callDoc.exists) return res.status(200).send('No call found');

        const { receiverId, callerId } = callDoc.data();
        const batch = db.batch();

        if (eventType === 101 || eventType === 103) { // Left or Terminated
            const updates = { status: 'ended', updatedAt: admin.firestore.FieldValue.serverTimestamp() };
            batch.update(db.collection('calls').doc(channelName), updates);
            batch.update(db.collection('calls').doc(receiverId), updates);
            batch.update(db.collection('calls').doc(callerId), updates);
        } else if (eventType === 102) { // Joined
            const updates = { status: 'connected', updatedAt: admin.firestore.FieldValue.serverTimestamp() };
            batch.update(db.collection('calls').doc(channelName), updates);
            batch.update(db.collection('calls').doc(receiverId), updates);
            batch.update(db.collection('calls').doc(callerId), updates);
        }

        await batch.commit();
        return res.status(200).send('Success');
    } catch (error) {
        console.error('Webhook Error:', error);
        return res.status(500).send(error.toString());
    }
});

/**
 * End Call Manually
 */
exports.endCall = functions.region('us-central1').https.onCall(async (data, context) => {
    const { callerId, receiverId, channelId } = data;
    const updates = { status: 'ended', updatedAt: admin.firestore.FieldValue.serverTimestamp() };
    
    const batch = db.batch();
    if (channelId) batch.update(db.collection('calls').doc(channelId), updates);
    if (callerId) batch.update(db.collection('calls').doc(callerId), updates);
    if (receiverId) batch.update(db.collection('calls').doc(receiverId), updates);
    
    await batch.commit();
    return { success: true };
});
