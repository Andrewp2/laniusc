import Lanius.Extraction.OutputPacking.Expression
import Lanius.Extraction.OutputPacking.Store
import Lanius.Extraction.OutputPacking.Read
import Lanius.Semantics.Branch
import Lanius.Semantics.RawStore
import Lanius.Semantics.ExpressionProof
import Lanius.Semantics.StatementProof
import Lanius.Semantics.CallProof
import Lanius.Semantics.CallRun
import Lanius.Semantics.RawSlice
import GeneratedDirectCore

namespace OutputByteProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction.OutputPacking

-- The call proofs below compose the actual body, including this destination.
private def store? : Stmt → Option Expr
  | .sequence first second => store? first <|> store? second
  | .letLocal _ _ _ body => store? body
  | .expression store@(.assign .set _ _) => some store
  | _ => none

private def actualBody : Stmt :=
  Extracted.«verified::lean_output».Functions.«byte».core.body.getD .skip

private def actualStore : Expr := (store? actualBody).getD (.value .unit)

private def actualGuard : Expr :=
  match actualBody with
  | .sequence (.ifThenElse condition _ _) _ => condition
  | _ => .value (.boolean true)

structure ByteBuffer (state : State) where
  address : Nat
  words : Nat
  capacity : Nat
  cursor : Nat
  capacityFits : capacity < 2 ^ 31
  available : cursor < capacity
  storage : capacity ≤ words * 4
  readable : state.heap.Readable (address + (cursor / 4) * 4) 4

def byteCall (output : Value) (capacity position value : Int) : Expr :=
  .call Extracted.«verified::lean_output».Functions.«byte».core.id
    ([output, .signed .i32 capacity, .signed .i32 position, .signed .i32 value].map Expr.value)

/-- The public contract derives the store and return from buffer facts, without
    assumptions about internal locals or successful intermediate execution. -/
