import verified_compiler.tests.direct_ir_owned_inputs
import verified_compiler.tests.direct_ir_body_production_event_store_tests
import verified_compiler.tests.direct_ir_body_production

namespace IRBodyOwnedLoweringTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRBodyOwnedInputs IRBodyProductionInputs IRTypeRefProof

private def word (number : Int) := i32Bytes number ++ List.replicate 4 165
private def tag (value : Value) : List UInt8 := match value with
  | .enumeration _ ordinal _ => encodeNatLE 4 ordinal ++ List.replicate 4 165
  | _ => []
private def node (production first count : Int) :=
  word production ++ word 0 ++ word 6 ++ word first ++ word count
private def child (kind : ChildKind) (payload : Int) :=
  tag (childKindValue kind) ++ word payload ++ word 0
private def nodeBytes :=
  node 74 15 0 ++ node 91 15 0 ++ node 76 13 2 ++ node 73 11 2 ++ node 12 9 2 ++ node 11 0 9
private def childBytes := (List.range 15).reverse.flatMap fun index => match index with
  | 8 => child .StateChild 1 | 10 => child .StateChild 2
  | 11 => child .StateChild 3 | 12 => child .StateChild 5
  | 13 => child .TokenChild 0 | 14 => child .StateChild 4
  | _ => child .NoChild 0
private def tokenBytes := tag (source_value Extracted.«verified::token».Types.«TokenKind».«ReturnKeyword» []) ++
  word 0 ++ word 6
private def signatureBytes (id : Int) := word id ++ tag functionKind ++ tag internalShape ++ word 0 ++
  tag (referenceValue .Void) ++ List.replicate 8 165 ++ word 0 ++ word 0 ++ word 0

-- Four original rows: two owned functions, one external, one other owner.
-- Core ID order differs from physical row order; the index is supplied as
-- original coherent bytes, not obtained from the index builder or valid flag.
private def rowBytes (unit : Int) (kind : DeclarationKind) (id : Int) :=
  word unit ++ tag (kindValue kind) ++ word 0 ++ word 0 ++ word 0 ++ word 0 ++ word 0 ++ word 0 ++
  word id ++ word id
private def allocationBytes :=
  word 0 ++ word 4 ++ List.replicate 56 0 ++
  rowBytes 0 .Function 0 ++ rowBytes 0 .External 44 ++
  rowBytes 1 .Function 1 ++ rowBytes 0 .Function 2
private def indexBytes := word 3 ++ word 3 ++ word 2 ++ word 2 ++ word 0 ++ word 0
private def indexEntryType : Ty := match source_value Extracted.«lowering::allocation».Types.«IndexEntry».mk [] with
  | .structure id _ => .structure id | _ => .unit
private def bindingType : Ty := match source_value Extracted.«lowering::value_catalog».Types.«ValueBinding».mk [] with
  | .structure id _ => .structure id | _ => .unit
private def bindingBytes (scope : Nat) (id : Int) :=
  word 0 ++ encodeNatLE 4 scope ++ List.replicate 4 165 ++
  encodeNatLE 4 1 ++ List.replicate 4 165 ++ word id ++ List.replicate 16 165
private def valuesBytes (order : Nat) :=
  if order == 1 then bindingBytes 2 2 ++ bindingBytes 1 0
  else bindingBytes 1 0 ++ bindingBytes 2 2
private def previousEventBytes := tag (IRBodyProductionProof.returnEvent false) ++ List.replicate 32 165
private def previousTypeBytes := tag (referenceValue .Invalid) ++ List.replicate 8 165
private def previousTree := IRValidatorProof.treeValue
  (.rawSlice IREventStoreProof.eventType 800 1)
  (.rawSlice IREventStoreProof.referenceType 832 1) true
  (.rawSlice (.scalar (.signed .i32)) 840 1) 1
private def previousValue (duplicate : Bool) := IRCatalogStoreProof.body
  (IRCatalogStoreProof.signature (if duplicate then 0 else 40) 0 .Void) previousTree
