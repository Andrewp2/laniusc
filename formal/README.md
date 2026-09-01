# Lanius formal semantics

This directory contains the mechanized language model for Lanius. It is an
engineering specification for the language, not a claim that the current
Rust/Slang compiler has been verified.

[`PROOF_ARCHITECTURE.md`](PROOF_ARCHITECTURE.md) proposes the relational
specification and weakest-precondition pilot for reducing the cost of proving
compiler code written in Lanius. It is a pilot design, not part of the settled
language semantics recorded here.

The model deliberately separates four levels:

1. `Lanius.Surface` describes the source constructs accepted by Lanius.
2. `Lanius.Names` defines module/import/visibility lookup.
3. `Lanius.Static` retains generic types, const parameters, trait obligations,
   implementation selection, and method receivers through monomorphization.
4. `Lanius.Core` is the resolved, monomorphic language on which typing and
   execution are defined.

`Lanius.Elaboration` defines literal, type, receiver, and method lowering.
`Lanius.SurfaceElaboration` connects lexical bindings and module-aware global
lookup to generic function instances, fields, expressions, and recursive
places. It also resolves symbolic struct and enum constructor schemes before
selecting their monomorphic artifacts. These boundaries are intentional:
source semantics must not depend on
token numbers, parse-tree scaffolding, GPU buffer layouts, or the current
compiler's HIR representation.

## Modules

- `Lanius.Basic` defines semantic identifiers and observable traps.
- `Lanius.Surface` defines files, declarations, types, statements,
  expressions, patterns, traits, implementations, and generics.
- `Lanius.SurfaceSyntax` restricts those abstract terms to shapes admitted by
  the concrete grammar, including nonempty paths, final-segment type
  arguments, bound-type syntax, and recursively well-formed declarations.
- `Lanius.LiteralSyntax` decodes classified lexer tokens into surface literals.
- `Lanius.ConcreteSyntax` removes right-recursive grammar scaffolding with
  an indexed expression tree whose types enforce every precedence layer,
  exact operator membership, unary recursion, grouping, and source-ordered
  postfix normalization. It also decodes pattern, array-length, import-string,
  and external-ABI tokens.
- `Lanius.ConcreteProgramSyntax` retains those concrete expressions through
  statement bodies, functions, externs, traits, implementations, constants,
  and files, then deterministically lowers grammar-admitted files to
  `Lanius.Surface`.
- `Lanius.Core` defines the resolved language used by the formal judgments.
- `Lanius.Names` defines local-first and imported-name lookup, qualified module
  access, visibility, and ambiguity rejection.
- `Lanius.Static` defines generic substitution, trait satisfaction, unique
  implementation/method selection, and the monomorphization boundary.
- `Lanius.Elaboration` begins the explicit surface-to-core relation.
- `Lanius.SurfaceElaboration` defines lexical/global resolution and typed
  expression/place/statement lowering into monomorphic core terms.
- `Lanius.SourceWellFormed` validates parameter uniqueness and the names,
  scopes, pattern bindings, and loop-control placement of every declaration
  body independently of monomorphic demand.
- `Lanius.ProgramElaboration` connects source-pack declarations, generic
  schemes, declaration-wide symbolic body typing, monomorphic instances,
  trait contracts, external bindings, and constant dependency order to a
  complete typed core program.
- The `Lanius.*Functionality` modules prove exact specialization deterministic
  from expressions through nested statement bodies and emitted function IDs.
- `Lanius.RuntimeBindings` maps all current standard-library extern ABI/name/
  signature combinations to executable host services, terminal panic hooks,
  or explicit unavailable capabilities and proves the catalog coherent.
- `Lanius.CurrentFeatureAudit` anchors the audited grammar by digest and exact
  production counts, snapshots all 68 compiler-materialized symbols, proves
  every symbol belongs to a modeled language/runtime category, and verifies
  every eagerly materialized external name has a canonical binding.
- `Lanius.WholeProgramWitnesses` packages a nonempty source program through
  source-pack and catalog completeness, symbolic declaration checking,
  monomorphization, core lowering, typing, layout, and artifact coverage under
  the complete-program judgment.
- `Lanius.CurrentSemanticCoverage` is the checked summary certificate tying
  the current grammar/symbol snapshots to deterministic concrete lowering,
  exhaustive expression/statement specialization functionality, canonical
  external bindings, nonempty complete-program integration, deterministic
  dynamics, and whole-program preservation.
- `Lanius.Layout` defines target-dependent byte size, alignment, struct field
  offsets, and tagged-enum payload placement.
- `Lanius.Typing` defines value, expression, statement, function, and program
  typing judgments.
- `Lanius.Memory` defines allocation, reallocation, deallocation, and bytewise
  access over abstract allocation identities.
- `Lanius.World` defines reproducible process inputs, environment state,
  entropy, clocks, standard streams, files, handles, and canonical runtime
  service effects.
- `Lanius.Semantics` defines left-to-right expression evaluation and statement
  execution, including calls, control flow, traps, and heap effects.
- `Lanius.Fuel` proves that terminal expression, statement, and whole-program
  results are unchanged by additional evaluator fuel.
- `Lanius.Dynamics` exposes fuel-independent expression, statement, and
  whole-program evaluation relations, including termination and divergence.
- `Lanius.Soundness` connects those public dynamic relations to expression,
  statement, and whole-program type and runtime-state preservation.
- `Lanius.Properties` defines the stable-cell store invariant and contains the
  metatheory lemmas for stable allocation, lexical unbinding, typed references
  and slices, recursive aggregate projection, and state-typing preservation by
  direct and projected assignment. Its evaluator-preservation relation records
  both monotone store growth and preservation of initialized cell identities.
  It currently covers literal/local evaluation; scalar casts; unary and binary
  operations, including short-circuiting and arithmetic traps; left-to-right
  expression lists and aggregate construction; field, array, and slice reads;
  recursive place resolution; borrows and dereferences; direct, compound, and
  projected assignment; place-backed and temporary array-to-slice conversion;
  constant lookup; ordered pattern matching with scoped bindings; and the
  `print_i32` and `assert` intrinsics. These proofs preserve both result types
  and all embedded reference descriptors across intervening state, scope, and
  world changes. Statement preservation now covers every typed statement:
  sequencing, conditionals, initialized and deferred locals, `while`, array/
  slice and numeric-range `for`, returns, and loop-control completions. The
  proof consumes `break`/`continue` at loop boundaries, retains stable cells,
  and restores exact caller-local environments. Internal call preservation
  connects typed argument evaluation, parameter binding, whole-body execution,
  return completion, and caller-scope restoration. Raw allocation,
  reallocation, deallocation, byte loads, byte stores, borrowed-array mapping,
  and both synchronization directions now preserve a stronger runtime
  invariant containing heap geometry and every registered borrowed view.
  Every concrete host-service branch satisfies its typed heap/world effect
  contract. Host and opaque calls are connected through synchronization to the
  evaluator's actual external-call branches; opaque responses must be closed
  and valid at every declaration sharing their external identity. The stronger
  runtime relation now also composes left-to-right expression lists and array,
  struct, and enum construction without losing earlier borrows or registered
  view validity. A strict strong induction on evaluator fuel closes the
  recursive contract across expressions, places, match arms, statements,
  loops, and internal calls. The public expression and statement preservation
  theorems therefore have no recursive preservation premise.
- `Lanius.Examples` contains executable semantic examples checked by Lean.

Build the complete formalization with:

```sh
cd formal
./check-current-sources.sh
lake build
```

The relational compiler-proof pilot has two explicit assurance gates:

```sh
./check-assurance.sh fast
./check-assurance.sh kernel-clean
```

