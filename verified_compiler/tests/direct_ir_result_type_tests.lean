import verified_compiler.tests.direct_ir_result_type

namespace IRResultTypeTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRTypeRefProof IRResultTypeProof

private def bytes := encodeNatLE 4 1 ++ List.replicate 12 165
private def sample : State := { heap := { blocks := [{
  base := 16, size := 32, alignment := 8, bytes := bytes ++ bytes }], nextAddress := 48 } }
private def events : Value := .unit
private theorem width : NativeLayout.valueWords? extractedProgram referenceType = some 2 := by decide +kernel
private def slot : Slot sample := {
  position := 0, capacity := 2, types := 40, address := 32
  bound := by decide
  location := by
    have layout := width
    dsimp only [referenceType] at layout ⊢
    simp only [rawSliceElementAddress?, layout]
    rfl
  room := Heap.Readable.of_loadBytes (show sample.heap.loadBytes 32 16 = .ok bytes from rfl) }

-- Every valid native constructor/payload, not just one fixed primitive.
-- The event descriptor is deliberately unusable: it is never accessed.
theorem recordsValid (kind : Reference) (valid : 0 ≤ typeCode kind) :
    ∃ after, RunsExpr extractedProgram sample (slot.call events kind) (.boolean true) after ∧
      readNativeValue 64 extractedProgram after.heap referenceType 32 = .ok (referenceValue kind) ∧
      after.heap.loadBytes 16 16 = .ok bytes := by
  obtain ⟨after, run, _, _, _, snapshot, effect⟩ := actualRecord slot kind valid
    (by simp [State.CellsWellFormed, sample])
    (by intro left hl right hr _; simp only [sample, List.mem_singleton] at hl hr; exact hl.trans hr.symm) rfl
  exact ⟨after, run, snapshot.read,
    effect.loadBytes (show sample.heap.loadBytes 16 16 = .ok bytes from rfl) (Or.inl (by decide))⟩

example : ∃ after, RunsExpr extractedProgram {} (call .unit .unit true 0 0 .I32)
    (.boolean false) after ∧ PureFrame {} after :=
  actualOutOfBounds _ _ _ (Or.inr (by decide)) (by simp [State.CellsWellFormed])

example : ∃ after, RunsExpr extractedProgram {} (call .unit .unit false 1 0 .Void)
    (.boolean true) after ∧ PureFrame {} after :=
  actualDisabled _ _ _ ⟨by decide, by decide⟩ (by decide) (by simp [State.CellsWellFormed])

#print axioms recordsValid

#eval (do
  let kinds : List Reference := [.Invalid, .Void, .I32, .Bool, .Usize, .Pointer, .String, .Slice,
    .Nominal 0, .Nominal 1073741807, .Nominal (-1), .Nominal 1073741808,
    .Nominal (-2147483648), .Nominal 2147483647,
    .NominalSlice 0, .NominalSlice 1073741807, .NominalSlice (-1), .NominalSlice 1073741808]
  for enabled in [false, true] do
    for kind in kinds do
      for position in [-1, 0, 1, 2] do
        let accepted := decide (0 ≤ position ∧ position < 2) && isValidResult kind
        let .done answer after := evalExpr 200 extractedProgram sample
          (call events (.rawSlice referenceType 40 2) enabled 2 position kind)
          | throw (IO.userError "result-type recording trapped")
        unless answer == .boolean accepted do throw (IO.userError "recording accepted the wrong inputs")
        if accepted && enabled then
          let .ok stored := readRawSliceIndex extractedProgram after referenceType 40 2 position.toNat
            | throw (IO.userError "recorded type became unreadable")
          unless stored == referenceValue kind do throw (IO.userError "nominal type payload changed")
          let other := 1 - position
          let address := if other == 0 then 32 else 16
          let .ok untouched := after.heap.loadBytes address 16
            | throw (IO.userError "neighboring annotation became unreadable")
          unless untouched == bytes do
            throw (IO.userError "recording changed a neighboring annotation")
        else
          let .ok untouched := after.heap.loadBytes 16 32
            | throw (IO.userError "annotation storage became unreadable")
          unless untouched == bytes ++ bytes do
            throw (IO.userError "rejection or disabled recording changed memory") : IO Unit)

end IRResultTypeTests