private def previousBytes (duplicate : Bool) := word (if duplicate then 0 else 40) ++
  tag (referenceValue .Void) ++ List.replicate 8 165 ++ word 0 ++
  encodeNatLE 8 800 ++ encodeNatLE 8 1 ++ encodeNatLE 8 832 ++ encodeNatLE 8 1 ++
  encodeNatLE 4 1 ++ List.replicate 4 165 ++ encodeNatLE 8 840 ++ encodeNatLE 8 1 ++ word 1
private def catalog (capacity : Nat) : IRCatalogConstructionProof.Catalog :=
  { memory := 5120, capacity := Int32.ofNat capacity }
private def catalogBytes (capacity : Nat) (duplicate : Bool) :=
  word 1 ++ List.replicate ((capacity - 1) * 96) 165 ++ previousBytes duplicate

private def readonlyBlocks (missing : Bool) (order : Nat) : List Block := [
  { base := 128, size := 392, alignment := 8, bytes := allocationBytes, owned := true },
  { base := 640, size := 48, alignment := 8, bytes := indexBytes },
  { base := 768, size := 40, alignment := 8, bytes := previousEventBytes },
  { base := 824, size := 16, alignment := 8, bytes := previousTypeBytes },
  { base := 840, size := 4, alignment := 4, bytes := i32Bytes 1 },
  { base := 1024, size := 24, alignment := 4, bytes := "return".toList.flatMap fun c => i32Bytes c.toNat },
  { base := 2048, size := 240, alignment := 8, bytes := nodeBytes },
  { base := 3072, size := 360, alignment := 8, bytes := childBytes },
  { base := 4096, size := 24, alignment := 8, bytes := tokenBytes },
  { base := 4608, size := 216, alignment := 8,
    bytes := signatureBytes (if missing then 99 else 2) ++ signatureBytes 1 ++ signatureBytes 0 },
  { base := 6400, size := 96, alignment := 8, bytes := valuesBytes order }]
private def before (budget capacity : Nat) (missing duplicate : Bool) (order : Nat) : State := {
  IRBodyProductionEventStoreTests.original with
  heap := {
    blocks := IRBodyProductionEventStoreTests.original.heap.blocks ++ readonlyBlocks missing order ++ [
      { base := 5120, size := (catalog capacity).bytes, alignment := 8, bytes := catalogBytes capacity duplicate }]
    nextAddress := 8192, remaining := some budget }
  world := { standardOutput := [88], standardError := [89] } }

private def tree : Tree := {
  nodes := 2280, children := 3424, nodesLength := 6, childrenLength := 15,
  nodeCount := 6, childCount := 15,
  nodesBound := by decide, childrenBound := by decide, nodesFit := by decide, childrenFit := by decide }
private def table : AllocationTable := { memory := 128, count := 4 }
private def index : Value := source_value Extracted.«lowering::allocation».Types.«Index».mk
  [table.value, .rawSlice indexEntryType 680 3, .rawSlice (.scalar (.signed .i32)) 0 0,
    .signed .i32 0, .signed .i32 3, .boolean true]
private def signatures : Value := source_value Extracted.«lowering::signature_index».Types.«Table».mk
  [.rawSlice signatureType 4816 3, .signed .i32 3,
    .unit, .signed .i32 0, .unit, .signed .i32 0, .unit, .signed .i32 0,
    .unit, .signed .i32 0, .unit, .signed .i32 0]
private def values (order : Nat) : Value := source_value Extracted.«lowering::value_catalog».Types.«ValueTable».mk
  [.rawSlice bindingType (if order == 0 then 0 else 6488) (if order == 0 then 0 else 2),
    .signed .i32 (if order == 0 then 0 else 2)]
private def inputs (owner : Int) (order : Nat) : Value :=
  source_value Extracted.«lowering::body_context».Types.«BodyLoweringInputs».mk [
    .signed .i32 owner,
    source_value Extracted.«lowering::body_context».Types.«WordRegion».mk
      [.rawSlice (.scalar (.signed .i32)) 1024 6, .signed .i32 6],
    source_value Extracted.«verified::token».Types.«TokenTable».mk
      [.rawSlice tokenType 4112 1, .signed .i32 1, .pointer 0],
    tree.value, index, signatures, .unit, .unit, values order,
    .unit, .unit, .unit, .unit, .unit, .unit]
