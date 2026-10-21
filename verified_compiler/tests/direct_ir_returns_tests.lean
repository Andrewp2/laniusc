import verified_compiler.tests.direct_ir_returns

namespace IRReturnsFixtures
open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRReturnsProof

private def leafTag (returns : Bool) : Tag := if returns then .returnVoid else .skip
private def eventOrdinal (returns : Bool) : Nat := match (leafTag returns).event .unit with
  | .enumeration _ ordinal _ => ordinal
  | _ => 0
private def sample (returns : Bool) : State := { heap := { blocks := [
  { base := 16, size := 40, alignment := 8,
    bytes := encodeNatLE 4 (eventOrdinal returns) ++ List.replicate 36 0 },
  { base := 64, size := 4, alignment := 4, bytes := i32Bytes 1 }], nextAddress := 68 } }
private def view : View := { count := 1, fits := by decide, events := 48, ends := 64 }
private theorem eventWidth : NativeLayout.valueWords? extractedProgram (.enumeration 217) = some 5 := by decide +kernel

private def physicalLeaf (returns : Bool) : Node view (sample returns).heap 0 1 (leafTag returns) := by
  cases returns <;> constructor
  case false.read =>
    change readRawSliceIndex extractedProgram { heap := (sample false).heap } (.enumeration 217) 48 1 0 = .ok (Tag.skip.event .unit)
    simp only [readRawSliceIndex, rawSliceElementAddress?, eventWidth]; rfl
  case true.read =>
    change readRawSliceIndex extractedProgram { heap := (sample true).heap } (.enumeration 217) 48 1 0 = .ok (Tag.returnVoid.event .unit)
    simp only [readRawSliceIndex, rawSliceElementAddress?, eventWidth]; rfl
  all_goals first | exact .unit | exact fun _ => 0 | rfl | (simp [view, leafTag, Tag.arity])

theorem skipRepresented : Native view (sample false).heap .skip 0 1 :=
  .skip (physicalLeaf false)
theorem returnVoidRepresented : Native view (sample true).heap (.returnValue none) 0 1 :=
  .returnVoid (physicalLeaf true)

theorem skipCall : ∃ after, RunsExpr extractedProgram (sample false) (returnCall view 0)
    (.boolean false) after ∧ PureFrame (sample false) after := by
  simpa [result] using actualReturns skipRepresented rfl (by simp [State.CellsWellFormed, sample])
theorem returnVoidCall : ∃ after, RunsExpr extractedProgram (sample true) (returnCall view 0)
    (.boolean true) after ∧ PureFrame (sample true) after := by
  simpa [result] using actualReturns returnVoidRepresented rfl (by simp [State.CellsWellFormed, sample])

#print axioms skipRepresented
#print axioms returnVoidRepresented
#print axioms skipCall
#print axioms returnVoidCall
end IRReturnsFixtures
