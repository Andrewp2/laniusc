import verified_compiler.tests.direct_ir_negative_lowering
import verified_compiler.tests.direct_ir_body_production_event_store_tests
import verified_compiler.tests.direct_ir_body_production_main_outer
import verified_compiler.tests.direct_ir_body_production_scalar_arena
import verified_compiler.tests.direct_ir_body_production_main_stream
import verified_compiler.tests.direct_ir_catalog_construction_call
import verified_compiler.tests.direct_ir_body_production_main_domain
import verified_compiler.tests.direct_ir_body_production_inputs_signature
import Lanius.Semantics.NativeRecordStore
import Lanius.Semantics.NativeSliceStore
import Lanius.Memory.Read.Slice
import verified_compiler.tests.direct_ir_body_production

namespace IRBodyProductionScalarCapacityTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IREventStoreProof
open IRBodyProductionEventStoreTests
open IRBodyProductionInputs IRBodyProductionProof IRBodyProductionScalar IRTypeRefProof

-- Existing native event bytes are reused. Source and token descriptors have
-- spare physical capacity, while their independent logical counts stay small.
#eval (do
  let tokenKind := source_value Extracted.«verified::token».Types.«TokenKind».«Integer» []
  let ordinal := match tokenKind with | .enumeration _ ordinal _ => ordinal | _ => 0
  let tokenType := match source_value Extracted.«verified::token».Types.«TokenRow».mk [] with
    | .structure id _ => Ty.structure id | _ => .unit
  let cases : List (String × Bool × Int × Int) := [
    ("7", false, 1, 7), ("0_07", false, 1, 7),
    ("2147483647", false, 1, 2147483647),
    ("7", true, 2, 7), ("2147483648", true, 1, -2147483648)]
  for (text, negative, cursor, payload) in cases do
    let words := text.toList.map fun character => (character.toNat : Int)
    let sourceCapacity := words.length + 4
    let sourceBytes := (words ++ List.replicate 4 165).flatMap i32Bytes
    let row := encodeNatLE 4 ordinal ++ List.replicate 4 165 ++ i32Bytes 0 ++
      List.replicate 4 165 ++ i32Bytes words.length ++ List.replicate 4 165
    -- Index zero is the high-address native row; two spare rows lie below it.
    let tokenBytes := List.replicate 48 165 ++ row
    let storageBytes := List.replicate 16 91
    let before : State := { original with heap := {
      blocks := original.heap.blocks ++ [
        { base := 256, size := sourceBytes.length, alignment := 4, bytes := sourceBytes, owned := false },
        { base := 464, size := 72, alignment := 8, bytes := tokenBytes, owned := false },
        { base := 640, size := 16, alignment := 8, bytes := storageBytes, owned := false }]
      nextAddress := 656 } }
    let context := source_value Extracted.«lowering::body_context».Types.«BodyContext».mk
      [.rawSlice (.scalar (.signed .i32)) 256 sourceCapacity, .signed .i32 words.length,
        source_value Extracted.«verified::token».Types.«TokenTable».mk
          [.rawSlice tokenType 528 3, .signed .i32 1, .pointer 640], .signed .i32 1]
    let expression := if negative then
      Expr.call Extracted.«lowering::body_literal».Functions.«negative».core.id
        [.value context, .value (.signed .i32 0), .value (input false).value, .value (.signed .i32 0)]
      else Expr.call Extracted.«lowering::body_literal».Functions.«emit».core.id
        [.value context, .value (IRLiteralLoweringProof.integerNode 0),
          .value (input false).value, .value (.signed .i32 0)]
    let .done actual after := evalExpr 700 extractedProgram before expression
      | throw (IO.userError "spare-capacity native literal path trapped")
    unless actual == .signed .i32 cursor do
      throw (IO.userError "logical decoder count was confused with physical capacity")
    let expected := if cursor == 2 then IREventWriteProof.negateEvent else integer (BitVec.ofInt 32 payload)
    unless (readNativeValue 64 extractedProgram after.heap eventType 56).toOption == some expected do
      throw (IO.userError "native source token did not determine the emitted root")
    if cursor == 2 then
      unless (readNativeValue 64 extractedProgram after.heap eventType 16).toOption ==
          some (integer (BitVec.ofInt 32 payload)) do
        throw (IO.userError "negative literal did not retain its decoded child")
    unless (after.heap.loadBytes 256 sourceBytes.length).toOption == some sourceBytes &&
        (after.heap.loadBytes 464 72).toOption == some tokenBytes &&
        (after.heap.loadBytes 640 16).toOption == some storageBytes do
      throw (IO.userError "decoder changed source, spare token rows or nonzero TokenTable storage")
    unless (after.heap.loadBytes 96 32).toOption == (before.heap.loadBytes 96 32).toOption do
      throw (IO.userError "disabled literal touched annotation bytes")
    unless after.locals == before.locals && after.world.calls.isEmpty && after.i32ArrayViews.isEmpty do
      throw (IO.userError "native literal changed caller bindings or world/view frame")
    match after.local? 9 with
    | some (.signed .i32 91) => pure ()
    | _ => throw (IO.userError "payload decoding lost the caller cell")
  IO.println "actual scalar capacity fixtures: spare source/token capacity, nonzero storage and signed minimum passed" : IO Unit)

private def nativeWord (value : Int) : List UInt8 := i32Bytes value ++ List.replicate 4 165
private def nativeTag (value : Value) : List UInt8 := match value with
  | .enumeration _ ordinal _ => encodeNatLE 4 ordinal ++ List.replicate 4 165
  | _ => []
private def fullText (minimum : Bool) := if minimum then "return -2147483648" else "return true"
private def fullResult (minimum : Bool) : Reference := if minimum then .I32 else .Bool
private def fullChildCount (minimum : Bool) : Nat := if minimum then 19 else 17
private def fullTokenCount (minimum : Bool) : Nat := if minimum then 3 else 2
private def nativeNode (finish production first count : Int) : List UInt8 :=
  nativeWord production ++ nativeWord 0 ++ nativeWord finish ++ nativeWord first ++ nativeWord count
private def nativeChild (kind : ChildKind) (payload : Int) : List UInt8 :=
  nativeTag (childKindValue kind) ++ nativeWord payload ++ nativeWord 0

-- The same native topology reaches either a true literal or one minus whose
-- integer token is 2^31. Unused physical rows remain deliberately undecoded.
private def fullNodes (minimum : Bool) : List UInt8 :=
  let finish := (fullText minimum).toList.length
  let tail := fullChildCount minimum
  List.replicate 80 165 ++
    nativeNode finish (if minimum then 175 else 74) (if minimum then 18 else tail) (if minimum then 1 else 0) ++
    nativeNode finish (if minimum then 157 else 185) 16 (if minimum then 2 else 1) ++
    nativeNode finish 74 tail 0 ++ nativeNode finish 90 15 1 ++
    nativeNode finish 76 13 2 ++ nativeNode finish 73 11 2 ++
    nativeNode finish 12 9 2 ++ nativeNode finish 11 0 9
private def fullChildren (minimum : Bool) : List UInt8 :=
  (List.range 22).reverse.flatMap fun index => match index with
    | 8 => nativeChild .StateChild 1
    | 10 => nativeChild .StateChild 2
    | 11 => nativeChild .StateChild 3
    | 12 => nativeChild .StateChild 5
    | 13 => nativeChild .TokenChild 0
    | 14 => nativeChild .StateChild 4
    | 15 => nativeChild .StateChild 6
    | 16 => nativeChild .TokenChild 1
    | 17 => if minimum then nativeChild .StateChild 7 else nativeChild .NoChild 0
    | 18 => if minimum then nativeChild .TokenChild 2 else nativeChild .NoChild 0
    | _ => nativeChild .NoChild 0
private def nativeToken (kind : Value) (start finish : Int) : List UInt8 :=
  nativeTag kind ++ nativeWord start ++ nativeWord finish
private def fullTokens (minimum : Bool) : List UInt8 :=
  let returnToken := nativeToken (source_value Extracted.«verified::token».Types.«TokenKind».«ReturnKeyword» []) 0 6
  if minimum then List.replicate 48 165 ++
    nativeToken (source_value Extracted.«verified::token».Types.«TokenKind».«Integer» []) 8 18 ++
    nativeToken (source_value Extracted.«verified::token».Types.«TokenKind».«Minus» []) 7 8 ++ returnToken
  else List.replicate 72 165 ++
    nativeToken (source_value Extracted.«verified::token».Types.«TokenKind».«TrueKeyword» []) 7 11 ++ returnToken