The fast profile records `#print axioms` for both public scanner theorems and
allowlists only the isolated complete checked-pack `native_decide`
certificate. The kernel-clean profile accepts no native axiom and contains an
exact proof-producing replacement split into evidence, semantics, and global
resolution phases. It is intentionally separate from normal builds: a
10m27s bounded run did not finish, although it produced no proof failure;
evidence stayed near 1.7 GiB while semantics grew to roughly 10 GiB. Direct
`decide +kernel` was rejected after reaching 27 GiB RSS plus 17 GiB swap.
Until the checker is decomposed more finely, the fast profile is the practical
CI gate and the kernel-clean profile is a resource-intensive audit target. See
`PROOF_ARCHITECTURE.md` for the pilot boundary and acceptance checklist.

## Current boundary

The concrete and surface syntax layers represent the present grammar, with a
checked deterministic boundary from precedence-indexed expressions and
grammar-shaped declarations into `Surface.File`. The
mechanized typing and dynamic semantics currently cover the resolved core:
all source-visible primitive scalar widths, target-sized integers, IEEE
floating-point arithmetic, arrays, structs, enums, lexical locals, functions,
conditionals, array/range loops, ordered pattern matching, recursive assignment
places, deferred initialization, immutable references, constants, returns, raw
allocation primitives, and executable host service families. Numeric
conversions are explicit in core. Generic substitution, trait satisfaction,
unique method selection, generic function-instance selection, receiver
lowering, explicit call type/const arguments tied to monomorphic-instance
identity, qualified name visibility, default-versus-contextual literal
elaboration, and a substantial
surface expression, pattern, place, and statement lowering now have checked
judgments, including inferred locals, lexical shadowing, control flow, ranges,
generic calls, named struct fields, enum variants, and match-arm bindings.
Generic aggregate construction supports explicit arguments, inference from
member types, and checking against an expected nominal type without depending
on which other monomorphic instances happen to be resident.
Source-pack shape and dependency ordering, declaration-local module contexts,
declaration collection, generic schemes, trait contracts,
implementation-method validation, monomorphic artifact coverage, explicit
external ABI binding, declaration-metadata uniqueness, and structurally
restricted constant dependency ordering now meet in one
bidirectional complete-program judgment. Closed whole-expression and
whole-statement preservation theorems now lift the state-transition lemmas
through all control flow, calls, raw memory operations, host effects, and
opaque foreign responses. Whole-program preservation then connects the
selected zero-argument entrypoint to ordinary return, explicit process exit,
terminal traps, and fuel exhaustion while retaining the runtime-state
invariant. For the grammar, compiler language-symbol table, and stdlib extern
catalog fixed by `CurrentFeatureAudit` and `check-current-sources.sh`, the
source syntax, static semantics, memory model, and dynamic semantics are
covered. The checked `CurrentSemanticCoverage.current` certificate records the
cross-layer result. Stronger generic metatheory, target ABI conformance,
generated-program differential testing, and verification of either compiler
are follow-on verification projects rather than missing source-language
semantics.

`Lanius.Examples` contains the component derivations for a nonempty checked path
from a source `main` declaration through header collection, scheme collection,
monomorphic function lowering, core typing, unique entrypoint selection,
executable observation, and the whole-program preservation theorem.
`Lanius.WholeProgramWitnesses.checkedMainComplete` assembles those derivations
with source/catalog/import completeness, metadata uniqueness, artifact
coverage, core-ID uniqueness, and layouts into one nonempty
`CompleteProgramElaboration`. Separate executable examples distinguish ordinary
return, explicit process exit, panic, and fuel exhaustion.

The executable evaluator is fuel-indexed so it remains a total Lean function.
The public dynamic relation is not: it states that some sufficient finite fuel
produces a terminal observation. A mutual induction over every evaluator
component proves that any terminal return, exit, or trap is unchanged by
additional fuel, including its final heap, world, locals, and stable borrowed
views. This makes the relational semantics deterministic. Divergence means
every finite approximation exhausts its fuel; one `outOfFuel` result alone
states only that termination has not yet been established.

See `SEMANTIC_DECISIONS.md` for the behaviors fixed by this model and the
remaining language-design decisions. `FEATURE_COVERAGE.md` tracks every
construct and runtime family found in the current grammar, standard library,
and checked sample suite.
