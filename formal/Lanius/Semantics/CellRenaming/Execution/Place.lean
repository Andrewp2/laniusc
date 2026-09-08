import Lanius.Semantics.CellRenaming.Execution.Step
import Lanius.Semantics.CellRenaming.Projection
import Std.Tactic

namespace Lanius.Semantics.CellRenaming.Execution
open Lanius.Core

theorem place {rename : Permutation boundary} (step : Step fuel rename program)
    (before : State) (input : Place) (result : ResolvedPlace) (after : State)
    (ready : boundary ≤ before.nextCell)
    (evaluated : evalPlace (fuel + 1) program before input = .done result after) :
    evalPlace (fuel + 1) program (state rename.forward before) (CellRenaming.place rename.forward input) =
      .done (resolvedPlace rename result) (state rename.forward after) ∧ boundary ≤ after.nextCell := by
  cases input with
  | «local» id =>
      simp only [CellRenaming.place, evalPlace, cellId] at evaluated ⊢
      cases found : before.cellId? id with
      | none => simp [found] at evaluated
      | some root =>
          simp only [found, Option.map, cellEntry] at evaluated ⊢
          cases entry : before.cellEntry? root with
          | none => simp [entry] at evaluated
          | some contents =>
              simp only [entry, Outcome.done.injEq] at evaluated
              obtain ⟨rfl, rfl⟩ := evaluated
              exact ⟨by simp [entry, cell, resolvedPlace], ready⟩
  | field base field =>
      simp only [CellRenaming.place, evalPlace] at evaluated ⊢
      cases baseRun : evalPlace fuel program before base with
      | done resolved next =>
          obtain ⟨transport, nextReady⟩ := step.place ready baseRun
          rw [transport]
          simp only [baseRun] at evaluated
          cases contents : resolved.value with
          | none => simp [contents] at evaluated
          | some entry =>
              cases entry <;> simp only [contents] at evaluated
              all_goals try contradiction
              case «structure» id fields =>
                cases selected : fields[field]? with
                | none => simp [selected] at evaluated
                | some entry =>
                    simp only [selected, Outcome.done.injEq] at evaluated
                    obtain ⟨rfl, rfl⟩ := evaluated
                    exact ⟨by simp [resolvedPlace, contents, value, values_eq_map,
                      List.getElem?_map, selected], nextReady⟩
      | _ => simp [baseRun] at evaluated
  | index base indexExpression =>
      simp only [CellRenaming.place, evalPlace] at evaluated ⊢
      cases baseRun : evalPlace fuel program before base with
      | done resolved afterBase =>
          obtain ⟨transport, baseReady⟩ := step.place ready baseRun
          rw [transport]
          simp only [baseRun] at evaluated
          cases contents : resolved.value with
          | none => simp [contents] at evaluated
          | some entry =>
              cases entry <;> simp only [contents] at evaluated
              all_goals try contradiction
              all_goals
                simp only [resolvedPlace, contents, Option.map, value, values_eq_map]
                cases indexRun : evalExpr fuel program afterBase indexExpression with
                | done indexValue afterIndex =>
                    obtain ⟨indexTransport, indexReady⟩ := step.expression baseReady indexRun
                    rw [indexTransport]
                    simp only [indexRun] at evaluated
                    simp only [integerIndex, CellRenaming.sliceValues, List.getElem?_map]
                    repeat' first
                      | split at evaluated
                      | simp_all only [Option.map, Except.map, List.getElem?_map,
                          values_eq_map, Outcome.done.injEq]
                    all_goals grind only [resolvedPlace]
                | _ => simp [indexRun] at evaluated
      | _ => simp [baseRun] at evaluated

end Lanius.Semantics.CellRenaming.Execution
