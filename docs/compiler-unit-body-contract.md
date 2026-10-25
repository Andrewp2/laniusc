# Executable unit bodies and deferred trait calls

The clone admission exposed an empty-function lowering bug. A separate focused
regression exposed an unspecialized generic helper whose concrete ABI hid an
unresolved static trait call. Both repairs use existing private GPU lowering
records, resources and passes. They change no public IR, extractor, formal proof
or x86 ABI record.

## A definition needs an executable return

An actual unit-function body can fall through even when its syntax produces no
other instruction. Target functions were discovered from instruction rows;
`{}` produced none. The x86 implicit footer attaches to a final target
instruction, so it could not create that missing function. A required trait
declaration ending in `;` correctly had no body, but an empty implementation
incorrectly reached the same native outcome.

The [count producer](../shaders/codegen/lir/semantic/count.slang) now admits one
existing bare RETURN row for unit-function fallthrough and the entrypoint's
default exit. Its [predicate](../shaders/codegen/lir/semantic/body_return.slang)
requires an actual body block, its direct function parent, and the exact admitted
function identity. Bodyless declarations and deferred bodies gain no row.

The [scatter consumer](../shaders/codegen/lir/semantic/scatter.slang) schedules
that row at the body's close with void type, no value words and no operand.
Ordinary blocks publish zero rows; the count producer is the authority for this
synthetic block row. Nested empty blocks therefore work too, without scanning
the entire function. An earlier explicit return makes the fallthrough row
unreachable; existing CFG authority excludes it from target emission.

## A concrete signature does not close implementation selection

The second reproducer imports this shape:

```lanius
pub fn imported_closed<T>(source: Item) where T: ClosedDestroy {
    T::closed_destroy(source);
    return;
}
```

Its argument and result layouts are concrete, but `T` still determines the
implementation. The original helper was admitted before that selection. Its
unrouted required declaration became a symbol call, and linking reported
LNC0017 even when no source call used the helper.

A retained function-scatter capture identified the missing identity exactly:
symbol `0x4000005b` was the bodyless `ClosedDestroy::closed_destroy`, HIR 40,
under trait HIR 39. It was not an inlined helper or a generic instance ID.
The helper itself remained admitted while the required declaration correctly
had no definition. Removing generic forwarding calls or the nested-empty call
did not alter this failure.

[Template admission](../shaders/codegen/lir/semantic/function_templates.slang)
now withholds an original generic body when a local static target still names a
trait requirement. It checks the enclosing generic environment before doing the
target lookup. [Shared function identity lookup](../shaders/codegen/lir/semantic/function_generic_environment.slang)
preserves the existing exact start-token policy used by call projection.
Concrete replay retains its implementation-selection authority. The repair
never manufactures a native body for a required declaration and does not
unconditionally replay every otherwise concrete generic helper.

This closes the reproduced local requirement path. Exporting a generic
implementation's complete environment remains a separate
[compiler dependency](library-dependencies.md).

## Executable evidence and cost

The [focused driver](../tests/compiler_empty_body_execution.rs) and
[fixtures](../tests/fixtures/compiler_empty_body/README.md) pass six compilation
jobs and four native executions in 3.21 seconds:

- Empty local/imported free, inherent and trait implementation methods execute.
- Direct, local generic and imported generic dispatch preserve record payloads.
- Nested empty blocks, nonempty unit fallthrough and both minimal entry forms
  execute; borrowed mutation preserves its neighbor sentinel.
- Missing implementation calls still reject with LNC0008 and LNC0027.
- The full native fixture executes again after the rejection jobs in the same
  compiler process. Every ELF passes the common strict x86 transfer checker.

The [clone gates](stdlib-clone.md) also execute natural empty destructors,
including packed bytes and zero-sized values. Their individual evidence and
allocation-failure coverage are recorded separately.

The normal shader budget remains enforced. Scatter measures 39,949 fully
inlined instructions against its 40,000 limit; template admission measures
19,873. A set-equivalent expression-kind predicate represents the same
`{14..24, 28, 33, 34}` kinds with contiguous range checks, reducing duplicated
shader code. No budget override was used. Fallthrough adds one private semantic
row per admitted unit/entry body, with no new pass or resource. These measurements
do not establish a compilation speedup.

Logs and the diagnostic capture are under `target/stdlib-work/clone-production/`.
Execution evidence is GPU-compiled x86-64 Linux output. User GPU execution and
other targets are not established by these tests.
