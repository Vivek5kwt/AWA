# Keep Razorpay classes
-keep class com.razorpay.** { *; }
-dontwarn com.razorpay.**

# Kotlin
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**

# Coroutines
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# Firebase
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
