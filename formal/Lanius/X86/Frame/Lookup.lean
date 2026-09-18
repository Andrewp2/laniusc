import Lanius.X86.Source.Lookup
import Lanius.X86.Buffer.Reservation
import Lanius.X86.Buffer.Locals
import Lanius.Separation.LocalStore

namespace Lanius.X86.Frame.Lookup

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

def arguments (work : Value) (active key : Int) : List Value :=
  [work, .signed .i32 active, .signed .i32 key]

/-- Lookup is lexical shadowing: the greatest active matching binding wins.
The predicate specifies the result without running a second search algorithm. -/
def Correct (workspace : List Int) (active : Nat) (key : Int) : Option Nat → Prop
  | none => ∀ index, index < active → workspace[16 + index]? ≠ some key
  | some index => index < active ∧ workspace[16 + index]? = some key ∧
      ∀ later, index < later → later < active → workspace[16 + later]? ≠ some key

def result : Option Nat → Int | none => -1 | some index => index
def completion : Option Nat → Completion
  | none => .next
  | some index => .returned (some (.signed .i32 index))

theorem Correct.extend (correct : Correct workspace active key answer)
    (absent : workspace[16 + active]? ≠ some key) : Correct workspace (active + 1) key answer := by
  cases answer with
  | none =>
      intro index inside
      by_cases last : index = active
      · simpa only [last] using absent
      · exact correct index (by omega)
  | some index =>
      refine ⟨by have := correct.1; omega, correct.2.1, ?_⟩
      intro later higher inside
      by_cases last : later = active
      · simpa only [last] using absent
      · exact correct.2.2 later higher (by omega)

theorem Correct.unique (first : Correct workspace active key left)
    (second : Correct workspace active key right) : left = right := by
  cases left with
  | none =>
      cases right with
      | none => rfl
      | some right => exact False.elim (first right second.1 second.2.1)
  | some left =>
      cases right with
      | none => exact False.elim (second left first.1 first.2.1)
      | some right =>
          by_cases equal : left = right
          · exact congrArg some equal
          · have order : left < right ∨ right < left := by omega
            rcases order with less | greater
            · exact False.elim (first.2.2 right less second.1 second.2.1)
            · exact False.elim (second.2.2 left greater first.1 first.2.1)

theorem positive (program : Program) (position : Nat)
    (found : before.local? 3 = some (.signed .i32 position)) :
    Evaluates program before Source.Lookup.positive (.boolean (decide (0 < position))) before := by
  apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program found)
    (show Evaluates program before (number 0) (.signed .i32 0) before from ⟨1, rfl⟩)
  simp [evalBinaryValue, evalSignedBinary]

