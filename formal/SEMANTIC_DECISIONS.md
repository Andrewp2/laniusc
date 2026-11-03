# Semantic decisions

This file records decisions embodied in the Lean model. It is deliberately
developer-facing: the source of truth for a settled rule is the corresponding
Lean definition or judgment.

## Settled in the current model

- Complete source packs contain only grammar-admitted abstract syntax. Value
  and type paths are nonempty; ordinary type arguments occur only on the final
  type-path segment; trait bounds contain only paths and immutable references;
  `where` predicates have at least one bound; and these invariants recurse
  through every declaration, statement, expression, pattern, and type.
- Expression operands, function arguments, array elements, struct fields, and
  raw-memory arguments evaluate from left to right.
- `&&` and `||` short-circuit.
- Signed and unsigned integer types retain their source-visible widths.
  Addition, subtraction, multiplication, and unary negation wrap at that
  width.
- The parser-shaped expression `-magnitude` has one direct elaboration when
  `magnitude` is exactly the absolute value of the selected signed type's
  minimum. This admits values such as `-2147483648` without pretending the
  positive magnitude is first representable as `i32`.
- `isize` and `usize` use the selected target's pointer width: 64 bits for
  x86-64 and 32 bits for Wasm32.
- A `char` literal denotes its Unicode scalar code, but the runtime type is an
  unsigned wrapping 32-bit code. Arithmetic, bitwise operations, shifts, and
  unary negation can therefore produce codes that are not Unicode scalars;
  Unicode validity is a property of literals and text conversion, not of every
  intermediate `char` value.
- Division and remainder truncate toward zero. Division by zero, remainder by
  zero, and signed `MIN / -1` trap at every integer width.
- A shift amount outside `0..width-1` traps. Signed right shift is arithmetic;
  unsigned right shift is logical. The amount of a signed or unsigned shift may
  be of any signed or unsigned integer type; its number is what is checked
  (`evalShiftBy`, since 2026-10-30).