private def workspace (enabled : Bool) (capacity : Nat) : Workspace := {
  expressionData := .unit, expressionCount := .unit, expressionCapacity := 1,
  codes := .unit, depths := .unit,
  types := source_value Extracted.«verified::surface_type».Types.«TypeArena».mk [.unit, .unit, .signed .i32 1],
  aliasScratch := .unit, aliasCapacity := 0,
  typeOutput := source_value Extracted.«lowering::types».Types.«Results».mk [.unit, .signed .i32 1],
  events := (IRBodyProductionEventStoreTests.input enabled).value, catalog := (catalog capacity).value }

private def call (enabled : Bool) (capacity : Nat) (owner : Int) (order : Nat) : Expr :=
  .call Extracted.«lowering::bodies».Functions.«lower_owned».core.id
    [.value (inputs owner order), .value (workspace enabled capacity).value]

private def replace (value : Value) (field : Nat) (replacement : Value) : Value := match value with
  | .structure id fields => .structure id (fields.set field replacement)
  | _ => value
private def metadata (heap : Heap) := heap.blocks.map fun block =>
  (block.base, block.size, block.alignment, block.live, block.owned, block.bytes)

-- Five pre-native failures have no header backing at all. Later entry guards
-- have just the reached 72-byte header, not its claimed rows or body storage.
private def earlyChecks : IO Unit := do
  let initial : State := { IRBodyProductionEventStoreTests.original with
    heap := { nextAddress := 8192, remaining := some 300 } }
  let sourceNegative := replace (inputs 0 0) 1
    (source_value Extracted.«lowering::body_context».Types.«WordRegion».mk [.unit, .signed .i32 (-1)])
  let tokensNegative := replace (inputs 0 0) 2
    (source_value Extracted.«verified::token».Types.«TokenTable».mk [.unit, .signed .i32 (-1), .pointer 0])
  let nodesZero := replace (inputs 0 0) 3 (replace tree.value 2 (.signed .i32 0))
  let tableNegative := replace (inputs 0 0) 4 (replace index 0 ({ table with count := -1 } : AllocationTable).value)
  for inputValue in [inputs (-2) 0, sourceNegative, tokensNegative, nodesZero, tableNegative] do
    let .done (.signed .i32 (-1)) after := evalExpr 1000 extractedProgram initial
        (.call Extracted.«lowering::bodies».Functions.«lower_owned».core.id
          [.value inputValue, .value (workspace false 6).value])
      | throw (IO.userError "pre-native owned guard trapped or accepted")
    unless metadata after.heap == metadata initial.heap && after.heap.remaining == initial.heap.remaining &&
        after.heap.nextAddress == initial.heap.nextAddress && after.world.calls.isEmpty &&
        after.locals == initial.locals && after.local? 9 == initial.local? 9 do
      throw (IO.userError "pre-native owned guard accessed absent backing or changed caller")
  let headerOnly : State := { initial with heap := {
    blocks := [{ base := 128, size := 72, alignment := 8, bytes := allocationBytes.take 72, owned := true }]
    nextAddress := initial.heap.nextAddress, remaining := initial.heap.remaining } }
  let zeroSignatures := replace (inputs 0 0) 5 (replace signatures 1 (.signed .i32 0))
  let negativeValues := replace (inputs 0 0) 8 (replace (values 0) 1 (.signed .i32 (-1)))
  let base := (workspace false 6).value
  let zeroExpression := replace base 0 (replace (workspace false 6).arena 2 (.signed .i32 0))
  let zeroTypes := replace base 3 (replace (workspace false 6).types 2 (.signed .i32 0))
  let zeroInference := replace base 5 (replace (workspace false 6).typeOutput 1 (.signed .i32 0))
  for (inputValue, outputValue) in [(zeroSignatures, base), (negativeValues, base),
      (inputs 0 0, zeroExpression), (inputs 0 0, zeroTypes), (inputs 0 0, zeroInference)] do
    let .done (.signed .i32 (-1)) after := evalExpr 1000 extractedProgram headerOnly
        (.call Extracted.«lowering::bodies».Functions.«lower_owned».core.id
          [.value inputValue, .value outputValue])
      | throw (IO.userError "header-reached owned guard trapped or accepted")
    unless metadata after.heap == metadata (headerOnly.heap.borrowBlock 128) &&
        after.heap.remaining == headerOnly.heap.remaining && after.heap.nextAddress == headerOnly.heap.nextAddress &&
        after.world.calls.isEmpty && after.locals == headerOnly.locals && after.local? 9 == headerOnly.local? 9 do
      throw (IO.userError "header-reached rejection lost borrow or read unused row/body/annotation backing")

-- Direct calls isolate semantic validation from owner filtering and append
-- failures. The row/index/binding bytes are original inputs, not outputs of
-- an index builder or a previously successful validator.
private def validatorCheck (initial : State) (tableValue indexValue : Value)
    (offset count tokenCount : Int) (expected : Bool) (borrowed : Bool := false) : IO Unit := do
  let .done (.boolean answer) after := evalExpr 10000 extractedProgram initial
      (.call Extracted.«lowering::value_catalog».Functions.«valid_slice».core.id
        [.value tableValue, .value (.signed .i32 offset), .value (.signed .i32 count),
          .value (.signed .i32 tokenCount), .value indexValue])
    | throw (IO.userError "original-byte valid_slice trapped")
  unless answer == expected do
    throw (IO.userError s!"original-byte validator answer mismatch offset={offset} count={count}")
  let expectedHeap := if borrowed then initial.heap.borrowBlock 128 else initial.heap
  unless metadata after.heap == metadata expectedHeap && after.heap.remaining == initial.heap.remaining &&
      after.heap.nextAddress == initial.heap.nextAddress && after.locals == initial.locals &&
      after.local? 9 == initial.local? 9 && after.world.calls == initial.world.calls &&
      after.world.standardOutput == initial.world.standardOutput &&
      after.world.standardError == initial.world.standardError && after.i32ArrayViews.isEmpty do
    throw (IO.userError s!"validation lost original bytes, exact borrow, caller or allocation state offset={offset} count={count}")

private def validatorChecks : IO Unit := do
  let initial := before 300 6 false false 1
  let bare : State := { initial with heap := { nextAddress := 8192, remaining := some 300 } }
  validatorCheck bare (values 0) index 0 0 0 true
  validatorCheck bare (replace (values 0) 1 (.signed .i32 (-1))) index 0 0 0 false
  validatorCheck bare (values 0) (replace index 5 (.boolean false)) 0 0 0 false
  validatorCheck bare (values 0) index 0 0 (-1) false
  -- Reached original allocation queries borrow their actual table block;
  -- bytes are retained, but the initially owned flag is not a heap identity.
  validatorCheck initial (values 1) index 0 2 1 true (borrowed := true)
  validatorCheck initial (values 1) index 0 1 1 true (borrowed := true) -- legitimate target ID zero
  validatorCheck (before 300 6 false false 2) (values 2) index 0 2 1 false (borrowed := true)
  -- Ordering is local to the requested span: no previous row outside offset.
  validatorCheck (before 300 6 false false 2) (values 2) index 1 1 1 true (borrowed := true)
  let altered (base : Nat) (bytes : List UInt8) : State := { initial with
    heap := { initial.heap with blocks := initial.heap.blocks.map fun block =>
      if block.base == base then { block with bytes := bytes } else block } }
  validatorCheck (altered 6400 (bindingBytes 1 2 ++ bindingBytes 1 0)) (values 1) index 0 2 1 false (borrowed := true)
  validatorCheck (altered 6400 (bindingBytes 2 2 ++ bindingBytes 2 0)) (values 1) index 0 2 1 false (borrowed := true)
  validatorCheck (altered 640 (word 3 ++ word 3 ++ word 2 ++ word 2 ++ word 1 ++ word 1))
    (values 1) index 0 1 1 false (borrowed := true) -- represented slot selects a mismatching row ID
  let enumBytes := word 0 ++ word 4 ++ List.replicate 56 0 ++
    rowBytes 0 .Enumeration 0 ++ rowBytes 0 .External 44 ++ rowBytes 1 .Function 1 ++ rowBytes 0 .Function 2
  validatorCheck (altered 128 enumBytes)
    (values 1) index 0 1 1 false (borrowed := true) -- callable target with a non-callable row kind
  for (ordinal, fields, expected) in [(-1, 0, false), (0, -1, false), (999, 999, true)] do
    let variant := word 0 ++ encodeNatLE 4 1 ++ List.replicate 4 165 ++
      encodeNatLE 4 2 ++ List.replicate 4 165 ++ word 0 ++ word ordinal ++ word fields
    let variantState := altered 6400 (bindingBytes 2 2 ++ variant)
    let represented := { variantState with heap := { variantState.heap with
      blocks := variantState.heap.blocks.map fun block =>
        if block.base == 128 then { block with bytes := enumBytes } else block } }
    -- This validator checks sign, ID and kind, not index-builder uniqueness
    -- or a new declaration arity/ordinal coherence assumption.
    validatorCheck represented (values 1) index 0 1 1 expected (borrowed := expected)
  let .done (.boolean true) wholeAfter := evalExpr 10000 extractedProgram initial
      (.call Extracted.«lowering::value_catalog».Functions.«valid».core.id
        [.value (values 1), .value (.signed .i32 1), .value index])
    | throw (IO.userError "whole value validator did not consume the original valid span")
  unless metadata wholeAfter.heap == metadata (initial.heap.borrowBlock 128) && wholeAfter.locals == initial.locals &&
      wholeAfter.local? 9 == initial.local? 9 && wholeAfter.world.calls == initial.world.calls do
    throw (IO.userError "whole value validator changed original bytes or caller")

private def occupiedBodyObserved (state : State) (capacity : Nat) (duplicate : Bool) : Bool :=
  (readRawSliceIndex extractedProgram state IRCatalogStoreProof.bodyType
    (5120 + (catalog capacity).length * 96) (catalog capacity).length 0).toOption ==
      some (previousValue duplicate) &&
  (readRawSliceIndex extractedProgram state IREventStoreProof.eventType 800 1 0).toOption ==
    some (IRBodyProductionProof.returnEvent false) &&
  (readRawSliceIndex extractedProgram state IREventStoreProof.referenceType 832 1 0).toOption ==
    some (referenceValue .Invalid) &&
  (readRawSliceIndex extractedProgram state (.scalar (.signed .i32)) 840 1 0).toOption ==
    some (.signed .i32 1)

-- Every case starts from independently supplied native bytes. Failures retain
-- earlier successful rows; no asserted validator or producer run is input.
private def check (enabled : Bool) (owner : Int) (order budget capacity : Nat)
    (missing duplicate : Bool) (expected : Int) (inserted attempts : Nat) : IO Unit := do
  let initial := before budget capacity missing duplicate order
  unless occupiedBodyObserved initial capacity duplicate do
    throw (IO.userError "owned fixture lacks its original represented occupied body")
  let .done result after := evalExpr 100000 extractedProgram initial (call enabled capacity owner order)
    | throw (IO.userError "owned multi-row lowering trapped")
  unless result == .signed .i32 expected do
    throw (IO.userError s!"owned result mismatch owner={owner} values={order} budget={budget}: {repr result}")
  unless (loadNatLE after.heap 5120 4).toOption == some (inserted + 1) do
    throw (IO.userError "owned lowering lost the ordered successful prefix count")
  unless (after.heap.loadBytes ((catalog capacity).rowBase 0) 96).toOption == some (previousBytes duplicate) do
    throw (IO.userError "owned lowering modified the initially occupied catalog row")
  unless occupiedBodyObserved after capacity duplicate do
    throw (IO.userError "owned lowering lost the initially represented payload, type or endpoint")
  for block in readonlyBlocks missing order do
    unless (after.heap.loadBytes block.base block.size).toOption == some block.bytes do
      throw (IO.userError "owned lowering modified original future input bytes")
  unless after.locals == initial.locals && after.local? 9 == initial.local? 9 &&
      after.world.standardOutput == initial.world.standardOutput &&
      after.world.standardError == initial.world.standardError && after.i32ArrayViews.isEmpty do
    throw (IO.userError "owned lowering changed caller/source stream observations")
  unless after.world.calls.length == attempts do
    throw (IO.userError s!"owned allocation attempt count mismatch: {after.world.calls.length} != {attempts}")
  -- Independent alignment/budget recurrence, including failed attempts. No
  -- evaluator/allocator result is used to predict this numerical ledger.
  let mut remaining := budget
  let mut frontier := 8192
  let mut blocks : List (Nat × Nat × Nat × Bool × Bool) := []
  for attempt in List.range attempts do
    let size := if attempt % 3 == 0 then 32 else if attempt % 3 == 1 then 56 else 4
    let alignment := if attempt % 3 == 2 then 4 else 8
    if size ≤ remaining then
      let base := frontier + (alignment - frontier % alignment) % alignment
      blocks := blocks ++ [(base, size, alignment, true, false)]
      remaining := remaining - size
      frontier := base + size
  unless after.heap.remaining == some remaining && after.heap.nextAddress == frontier &&
      (after.heap.blocks.filter (fun block => block.base ≥ 8192)).map
        (fun block => (block.base, block.size, block.alignment, block.live, block.owned)) == blocks do
    throw (IO.userError "owned lowering lost exact allocation metadata, remaining budget or frontier")
  for position in List.range inserted do
    let rowAddress := (catalog capacity).rowBase (position + 1)
    let .ok id := readNativeValue 64 extractedProgram after.heap (.scalar (.signed .i32)) rowAddress
      | throw (IO.userError "owned successful row ID unreadable")
    let wanted := if owner == 1 then 1 else if owner == -1 then position else position * 2
    unless id == .signed .i32 wanted do
      throw (IO.userError "owned successful rows were reordered or skipped")
    let .ok (.structure _ [_, .structure _ [events, types, .boolean true, ends, .signed .i32 1]]) :=
        readRawSliceIndex extractedProgram after IRCatalogStoreProof.bodyType
          (5120 + (catalog capacity).length * 96) (catalog capacity).length (position + 1)
      | throw (IO.userError "owned prefix lacks its native copied one-event tree")
    let .rawSlice eventType eventAddress 1 := events
      | throw (IO.userError "owned prefix event descriptor changed")
    let .rawSlice typeType typeAddress 1 := types
      | throw (IO.userError "owned prefix type descriptor changed")
    let .rawSlice endType endAddress 1 := ends
      | throw (IO.userError "owned prefix endpoint descriptor changed")
    unless (readRawSliceIndex extractedProgram after eventType eventAddress 1 0).toOption ==
        some (IRBodyProductionProof.returnEvent false) &&
        (readRawSliceIndex extractedProgram after typeType typeAddress 1 0).toOption ==
          some (IRTypeRefProof.referenceValue .Invalid) &&
        (readRawSliceIndex extractedProgram after endType endAddress 1 0).toOption == some (.signed .i32 1) do
      throw (IO.userError "owned prefix lost earlier native payload, annotation or endpoint")
  if !enabled then
    unless (after.heap.loadBytes 96 32).toOption ==
        some (IRBodyProductionEventStoreTests.typeBytes ++ IRBodyProductionEventStoreTests.typeBytes) do
      throw (IO.userError "disabled annotations wrote neighboring original type bytes")

#eval (do
  earlyChecks
  validatorChecks
  for enabled in [false, true] do
    check enabled 0 0 300 6 false false 2 2 6
    check enabled (-1) 0 300 6 false false 3 3 9
    check enabled 1 0 300 6 false false 1 1 3
    check enabled 0 1 300 6 false false 2 2 6
    check enabled 0 2 300 6 false false (-1) 0 0
    check enabled 0 0 300 6 true false (-1) 1 3
    check enabled (-1) 0 300 6 true false (-1) 2 6
    check enabled 0 0 300 6 false true (-1) 0 1
    check enabled 0 0 300 1 false false (-1) 0 1
    check enabled 0 0 300 2 false false (-1) 1 4
    check enabled 0 0 0 6 false false (-1) 0 1
    check enabled 0 0 32 6 false false (-1) 0 2
    check enabled 0 0 88 6 false false (-1) 0 3
    check enabled 0 0 124 6 false false (-1) 1 5
    check enabled 0 0 180 6 false false (-1) 1 6
  IO.println "owned original multi-row fixtures: filters, native bindings, first failure, occupied/full/duplicate/OOM, both annotation modes" : IO Unit)

end IRBodyOwnedLoweringTests
