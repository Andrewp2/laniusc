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

### `x<` in an expression (decided 10-29)

The grammar gives `a < b > (c)` two trees: a chain of comparisons and a call
of the generic path `a<b>`. Lanius reads `x<` in an expression as the start
of type arguments exactly when, from the `<` on, the matching `>` (angles
counted outside brackets, a `>>` closing two) comes before any bracket
closes or a `;`, no `||`, `==`, `!=`, `<=` or `>=` comes before it, and `(`,
`::` or `{` follows it; otherwise `<` is a comparison. This is laniusc's rule
(`shaders/parser/tokens/to/angle_kinds.slang`) without its limit of 64
argument tokens; the verified compiler's validator checks it (`picks`).
A method's type arguments (`x.f<T>(..)`) are outside the verified
compiler's subset, since they are ambiguous in the same way (`x.f < a >
(b)`). A statement that begins with `{` is a block statement, never an
expression statement (decided 10-30, F4), as in Rust: `{ a } - b;` is the
block `{ a }` and then `-b;`. Its lets scope over the block only
(`StmtR.block`). With these, every token sequence has at most one parse
tree (V4, `Mini/ParseUnique.lean`; `pickedPair` in `Mini/Unique.lean` lists
the two pairs of productions `picks` tells apart).

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
- Not yet: an array passed where a slice is
  expected (Core's coercion of `[T; N]` to `[T]`), `for` over an array,
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
2. **Addressed bindings.** A local is addressed when the program takes its
   address: an array local passed where a slice is expected (later `&x`
   and `&self`). Its slot holds its frame address, and its value lives in
   frame memory in the raw-slice element layout (`ElementLayout`: an `i32`
   in 4 bytes, a word type in 8 bytes a word), so a slice of it is the
   same (pointer, length) pair as a raw slice and the callee runs the code
   it runs for a raw slice. Element reads and writes of the local itself
   are loads and stores at its address.
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
   slice. Other coercions are rejected.
5. **`i32_array_data_ptr` uses the heap, not frame memory.** Core maps the
   array into a fresh heap block at `nextAddress` (`mapI32ArrayView`) and
   keeps block and cell equal from then on (`syncI32Views*`), and the
   pointer's value is observable (host calls take it). The verified
   compiler does the same: it bump-allocates the block, copies the
   elements, and from then on the array local is addressed at that heap
   address. The proofs' invariant "Core has no views" (`Grows`) becomes
   "every view's block holds its cell".
6. **`str`** is (pointer, length) of read-only bytes in a static region
   above frame memory, a literal's bytes placed by the loader (Core's
   `.string` value names no address, so any region outside Core's heap
   will do).

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
  `slice_from_raw_parts`, `slice_stride` and `assert` (`builtinPaths`) are
  never read as a function or variant.
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
  result lands in `target`. `Syscall.write`, `Syscall.read` and `Syscall.poll` exist.
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
- **Not yet modeled (deferred).** `getrandom`/`secure_u32`, process
  arguments and environment variables (the loader would have to place
  `argv`/`envp`, now arbitrary memory), clock reads (`clock_gettime`; sleeping is done, "Host sleep"),
  files, sockets and processes, the general `syscall6`, the allocator
  externs (the verified compiler's `alloc` is the mini bump allocator over
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
  most `maxTransfer` delivers `input.take count` at `address` (`writeAll`)
  and drops count bytes, returning how many came; the delivered range must
  lie in the heap (nothing is checked when no byte comes). The x86 code is
  `sysSpec` with `mov eax, 0` (`Syscall.linux`), the kernel's `read`
  (TRUSTED_BASE.md section 8).
- **`read_stdin(ptr, len)` (host id 2^32 + 3).** Core's meaning
  (`World.call .readStdin`): store `standardInput.take len` from `ptr`
  (trapping where Core's store traps), drop that many, return the count as
  `i32` (wrapped, as Core's `i32Result` is). The front end reads the
  stdlib's `extern "lanius_std" fn read_stdin` as the host call
  (`hostExtern`, case `host_read`). The verified compiler lowers it to a
  loop (`host_read_code`): a chunk of at most `maxTransfer` bytes, read;
  pointer, count and total moved past what came; and the loop ends when a
  read comes back short, since the input is then used up. Proved against
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
  the world's clocks advanced by `ms` (`afterSleepMs`). laniusc's runtime
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
- **The clocks are not observed.** Neither the mini heap nor the x86 model
  has a clock, and `HeapCorr` does not mention Core's clocks
  (`HeapCorr.sleep`), so the proof (`LowerEval.host_sleep`) is about the
  result and the rest of the world only. Reading a clock
  (`monotonic_read`, `system_read`) would need Core's clock to be a stream
  of readings given before the run, like standard input, and is not done.
- **The oracle sleeps briefly.** A stdlib function's `milliseconds: i32`
  parameter gets small or negative counts (`SLEEP_MS`), so that calls end
  well inside the two-second timeout; gate step `stdlib-time` compares
  `std::time_checked::sleep_nonnegative_ms` with laniusc.

## `for` over a range (decided 10-30, F4)

`for x in a..n { body }`, with `a` an integer literal and `n` a local, is
read as `let c = a; let e = n; while (c < e) { let x = c; c = c + 1; body }`
(`for_of`, `StmtR.forRange`), so that:

- `n` is read once, before the loop, as Rust evaluates a range once;
  assigning `n` in the body does not change the iterations;
- `x` is a fresh local each iteration, and `c` moves on before the body, so a
  `continue` goes to the next value; `c + 1` cannot overflow, as `c < e`;
- `x`, `c` and `e` have `n`'s type, and the literal `a` takes it.

This agrees with Core's own `forRange` (`Semantics.lean`), which evaluates
the bound once, on `i32`, the one type Core's loop takes.

`c` and `e` are hidden locals: they have no name in scope, and they are
numbered by the `for` token and `x`'s token, and `x` by the `in` token, so the
locals are numbered in the order the desugared text declares them and the
front end's cases can write the desugaring as the expected reading.

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
`!`, `slice_stride`, or a local or field (`inferred`). A bare literal, an
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
item. Two deliberate differences, both on programs laniusc rejects: an item
import also beats a declaration of the same name in `m` (laniusc reports a
clash), and a module with no declarations counts as no module. Module
imports still bring only variants into scope by their bare names.
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
