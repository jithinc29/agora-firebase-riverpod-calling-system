const express = require('express');
const cors = require('cors');
const { RtcTokenBuilder, RtcRole } = require('agora-token');

const app = express();
app.use(cors({ origin: '*' }));
app.use(express.json());

// Hardcoded credentials for simplicity
const APP_ID = '6554a053a9454af59285b9ec5177fade';
const APP_CERTIFICATE = 'a277026fa1c84711a3210c157d48ec3a';

const nocache = (_, resp, next) => {
  resp.header('Cache-Control', 'private, no-cache, no-store, must-revalidate');
  resp.header('Expires', '-1');
  resp.header('Pragma', 'no-cache');
  next();
};

const generateToken = (req, res) => {
  res.header('Access-Control-Allow-Origin', '*');
  
  const channelName = req.query.channelName;
  if (!channelName) {
    return res.status(400).json({ 'error': 'channelName is required' });
  }

  // Get uid
  let uid = req.query.uid;
  if (!uid || uid === '') {
    uid = 0;
  } else {
    uid = parseInt(uid, 10);
  }
  
  // Get role
  let role;
  if (req.query.role === 'publisher') {
    role = RtcRole.PUBLISHER;
  } else if (req.query.role === 'subscriber') {
    role = RtcRole.SUBSCRIBER;
  } else {
    role = RtcRole.PUBLISHER; // default
  }

  // Get expire time
  let expireTime = req.query.expireTime;
  if (!expireTime || expireTime === '') {
    expireTime = 3600;
  } else {
    expireTime = parseInt(expireTime, 10);
  }

  // Calculate privilege expire time
  const currentTime = Math.floor(Date.now() / 1000);
  const privilegeExpireTime = currentTime + expireTime;

  try {
    const token = RtcTokenBuilder.buildTokenWithUid(
      APP_ID, 
      APP_CERTIFICATE, 
      channelName, 
      uid, 
      role, 
      privilegeExpireTime,
      privilegeExpireTime
    );
    
    return res.json({ 'token': token });
  } catch (err) {
    console.error('Error generating token:', err);
    return res.status(500).json({ 'error': 'Failed to generate token' });
  }
};

app.get('/api/token', nocache, generateToken);

// Vercel serverless functions require the app to be exported
module.exports = app;
