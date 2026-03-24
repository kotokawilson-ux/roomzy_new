# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Firestore
-keep class com.google.firestore.** { *; }

# Keep your app model classes (update the package name if needed)
-keep class com.example.roomzy_new.** { *; }

# Prevent stripping of Kotlin metadata
-keep class kotlin.** { *; }
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable