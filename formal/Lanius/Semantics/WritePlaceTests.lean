import Lanius.Semantics
import Lanius.Semantics.RawFieldStore

namespace Lanius.Semantics.WritePlaceTests

open Lanius Lanius.Core Lanius.Memory

private def i (n : Int) : Value := .signed .i32 n
private def lit (n : Int) : Expr := .value (i n)
private def pair (n : Int) (b : Bool) : Value := .structure 3 [i n, .boolean b]
private def seq (first second : Expr) : Expr := .matchValue first [(.wildcard, second)]
private def set (id : VarId) (value : Expr) : Expr := .assign .set (.local id) value
private def bump (id : VarId) : Expr := .assign .add (.local id) (lit 1)

private def program : Program := {
  structures := [{ id := 3, fields := [.scalar (.signed .i32), .scalar .bool] }]
  functions := [{
    id := 90
    parameters := [(41, .scalar (.signed .i32))]
    returnType := .unit
    body := none
    external := some (.host .exit) }] }

-- Independent bytes: 2 is not a native bool. Do not seed this via the writer
-- whose absence of an old read is under test.
private def initial : State :=
  let base : State := {
    heap := {
      blocks := [
      { base := 4, size := 4, alignment := 4, bytes := List.replicate 4 165 },
      { base := 8, size := 16, alignment := 8,
        bytes := encodeNatLE 4 2 ++ List.replicate 4 165 ++ i32Bytes 17 ++ List.replicate 4 165 },
      { base := 32, size := 16, alignment := 8,
        bytes := encodeNatLE 4 0 ++ List.replicate 4 165 ++ i32Bytes 51 ++ List.replicate 4 165 },
      { base := 48, size := 4, alignment := 4, bytes := List.replicate 4 165 }]
      nextAddress := 52
      remaining := some 100 }
    world := { standardOutput := [88] } }
  let descriptor := base.bindLocal 0 (.rawSlice (.structure 3) 16 1)
  let traced := descriptor.bindLocal 1 (i 0)
  let indexed := traced.bindLocal 2 (i 0)
  indexed.bindLocal 3 (i 0)

private def row (index : Expr := lit 0) : Place := .index (.local 0) index
private def field (index : Expr := lit 0) : Place := .field (row index) 0
private def indexMark (value : Int) : Expr := seq (bump 2) (lit value)
private def rhs (value : Expr) : Expr := seq (bump 3) value
private def run (state : State) (expression : Expr) : Outcome Value :=
  evalExpr 48 program state expression

private def localIs (state : State) (id : VarId) (value : Value) : Bool :=
  state.local? id == some value
private def uninitialized (state : State) (id : VarId) : Bool :=
  match state.cellId? id with
  | none => false
  | some cell => (state.cellEntry? cell).map Cell.value == some none

private def heapShape (heap : Heap) := heap.blocks.map fun block =>
  (block.base, block.size, block.alignment, block.live, block.owned)

-- Check all initial bytes outside the permitted write footprint, not just
-- selected sentinels. Also check allocator metadata and block identities.
private def heapFrame (before after : Heap) (address size : Nat) : Bool :=
  before.nextAddress == after.nextAddress && before.remaining == after.remaining &&
  heapShape before == heapShape after && before.blocks.all (fun block =>
    (List.range block.size).all fun offset =>
      if address ≤ block.base + offset && block.base + offset < address + size then true
      else (before.loadByte block.base offset).toOption == (after.loadByte block.base offset).toOption)

private def callerFrame (before after : State) : Bool :=
  before.locals == after.locals && before.nextCell == after.nextCell &&
  before.i32ArrayViews.length == after.i32ArrayViews.length &&
  before.world.standardOutput == after.world.standardOutput &&
  before.world.calls == after.world.calls

private def nativeIs (state : State) (type : Ty) (address : Nat) (value : Value) : Bool :=
  (readNativeValue 16 program state.heap type address).toOption == some value

example : readNativeValue 16 program initial.heap (.structure 3) 16 = .error .typeMismatch := rfl

def wholeOverwrite : Bool :=
  match run initial (.assign .set (row) (.value (pair 19 true))) with
  | .done .unit after => nativeIs after (.structure 3) 16 (pair 19 true) &&
      nativeIs after (.structure 3) 40 (pair 51 false) &&
      heapFrame initial.heap after.heap 8 16 && callerFrame initial after
  | _ => false

def plainField : Bool :=
  match run initial (.assign .set (field) (lit 99)) with
  | .done .unit after => nativeIs after (.scalar (.signed .i32)) 16 (i 99) &&
      (after.heap.loadBytes 8 4).toOption == some (encodeNatLE 4 2) &&
      heapFrame initial.heap after.heap 16 4 && callerFrame initial after
  | _ => false

-- RHS overwrites the selected old value with 100. Compound addition must use
-- the captured 17, not reread 100, and must not decode the bad bool sibling.
def compoundCapturedOld : Bool :=
  match run initial (.assign .add (field)
      (rhs (seq (.assign .set (field) (lit 100)) (lit 5)))) with
  | .done .unit after => nativeIs after (.scalar (.signed .i32)) 16 (i 22) &&
      localIs after 3 (i 1) && heapFrame initial.heap after.heap 16 4 && callerFrame initial after
  | _ => false

-- A changed base descriptor in the index must not redirect this assignment.
-- The index and RHS run once and in that order; the final trace is 12.
def descriptorCaptured : Bool :=
  let index := seq (bump 2) (seq (set 0 (.value (.rawSlice (.structure 3) 40 1)))
    (seq (set 1 (lit 1)) (lit 0)))
  let value := rhs (seq (set 1 (.binary .add (.binary .multiply (.local 1) (lit 10)) (lit 2)))
    (.value (pair 19 true)))
  match run initial (.assign .set (row index) value) with
  | .done .unit after => nativeIs after (.structure 3) 16 (pair 19 true) &&
      nativeIs after (.structure 3) 40 (pair 51 false) &&
      localIs after 0 (.rawSlice (.structure 3) 40 1) && localIs after 1 (i 12) &&
      localIs after 2 (i 1) && localIs after 3 (i 1) &&
      heapFrame initial.heap after.heap 8 16 && callerFrame initial after
  | _ => false

-- Deliberate rejected descriptors/places, not claimed valid constructor
-- inputs. Each failure preserves the executed index marker and skips the RHS.
private def rejected (state : State) (place : Place) (reason : Trap) : Bool :=
  match run state (.assign .set place (rhs (.value (pair 19 true)))) with
  | .trapped actual after => actual == reason && localIs after 2 (i 1) &&
      localIs after 3 (i 0) && heapFrame state.heap after.heap 0 0 && callerFrame state after
  | _ => false

def rejectedBeforeRhs : Bool :=
  rejected initial (row (indexMark 1)) .arrayBounds &&
  rejected initial (row (indexMark (-1))) .arrayBounds &&
  rejected (initial.bindLocal 0 (.rawSlice (.structure 3) 0 1))
    (row (indexMark 0)) .rawMemoryBounds &&
  rejected (initial.bindLocal 0 (.rawSlice (.structure 999) 16 1))
    (row (indexMark 0)) .typeMismatch &&
  rejected initial (.field (row (indexMark 0)) 2) .typeMismatch

def requiredOldRead : Bool :=
  let state := initial.bindLocal 0 (.rawSlice (.scalar (.signed .i32)) 128 1)
  match run state (.assign .add (row (indexMark 0)) (rhs (lit 5))) with
  | .trapped .invalidPointer after => localIs after 2 (i 1) && localIs after 3 (i 0) &&
      heapFrame state.heap after.heap 0 0 && callerFrame state after
  | _ => false

def compoundUninitialized : Bool :=
  let state := initial.bindUninitialized 4
  match run state (.assign .add (.local 4) (rhs (lit 5))) with
  | .trapped .uninitializedLocal after => uninitialized after 4 && localIs after 3 (i 0) &&
      heapFrame state.heap after.heap 0 0 && callerFrame state after
  | _ => false

def plainSelfRead : Bool :=
  let state := initial.bindUninitialized 4
  match run state (.assign .set (.local 4) (.local 4)) with
  | .trapped .uninitializedLocal after => uninitialized after 4 &&
      heapFrame state.heap after.heap 0 0 && callerFrame state after
  | _ => false

def delayedInitialization : Bool :=
  let state := initial.bindUninitialized 4
  let success := match run state (.assign .set (.local 4) (rhs (lit 23))) with
    | .done .unit after => localIs after 4 (i 23) && localIs after 3 (i 1) &&
        heapFrame state.heap after.heap 0 0 && callerFrame state after
    | _ => false
  let failure := match run state (.assign .set (.local 4) (rhs (.local 4))) with
    | .trapped .uninitializedLocal after => uninitialized after 4 && localIs after 3 (i 1) &&
        heapFrame state.heap after.heap 0 0 && callerFrame state after
    | _ => false
  success && failure

def aggregateUninitialized : Bool :=
  let state := initial.bindUninitialized 4
  match run state (.assign .set (.field (.local 4) 0) (rhs (lit 5))) with
  | .trapped .uninitializedLocal after => uninitialized after 4 && localIs after 3 (i 0) &&
      heapFrame state.heap after.heap 0 0 && callerFrame state after
  | _ => false

def descriptorUninitialized : Bool :=
  let state := initial.bindUninitialized 0
  match run state (.assign .set (row (indexMark 0)) (rhs (.value (pair 19 true)))) with
  | .trapped .uninitializedLocal after => uninitialized after 0 &&
      localIs after 2 (i 0) && localIs after 3 (i 0) &&
      heapFrame state.heap after.heap 0 0 && callerFrame state after
  | _ => false

def rhsTrap : Bool :=
  match run initial (.assign .set (row (indexMark 0))
      (rhs (seq (.intrinsic .assert (.value (.boolean false))) (.value (pair 19 true))))) with
  | .trapped .assertionFailed after => localIs after 2 (i 1) && localIs after 3 (i 1) &&
      heapFrame initial.heap after.heap 0 0 && callerFrame initial after
  | _ => false

def rhsExit : Bool :=
  match run initial (.assign .set (row (indexMark 0))
      (rhs (seq (.call 90 [lit 17]) (.value (pair 19 true))))) with
  | .exited 17 after => localIs after 2 (i 1) && localIs after 3 (i 1) &&
      after.world.calls == [.exit] && after.world.standardOutput == [88] &&
      initial.locals == after.locals && initial.nextCell == after.nextCell &&
      heapFrame initial.heap after.heap 0 0
  | _ => false

def arithmeticFailure : Bool :=
  match run initial (.assign .divide (field (indexMark 0)) (rhs (lit 0))) with
  | .trapped .divisionByZero after => localIs after 2 (i 1) && localIs after 3 (i 1) &&
      heapFrame initial.heap after.heap 0 0 && callerFrame initial after
  | _ => false

-- Permission is checked at the post-RHS heap, not at address resolution.
def rhsDeallocates : Bool :=
  let release : Expr := .dealloc (.value (.pointer 8)) (.value (.unsigned .usize 16))
    (.value (.unsigned .usize 8))
  match run initial (.assign .set (field (indexMark 0)) (rhs (seq release (lit 5)))) with
  | .trapped .invalidPointer after => localIs after 2 (i 1) && localIs after 3 (i 1) &&
      (after.heap.block? 8).map Block.live == some false &&
      (after.heap.block? 8).map Block.bytes == (initial.heap.block? 8).map Block.bytes &&
      after.heap.remaining == some 116 && callerFrame initial after
  | _ => false

-- Small kernel reductions complement the executable phase/frame suite.
example : wholeOverwrite = true := by decide
example : plainField = true := by decide
example : compoundUninitialized = true := by decide
example : plainSelfRead = true := by decide
example : aggregateUninitialized = true := by decide

#eval (do
  let cases := [("invalid-old-bool whole overwrite", wholeOverwrite),
    ("plain field preserves invalid sibling", plainField),
    ("compound captures selected old i32", compoundCapturedOld),
    ("descriptor capture and index/RHS order", descriptorCaptured),
    ("bounds/layout/field reject before RHS", rejectedBeforeRhs),
    ("required selected old read precedes RHS", requiredOldRead),
    ("compound uninitialized local precedes RHS", compoundUninitialized),
    ("plain x=x remains uninitialized", plainSelfRead),
    ("successful and failed delayed initialization", delayedInitialization),
    ("aggregate partial initialization rejects", aggregateUninitialized),
    ("descriptor initialization precedes index", descriptorUninitialized),
    ("RHS trap preserves phase effects", rhsTrap), ("RHS exit preserves phase effects", rhsExit),
    ("arithmetic failure preserves RHS effects", arithmeticFailure),
    ("store permission uses post-RHS heap", rhsDeallocates)]
  for (name, passed) in cases do
    unless passed do throw (IO.userError s!"write-place regression: {name}")
  IO.println s!"write-place regressions: {cases.length} passed" : IO Unit)

-- These are rule applications, not full-assignment evaluator reductions.
-- Both phases change caller cells; the store must use the captured address
-- and preserve the exact state reached after those effects.
private def wholeBefore : State :=
  (initial.assignLocal 0 (.rawSlice (.scalar (.signed .i32)) 8 1)).getD initial
private def wholeIndex : Expr :=
  seq (set 0 (.value (.rawSlice (.scalar (.signed .i32)) 32 1))) (lit 0)
private def wholeIndexed : State :=
  (wholeBefore.assignLocal 0 (.rawSlice (.scalar (.signed .i32)) 32 1)).getD wholeBefore
private def markedValue : Expr := seq (set 1 (lit 5)) (lit 99)
private def wholeReady : State :=
  (wholeIndexed.assignLocal 1 (i 5)).getD wholeIndexed
private def fieldIndex : Expr :=
  seq (set 0 (.value (.rawSlice (.structure 3) 40 1))) (lit 0)
private def fieldIndexed : State :=
  (initial.assignLocal 0 (.rawSlice (.structure 3) 40 1)).getD initial
private def fieldReady : State :=
  (fieldIndexed.assignLocal 1 (i 5)).getD fieldIndexed

private theorem initialUnique : HeapBlockBasesUnique initial.heap := by
  intro left leftFound right rightFound same
  simp only [initial, State.bindLocal, State.bindCell,
    List.mem_cons, List.not_mem_nil, or_false] at leftFound rightFound
  rcases leftFound with rfl | rfl | rfl | rfl <;>
    rcases rightFound with rfl | rfl | rfl | rfl <;> first | rfl | cases same

private theorem ninetyNineCodec :
    NativeStoreSpec 64 program (.scalar (.signed .i32)) (i 99) 8 := by
  exact NativeStoreSpec.i32 (fuel := 63) (BitVec.ofNat 32 99)

theorem effectfulWholeRule : ∃ heap,
    RunsExpr program wholeBefore (.assign .set (row wholeIndex) markedValue)
      .unit { wholeReady with heap } ∧
    NativeSnapshot 64 program heap (.scalar (.signed .i32)) 8 (i 99) 8 ∧
    HeapRegionWrite wholeReady.heap heap 8 8 ∧
    ({ wholeReady with heap } : State).local? 0 = some (.rawSlice (.scalar (.signed .i32)) 32 1) ∧
    ({ wholeReady with heap } : State).local? 1 = some (i 5) := by
  have index : RunsExpr program wholeBefore wholeIndex (i 0) wholeIndexed :=
    .ofStable (.ofEval (show evalExpr 8 program wholeBefore wholeIndex =
      .done (i 0) wholeIndexed by rfl)) rfl
  have right : RunsExpr program wholeIndexed markedValue (i 99) wholeReady :=
    .ofStable (.ofEval (show evalExpr 8 program wholeIndexed markedValue =
      .done (i 99) wholeReady by rfl)) rfl
  obtain ⟨heap, run, snapshot, frame⟩ := RunsExpr.assignRawNative
    (before := wholeBefore) (indexed := wholeIndexed) (ready := wholeReady)
    (sourceId := 0) (address := 8) (length := 1) (position := 0) (base := 8)
    (program := program) (indexExpression := wholeIndex) (expression := markedValue)
    rfl index (by decide) rfl ninetyNineCodec (by decide)
    (Heap.Readable.of_loadBytes (bytes := encodeNatLE 4 2 ++ List.replicate 4 165) (by rfl)) initialUnique rfl right
  exact ⟨heap, run, snapshot, frame, rfl, rfl⟩

theorem effectfulFieldRule : ∃ heap,
    RunsExpr program initial (.assign .set (field fieldIndex) markedValue)
      .unit { fieldReady with heap } ∧
    NativeSnapshot 64 program heap (.scalar (.signed .i32)) 16 (i 99) 8 ∧
    HeapRegionWrite fieldReady.heap heap 16 8 ∧
    ({ fieldReady with heap } : State).local? 0 = some (.rawSlice (.structure 3) 40 1) ∧
    ({ fieldReady with heap } : State).local? 1 = some (i 5) := by
  have index : RunsExpr program initial fieldIndex (i 0) fieldIndexed :=
    .ofStable (.ofEval (show evalExpr 8 program initial fieldIndex =
      .done (i 0) fieldIndexed by rfl)) rfl
  have right : RunsExpr program fieldIndexed markedValue (i 99) fieldReady :=
    .ofStable (.ofEval (show evalExpr 8 program fieldIndexed markedValue =
      .done (i 99) fieldReady by rfl)) rfl
  obtain ⟨heap, run, snapshot, frame, _⟩ := RunsExpr.assignRawFieldNative
    (before := initial) (indexed := fieldIndexed) (ready := fieldReady)
    (sourceId := 0) (address := 16) (length := 1) (position := 0) (base := 16) (field := 0)
    (program := program) (indexExpression := fieldIndex) (expression := markedValue)
    rfl index (by decide) rfl rfl rfl rfl ninetyNineCodec (by decide) (by decide)
    (Heap.Readable.of_loadBytes (bytes := i32Bytes 17 ++ List.replicate 4 165) (by rfl)) initialUnique rfl right
  exact ⟨heap, run, snapshot, frame, rfl, rfl⟩

#print axioms effectfulWholeRule
#print axioms effectfulFieldRule

end Lanius.Semantics.WritePlaceTests