- `f32` and `f64` values are represented by their IEEE bit patterns.
  Arithmetic, comparisons, negation and conversions are `Lanius/IEEE.lean`'s,
  on those bits (since 2026-10-30; before, Lean's `Float32` and `Float`):
  round to nearest, ties to even, no traps (division by zero gives an
  infinity), NaN results as x86 SSE gives them (the first NaN operand
  quieted, or the default NaN for an invalid operation). A float to integer
  cast truncates toward zero and saturates, NaN to 0 (Rust's `as`).
- Array indexing outside the array bounds traps.
- Slices are borrowed views identified by an element type, stable backing cell,
  projection path, start, and length. Reads observe later writes to the backing
  array, indexed assignment writes through the view, and an escaping slice stays
  valid while its stable backing cell remains reachable. ABI representation is
  deliberately separate from this semantic identity.
- Arrays, structs, and enums are semantic values. Binding or assigning them
  copies the value; their representation is not an implicit heap object.
- Target layout is explicit and separate from semantic identity. References
  and raw pointers occupy one target pointer word; strings and slices occupy a
  pointer/length pair; structs use aligned declaration-order fields; enums use
  a 32-bit discriminant followed by one aligned maximum-size payload region.
- Assignment uses a recursive place consisting of a local root followed by
  field and index projections. The place, including every index expression, is
  resolved once before the right-hand side. Compound assignment reads the old
  value before evaluating the right-hand side, then writes through the resolved
  path. The mechanized store invariant proves that a same-typed direct or
  recursively projected write preserves the aggregate's type, all unaffected
  borrows, and the typing of the complete stable-cell state.
- Locals are lexically scoped. A function call receives fresh parameter locals
  and shares the caller's heap.
- A declaration without an initializer creates an uninitialized cell. Plain
  assignment initializes it without first reading it. Any actual read,
  borrow, dereference, field/index projection, or compound assignment before
  initialization traps as `uninitializedLocal`.
- Local bindings own stable semantic cells. Immutable references identify a
  cell plus a resolved field/index projection path; they observe later writes
  to that place and remain valid if they escape lexical scope. Cells that are
  no longer reachable are semantic garbage and may be reclaimed without an
  observable effect. Cell identities are unique, allocated monotonically, and
  are not reused while observable; lexical unbinding removes only the local
  name. Lanius currently has no mutable-reference syntax.
- `for` over arrays and slices visits values from left to right. Range bounds are
  evaluated once before iteration. Numeric ranges use `i32`; inclusive ranges
  execute their endpoint once without wrapping into another iteration, and an
  omitted endpoint iterates until control leaves the loop or evaluation runs out
  of proof fuel.
- A path-valued `for` iterable is a named numeric range only when its nominal
  type is exactly `core::range::Range<i32>` or
  `core::range::RangeInclusive<i32>`. Its `start` and `end` fields are selected
  through ordinary field metadata and each is evaluated once when the named
  value lowers to the core range loop. Other nominal types do not acquire range
  behavior merely by having fields with those names.
- A range bound follows the concrete grammar: an integer literal or one
  unqualified name followed by any call/index/member postfix chain. The whole
  bound is checked against `i32` before loop execution, so the ordinary single
  contextual scalar conversion is available.
- A nonempty match infers its result type from the first arm and checks every
  later arm against that type, including the ordinary contextual conversions.
  An empty match cannot infer a result type. At runtime, arms are tried in
  source order, and only the selected arm receives pattern bindings. A match
  with no selected arm traps as non-exhaustive. Completing, trapping, or
  exiting from an arm restores the caller's exact local-name environment while
  retaining every stable cell allocated by the arm.
- Bindings introduced by one pattern have pairwise-distinct source names and
  local IDs. A repeated name such as `Variant(x, x)` is rejected rather than
  acquiring overwrite or implicit-equality semantics.
- `_` is a distinct wildcard pattern, not a path or a binding named `_`.
  Wildcard, binding, and enum-constructor patterns are therefore disjoint in
  the surface syntax as well as in elaboration.
- Statement locals and loop iteration bindings restore the caller's exact
  local-name environment on completion, trap, or process exit. Their stable
  cells remain allocated so an escaping reference retains its identity.
- Typed statement execution preserves the complete state invariant for every
  statement form. Loop bodies may extend the semantic store on each iteration;
  `continue` re-enters, `break` becomes ordinary loop completion, and returns,
  traps, exits, and proof-fuel exhaustion propagate without discarding prior
  initialized cells.
- An internal function call evaluates arguments left to right, replaces the
  visible local environment with freshly allocated parameter cells, executes
  the typed body with `inLoop = false`, and restores the caller's exact local
  names on every terminal path. Cells allocated for parameters and body locals
  remain stable semantic cells, so returned references do not acquire a
  dangling identity merely because the callee scope ended.
- The formal heap uses stable abstract allocation identities. It does not
  prescribe native virtual addresses or an x86-64/Wasm object layout.
- A well-formed raw heap has a positive next allocation identity, unique block
  bases, valid block alignment and byte extents, and pairwise-disjoint block
  intervals. Every block, including a zero-byte allocation's reserved identity,
  lies strictly behind the next-allocation frontier. Live and freed blocks
  retain their identity in the abstract heap; the `live` bit determines whether
  byte access is permitted.
- Address zero is null. Allocation returns null when a finite abstract heap is
  exhausted and traps when its alignment contract is invalid.
- Deallocating null is a no-op. A non-null deallocation must name the base of a
  live allocation and provide its exact size and alignment; invalid pointers,
  double frees, and contract mismatches trap.
- Reallocating null behaves as allocation. Reallocating to size zero frees the
  old allocation and returns null. A failed reallocation preserves the old
  allocation. A successful reallocation preserves the common byte prefix and
  zero-initializes new bytes.
- Reading or writing beyond a live raw allocation traps.
- Filesystem paths in raw-pointer APIs are byte sequences; paths supplied as
  `str` use their UTF-8 bytes. Directory ancestry treats one trailing slash as
  a separator rather than introducing an empty path component. Rename succeeds
  unchanged when source and destination are the same existing path, rejects an
  occupied destination, updates open handles and every descendant during a
  directory move, and rejects moving a directory into its own descendants.
  Removing a nonempty directory fails.
- Reaching the end of a non-unit function without returning a value traps at
  runtime and is rejected by the current function typing judgment.
- Compiler-known host services carry semantic identities and must exactly match
  their canonical parameter and return types. Known unavailable capability
  families trap as `serviceUnavailable`; panic and unreachable have distinct
  terminal traps. Arbitrary external ABIs remain opaque and trap as
  `unmodeledExtern` until an explicit external-world semantics supplies them.
- The canonical runtime catalog covers all 65 extern declarations in the
  checked-in standard library. Clock APIs without a current runtime binding,
  together with network, thread, and GPU APIs, receive explicit unavailable
  capability behavior rather than an opaque or silently invented effect.
- Process arguments, environment entries, clocks, entropy, standard streams,
  files, and open handles are explicit semantic state. Randomness is consumed
  from an initial entropy stream, so a concrete execution remains reproducible.
- Exhausting either secure entropy stream traps as `entropyExhausted`; it is not
  misclassified as an unknown external function. The monotonic and system
  clocks are streams of readings (10-31, "Clock readings and secure bytes");
  reading past one's end traps as `clockExhausted`. A successful nonnegative
  millisecond sleep advances only the whole-second compatibility clock. A
  negative sleep returns `-1` without advancing time.
- Process exit is a terminal execution outcome distinct from both return and
  trap, and propagates through every enclosing expression, statement, and call.
- Generic type and const parameters are substituted before core execution.
  Trait implementations and methods must resolve uniquely; a complete program
  rejects any two concrete or generic implementation patterns that apply to
  the same ground trait goal, and overlap has no source-order fallback. A
  selected method becomes an ordinary core function call with either the
  receiver value or an immutable receiver borrow prepended.
- Field and method lookup automatically dereference immutable references. For
  an `&self` method call, lookup uses the dereferenced receiver type while the
  call reuses the existing reference as its first argument; it does not borrow
  a temporary dereference. Assignment places do not acquire this automatic
  dereference, because the current language has no mutable references. Every
  exact field derivation explicitly grounds the normalized symbolic receiver
  to the concrete receiver used for member lowering and field-table lookup;
  symbolic and monomorphic field rows cannot be selected independently.
- Monomorphic function and method instances retain their ordered type and
  const arguments in addition to their parameter/return signature. Explicit
  call arguments such as `make<u8>()` are grounded into the very substitution
  that instantiates the selected function. They are not discarded after name
  lookup, and signature-identical instantiations remain distinct.
- Struct and enum construction resolves declaration-level symbolic member
  types before consulting emitted monomorphic artifacts. Explicit constructor
  arguments bind the substitution directly; an expected nominal type supplies
  it contextually; otherwise every generic parameter must occur in a field or
  payload type and is matched against independently inferred expression types.
  Unconstrained parameters therefore have no inferred construction, and adding
  another retained monomorphic instance cannot change source-level inference.
- A receiver-bearing inherent method consumes exactly one receiver at
  parameter zero. The receiver may be written as `self`, `&self`, `self: T`,
  or as an ordinary named parameter whose type is exactly the implementation
  receiver. A member call cannot target a receiverless declaration or place
  ordinary arguments before its receiver; after parameter zero, only ordinary
  named parameters remain.
- `Type::function(...)` is type-qualified inherent-function syntax. A
  receiverless declaration consumes its stored ordinary parameters. A
  declaration with an explicit typed receiver consumes that receiver as its
  first ordinary source argument. `self` and `&self` declarations remain
  member-only. Generic arguments on the owner path are preserved, and the
  associated result is an ordinary core value that can immediately serve as a
  member-call receiver.
- The grammar retains generic parameter and `where` syntax on method
  declarations, but complete collection currently requires both lists to be
  empty for inherent methods, trait contracts, and trait-implementation
  methods. Generics declared by the enclosing trait or implementation remain
  available. This records the current compiler boundary without deleting the
  parsed syntax or pretending unsupported method-local substitution succeeds.
- Inherent-method lookup chooses its visibility tier from the receiver and
  member name before argument checking. Same-module declarations form the
  preferred tier. Only when that tier is empty may public declarations from
  other modules compete. A same-module method with incompatible arguments
  therefore produces a call error rather than allowing lookup to fall through
  to a foreign public method.
- Integer source literals accept decimal, hexadecimal, binary, and octal forms
  with separators. Their mathematical value is checked against the expected
  integer type; absent an expectation, the default is `i32`. Decimal and
  scientific float literals are rounded to explicit `f32` or `f64` IEEE bits
  during elaboration; absent an expectation, the default is `f32`. An expected
  scalar type propagates through unary `+` or `-` directly to its literal, so a
  negative `i64` is not first constrained to `i32` and an `f64` literal is not
  first rounded to `f32`.
- String and character token bodies decode `\\n`, `\\r`, `\\t`, `\\0`, `\\"`,
  and `\\\\` conventionally. Any other escaped character denotes that
  character itself, matching the current compiler. A character literal must
  decode to exactly one character; balanced quotes alone do not make a
  multi-character token a valid source character literal. The current GPU
  literal pass instead takes the first byte of such a token; that is a compiler
  conformance defect, not part of the language semantics.
- Every same-precedence binary operator chain is normalized left-associatively;
  assignment chains are normalized right-associatively; and call, index, and
  member postfixes wrap their base in source order. These are properties of
  the source language, not consequences of the grammar's right-recursive parse
  tree representation. The concrete expression tree is indexed by grammar
  level, so both the tighter operand level and the operators admitted at each
  layer are enforced by its Lean type. Parenthesized expressions re-enter at
  the assignment level before being embedded as a primary.
- Quoted import targets and external ABI names are lexer-reclassified string
  tokens. They use the same quote validation and escape decoding as expression
  string literals before their decoded values enter the surface program.
- Concrete expressions remain precedence-indexed while nested in declarations:
  statement bodies, functions, implementation methods, constants, and complete
  files lower deterministically to the surface AST. A `ConcreteFile` carries a
  proof that every resulting item satisfies the grammar-shape judgment; parser
  production nodes and compiler HIR rows are not part of this language model.
- A nonempty array literal infers its element type from its first element and
  checks every remaining element against that type. An empty array literal has
  no independently inferable element type; it is admitted only where an
  expected `[T; 0]` type is already available.
- A direct module import contributes that module's exported declarations to
  unqualified lookup and authorizes qualified access. A declaration in the
  current module shadows imported declarations of the same name and namespace;
  otherwise distinct imported declarations with that name are ambiguous.
  Imports are not transitive, type/value namespaces remain separate, and
  private declarations are accessible only from their own module.
- Lexical locals shadow unqualified global values for constants, direct calls,
  and enum constructors, including unqualified calls carrying explicit generic
  arguments. Qualified value paths bypass lexical shadowing and continue
  through ordinary module authorization and visibility checks.
- A complete program carries a dependency-ready ordering containing every
  module exactly once, with each direct import before its importer. The
  existence of this order constructively rejects self imports and import
  cycles while exposing the order a bounded compiler can process.
- Every top-level declaration is elaborated in the module recorded by its own
  source header. Entering that module clears lexical locals, generic bindings,
  and substitutions while retaining the source-pack-wide semantic tables.
  Deferred type-alias targets store their declaration module and switch back
  to it during expansion, so private helper types and unqualified names do not
  accidentally resolve in the importing module.
- Declaration-indexed semantic tables are finite functional maps represented
  as compact row lists. Complete elaboration requires rows keyed by the same
  source declaration to be equal, in addition to proving that every row came
  from source and every source declaration has a row. A nominal declaration
  therefore cannot acquire two source type identities or two incompatible
  constructor signatures. A struct source `TypeId` also keys exactly one
  constructor scheme, because symbolic member lookup begins from that identity
  rather than from a source declaration number.
- Symbolic substitutions are semantically observed only through the generic
  parameters declared by the source item whose retained type is being
  instantiated. Two substitution maps that bind the same ordered type and
  const arguments therefore produce the same retained field or variant-payload
  types, regardless of unrelated entries outside that declaration's domain.
- Every function and implementation-method body is name-, scope-, and
  type-checked at declaration collection time, whether or not any monomorphic
  artifact is demanded. The bidirectional symbolic judgment retains type and
  const parameters rather than selecting a concrete instance. Parameter names
  must be distinct; unresolved value/call/constructor paths are rejected;
  match bindings are arm-local and distinct; block and branch locals do not
  escape; `break` or `continue` requires an enclosing loop; and every return,
  operation, place, aggregate, call, pattern, and local declaration must be
  valid under the declaration's generic assumptions. Every demanded function,
  inherent-method, and trait-implementation artifact carries one specialization
  derivation that retains the exact collected generic body context, symbolic
  parameter and return types, ground substitution, dense parameter allocation,
  concrete body, and typed core function. These facts cannot be supplied by
  unrelated declaration-wide and monomorphic witnesses.
- A symbolic trait obligation in a declaration body may be discharged either
  by an identical declared assumption or by a matching implementation in the
  program catalog. Implementation requirements are resolved recursively under
  the same symbolic substitution. A concrete obligation therefore does not
  need to be restated in the caller's `where` clause, while an unconstrained
  caller type still requires an assumption.
- Symbolic method lookup uses only receiver type and member name. Same-module
  declarations form the preferred tier; otherwise only public foreign
  declarations participate. The selected signature then either checks
  inferred argument types or flows its parameter types inward to contextual
  expressions. This admits representable literals such as an unannotated `255`
  at a declared `u8` parameter without allowing argument-list overloading.
- Method selection must remain stable when a generic body is specialized. A
  ground substitution may not make a different method declaration newly
  applicable to the same receiver and name. Such a call is
  rejected as ambiguous instead of silently changing its meaning during
  monomorphization; this matches the compiler's fail-closed exact/generic
  receiver lookup. Complete elaboration therefore requires the finite method
  scheme/instance tables to have receiver/name lookup coherence, rather than asking
  each call-site proof to assume stability independently.
- A method-call specialization is occurrence-indexed. One finite witness
  contains the receiver and argument derivations, the symbolic lookup
  decision, grounding of its generic substitution, the exact emitted method
  row, receiver adaptation, and concrete call. Inferred and contextually
  checked arguments have separate constructors. The formalization does not use
  a universal callback that can manufacture concrete evidence for arbitrary
  hypothetical expressions.
- Direct calls use the same occurrence-indexed discipline. Explicit generic,
  inferred generic, and nongeneric calls remain distinct constructors, and
  each constructor ties the declaration selected during symbolic typing to
  its grounded arguments, requirements, and exact emitted function row.
- Recursive specialization is indexed by both the grounded type and the exact
  emitted core term. A parent derivation therefore consumes the very child
  term produced by its receiver, argument, operand, element, index, condition,
  range-bound, or place derivation; it cannot pair symbolic typing with a
  second existential lowering of the same source occurrence. The same kernel
  now covers literals, locals/constants/self, arrays and slices, unary/binary
  operations with explicit coercion choice, assignments and recursive places,
  intrinsics, direct and method calls, indexing/member access, statement
  sequencing, locals, returns, branches, loops, range iteration, named struct
  fields, enum payloads, pattern allocation, and match results. Checking
  retains an inference derivation even at same-source coercion boundaries, and
  records its established projections so the mutual proof dependency is
  well-founded without weakening the exact-output invariant. Pattern witnesses
  expose their grounded pattern, concrete binding rows, and final local ID;
  match-arm witnesses consume those exact rows. The structural functionality
  proof traverses every expression child, including named fields and match-arm
  bodies under their pattern-extended contexts. Statement functionality then
  proves both the emitted Core statement and the final local-ID frontier unique
  through declarations, returns, branches, blocks, and every loop form.
- Imports form a leading block in each file. A declared file has exactly one
  matching module declaration at item zero, followed by imports and then
  declarations; a synthetic file omits the module declaration but retains the
  same import-before-declaration rule.
- Quoted import syntax is represented because it is accepted by the parser,
  but it has no static elaboration rule. This matches the current compiler's
  `LNC0011` rejection instead of inventing a filesystem-to-module mapping in
  the language semantics.
- Trait methods are contracts in the current language. Trait implementations
  must cover those contracts exactly, but only inherent implementation methods
  participate in member-call lookup; this matches the current compiler's
  deliberate rejection of trait-method dispatch.
- Constant initializers form a separate compile-time expression language:
  literal values, references to constants already admitted by dependency
  order, scalar casts, and unary/binary scalar operators. They must evaluate
  successfully without changing heap or world state before their immutable
  core value is installed. Function calls and aggregate construction are not
  admitted merely because a particular evaluation would be pure. Self and
  forward dependency cycles have no derivation. The declared constant type is
  an expected type for its initializer rather than a demand that the expression
  infer that type without context.
- Allocation and reallocation exhaustion return null and preserve the specified
  failure-state guarantees. Invoking the separately declared `alloc_failed`
  handler is explicit and terminates with `allocationFailure`; allocation does
  not invoke it implicitly.
- `print`, `assert`, and `i32_array_data_ptr` are reserved compiler intrinsics
  by the leaf name of a call path, including a qualified path. This matches the
  compiler's intrinsic lookup and gives them precedence over ordinary,
  associated, external-function, and enum-constructor calls.
  `print` accepts exactly one `i32`, writes its signed decimal representation
  followed by a newline to standard output, and returns unit. `assert` accepts
  exactly one boolean, returns unit for `true`, and traps as
  `assertionFailed` for `false`.
- `i32_array_data_ptr` accepts any `[i32; N]` expression. A place-shaped
  argument creates or reuses a stable borrowed raw-address view of the original
  place; another expression receives a stable temporary cell. Language
  assignments are reflected before raw reads or host calls, and raw or host
  writes are reflected back into the aliased array. The borrowed view does not
  consume allocator capacity and cannot be deallocated or reallocated.
- Contextually checking `[T; N]` against `[T]` produces an explicit core slice
  view. Place-shaped arrays borrow their existing stable cell; non-place array
  expressions receive stable temporary cells, so returned or otherwise
  escaping slices do not dangle in the abstract semantics.
- The integer literal `0` is the only integer literal that contextually lowers
  to `ptr`. Raw pointers support equality and byte-offset addition/subtraction
  by signed integers, unsigned integers, or characters. Arithmetic wraps at
  the target pointer width; an interior result addresses the containing raw or
  borrowed block, while deallocation and reallocation still require its base.
- Source expressions infer their uncoerced type through `ExprLowers` and are
  checked against contextual expectations through `ExprChecks`. Checking may
  either retain the inferred expression or insert one explicit core scalar
  cast; literals are checked directly for representability at the expected
  scalar type rather than first acquiring their default type. Whenever that
  direct contextual rule is applicable, including through a unary operator,
  the general scalar-cast rule is excluded: contextual literal elaboration has
  priority and one source occurrence cannot also elaborate as a default literal
  followed by a cast. A literal for which the expected type has no direct rule,
  such as `char` checked as `i32`, may still use an ordinary scalar cast.
  Checking cannot
  recursively search through chains of implicit casts. The
  same judgment owns annotated initialization, assignment, call arguments,
  returns, aggregate elements and payloads, and match-arm results.
- An omitted function return annotation is a default, not body inference. A
  function named `main` defaults to `i32`; every other function or method name
  defaults to `unit`. The return statements are then checked against that
  selected type. The name-indexed rule matches the current alpha compiler and
  is proved unique in both retained and monomorphic type domains.
- An executable selects exactly one source function named `main`. Its resolved
  entrypoint has no value parameters and returns `unit`, `bool`, a signed or
  unsigned integer, or `char`; aggregate and borrowed results are not process
  entrypoint values. These are language-level entrypoint rules. Concrete x86-64
  and Wasm register, stack, export, and exit-status conventions remain backend
  obligations.
- Whole-program execution calls the selected entrypoint with no arguments.
  Ordinary return retains its typed semantic value. Explicit process exit,
  terminal trap, and fuel exhaustion are separate observations; none is
  silently converted into an ordinary return value.
- Fuel is a totality device for the Lean evaluator, not a source-language
  resource. Once an execution returns, explicitly exits, or traps, increasing
  fuel preserves the exact observation and final runtime state. An
  `outOfFuel` result states only that the selected bound did not establish a
  terminal result.
- The language-level dynamic semantics is the fuel-independent relation saying
  that some finite evaluator bound reaches a terminal observation. It is
  deterministic. Divergence means that every finite bound exhausts fuel, so
  termination and divergence are mutually exclusive.
- In a mixed-scalar binary expression, `f64` dominates `f32`, and either float
  type dominates signed integers, unsigned integers, and `char`, regardless of
  operand order. Otherwise the left operand selects the operation domain and
  the right receives at most one explicit cast. This rejects narrowing
  float-to-integer accidents while retaining a deterministic rule for mixed
  signed/unsigned integer expressions.
- A user-defined `extern` has an opaque semantic identity. Successful results
  and explicit traps are supplied by an ordered external-response stream in
  the initial world; calls record their identity and evaluated arguments. This
  gives arbitrary externs deterministic language-level behavior, including
  aggregate returns, without defining x86-64 or Wasm calling conventions as
  part of the source language. A missing or out-of-order response traps as an
  unmodeled external call. A returned opaque value must be closed—it cannot
  contain a forged reference or slice into the Lanius stable-cell store—and it
  must have the declared return type for every function sharing that external
  identity.
- Integer-valued host results are reduced modulo 32 bits and interpreted as a
  signed `i32`. Large clock values, byte counts, and other mathematical host
  integers therefore cannot create an out-of-range runtime value.

### Traps in compiled code (decided 10-28)

The verified compiler sorts Core's traps three ways. Checked traps make the
compiled code fault (`ud2` or `#DE`): `arrayBounds`, `invalidShift`,
`divisionByZero`, `signedDivisionOverflow` and `allocationFailure`; running
out of heap or of stack faults too. An allocation whose end would pass 2^64
is an allocation failure, not a wrap (`bump` tests the carry). Undefined
traps are a premise of the compiler's theorems, as undefined behaviour is in
CompCert: `rawMemoryBounds`, `invalidPointer`, `doubleFree`,
`allocatorContract` and (decided 10-29) `typeMismatch`. A typed program
reaches `typeMismatch` only by reading an invalid bit pattern from raw
memory (a `bool` byte of 2, say) or through a raw slice of an element type
past Core's native layout limits, so it is a raw memory error too.
Impossible traps cannot happen in a program the compiler accepts:
`uninitializedLocal`, `missingReturn` and `nonExhaustiveMatch`.

The compiled code checks in Core's order. A store `slice[i] = v` evaluates
`i`, checks `i` against the length, and only then evaluates `v` (10-29:
proving `compileSource_stops` found the old order, `v` before the check,
wrong when `i` is out of bounds and `v` reaches an undefined trap).

This is a known difference from laniusc (recorded 10-31). laniusc evaluates
`v` first and then checks `i`, which is Rust's order for an assignment (the
assigned value, then the place). With `i` out of bounds the two compilers
trap at the same store, but laniusc first runs whatever `v` does: its
output, or a trap of its own. Core's order stays: the store's check is
proved to come before any effect of `v`. fuzz_oracle.py counts such a
program as known (both trap, the verified compiler's output a prefix of
laniusc's, an indexed store in the program) rather than as a disagreement.

### `x<` in an expression (decided 10-29)

The grammar gives `a < b > (c)` two trees: a chain of comparisons and a call
of the generic path `a<b>`. Lanius reads `x<` in an expression as the start
of type arguments exactly when, from the `<` on, the matching `>` (angles
counted outside brackets, a `>>` closing two) comes before any bracket
closes or a `;`, no `||`, `==`, `!=`, `<=` or `>=` comes before it, and `(`,
`::` or `{` follows it; otherwise `<` is a comparison. This is laniusc's rule
(`shaders/parser/tokens/to/angle_kinds.slang`) without its limit of 64
argument tokens; the verified compiler's validator checks it (`picks`).
A method's `<` (`x.f<T>(..)`, ambiguous in the same way: `x.f < a > (b)`)
opens type arguments by the same rule, from the `<` on (decided 10-31, F11b;
before, a file with one was rejected, which rejected `alloc::vec` and every
program importing it). The reader reads such a call as the call without
them, with the method's own type parameters bound to the written types in
order, after the binds the receiver's type gives the impl, instead of
inferring them (`MethodBinds`; a count other than the method's type
parameters rejects; decided 11-01, F11b). A field (`x.f`) with type
arguments rejects.
A statement that begins with `{` is a block statement, never an
expression statement (decided 10-30, F4), as in Rust: `{ a } - b;` is the
block `{ a }` and then `-b;`. Its lets scope over the block only
(`StmtR.block`). With these, every token sequence has at most one parse
tree (V4, `Mini/ParseUnique.lean`; `pickedPair` in `Mini/Unique.lean` lists
the three pairs of productions `picks` tells apart).

### The process (decided 10-29)

A Lanius program runs as a Linux process whose exit status is the low byte
of `main`'s last result slot (rax): `main` takes no parameters, and its
return value is the status. The verified compiler writes the executable
itself (`elf_file`): one readable, writable, executable segment at 2^32
holding the ELF headers, the startup code and the image, followed in the
segment's zero fill by the stack and then the heap, whose sizes the caller
chooses (`stack` at least `binary.guard`, `heap` at least 1, both below
2^40). There is no dynamic loader, no libc and no argv; a trap is a signal
(SIGFPE or SIGILL), so the status is never a trap code. The entry is a
function index; the driver's convention is function 0.

### The pure subset and raw views (decided 10-29)

Proving that the self program never traps undefinedly (V7b) fixed three
rules of the verified compiler's pure subset. Its checker requires the
operands of a binary operator to have one type, numbers for arithmetic and
`bool`s for conditions and `!`. A `boxed`/`unbox` primitive's element type
must have a native layout within Core's limits (`BoxedAt`), since Core's raw
view of a type past them traps `typeMismatch`. A boxed value's meaning
(`VRel.box`) includes that its storage passes `checkRange`, so reading it
back through a raw view cannot trap. The front pass's `lower_slice` rejects
a raw slice whose element type is past those limits too (F1, decided
10-29): `within_layout` checks Core's nesting depth (64), struct size (at
most 4096 words) and payload size (under 4096 words), and
`lowerSlice_layout` (`Mini/ElementLayout.lean`) proves that an element it
accepts has Core words, its mini size. A typed program now reaches
`typeMismatch` only by reading an invalid bit pattern from raw memory.

### Char literals (decided 10-30)

The front end reads a char literal only when its text is the UTF-8
encoding of one Unicode scalar value (not the quote, backslash or newline)
or one of the escapes `\n \r \t \0 \' \" \\`, between quotes
(`Reading.CharLiteral`). laniusc reads more (`'ab'` as `'a'`, `'\q'` as
`'q'`, a malformed encoding as code 0); those texts are rejected rather
than given laniusc's reading, since a program that relies on them is
almost certainly wrong. Where both read a literal they give the same code.

### Floats in the verified compiler (decided 10-30, F9)

`f32` and `f64` are source types of the verified compiler (`SrcType.float`).
A slot holds a float's bit pattern, an `f32` one zero-extended, and every
operation goes through xmm0 and xmm1 (`Instr.fp`). The lowering:

- `+ - *` of two floats of one type are `addss`/`subss`/`mulss` (`sd` for
  `f64`). Source `/` and `%` of floats are not lowered: Core's division is
  `eval_division`, and its float arm is not yet part of the subset (the IR
  and the x86 model have `divss`/`divsd`, proved, for when it is).
- `==`, `<`, `<=` are `cmpss`/`cmpsd` with predicates 0, 1, 2, the mask's
  low bit made 0 or 1 (`neg eax`). `>` and `>=` swap the operands (both
  are pure, so nothing is reordered), and `!=` compares `==`'s result to 0,
  so that a NaN operand makes `!=` true as Core's `!=` is.
- Negation flips the sign bit by adding it at the format's width and
  dropping the carry, NaNs included, as Core's `neg` (and `xorps`) do.
- Casts to a float: `i32` and the narrow signed types from their 32-bit
  value (`cvtsi2ss xmm0, ecx`); `isize`, `i64`, `char` and the narrow
  unsigned types from the 64-bit slot (an unsigned narrow value is below
  2^32, so its signed 64-bit reading is its value); `f32 -> f64` widens and
  `f64 -> f32` rounds. `u64` and `usize` to a float are rejected (x86 has no
  unsigned 64-bit conversion before AVX-512; a sequence for it is later
  work), and so are casts of a float to an integer (Core's `truncSat`; the
  saturating sequence is later work) and to its own type (Core has none).
- Float fields, locals, parameters, results and constants are lowered;
  slices and raw views of floats are rejected (no element layout yet), as
  is a match on a float.

Float literals in the front end:

- A literal is read as `m * 10^e` exactly and rounded once to the nearest
  pattern by `Lanius.IEEE.Format.ofDecimal`, the function Core's elaboration
  uses (`flDecimal_eq` proves the front end's bignum rounding equal to it).
  So `0.1`, `1e-1` and `100000000000000000e-18` are one literal.
- While the expected type is not yet known the builder carries both
  roundings in a marker no source can spell (`float_marker`); the context
  picks one (`float_want`). With no float type expected, the literal is an
  `f32`, Core's `literalDefaultType`: `(0.5 as f64)` is the `f32` 0.5
  widened. A typed constant takes its declared type, and `-` of a literal
  is its negation at that type.
- Underscores in a float literal are rejected, and so is an exponent above
  99999 (with 10^400 already past every finite pattern, this only keeps the
  front end's powers small).

### Arrays in the verified compiler (decided 10-31, F6)

`[T; N]` is a source type of the verified compiler (`SrcType.array T N`),
Core's array, held by value:

- An array takes N times T's slots, its elements one after another, as a
  struct of N fields of type T would (`HoldsAt.array`, `repeatType`). So a
  local, parameter, result or field of an array type is lowered as such a
  struct is: copies, calls and results move N * size(T) words.
- A literal `[a, b, ..]` or `[x; N]` is the struct literal node `EStruct`
  (or `LetStruct`) at the array type, and its Core meaning is the array
  value of its elements (`SrcType.literal`, a change to the trusted
  `toCore`). The front end reads it only where an array type is expected,
  with exactly N elements; `[x; N]` needs a pure x and is read as N copies
  of x, which is the value Core's `[x; N]` (x evaluated once) has. The
  length must be written as a decimal literal, in the type and in `[x; N]`.
- `a[i]` of an array local, i an `i32` or `usize`, evaluates i into its
  slot, checks `i <u N` (a negative `i32` index is past N as an unsigned
  word), and then copies element i over the slot by a chain of compares of
  i with 0 .. N-1 (`pickElement`). Core traps with `arrayBounds` where the
  check fails; the mini program stops at the check, as at every other trap.
  The chain is N copies of the element in the code, so an index of a long
  array is long code; a scaled address is later work (it needs the
  array's base address, which a frame slot has but the IR does not name).
  `let x: T = a[i];` is read as `slice[i]` is (`LetIndex`), and lowered as
  the `let` of the indexed value (`lower_let_index_any`), whose Core
  meaning is the same.
- `a[i] = v` on an array local, i an `i32` or `usize`, evaluates i into its
  slot, checks `i <u N`, then evaluates v (Core checks the bound before it
  evaluates the value, as for a slice) and copies it over element i by the
  same chain of compares (`putElement`, `storeArray`). With pure operands it
  is read as `slice[i] = v` is (`SetIndex`) and lowered as the effectful
  form (`lower_set_index_any`). The front end reads v at the element type
  (`index_elem`), so `bytes[i] = 48` is a `u8` store.
- An array local passed as a call's argument at a `[T]` parameter, its
  element type T, is read as `ArraySlice(T, a)`, Core's `arrayToSlice`
  of the local, so the callee's writes reach the array, as laniusc's do
  (decided 11-01, F11b; before, the reading passed the array by value,
  which disagreed with laniusc in `core::utf16_bytes`). An array local of
  another element type rejects. The compiler does not lower it yet
  (`SrcEff.eval` rejects it), so such a program is read but not compiled.
- Not yet: an array other than a local passed where a slice is
  expected, `for` over an array,
  `==` of arrays, `core::mem::i32_array_data_ptr`, a length that names a
  constant, and arrays of floats (no element layout for float slices yet;
  an array of floats is held by value and should work, but is untested).

### Addressed locals (decided 10-31, F6; being built)

Core names a local's storage in three places the verified compiler does not
yet have: the coercion of `[T; N]` to `[T]` (Core's `.slice T cell
projections start length`, so `format_u32(bytes, ..)` fills the caller's
buffer), `&T` and `&self` (`.reference`, F5: `fn bump(&self)` writes the
caller's value), and `i32_array_data_ptr` (a pointer to the array). The
verified compiler's locals are 64-bit slots with no address. The design:

1. **Frame memory in the IR.** The mini heap's bytes from `limit` up to a
   new `top` are frame memory, handed out downward, one block per
   activation, by a statement `Frame slot bytes` (the frame pointer `fsp`
   drops by `bytes`, `slot` gets the new `fsp`; below `limit` there is no
   run, as for an allocation past the limit). A call gives its callee's
   frame memory back: the call rule restores the caller's `fsp`. The bump
   heap below `limit` is unchanged, so Core's heap addresses are still the
   mini ones and `HeapCorr`'s zero bytes are still those from the cursor
   up to `limit`. On x86, `fsp` is rbx, an offset from the heap base like
   the cursor in r13. rbx is scratch: each call stores it into the
   caller's first result slot (the results overwrite that slot after the
   return) and loads it back after the return, so the callee may change it
   and the call rule's restore is what x86 does. r10 holds the heap's top
   (`Frame.heapTop`, `Rel.top`), so loads and stores reach frame memory
   through the same `r12 + offset` as the bump heap. The loader maps frame
   memory as large as the stack above the heap (`frame` stops at a `ud2`
   past it, as the prologue does past the stack); the startup code
   sets r10 and rbx to `heap + stack`.
   `Frame target bytes` compiles to the abstract instruction `frame bytes`
   then `store target`. `frame bytes` is `mov r11, bytes; mov rax, rbx;
   sub rax, r11; jb +12; mov r11, rax; cmp r11, r14; jae +2; ud2; mov rbx,
   rax`: a borrow or a result below the limit reaches the `ud2` (the stop
   rule `Stops.frame`, as for an allocation past the limit), and otherwise
   rbx and rax hold the new frame pointer. `bytes` is below 2^31 (`within`).
   The simulation keeps `fsp ≤ top` (`Rel.fspLe`, `HeapAt.fspLe`), so the
   frame pointer is below 2^62 and rbx's subtraction is exact.
2. **One slice layout (decided 10-31).** Every slice, safe or raw, has one
   element layout, laniusc's native one (`stdlib/core/mem.lani`): an `i32`
   packed at stride +4 from the pointer, a `u8` packed at stride +1, every
   other scalar as one 8-byte word and a struct or enum as its native words,
   both running down from the pointer (stride -8 times the element's native
   words). The verified compiler never reads `[T]` two ways: a function
   with a `[T]` parameter runs one body whether its argument is a raw slice
   or a safe one. An array local passed as a slice is therefore stored in
   that layout wherever it lives, in a heap view (point 5) or in a frame
   block by F5's call sequence, and its slice is the same (pointer, length)
   pair as a raw slice of those bytes. So `FrameCorr`'s places carry a
   layout: word per slot for a reference to a scalar or a struct (F5), the
   slice layout for an array passed as a slice. Element reads and writes of
   an addressed local itself are loads and stores at its address in its
   layout.
   Core's `slice_stride` follows (decided 11-01, step 3.4): a safe slice
   `.slice T cell projections start length` answers its element's native
   stride (`rawSliceStride?`, `NativeLayout.elementStride?`), as a raw slice
   of `T` does: 4 for `i32`, 1 for `u8`, -8 times the native words for a
   struct, an enum or `u16`, and no stride (a `typeMismatch` trap) for the
   element types a raw slice cannot hold. Before, a safe slice had no
   stride, which disagreed with laniusc, whose one layout gives every slice
   the same stride, and with the typing rule `ExprHasType.sliceStride`,
   which accepts any slice.
   The verified compiler passes only arrays of `i32` and `u8` as slices for
   now (decided 11-01, step 3.4; `SrcType.HoldsAt.borrowed`): their
   elements are packed, one 4-byte or 1-byte load or store each, so the
   frame block holds exactly the bytes the slice's loads read. A struct or
   enum element's scalar fields take their own widths inside 8-byte words
   (a 4-byte `i32` field, the 4-byte tag), so the block's remaining bytes
   would need a byte-level account of Core's native layout; such arrays are
   rejected at a `[T]` argument until it is written.
   **Lent u8 arrays (found 11-02, open).** laniusc does not pack a `[u8; N]`:
   it lays the array out one 8-byte word per element and lends it in that
   layout, at stride -8 (`stdlib/core/mem.lani`: a native array passed as a
   slice keeps its own layout; `std::io_byte::write_byte_view` branches on
   it), while a raw `[u8]` view has stride 1. Core (`rawSliceStride?`) and
   the verified compiler give the lent array stride 1. Element reads and
   writes agree (the oracle's array calls, 2,400 calls alike); `slice_stride`
   of such a slice, and code that branches on it, differ. An `[i32; N]` is
   lent at stride 4 by both. Closing it needs Core to give a lent `[u8; N]`
   laniusc's stride -8 and the verified compiler's `[u8]` slices to carry
   their stride (laniusc's three-word slice), since one `[u8]` body sees
   both layouts; until then the oracle generates no `slice_stride` of a
   `[u8]`.
3. **The correspondence.** The simulation relation carries the addressed
   cells (cell, type, address); for each, frame memory at the address holds
   the cell's value in that layout (`FrameCorr`, beside `HeapCorr`). A safe
   slice `.slice T cell [] start length` is held by (the cell's address plus
   `start` strides, `length`). A write through the slice changes the cell
   in Core and the bytes in the mini heap, so both sides stay equal.
4. **No escapes.** Core keeps every cell; frame memory is reused after the
   activation returns. The verified compiler therefore coerces a local only
   where the slice cannot outlive the activation: a direct call argument
   whose parameter is `[T]`, to a function whose result type contains no
   slice. Other coercions are rejected. The verified compiler is stricter
   for now (step 3.5b, `array_call_code`): the call is a statement's value
   (`LetEval` or `Discard`, `stmt_eval`), its result is a scalar, and no
   array is passed twice (`id_absent`), so the arrays lent are apart and
   none is read while lent. After the return the caller loads each array's
   elements back from the block into its slots, so the callee's writes
   through the slice reach the caller's copy (`arrayCall_sound`).
5. **`i32_array_data_ptr` uses the heap, not frame memory.** Core maps the
   array into a fresh heap block at `nextAddress` (`mapI32ArrayView`) and
   keeps block and cell equal from then on (`syncI32Views*`), and the
   pointer's value is observable (host calls take it). The verified
   compiler does the same: it bump-allocates the block, copies the
   elements, and from then on the array local is addressed at that heap
   address. The proofs' invariant "Core has no views" (`Grows`) becomes
   "every view's block holds its cell".
   The plan (decided 11-02, f6v):
   - *When.* Core maps a view at the first `i32_array_data_ptr` the run
     evaluates, so the verified compiler's block must be allocated there and
     not earlier (Core's later allocations would get other addresses). The
     verified compiler reads only the statement `let p: ptr =
     core::mem::i32_array_data_ptr(a);` (Source `LetView p a body`, Core's
     `letLocal p (i32ArrayDataPtr (local a)) body`), a an `[i32; n]` local
     declared in the same block: `lower_func` rejects a body with a
     `LetView` inside an `if`, `while` or match arm whose array is declared
     outside it (`loose_views`, as `breaks_out` for a loose `break`), so the
     local is viewed for the whole rest of its scope and never seen in
     slots again. That is the
     stdlib's pattern (most of its 125 calls; the rest pass the pointer
     inside an expression, later work). A second `LetView` of a viewed
     array gives its address again, as Core's `mapI32ArrayView` finds the
     view it made.
   - *Code.* `LetView` bump-allocates `4 n` bytes at alignment 4 (Core's
     `mapBorrowed`, which takes no budget: the heap is unbounded in
     `HeapCorr`), stores the n elements packed (an `i32` at +4k), and the
     body is lowered with a's binding replaced by one of the new source
     type `SrcType.View n` (one slot: the block's address). Reads `a[i]`,
     `let x = a[i]`, writes `a[i] = v` and the length of a `View` are
     loads and stores at the address, after the bound check `i <u n`, as a
     raw `[i32]`'s; every other use of a `View` (a copy, a call argument,
     an array call) is rejected for now.
   - *Proofs.* `HoldsAt.view`: a `View n` slot holds the block's address
     and Core's cell an array of n `i32`s; `Corr.viewed`: the state's view
     list has the view (address, the binding's cell, [], n). `State.Fresh`
     replaces "no views" by `ViewsHold` (each view's root cell is an array
     of `i32`s in range whose encoding is its live, borrowed block's bytes;
     roots and blocks apart), under which Core's `syncI32ViewsToHeap` and
     `syncI32ViewsFromHeap` are the identity. `Grows` becomes: the view
     list only grows at its end, `ViewsHold` is kept, and the cursor does
     not go down. `Keeps` exempts view roots (a callee's raw store into a
     caller's viewed array changes the caller's cell through
     `syncI32ViewsFromHeap`); a viewed binding's `Corr` comes back from
     `ViewsHold` instead. Stages: (a) Core lemmas (`ViewsHold`, the syncs'
     identity, its preservation by binds, allocation, cell writes followed
     by a sync, raw stores, host calls); (b) `Fresh`, `Grows`, `Keeps`
     generalized through the proofs; (c) `View`, `LetView` and the viewed
     reads and writes in the compiler, with their proofs; (d) the front
     end's reading; (e) the oracles.
   - *Done so far.* (a) 6fa6c5b1b. (b): `State.Fresh` is "cells below
     `nextCell` and `ViewsHold`" (a trusted change, TRUSTED_BASE). `Grows`
     keeps the view list equal for now (`Grows.views`), since no lowered
     statement maps a view yet; `Grows.empty` gives the Faithful proofs
     their "no views" from it. Stage (c) relaxes it to "grows at its end"
     when `LetView` is lowered. Raw stores, `storeByte` and host calls
     reach the sync after them through `ViewsHold.afterStores` and
     `ViewsHold.syncAfter`, which keep every view and every cell no view
     roots at. A raw write into a value that holds a slice is a defined
     trap only where no view roots at it (`Unhit`, `UndefTraps.lean`),
     which a slot holding (`HoldsAt.unhit`) gives from `FrameCorr.unviewed`
     (no view roots at a frame place) and `Corr.unviewed` (nor at a scope
     binding's cell).
     (c), decided while doing it (11-02, f6v): the source statement is one
     combined `LetView(id, n, elements, p, body)` = `let id: [i32; n] =
     [elements]; let p: ptr = core::mem::i32_array_data_ptr(id); body`
     (Core: two `letLocal`s), so the view's array is always declared right
     there and no `loose_views` check is needed: the binding is a `View n`
     for the whole of its scope. `lower_view` lowers the literal into n
     slots, allocates `4 n` bytes at alignment 4 (shift 2, Core's
     `mapBorrowed` base), stores the elements (`StoreWord m32` at +4k), then
     assigns the pointer into the `View`'s first slot (`slot := pointer`),
     binding `p` as a `Ptr` in slot `next + n`. It rejects `n = 0` and
     `n >= 2^31` (the block's size is then a 32-bit word, and Core's
     `mapBorrowed` gives an n-element block). No value of the language has
     type `View` (`viewed_type`): `same(View, View)` is false, and
     parameters, match arms' bindings and match payloads of a viewed type
     are rejected, so for now the body may only use `p`; reads and writes
     of a `View` binding are later work. `HoldsAt.view` (trusted) asks
     that Core's cell hold n in-range i32s; `Corr.viewed`: a `View n`
     binding's cell is the root of a view whose address is its slot and
     whose length is n; `Corr.unviewed` only for non-viewed bindings;
     `Keeps` gains `persist` (old views stay) and `arrays` (a view root's
     cell still holds an i32 array of the view's length, `HeldArray`).
     `Grows` is now "the cursor does not go down and the views only grow
     at their end". The Faithful proofs no longer take "no views" from
     `Grows` (`Grows.empty` is gone): they use only its cursor (`.next`),
     and get "no views" after a value's run from the simulation's own
     invariant (`Ran.inv`, `Inv.views`), since the self program, whose
     statements pass `stmtOk`, has no `LetView`; its pure and cost meanings
     are `none`, as `letAlloc`'s. Proved: `stmt_letView` in
     `LowerEval.sound_both` and `stops_letView` (`Mini/ViewLower.lean`,
     `LowerStops.lean`), the Faithful growth of a trapped `LetView`
     (`view_trap_grows`). LaniusMini and every gate target build.
     (d), decided while doing it (11-02, f6v): the front end reads the two
     lets as one statement only when the pointer's let comes directly
     after the array's (`let a: [i32; n] = [..]; let p: ptr =
     core::mem::i32_array_data_ptr(a);`, the stdlib's spelling, on one line
     or two). `core::mem::i32_array_data_ptr` is a reserved path (a seventh
     entry of `builtinPaths`), so it is never read as a call of a function;
     its let head is `viewOf x`, which no single let reads, so a pointer
     let anywhere else (after another statement, typed other than `ptr`,
     of a local that is not the array just declared) leaves the function
     unread. The array's literal must have `n` elements (`[v; n]` counts),
     and `p` must be fresh and not a global. Uniqueness: a list whose first
     statement is such a pointer let has no reading
     (`stmtsR_noViewHead`), so the array's let read as a plain `let`
     cannot overlap the combined reading. The builder reads the pair in
     `let_first`, inline, since its mutual recursion only calls itself at
     fuel minus one. Frontend cases `view_array`, `view_repeat` (read and
     compiled), `reject_view_gap`, `reject_view_type`.
     (e) the stdlib oracle (11-02, f6v; the 14 `std::io*` and
     `std::random_checked`/`random_wide` modules, `--calls 16 --seed 1`):
     before, 120 testable, 71 compiled, 39 unread (every one an
     `i32_array_data_ptr` let), 10 uncompiled, 446 calls agree; after, 120
     testable, 76 compiled, 3 unread (`i32_slice_data_ptr`, a different
     view), 41 uncompiled (each calls an extern host function, `read_stdin`,
     `write_byte`, ..., which the verified compiler does not compile), 593
     calls agree, 0 disagreements. The 5 newly compiled targets use only
     the pointer (`write_code_view` and its callers). Left: reads and
     writes of a `View` binding (`slot[0]` after `read_stdin`), which no
     testable target reaches until extern calls compile.
6. **`str`** is (pointer, length) of read-only bytes in a static region
   above frame memory, a literal's bytes placed by the loader (Core's
   `.string` value names no address, so any region outside Core's heap
   will do).
   The plan (decided 11-02, f6v). What the stdlib needs: nearly every
   `str` is a local bound to a literal whose bytes are taken by
   `core::mem::string_data_ptr(text)` and read through
   `typed_slice_from_raw_parts` (the `core::unicode_*_data` tables, file
   names); Core's `string_data_ptr` maps a fresh borrowed heap block at
   `nextAddress` holding the bytes zero-padded to whole words
   (`mapStringDataPtr`, `stringStorage`), so the verified compiler must
   allocate and fill that block there, as for `i32_array_data_ptr`.
   - *Where the bytes are.* The literals' bytes follow the code in the
     binary's image, so the one loadable segment the loader maps (Linux's
     `Loaded`) places them; no new segment and no copy at startup. The mini
     heap gets a read-only static region, `staticBase` and its bytes
     `statics`: loads may read `[staticBase, staticBase + length)`, stores
     only below `top`, so the static bytes never change. Its mini address is
     the image's x86 address less the heap's base (wrapping, so above frame
     memory in the mini address space, `top ≤ staticBase`). A new mini
     statement `Static target offset` gives `staticBase + offset`; on x86 it
     is `lea rax, [r8 + offset]` then `sub rax, r12`. r8 (unused before,
     kept across calls) holds the static bytes' x86 address, which the
     startup code sets (`mov r8, imm64`, the image's base plus the code's
     length). This replaces the first plan's `lea rax, [rip + d]`: rip
     relative code would tie each function's bytes to its place in the
     image (the linker would patch every `d`, and `Contract` would need the
     image's base), while r8 keeps the code position independent and the
     calling convention's new facts about one register. The calling
     convention (`HeapAt`, trusted) gains the static region: r8 is the
     heap's base plus `staticBase`, the bytes there are the heap's
     `statics`, and the region is outside the heap and the stack window.
     Rejected alternatives: a second loadable segment above
     frame memory (changes the trusted loader), a startup copy loop
     (an x86 loop proof at startup), moving the stack so the static bytes
     sit at a constant below the heap (reworks the whole process layout).
     Separate compilation: a module's static references are holes the
     linker fills like call targets; until then a module with literals is
     not compiled alone.
   - *Values.* `SrcType.str` takes two slots, the pointer into the static
     region and the byte length (below `2^31`). As for `View`, the slots'
     truth is a heap fact kept per binding (`Corr.str`: the static bytes
     at the pointer are the literal's UTF-8 bytes) rather than in
     `HoldsAt`, which has no heap; so for now a `str` is only a local bound
     to a literal (no `str` parameters, results, fields or payloads, no
     assignment, no `==`), which is the stdlib's pattern.
   - *`string_data_ptr`.* Allocate `stringStorage`'s size at alignment 4
     (Core's `mapBorrowed`), copy the bytes from the static region (a
     loop of byte loads and stores; the padding is the fresh block's
     zeros), giving the block's address.
   - *Stages.* (a) the mini machine's static region and `Static`, to x86,
     the linker and the process, the top theorems kept; (b) `str`, its
     literal let and `string_data_ptr` in the verified compiler, proved;
     (c) the front end's reading; (d) the oracles.
   - *Stage (a), done (11-02, f6v).* `Program.statics` and
     `Binary.statics` carry the bytes; `link` puts them after the code
     (`linkOnto`'s tail), and the startup code is 95 bytes (the image
     starts at `elfBase + 215`). `Exec.static` and `Exec.loadByteStatic`
     (a byte load at `staticBase + k`, `k` below the length, the region at
     or above `top`, so it never overlaps a heap load); the machine's
     `Step.loadAtStatic`, and `Step.call` asks that the callee keep the
     region (`Exec.statics`: no mini statement changes it). On x86
     `Rel.static`/`Rel.statics` (r8, and each static byte as the entry
     memory has it, outside the window and the heap, so no store reaches
     it) carry the region through every step; `call_simulates` hands it to
     the callee in `HeapAt`. The process's heap (`elfHeap`) has the
     binary's `statics` at `elfStaticBase`, the static bytes' address
     less the heap's base, wrapped (`compileSource_layout`: the verified
     compiler's image is the code, then the statics). The front-pass
     lowering still emits no statics, so the compiled programs are
     unchanged but for the startup's `mov r8`.
   - *Stage (b), decided and done (11-02, f6v): one statement, not a `str`
     value.* What the stdlib does with a literal is always `let text: str =
     "..."; ... core::mem::string_data_ptr(text) ...` (or
     `string_data_ptr("...")` directly), so the front-pass program gets
     `LetStr(pointer, chars, body)`, meaning Core's `let pointer: rawPtr =
     core::mem::string_data_ptr("chars"); body`, and no `SrcType.str`. This
     departs from the plan above in three ways. (1) No two-slot `str` value
     and no `Corr.str`: the reading (stage (c)) reads the `str` let and its
     `string_data_ptr` use as one `LetStr`, the literal put where the local
     was, which is Core's meaning when the local has no other use (its cell
     is never read again); a `str` local used any other way, and `str`
     parameters, are not read yet. (2) The block is filled by stores of
     constant words, not copied from the static region: Core's block is the
     string's UTF-8 bytes zero-padded to whole words (`stringStorage`), so
     the lowering packs them four to a word (`str_words`) and stores each
     (`StoreWord(M32, pointer + 4k, word)`), with no loop to prove and no
     static-region fact to carry through the lowering's correspondence
     (stage (a)'s region stays for `str` values: parameters, results). The
     code is about one store per four bytes of the literal; the copy loop
     would have been smaller code but slower and a loop invariant in the
     proof. (3) Only nonempty ASCII literals below `2^31` bytes are lowered
     (`lower_str` rejects others), since their UTF-8 bytes are their
     scalar values (`utf8Bytes_strValue`); a UTF-8 encoder proved against
     `String.toUTF8` lifts this. The values are `usize` scalar values, as
     the front end reads char literals. The proof (`Mini/StrLower.lean`):
     Core's `mapStringDataPtr` maps `stringStorage` at the cursor rounded to
     4 (`strPtr_run`), which the words' bytes equal (`strWords_storage`);
     the mini code allocates the same block and writes the same bytes
     (`str_entered`), so the heap correspondence holds after it
     (`HeapCorr.mapView`), and the body runs with the pointer bound
     (`stmt_letStr`, `stops_letStr`).
7. **A static need per function (decided 11-01, step 3.5).** A function
   takes its whole block at entry (`frame_block`: 8 bytes per element of
   each array, parameter or let, it passes as a slice), by a prologue
   `Frame(count, block)` before its body, and its array calls place their
   arrays in that block. Its need (`func_needs`) is its block plus the
   largest need of a function it calls, computed by rounds from all zeros
   until they repeat (at most one round per function). The call sequence's
   check is static: a call is lowered only when the callee's need fits the
   caller's room (`sig.need <= sig.room`, `Sig` carries the need, the room
   and the block of the function being lowered), so no frame-memory check
   runs per call and the proofs carry the budget in `FrameCorr` (its room
   field: `limit + room ≤ fsp` when the budget is positive). A call that
   passes arrays round a recursive cycle has no fixpoint, so its need
   never fits and the call is rejected; ROADMAP F15 lifts this with per-call
   blocks released on return and a dynamic premise. The top theorems take
   the need of the function they run as a premise on the heap
   (`0 < need → limit + need ≤ fsp ∧ fsp ≤ top ∧ top < 2 ^ 62`; for a
   process, `need ≤ stack`), which holds for any heap when the need is 0,
   as it is for every function of the self program (`SelfPure.prog_need`),
   since it passes no array as a slice. `FrameCorr` carries the two other
   parts as its `ceiling` (the block is below the top, so the stores reach
   it) and `bounded` (the blocks taken are below `2 ^ 62`, the `small` of a
   place lent) fields. An array call needs a positive block of its caller
   (`sig.block > 0`), which with the room puts the frame pointer above the
   limit, so `Frame(t, 0)`, which reads the block's address into slot `t`,
   runs.

Order: frame memory in the IR and on x86; addressed array locals passed as
slices; `i32_array_data_ptr`; `str`.

## Decisions still required

- Which NaN payload details are observable through future bit-conversion APIs.
  Literal parsing/rounding is already explicit, and resolved numeric casts are
  explicit in core and width-correct dynamically. (Since 2026-10-30 Core
  fixes NaN payloads as x86 SSE does, `Lanius/IEEE.lean`; a target with other
  NaN rules, Wasm's nondeterministic NaNs, would need this revisited.)
- Calling-convention classification for aggregate parameters and results on
  x86-64 and Wasm. In-memory value layouts are fixed; register/stack passing is
  not yet part of the language model.
- Whether exhaustiveness and unreachable-pattern analysis are mandatory static
  diagnostics. Dynamic first-match behavior and non-exhaustive trapping are
  already defined.
- Whether a future language version adds unwinding. The current model makes
  panic and reached-unreachable terminal traps.
- Concrete x86-64 and Wasm data-layout and calling-convention rules.

## Verification boundary

The current work defines a language model. It does not prove that `laniusc`,
its GPU shaders, either backend, or a future CPU compiler implements the model.
The language permits references to escape lexical scope because semantic cells
retain stable identities. A native implementation must promote or otherwise
preserve those cells rather than expose dangling stack addresses.
The intended next verification boundary is a compiler written in Lanius whose
passes can be related to this core language. Translation validation can later
compare artifacts emitted by the CPU and GPU compilers without treating the
current GPU implementation as the definition of the language.

## The reading is one reading (decided 10-29, F1)

Earlier the relation stated only the positive part of the builder's
searches, so a text could have several readings. F1 changes the builder
where it recovered from a failed search, so that every choice it makes is
one the relation can state exactly:

- Constants' values (`Reading.ConstValue`): a value is wide only when it
  reads as a wide marker (`wide_read_of`), else literal.
- Method calls (`Reading.MethodFor`): `impl_fit` and the type matches it
  uses are three-valued (fits, misfit, spent); a misfit is proved by
  induction on fuel, and a spent search fails the reading. The relation
  states the method's impl matches and no other impl of that name does.
- Expected types (`Reading.EffR`): a hint the builder needs is never
  dropped. Where a search for a parameter's, field's or payload's type at
  known arguments fails, the reading fails (`checked_eff`, `has_tys`); the
  relation states the hint exactly (`KnownTys`, `ArgHint`, `FieldTyAt`,
  `ParamExpects`). Only a match's arm types keep `MaybeTy`, since only the
  first arm's type is used.
- Locals: each binding's id is fresh in its scope (`fresh_id`, the
  relation's `FreshId`), so a local found by name is the local found by id.
  A unit variant is not read where a local or constant of that name exists.
- One path for values: a statement's value is read once, as an effectful
  expression, and the statement constructors put a value that reads as
  pure, a call with pure arguments, a literal or variant of the let's type
  with pure fields, a slice element at a pure index or a match of a local
  with pure arms in that statement's form (`returnEff`, `ifEff`, `setEff`,
  `evalHead`, ...). The separate pure readers of returns, conditions,
  assignments and let heads are gone. Only an allocation and a raw slice
  are decided by their spelling.
- Reserved paths: `alloc::allocator::alloc`, `alloc::allocator::dealloc`,
  `slice_from_raw_parts`, `slice_stride`, `slice_len` and `assert`
  (`builtinPaths`) are never read as a function or variant.
- The pure and effectful expression readings agree: a node read as the
  pure expression `e` reads effectfully only as `XPure e` (`pure_agree`,
  `Reading/Det/Agree`).
- The relation's rules exclude each other where the builder tests in order:
  an assignment is a call statement only when its tail is empty, as the
  builder tries a compound assignment first; `InstBound.relit` only when no
  argument binds the type parameters.

With these, `reading_unique` (`Reading/Det/Program`) proves that a list of
parse trees has at most one reading. It needs each enum's variant names to
be distinct, which `WellNamed` states per module, and every type to be
declared in one of the files' modules (`collected_home`).

## The reading of a closed program, and which reading the theorems mean (decided 10-29)

The closing pass and the literal pass (`Reading.EffClosed`, `StmtClosed`,
`LitExpr`, `LitEff`, `LitStmt`, V8e) are total rules over the monomorphized
program: a type lowers as `LowerR` says (the builder's table of lowerings
is proved to hold them, `LoweredOk`), a call names its instance's first
position, and each literal takes the type its position expects. The
expected-type helpers (`intAt`, `wideAt`, `negWideAt`, `operandWant`,
`knownExpr`, `knownEff`, `tyLocal`, `srcFields`, `boundTys`,
`calleeParams`) and the check that no wide literal is left untyped
(`wideLeftFuncs`) are small total functions with no fuel or search, so the
relation uses them as vocabulary rather than restating them.

The relation is deterministic (`reading_unique`, F1): `compileText_correct`
and the process theorems say that the program is the texts' one reading
(`TextReading`, on `Reading.Reading`, unique by `textReading_unique`). That
`build` finds a reading whenever there is one is a later step.

## `break` and `continue` (decided 10-30, F4)

Core's `breakLoop` and `continueLoop` leave or restart the nearest
`whileLoop`, and the Mini IR's `Brk` and `Cont` do the same for `Loop`.
`Brk` compiles to `Imm 0; Jmp brk`, where `brk` is the loop's `Jz`, so the
loop's own exit runs; `Cont` compiles to `Jmp cont`, the loop's start
(`compileStmt_correct` takes both targets).

- A function body with a `break` or `continue` outside any loop is
  rejected by `lower_func` (`breaks_out`). The front end reads it; the
  `reject_loose_break` case (marker `compile_rejects`) checks that
  `compileSource` rejects it. Lowered code thus never runs a loose
  `Brk` (`breaksOut_noEscape`).
- `continue` must re-test the condition. A while loop whose condition needs
  a check (a division, a call) lowers as `Loop(1, check; if c { body }
  else { Brk })`, so the check runs on every iteration, including after a
  `continue`; a condition that needs none lowers as `Loop(c, body)`. A
  `while` whose condition has effects lowers the same way:
  `Loop(1, c.stmt; if c { body } else { Brk })`.

## Externs and the runtime (decided 10-30, F8)

- **The runtime is the kernel, called directly.** The verified compiler
  links no C runtime and no `lanius_std` library: a host service is lowered
  to inline `syscall` code. The mini IR's `Stmt.sys kind target args`
  (`Instr.sys kind slot`, `Mini/Semantics.lean`) is one system call; its
  arguments are evaluated into three consecutive frame slots, and the
  result lands in `target`. `Syscall.write`, `Syscall.read`, `Syscall.poll`,
  `Syscall.clock` and `Syscall.random` exist.
- **`Syscall.write` at the mini level.** `[fd, address, count]` with fd 1 or
  2, count at most `maxTransfer`, and `address + count` within the heap
  limit; it appends `.write fd (heap bytes address..address+count)` to
  `Heap.io` and returns count. Anything else has no mini step, so a run
  that reaches it does not return. The address is a heap offset;
  the code adds r12 (`sysSpec`, `Mini/Bytes.lean`: `mov rdi,[slot]; mov
  rsi,[slot+1]; add rsi,r12; mov rdx,[slot+2]; mov eax,1; syscall; mov
  r11,rcx`, 34 bytes). The last move only makes r11 deterministic, so a
  `Det` run exists (r11 is scratch anyway).
- **rdx, rsi and rdi are scratch** (`Scratch`, `Mini/Simulation.lean`),
  like rax, rcx and r11. Callers that keep them across a compiled call must
  save them.
- **The trace.** The x86 state has `io : Io`, a list of events; the mini
  heap has the same field. The simulation relation (`Rel`, `HeapAt`,
  `Returned`, `Frame.Exit`) says they are equal, and `process_exits` says
  the process trace at the exit is the compiled program's trace. Core's
  side is `World.State.standardOutput`/`standardError`; the link from
  Core's `write_byte`/`write_stdout` services to `.write` events (one event
  per call, the bytes Core appends) is the next part of F8.
- **Not yet modeled (deferred).** Process
  arguments and environment variables (the loader would have to place
  `argv`/`envp`, now arbitrary memory), files, sockets and processes, the
  general `syscall6`, the allocator externs (the verified compiler's `alloc` is the mini bump allocator over
  a heap the startup code provides, not `mmap`), and writes longer than
  `MAX_RW_COUNT` (Core would have to loop; a short write is not modeled).

## Host reads (decided 10-31, F8)

- **Standard input is a stream given before the run.** The x86 state's
  `Io` and the mini heap's carry `input`, the bytes not yet read; Core's is
  `World.State.standardInput`. `HeapCorr` says Core's is the mini heap's
  (`input`), and the top theorems start Core from `startState input` (an
  empty heap, the world holding only `input`): `compileSource_correct` from
  the mini heap's input, `process_exits` and `textProcess_exits` from any
  `input`, for every loaded state whose input it is (`Loaded` leaves the
  stream as it is, the trace empty). Reads are not events in the trace:
  the input a run consumed is what it was given minus what is left, so the
  trace stays the list of writes.
- **`Syscall.read` at the mini level.** `[0, address, count]` with count at
  most `maxTransfer` delivers the bytes the kernel's read does
  (`Io.readBytes count`: from 1 to count or all that are left, at most the
  next of `readLimits` plus one, 0 only when count is 0 or the input is
  used up) at `address` (`writeAll`) and drops them (`Io.afterRead`),
  returning how many came; the delivered range must lie in the heap
  (nothing is checked when no byte comes). The x86 code is
  `sysSpec` with `mov eax, 0` (`Syscall.linux`), the kernel's `read`
  (TRUSTED_BASE.md section 8).
- **`read_stdin(ptr, len)` (host id 2^32 + 3).** Core's meaning
  (`World.call .readStdin`): store `standardInput.take len` from `ptr`
  (trapping where Core's store traps), drop that many, return the count as
  `i32` (wrapped, as Core's `i32Result` is). The front end reads the
  stdlib's `extern "lanius_std" fn read_stdin` as the host call
  (`hostExtern`, case `host_read`). The verified compiler lowers it to a
  loop (`host_read_code`): a chunk of at most `maxTransfer` bytes, read;
  pointer, count and total moved past what came; and the loop ends when
  none are left to ask for or a read delivers none, since the input is then
  used up. A short read, as a pipe or terminal gives, does not end it
  (until 10-31 it did, and a short read lost the rest: review finding 3).
  Proved for every schedule of read lengths against
  Core (`hostRead_exec`, `LowerEval.host_read`): the stored bytes are
  Core's, the input left is Core's, and the result is Core's count.
- **The oracle gives each reading call its own input.** The stdlib oracle
  gives every call of a program whose stdlib files call `read_stdin` fixed
  random bytes (by seed, program and call) as a regular file on fd 0, to
  the verified compiler's image and to laniusc's harness (one call per
  run); other calls read `/dev/null`.

## Host sleep (decided 10-31, F8)

- **`sleep_ms_i32(ms)` (host id 2^32 + 4) is `poll(NULL, 0, ms)`.** Core's
  meaning (`World.call .sleepMsI32`): -1 for a negative count; else 0, with
  the whole-second compatibility clock advanced by `ms` (`afterSleepMs`; the
  monotonic and system clocks are streams of readings, which a sleep does
  not change). laniusc's runtime
  calls `nanosleep` with a timespec on the stack; the verified compiler
  calls `poll` with no fds instead (rax 7), which waits the same
  milliseconds and needs no memory, so neither the frame nor the heap
  changes. The front end reads the stdlib's `extern "lanius_std" fn
  sleep_ms_i32` as the host call (case `host_sleep`), and the verified
  compiler lowers it to `host_sleep_code`: a signed test of the count, -1 if
  it is negative, else `Sys Poll [0, 0, ms]` and 0.
- **`Syscall.poll` at the mini level.** `[0, 0, timeout]` with a timeout
  below 2^31 returns 0 and changes nothing; anything else has no step. The
  x86 code is `sysSpec` with `mov rsi, rsi` where the address calls have
  `add rsi, r12` (`Syscall.rsiBytes`, same length, so every `Sys` is still
  34 bytes) and `mov eax, 7`; the kernel's `poll` is in TRUSTED_BASE.md
  section 8.
- **The sleep is not observed.** `HeapCorr` does not mention the
  compatibility clock (`HeapCorr.sleep`), so the proof
  (`LowerEval.host_sleep`) is about the result and the rest of the world
  only; the clocks a program can read are streams of readings ("Clock
  readings and secure bytes").
- **The oracle sleeps briefly.** A stdlib function's `milliseconds: i32`
  parameter gets small or negative counts (`SLEEP_MS`), so that calls end
  well inside the two-second timeout; gate step `stdlib-time` compares
  `std::time_checked::sleep_nonnegative_ms` with laniusc.

## Clock readings and secure bytes (decided 10-31, F8)

- **Streams fixed before the run, like standard input.** Core's world holds
  `monotonicReadings` and `systemReadings`, the (seconds, nanoseconds)
  readings the monotonic and the system clock give, one a read, and
  `secureByteStream`, the secure random bytes; the process side (`Io`,
  which the x86 state and the mini heap hold) has the same streams
  (`monotonic`, `realtime`, `entropy`), and `HeapCorr` says they are equal
  (`Streams`). The top theorems start Core from `startState io`, the
  streams of the mini heap's or the loaded process's `io`, so they hold for
  every reading and random byte the kernel could give. A sleep does not
  move the readings: a real clock moves on its own, and a stream says what
  it was each time it was read.
- **`monotonic_read(ptr, len)` and `system_read(ptr, len)`.** -1 when `len`
  is below 16; else the next reading of that clock as a 16-byte timespec
  (`timespecBytes`, two little-endian 64-bit words) stored from `ptr`
  (trapping where Core's store traps), the reading dropped, and 0. No
  readings left traps as `clockExhausted`.
- **`fill_secure_bytes(ptr, len)`** stores the next `len` secure bytes, drops
  them, and returns `len`; fewer than `len` left traps as
  `entropyExhausted` (Core's existing meaning).
- **Reading past a stream's end is not specified.** The kernel's clocks and
  random source do not run out, so a Core run that exhausts a stream is a
  run the given streams do not describe: `clockExhausted` and
  `entropyExhausted` are undefined traps (`undefinedTrap`), on which the
  stop theorems promise nothing, as for raw memory errors.
- **Host ids.** `monotonic_read`, `system_read` and `fill_secure_bytes` are
  host functions 2^32 + 5, + 6 and + 7 (`hostFuncs`); the front end reads
  their `extern "lanius_std"` declarations as those host calls (case
  `host_clock`, which `compileSource` compiles).
- **Lowering.** A clock read is `host_clock_code`: -1 when `len` is below
  16, else `clock_gettime(clock, ptr)` (clock 1 for the monotonic clock, 0
  for the system clock; `Syscall.clock`, rax 228, `add rsi, r12`) and 0.
  `fill_secure_bytes` is `host_random_code`: `getrandom(ptr, chunk, 0)` of
  chunks of at most 256 bytes until none are left to ask for, then `len`
  as `i32` (`Syscall.random`, rax 318, `add rdi, r12`: the first argument
  is the address). At the mini level `Syscall.clock` with clock 0 or 1, a
  reading left and 16 bytes inside the heap stores the reading
  (`timespecLE`, the same bytes as Core's `timespecBytes`) and drops it;
  `Syscall.random` with flags 0, a count of at most 256 and no more than
  the secure bytes left, inside the heap, stores and drops them. Proved
  against `World.call` (`LowerEval.host_monotonicRead`, `host_systemRead`,
  `host_fillSecureBytes`) and through the simulation (`clock_simulates`,
  `random_simulates`); the kernel calls are in TRUSTED_BASE.md section 8.
  The stdlib's callers pass a pointer the oracle cannot give, so there is
  no oracle step for them.

## `for` over a range (decided 10-30, F4)

`for x in a..n { body }`, with `a` an integer literal and `n` a local, is
read as `let c = a; let e = n; while (c < e) { let x = c; c = c + 1; body }`
(`for_of`, `StmtR.forRange`), so that:

- `n` is read once, before the loop, as Rust evaluates a range once;
  assigning `n` in the body does not change the iterations;
- `x` is a fresh local each iteration, and `c` moves on before the body, so a
  `continue` goes to the next value; `c + 1` cannot overflow, as `c < e`;
  a body that writes `x` is not read (10-31: laniusc's `x` is the counter,
  see "Front end review fixes");
- `x`, `c` and `e` have `n`'s type, and the literal `a` takes it.

This agrees with Core's own `forRange` (`Semantics.lean`), which evaluates
the bound once, on `i32`, the one type Core's loop takes.

`c` and `e` are hidden locals: they have no name in scope, and they are
numbered by the `for` token and `x`'s token, and `x` by the `in` token, so the
locals are numbered in the order the desugared text declares them and the
front end's cases can write the desugaring as the expected reading.

## `for` over an array (decided 11-01, F11b)

`for x in a { body }`, with `a` a local of type `[T; n]` (grammar
`for_iter_path`), is read as `let i: usize = 0; while (i < n) { let x: T =
a[i]; i = i + 1; body }` (`for_array`, `StmtR.forArray`). This is
laniusc's array loop (shaders/codegen/lir/semantic/loop_recipe.slang,
`SEMANTIC_LOOP_RECIPE_ARRAY`): the index starts at 0 and is compared with
the type's constant length; `x` is set from `a[i]`, which reads the array
local again at each step, before the body; the index steps after the
body's block, so `continue` goes to the next element and `break` leaves the
loop. Writes to `a` in the body are seen by later steps in both, and `x`
is a copy, so a body that writes `x` changes nothing else. `i` is hidden
and numbered by the `for` token, and `x` by its own token. laniusc's index
is an `i32`; here it is `usize`, which no source can observe, since the
body cannot name it. Lengths from 2^31 up are not read (the lowering's
array index takes no more).

`for x in s { body }`, with `s` a slice local, is read as `let i: usize =
0; let n: usize = slice_len(s); while (i < n) { let x: T = s[i]; i = i +
1; body }` (`for_slice`, `StmtR.forSlice`; `slice_len` is "Slice length").
This is laniusc's slice loop (`SEMANTIC_LOOP_RECIPE_SLICE`): the length is
read once, before the loop, and each step reads element i. laniusc reads
it from the slice it captured before the loop, here from `s`. The two agree
unless the body writes `s` itself, so such a body is not read (as a range
loop's body that writes its variable is not). Writes to `s`'s elements are
seen by later steps in both, since both views name the same elements. The
hidden locals are numbered as a range loop's: i by the `for` token, n by
`x`'s token, and `x` by the `in` token.

## Match arm statements (decided 10-31, F4)

The source statement `MatchArm(scrutinee, enum_id, variant, binds, binder,
ty, body, rest)` runs `body` when the enum local `scrutinee` is `variant`,
and `rest` otherwise. A match statement, and `?`, are read as a chain of
these, so the statement type has no list of arms and no nested inductive. In
Core (`SrcStmt.toCore`) it is, when `binds`,

    if (match scrutinee { enum_id::variant(_) => true, _ => false }) {
        let binder: ty = match scrutinee { enum_id::variant(binder) => binder };
        body
    } else { rest }

and without `binds` the test's pattern has no fields and `body` runs as it
is. So that:

- a variant with no payload binds nothing (`binds` false); a variant with a
  payload has exactly one field, of type `ty`, which takes slots, and
  `binder` is a copy of it, not an alias, as in Core's `let`;
- `binds` is a flag, not read off `ty`: `Ok(())` has one field of type unit,
  which takes a slot, while `None` has none;
- the lowering tests the tag word against `variant` and copies the field to
  the next free slots (`lower_match_arm`); a tag never needs more than 32
  bits, as for `let match`.

## Unreachable statements (decided 10-31, F4)

`Unreachable(id, ty)` is a branch that never runs, such as the last branch
of the MatchArm chain a `let x: T = op?;` reads as. Its Core meaning
(`SrcStmt.toCore`) is `let id: ty; return id;` (`letUninitialized` of the
`returnValue` of the local), so that:

- Core's `DefinitelyReturns` holds by `letUninitialized` and `returnValue`,
  and a chain ending in it counts as returning without a match rule;
- the read of `id` traps with `uninitializedLocal`, a defined trap, so a
  run that reaches it is a run the compiled code must stop on;
- `ty` is the function's result type: the lowering requires `ty = ret`,
  which makes the `return` type-check, and emits `1 / 0` into the next slot
  (`lower_unreachable`), which has no mini step and traps on x86, as
  `assert`'s failing division does. It binds no slot beyond that one
  (depth 1).
## `?` (decided 10-31, F4)

The front end reads `let x: T = op?;`, `op?;` and their Option forms as
statements, not as an expression: Core has no early return inside an
expression. `op` is a local or a call `path(args)` with no further postfix.
Its type must be `core::result::Result<T, E>` (variants `Ok`, `Err`) or
`core::option::Option<T>` (`Some`, `None`). The function's result must be the
same enum with exactly the same failure payload (`Result<U, E>`, any `U`), as
laniusc requires (docs/language-ergonomics.md). There is no conversion.

`let x: T = f(a)?; body` reads as

    let r = f(a);
    MatchArm(r, variant 1 (Err(w) or None) -> return Err(w) or return None,
      else MatchArm(r, variant 0 (Ok(x) or Some(x)) -> body,
        else Unreachable))

and `f(a)?;` as the same failure arm followed by nothing. For a local
operand, `r` is the local and there is no call.

- The ids: `r` is numbered by the call's `(` token, the failure binder `w`
  by the `?` token, and `x` by its name. Like every local, each is a token
  offset and is distinct from the other locals in scope.
- `T` must be the success payload's type: the reader does not convert.
- The success arm's `else` never runs, since the enum has two variants.
  Core's `DefinitelyReturns` has no rule for `match`, though, so that branch
  is `Unreachable(w, U)`. In Core that binds `w` uninitialized at the result
  type and returns it, which traps, and it counts as returning.
- `x = op?;`, with x a local of the success payload's type, reads like
  the let. Its success arm binds a fresh local `v`, numbered by the `=`
  token, and its body is `x = v`. The statements after it follow the whole
  chain, as they follow any statement. A field or element target with `?`
  is not read.
- `x.m(args)?` and `self.m(args)?` (10-31), with no further postfix, read
  like `path(args)?`: the operand is the method call as `x.m(args)` alone
  reads (`T::m(x, args)` for x's type T), `r` is numbered by the call's
  `(` and `w` by the `?`. This is the stdlib's only `?` after a method
  (`core::path`'s `cursor.next_back()?` and `self.file_name()?`).
- Not read: `?` after a field (`a.b?`) or after a chain longer than one
  method call, on a field or element target, `x.m()?;` as a statement, or
  nested inside a larger expression. The stdlib uses none of these (10-31
  survey of its 168 files).

## Match statements with block arms (decided 10-31, F4)

The front end reads `match (s) { arms };`, with every arm a block
(`pattern -> { statements }`), as a chain of `MatchArm`s in variant order:
arm k runs its block if the scrutinee is variant k, else the next arm is
tried. After the last arm comes `Unreachable(c, R)`, with `c` numbered by
the match's `}` and `R` the function's result type.

- The scrutinee is read like a match expression's. If it reads as a local,
  the chain matches that local. Otherwise its value is bound first
  (`MLetEval`) to a local numbered by the `match` token.
- The arms are taken in variant order (`arms_in_order`), with each variant
  named by exactly one arm, as for a match expression.
- A pattern `V` binds nothing. Its binder id is unused: it is `c`, and its
  type is the scrutinee's. A pattern `V(x)` binds x to the payload's one
  value. A variant whose payload has more than one value is not read.
- laniusc rejects a block arm whose end is reachable (LNC0006), so no arm
  falls through and the match's own end is never reached. The chain's
  meaning does not depend on that: if a block did fall through, the
  statements after the match would run. compileSource rejects such a match
  when it ends a function with a result, since not every path returns
  (case `match_block_open`).
- `let x: T = match (s) { arms }; rest` with at least one block arm and
  exactly one value arm reads as the same chain. The value arm's body is
  `let x: T = value; rest`, so the statements after the let are read once,
  inside that arm (case `let_match_block`). A let's match with two or more
  value arms and a block arm is not read: it would copy rest into each.

## Untyped lets (decided 10-31, F4)

`let x = init;` binds `x` at `init`'s own type, as laniusc's local inference
does: from the initializer alone, never from later uses. For `op?` that is
the success payload's type. Otherwise `init` is read as an effectful
expression with no expected type. Its type must be one no literal decides:
a call (a method call included), a cast, an element, a struct literal, a
`!`, `slice_stride`, `slice_len`, or a local or field (`inferred`). A bare literal, an
arithmetic expression, a variant and a `match` are not read untyped. Their
type depends on a default for literals that the reader does not pick. The
`let` then reads as the typed `let x: T = init;` would.

## `requires` clauses (decided 10-31, F10)

`fn f(..) -> T requires (c1) requires (c2) { body }` reads as a body of
`assert(c1); assert(c2); body`: each clause is a `bool` effectful
expression over the parameters, checked in source order before the body
runs. A false clause traps as a false `assert` does, which matches laniusc
(its `requires_fails` fixture stops with SIGILL before the body runs). The
lexer spec gains the `requires` keyword (laniusc's token code 201). The
grammar has no `ensures` clause, so none is read.

## Item imports (decided 10-31, F11)

`import p::name;` in module `m`, when no file declares anything in module
`p::name`, imports the item `name` of module `p`: in `m`, the bare path
`name` names `p`'s `name`, whether a type, a function, a constant, an alias
or a variant (`pathHome`, `itemImport`, `BareVariant.item`). As in laniusc
(docs/language-ergonomics.md) the import names only that item and beats
module imports for its name; a module of that whole path wins over the
item. One deliberate difference, on programs laniusc rejects: an item
import also beats a declaration of the same name in `m` (laniusc reports a
clash). A module is a path a file's `module` item names, whatever the file
declares (10-31, "Front end review fixes"). Module imports still bring
only variants into scope by their bare names.
Stdlib: `core::wide_i64_checked` and `core::wide_u64_checked`, 20 targets,
all compile now (432 calls agree with laniusc).

## Impls with where clauses (decided 10-31, F7)

An `impl` block with a `where` clause is read as the same block, its
methods found by type alone (the one impl whose type matches, as before).
Since the bounds are checked (next section), the clause now also requires
its bounds of each method instance, at the impl's arguments. Unlocks the 51
such impls in 15 stdlib and `extended/` files, among them `core::iter` and
`core::clone_values`, which most of the stdlib reaches (case impl_where).

## Trait bounds (decided 10-31, F7)

A bound `T: Tr<A, ..>`, written on a type parameter (`<T: Tr<A> >`, `+`
for several) or in a `where` clause, requires that the type T stands for
has an impl of the trait `Tr` at the arguments `A, ..` (`Implements`,
`Reading/Bounds.lean`). The front end checks it after monomorphization, on
each function instance, and rejects the program when a bound fails, as
laniusc does ("no matching impl satisfies this call"):

- **Which bounds.** A function instance's own type parameters' bounds and
  where clause, and for a method also its impl's type parameters' bounds
  and where clause (`FnBound`), read where the function's signature is
  read: its module, its type parameters (the impl's, then its own)
  standing for the instance's arguments. A where clause's predicate must
  name one of those type parameters, else the instance is not read.
- **What a trait is.** A trait is its module and spelling, by the bound's
  path resolved as a type path is (`Resolves`: a bare name is the item it
  is imported as by `import p::Tr;`, else the current module's; `p::Tr` is
  module p's), and its type arguments, each read as a type. A trait's
  declaration is not looked up: an impl and a bound name the same trait
  when their paths resolve alike. The `&Tr` bound form is not read.
- **What satisfies a bound.** `impl<P..> Tr'<B..> for S where ..` (a trait
  impl, recorded in `Decls.impls`) satisfies `t: Tr<A..>` when, with its
  parameters P.. standing for some types, `Tr'<B..>` reads as `Tr<A..>`
  and `S` reads as `t`, and its own bounds and where clause hold there, by
  the same rule (so `Boxed<Boxed<i32>>: Hash` needs `Boxed<i32>: Hash`,
  then `i32: Hash`). The relation is inductive, so a bound holds only
  through a finite chain of impls. The builder finds P.. by matching S
  against t and then B.. against A.., checks the reading as above, and
  tries the impls in order; it has fuel, so a cycle of impls rejects.
  Bounds are a condition on which programs are read, not on what a read
  program means: `Implements` has no output, and `reading_unique` is
  unchanged. Overlapping impls are not an issue for the same reason.
- **No implicit impls.** No type has an impl it does not declare: a
  primitive type satisfies `core::clone::Destroy<bool>` only through the
  stdlib's `impl core::clone::Destroy<bool> for bool`, as in laniusc.
- **Structs, enums and aliases** with a bound on a type parameter are not
  read (`FreeParams`), as those with a `where` clause already were: such
  bounds would have to be checked at each type instance. None is in the
  stdlib.

Cases trait_bounds (compiles), reject_bound, reject_impl_bound and
reject_method_bound. laniusc rejects the three reject cases too.

## Static calls on enums and qualified paths (decided 10-31, F7)

`front::m(args)` calls the method `m` of the one impl whose type matches
the type that `front` names (`TypeOwner`, `EffNamed.static`), when `front`
is a type parameter or a primitive type, or names, as a type path resolved
like any other (`DeclAt`: the current module's type, an item imported by
`import p::S;`, or `p::S`), a struct, or an enum with no variant spelled
`m`. The receiver type is `front` read as a type without arguments
(`BareTy`), so a generic struct or enum as `front` is not read. Before
F7 only a one-segment struct of the current module (or an imported one)
was a type owner.

- `E::V(args)` with V a variant of E still names the variant: a variant
  wins over a method of the same spelling. `E::m(args)` with m no variant
  of E is a method call, where it used to be read as the variant m of a
  module E's enums (module paths and type paths rarely share a spelling).
- A type path beats a module path: when `p::S` is both a type S of
  module p and a module with a function m, `p::S::m(args)` is S's method.
  The same precedence already held for one segment.
- laniusc reads such a path only for an associated function, one that does
  not take `self` (`Color::next(c)` with `fn next(c: Color)`); the front
  end reads either (cases enum_methods, qualified_methods).

## Writes through `&self` (decided 10-31, F5)

laniusc's `&self` and `&T` are references that may write: `fn bump(&self) {
self.n = self.n + 1; }` changes the caller's value (laniusc returns 12 for
the case reject_self_write, where the by-value reading gave 11). Until F5
gives such locals an address, the front end keeps reading `&self` by value
and does not read a method whose body writes the `self` local (a set, a
field set, a set from a call or an effectful value: `writesLocal`). A write
to a slice element through `self` goes to the heap, which the copy shares,
so it is read. `&T` parameters are not read yet.

## The fixpoint (decided 10-31, F12)

What "the verified compiler self-hosts" states, as a theorem
(`selfHost_fixpoint`, `Faithful/SelfHost.lean`): for the self program's
source files `self`, if the front end reads them as `prog` (the program the
certificates are about) and the verified compiler makes `B` of them, then
`prog` is their one reading, and `B`'s code for the driver `w`, given the
words of `self`, faults or returns `B`'s own words (entry count, entries,
image length, then the image's bytes four to a word). The native compiler, run on its own text, is the
compilation of what that text means, and gives itself back.

- The two facts about `self` stay premises, computed by Lean's compiled
  code and checked by the gate (TRUSTED_BASE.md section 5, "The self-built
  verified compiler"). The kernel cannot evaluate the front end on the 8
  files (795 KB, 1.4 million productions) or `compileSource` on `prog`
  (2,221 functions, a 15 MB image): Lean's compiled code takes 12 s for
  both, the kernel's evaluator is orders of magnitude slower and keeps every
  intermediate term. The premises are about source text and the binary on
  disk, so they are exactly what `srcDump` and `runAll` compute; V7's
  premise `compileSource prog = some B` follows from them
  (`compileSource_of_text`).
- `self` is a parameter, not a Lean constant: writing 795 KB of text and
  2.8 million tree numbers as a Lean literal adds nothing the premise `read`
  does not already say, and the theorem holds of any text read as `prog`.
- The extractor is not in the self program. It is not on the path from
  source text to the image: the top theorems are about Core's meaning of
  the reading and the Lean definitions `compileText` and `compileSource`,
  and for the self program the certificates prove each reachable function's
  Core run equal to its extraction, so a wrong extraction would fail to
  check rather than be trusted. A self-built extractor would only matter
  for running `extract` natively, which nothing in the theorems needs.
- The ELF writer is not on the native path: `elf_file` is in the self
  program's text but no root of `w` reaches it, and the self-built compiler
  writes the binary's words. V6's `textProcess_exits` covers `elfFile` as a
  Lean function. A self-built compiler that is itself a process (reading
  the files from standard input with F8's `read_stdin` and writing the
  executable to standard output) would put the driver under
  `process_exits`; it needs a driver proved for byte I/O, and the
  run's 5.2 GiB of heap and its stack in an ELF's zero fill.
- The fixpoint's time (10-31): the gate step took 264 s of its 300 s (the
  native run 218 s; 106 s on 10-29, at 1,823 functions and an 11 MB
  image), and after the changes below about 140 s (the native run about
  112 s, at 2,221 functions and a 15 MB image). The
  bump allocator never frees, so heap is time: allocation was 12 GiB and
  is 5.2 GiB (sampled by rip and heap cursor,
  `target/claude-work/f12/prof.py`). The changes, all to the verified
  compiler, with its proofs kept:
  - The driver's output packs the image four bytes to a word
    (`pack_rounds`, rounds of 4096 words on fuel, so no walk is 15 million
    calls deep), 3.8 million words instead of 15 million, and `link`
    checks the image limit against the functions' sizes (`linked_size`,
    `linkFrom_length`) instead of counting the image.
  - The validator's facts: a write keeps the part of the fact list after
    the last fact it kills (`kill_shared`; `kill_tail` checks that nothing
    after that point dies, so `dying_extent` only decides where sharing
    starts and the proof, `mem_killPrefix`, does not depend on it), and a
    list past 31 facts is cut to its 15 newest (`trim_facts`), so a list
    holds at most 32. The optimizer uses the validator's `facts_after`;
    its own copies are gone. With the packed output this took the heap
    from 12 to 5.6 GiB; the facts no longer show in the profile.
  - `link` builds each function's bytes in front of the rest
    (`link_onto`, equal to `link_from` by `linkOnto_eq`) instead of
    concatenating whole function images: 5.6 to 5.2 GiB.

  The front end then built two lists by appending to what it had read so
  far, so each step copied everything before it: `collect` appended each
  item's declarations to the file's (each `FnDecl` node copied once per
  later item), and `mono_loop` appended each function it read to the
  ones before. `collect` now puts each item's declarations in front of
  the rest's (`collect_front`; `collect_sound` is now `collect … = some
  d → Collect home items d`), and `mono_loop` conses each function onto
  the ones read so far, the last first, and reverses them once at the end
  (`funcs_onto`, `funcsOnto_eq`; `monoLoop_sound` reads `done.reverse`).
  The relations `Collect` and `MonoR` are unchanged. The front end's heap
  went from about 2.1 GiB to 0.7 GiB, and the whole run's from 5.2 to
  about 3.9 GiB, in the same time (the native run about 110 s). The
  lookups (`find_fn`, `get`) allocate nothing: `unbox` reads the node
  through a slice held in slots. The peak resident set is still at the
  4 GiB cap, since about 3.9 GiB is allocated: what is left is mostly
  the encoder (each instruction's bytes built as a list and copied once
  by `concat` onto the rest, and `slot_load`/`slot_store` copying their
  opcode bytes onto `le32`'s, about 1.5 GiB), lowering's
  `concat<Instr>` and the validator's facts.

### The design of writes through references (decided 10-31, F5)

The stdlib has no `&mut` and no `&mut x`; it has 1046 `&self` methods, 200
of which write `self`, 279 `&T` parameters and 100 functions that return a
reference. In that order of need:

1. **Core.** Core's places gain `Place.deref reference`: the reference's
   value names a cell and a projection path, and the place is that path in
   that cell, so `self.n = v` in a method that writes `self` is
   `assign set (field (deref (local self)) n) v` and writes the caller's
   cell. Core still does not dereference a place automatically: the front
   end writes the `deref`, as the elaborator writes `dereference` for reads.
2. **Which methods take a reference.** A `&self` method whose body writes
   `self` (`writesLocal`) takes a reference; one that does not is still read
   by value, which has the same meaning when nothing writes through it. `&T`
   parameters follow the same rule.
3. **Lowering.** Mini Source's `ref ty` is one slot holding an address. A
   call that passes a reference to a local's place evaluates the other
   arguments first (Core's reference names the cell, not a copy, so the
   order of reading is the call's), stores the place's slots into the
   function's frame block, passes the block's address plus the place's
   offset, and loads the slots back after the call. Each function takes one
   frame block at entry (`Frame`), as large as its largest such store, so a
   loop does not use more frame memory. A reference parameter passes its
   own address on, plus a field's offset. Reads and writes through a
   reference are word loads and stores at the address. A reference is only
   passed as an argument: a function whose result, a struct field or a
   local's type holds a reference is not read, so no address outlives the
   activation that took it.
4. **The correspondence.** `FrameCorr` (`Mini/FrameCorr.lean`) lists the
   places in frame memory: cell, projection path, type, address. Each
   place's value is its words (`ty.HoldsAt v (hp.words address) 0`, the
   slot layout), and its words lie between the frame pointer and the top.
   Stores below the frame pointer (the bump heap, a callee's own frame) and
   Core writes to other cells keep it (`FrameCorr.congr`); a store through a
   reference changes Core's cell at the path and the words together.

## Wildcard match arms (decided 10-31, F11)

A last arm `_ -> value` (a plain one-segment pattern spelled `_`) is the arm
of every variant that no other arm names, in a match expression, a match
statement with block arms and a let's match (`arms_in_order`,
`ArmsOrder`). The front end reads it as the arm `V(_, ...) -> value` for
each such variant V, in variant order (`wild_arm_for`: the wildcard's tree
with its one segment spelled V and one binder per payload field), so the
arms after it are read as before.

- laniusc runs the first arm that matches, so an arm after a wildcard never
  runs. The front end reads a wildcard only as the last arm; a wildcard
  before another arm is not read (case reject_wild_first). laniusc accepts
  it, so this is a reading the front end leaves out, not one that differs.
- Every other arm must name a variant, and no variant may be named twice,
  as without a wildcard. A wildcard after arms naming every variant stands
  for none, so its value would not be read at all; the front end rejects it
  (`uses_wild`; case reject_wild_unused), which laniusc accepts.
- The compiler binds every payload field of an arm (`arm_scope`), so the
  wildcard binds each field of V's payload, field i to the id of the `_`
  token's position plus i, named `_`, which no expression can spell. The
  ids are checked fresh like any binder's. The value is read once per
  variant it stands for. A match statement's arm still binds at most one
  value (`arm_binder`), so there a wildcard for a variant of two or more
  fields is not read, as an arm naming it would not be. A
  wildcard with a block value in a match statement is the same block in
  each variant's arm; its lets bind the same local ids in branches that
  exclude each other, which Core's scoped lets and the lowering allow.
- Determinism: an arm another arm names is the same arm in any reading
  (it names one variant, and variant names are distinct), and the wildcard
  as V's arm names V only (`armsOrder_unique`).
- A let's match with block arms still needs exactly one value arm as
  written; a wildcard value arm then copies the statements after the let
  into each variant it stands for.

## Enums with no variants (decided 10-31, F11)

An enum with no variants (`enum Never {}`, as `core::clone_values::Infallible`)
needs nothing new in the front end: it is a type with no values, so a
`Result<T, Never>` is always `Ok`, and the arm of its error still binds its
payload (case empty_enum). A match on a value of it has no arms; the front
end reads it (`ArmsOrder` with no variants and no arms), but `compileSource`
rejects it, since Core has no match with no arms and the lowering would need
one that traps (case empty_match, `compile_rejects`). No reachable code can
run such a match, so this leaves out no behavior a program can show.

The 14 `core::clone_values` targets were unread for a reason in the oracle,
not the front end: its wrapper wrote the trait method's result at the
instance type (`Result<bool, E>`) where laniusc checks the generic helper
first (`Result<T, E>`), and wrote the trait's type arguments unqualified from
the wrapper's module (LNC0006). `stdlib_oracle.py`'s `wrapper_text` writes
both as laniusc names them; 12 of the 14 now compile, 240 calls agree.

## Nested patterns (decided 10-31, F11)

A match expression with a nested arm, one whose payload patterns are not all
plain binders (`Ok(Some(x))`, `Pair(Bar::X(a), b)`, `Err(m::E::V(n))`), is
read as nested matches (`match_order`, `MatchOrder`, `NestedOrder` in
`Reading/Nested`). Module-qualified patterns need nothing new: an arm's path
may already be `V`, `E::V`, `m::V` or `m::E::V` (`ArmNamed`). Variant V's arm
is the wildcard's when no arm names V, V's one written arm when that is
plain, and otherwise `V(b, .., h, ..) -> match (h) { p -> value, .., _ ->
w }`: the arms naming V, in order, matched on the first arm's first column
j that is not a binder; each gives the inner match its pattern p at j and
its value. The inner match is read again, nested or not.

- laniusc runs the first arm that matches. The arms naming V are kept in
  order in the inner match, and every other column of each of them must be
  a binder spelled as the first arm's (`row_fits`), so each arm matches
  exactly when its pattern at j does, and its value sees the same names
  (bound to the same payload fields, with the first arm's ids). Arms that
  differ off column j are not read; laniusc accepts them, so this is a
  reading the front end leaves out.
- (F11b) When V's first arm is plain and a later one for V is nested
  (`In(n) -> 5, In(Num::Val(x)) -> x`), the plain arm is V's arm
  (`VariantArm.shadow`): it matches every value of V, so laniusc never runs
  the later ones, and they are not read. laniusc type-checks them, so a
  program whose never-run arm is ill-typed is read here and rejected there;
  the meaning of a program both accept is the same. Without a nested arm
  for V, a second arm for V is still rejected, as without nesting. Case
  nested_plain_first (laniusc runs it alike).
- At column j the last arm may be a binder; it matches everything there,
  so it is read as `_` when its value spells no token as that name
  (`Mentions`), and otherwise not read (case reject_nested_binder).
- The outer wildcard, if any, is added as the inner match's last arm,
  unless an inner arm is `_` already or the inner arms name every variant
  of h's enum with plain binders (`Covers`): then no value of V reaches it.
  In the inner match the first arm's other binders are in scope, where the
  wildcard's value was written without them, so it is added only when its
  value spells none of their names (`ColsQuiet`; case
  reject_nested_capture). The wildcard must still be used somewhere, a
  variant's arm or an inner arm, so that its value is read.
- h is a binder no source can spell (the one byte 0), its id the position
  of the first arm's pattern at j, checked fresh like any binder's. The
  inner match's scrutinee is h.
- A match statement reads block arms; a nested match expression may have
  no arm whose value is a block (`BlockValue`), so the two readings never
  overlap.
- (F11b) A match statement with a nested arm is read the same way
  (`stmt_arm_order`, `StmtOrder`), its arms' values blocks: the nested arm
  `V(h) -> match (h) { p -> { .. }, .. }` is read as a match statement on h
  inside V's arm (`ArmsStmtR.inner`), its closer the arm's `->` token, so
  every inner arm leaves the match as a block arm does. laniusc runs such
  a statement as written (case nested_match_stmt runs alike); an inner
  match that names some of h's variants and has no wildcard is rejected
  (case reject_nested_stmt_gap). A block arm's value is never the bare
  match node `nest_arm` builds (`armBlockR_noMatch`), so the two arm
  readings never overlap.
- (F11b) A let's match with a block arm and a nested arm, `let x: t = match
  (s) { V(Some(y)) -> y, V(None) -> { return 0; }, .. }`, is read the same
  way (`LetArmsR.inner`): the inner match is read as the let's match on h,
  its value arms binding x and running the rest, its block arms leaving. A
  value arm's value is never the bare match node (a written `match` sits
  under its expression levels; `LetArmsR.value` requires it), so the value
  and inner readings never overlap. Case nested_let_match (laniusc runs it
  alike).
- Every arm but a last wildcard must name a variant, as without nesting.
- Determinism: whether some arm is nested decides the branch; the arms
  naming a variant, their patterns, the column and the inner arms are each
  determined by the tree (`nestedOrder_unique`, `matchOrder_unique`,
  `stmtOrder_unique`).

## Payload names that are variants (decided 10-31, F11b)

laniusc reads a payload pattern whose name resolves to a variant as a check
of that payload, not a binder: `match_payload_binding`
(`shaders/codegen/lir/semantic/local_mark.slang`) binds a payload pattern
only when its resolved declaration is no variant, and
`shaders/codegen/lir/semantic/match_reference.slang` lowers one that names a
variant as a check of the payload's discriminant. So with `import
core::option;`, `Some(None) -> 1` matches only `Some(None)` (laniusc runs
`Some(Some(7))` past it). The front end once bound such a name: a payload
binder had only to be spelled unlike the module's own types, aliases,
constants and variants (`module_globals`), so an imported variant's bare
name was a binder and the arm read as `Some(_) -> 1`, a wrong reading.

Now a payload pattern spelled like a variant of any enum of the program is
never a binder (`any_variant`; `BindersR`'s `NoVariant`). This covers every
name laniusc resolves to a variant (its own module's, an imported module's,
an item import's, or one the payload's type gives), and more: a payload name
spelled like some variant nowhere visible is not read either, a reading the
front end leaves out. Such a pattern is a nested pattern, read as the check
it is (SEMANTIC_DECISIONS "Nested patterns"; cases bare_variant_payload,
reject_bare_variant, which was misread). Variants are spelled with a capital
letter in the stdlib and `extended/`, so no binder there is affected.

## Front end review fixes (decided 10-31)

The 10-31 review of the front end against laniusc found three programs the
front end read with another meaning than laniusc's. Each is now read as
laniusc reads it or not read (frontend cases `reject_for_write`,
`reject_index_call`, `module_traits_only`):

- A write to a range loop's variable. laniusc's loop variable is the
  counter itself (shaders/codegen/lir/semantic/loop_recipe.slang: the
  binding is set to the start and incremented), so `for i in 0..n { i = i +
  1; ... }` runs about n/2 times there and n times in a reading with `x` a
  copy of the counter. `for_range` does not read a body that writes `x`
  (`writesLocal`, as for `&self`; `StmtR.forRange`). Reading `x` as the
  counter would also need `continue` to move on after the body, which is
  laniusc's order but not this desugaring's.
- `s[i] = value` where the value can act: it calls a declared function or a
  host service (`effActs`; a field projection only reads). Core checks `i`
  against the length before it evaluates the value ("Traps in compiled
  code"); laniusc's store is one operation after its operands, so its bound
  guard runs after the value (shaders/codegen/x86/safety_emit.slang). With
  `i` out of bounds, laniusc runs the call's effects (output, a loop that
  never ends) before it traps, and the reading traps first. Such a store is
  not read (`AssignTargetR.indexEval`); a value without calls traps or not
  the same way in both orders (Core does not tell traps apart), and a call
  in the index is read. Programs write `let t = f(); s[i] = t;`. The quick
  gate's `store-rule` step (formal/tools/store_rule.py, a port of this rule
  to the source text) names any such store in stdlib/ and extended/.
- A module that declares nothing the front end counts. laniusc's module
  table holds every file's `module` item, and an import whose whole path is
  a module imports the module (modules/05_resolve_imports.slang). The front
  end counted a module only when it declared a type, function, constant or
  alias, so `import a::b;` with `a/b.lani` holding only a trait imported the
  function `b` of `a`, and a local `b()` called `a::b` instead of this
  module's `b`. Now a `module` item declares its path (`Decls.homes`,
  `ItemDecls.module`) and `isModule` is membership in those paths.

## Oracle comparisons of laniusc's programs and `extended/` (decided 10-31, F11)

- Traps agree as traps: laniusc's checked traps exit 101 (bounds), 102
  (shift), 103 (division by zero) and 104 (signed overflow), or end with
  SIGILL or SIGFPE; the verified compiler's traps end with SIGFPE or SIGILL.
  The programs oracle counts a run as agreeing when both trap with the same
  output, as Core does not tell the traps apart in a program's result.
- A program whose resources differ by design is listed as known, not as
  agreeing: `raw_host_width_admission` asks the host for 4 GiB, which
  laniusc's mmap gives and Core's heap budget (64 MiB) refuses with a trap.
- Programs read their imports from `extended/` and from their own
  directory (`--source-root`, more than once); the stdlib oracle's `--root
  DIR` adds such a root and makes its modules the targets, which is the
  full-tier gate step `extended`.

## Byte views (decided 10-31)

Core's raw slices had no `u8` element: `slice_from_raw_parts` of a `u8`
pointer trapped `typeMismatch`, so the verified compiler lowered no function
with a `[u8]` or `View<u8>` slice. A raw slice of `u8` is now a byte view,
in laniusc's layout (point 2 of "Addressed locals"): element `i` is the one
byte at `pointer + i`.

- `isByte` marks the element type `u8`. `NativeLayout.elementStride?` is 1,
  `rawSliceElementAddress?` is `address + index`, and a `[u8]` value is the
  usual 3 words (pointer, length, padding).
- `mapRawNominalSlice` of a byte view checks `length` bytes from `pointer`
  inside one live block (`checkRange`, alignment 1); a length of 0 needs no
  block, as for the other raw slices; a negative length traps
  `rawMemoryBounds`.
- A read of element `i` loads the one byte (`readRawElement`), not the
  4-byte word a `u8` struct field or local takes in native layout; a write
  stores the value's one byte (`storeRawByte`, any other value is
  `typeMismatch`). The place says so: `ResolvedPlace.rawByte`, set by
  `evalPlace` on a byte view's element and false everywhere else, picks the
  store (`writeRawNative`).
- `typedSliceFromRawParts` types a byte view (`RawNominalSliceElement.byte`)
  beside the declared structs and enums.

The verified compiler lowers `s[i]` of a byte view to a bounds check and a
zero-extending byte load (`LoadByte`, `movzx`), and `s[i] = v` to a byte
store (`StoreByte`, `mov byte`) after the same check; `slice_stride` is 1.

## The prelude's `minus` truncates (decided 11-01, review finding 5)

The self program's prelude (`compiler.lani`, `frontend.lani`) had `minus(a,
b)` panic when `b > a` ("used only where a >= b", which nothing checked).
It now returns 0 there, which is Lean's truncated `Nat` subtraction, the
meaning the extraction gives it (`PRELUDE_FNS`: `-`). So no run of the self
program can stop at a `minus`, and the 287 `minus` calls the compile makes
are no longer places its pure meaning can fail. `plus` and `times` still
panic on a result past `2 ^ 64`: `usize` has no room for it and Lean's
`Nat` has, so they are where the self program and its Lean definitions can
part (`selfCompiler_reason`'s "no pure cost"). `extract.lani`'s and
`mut_pilot.lani`'s own preludes are unchanged; their Lean meaning is the
same `-` either way.

With it, `wide_digit` (`frontend.lani`) returns `None` before the multiply
that would pass `2 ^ 64` (`acc > 1844674407370955161`, or equal with a digit
above 5). Before, it checked `acc` only on the next digit, so a 20-digit
literal such as `99999999999999999999` panicked in `times` or `plus` where
Lean's `wideDecimal` gave `none`; the self-built compiler then faulted on
any source with such a literal instead of returning -1. `wideDecimal` gives
the same answers as before.

## Integer literal bases (decided 11-01)

The verified front end reads integer literals as laniusc does: decimal
digits, or `0x`, `0o` or `0b` (the letter in either case, as the lexer's
`lx_base_of` takes it) and digits of base 16, 8 or 2, with `_` separators
skipped (`lit_value` in `frontend.lani`; `intValue` in
`Reading/Exprs.lean`). Before, only decimal digits without `_` were read,
so such a program was rejected (found by `fuzz_oracle.py`'s EDGE_FORMS).
The value then goes where a decimal one does: an `i32` literal below 2^31,
the wide marker up to 2^64, a constant's value. A digit of base 2, 8 or 16
may follow only a value at most `(2^64 - base) / base`, which is exact for
those bases, so nothing past `2^64 - 1` is formed. An array length is still
read only as decimal digits. A type suffix (`5u8`) is read by neither.

## Literal patterns (decided 11-01)

The verified front end reads a match on an integer or `bool` value whose
arms' patterns are integer literals, `true` or `false` (found by the
fuzzer: `match (x) { 1 -> 10, 3 -> 30, _ -> 0, }`). The arms are tried in
order: the match becomes `if (x == n) arm else ..` on the scrutinee's local
(bound first when the scrutinee is not a local), each literal typed at the
scrutinee's type, so a `u8` match compares `u8` values. `true` and `false`
test `x` and `!x`. The last arm must be `_`; at `bool` it may instead
follow arms for both `true` and `false`, and the chain then ends in an
unreachable statement, which no run reaches. A repeated literal's later
arm is never run, as in laniusc's first-match lowering. A match that is
not exhaustive this way (no `_`, an integer match without one) is not
read. The forms read are a match statement, a typed `let`'s value (each
value arm followed by the rest of the block) and a returned value; a
negative literal pattern and a literal inside a payload pattern are not
read.

A literal match is also read anywhere in an expression, as a value: a
chain of conditional expressions (`EIf`, below) in arm order, each
literal arm's test on the scrutinee choosing its value, else the rest of
the chain, and the `_` arm's value (or the last `bool` arm's) at the
end. Each arm's value is read at the type the match's position expects,
and the match has that type, or else its first arm's. A pure scrutinee
is tested as it is: reading a pure expression changes no state, so each
test gets the first read's result, as laniusc's one evaluation does. An
effectful scrutinee, such as a call, is evaluated once and bound to the
local the `match` token numbers, as the statement form binds it; the
chain then tests that local. The binding is a let in the expression
(`ELet`, "Lets in expressions"), so the match fits any position. A let or
return of a literal match has both readings, so the statement form is
taken only when the value form cannot apply, because some arm's value is a
block (`lit_wanted`, `LitWanted`). The two readings mean the same, and
each source then has one reading, as the front end's uniqueness proof
needs.

## Conditional expressions (decided 11-01)

The verified compiler's mini syntax has a conditional expression,
`SrcEff.eIf c T a b` (`EIf` in `compiler.lani`): `a` when the bool `c`
is true, else `b`, both of type `T`. Core has no conditional expression,
but its `matchValue` takes literal patterns, so the meaning
(`SrcEff.toCore`) is Core's match on the condition's value, with an arm
for the literal `true` and then a wildcard arm. Core needed no change.
The lowering (`eval_if` in `compiler.lani`) is the smallest that fits the
mini IR's way of computing a value into a slot. The condition goes into
the slot, and `Ite` on that slot then runs either branch's code, which
writes into the same slot. The condition has been tested by then, so
nothing needs a fresh local. It checks that the condition is a bool and
that both branches have type `T`. The proofs are its cases in the
forward simulation (`eval_if`), in the stopping of failing runs
(`eff_if`), in heap growth (`ifArms_grows`) and in Core typing
(`SrcEff.eval_typed`). The self-simulation's pure meaning has it (11-01,
F11b): `peff` tests the condition's bool and gives the branch's value
(`qeff` with its cost), `effTy` takes a bool condition and two branches of
one type, the termination check checks all three parts, and `liveEff` needs
all three live. Its cases are in `eff_step` (Core's run to the pure value,
from `ifArms_inv`), `eff_live` in `Fwd/Eff.lean` (the converse), `eff_safe`
(no undefined trap, from `ifArms_trap_inv`), `eff_evConst` (settling) and
`eff_live` in `Sim/Live.lean` (a value of its type). So the compiler's own
sources may use it once the certificates are regenerated. The front end
produces it for a literal match in an expression ("Literal patterns"
above).

## Lets in expressions (decided 11-01)

The mini syntax has a let in an expression, `SrcEff.eLet x T v R b`
(`ELet` in `compiler.lani`): `v`, of type `T`, is bound to the local `x`,
then `b`, of type `R`, is the value. Core has no let expression, so the
meaning (`SrcEff.toCore`) is Core's match of `v` with one arm, the pattern
`bind x`: Core binds `x` for the arm and drops it after, as it does a match
arm's payload binders. Core needed no change. The lowering (`eval_let_in`)
is a match with one arm and no tag test. `v` goes into the slot, and `x`'s
binding names that slot (`arm_scope`, as for a payload binder). `b` is
evaluated from `match_dst(slot, T, R)`, above both values, and its value
is then copied down to the slot. The proofs are its cases in the forward
simulation (`eval_let`, from `armScope_layout`), in failing runs
(`eff_let`), in heap growth (`letArm_grows`, and `letArm_trap_grows` in the
Faithful layer) and in Core typing (`armScope_ok`, Core's `bind` pattern).
The Faithful pure meaning has it (11-01, F11b), as `EIf`: `peff` binds the
value's pure value and evaluates the body, `effTy` types the body with the
value's type, and the termination check gives the local the value's size
class (`effCls`), as `letEval` does. The front
end uses it to read a literal match whose scrutinee is effectful ("Literal
patterns"): the scrutinee bound to the `match` token's local.

## Loops and assignment in the pure fragment (decided 11-01, F11b)

The Faithful pure meaning (`Faithful/Pure.lean`) gave loops, assignment,
`break` and `continue` no meaning, so a function with a `for` or a `while`
had no certificate. They get one as follows. Neither `mut_pilot` nor the
TLS lifecycle machine has a loop today: `extract.py` reads `+=`, `-=` and
`&mut` writes as a rebinding (`let x := x + e`), and the machines' runs
are Lean recursion on a fuel at least the number of steps
(`Machine.lowered`, `lowered_eq_run` in `Machines/RunLowering.lean`). The
pure meaning takes the same two shapes: an assignment rebinds the local in
the environment, and a loop is recursion on fuel.

- **The meaning of a statement** is `mstmt call fuel env s : Option Out`.
  `Out` is how the statement ended and, unless it returned, the environment
  it left: `next env`, `brk env`, `cont env` or `ret value`. `fuel` is the
  loop fuel; `call` is still the meaning of calls.
- **Assignment.** `x = e` (`set`, and `setEval` for an effectful value)
  evaluates `e` and replaces the value of `x`'s newest binding
  (`Env.set`), as Core's `assign` writes the cell `x`'s newest binding
  names. It is `none` when `x` is not bound. `x += e` is read as
  `x = x + e` by the front end already, so it needs nothing more.
- **Scopes.** A `let` runs its body with the new binding first, then drops
  it from the environment the body left (`Out.pop`), as Core's
  `restoreLocals` drops the local and keeps the cells the body wrote. `a;
  b` runs `b` in the environment `a` left. A `break`, `continue` or
  `return` skips the rest.
- **Loops.** `while c { b }` (and `whileEval`) is `ploop`, recursion on the
  fuel: with fuel `n + 1` it tests `c`; on `false` it ends `next` in the
  current environment; on `true` it runs `b`, then loops with fuel `n` in
  the environment `b` left if `b` ended `next` or `cont`, ends `next` if it
  ended `brk`, and returns if it returned. With fuel 0 it is `none`. Core's
  `whileLoop` with fuel `k` runs fewer than `k` steps, so the loop fuel of a
  body is its call's fuel: `pcall (n + 1)` runs the body with calls of
  fuel `n` and loop fuel `n`. Both only grow the answer (`mstmt_mono`): a
  value at some fuel is the value at every larger fuel.
- **Function results.** A body that ends `brk` or `cont` has no value
  (`outValue`), as Core traps (`typeMismatch`) on a body that ends so.
- **Certificates.** The certificates go on with the loop-free meaning
  `pstmt` they use now. `pcall_succ` unfolds a call to `pstmt` for a body
  with no loop, assignment, `break` or `continue` (`SrcStmt.loopFree`,
  checked by `rfl` in an `autoParam`), by `mstmt_loopFree`: such a body
  leaves the environment it got, so `mstmt` is `pstmt` with that
  environment. The generated certificates do not change while no self
  function has a loop or an assignment.
- **The checks.** `stmtOk` takes `x = e` when `x` is bound and `e` has its
  type, `while c { b }` when `c` is a `bool` and `b` passes, and `break`
  and `continue` anywhere. `PureFunc` also asks that the body has no
  `break` or `continue` outside its loops (`looseJump`, which is
  `SrcStmt.breaksOut`), since Core traps undefined (`typeMismatch`) on a
  call whose body ends with one. A loop may go on, so `neverNext` of a loop
  is `false`.
  The termination check (`chkStmt`) forgets the size class of every local a
  statement may write (`SrcStmt.writes`, `AEnv.forget`) for the statements
  after it and, for a loop, in its condition and body. Settling needs no
  measure at all: since a value at some fuel is the value at every larger
  fuel, every pure call settles (`pcall_settles`, by `pcall_mono`), to its
  value when it stops and to `none` when it does not. `pcall_complete`
  keeps its statement and no longer walks the check; the check's classes
  now serve the liveness proof only. The liveness check (`liveStmt`)
  needs a measure, since a live call must have a value. It does not take
  loops yet. The next step is to take the front end's counted loop, `while
  c < e { let x = c; c = c + 1; b }` with `b` writing neither `c` nor `e`,
  which runs `e - c` steps.
- **The proofs** relate Core's state after a statement to the environment
  it left. A loop is one induction on fuel in each direction:
  `loop_sim` (Core's run with fuel `k` is `ploop` with fuel `k`, then more
  fuel by `ploop_mono`), `loop_safe` (a trap is the test's, the body's or
  a later step's) and `loop_live` (`qloop`'s ending is Core's, by
  `while_again_fwd`, `while_break_fwd` and `while_ret_fwd`). `Locs` (next to `Inv`) says that the cells of the locals are
  distinct and allocated, so an assignment to `x` changes no other visible
  local.
  Statements keep `Frame st st'` (in place of `Step`): every cell that no
  visible local names keeps its value, the others may change, and new
  cells come after. So a local a `let` shadowed keeps its value, and a
  call's body, whose visible locals are its own new cells, leaves the
  caller's cells as `Step` says.

## Slice length (decided 11-01, F11b)

Core gets `Intrinsic.sliceLength`, written `slice_len(s)` beside
`slice_stride(s)`: the length of a slice as a `usize` (`sliceLength?`).
It is the same for a slice of a language array (`Value.slice`, its
`length`) and for a raw view (`Value.rawSlice`, its `length`). Any other
value traps (`typeMismatch`), as `slice_stride` does. The typing rule is
`ExprHasType.sliceLength`, from any `[T]` to `usize`, with its checker arm.
It is spelled `slice_len`, not `len`, because `std::vec::len` and
`core::set::len` already name free functions `len`, and `slice_stride` is
the intrinsic it sits beside. It is a `usize` because Core's slice length is
a natural number. The mini syntax's lengths are below 2^31, so the value
also fits laniusc's `i32` lengths. laniusc keeps a slice's length in word 1
of its descriptor (`NATIVE_SLICE_LENGTH`) and reads it there. It has no
surface intrinsic for it yet. Adding `slice_len` to laniusc's intrinsics
(`shaders/type_checker/calls/intrinsic_result.slang`, `stdlib/core/mem.lani`)
is a laniusc step, not yet run.

The mini syntax reads it as `SrcEff.eLen x` (`ELen` in `compiler.lani`), for
a slice local `x`; its meaning is Core's `intrinsic sliceLength (local x)`.
The lowering (`eval_len`) copies the slot after the slice's pointer, where
the slice keeps its length, to the result slot: a raw slice is its address
then its length, and a borrowed slice of a caller's array (`HoldsAt`'s
`borrowed`) its pointer then its length, so one read covers both. The
proofs are its cases in the forward simulation (`eval_len`, from
`len_inv`), in failing runs (`eff_len`: Core does not fail on a slice
local), in heap growth (and `len_trap_state` in the Faithful layer) and in
Core typing (`ExprHasType.sliceLength`). The Faithful pure meaning leaves it
unmodelled, as it does `ELet`.

The front end reads `slice_len(x)`, with `x` a slice local named alone, as
`ELen(x)` (`len_arg`, `EffPathCall.len`), as it reads `slice_stride(x)`.
`slice_len` joins the reserved paths (`builtinPaths`), so no function or
variant is read there. Its type is `usize`, so `let n = slice_len(s);`
needs no annotation (`inferred`).

## `u16` views (decided 11-01)

Core's raw slices had no `u16` element (`slice_from_raw_parts` of a `u16`
pointer trapped `typeMismatch`), so the verified compiler lowered no
function with a `[u16]`, among them `core::utf16`'s, which
`core::utf16_bytes` and `core::transcode` call. The request was a two-byte
packed view, but laniusc does not lay `[u16]` out that way:
`stdlib/core/mem.lani` packs only `i32` (stride +4) and `u8` (+1), and every
other scalar is one descending 8-byte word. Measured with laniusc:
`slice_stride` of `typed_slice_from_storage<u16>(p, 2)` is -8, and so is the
stride of a `[u16; 2]` local passed as a `[u16]`. A packed view would make
Core disagree with laniusc on every `[u16]` built from storage, so a raw
slice of `u16` is a word view, as point 2 of "Addressed locals" says for
every scalar but `i32` and `u8`:

- `NativeLayout.elementStride?` of `u16` is -8 (its one native word) and a
  `[u16]` value is the usual 3 words. `rawSliceElementAddress?` is the
  struct and enum rule with one word: element `i`'s word is at
  `pointer - 8 * i`.
- `mapRawNominalSlice` checks the view's words in one live block, as for a
  struct or enum view.
- An element is read and written as a `u16` value is everywhere else in
  native layout (`readNativeValue`, `writeNativeValue`: the word's low 4
  bytes, a value above 65535 is `typeMismatch`); it is not a byte view
  (`isByte` stays `u8` only).
- `typedSliceFromRawParts` types it (`RawNominalSliceElement.word16`).

The verified compiler lowers it on the word-element path (`word_element`
accepts `u16`): `s[i]` is a bounds check and a 32-bit load at
`pointer - 8 * i`, `s[i] = v` a 32-bit store there after the same check,
and `slice_stride` is -8. The other one-word scalars (`u32`, `u64`, `i64`,
`bool`, `char`, `ptr`, ...) have the same layout in laniusc and are later
work.

## Type weights (decided 11-01, F14)

The self-built compiler trapped on a 7-line program. A parameter of type
`[[[i32; 2000000000]; 2000000000]; 2000000000]` has 8 * 10^27 slots, so
`SrcType::size`'s `times` overflowed a usize (SIGILL in laniusc's build of
the verified compiler). Lean computed the size in `Nat` and rejected the
program only later, at `frame_limit`. Structs whose fields double,
`S_k { a: S_{k-1}, b: S_{k-1} }`, reach 2^64 slots in 64 links. The front
end now rejects any type heavier than `weight_limit()` (2^22) before the
compiler sizes it:

- A type's weight is at least its slot count and its node count. A scalar
  weighs 1, a slice 1 more than its element, `[T; n]` 1 + max(n, 1) times
  T's weight, a struct 1 more than its fields together, and an enum 1 more
  than all its payloads together (`src_weight` on source types, `ty_weight`
  on the front end's types).
- `array_type` keeps an array type only within the limit (`weighed`). This
  covers arrays written at a use site.
- `types_weighed` checks every instance in the type table before the
  instances are lowered. It works bottom up in rounds: each round weighs the
  instances whose parts already have weights, so a doubling chain is
  rejected at its 21st link, not lowered at exponential cost. An instance
  that never gets a weight (past the limit, or not lowerable) rejects the
  program.
- The arithmetic is guarded (`weight_sum`, `weight_times`), so weighing
  itself cannot overflow. With every type's size at most 2^22, sums of
  sizes over a function's lets, offsets (`times(8, ...)`) and frame sizes
  stay far below 2^64 for inputs under 2^31 words.

laniusc fails both programs too, but not cleanly: `LNC0057 compiler
execution failed` ("a compiler diagnostic gap"). The cap is 4x the
compiler's `frame_limit` (2^20 slots), and no checked-in program has a
type near it (the largest arrays are 262144 elements). A type heavier than
2^22 that fits no frame, for example one behind a slice that is never
indexed, or a declared but unused struct, was accepted before and is
rejected now.

Still open: building the type table (`ty_insts`) expands every occurrence
of an instance, so a doubling chain takes exponential time there, before
`types_weighed` runs. The front end takes about 1 s at 18 links and about
60 s at 24, where it rejects, and hangs at 70 links. This is time, not
overflow: the pure compile still reaches its result at some fuel. A
visited set in `ty_insts` would make it linear, but the reading's
`TyInsts` relation is stated over the full expansion, so that change needs
its own proof.

## Budget certificates (decided 11-01, F14)

`CompileBounded T` asks that the guarded run of `progW` has a value
whenever `progW`'s run costs under `T`. It is proved function by function.
For each self-program function `F` at index `ix`, with the unit cost
`uc = fun _ => 1` (each boxed call costs 1),
`formal/tools/budget_certs.py` generates three things into
`Faithful/GenB/`: two Lean models `Pre_F` and `Cost_F` beside the
function's Lean meaning `F`, and a budget certificate:

    qcall progW prims uc n ix vs = some (w, k) → Rep x vs → k < b → Pre_F n x b →
      qcall prog prims uc n ix vs = some (w, k) ∧ Cost_F n x = k ∧ Rep (F x) w

If `F` cannot overflow along any path, it has no `b` and no `Pre_F`.

- The models follow the source function, not the Lean meaning. Inline
  functions are separate source functions. Values are Lean terms over the
  parameters, with callee results written as the callee's Lean meaning
  `G y`. Both models are fuel-indexed like `qcall`: `Pre_F 0 = True` and
  `Cost_F 0 = 0`. The case `n = 0` is vacuous, because `qcall` at fuel 0
  is `none`.
- The Cost_F convention: `Cost_F (n + 1) x` is the sum along the taken path
  of `Cost_G n y` for each costly callee, plus 1 per boxed prim call.
  A callee that never reaches a boxed prim is free and adds nothing. Its
  certificate states `0 = k`. Branches that are equal collapse.
- The Pre_F generation rule: `Pre_F` is built in evaluation order, in
  continuation-passing style, with `B` the budget still left. At a call of
  a guarded `G` it adds `Pre_G n y B`. After a costly call the rest is
  `∀ b1, Cost_G n y < B → b1 = B - Cost_G n y → REST` at `b1`. After a
  boxed prim it is `∀ b1, 1 < B → b1 = B - 1 → REST`. The new budget gets
  a name, so it does not grow along a path: written out as differences,
  a long branch chain made one model 1.6 MB. A part that is `True` is
  dropped. A condition that is the literal `true` or `false` is decided
  by the generator, so a lazy `&&` chain copies its continuation once per
  operand, not twice.
  `plus` and `times` are the base cases:
  `Pre_plus n x y b := x + y < 2 ^ 64`, likewise for `times`, and their
  certificates are written by hand (`Budget.bcert_plus`, `bcert_times`).
  Lazy `&&` and `||` and pure arguments follow the semantics: a condition
  that is not evaluated adds nothing.
- The premise is stated against the remaining budget, not the cost so far.
  The run's total cost `k` is below `b`, so every prefix is below `b`, and
  a callee's certificate gets `k_G < b - prefix`.
- A function without arguments that reaches neither `plus` nor `times`,
  through no recursion, for example a table builder such as
  `grammar_part_0`, which makes hundreds of calls in a line, is not proved
  step by step. The kernel evaluates its run instead (`decide +kernel`),
  using `BudgetClosed.qcallB`: a computable `qcall` that has no value at a
  call of `plus` or `times`, and whose value is the self program's
  (`qcall_of_okW`). `bclosed` takes four premises: the run has a value at
  the fuel `D` (its call depth), its cost there is `Cost_F D`, `Cost_F`
  is the same past `D` (by `rfl`), and there is no run below `D`. From
  these it gives the certificate at every fuel. (11-02: 54 functions, the
  costly ones; the free ones take `bfree`, below.)
- Proofs: the `budget` tactic (`Faithful/BudgetTactic.lean`) runs the two
  `qcall`s in lockstep. It steps through calls with the callee's
  certificate, prims, `addC`, condition splits and `Rep` cases, and it
  closes each path's cost with `omega`. Groups of recursive functions are
  proved by induction on fuel.

Decided 11-02 (F14), regenerating against F11b's `qstmt`/`qloop`/`qpop`
and extending the certificates to every function that `front_end_words`,
`grammar` and `compile_words` reach:

- A function that reaches neither `boxed`, `plus` nor `times` (and none of
  its callees do) is not proved step by step either (`BudgetFree.lean`).
  Its run of `progW` is the self program's at cost 0 for a syntactic
  reason: its body calls only such functions (`SrcStmt.callsOk`), and
  `qstmt_z` carries "same value, cost 0" (`ZLe`) through any body whose
  calls have it. The set is the bits of one number, `GenB.SelfBFree.freeMask`
  (the functions and the unboxed prims they call), and `freeCheck` checks
  the whole self program against it once, by `decide +kernel` (11 s). Each
  such function's certificate is then `bfree` plus its `SelfCert`
  certificate, with no stepping. The set's soundness does not depend on the
  generator: a wrong bit fails the kernel's check. 838 of the 2,244
  functions take this path: 537 that were proved step by step, `is_link` (a
  70-operand `||` chain, 2m46) among them, and 301 argument-free ones that
  were evaluated by `bclosed`. 54 costly argument-free builders keep
  `bclosed`; 1,352 are proved by `budget`.
- The tactic runs `qpop` (a `let`'s body) by rules that move it inside
  `qthen`, `addC`, `bind` and `ite`, and looks through it for the call a
  run waits on.
- No BitVec literal reductions in the tactic's simp set: they turned
  `u64`/`i32` literals into forms `Rep` lemmas do not match. A shift by a
  constant leaves a closed `Nat` comparison (`(8#32).toNat < 32`), which
  two simprocs decide (`closedNatLt`, and `closedNatEq` for small terms).
- Budgets are generalized (`B - c` to a fresh `bud`) as each cost is taken
  off, so terms do not grow along a path. A boxed call `addC m` with
  `m > 1` steps one block at a time.
- Before `omega`, duplicate costs of one call made twice are merged
  (`mergeCosts`), as are duplicate case splits (`mergeCases`); `omega` runs
  on a goal with only the cost facts (`omegaAlone`), since with ~100
  hypotheses in context it took minutes on `host_read_code`.
- The models share an `if`'s branches through `let` when a lazy `&&`/`||`
  condition would copy them (`Pre_let_first` 199 KB to under 20 KB), and the
  model modules elaborate with `Elab.async false`: asynchronous elaboration
  took one part 70 s instead of 10 s. Proof modules stay asynchronous
  (15.7 s against 30 s).
- The generator's `/` was written as `%` (it compared against `divide`, the
  source says `quotient`); `frame_size` and `arg_base` exposed it.
- Speed (11-02, after `let_first` took 70 s and `stmt_of` 45 s). Three
  costs grew faster than the body:
  - Instantiating the metavariables of a whole proof at once (17 s of
    `let_first`). `budget` now works depth first and proves each case of a
    split on a fresh goal, assigned with its proof instantiated
    (`instantiateCase`). An auxiliary theorem per case did the same, but
    its kernel checks cost more than the one check of the whole.
  - `simp` over the whole run at every step. `qsimp` now simplifies a run's
    head only (`headPre`, a `simp` pre-method). For `qthen`, `bind` and
    `Out.qthen` it simplifies the first argument, for an `if` the condition,
    and for the goal's `∧` its left side; then it tries the rules at the
    node. A continuation is simplified when it becomes the head.
  - Building `qsimp`'s simp context, with `qstmt`'s and the others'
    equations, at every call (16 ms). It is made once per module
    (`qsimpCache`).
  A call's runs (`hc`, `hq`) are cleared once used. `let_first` went from
  70 s to about 25 s of one thread, and `SelfBProof53` from 112 s to 69 s.
  The proof modules are now cut by estimated work, not by characters:
  `proof_work` is about `(body length / 1000) ^ 1.5` seconds, and each
  module holds up to 30 of them. That gives 74 modules, with the few
  25-35 s certificates (`let_first`, `for_of`, `SrcStmt_lower`,
  `stmt_of`) about alone. A module takes 15-20 s alone (`SelfBProof3`:
  16 s on 11-02, with other agents loading the machine).

Decided 11-02 (F14, proving the roots' preconditions): a cost model whose
fuel runs out costs `2 ^ 64`, not 0 (`Cost_F 0 x = 18446744073709551616`,
the numeral, since Lean unfolds `2 ^ 64` one step at a time).
- Why: `Pre_F n` follows a call of `G` with its cost at fuel `n`. Where a
  list is bounded only by the blocks that built it (the monomorphizer's
  instances, the compiler's code), the bound a later `plus` needs is "`G`'s
  result is at most its arguments and `Cost_G n y`". With `Cost_G 0 = 0`
  that fails wherever fuel `n` is too small for `G`: the Lean value is
  whole and the cost cut short, so `Pre_F N` need not follow from Lean
  facts at all. With `2 ^ 64`, a cut-short cost is above any budget, so
  what follows the call in `Pre_F` is vacuous, and the bound only has to
  hold where `Cost_G n y < 2 ^ 64`.
- The certificates do not change: a run at fuel 0 has no value, so they
  never use `Cost_F 0`. `bfree`'s functions have no cost model (their cost
  is 0 at every fuel), and `bclosed` evaluates its model at the fuel `D`
  the run needs, where no model is at fuel 0; both still hold as they were.
- Proofs about the preconditions should not `match` on a fuel while a
  hypothesis mentions a cost at it (Lean then reduces `Cost_G 0 ..` with
  the numeral and runs out of recursion depth): the guards' hypotheses are
  cleared first (`SelfPre/Validate.lean`).

## One-word scalar views (decided 11-01, F11b)

The other one-word scalars the stdlib oracle passes as slices, `u32`,
`u64`, `i64` and `bool`, are word views like `u16` ("`u16` views"):
laniusc's `stdlib/core/mem.lani` packs only `i32` and `u8`, and lays every
other element out as descending 8-byte words. Core takes them where it takes
a `u16` view: `rawSliceElementAddress?` puts element `i` at `pointer - 8 *
i`, `mapRawNominalSlice` checks the view's words in one live block,
`NativeLayout.elementStride?` is -8 and a slice of one is 3 words.
Elements are read and written as the scalar is elsewhere in native layout
(`readNativeValue`, `writeNativeValue`): `u32` and `bool` as the word's low
4 bytes (a `bool` above 1 is `typeMismatch`), `u64` and `i64` as all 8.
`typedSliceFromRawParts` types them (`RawNominalSliceElement.word32`,
`word64`, `signed64`, `boolean`). As for struct fields, Core writes a
`u32` or `bool` element as 4 bytes where laniusc writes the zero-extended
word; the upper 4 bytes are never read as part of the element.

The verified compiler takes them on its word path. `word_element` in
`lani/mini/compiler.lani` accepts `u16`, `u32`, `u64`, `i64` (the source
type `Sint(Uint64)`) and `bool`, so `slice_from_raw_parts`, `slice[i]`, the
store `slice[i] = v` and `slice_stride` of such a view lower as they do for
a struct or `u16` element. `Lanius/Mini/WordScalar.lean` names the five
(`SrcType.WordScalar`, `CoreWordScalar`). The read, store and stride proofs
(`ElementLayout`, `LowerStmt`, `LowerStops`, `LowerEval`, `TypeSound` and
the Faithful raw-view modules) take that predicate where they took `u16`.
Borrowed slices of a caller's array still hold only `i32` and `u8`.

## laniusc's process exit is `exit_group`; the verified compiler's stays `exit` (decided 11-01)

laniusc's x86 runtime now ends a process with Linux syscall 231,
`exit_group`, instead of 60, `exit`. This covers the `exit` service
(`std::process::exit`) and allocation failure
(`shaders/codegen/lir/x86/runtime_abi.slang`), the inline exits of failed
safety guards such as bounds checks, status 101 (`emit_exit` in
`safety_emit.slang`), and the static entry wrapper's exit after `main`
(`emit.slang`).
With `std::pthread`, `exit` ended only the calling thread. A worker that
failed a bounds check vanished, `pthread_join` returned, and `main` went on
to exit 0 (`tests/fixtures/stdlib_execution/concurrency/thread_exit.lani`).
The native-link CRT bridge returns into glibc, whose `exit` already uses
`exit_group`, so it is unchanged.

The verified compiler keeps `mov eax, 60; syscall` (`lani/mini/compiler.lani`'s
entry, `Lanius/Mini/Process.lean`'s `Exits`, `exit_steps` and the start bytes
`[72, 137, 199, 184, 60, 0, 0, 0, 15, 5]`). Its programs have one thread:
it emits no C entries and links no pthread. For a one-thread process, `exit`
and `exit_group` end the same process with the same status, so `Exits` is
exact for every program it compiles. Switching it would change the self
source, the process theorems and the self-hosting fixpoint for no
observable difference. It should switch when the verified compiler admits
threads. The change is the byte 60 -> 231 in the entry and the immediate
in `Exits.number` and `exit_steps`.
