# Agora SDK rules
-keep class io.agora.** { *; }
-keep class io.agora.rtc2.** { *; }
-dontwarn io.agora.**

# Firebase and Google Play Services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Flutter and generic rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Ignore missing Play Core classes
-dontwarn com.google.android.play.core.**