theorem actualCall_writes (inputs : ByteBuffer state) (byte : Fin 256)
    (formed : state.CellsWellFormed) (noViews : state.i32ArrayViews = [])
    (unique : Memory.HeapBlockBasesUnique state.heap) :
    ∃ after, RunsExpr extractedProgram state
        (byteCall (.rawSlice (.scalar (.signed .i32)) inputs.address inputs.words)
          inputs.capacity inputs.cursor byte.val)
        (.signed .i32 (inputs.cursor + 1 : Nat)) after ∧
      Memory.ByteWrite state.heap after.heap (inputs.address + inputs.cursor) (UInt8.ofNat byte.val) ∧
      FreshCellFrame state after ∧ after.world = state.world ∧ after.i32ArrayViews = state.i32ArrayViews := by
  rcases inputs with ⟨address, words, capacity, cursor, capacityFits, available, storage, readable⟩
  obtain ⟨word, contents⟩ := readableWord readable
  let encoded := BitVec.ofNat 8 byte.val
  have encodedNat : encoded.toNat = byte.val := Nat.mod_eq_of_lt byte.isLt
  let bindings : List (VarId × Value) := [(100, .rawSlice (.scalar (.signed .i32)) address words),
    (106, .signed .i32 capacity), (110, .signed .i32 cursor), (114, .signed .i32 byte.val)]
  let callee := ({ state with locals := [] }).bindLocals bindings
  have calleeFormed : callee.CellsWellFormed := formed.bindLocals bindings
  have cursorFits : cursor < 2 ^ 31 := Nat.lt_trans available capacityFits
  let lane : Fin 4 := ⟨cursor % 4, Nat.mod_lt _ (by decide)⟩
  have byteBound := byte.isLt
  have byteValue : (encoded.setWidth 32).toInt = (byte.val : Int) := by
    rw [BitVec.toInt_setWidth, ← wrapSigned_bmod, encodedNat]
    exact wrapSigned_i32_nat_lt _ _ (by omega)
  let indexed := callee.bindLocal 152 (.signed .i32 (cursor / 4 : Nat))
  let shifted := indexed.bindLocal 167 (.signed .i32 (lane.val * 8 : Nat))
  let ready := shifted.bindLocal 192 (.signed .i32 ((255 : BitVec 32) <<< (lane.val * 8)).toInt)
  have maskStep : evalBinaryValue extractedProgram.target .shiftLeft
      (.signed .i32 255) (.signed .i32 (lane.val * 8 : Nat)) =
        .ok (.signed .i32 ((255 : BitVec 32) <<< (lane.val * 8)).toInt) := by
    simpa only [evalBinaryValue, BEq.rfl, ↓reduceIte,
      show extractedProgram.target = .x86_64 by rfl,
      show (255 : BitVec 32).toInt = 255 by decide] using
      evalSignedBinary_i32_shiftLeft (255 : BitVec 32) (lane.val * 8) (by omega)
  obtain ⟨heap, stored, effect⟩ := Lanius.Extraction.OutputPacking.storeByte
    state.heap _ word lane encoded unique contents
  have storeRun : StableExpr 6 extractedProgram ready actualStore .unit { ready with heap } := by
    apply StableExpr.assignRawI32 (before := ready) (indexed := ready) (ready := ready)
      (length := words) (threshold := 5) (indexFuel := 1)
      (by core_local) (.local (by core_local))
      (by omega) noViews ?_ stored
    apply byteExpression_evaluates word lane encoded rfl
    · exact StableExpr.rawSliceIndex (state := ready) (length := words) (by core_local) (by core_local)
        (readRawSliceIndex_i32Bytes extractedProgram ready (by omega) contents)
    all_goals
      intro fuel enough
      apply StableExpr.local
      try rw [byteValue]
      core_local
      omega
  have guardRun : StableExpr 5 extractedProgram callee actualGuard (.boolean false) callee := by core_guard
  have run : RunsStmt extractedProgram callee actualBody
      (.returned (some (.signed .i32 (cursor + 1 : Nat))))
      (restoreLocals callee { ready with heap }) := by core_stmt_forward
  refine ⟨restoreLocals state { ready with heap },
    RunsExpr.call (completed := restoreLocals callee { ready with heap })
      (by core_lookup) rfl (RunsExprs.values _) rfl run, ?_, ?_, rfl, rfl⟩
  · have location : address + cursor / 4 * 4 + lane.val = address + cursor := by dsimp [lane]; omega
    rw [location] at effect
    exact effect
  · have parameters : FreshCellFrame state callee :=
      FreshCellFrame.bindLocals { state with locals := [] } bindings
    exact (parameters.trans ((FreshCellFrame.bindLocal callee 152 _).trans
      ((FreshCellFrame.bindLocal indexed 167 _).trans (FreshCellFrame.bindLocal shifted 192 _)))).restoreLocals

/-- Rejection does not read the output buffer and preserves caller state,
    except for fresh parameter cells permitted by the call semantics. -/
theorem actualCall_rejects (state : State) (output : Value) (capacity position value : Int)
    (formed : state.CellsWellFormed)
    (bad : position < 0 ∨ position ≥ capacity ∨ value < 0 ∨ value > 255) :
    ∃ after, RunsExpr extractedProgram state (byteCall output capacity position value)
      (.signed .i32 (-1)) after ∧ PureFrame state after := by
  core_call Extracted.«verified::lean_output».Functions.«byte».core
  core_stmt

#print axioms actualCall_writes
#print axioms actualCall_rejects

-- Inhabited success contract: negative, nonzero data, a nonzero word index,
-- neighboring bytes, a separate allocation, aliases, and invalid addresses.
private def sample : State :=
  ({ heap := { blocks := [
      { base := 4, size := 8, alignment := 4, bytes := [11, 22, 33, 44, 255, 255, 255, 255] },
      { base := 16, size := 1, alignment := 1, bytes := [77] }], nextAddress := 17 } } : State).bindLocals
    [(100, .rawSlice (.scalar (.signed .i32)) 4 2), (152, .signed .i32 1),
     (192, .signed .i32 65280), (114, .signed .i32 37), (167, .signed .i32 8)]

