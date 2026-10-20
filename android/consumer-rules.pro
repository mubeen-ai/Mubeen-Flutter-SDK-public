# ============================================================================
# mubeen_flutter — consumer R8 keep rules.
#
# Applied to the CLIENT APP's R8 pass. The SDK AAR ships its own consumer rules
# (device_intel_lib/consumer-rules.pro) and AGP applies those too, so the SDK
# block below is a mirror, not a replacement: it exists so a client who resolves
# deviceintel-lib from a flat-dir/local AAR, or who strips consumer rules, still
# gets a working release build. Keep the two files in sync.
# ============================================================================

# --- Plugin entry point (instantiated reflectively by the engine) + the
#     Pigeon-generated message classes. ~20 classes; not worth enumerating. ---
-keep class ai.mubeen.mubeen_flutter.** { *; }
-keepclassmembers enum ai.mubeen.mubeen_flutter.** { *; }

# --- Mirror of the SDK's own consumer rules (deviceintel-lib 1.7.3) ---
-keep class ai.mubeen.deviceintel.MB_DeviceIntel { *; }
-keep class ai.mubeen.deviceintel.MB_DeviceConfig { *; }
-keep class ai.mubeen.deviceintel.ErrorCallback { *; }
-keep class ai.mubeen.deviceintel.DeviceIntelError { *; }
-keep class ai.mubeen.deviceintel.ErrorType { *; }
-keepclassmembers enum ai.mubeen.deviceintel.ErrorType { *; }

# Payload models. Kept defensively: deviceintel-lib 1.7.3 builds the request body itself
# with org.json and posts an okhttp3.RequestBody, so no reflective serializer reads these
# field names today, and renaming them cannot change the wire schema. The rule costs
# nothing and guards a future version that does serialise them reflectively.
-keep class ai.mubeen.deviceintel.models.** { *; }

# Retrofit builds this interface with a runtime Proxy.
-keep interface ai.mubeen.deviceintel.network.DeviceIntelApi { *; }

# Retrofit/Gson need these to read generic signatures and method annotations.
-keepattributes RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations,AnnotationDefault,Signature,InnerClasses,EnclosingMethod,Exceptions

# Benign: the invokedynamic string-concat factory is supplied by the platform at
# runtime, not by the R8 classpath. R8 full mode treats missing classes as errors.
-dontwarn java.lang.invoke.StringConcatFactory

# --- R8 full mode (default since AGP 8) strips the generic signatures Retrofit reads at
# runtime, which surfaces as
#   Upload error: ClassCastException: java.lang.Class cannot be cast to
#   java.lang.reflect.ParameterizedType
# on every upload in a minified build. Reproduced on Android 13 with the example app's
# release APK, 2026-09-16, and every app that depends on this plugin inherits the fix.
#
# The delta is the THREE keeps immediately below, and only those: retrofit2.Call,
# retrofit2.Response and kotlin.coroutines.Continuation. Retrofit 2.9.0's own bundled
# META-INF/proguard/retrofit2.pro already carries the -if/-keep interface pair and the
# keepattributes repeated after them, and the SDK AAR's proguard.txt already keeps
# DeviceIntelApi, so those last three lines are belt and braces. Do not "clean up the
# duplicates" by deleting the first three: they are the ones nothing else supplies, and
# removing them silently breaks every release upload again.
# A defect is filed against the SDK so the fix lands upstream.
-keep,allowobfuscation,allowshrinking interface retrofit2.Call
-keep,allowobfuscation,allowshrinking class retrofit2.Response
-keep,allowobfuscation,allowshrinking class kotlin.coroutines.Continuation
-if interface * { @retrofit2.http.* <methods>; }
-keep,allowobfuscation interface <1>
-keep,allowobfuscation,allowshrinking class ai.mubeen.deviceintel.network.DeviceIntelApi
