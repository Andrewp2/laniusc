# Trait-bound compound result contracts

The stdlib clone admission exposed two checker defects: a valid required
method returning `Result<T,E>` rejected when `E` remained symbolic, while a
bound's concrete error type could be replaced by an incompatible receiving
type. The repair is `972f0564`. It changes private GPU checker/projection
passes; it adds no public IR, serialized ABI field, extractor or proof change.

## Binding and scope authority

For a call through `T: Produce<T,E>`:

1. Method selection admits one required member from the checked lexical bound.
   That bound supplies its ordered type arguments in caller scope.
2. The complete result is instantiated under those arguments. A receiving
   annotation must agree with them. It cannot replace a bound `E` with `F`.
3. The accepted call result is already in caller scope. Semantic projection
   preserves that whole graph rather than selecting a provisional declaration
   instance or applying callee parameter slots to its children again.

The last rule matters for `helper<E,T>` returning `Result<T,E>`: caller slot 0
means `E`, while the trait's slot 0 means `T`. Reinterpreting the accepted
children as trait slots can capture the wrong parameter. Nested applications
such as `Result<Option<T>,E>` obey the same rule.

Ordinary generic calls can still infer genuinely unconstrained parameters
from their receiving type. The prior-agreement check applies to selected
required trait members, whose arguments already have binding authority.

## Actual checked path and repair

The failing import closure is checked as a **local source pack**. Its trace
identified the failing static call with a local function token and no
dependency library identity. Initial imported-interface-only experiments did
not affect it and were removed. This closeout does not claim a repair of every
external binary trait-interface path.

The implementation uses the existing result relation and resources:

- [Local result inference](../shaders/type_checker/calls/03a4b_contextual_result_requests.slang)
  checks receiving bindings against the required member's prior arguments.
  A contradiction reports the final assignment mismatch; busy/capacity behavior
  retains its existing handling.
- [Required-member classification](../shaders/type_checker/methods/local_required_member.slang)
  is shared with bound-call routing. It checks a current-job method-name marker
  before reading sparse owner metadata, so a later ordinary function cannot
  inherit a prior compilation's method classification.
- [Call projection](../shaders/type_checker/semantic/artifact/00_calls.slang)
  prefers the complete accepted compound result over provisional caches.
- [Legacy result completion](../shaders/type_checker/semantic/artifact/00c_generic_call_results.slang)
  preserves its symbolic-environment flag, then leaves accepted compound graphs
  in caller scope. Calls without that accepted result keep their fallback path.

The change adds reads of existing graph resources. It introduces no additional
dispatch or inference loop. No compilation speedup is claimed from source
inspection or the focused test timings.

## Executable evidence

The [focused driver](../tests/compiler_trait_return_context_execution.rs) and
[test-only imported modules](../tests/fixtures/compiler_trait_return_context/README.md)
pass seven serial compilation jobs and three native executions in 4.48 seconds:

- Success and error values retain a user record's `u64`/`i32` fields and an
  error enum's negative `i32` and high `u64` payloads.
- Reversed generic parameter order and nested `Some`, `None` and `Err` execute.
- Symbolic `E` to unrelated `F`, fixed `Fault` to `i64`, and an incompatible
  source argument reject at the required call with `LNC0006`.
- A missing method bound rejects with `LNC0027`.
- An ordinary receiving-inference program executes between trait jobs, followed
  by another native trait execution in the same compiler process.

All native programs pass the common strict x86 control-transfer checker. Two
existing adjacent tests also pass:

| Test in `compiler_generic_types_execution` | Result |
| --- | --- |
| `generic_compound_returns_use_complete_call_environments` | Passed; two native programs; 5.83 s |
| `imported_generic_inferred_compound_returns_preserve_values_copies_and_aliases` | Passed; one native program; 3.68 s |

The separate [clone re-admission](../tests/fixtures/stdlib_compiler_state/clone_admission/AFTER.md)
passes intended stdlib-root classification, independent String owners and
partial two-String record cleanup with exact allocation ledgers. Its original
before-fix results remain preserved; production clone acceptance is recorded
in that API's own guide.
The [capture-time source-root note](../tests/fixtures/stdlib_compiler_state/clone_admission/REPRODUCTION.md)
explains how to avoid combining historical prototype implementations with
later production String implementations.

Execution evidence is x86_64 Linux output from GPU compilation. This does not
establish user GPU execution, arbitrary generic implementation forwarding,
automatic destruction, or general lifetime enforcement. The
[remaining compiler dependencies](library-dependencies.md) continue to track
those boundaries separately.
