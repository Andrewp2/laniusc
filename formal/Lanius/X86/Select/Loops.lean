import Lanius.X86.Select.Evaluate

namespace Lanius.X86.Select.Loops

open Lanius.Core Lanius.Semantics Lanius.FunctionalView Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful Lanius.FunctionalView.Stateful

abbrev Runs (program : Program) (calls : Effectful.CallModel) :=
  @Command.Evaluates signature actions (Effectful.machine program calls)
    (machineWith program (Effectful.evaluateOperation program calls))

variable {program : Program} {calls : Effectful.CallModel} {world : ReadOnly.World}

theorem reject_false {environment : Env arity} {condition : Syntax.T arity}
    (free : Effectful.termCallFree condition = true)
    (evaluated : Term.evaluate (ReadOnly.machine program) world environment condition = .ok (.boolean false, world)) :
    Runs program calls world environment (Syntax.reject condition) .next world environment :=
  .ifFalse (Evaluate.pure free evaluated) .skip

theorem increment {environment : Env arity} (index : Nat) (bound : index < arity)
    (current : environment ⟨index, bound⟩ = .signed .i32 (value : Nat)) (bounded : value + 1 ≤ 2147483647) :
    Runs program calls world environment (Syntax.increment index bound) .next world
      (Env.set environment ⟨index, bound⟩ (.signed .i32 (value + 1 : Nat))) := by
  apply Command.Evaluates.sequenceNext (Command.Evaluates.updateLocal (by rfl) ?_) .skip
  change evalAssignValue program.target .add (some (environment ⟨index, bound⟩)) (.signed .i32 1) = _
  rw [current]
  simp only [evalAssignValue, assignOpBinary?, evalBinaryValue, beq_self_eq_true, if_true, evalSignedBinary]
  change Except.ok (Value.signed .i32 (wrapSigned program.target .i32 ((value : Int) + 1))) = _
  rw [show (value : Int) + 1 = Int.ofNat (value + 1) by simp,
    wrapSigned_i32_ofNat program.target (value + 1) bounded]
  rfl

theorem earlier_loop
    (owned : world.i32Slice? cell = some (input : Input).words)
    (index : Fin input.ids.length) (previous : Nat) (before : previous ≤ index.val) :
    Runs program calls world (Environment.earlier input cell value index.val (input.ids.get index) previous)
      Syntax.earlierLoop .next world (Environment.earlier input cell value index.val (input.ids.get index) index.val) := by
  by_cases done : previous = index.val
  · subst previous
    exact .whileFalse (Evaluate.pure (by rfl) (by simpa using
      (Evaluate.earlier_condition (program := program) (world := world)
        (input := input) (cell := cell) (value := value) (index := index.val)
        (id := input.ids.get index) (previous := index.val))))
  · have less : previous < index.val := by omega
    have advance := increment (program := program) (calls := calls) (world := world)
      (environment := Environment.earlier input cell value index.val (input.ids.get index) previous)
      10 (by decide) (by rfl) (by have := index.isLt; have := input.countBound; omega)
    rw [Environment.earlier_increment] at advance
    exact .whileNext (Evaluate.pure (by rfl) (by simpa only [less, decide_true] using
      (Evaluate.earlier_condition (program := program) (world := world)
        (input := input) (cell := cell) (value := value) (index := index.val)
        (id := input.ids.get index) (previous := previous))))
      (.sequenceNext (reject_false (by rfl) (Evaluate.duplicate_false owned index previous less)) advance)
      (earlier_loop owned index (previous + 1) (by omega))
termination_by index.val - previous

def nextSelected (input : Input) (value : Int) (index : Nat) : Int :=
  if index = input.position.val then index else value

theorem select_current (index : Fin input.ids.length) :
    Runs program calls world (Environment.earlier input cell value index.val (input.ids.get index) previous)
      Syntax.selectCurrent .next world
      (Environment.earlier input cell (nextSelected input value index.val) index.val (input.ids.get index) previous) := by
  have condition := Evaluate.pure (calls := calls) (by rfl)
    (Evaluate.selected_condition (program := program) (world := world) (cell := cell)
      (value := value) (previous := previous) index)
  by_cases same : index.val = input.position.val
  · rw [nextSelected, if_pos same]
    have update : Runs program calls world
        (Environment.earlier input cell value index.val (input.ids.get index) previous)
        (.setLocal ⟨7, by decide⟩ (Syntax.slot 8)) .next world
        (Env.set (Environment.earlier input cell value index.val (input.ids.get index) previous)
          ⟨7, by decide⟩ (.signed .i32 index.val)) := .setLocal (by rfl)
    rw [Environment.select_index] at update
    exact .ifTrue (by simpa only [same, decide_true] using condition) (.sequenceNext update .skip)
  · rw [nextSelected, if_neg same]
    exact .ifFalse (by simpa only [same, decide_false] using condition) .skip

