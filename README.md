# 📱 Connectify: Premium Social & Calling App

### A Full-Stack Social App Built with Clean Architecture & Riverpod 🚀

Connectify is a production-ready, feature-rich social media and communication application built in Flutter. It seamlessly combines **Real-time Chat, Video/Audio Calling, and Social Feeds (Posts & Reels)** into a single, premium user experience. Built to impress, this app focuses on robust state management, scalable cloud infrastructure, and top-tier UI/UX design.

---

## 🌟 Key Features

### 📞 Real-Time Communication
- **Instant Audio & Video Calls**: Low-latency, high-quality peer-to-peer communication powered by **Agora RTC**.
- **Background CallKit Integration**: Native incoming call screens even when the app is killed, using **FCM** and **CallKit**.
- **Real-Time Chat**: Live messaging system for seamless text-based conversations.

### 🌐 Social Network
- **Dynamic Feeds (Posts & Reels)**: Share photos, short-form videos (Reels), and text updates with the community.
- **Automated Video Compression**: Built-in, on-device video compression and thumbnail generation to save bandwidth and ensure lightning-fast playback.
- **Follower System**: Send requests, accept/reject followers, and build your personal network.
- **Global Presence System**: Accurate "Active Now" or "Last Seen" status synchronized across all screens.
- **Complete Data Control**: Full account scrub options that recursively wipe users' posts, media, messages, and profiles upon account deletion.

### 🎨 Premium UI/UX
- **Modern Aesthetics**: Curated Midnight/Indigo color palettes with soft shadows, dynamic layouts, and fluid micro-animations.
- **Global Typography**: Clean, readable interface using *Plus Jakarta Sans*.

### 🛡️ Robust Architecture & Backend
- **Clean Architecture**: Strictly layered separation of concerns (Presentation, Domain, Data) ensuring scalability, readability, and testability.
- **Riverpod State Management**: Reactive, safe, and boilerplate-free global state management.
- **Scalable Cloud Backend**: Automated media deletion, secure webhook handling, and call lifecycle management via **Firebase Cloud Functions** & **Vercel** token generation.

---

## 🏗️ Technical Stack

- **Frontend**: Flutter (Dart)
- **State Management**: Riverpod (Code Generation)
- **Backend/Database**: Firebase Firestore & Firebase Storage
- **Authentication**: Firebase Auth (Email/Password)
- **Real-Time Audio/Video**: Agora SDK
- **Push Notifications**: Firebase Cloud Messaging (FCM)
- **Token Servers**: Vercel Serverless Functions

---

## 🛠️ Setup & Installation

### 1. Requirements
- Flutter SDK (Latest Stable)
- Firebase Project (Blaze Plan required for Cloud Functions)
- Agora Account (App ID and App Certificate)

### 2. Backend Deployment

#### A. Vercel (Agora Token Server)
Tokens are generated securely on Vercel to protect your App Certificate.
```powershell
cd vercel_backend
vercel --prod --yes
```

#### B. Firebase Functions
Handles FCM background notifications and Agora webhook callbacks.
```powershell
cd functions
firebase deploy --only functions
```

### 3. Build & Run
```powershell
flutter clean
flutter pub get
flutter run
```

---

## 👤 Author
**Jithin C** 
- [GitHub Profile](https://github.com/jithinc29)

*If you're a recruiter looking at this project, feel free to clone it, test it, and reach out! Star ⭐ this repository if you find it helpful!*
