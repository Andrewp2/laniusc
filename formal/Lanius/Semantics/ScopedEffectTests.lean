import Lanius.Semantics.ScopedEffect
import Lanius.Semantics.CallProof
import Lanius.Semantics.RawSlice
import Lanius.Semantics.PureProof

namespace Lanius.Semantics.ScopedEffectTests

open Lanius.Core Lanius.Memory

private def before : State := { heap := { blocks := [
  { base := 4, size := 4, alignment := 4, bytes := [0, 0, 0, 0], owned := true }], nextAddress := 8 } }
-- A raw view leaves the heap as it was.
private def borrowed : Heap := before.heap
private def pointer : Value := .rawSlice (.scalar (.signed .i32)) 4 1
private def declaration : Function := {
  id := 7, parameters := [], returnType := .slice (.scalar (.signed .i32))
  body := some (.returnValue (some (.i32SliceFromRawParts (.value (.pointer 4)) (.value (.signed .i32 1))))) }
private def program : Program := { functions := [declaration] }
private def relation (_ : Heap) (after : Heap) : Prop := after = borrowed

-- The applied rule term carries proved laws. The actual constructor changes
-- ownership, and call/return composition retains that effect after scope exit.
theorem retainsOwnership : ∃ after, RunsExpr program before (.call 7 []) pointer after ∧
    MemoryEffect relation before after := by
  have formed : before.CellsWellFormed := by simp [State.CellsWellFormed, before]
  core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable relation)) declaration as callee
  have construct : mapRawI32Slice callee 4 1 = .done pointer { callee with heap := borrowed } :=
    mapRawI32Slice_of_block (state := callee) (address := 4) 1 (by decide) rfl (by decide) (by decide)
      (by decide)
  have run := RunsExpr.rawSliceFromParts (program := program)
    (RunsExpr.ofStable StableExpr.value rfl) (RunsExpr.ofStable StableExpr.value rfl) construct rfl
  apply RunsStmt.returnEffect
  core_state current
  exact ⟨{ callee with heap := borrowed }, run,
    ⟨⟨[], by simp only [List.append_nil]; rfl, Nat.le_refl _, by simp⟩, rfl, rfl, rfl⟩⟩

-- A bound result remains usable after the initializer changes heap ownership.
-- This would fail if the composition silently treated the call as read-only.
theorem retainsInitializerOwnership : ∃ after, RunsStmt program before
    (.letLocal 10 (.slice (.scalar (.signed .i32))) (.call 7 []) (.returnValue (some (.local 10))))
    (.returned (some pointer)) after ∧ MemoryEffect relation before after := by
  apply RunsStmt.letMemoryEffect retainsOwnership
  intro ready run effect
  have cells := effect.1
  have formed := cells.after_cellsWellFormed (show before.CellsWellFormed by simp [before, State.CellsWellFormed])
  core_pure

-- Scope laws cannot manufacture a body postcondition. False is scope-stable,
-- but there is no proved execution carrying this impossible memory effect.
example : True := by
  have formed : before.CellsWellFormed := by simp [State.CellsWellFormed, before]
  fail_if_success
    suffices wrong : ∃ after, RunsExpr program before (.call 7 []) pointer after ∧
        MemoryEffect (fun _ _ => False) before after from True.intro
    core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) declaration as callee
    core_contract
  trivial

#print axioms retainsOwnership
#print axioms retainsInitializerOwnership
#print axioms Lanius.Semantics.RunsExpr.callEffect
#print axioms Lanius.Semantics.RunsStmt.guardEffectFalse
#print axioms Lanius.Semantics.RunsExpr.matchEffect

end Lanius.Semantics.ScopedEffectTests