-- Start with the actual raw-parts constructor; it changes only ownership,
-- without creating a copied array or a registered view.
private def mapped : State := { sample with heap := { sample.heap with
  blocks := sample.heap.blocks.map fun block =>
    if block.base == 4 then { block with owned := false } else block } }

private def sampleBuffer (lane : Fin 4) : ByteBuffer mapped := {
  address := 4, words := 2, capacity := 8, cursor := 4 + lane.val,
  capacityFits := by decide, available := by omega, storage := by decide,
  readable := Memory.Heap.Readable.of_loadBytes (by
    rw [show (4 + lane.val) / 4 = 1 by omega]; rfl) }

example (lane : Fin 4) (byte : BitVec 8) :
    mapRawI32Slice sample 4 2 =
      .done (.rawSlice (.scalar (.signed .i32)) 4 2) mapped ∧
    ∃ after, RunsExpr extractedProgram mapped
        (byteCall (.rawSlice (.scalar (.signed .i32)) 4 2) 8 (4 + lane.val : Nat) byte.toNat)
        (.signed .i32 (5 + lane.val : Nat)) after ∧
      Memory.ByteWrite mapped.heap after.heap (8 + lane.val) (UInt8.ofBitVec byte) ∧
      after.local? 100 = some (.rawSlice (.scalar (.signed .i32)) 4 2) := by
  refine ⟨by simpa [mapped, sample, Memory.replaceBlock,
    State.bindLocals, State.bindLocal, State.bindCell] using
    (mapRawI32Slice_of_block (state := sample) (address := 4) 2 (by decide) rfl rfl rfl rfl), ?_⟩
  obtain ⟨after, run, effect, cells, _⟩ := actualCall_writes (sampleBuffer lane) ⟨byte.toNat, byte.isLt⟩ (by
    simp [State.CellsWellFormed, mapped, sample, State.bindLocals, State.bindLocal, State.bindCell]) rfl (by
    simp [Memory.HeapBlockBasesUnique, mapped, sample,
      State.bindLocals, State.bindLocal, State.bindCell])
  refine ⟨after, ?_, ?_, cells.localFound run.choose_spec.2 100 _ rfl⟩
  · simpa [sampleBuffer, show (4 + (lane.val : Int) + 1) = 5 + lane.val by omega] using run
  · simpa [sampleBuffer, ← Nat.add_assoc, UInt8.ofNat, UInt8.ofBitVec] using effect

example : ∃ after, RunsExpr extractedProgram mapped
    (byteCall (.rawSlice (.scalar (.signed .i32)) 4 2) 8 5 37) (.signed .i32 6) after ∧
    after.heap.loadByte 8 1 = .ok 37 ∧ after.heap.loadByte 9 0 = .ok 37 ∧
    after.heap.loadByte 8 0 = .ok 255 ∧ after.heap.loadByte 4 0 = .ok 11 ∧
    after.heap.loadByte 16 0 = .ok 77 ∧ after.heap.loadByte 0 0 = .error .invalidPointer := by
  obtain ⟨after, run, effect, _⟩ := actualCall_writes (sampleBuffer ⟨1, by decide⟩) 37 (by
    simp [State.CellsWellFormed, mapped, sample, State.bindLocals, State.bindLocal, State.bindCell]) rfl (by
    simp [Memory.HeapBlockBasesUnique, mapped, sample, State.bindLocals, State.bindLocal, State.bindCell])
  refine ⟨after, run, ?_⟩
  simp only [effect.reads]
  exact ⟨rfl, rfl, rfl, rfl, rfl, rfl⟩

end OutputByteProof
