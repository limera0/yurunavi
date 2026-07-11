# Flutter embedding — plugin registration relies on reflection-free codegen,
# but keep defensively since GeneratedPluginRegistrant is invoked from native code.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# MapLibre Native Android SDK — ships its own consumer-rules.pro via AAR, this is a
# defensive backstop in case a future version relies on JNI method names R8 would rename.
-keep class org.maplibre.android.** { *; }
-dontwarn org.maplibre.android.**

# geolocator / permission_handler use enum valueOf() reflection for method-channel args.
-keep class com.baseflow.geolocator.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }

-keepattributes Signature,*Annotation*,EnclosingMethod,InnerClasses

# Flutter's embedding references Play Core's deferred-components (dynamic
# feature delivery) classes even though this app doesn't use split installs.
# Standard Flutter-recommended suppression — see:
# https://docs.flutter.dev/release/breaking-changes/deferred-components-play-core-migration
-dontwarn com.google.android.play.core.**
