# Add project specific ProGuard rules here.
# https://developer.android.com/build/shrink-code

# kotlinx.serialization: keep generated serializers for our DTOs.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class com.moodpatterndiary.app.**$$serializer { *; }
-keepclassmembers class com.moodpatterndiary.app.** {
    *** Companion;
}
-keepclasseswithmembers class com.moodpatterndiary.app.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Retrofit / OkHttp: keep line numbers for stack traces, silence platform warnings.
-keepattributes Signature, Exceptions
-dontwarn okhttp3.**
-dontwarn retrofit2.**
