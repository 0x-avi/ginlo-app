# flutter_gemma / MediaPipe LLM: classes reached from native code by name must survive shrinking.
-keep class com.google.mediapipe.** { *; }
-keep class com.google.ai.edge.** { *; }
# Referenced by MediaPipe but not shipped (profiling/graph templates GinLo never uses).
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate
