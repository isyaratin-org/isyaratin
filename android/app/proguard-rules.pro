# WorkManager 2.7 (pulled transitively by ML Kit) constructs Room's generated
# database implementation via reflection. Keep Room database implementations
# and their no-argument constructors for release builds using R8 full mode.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class **_Impl { <init>(); }

# ML Kit discovers these registrars from AndroidManifest metadata and creates
# them reflectively. R8 full mode otherwise removes their empty constructors,
# making pose detection unavailable only in release builds.
-keep class * implements com.google.firebase.components.ComponentRegistrar { public <init>(); }
