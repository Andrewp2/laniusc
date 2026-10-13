# Floating payload checkpoint

The exact decimal converter passed 841 cases on the physical GPU against native Rust parsing and fixed IEEE vectors, including rounding boundaries, subnormal/overflow cases, long decimal tails, malformed spans, and workspace redzones. The converter and parser float shaders use only the Shader capability; neither requests Float64.

The build5 native suite passed six compile-and-execute programs: f32 arithmetic, f64 arithmetic, numeric literal contexts, nested record/Result/Option/array payloads with copy and borrowed mutation, imported mixed-width stack arguments, and portable literal/unary float constants. Five rejection tests passed: incompatible named scalar and Option payload widths, f32/f64 literal overflow, and computed floating constants. Four integer execution/rejection controls also pass on that build.

One native fixture still fails to compile: `native_float_payload_option_scalars`, at an f64 fallback literal after a generic return. The failing suite and its inference trace are preserved; this checkpoint does not claim complete floating payload support. The decimal oracle used build4; native evidence used build5 after repairing absent-family graph initialization and restricting computed-constant diagnostics to actual constant initializer expressions. Every run records its own source and shader snapshots.

No Wasm runtime or refreshed performance acceptance is established. These records predate the full-width typed generic constant migration.
