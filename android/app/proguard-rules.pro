# Krypta ProGuard Rules
# Security-focused: maximum obfuscation while preserving Flutter functionality.

# --- Flutter Engine ---
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# --- Firebase ---
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# --- Flutter Secure Storage (keystore operations) ---
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# --- Local Auth (biometric) ---
-keep class io.flutter.plugins.localauth.** { *; }

# --- Crypto operations (keep native JNI interfaces) ---
-keepclassmembers class * {
    native <methods>;
}

# --- Prevent stripping of security-critical annotations ---
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# --- Aggressive obfuscation settings ---
-repackageclasses ''
-allowaccessmodification
-overloadaggressively

# --- Remove logging in release (defense in depth with kDebugMode) ---
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