private def fullSignature (minimum : Bool) : List UInt8 :=
  nativeWord 0 ++ nativeTag functionKind ++ nativeTag internalShape ++ nativeWord 0 ++
    nativeTag (referenceValue (fullResult minimum)) ++ List.replicate 8 165 ++
    nativeWord 0 ++ nativeWord 0 ++ nativeWord 0
private def fullInputs (minimum : Bool) : Inputs := {
  owner := 0
  source := .rawSlice (.scalar (.signed .i32)) 256 ((fullText minimum).toList.length + 4)
  sourceLength := (fullText minimum).toList.length
  tokens := .rawSlice IRBodyProductionInputs.tokenType 3184 5
  tokenCount := fullTokenCount minimum
  tokenStorage := 640
  tree := {
    nodes := 1416
    children := 2568
    nodesLength := 10
    childrenLength := 22
    nodeCount := 8
    childCount := fullChildCount minimum
    nodesBound := by decide
    childrenBound := by cases minimum <;> decide
    nodesFit := by decide
    childrenFit := by cases minimum <;> decide }
  allocationTable := .unit
  allocationTail := fun _ => .unit
  signature := {
    address := 4232
    length := 2
    count := 1
    id := 0
    result := fullResult minimum
    tail := fun _ => .unit
    starts := fun _ => .signed .i32 0
    inside := by decide
    bound := by decide
    fits := by decide }
  resolutions := .unit
  aliases := .unit
  values := .unit
  valueNames := .unit
  contexts := .unit
  sourceCatalog := .unit
  tokenCatalog := .unit
  globalDeclarations := .unit
  trees := .unit }
private def fullCatalog : IRCatalogConstructionProof.Catalog := { memory := 4608, capacity := 2 }
private def fullSourceBlocks (minimum : Bool) : List Block := [
  { base := 256, size := ((fullText minimum).toList.length + 4) * 4, alignment := 4,
    bytes := ((fullText minimum).toList.map (fun character => i32Bytes character.toNat)).flatten ++ List.replicate 16 165 },
  { base := 640, size := 16, alignment := 8, bytes := List.replicate 16 91 },
  { base := 1024, size := 400, alignment := 8, bytes := fullNodes minimum },
  { base := 2048, size := 528, alignment := 8, bytes := fullChildren minimum },
  { base := 3072, size := 120, alignment := 8, bytes := fullTokens minimum },
  { base := 4096, size := 144, alignment := 8, bytes := List.replicate 72 165 ++ fullSignature minimum }]
private def fullBefore (minimum : Bool) (budget : Nat) : State := { original with
  heap := {
    blocks := original.heap.blocks ++ fullSourceBlocks minimum ++ [
      { base := 768, size := 96, alignment := 8, bytes := List.replicate 96 165 },
      { base := 896, size := 8, alignment := 8, bytes := nativeWord 13 },
      { base := 912, size := 8, alignment := 4, bytes := i32Bytes 77 ++ i32Bytes 88 },
      { base := 928, size := 8, alignment := 4, bytes := i32Bytes 331 ++ i32Bytes 442 },
      { base := fullCatalog.memory, size := fullCatalog.bytes, alignment := 8,
        bytes := nativeWord 0 ++ List.replicate 192 165 }]
    nextAddress := 5120
    remaining := some budget }
  world := { standardOutput := [88], standardError := [89] } }
private def fullWorkspace (enabled : Bool) : Workspace := {
  expressionData := .rawSlice expressionNodeType 856 2
  expressionCount := .rawSlice (.structure expressionCountId) 896 1
  expressionCapacity := 2
  codes := .rawSlice (.scalar (.signed .i32)) 912 2
  depths := .rawSlice (.scalar (.signed .i32)) 928 2
  types := .unit
  aliasScratch := .unit
  aliasCapacity := 0
  typeOutput := .unit
  events := (input enabled).value
  catalog := fullCatalog.value }

#eval (do
  -- MIN uses two arena nodes but only one emitted expression event. The
  -- three failing budgets distinguish locals, copy and endpoint attempts.
  let cases : List (Bool × Nat × Int × Nat) := [
    (false, 176, 0, 3), (true, 200, 0, 3),
    (true, 79, -1, 1), (true, 191, -1, 2), (true, 199, -1, 3)]
  for enabled in [false, true] do
    for (minimum, budget, answer, attempts) in cases do
      let before := fullBefore minimum budget
      let arguments := fullInputs minimum
      let .done actual after := evalExpr 1800 extractedProgram before
          (producerCall arguments (fullWorkspace enabled) 0 8)
        | throw (IO.userError "original scalar full1179 path trapped")
      unless actual == .signed .i32 answer do
        throw (IO.userError "scalar full1179 returned the wrong success/resource outcome")
      for block in fullSourceBlocks minimum do
        unless (after.heap.loadBytes block.base block.size).toOption == some block.bytes do
          throw (IO.userError "scalar full1179 changed original source/token/tree/signature bytes")
      for cell in before.cells do
        unless after.cell? cell.id == cell.value do
          throw (IO.userError "scalar full1179 changed an original caller cell")
      unless after.locals == before.locals && after.i32ArrayViews.isEmpty &&
          after.world.standardOutput == before.world.standardOutput &&
          after.world.standardError == before.world.standardError &&
          after.world.calls == List.replicate attempts .alloc do
        throw (IO.userError "scalar full1179 lost its caller frame or exact attempted allocations")
      unless (after.heap.loadBytes 4608 4).toOption == some (i32Bytes (if answer = 0 then 1 else 0)) do
        throw (IO.userError "scalar full1179 corrupted the original catalog count")
      if attempts = 1 then
        unless after.heap.nextAddress == before.heap.nextAddress && after.heap.remaining == before.heap.remaining &&
            after.heap.blocks.map (fun block => (block.base, block.size, block.alignment, block.live, block.owned, block.bytes)) ==
              before.heap.blocks.map (fun block => (block.base, block.size, block.alignment, block.live, block.owned, block.bytes)) do
          throw (IO.userError "locals exhaustion changed the heap")
      else
        let arenaCount := if minimum then 2 else 1
        unless (after.heap.loadBytes 896 4).toOption == some (i32Bytes arenaCount) &&
            (after.heap.loadBytes 912 4).toOption == some (i32Bytes (typeCode arguments.signature.result)) do
          throw (IO.userError "actual scalar reset/inference retained old count13 or cached code77")
        unless (after.heap.loadBytes 900 4).toOption == some (List.replicate 4 165) do
          throw (IO.userError "scalar reset touched count-cell padding")
        if !minimum then
          unless (after.heap.loadBytes 768 48).toOption == (before.heap.loadBytes 768 48).toOption &&
              (after.heap.loadBytes 916 4).toOption == some (i32Bytes 88) &&
              (after.heap.loadBytes 932 4).toOption == some (i32Bytes 442) do
            throw (IO.userError "one-node Bool path read or changed unused arena/cache capacity")
      if !enabled then
        unless (after.heap.loadBytes 96 32).toOption == (before.heap.loadBytes 96 32).toOption do
          throw (IO.userError "disabled unreadable scalar descriptor changed annotation bytes")
      if answer = 0 then
        let localSize := if minimum then 80 else 56
        let copied := 5120 + localSize
        let ends := copied + 112
        let tree := IRValidatorProof.treeValue (.rawSlice eventType (copied + 72) 2)
          (.rawSlice referenceType (copied + 104) 2) true (.rawSlice (.scalar (.signed .i32)) ends 2) 2
        let stored := IRCatalogStoreProof.body (IRCatalogStoreProof.signature 0 0 arguments.signature.result) tree
        let literal := if minimum then integer (BitVec.ofInt 32 (-2147483648)) else IREventStoreProof.boolean true
        unless (readRawSliceIndex extractedProgram after IRCatalogStoreProof.bodyType
            (fullCatalog.memory + fullCatalog.length * 96) fullCatalog.length 0).toOption == some stored &&
            (readNativeValue 64 extractedProgram after.heap eventType (copied + 40)).toOption == some (returnEvent true) &&
            (readNativeValue 64 extractedProgram after.heap eventType copied).toOption == some literal &&
            (after.heap.loadBytes ends 8).toOption == some (i32Bytes 2 ++ i32Bytes 2) do
          throw (IO.userError "scalar full1179 did not copy the same Bool/MIN return body and subtree ends")
        unless (readRawSliceIndex extractedProgram after referenceType (copied + 104) 2 1).toOption ==
            some (referenceValue (if enabled then arguments.signature.result else .Invalid)) do
          throw (IO.userError "scalar full1179 lost selected/disabled copied annotations")
        unless after.heap.remaining == some 0 && after.heap.nextAddress == ends + 8 do
          throw (IO.userError "scalar full1179 lost sequential locals/copy/endpoint resource accounting")
      else if attempts = 2 then
        unless after.heap.remaining == some 111 && after.heap.nextAddress == 5200 do
          throw (IO.userError "first-copy exhaustion lost its successful locals allocation")
      else if attempts = 3 then
        unless after.heap.remaining == some 7 && after.heap.nextAddress == 5312 do
          throw (IO.userError "endpoint exhaustion lost its successful locals/copy allocations")
  IO.println "actual full scalar append_function: Bool/MIN, stale reset, disabled annotations and allocation failures passed" : IO Unit)

