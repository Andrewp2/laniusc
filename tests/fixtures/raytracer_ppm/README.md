This fixture is a future-facing acceptance target for Lanius.

The compiler does not need to compile this program yet. The source is intended
to represent the language surface we want to support for a real small program:
struct-heavy code, f32 arithmetic, arrays of structs, file reads for render
settings, file writes for a PPM image, and `print()` for stdout.

`expected.ppm` and `expected.stdout` are the behavior oracle. The non-ignored
test validates those oracle files against a small reference renderer. The
ignored acceptance test is the point where native codegen should eventually
compile and run `raytracer.lani` and compare its actual outputs against
the same oracle.
