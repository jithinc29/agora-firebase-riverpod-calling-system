# 💎 Premium Calling App
### Real-time Communication with Clean Architecture & Riverpod

A high-end, production-ready Flutter application delivering seamless **Audio & Video Calling** experiences. Built with a focus on premium UI/UX, robust state management, and scalable cloud infrastructure.

---

## 🚀 Key Features

- **⚡ Instant Real-time Calling**: Low-latency Audio and Video communication powered by **Agora RTC**.
- **🔔 Background CallKit Integration**: Professional background notifications and system-native call screens via **FCM** and **CallKit**.
- **🟢 Intelligent Presence Logic**: Accurate user status (Active now/Away) using a synchronized 2-minute "last seen" threshold across all profiles.
- **🎨 Premium UI/UX Design**:
  - Global typography with **Plus Jakarta Sans**.
  - A curated **Midnight/Indigo/Slate** color palette.
  - Responsive, bottom-heavy interaction models optimized for modern mobile displays.
- **🔒 Secure Authentication**: Robust Email/Password authentication flow integrated with Firebase.
- **☁️ Scalable Backend**: Automated call lifecycle management (Join/Leave/Terminate) via **Firebase Cloud Functions** and **Vercel** token generation.

---

## 🏗️ Technical Architecture

This project follows **Clean Architecture** principles to ensure maintainability and testability:
- **Presentation**: State management with **Riverpod** (Code Generation).
- **Domain**: Pure business logic with Entities and Repository interfaces.
- **Data**: Implementation of repositories using Firebase Firestore and Agora.

**Core Tech Stack:**
- **Framework**: Flutter (Dart)
- **State Management**: Riverpod
- **Database**: Firebase Firestore
- **Real-time Audio/Video**: Agora SDK
- **Push Notifications**: Firebase Cloud Messaging (FCM)

---

## 📸 Screenshots & Demo
*(Tip: Add high-quality screenshots or a GIF here to WOW recruiters!)*

---

## 🛠️ Setup & Installation

### 1. Requirements
- Flutter SDK (Latest Stable)
- Firebase Account (Blaze Plan for Cloud Functions)
- Agora Account

### 2. Quick Start
1. **Clone the repo**: `git clone https://github.com/yourusername/call_project.git`
2. **Setup Firebase**: Run `flutterfire configure` to generate `lib/firebase_options.dart`.
3. **Generate Code**: Run `dart run build_runner build --delete-conflicting-outputs`.
4. **Deploy Backend**: 
   - Deploy functions: `cd functions && firebase deploy --only functions`.
   - Setup Agora Webhooks using the deployed `agoraWebhook` URL.

### 3. Build & Run
```powershell
# For Debug
flutter run

# For Release APK
flutter build apk --release
```

---

## 📄 License
Distributed under the MIT License. See `LICENSE` for more information.

---

## 👤 Contact
**Jithin C** - [LinkedIn](https://www.linkedin.com/in/your-profile) - [GitHub](https://github.com/your-username)