-- These witnesses concern the same original bytes as the full calls above.
-- No query, decoder, extraction or producer execution supplies a premise.
private theorem fullBudgetReads (minimum : Bool) (budget : Nat) :
    HeapReads (fullBefore minimum 0).heap (fullBefore minimum budget).heap := by
  intro pointer offset byte loaded
  exact loaded

private theorem scalarOkOfOption {result : Except errorType valueType}
    (same : result.toOption = some value) : result = .ok value := by
  cases result with
  | error reason => cases same
  | ok actual => exact congrArg Except.ok (Option.some.inj same)

private theorem scalarWord (heap : Heap) (number : Int) (lower : -(2 ^ 31) ≤ number)
    (upper : number < 2 ^ 31) (large : 4 ≤ size)
    (loaded : heap.loadBytes address 4 = .ok (i32Bytes number)) :
    NativeSnapshot (fuel + 1) extractedProgram heap (.scalar (.signed .i32))
      address (.signed .i32 number) size := by
  have represented : (BitVec.ofInt 32 number).toInt = number :=
    BitVec.toInt_ofInt_eq_self (by decide) lower upper
  simpa only [represented] using
    (NativeSnapshot.i32 (program := extractedProgram) (fuel := fuel)
      (BitVec.ofInt 32 number) (by simpa only [represented] using loaded)).enlarge large

private theorem scalarEmptySlice (heap : Heap)
    (supported : nativeSliceSupported extractedProgram element = true)
    (pointer : heap.loadBytes address 8 = .ok (encodeNatLE 8 0))
    (length : heap.loadBytes (address + 8) 8 = .ok (encodeNatLE 8 0)) :
    NativeSnapshot (fuel + 1) extractedProgram heap (.slice element)
      address (.rawSlice element 0 0) 16 := by
  intro other reads
  have pointer := reads _ _ _ (Nat.le_refl _) (by omega) pointer
  have length := reads (address + 8) 8 _ (by omega) (by omega) length
  simp only [readNativeValue]
  change (if !nativeSliceSupported extractedProgram element then .error .typeMismatch else do
      let pointer ← loadNatLE other address 8
      let length ← loadNatLE other (address + 8) 8
      pure (Value.rawSlice element pointer length)) = .ok (.rawSlice element 0 0)
  simp only [supported, Bool.not_true, Bool.false_eq_true, ↓reduceIte,
    loadNatLE_of_encoded pointer (by decide), loadNatLE_of_encoded length (by decide)]
  rfl