theorem iteration
    (owned : world.i32Slice? cell = some (input : Input).words) (index : Fin input.ids.length) :
    Runs program calls world (Environment.indexed input cell value index.val) Syntax.iteration .next world
      (Environment.indexed input cell (nextSelected input value index.val) (index.val + 1)) := by
  have advance := increment (program := program) (calls := calls) (world := world)
    (environment := Environment.earlier input cell (nextSelected input value index.val) index.val (input.ids.get index) index.val)
    8 (by decide) (by rfl) (by have := index.isLt; have := input.countBound; omega)
  rw [Environment.index_increment] at advance
  have tail := Command.Evaluates.sequenceNext (earlier_loop (program := program) (calls := calls)
    (value := value) owned index 0 (Nat.zero_le _))
    (.sequenceNext (select_current (program := program) (calls := calls) (world := world)
      (cell := cell) (value := value) (previous := index.val) index) advance)
  have body := Command.Evaluates.letValue (type := Syntax.i32) (initializer := Syntax.number 0)
    (by rfl) tail
  have validated := Command.Evaluates.sequenceNext
    (reject_false (calls := calls) (by rfl) (Evaluate.iteration_valid (value := value) owned index)) body
  have run := Command.Evaluates.letValue (type := Syntax.i32)
    (Evaluate.pure (calls := calls) (by rfl) (Evaluate.id_at (program := program)
      (environment := Environment.indexed input cell value index.val) (by decide) (by rfl) owned index
      (term := Syntax.slot 8) (by rfl))) validated
  simpa only [Syntax.iteration, Environment.earlier, Environment.identified, Env.pop_push] using run

/-- Before the matching row, selection is -1; afterwards it is the selected
parameter's position. This invariant follows the actual nested source loops. -/
def selection (input : Input) (index : Nat) : Int := if input.position.val < index then input.position.val else -1

theorem selection_next (input : Input) (index : Nat) :
    nextSelected input (selection input index) index = selection input (index + 1) := by
  simp only [nextSelected, selection]
  by_cases same : index = input.position.val
  · simp only [same, Nat.lt_succ_self, ↓reduceIte]
  · have next : input.position.val < index + 1 ↔ input.position.val < index := by omega
    simp only [same, ↓reduceIte, next]

theorem loop
    (owned : world.i32Slice? cell = some (input : Input).words) (index : Nat) (bound : index ≤ input.ids.length) :
    Runs program calls world (Environment.indexed input cell (selection input index) index)
      Syntax.loop .next world (Environment.indexed input cell input.position.val input.ids.length) := by
  by_cases done : index = input.ids.length
  · subst index
    rw [selection, if_pos input.position.isLt]
    exact .whileFalse (Evaluate.pure (by rfl) (by simpa using
      (Evaluate.loop_condition (program := program) (world := world) (input := input)
        (cell := cell) (value := (input.position.val : Int)) (index := input.ids.length))))
  · have less : index < input.ids.length := by omega
    have step := iteration (program := program) (calls := calls) (value := selection input index) owned ⟨index, less⟩
    rw [selection_next] at step
    exact .whileNext (Evaluate.pure (by rfl) (by simpa only [less, decide_true] using
      (Evaluate.loop_condition (program := program) (world := world) (input := input)
        (cell := cell) (value := selection input index) (index := index))))
      step (loop owned (index + 1) (by omega))
termination_by input.ids.length - index

theorem scan (owned : world.i32Slice? cell = some (input : Input).words) :
    Runs program calls world (Environment.returned input cell) Syntax.scan
      (.returned (some (.signed .i32 input.position.val))) world (Environment.returned input cell) := by
  have loopRun := loop (program := program) (calls := calls) owned 0 (Nat.zero_le _)
  simp only [selection, Nat.not_lt_zero, ↓reduceIte] at loopRun
  have returned : Runs program calls world (Environment.indexed input cell input.position.val input.ids.length)
      (Syntax.returned (Syntax.slot 7)) (.returned (some (.signed .i32 input.position.val))) world
      (Environment.indexed input cell input.position.val input.ids.length) :=
    .sequenceStop (.returnSome (by rfl)) (by intro impossible; cases impossible)
  have run := Command.Evaluates.letValue (type := Syntax.i32) (initializer := Syntax.negative)
    (Evaluate.pure (by rfl) ReadOnly.Term.evaluate_i32_negate_one)
    (Command.Evaluates.letValue (type := Syntax.i32) (initializer := Syntax.number 0) (by rfl)
      (.sequenceNext loopRun returned))
  simpa only [Syntax.scan, Environment.indexed, Environment.selected, Env.pop_push] using run

end Lanius.X86.Select.Loops
