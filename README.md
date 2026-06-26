<div align="center">
  
  <h1>📱 Connectify: Premium Social & Calling App</h1>
  <p><strong>A Full-Stack Social App Built with Clean Architecture & Riverpod 🚀</strong></p>

  <p>
    Connectify is a production-ready, feature-rich social media and communication application built in Flutter. It seamlessly combines <strong>Real-time Chat, Video/Audio Calling, and Social Feeds (Posts & Reels)</strong> into a single, premium user experience. Built to impress, this app focuses on robust state management, scalable cloud infrastructure, and top-tier UI/UX design.
  </p>

  <h3>
    <a href="https://github.com/jithinc29/agora-firebase-riverpod-calling-system/releases/download/v3.1.0/v3.1.0.apk">📥 Download & Test Latest APK</a>
  </h3>
</div>

<hr>

## 🌟 Key Features

<table width="100%">
  <tr>
    <td width="50%" valign="top">
      <h3>📞 Real-Time Communication</h3>
      <ul>
        <li><strong>Instant Audio & Video Calls</strong>: Low-latency, high-quality peer-to-peer communication powered by <strong>Agora RTC</strong>.</li>
        <li><strong>Background CallKit</strong>: Native incoming call screens even when the app is killed, using <strong>FCM</strong> and <strong>CallKit</strong>.</li>
        <li><strong>Real-Time Chat</strong>: Live messaging system for seamless text-based conversations.</li>
      </ul>
    </td>
    <td width="50%" valign="top">
      <h3>🌐 Social Network</h3>
      <ul>
        <li><strong>Dynamic Feeds</strong>: Share photos, short-form videos (Reels), and text updates.</li>
        <li><strong>Automated Video Compression</strong>: Built-in, on-device video compression.</li>
        <li><strong>Follower System</strong>: Send requests and build your personal network.</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <h3>🎨 Premium UI/UX</h3>
      <ul>
        <li><strong>Modern Aesthetics</strong>: Curated Midnight/Indigo color palettes with soft shadows, dynamic layouts, and fluid micro-animations.</li>
        <li><strong>Global Typography</strong>: Clean, readable interface using <em>Plus Jakarta Sans</em>.</li>
      </ul>
    </td>
    <td width="50%" valign="top">
      <h3>🛡️ Robust Architecture</h3>
      <ul>
        <li><strong>Clean Architecture</strong>: Strictly layered separation of concerns ensuring scalability.</li>
        <li><strong>Riverpod</strong>: Reactive, safe, and boilerplate-free global state management.</li>
        <li><strong>Scalable Cloud Backend</strong>: Automated media deletion via <strong>Firebase Cloud Functions</strong>.</li>
      </ul>
    </td>
  </tr>
</table>

<hr>

## 🏗️ Technical Stack

<div align="center">
  <table>
    <tr>
      <th>Category</th>
      <th>Technology</th>
    </tr>
    <tr>
      <td><strong>Frontend</strong></td>
      <td>Flutter (Dart)</td>
    </tr>
    <tr>
      <td><strong>State Management</strong></td>
      <td>Riverpod (Code Generation)</td>
    </tr>
    <tr>
      <td><strong>Backend / DB</strong></td>
      <td>Firebase Firestore & Storage</td>
    </tr>
    <tr>
      <td><strong>Authentication</strong></td>
      <td>Firebase Auth</td>
    </tr>
    <tr>
      <td><strong>Audio / Video</strong></td>
      <td>Agora SDK</td>
    </tr>
    <tr>
      <td><strong>Push Notifications</strong></td>
      <td>Firebase Cloud Messaging (FCM)</td>
    </tr>
    <tr>
      <td><strong>Token Servers</strong></td>
      <td>Vercel Serverless Functions</td>
    </tr>
  </table>
</div>

<br>

## 🛠️ Setup & Installation

### 1. Requirements
- Flutter SDK (Latest Stable)
- Firebase Project (Blaze Plan required for Cloud Functions)
- Agora Account (App ID and App Certificate)

### 2. Backend Deployment

**A. Vercel (Agora Token Server)**
```bash
cd vercel_backend
vercel --prod --yes
```

**B. Firebase Functions**
```bash
cd functions
firebase deploy --only functions
```

### 3. Build & Run
```bash
flutter clean
flutter pub get
flutter run
```

<hr>

<div align="center">
  <h3>👤 Author</h3>
  <p><strong>Jithin C</strong></p>
  <a href="https://github.com/jithinc29">GitHub Profile</a>
  <br><br>
  <p><em>If you're a recruiter looking at this project, feel free to clone it, test it, and reach out! Star ⭐ this repository if you find it helpful!</em></p>
</div>
