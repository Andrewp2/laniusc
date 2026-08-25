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
  unsigned right shift is logical.
- `f32` and `f64` values are represented by their IEEE bit patterns. Arithmetic
  and ordered comparisons use Lean's `Float32` and `Float` operations, so
  division by zero and NaNs follow floating-point behavior rather than integer
  traps.
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
  misclassified as an unknown external function. A successful nonnegative
  millisecond sleep advances monotonic and system clocks with nanosecond carry
  and advances the whole-second compatibility clock. A negative sleep returns
  `-1` without advancing time.
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

## Decisions still required

- Which NaN payload details are observable through future bit-conversion APIs.
  Literal parsing/rounding is already explicit, and resolved numeric casts are
  explicit in core and width-correct dynamically.
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
