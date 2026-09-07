import Lanius.Extraction.CanonicalTokens.Ascii.Function
import Lanius.CallContracts

namespace Lanius.Extraction.CanonicalTokens.Ascii

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

/-- Calling the source-checked matcher is correct in an arbitrary well-formed
caller. Parameter binding and caller restoration are part of the proof. -/
theorem evaluates_call (program : Program) (functionId : FunctionId) (before : State)
    (sourceCell : CellId) (source : List Int) (start : Nat)
    (text : String) (spelling : List UInt8) (arguments : List Expr)
    (found : program.function? functionId = some (sourceFunction functionId))
    (wellFormed : StateWellFormed before)
    (sourceContents : before.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) })
    (argumentsResult : ArgumentsEvaluateTo program before arguments [
      .slice (.scalar (.signed .i32)) sourceCell [] 0 source.length,
      .signed .i32 start, .string text, .signed .i32 spelling.length] before)
    (capacity : start + spelling.length ≤ source.length)
    (bounded : source.length ≤ 2147483647)
    (countBound : spelling.length + 3 ≤ 2147483647)
    (padded : (Lanius.World.utf8Bytes text).length = ((spelling.length + 3) / 4) * 4)
    (prefixBytes : (Lanius.World.utf8Bytes text).take spelling.length = spelling) :
    ∃ after, Evaluates program before (.call functionId arguments)
      (.boolean (matchesBytes source start spelling)) after ∧
      StateWellFormed after ∧ after.locals = before.locals ∧ after.world = before.world ∧
      (∀ cell, cell < before.nextCell → after.cellEntry? cell = before.cellEntry? cell) ∧
      CellDomainExtension before after ∧ before.nextCell ≤ after.nextCell := by
  let slice := Value.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length
  let bindings : List (VarId × Value) := [
    (0, slice), (1, .signed .i32 start), (2, .string text), (3, .signed .i32 spelling.length)]
  let entered := enterCall before bindings
  have enteredWF : StateWellFormed entered := enterCall_preserves_wellFormed wellFormed
  have enterEffect := enterCall_effect before bindings
  have sourceOld := StateWellFormed.cell_lt_next_of_entry wellFormed sourceContents
  have sourceReady : entered.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) } :=
    (enterEffect.oldCells sourceCell sourceOld (by simp [CellSet.empty])).trans sourceContents
  have sourceLocal : entered.local? 0 = some slice :=
    enterCall_local_of_binding before [] [(1, .signed .i32 start), (2, .string text),
      (3, .signed .i32 spelling.length)] 0 slice wellFormed (by
        intro binding member
        simp only [List.mem_cons, List.not_mem_nil, or_false] at member
        rcases member with rfl | rfl | rfl <;> simp)
  have startLocal : entered.local? 1 = some (.signed .i32 start) :=
    enterCall_local_of_binding before [(0, slice)] [(2, .string text),
      (3, .signed .i32 spelling.length)] 1 (.signed .i32 start) wellFormed
        (by
          intro binding member
          simp only [List.mem_cons, List.not_mem_nil, or_false] at member
          rcases member with rfl | rfl <;> simp)
  have textLocal : entered.local? 2 = some (.string text) :=
    enterCall_local_of_binding before [(0, slice), (1, .signed .i32 start)]
      [(3, .signed .i32 spelling.length)] 2 (.string text) wellFormed
        (by intro binding member; simp_all)
  have lengthLocal : entered.local? 3 = some (.signed .i32 spelling.length) :=
    enterCall_local_of_binding before [(0, slice), (1, .signed .i32 start), (2, .string text)]
      [] 3 (.signed .i32 spelling.length) wellFormed (by simp)
  obtain ⟨completed, run, completedWF, _, world, oldCells, domain, nextCell⟩ := executes_sourceBody
    program entered sourceCell source start text spelling enteredWF sourceLocal sourceReady
      startLocal textLocal lengthLocal capacity bounded countBound padded prefixBytes
  have bound : bindParameters (sourceFunction functionId).parameters [slice,
      .signed .i32 start, .string text, .signed .i32 spelling.length] = some bindings := rfl
  have called := evaluatesCallReturned argumentsResult found bound rfl run
  have completeDomain := enterEffect.domain.trans domain
  refine ⟨restoreLocals before completed, called,
    completeDomain.restoreLocals_wellFormed wellFormed completedWF, rfl,
    world.trans enterEffect.world, ?_, completeDomain.restoreLocals,
    Nat.le_trans enterEffect.nextCell nextCell⟩
  intro cell old
  exact (oldCells cell (Nat.lt_of_lt_of_le old enterEffect.nextCell)).trans
    (enterEffect.oldCells cell old (by simp [CellSet.empty]))

end Lanius.Extraction.CanonicalTokens.Ascii