open Lean Meta Elab Tactic in
private def scalarFinite (index : TSyntax `ident) : Nat → TSyntax `tactic → TacticM (TSyntax `tactic)
  | 0, _ => `(tactic| ((try simp only [List.length_cons, List.length_nil] at *); omega))
  | count + 1, leaf => do
      let tail ← scalarFinite index count leaf
      `(tactic| cases $index:ident with | zero => $leaf:tactic | succ $index:ident => $tail:tactic)

open Lean Meta Elab Tactic in
elab "scalar_cases " index:ident count:num " => " leaf:tactic : tactic => do
  evalTactic (← scalarFinite index count.getNat leaf)

open Lean Meta Elab Tactic in
elab "scalar_fields " count:num " => " leaf:tactic : tactic => do
  let index := mkIdent (← mkFreshUserName `field)
  let bound := mkIdent (← mkFreshUserName `inside)
  let cases ← scalarFinite index count.getNat leaf
  evalTactic (← `(tactic| intro $index:ident $bound:ident; $cases:tactic))

open Lean Meta Elab Tactic in
elab "scalar_primitive" : tactic => withMainContext do
  let target ← instantiateMVars (← (← getMainGoal).getType)
  unless target.isAppOfArity ``NativeSnapshot 7 do throwError "native snapshot required"
  let value ← whnf target.getAppArgs[5]!
  if value.isAppOfArity ``Lanius.Core.Value.signed 2 then
    evalTactic (← `(tactic| apply scalarWord <;>
      first | exact scalarOkOfOption (by decide +kernel) | decide))
  else if value.isAppOfArity ``Lanius.Core.Value.enumeration 3 then
    evalTactic (← `(tactic| exact (NativeSnapshot.enumEmpty
      (by core_lookup) (by decide +kernel) (by decide)
      (scalarOkOfOption (by decide +kernel))).enlarge (by decide)))
  else if value.isAppOfArity ``Lanius.Core.Value.rawSlice 3 then
    evalTactic (← `(tactic| exact scalarEmptySlice _ (by decide +kernel)
      (scalarOkOfOption (by decide +kernel)) (scalarOkOfOption (by decide +kernel))))
  else throwError "original scalar primitive bytes required"

open Lean Elab Tactic in
elab "scalar_record " offsets:term ", " widths:term ", " count:num " => " leaf:tactic : tactic => do
  evalTactic (← `(tactic| apply NativeSnapshot.record
    (offset := fun index => (($offsets)[index]?).getD 0)
    (width := fun index => (($widths)[index]?).getD 0)))
  evalTactic (← `(tactic| next => core_lookup))
  evalTactic (← `(tactic| next => rfl))
  evalTactic (← `(tactic| next => scalar_fields $count => decide +kernel))
  evalTactic (← `(tactic| next => scalar_fields $count => first | decide | omega))
  evalTactic (← `(tactic| scalar_fields $count => $leaf:tactic))

macro "scalar_location" words:num : tactic => `(tactic|
  apply rawSliceElementAddress_of_layout (words := $words) rfl (by decide +kernel) (by decide) <;> decide)

private def fullProduction (minimum : Bool) : Nat → Int
  | 0 => 11 | 1 => 12 | 2 => 73 | 3 => 76 | 4 => 90 | 5 => 74
  | 6 => if minimum then 157 else 185 | _ => if minimum then 175 else 74
private def fullFirst (minimum : Bool) : Nat → Nat
  | 0 => 0 | 1 => 9 | 2 => 11 | 3 => 13 | 4 => 15 | 6 => 16
  | 7 => if minimum then 18 else fullChildCount minimum | _ => fullChildCount minimum
private def fullArity (minimum : Bool) : Nat → Nat
  | 0 => 9 | 1 | 2 | 3 => 2 | 4 => 1 | 6 => if minimum then 2 else 1
  | 7 => if minimum then 1 else 0 | _ => 0

/-- One symbolic row read supplies all five scalar fields. The surrounding
    buffer and every other row remain outside this record proof. -/
private theorem scalarNodeRow (heap : Heap) (address : Nat)
    (production finish : Int) (first count : Nat)
    (bounded : ∀ number ∈ [production, 0, finish, (first : Int), (count : Int)],
      -(2 ^ 31) ≤ number ∧ number < 2 ^ 31)
    (loaded : heap.loadBytes address 40 = .ok (nativeNode finish production first count)) :
    NativeSnapshot 64 extractedProgram heap nodeType address
      (nodeValue production 0 finish first count) 40 := by
  have wordLength : ∀ number, (i32Bytes number).length = 4 := by
    intro number
    simp only [i32Bytes, List.length_map, List.length_range]
  have word (offset : Nat) (number : Int)
      (range : -(2 ^ 31) ≤ number ∧ number < 2 ^ 31)
      (slice : ((nativeNode finish production first count).drop offset).take 4 = i32Bytes number) :
      NativeSnapshot 63 extractedProgram heap (.scalar (.signed .i32))
        (address + offset) (.signed .i32 number) 8 := by
    apply scalarWord heap number range.1 range.2 (by decide)
    simpa only [wordLength] using
      Heap.loadBytes_of_read_slice (start := offset) (bytes := i32Bytes number) loaded
        (by simpa only [wordLength] using slice)
  scalar_record [0, 8, 16, 24, 32], [8, 8, 8, 8, 8], 5 =>
    (apply word <;> first
      | exact bounded _ (by simp)
      | simp (disch := (simp only [List.length_append, List.length_replicate,
          List.length_nil, wordLength]; omega)) only
        [nativeNode, nativeWord, List.getElem?_cons_zero, List.getElem?_cons_succ,
          Option.getD_some, List.drop_append, List.drop_eq_nil_of_le,
          List.drop_zero, List.length_append, List.length_replicate, List.length_nil,
          wordLength, Nat.reduceAdd, Nat.reduceSub, List.nil_append, List.append_nil,
          List.take_append_of_le_length, List.take_of_length_le])

#print axioms scalarNodeRow

open Lean Meta Elab Tactic in
private partial def nodeRows (e : Lean.Expr) : MetaM (Array (Lean.Expr × Nat)) := do
  let e ← zetaReduce e
  if e.isAppOf ``HAppend.hAppend || e.isAppOf ``Append.append || e.isAppOf ``List.append then
    let args := e.getAppArgs
    return (← nodeRows args[args.size - 2]!) ++ (← nodeRows args.back!)
  if e.isAppOfArity ``nativeNode 4 then return #[(e, 40)]
  if e.isAppOfArity ``List.replicate 3 then
    let some length ← getNatValue? e.getAppArgs[1]! | throwError "closed padding length required"
    return #[(e, length)]
  if let some unfolded ← delta? e (fun name => name == ``fullNodes) then
    return ← nodeRows unfolded
  throwError "unsupported actual node row {e}"

open Lean Meta Elab Tactic in
private def nodeAppend (chunks : Array Lean.Expr) : MetaM Lean.Expr := do
  let element := mkConst ``UInt8
  let list := mkApp (mkConst ``List [Level.zero]) element
  let mut result ← mkListLit element []
  for chunk in chunks.reverse do
    result ← mkAppOptM ``HAppend.hAppend #[some list, some list, some list, none, some chunk, some result]
  return result

open Lean Meta Elab Tactic in
elab "scalar_node_row " block:term ", " selected:term ", " rowLength:term : tactic => withMainContext do
  evalTactic (← `(tactic| apply scalarNodeRow))
  evalTactic (← `(tactic| next => simp only [List.forall_mem_cons, List.forall_mem_singleton]; decide))
  let target ← instantiateMVars (← (← getMainGoal).getType)
  unless target.isAppOfArity ``Eq 3 do throwError "encoded node row equality required"
  let load := target.getAppArgs[1]!
  unless load.isAppOfArity ``Heap.loadBytes 3 do throwError "actual node row load required"
  let heap ← Term.exprToSyntax load.getAppArgs[0]!
  let address ← Term.exprToSyntax load.getAppArgs[1]!
  let some pointer ← getNatValue? (← whnf load.getAppArgs[1]!) | throwError "closed actual row address required"
  let blockValue ← zetaReduce (← Term.elabTerm block none)
  unless blockValue.isAppOfArity ``Block.mk 6 do throwError "actual fixed node block required"
  let rows ← nodeRows blockValue.getAppArgs[3]!
  let start := pointer - 1024
  let mut position := 0
  let mut found := none
  for i in [:rows.size] do
    if position == start && rows[i]!.2 == 40 then found := some i
    position := position + rows[i]!.2
  let some index := found | throwError "actual row is not an encoded segment"
  let actual ← Term.exprToSyntax rows[index]!.1
  let front ← Term.exprToSyntax (← nodeAppend ((rows.extract 0 index).map Prod.fst))
  let back ← Term.exprToSyntax (← nodeAppend ((rows.extract (index + 1) rows.size).map Prod.fst))
  let offset ← Term.exprToSyntax (mkNatLit start)
  evalTactic (← `(tactic| refine Eq.trans
    (show Heap.loadBytes $heap $address 40 = Except.ok $actual from ?_)
    (congrArg Except.ok (by congr 1 <;> rfl))))
  evalTactic (← `(tactic| apply Heap.loadBytes_of_block_segment
    (heap := $heap) (block := $block) (bytes := $actual) (start := $offset)
    (front := $front) (back := $back) $selected))
  evalTactic (← `(tactic| next => ((try simp only [$rowLength:term]); decide)))
  evalTactic (← `(tactic| next => simp only [List.length_append, List.length_replicate,
    List.length_nil, $rowLength:term, Nat.reduceAdd]))
  evalTactic (← `(tactic| simp only [$block:term, fullNodes,
    List.append_assoc, List.nil_append, List.append_nil]))

private def fullNodeWitness (minimum : Bool) (budget index : Nat)
    (inside : index < if minimum then 8 else 7) :
    NativeNode (fullInputs minimum).tree (fullBefore minimum budget).heap index := {
  production := fullProduction minimum index
  origin := 0
  finish := (fullText minimum).toList.length
  first := fullFirst minimum index
  count := fullArity minimum index
  base := 1384 - index * 40
  inside := by
    change index < 8
    cases minimum <;> simp only [Bool.false_eq_true, if_false, if_true] at inside <;> omega
  childrenInside := by
    cases minimum <;> simp only [Bool.false_eq_true, if_false, if_true] at inside
    · scalar_cases index 7 => decide
    · scalar_cases index 8 => decide
  location := by
    apply rawSliceElementAddress_of_layout (words := 5) rfl (by decide +kernel) (by decide)
    · change (index * 5 + 5 - 1) * 8 ≤ 1416
      cases minimum <;> simp only [Bool.false_eq_true, if_false, if_true] at inside <;> omega
    · change 1416 - (index * 5 + 5 - 1) * 8 = 1384 - index * 40
      omega
  snapshot := by
    let nodeBlock : Block := { base := 1024, size := 400, alignment := 8, bytes := fullNodes minimum }
    have selected : ∀ address : Nat, 1024 ≤ address → address < 1424 →
        (fullBefore minimum 0).heap.containingBlock? address = some nodeBlock := by
      intro address lower upper
      have sourcePast : 256 + ((fullText minimum).toList.length + 4) * 4 ≤ 1024 := by
        cases minimum <;> decide
      have oldMiss : ¬ address < 16 + 112 := by omega
      have sourceMiss : ¬ address < 256 + ((fullText minimum).toList.length + 4) * 4 := by omega
      have storageMiss : ¬ address < 640 + 16 := by omega
      have nodeHigh : address < 1024 + 400 := by omega
      simp only [Heap.containingBlock?, fullBefore, original, fullSourceBlocks,
        List.append_assoc, List.cons_append, List.nil_append, List.find?_cons,
        Bool.true_and, decide_eq_false oldMiss, decide_eq_false sourceMiss,
        decide_eq_false storageMiss, decide_eq_true lower, decide_eq_true nodeHigh,
        Bool.and_false, nodeBlock]
    have rowLength : ∀ finish production first count,
        (nativeNode finish production first count).length = 40 := by
      intro finish production first count
      simp only [nativeNode, nativeWord, i32Bytes, List.length_append,
        List.length_map, List.length_range, List.length_replicate]
    have snapshot : NativeSnapshot 64 extractedProgram (fullBefore minimum 0).heap nodeType
        (1384 - index * 40) (nodeValue (fullProduction minimum index) 0
          (fullText minimum).toList.length (fullFirst minimum index) (fullArity minimum index)) 40 := by
      cases minimum <;> simp only [Bool.false_eq_true, if_false, if_true] at inside
      · scalar_cases index 7 =>
          scalar_node_row nodeBlock, selected, rowLength
      · scalar_cases index 8 =>
          scalar_node_row nodeBlock, selected, rowLength
    exact snapshot.afterHeapReads (fullBudgetReads minimum budget) }

private def fullChildKind (minimum : Bool) : Nat → ChildKind
  | 8 | 10 | 11 | 12 | 14 | 15 => .StateChild
  | 13 | 16 => .TokenChild
  | 17 => if minimum then .StateChild else .NoChild
  | 18 => if minimum then .TokenChild else .NoChild
  | _ => .NoChild
private def fullChildPayload : Nat → Int
  | 8 => 1 | 10 => 2 | 11 => 3 | 12 => 5 | 14 => 4 | 15 => 6
  | 16 => 1 | 17 => 7 | 18 => 2 | _ => 0

private def fullChildWitness (minimum : Bool) (budget index : Nat)
    (selected : index ∈ if minimum then [8,10,11,12,13,14,15,16,17,18]
      else [8,10,11,12,13,14,15,16]) :
    NativeChild (fullInputs minimum).tree (fullBefore minimum budget).heap index := {
  kind := fullChildKind minimum index
  payload := fullChildPayload index
  semantic := 0
  base := 2552 - index * 24
  inside := by
    cases minimum <;>
      simp only [Bool.false_eq_true, if_false, if_true, List.mem_cons, List.not_mem_nil] at selected
    · rcases selected with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | impossible
      all_goals first | contradiction | decide
    · rcases selected with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | impossible
      all_goals first | contradiction | decide
  location := by
    apply rawSliceElementAddress_of_layout (words := 3) rfl (by decide +kernel) (by decide)
    · change (index * 3 + 3 - 1) * 8 ≤ 2568
      cases minimum <;>
        simp only [Bool.false_eq_true, if_false, if_true, List.mem_cons, List.not_mem_nil] at selected
      · rcases selected with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | impossible
        all_goals first | contradiction | decide
      · rcases selected with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | impossible
        all_goals first | contradiction | decide
    · change 2568 - (index * 3 + 3 - 1) * 8 = 2552 - index * 24
      omega
  snapshot := by
    have snapshot : NativeSnapshot 64 extractedProgram (fullBefore minimum 0).heap childType
        (2552 - index * 24) (childValue (fullChildKind minimum index) (fullChildPayload index) 0) 24 := by
      cases minimum <;>
        simp only [Bool.false_eq_true, if_false, if_true, List.mem_cons, List.not_mem_nil] at selected
      · rcases selected with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | impossible
        all_goals first | contradiction | scalar_record [0, 8, 16], [8, 8, 8], 3 => scalar_primitive
      · rcases selected with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | impossible
        all_goals first | contradiction | scalar_record [0, 8, 16], [8, 8, 8], 3 => scalar_primitive
    exact snapshot.afterHeapReads (fullBudgetReads minimum budget) }

private def fullNativeSignature (minimum : Bool) (budget : Nat) :
    NativeSignature (fullInputs minimum).signature (fullBefore minimum budget).heap := {
  base := 4168
  location := by
    change rawSliceElementAddress? extractedProgram signatureType 4232 0 = .ok 4168
    scalar_location 9
  snapshot := by
    have snapshot : NativeSnapshot 64 extractedProgram (fullBefore minimum 0).heap signatureType
        4168 (fullInputs minimum).signature.entry 72 := by
      cases minimum <;>
        scalar_record [0, 8, 16, 24, 32, 48, 56, 64], [8, 8, 8, 8, 16, 8, 8, 8], 8 => scalar_primitive
    exact snapshot.afterHeapReads (fullBudgetReads minimum budget) }

private def fullTokenKind (minimum : Bool) : Nat → Value
  | 0 => source_value Extracted.«verified::token».Types.«TokenKind».«ReturnKeyword» []
  | 1 => if minimum then source_value Extracted.«verified::token».Types.«TokenKind».«Minus» []
      else booleanToken true
  | _ => integerToken
private def fullTokenStart : Nat → Int | 0 => 0 | 1 => 7 | _ => 8
private def fullTokenEnd (minimum : Bool) : Nat → Int
  | 0 => 6 | 1 => if minimum then 8 else 11 | _ => 18
private def fullTokenWitness (minimum : Bool) (budget index : Nat)
    (inside : index < fullTokenCount minimum) :
    NativeToken (fullInputs minimum) (fullBefore minimum budget).heap index := {
  address := 3184, length := 5, base := 3168 - index * 24
  kind := fullTokenKind minimum index
  start := fullTokenStart index, finish := fullTokenEnd minimum index
  descriptor := rfl, inside := inside, bound := by cases minimum <;> decide
  location := by
    apply rawSliceElementAddress_of_layout (words := 3) rfl (by decide +kernel) (by decide)
    · change (index * 3 + 3 - 1) * 8 ≤ 3184
      cases minimum <;> simp only [fullTokenCount, Bool.false_eq_true, if_false, if_true] at inside <;> omega
    · change 3184 - (index * 3 + 3 - 1) * 8 = 3168 - index * 24
      omega
  snapshot := by
    have snapshot : NativeSnapshot 64 extractedProgram (fullBefore minimum 0).heap tokenType
        (3168 - index * 24) (tokenRow (fullTokenKind minimum index)
          (fullTokenStart index) (fullTokenEnd minimum index)) 24 := by
      cases minimum <;> simp only [fullTokenCount, Bool.false_eq_true, if_false, if_true] at inside
      all_goals scalar_cases index 3 =>
        first | omega | scalar_record [0, 8, 16], [8, 8, 8], 3 => scalar_primitive
    exact snapshot.afterHeapReads (fullBudgetReads minimum budget) }

private theorem fullSourceWord (minimum : Bool) (budget : Nat) (number : Int)
    (lower : -(2 ^ 31) ≤ number) (upper : number < 2 ^ 31)
    (inside : index < (fullText minimum).toList.length + 4)
    (loaded : (fullBefore minimum budget).heap.loadBytes (256 + index * 4) 4 = .ok (i32Bytes number)) :
    readRawSliceIndex extractedProgram (fullBefore minimum budget) (.scalar (.signed .i32))
      256 ((fullText minimum).toList.length + 4) index = .ok (.signed .i32 number) := by
  have represented : (BitVec.ofInt 32 number).toInt = number :=
    BitVec.toInt_ofInt_eq_self (by decide) lower upper
  simpa only [represented] using readRawSliceIndex_i32Bytes extractedProgram (fullBefore minimum budget)
    (word := BitVec.ofInt 32 number) inside (by simpa only [represented] using loaded)

private def fullReturnSpelling (minimum : Bool) (budget : Nat) :
    OriginalToken (fullInputs minimum) (fullBefore minimum budget) 0 "return"
      (source_value Extracted.«verified::token».Types.«TokenKind».«ReturnKeyword» []) := {
  toNativeToken := fullTokenWitness minimum budget 0 (by cases minimum <;> decide)
  sourceAddress := 256, sourceCapacity := (fullText minimum).toList.length + 4, origin := 0
  kindMatches := rfl, startMatches := rfl, finishMatches := rfl, source := rfl
  span := by cases minimum <;> decide
  sourceBound := by change (fullText minimum).toList.length ≤ (fullText minimum).toList.length + 4; omega
  sourceFits := by cases minimum <;> decide
  tokensFit := by cases minimum <;> decide
  words := by
    intro index inside
    change index < 6 at inside
    cases minimum <;> scalar_cases index 6 => apply fullSourceWord <;> first | rfl | decide }

private def fullTopology (minimum : Bool) (budget : Nat) :
    TerminalTopology (fullInputs minimum) (fullBefore minimum budget).heap 0 := {
  block := 1, list := 2, statement := 3, rest := 5, optional := 4, tokenIndex := 0
  declarationNode := fullNodeWitness minimum budget 0 (by cases minimum <;> decide)
  declarationProduction := rfl, declarationBound := by change 8 < (9 : Nat); decide
  bodyChild := fullChildWitness minimum budget 8 (by cases minimum <;> decide)
  bodyKind := rfl, bodyIndex := rfl
  blockNode := fullNodeWitness minimum budget 1 (by cases minimum <;> decide)
  blockProduction := rfl, blockBound := by change 1 < (2 : Nat); decide
  listChild := fullChildWitness minimum budget 10 (by cases minimum <;> decide)
  listKind := rfl, listIndex := rfl
  listNode := fullNodeWitness minimum budget 2 (by cases minimum <;> decide)
  listProduction := rfl, listBound := by change 1 < (2 : Nat); decide
  firstChild := fullChildWitness minimum budget 11 (by cases minimum <;> decide)
  firstKind := rfl, firstIndex := rfl
  restChild := fullChildWitness minimum budget 12 (by cases minimum <;> decide)
  restKind := rfl, restIndex := rfl
  restNode := fullNodeWitness minimum budget 5 (by cases minimum <;> decide)
  restProduction := rfl
  statementNode := fullNodeWitness minimum budget 3 (by cases minimum <;> decide)
  statementProduction := rfl, statementBound := by change 1 < (2 : Nat); decide
  optionalChild := fullChildWitness minimum budget 14 (by cases minimum <;> decide)
  optionalKind := rfl, optionalIndex := rfl
  optionalNode := fullNodeWitness minimum budget 4 (by cases minimum <;> decide)
  returnChild := fullChildWitness minimum budget 13 (by cases minimum <;> decide)
  returnKind := rfl, returnIndex := rfl
  returnToken := fullTokenWitness minimum budget 0 (by cases minimum <;> decide)
  returnKeyword := rfl
  distinct := by decide }

private def fullBooleanSpelling (budget : Nat) :
    OriginalToken (fullInputs false) (fullBefore false budget) 1 "true" (booleanToken true) := {
  toNativeToken := fullTokenWitness false budget 1 (by decide)
  sourceAddress := 256, sourceCapacity := 15, origin := 7
  kindMatches := rfl, startMatches := rfl, finishMatches := rfl, source := rfl
  span := by decide, sourceBound := by decide, sourceFits := by decide, tokensFit := by decide
  words := by
    intro index inside
    change index < 4 at inside
    scalar_cases index 4 => apply fullSourceWord <;> first | rfl | decide }

private def fullBooleanNatural (budget : Nat) : NaturalBody (fullInputs false) (fullBefore false budget) 0 := {
  topology := fullTopology false budget
  keyword := fullReturnSpelling false budget
  returns := .scalar 6 rfl (by change 0 < (1 : Nat); decide) (fullChildWitness false budget 15 (by decide)) rfl rfl
    { expression := .literal (.boolean true), result := .Bool, spelling := .boolean true, route := [6]
      «syntax» := .boolean (fullNodeWitness false budget 6 (by decide)) rfl rfl
        (fullChildWitness false budget 16 (by decide)) rfl rfl (fullBooleanSpelling budget)
      distinct := by decide } rfl (by change ([0,1,2,3,4,6] : List Nat).Nodup; decide) }

/-- The full scalar fixture's original Bool bytes inhabit the public domain. -/
theorem originalBooleanNatural (budget : Nat) :
    ∃ body : NaturalBody (fullInputs false) (fullBefore false budget) 0, body.Selects (.boolean true) :=
  ⟨fullBooleanNatural budget, ScalarSpelling.Selects.boolean true⟩

private def fullMinusSpelling (budget : Nat) :
    OriginalToken (fullInputs true) (fullBefore true budget) 1 "-"
      (source_value Extracted.«verified::token».Types.«TokenKind».«Minus» []) := {
  toNativeToken := fullTokenWitness true budget 1 (by decide)
  sourceAddress := 256, sourceCapacity := 22, origin := 7
  kindMatches := rfl, startMatches := rfl, finishMatches := rfl, source := rfl
  span := by decide, sourceBound := by decide, sourceFits := by decide, tokensFit := by decide
  words := by
    intro index inside
    change index < 1 at inside
    scalar_cases index 1 => apply fullSourceWord <;> first | rfl | decide }

private def fullIntegerSpelling (budget : Nat) :
    OriginalToken (fullInputs true) (fullBefore true budget) 2 "2147483648" integerToken := {
  toNativeToken := fullTokenWitness true budget 2 (by decide)
  sourceAddress := 256, sourceCapacity := 22, origin := 8
  kindMatches := rfl, startMatches := rfl, finishMatches := rfl, source := rfl
  span := by decide, sourceBound := by decide, sourceFits := by decide, tokensFit := by decide
  words := by
    intro index inside
    change index < 10 at inside
    scalar_cases index 10 => apply fullSourceWord <;> first | rfl | decide }

private theorem minimumDecimal : DecimalSpelling (ascii "2147483648") (2 ^ 31) := by
  change DecimalSpelling [50, 49, 52, 55, 52, 56, 51, 54, 52, 56] 2147483648
  exact .append
    (.append (.append (.append (.append (.append (.append (.append
      (.append (.digit 2 (by decide)) 1 (by decide) false)
      4 (by decide) false) 7 (by decide) false) 4 (by decide) false)
      8 (by decide) false) 3 (by decide) false) 6 (by decide) false)
      4 (by decide) false) 8 (by decide) false

private def fullMinimumNatural (budget : Nat) : NaturalBody (fullInputs true) (fullBefore true budget) 0 := {
  topology := fullTopology true budget
  keyword := fullReturnSpelling true budget
  returns := .scalar 6 rfl (by change 0 < (1 : Nat); decide)
    (fullChildWitness true budget 15 (by decide)) rfl rfl
    { expression := .unary .negative (.literal (.integer "2147483648"))
      result := .I32
      spelling := .negative minimumDecimal (by decide)
      route := [6,7]
      «syntax» := .negative (fullNodeWitness true budget 6 (by decide)) rfl rfl
        (fullChildWitness true budget 17 (by decide)) rfl rfl
        (fullChildWitness true budget 16 (by decide)) rfl rfl (fullMinusSpelling budget)
        (.integer (fullNodeWitness true budget 7 (by decide)) rfl rfl
          (fullChildWitness true budget 18 (by decide)) rfl rfl (fullIntegerSpelling budget))
      distinct := by decide } rfl (by change ([0,1,2,3,4,6,7] : List Nat).Nodup; decide) }

/-- The same MIN call uses two native arena nodes without requiring a second
    scalar event slot, and its decimal magnitude is proved from spelling. -/
theorem originalMinimumNatural (budget : Nat) :
    ∃ body : NaturalBody (fullInputs true) (fullBefore true budget) 0,
      body.Selects (.integer (Int32.ofInt (-2147483648))) :=
  ⟨fullMinimumNatural budget, ScalarSpelling.Selects.minimum minimumDecimal (by decide) rfl⟩

#print axioms originalBooleanNatural
#print axioms originalMinimumNatural

private def fullNatural (minimum : Bool) (budget : Nat) :
    NaturalBody (fullInputs minimum) (fullBefore minimum budget) 0 := by
  cases minimum
  · exact fullBooleanNatural budget
  · exact fullMinimumNatural budget

private def fullBody (minimum : Bool) : ReturnBody :=
  if minimum then .integer (Int32.ofInt (-2147483648)) else .boolean true

private theorem fullSelected (selected : (fullNatural minimum budget).Selects body) :
    body = fullBody minimum := by
  cases minimum
  · change ScalarSpelling.Selects (.boolean true) body at selected
    cases selected
    rfl
  · change ScalarSpelling.Selects (.negative minimumDecimal (by decide)) body at selected
    cases selected with
    | negative spelled _ ordinary =>
        have same := Option.some.inj (minimumDecimal.parsedDecimal.symm.trans spelled.parsedDecimal)
        exact False.elim (by omega)
    | minimum => rfl

private theorem fullRoom (minimum : Bool) (budget : Nat)
    (read : (fullBefore minimum 0).heap.loadBytes address count = .ok bytes) :
    (fullBefore minimum budget).heap.Readable address count :=
  (fullBudgetReads minimum budget).readable (Heap.Readable.of_loadBytes read)

private def fullOutput (minimum enabled : Bool) (budget : Nat) : Context (fullBefore minimum budget) := {
  input enabled with
  eventRoom := fullRoom minimum budget (bytes := eventBytes) (by
    change (fullBefore minimum 0).heap.loadBytes 56 40 = .ok eventBytes
    cases minimum <;> exact scalarOkOfOption (by decide +kernel))
  typeRoom := by
    intro yes
    change enabled = true at yes
    subst enabled
    exact fullRoom minimum budget (bytes := typeBytes) (by cases minimum <;> exact scalarOkOfOption (by decide +kernel)) }

private def fullPermissions (minimum enabled : Bool) (budget : Nat) :
    OutputPermissions (fullOutput minimum enabled budget) 2 := {
  bound := by change 2 ≤ (2 : Nat); decide
  typeBound := by intro yes; change enabled = true at yes; subst enabled; change 2 ≤ (2 : Nat); decide
  eventBases := fun index => 56 - index * 40
  typeBases := fun index => 112 - index * 16
  eventLocation := by
    intro index inside
    change rawSliceElementAddress? extractedProgram eventType 88 index = .ok (56 - index * 40)
    scalar_cases index 2 => scalar_location 5
  typeLocation := by
    intro yes index inside
    change enabled = true at yes
    subst enabled
    change rawSliceElementAddress? extractedProgram referenceType 120 index = .ok (112 - index * 16)
    scalar_cases index 2 => scalar_location 2
  eventRoom := by
    intro index inside
    cases minimum <;> scalar_cases index 2 =>
      exact fullRoom _ budget (bytes := eventBytes) (scalarOkOfOption (by decide +kernel))
  typeRoom := by
    intro yes index inside
    change enabled = true at yes
    subst enabled
    cases minimum <;> scalar_cases index 2 =>
      exact fullRoom _ budget (bytes := typeBytes) (scalarOkOfOption (by decide +kernel))
  planes := by
    intro _ event type eventInside typeInside
    apply Or.inl
    change 56 - event * 40 + 40 ≤ 112 - type * 16
    omega }

private def fullArena : Arena := {
  nodes := 856, capacity := 2, count := 896, countLength := 1
  fits := by decide, countPositive := by decide }

private def fullStorage (minimum enabled : Bool) (budget : Nat) :
    ScalarStorage (fullWorkspace enabled) (fullBefore minimum budget) (if minimum then 2 else 1) := {
  arena := fullArena
  arenaValue := rfl
  positive := by cases minimum <;> decide
  bound := by cases minimum <;> decide
  bases := fun index => 816 - index * 48
  locations := by
    intro index inside
    have two : index < 2 := by cases minimum <;> simp only [Bool.false_eq_true, if_false, if_true] at inside <;> omega
    scalar_cases index 2 => scalar_location 6
  nodeRoom := by
    intro index inside
    have two : index < 2 := by cases minimum <;> simp only [Bool.false_eq_true, if_false, if_true] at inside <;> omega
    cases minimum <;> scalar_cases index 2 =>
      exact fullRoom _ budget (bytes := List.replicate 48 165) (scalarOkOfOption (by decide +kernel))
  countRoom := fullRoom minimum budget (bytes := i32Bytes 13)
    (by cases minimum <;> exact scalarOkOfOption (by decide +kernel))
  codes := 912, depths := 928
  codesValue := rfl, depthsValue := rfl
  codesRoom := by
    cases minimum
    · exact fullRoom false budget (bytes := i32Bytes 77) (scalarOkOfOption (by decide +kernel))
    · exact fullRoom true budget (bytes := i32Bytes 77 ++ i32Bytes 88) (scalarOkOfOption (by decide +kernel))
  depthsRoom := by
    cases minimum
    · exact fullRoom false budget (bytes := i32Bytes 331) (scalarOkOfOption (by decide +kernel))
    · exact fullRoom true budget (bytes := i32Bytes 331 ++ i32Bytes 442) (scalarOkOfOption (by decide +kernel))
  countCodes := Or.inl (by decide)
  countDepths := Or.inl (by decide)
  codeDepths := by cases minimum <;> exact Or.inl (by decide)
  nodeCount := by intro index _; apply Or.inl; change 816 - index * 48 + 48 ≤ 896; omega
  nodeCodes := by intro index _; apply Or.inl; change 816 - index * 48 + 48 ≤ 912; omega
  nodeDepths := by intro index _; apply Or.inl; change 816 - index * 48 + 48 ≤ 928; omega }

private theorem fullWrites (written : (fullStorage minimum enabled budget).writes address) :
    768 ≤ address ∧ address < 936 := by
  rcases written with count | ⟨index, inside, lower, upper⟩ | codes | depths
  · change 896 ≤ address ∧ address < 900 at count
    omega
  · have two : index < 2 := by cases minimum <;> simp only [Bool.false_eq_true, if_false, if_true] at inside <;> omega
    change 816 - index * 48 ≤ address at lower
    change address < 816 - index * 48 + 48 at upper
    omega
  · change 912 ≤ address ∧ address < 912 + (if minimum then 2 else 1) * 4 at codes
    cases minimum <;> simp only [Bool.false_eq_true, if_false, if_true] at codes <;> omega
  · change 928 ≤ address ∧ address < 928 + (if minimum then 2 else 1) * 4 at depths
    cases minimum <;> simp only [Bool.false_eq_true, if_false, if_true] at depths <;> omega

private theorem fullOutputBelow (written : (fullPermissions minimum enabled budget).writesFrom 0 address) :
    address < 128 := by
  rcases written with ⟨index, _, _, event | ⟨_, annotation⟩⟩
  · change 56 - index * 40 ≤ address ∧ address < 56 - index * 40 + 40 at event
    omega
  · change 112 - index * 16 ≤ address ∧ address < 112 - index * 16 + 16 at annotation
    omega

private def fullOriginalRegion (address : Nat) : Prop :=
  (256 ≤ address ∧ address < 512) ∨ (1024 ≤ address ∧ address < 4240)

private theorem scalarSlot (element : Ty) (pointer index words base : Nat)
    (nominal : (match element with | .structure _ | .enumeration _ => true | _ => false) = true)
    (layout : NativeLayout.valueWords? extractedProgram element = some words) (positive : 0 < words)
    (room : (index * words + words - 1) * 8 ≤ pointer)
    (location : rawSliceElementAddress? extractedProgram element pointer index = .ok base) :
    base + (index * words + words - 1) * 8 = pointer := by
  have known := rawSliceElementAddress_of_layout nominal layout positive room rfl
  have same : base = pointer - (index * words + words - 1) * 8 := Except.ok.inj (location.symm.trans known)
  omega

private theorem fullApart (minimum : Bool) : InputApart (fullInputs minimum) (fun address => ¬fullOriginalRegion address) := {
  nodes := fun index base inside location address lower upper outside => by
    change index < 8 at inside
    change rawSliceElementAddress? extractedProgram nodeType 1416 index = .ok base at location
    have point := scalarSlot nodeType 1416 index 5 base rfl (by decide +kernel) (by decide) (by omega) location
    change base ≤ address at lower
    change address < base + 40 at upper
    dsimp only [Lanius.Address] at point lower upper
    exact outside (Or.inr ⟨by omega, by omega⟩)
  children := fun index base inside location address lower upper outside => by
    change index < fullChildCount minimum at inside
    have bounded : index < 19 := by cases minimum <;>
      simp only [fullChildCount, Bool.false_eq_true, if_false, if_true] at inside <;> omega
    change rawSliceElementAddress? extractedProgram childType 2568 index = .ok base at location
    have point := scalarSlot childType 2568 index 3 base rfl (by decide +kernel) (by decide) (by omega) location
    change base ≤ address at lower
    change address < base + 24 at upper
    dsimp only [Lanius.Address] at point lower upper
    exact outside (Or.inr ⟨by omega, by omega⟩)
  tokens := fun pointer length index base descriptor inside location address lower upper outside => by
    change Value.rawSlice tokenType 3184 5 = .rawSlice tokenType pointer length at descriptor
    cases descriptor
    change index < fullTokenCount minimum at inside
    have bounded : index < 3 := by cases minimum <;>
      simp only [fullTokenCount, Bool.false_eq_true, if_false, if_true] at inside <;> omega
    have point := scalarSlot tokenType 3184 index 3 base rfl (by decide +kernel) (by decide) (by omega) location
    change base ≤ address at lower
    change address < base + 24 at upper
    dsimp only [Lanius.Address] at point lower upper
    exact outside (Or.inr ⟨by omega, by omega⟩)
  source := fun pointer length descriptor index inside address lower upper outside => by
    change Value.rawSlice (.scalar (.signed .i32)) 256 ((fullText minimum).toList.length + 4) =
      .rawSlice (.scalar (.signed .i32)) pointer length at descriptor
    cases descriptor
    have bounded : index < 18 := by
      cases minimum
      · change index < 11 at inside; omega
      · change index < 18 at inside; exact inside
    change 256 + index * 4 ≤ address at lower
    change address < 256 + index * 4 + 4 at upper
    dsimp only [Lanius.Address] at lower upper
    exact outside (Or.inl ⟨by omega, by omega⟩) }

private theorem fullSourceRange (inside : sourceBytes (fullInputs minimum) (fullNativeSignature minimum budget) address) :
    fullOriginalRegion address := by
  by_cases contained : fullOriginalRegion address
  · exact contained
  · exact False.elim (sourceBytes.apart (fullApart minimum)
      (fun address lower upper outside => outside (Or.inr ⟨by change 4168 ≤ address at lower; omega,
        by change address < 4240 at upper; omega⟩)) inside contained)

private theorem fullUnique : HeapBlockBasesUnique (fullBefore minimum budget).heap := by
  intro left leftMember right rightMember same
  simp only [fullBefore, original, fullSourceBlocks, List.mem_append,
    List.mem_cons, List.not_mem_nil, or_false, or_assoc] at leftMember rightMember
  rcases leftMember with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    rcases rightMember with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    first | rfl | cases same

private def inactivePrevious : IRCatalogAppendProof.PreviousRow := {
  id := 0, parameters := 0, result := .Invalid, tree := .unit }

private theorem fullInvariant (minimum : Bool) (budget : Nat) :
    IRCatalogConstructionProof.Invariant fullCatalog 0 (fun _ => inactivePrevious)
      (fullBefore minimum budget) := {
  supported := ⟨by decide, by decide⟩
  bounds := ⟨by decide, by decide⟩
  count := by
    have snapshot : NativeSnapshot 64 extractedProgram (fullBefore minimum 0).heap (.scalar (.signed .i32))
        4608 (.signed .i32 0) 4 := by
      apply scalarWord <;> first | decide | cases minimum <;> exact scalarOkOfOption (by decide +kernel)
    exact (snapshot.afterHeapReads (fullBudgetReads minimum budget)).read
  backing := by
    intro index inside
    let bytes := nativeWord 0 ++ List.replicate 192 165
    change index < 200 at inside
    have length : bytes.length = 200 := by decide +kernel
    have bound : index < bytes.length := by omega
    have endBound : (4608 : Nat) + index < 4808 := Nat.add_lt_add_left inside 4608
    refine ⟨bytes[index], Heap.loadByte_ok_iff.mpr ⟨
      { base := 4608, size := 200, alignment := 8, bytes := bytes }, ?_, ?_⟩⟩
    · change (fullBefore minimum budget).heap.containingBlock? (4608 + index) =
        some { base := 4608, size := 200, alignment := 8, bytes := bytes }
      cases minimum <;>
        dsimp only [Heap.containingBlock?, fullBefore, original, fullSourceBlocks, fullCatalog,
          IRCatalogConstructionProof.Catalog.bytes, IRCatalogConstructionProof.Catalog.length]
      all_goals
        simp (disch := omega) [fullText]
        repeat' first | apply And.intro | rfl | exact endBound | omega
    · change bytes[(4608 + index) - 4608]? = some bytes[index]
      simpa only [Nat.add_sub_cancel_left] using
        (show bytes[index]? = some bytes[index] from List.getElem?_eq_getElem bound)
  occupied := by intro index inside; change index < 0 at inside; omega
  formed := by simp [State.CellsWellFormed, fullBefore, original]
  unique := fullUnique
  below := by
    intro block member
    change block.base + max block.size 1 ≤ 5120
    simp only [fullBefore, original, fullSourceBlocks, List.mem_append,
      List.mem_cons, List.not_mem_nil, or_false, or_assoc] at member
    rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
      cases minimum <;> decide +kernel
  noViews := rfl }

private def fullBudget (minimum : Bool) : Nat := if minimum then 200 else 176

private def fullWorkspaceStorage (minimum enabled : Bool) (budget : Nat) :
    (fullNatural minimum budget).returns.WorkspaceStorage (fullWorkspace enabled) := by
  cases minimum
  · exact fullStorage false enabled budget
  · exact fullStorage true enabled budget

private theorem fullWorkspaceWrites :
    (fullNatural minimum budget).returns.workspaceWrites (fullWorkspace enabled)
      (fullWorkspaceStorage minimum enabled budget) address =
      (fullStorage minimum enabled budget).writes address := by
  cases minimum <;> rfl

private def fullUsed (minimum enabled : Bool) (budget : Nat) (body : ReturnBody)
    (selected : (fullNatural minimum budget).Selects body) :
    OutputPermissions (fullOutput minimum enabled budget) body.count := by
  rw [fullSelected selected]
  cases minimum <;> exact fullPermissions _ enabled budget

private theorem fullCatalogFootprint (request : IRCatalogAppendProof.Model) :
    (fullCatalog.model 0 (fun _ => inactivePrevious) request).footprint address =
      ((4712 ≤ address ∧ address < 4808) ∨ (4608 ≤ address ∧ address < 4612)) := by
  dsimp only [IRCatalogAppendProof.Arguments.footprint, IRCatalogAppendProof.Arguments.rowBase,
    IRCatalogAppendProof.Arguments.occupied, IRCatalogConstructionProof.Catalog.model]
  rw [show fullCatalog.length = 2 by decide +kernel,
    show (0 : Int32).toInt.toNat = 0 by decide +kernel]
  change ((4712 ≤ address ∧ address < 4808) ∨ (4608 ≤ address ∧ address < 4612)) = _
  rfl

/-- Direct application of the total theorem to the same Bool/MIN bytes used
    by the full1179 runtime checks, in both annotation modes. -/
theorem fullNaturalSuccess (minimum enabled : Bool) :
    ∃ body, ∃ selected : (fullNatural minimum (fullBudget minimum)).Selects body, ∃ after,
      RunsExpr extractedProgram (fullBefore minimum (fullBudget minimum))
        (producerCall (fullInputs minimum) (fullWorkspace enabled) 0 8) (.signed .i32 0) after ∧
      after.locals = (fullBefore minimum (fullBudget minimum)).locals ∧
      (fullInputs minimum).signature.Read after ∧
      (∀ pointer offset byte,
        sourceBytes (fullInputs minimum) (fullNativeSignature minimum (fullBudget minimum)) (pointer + offset) →
        (fullBefore minimum (fullBudget minimum)).heap.loadByte pointer offset = .ok byte →
        after.heap.loadByte pointer offset = .ok byte) ∧
      (∀ (context : SurfaceElaboration.Context) (target : extractedProgram.target = context.target) (next : VarId),
        body.Meaning (fullInputs minimum).signature.result context next
          (fullNatural minimum (fullBudget minimum)).surface) := by
  classical
  obtain ⟨body, selected, result, after, run, _, locals, _, meaning, readonly, signature, _, _, sufficient⟩ :=
    actualNaturalFunction (fullInputs minimum) (fullWorkspace enabled) 0
      (fullNatural minimum (fullBudget minimum)) (fullNativeSignature minimum (fullBudget minimum))
      (fullWorkspaceStorage minimum enabled (fullBudget minimum))
      (fullOutput minimum enabled (fullBudget minimum)) rfl
      (fullUsed minimum enabled (fullBudget minimum)) rfl rfl (fullInvariant minimum (fullBudget minimum))
      (by cases minimum <;> decide) (by cases minimum <;> decide)
      (by
        intro body selected budget available
        have same := fullSelected selected
        subst body
        have resource : budget = some 120 := by
          cases minimum <;> change some (some 120) = some budget at available <;> exact Option.some.inj available.symm
        subst budget
        cases minimum <;> decide)
      (by
        intro body selected
        have same := fullSelected selected
        subst body
        apply (fullApart minimum).mono
        intro address changed
        rw [fullWorkspaceWrites] at changed
        cases minimum <;> change _ ∨ (fullPermissions _ enabled _).writesFrom 0 address at changed
        all_goals
          rcases changed with storage | output
          · have bounds := fullWrites storage
            simp only [fullOriginalRegion] at *
            omega
          · have bounds := fullOutputBelow output
            simp only [fullOriginalRegion] at *
            omega)
      (by
        intro body selected address lower upper changed
        have same := fullSelected selected
        subst body
        rw [fullWorkspaceWrites] at changed
        change 4168 ≤ address at lower
        cases minimum <;> change _ ∨ (fullPermissions _ enabled _).writesFrom 0 address at changed
        all_goals
          rcases changed with storage | output
          · have bounds := fullWrites storage; omega
          · have bounds := fullOutputBelow output; omega)
      (by
        intro body selected address written changed
        have same := fullSelected selected
        subst body
        rw [fullWorkspaceWrites] at changed
        cases minimum <;> change (fullPermissions _ enabled _).writesFrom 0 address at written
        all_goals have output := fullOutputBelow written; have storage := fullWrites changed; omega)
      (by
        intro body selected address lower upper changed
        have same := fullSelected selected
        subst body
        rw [fullWorkspaceWrites] at changed
        change 4608 ≤ address at lower
        cases minimum <;> change _ ∨ (fullPermissions _ enabled _).writesFrom 0 address at changed
        all_goals
          rcases changed with storage | output
          · have bounds := fullWrites storage; omega
          · have bounds := fullOutputBelow output; omega)
      (by
        intro body selected address inside _room changed
        have range := fullSourceRange inside
        rw [fullCatalogFootprint] at changed
        simp only [fullOriginalRegion] at range
        omega)
  have count : body.count = 2 := by rw [fullSelected selected]; cases minimum <;> rfl
  have zero : result = 0 := sufficient (some 120) (some 8) (some 0)
    (by cases minimum <;> rfl) (by rw [count]; rfl) (by rw [count]; rfl)
    (by decide) (by intro index inside; change index < 0 at inside; omega)
  rw [zero] at run
  exact ⟨body, selected, after, run, locals, signature, readonly, meaning⟩

#print axioms fullNaturalSuccess

end IRBodyProductionScalarCapacityTests
