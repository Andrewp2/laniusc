import Lanius.Extraction.CompactOutput.Assignments.Source
import Lanius.Extraction.CompactOutput.Assignments.Domain
import Lanius.Extraction.SemanticTokens.Specification
import Lanius.Separation.I32Prefix

namespace Lanius.Extraction.CompactOutput.Assignments

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.SemanticTokens

theorem stored_pair (assignments : List Assignment) (index : Nat)
    (bound : index < assignments.length) :
    (assignments.flatMap Assignment.words)[index * 2]? = some (Int.ofNat assignments[index].first) ∧
    (assignments.flatMap Assignment.words)[index * 2 + 1]? = some (secondWord assignments[index]) := by
  induction assignments generalizing index with
  | nil => simp at bound
  | cons assignment rest ih =>
    cases index with
    | zero => simp [List.flatMap_cons, stored_fields]
    | succ index =>
      simpa [List.flatMap_cons, stored_fields, Nat.add_mul, Nat.add_assoc] using ih index (by simpa using bound)

/-- Both source index expressions stay within signed i32 and select the
collector's actual two-word record, independently of spare allocation. -/
theorem read_pair (program : Program) (assignments : List Assignment) (index : Nat)
    (input : I32PrefixLocal before 0 inputCell (assignments.flatMap Assignment.words))
    (indexRead : before.local? 7 = some (.signed .i32 index))
    (bound : index < assignments.length) (sizeFit : 2 * assignments.length ≤ 2147483647) :
    Evaluates program before (.index (read 0) firstIndex)
      (.signed .i32 assignments[index].first) before ∧
    Evaluates program before (.index (read 0) secondIndex)
      (.signed .i32 (secondWord assignments[index])) before := by
  have firstBound : index * 2 < (assignments.flatMap Assignment.words).length := by
    rw [assignments_words_length]
    omega
  have secondBound : index * 2 + 1 < (assignments.flatMap Assignment.words).length := by
    rw [assignments_words_length]
    omega
  have firstAddress : Evaluates program before firstIndex (.signed .i32 (index * 2 : Nat)) before :=
    evaluatesNatI32Multiply (leftValue := index) (rightValue := 2) (local_evaluates program indexRead)
      (show Evaluates program before (number 2) (.signed .i32 2) before from ⟨1, rfl⟩) (by omega)
  have secondAddress : Evaluates program before secondIndex (.signed .i32 (index * 2 + 1 : Nat)) before :=
    evaluatesNatI32Add (leftValue := index * 2) (rightValue := 1) firstAddress
      (show Evaluates program before (number 1) (.signed .i32 1) before from ⟨1, rfl⟩) (by omega)
  have firstRun := input.read program firstIndex (index * 2) firstBound firstAddress
  have secondRun := input.read program secondIndex (index * 2 + 1) secondBound secondAddress
  have selected := stored_pair assignments index bound
  simp only [List.getElem?_eq_getElem firstBound, List.getElem?_eq_getElem secondBound,
    Option.some.injEq] at selected
  constructor
  · simpa only [List.get_eq_getElem, selected.1, Int.ofNat_eq_natCast, read] using firstRun
  · simpa only [List.get_eq_getElem, selected.2, read] using secondRun

def fieldsState (before : State) (assignment : Assignment) : State :=
  (before.bindLocal 8 (.signed .i32 assignment.first)).bindLocal 9 (.signed .i32 (secondWord assignment))

/-- The second read occurs after the first lexical declaration. Both values
and the same input prefix survive the two real bindings. -/
theorem initialize_fields (program : Program) (assignments : List Assignment) (index : Nat)
    (wellFormed : StateWellFormed before)
    (input : I32PrefixLocal before 0 inputCell (assignments.flatMap Assignment.words))
    (indexRead : before.local? 7 = some (.signed .i32 index))
    (bound : index < assignments.length) (sizeFit : 2 * assignments.length ≤ 2147483647) :
    Evaluates program before (.index (read 0) firstIndex) (.signed .i32 assignments[index].first) before ∧
    Evaluates program (before.bindLocal 8 (.signed .i32 assignments[index].first))
      (.index (read 0) secondIndex) (.signed .i32 (secondWord assignments[index]))
      (before.bindLocal 8 (.signed .i32 assignments[index].first)) ∧
    StateWellFormed (fieldsState before assignments[index]) ∧
    (fieldsState before assignments[index]).local? 8 = some (.signed .i32 assignments[index].first) ∧
    (fieldsState before assignments[index]).local? 9 = some (.signed .i32 (secondWord assignments[index])) ∧
    I32PrefixLocal (fieldsState before assignments[index]) 0 inputCell (assignments.flatMap Assignment.words) := by
  let firstState := before.bindLocal 8 (.signed .i32 assignments[index].first)
  have firstWF : StateWellFormed firstState := bindLocal_preserves_well_formed _ _ _ wellFormed
  have firstInput := input.bindLocal wellFormed 8 (.signed .i32 assignments[index].first) (by decide)
  have indexAfter : firstState.local? 7 = some (.signed .i32 index) :=
    (bindLocal_preserves_other_local wellFormed (by decide : (8 : VarId) ≠ 7)).trans indexRead
  have secondRun := (read_pair program assignments index firstInput indexAfter bound sizeFit).2
  exact ⟨(read_pair program assignments index input indexRead bound sizeFit).1, secondRun,
    bindLocal_preserves_well_formed _ _ _ firstWF,
    (bindLocal_preserves_other_local firstWF (by decide : (9 : VarId) ≠ 8)).trans
      (bindLocal_finds_local before _ _ wellFormed),
    bindLocal_finds_local firstState _ _ firstWF,
    firstInput.bindLocal firstWF 9 (.signed .i32 (secondWord assignments[index])) (by decide)⟩

end Lanius.Extraction.CompactOutput.Assignments
