# Layouts from accepted GPU proof terms

This checkpoint contains two passing host planner tests from numeric build 5 and
seven passing physical GPU checks from build 6. Three exercise the new layout
engine; four check scalar/call projection, function ABI projection, aggregate
metadata, and control lowering. Each run records its own binary and frozen
source/shader manifests. These are GPU dispatch/readback tests; they do not
execute a native program through abstract trait-member routing.

## Verified behavior

The GPU derives widths from admitted definition recipes for nested records,
enums, arrays, references, slices, and zero-sized values. The nested test checks
the complete semantic graphs and widths 3, 3, 5, 6, 6, 0, 1, and 3. A fresh
repeat job preserves prior results. Parameter identities with source ordinals 9
and 17 bind in declared operand order. Insufficient arena capacity and a sibling
owner's parameter fail explicitly; a subsequent valid job succeeds without
changing accepted proof storage.

The test inputs use pending original facts followed by the physical program
solver, which owns blanket-implementation selection. The strict standalone
producer is retained for tests that require strict checking. No unchecked native
object is released. `usize` constant parameters use the shared integer-domain
predicate; array extents retain their existing checked u32 limit.

## Startup and limits

The first shader build exceeded the 512 KiB artifact limit. The existing minimum
optimization policy produced a 255,704-byte SPIR-V artifact. Its recorded first
pipeline creation took 31.843 seconds and persisted the cache. The build-6 test
process took 41.334 seconds, mostly creation of other program-proof pipelines.
These timings establish neither cold-start acceptance nor warm throughput. The
probe creates a pipeline without dispatching it; the three acceptance tests
supply the dispatch evidence. Every recorded command took less than two minutes.

Each root has an independent configured work arena and bounded traversal. Zero
width is complete; missing width is distinct. The host copies identities and
GPU-produced widths without evaluating layouts or substituting type parameters.
The result is data and grants no method-call or body-replay authority.

## Remaining integration

The engine is not yet called by NativeProgramSession for abstract required-member
routing. That path must consume the exact accepted implementation proof, preserve
the original member identity, and use these layouts for the selected environment.
Full-width typed constant transport and complete floating-point behavior remain
separate unfinished work. This checkpoint does not claim complete generics or a
refreshed stdlib/large-workload performance gate.