theorem key_matches (checked : Source.Lookup.Checked program) (position : Nat)
    (sliceRead : before.local? 0 = some (.slice i32 work [] 0 workspace.length))
    (keyRead : before.local? 2 = some (.signed .i32 key))
    (positionRead : before.local? 3 = some (.signed .i32 position))
    (backing : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (inside : 16 + position < workspace.length) (bounded : 16 + position ≤ 2147483647) :
    Evaluates program.core before (Source.Lookup.sameKey checked.header.id)
      (.boolean (decide (workspace[16 + position] = key))) before := by
  have header := checked.header.evaluates (before := before)
  rw [checked.value] at header
  have index := evaluatesNatI32Add (leftValue := 16) (rightValue := position) header
    (local_evaluates program.core positionRead) bounded
  have entry := evaluatesSignedI32SliceIndex program.core before before before workspace (read 0)
    (.binary .add (.constant checked.header.id) (read 3)) work (16 + position) inside
    (local_evaluates program.core sliceRead) index backing
  apply evaluatesEagerBinary (by decide) (by decide) entry (local_evaluates program.core keyRead)
  simp only [evalBinaryValue, scalarEqual, beq_self_eq_true, ↓reduceIte, Except.ok.injEq, Value.boolean.injEq]
  apply Bool.eq_iff_iff.mpr
  simp

/-- Execute the actual reverse scan. Only its fresh index local changes;
the original arguments and complete workspace remain available at each step. -/
theorem loop (checked : Source.Lookup.Checked program) (remaining : Nat)
    (wellFormed : StateWellFormed before)
    (locals : Locals (arguments (.slice i32 work [] 0 workspace.length) active key) frontier before)
    (fresh : frontier ≤ temporary)
    (owned : (Assertion.localPointsTo 3 temporary (some (.signed .i32 remaining))).holds before)
    (backing : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (room : 16 + remaining ≤ workspace.length) (bounded : 16 + remaining ≤ 2147483647) :
    ∃ answer after, Executes program.core before (Source.Lookup.loop checked.header.id) (completion answer) after ∧
      Correct workspace remaining key answer ∧
      CellEffect (CellSet.singleton temporary) before after ∧ HeapFrame before after := by
  induction remaining generalizing before with
  | zero =>
      have guard := positive program.core 0 (Assertion.localPointsTo_local 3 temporary _ before owned)
      exact ⟨none, before, executesWhileFalse guard, by intro index inside; omega,
        CellEffect.refl wellFormed, HeapFrame.refl before⟩
  | succ remaining ih =>
      have guard := positive program.core (remaining + 1) (Assertion.localPointsTo_local 3 temporary _ before owned)
      simp only [Nat.zero_lt_succ, decide_true] at guard
      have distinct : temporary ≠ work := local_cell_ne_of_distinct_value
        (Assertion.localPointsTo_local 3 temporary _ before owned) backing (by intro same; cases same) owned.1
      obtain ⟨decremented, decrementRun, nextOwned, effect, heap⟩ := evaluatesDecrementOwnedI32Local wellFormed owned (by omega)
      have nextLocals := locals.fresh wellFormed effect fresh
      have nextBacking := effect.preserves_entry wellFormed backing (Ne.symm distinct)
      have within : 16 + remaining < workspace.length := by omega
      have matched := key_matches checked remaining (nextLocals.found ⟨0, by simp [arguments]⟩)
        (nextLocals.found ⟨2, by simp [arguments]⟩)
        (Assertion.localPointsTo_local 3 temporary _ decremented nextOwned) nextBacking within (by omega)
      by_cases same : workspace[16 + remaining] = key
      · simp only [same, decide_true] at matched
        have returnRun : Executes program.core decremented (returned (read 3))
            (.returned (some (.signed .i32 remaining))) decremented :=
          executesSequenceReturned (executesReturnValue
            (local_evaluates program.core (Assertion.localPointsTo_local 3 temporary _ decremented nextOwned)))
        have step : Executes program.core before (Source.Lookup.step checked.header.id)
            (.returned (some (.signed .i32 remaining))) decremented :=
          executesSequence (executesExpression decrementRun)
            (executesSequenceReturned (executesIfTrue matched returnRun))
        refine ⟨some remaining, decremented, executesWhileReturned guard step, ?_, effect, heap⟩
        refine ⟨by omega, ?_, ?_⟩
        · simp only [List.getElem?_eq_getElem within, same]
        · intro later higher inside; omega
      · simp only [same, decide_false] at matched
        have step : Executes program.core before (Source.Lookup.step checked.header.id) .next decremented :=
          executesSequence (executesExpression decrementRun)
            (executesSequence (executesIfFalse matched (executesSkip _ _)) (executesSkip _ _))
        obtain ⟨answer, after, rest, correct, restEffect, restHeap⟩ :=
          ih effect.wellFormed nextLocals nextOwned nextBacking (by omega) (by omega)
        have absent : workspace[16 + remaining]? ≠ some key := by
          intro equal
          apply same
          exact Option.some.inj (by simpa only [List.getElem?_eq_getElem within] using equal)
        exact ⟨answer, after, executesWhileTrueThen guard step rest, correct.extend absent,
          effect.trans restEffect, heap.trans restHeap⟩

theorem body (checked : Source.Lookup.Checked program) (active : Nat)
    (wellFormed : StateWellFormed before)
    (locals : Locals (arguments (.slice i32 work [] 0 workspace.length) active key) frontier before)
    (backing : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (room : 16 + active ≤ workspace.length) (bounded : 16 + active ≤ 2147483647) :
    ∃ answer after, Executes program.core before (Source.Lookup.body checked.header.id)
        (.returned (some (.signed .i32 (result answer)))) after ∧ Correct workspace active key answer ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let entered := before.bindLocal 3 (.signed .i32 active)
  have enteredWF := bindLocal_preserves_well_formed before 3 (.signed .i32 active) wellFormed
  have enteredLocals := locals.bind (id := 3) wellFormed (by simp [arguments]) (.signed .i32 active)
  have enteredBacking := ((bindLocal_effect before 3 (.signed .i32 active)).oldCells work
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  obtain ⟨answer, completed, run, correct, effect, heap⟩ := loop checked active enteredWF enteredLocals
    locals.frontierBound (bindLocal_owns_fresh before 3 (.signed .i32 active) wellFormed) enteredBacking room bounded
  have whole : Executes program.core entered (.sequence (Source.Lookup.loop checked.header.id) (returned (.unary .negate (number 1))))
      (.returned (some (.signed .i32 (result answer)))) completed := by
    cases answer with
    | none =>
        have negative : Evaluates program.core completed (.unary .negate (number 1)) (.signed .i32 (-1)) completed := by
          apply evaluatesUnary (show Evaluates program.core completed (number 1) (.signed .i32 1) completed from ⟨1, rfl⟩)
          simp [evalUnaryValue, wrapSigned_i32_neg_one]
        exact executesSequence run (executesSequenceReturned (executesReturnValue negative))
    | some index => exact executesSequenceReturned run
  have closed := CellEffect.closeLocal before 3 (.signed .i32 active) wellFormed effect
  have narrow : CellEffect CellSet.empty before (restoreLocals before completed) := by
    apply closed.narrow
    intro changed old member
    exact False.elim ((Nat.ne_of_lt old) member)
  exact ⟨answer, restoreLocals before completed,
    executesLetLocal (local_evaluates program.core (locals.found ⟨1, by simp [arguments]⟩)) whole,
    correct, narrow, HeapFrame.closeLocal before 3 (.signed .i32 active) heap⟩

/-- The actual authenticated lookup call is total within its declared
workspace range and returns precisely the most recent matching binding.
It preserves all old caller cells, including the full workspace. -/
theorem runs (checked : Source.Lookup.Checked program) (active : Nat) (key : Int)
    (wellFormed : StateWellFormed before)
    (backing : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (room : 16 + active ≤ workspace.length) (bounded : 16 + active ≤ 2147483647)
    (argumentsResult : ArgumentsEvaluateTo program.core caller expressions
      (arguments (.slice i32 work [] 0 workspace.length) active key) before) :
    ∃ answer after, Evaluates program.core caller (.call checked.internal.source.function.id expressions)
        (.signed .i32 (result answer)) after ∧ Correct workspace active key answer ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) } ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun index : Fin 3 =>
    (arguments (.slice i32 work [] 0 workspace.length) active key).get index)
  have initialWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have initialLocals := Locals.ofReads (values := arguments (.slice i32 work [] 0 workspace.length) active key) initialWF
    (fun index => enterCall_parameterBindings_matches wellFormed index)
  have initialBacking := ((enterCall_effect before params).oldCells work
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  obtain ⟨answer, completed, run, correct, effect, heap⟩ := body checked active initialWF initialLocals initialBacking room bounded
  have called := checked.internal.call wellFormed argumentsResult (bindings := params) rfl run effect
  exact ⟨answer, restoreLocals before completed, called.1, correct,
    called.2.empty_preserves_entry wellFormed backing, called.2, HeapFrame.closeCall before params heap⟩

/-- A caller can supply the binding invariant it already knows; uniqueness
then pins the source execution to that exact result without another search. -/
theorem call (checked : Source.Lookup.Checked program) (active : Nat) (key : Int)
    (wellFormed : StateWellFormed before)
    (backing : before.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) })
    (room : 16 + active ≤ workspace.length) (bounded : 16 + active ≤ 2147483647)
    (correct : Correct workspace active key answer)
    (argumentsResult : ArgumentsEvaluateTo program.core caller expressions
      (arguments (.slice i32 work [] 0 workspace.length) active key) before) :
    ∃ after, Evaluates program.core caller (.call checked.internal.source.function.id expressions)
        (.signed .i32 (result answer)) after ∧
      after.cellEntry? work = some { id := work, value := some (.array (signedI32Values workspace)) } ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  obtain ⟨actual, after, run, found, contents, effect, heap⟩ := runs checked active key wellFormed backing room bounded argumentsResult
  have same := found.unique correct
  subst actual
  exact ⟨after, run, contents, effect, heap⟩

/-- An empty or negative active range bypasses the table entirely. This
stronger boundary case needs neither a workspace allocation nor a valid key. -/
theorem body_nonpositive (checked : Source.Lookup.Checked program) (active : Int)
    (wellFormed : StateWellFormed before) (found : before.local? 1 = some (.signed .i32 active))
    (nonpositive : active ≤ 0) :
    ∃ after, Executes program.core before (Source.Lookup.body checked.header.id)
        (.returned (some (.signed .i32 (-1)))) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let entered := before.bindLocal 3 (.signed .i32 active)
  have enteredWF := bindLocal_preserves_well_formed before 3 (.signed .i32 active) wellFormed
  have index := bindLocal_finds_local before 3 (.signed .i32 active) wellFormed
  have guard : Evaluates program.core entered Source.Lookup.positive (.boolean false) entered := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program.core index)
      (show Evaluates program.core entered (number 0) (.signed .i32 0) entered from ⟨1, rfl⟩)
    simp [evalBinaryValue, evalSignedBinary, show ¬ (0 : Int) < active from by omega]
  have negative : Evaluates program.core entered (.unary .negate (number 1)) (.signed .i32 (-1)) entered := by
    apply evaluatesUnary (show Evaluates program.core entered (number 1) (.signed .i32 1) entered from ⟨1, rfl⟩)
    simp [evalUnaryValue, wrapSigned_i32_neg_one]
  exact ⟨restoreLocals before entered,
    executesLetLocal (local_evaluates program.core found)
      (executesSequence (executesWhileFalse guard) (executesSequenceReturned (executesReturnValue negative))),
    CellEffect.closeLocal before 3 (.signed .i32 active) wellFormed (CellEffect.refl enteredWF),
    HeapFrame.closeLocal before 3 (.signed .i32 active) (HeapFrame.refl entered)⟩

theorem nonpositive (checked : Source.Lookup.Checked program) (work key : Value) (active : Int)
    (wellFormed : StateWellFormed before) (empty : active ≤ 0)
    (argumentsResult : ArgumentsEvaluateTo program.core caller expressions [work, .signed .i32 active, key] before) :
    ∃ after, Evaluates program.core caller (.call checked.internal.source.function.id expressions) (.signed .i32 (-1)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let values : List Value := [work, .signed .i32 active, key]
  let params := parameterBindings (fun index : Fin 3 => values.get index)
  have initialWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have initialRead : (enterCall before params).local? 1 = some (.signed .i32 active) :=
    enterCall_parameterBindings_matches wellFormed ⟨1, by decide⟩
  obtain ⟨completed, run, effect, heap⟩ := body_nonpositive checked active initialWF initialRead empty
  have called := checked.internal.call wellFormed argumentsResult (bindings := params) rfl run effect
  exact ⟨restoreLocals before completed, called.1, called.2, HeapFrame.closeCall before params heap⟩

end Lanius.X86.Frame.Lookup
