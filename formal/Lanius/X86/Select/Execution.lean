import Lanius.X86.Select.Header

namespace Lanius.X86.Select.Execution

open Lanius.Core Lanius.FunctionalView Lanius.FunctionalView.Core
open Lanius.FunctionalView.Stateful Lanius.X86.Select.Loops

variable {program : Program} {calls : Effectful.CallModel} {world : ReadOnly.World}

theorem unwrap (owned : world.i32Slice? cell = some (input : Input).words) :
    Runs program calls world (Environment.first input cell input.bodyStart) Syntax.unwrap .next world
      (Environment.first input cell input.returnStart) := by
  have condition := Evaluate.pure (calls := calls) (by rfl)
    (Header.eq (program := program) (world := world) (environment := Environment.first input cell input.bodyStart)
      (left := Syntax.slot 3) (right := Syntax.number 6) (by rfl) (by rfl))
  cases trailing : input.trailing
  · have branch : Runs program calls world (Environment.first input cell input.bodyStart) Syntax.unwrap .next world
        (Environment.first input cell input.bodyStart) :=
      .ifFalse (by
        simp only [Input.bodyLength, trailing, Bool.false_eq_true, ↓reduceIte] at condition
        exact condition) .skip
    simpa only [Input.returnStart, trailing, Bool.false_eq_true, ↓reduceIte, Nat.add_zero] using branch
  · have advanced := increment (program := program) (calls := calls) (world := world)
      (environment := Environment.first input cell input.bodyStart) 5 (by decide) (by rfl)
      (by have := input.bounds; omega)
    rw [Environment.first, Environment.set_push_last] at advanced
    have branch : Runs program calls world (Environment.first input cell input.bodyStart) Syntax.unwrap .next world
        (Environment.first input cell (input.bodyStart + 1)) :=
      .ifTrue (by
        simp only [Input.bodyLength, trailing, ↓reduceIte] at condition
        exact condition)
        (.sequenceNext (reject_false (by rfl) (Header.unwrap_tags owned trailing)) advanced)
    simpa only [Input.returnStart, trailing, ↓reduceIte] using branch

theorem after_body (owned : world.i32Slice? cell = some (input : Input).words) :
    Runs program calls world (Environment.body input cell) Syntax.afterBody
      (.returned (some (.signed .i32 input.position.val))) world (Environment.body input cell) := by
  have returnedRead := Evaluate.pure (calls := calls) (by rfl)
    (Evaluate.read (program := program) (environment := Environment.first input cell input.returnStart)
      (index := Syntax.add (Syntax.slot 5) (Syntax.number 3)) (by decide) (by rfl) owned
      (Header.add (by rfl) (by rfl) (by have := input.bounds; omega)) input.return_tags.2.2.2)
  have tail := Command.Evaluates.letValue (type := Syntax.i32) returnedRead
    (Loops.scan (program := program) (calls := calls) owned)
  have tags := Command.Evaluates.sequenceNext (reject_false (by rfl) (Header.return_tags owned)) tail
  have unwrapped := Command.Evaluates.sequenceNext (unwrap owned) tags
  have bodyRun := Command.Evaluates.letValue (type := Syntax.i32) (initializer := Syntax.slot 4) (by rfl) unwrapped
  have run := Command.Evaluates.sequenceNext (reject_false (by rfl)
    (Header.length_valid (program := program) (world := world) (input := input) (cell := cell))) bodyRun
  simpa only [Syntax.afterBody, Environment.returned, Environment.first, Env.pop_push] using run

/-- Complete selector execution on the real serialized Core-function domain.
All guards, both loops, both body forms, and the return are discharged. -/
theorem command (owned : world.i32Slice? cell = some (input : Input).words) :
    Runs program calls world (Environment.initial input cell) Syntax.command
      (.returned (some (.signed .i32 input.position.val))) world (Environment.initial input cell) := by
  have bodyRead := Evaluate.pure (calls := calls) (by rfl)
    (Header.add (program := program) (world := world) (environment := Environment.counts input cell)
      (a := 6) (b := input.ids.length * 2)
      (left := Syntax.number 6) (right := Syntax.mul (Syntax.slot 2) (Syntax.number 2)) (by rfl)
      (Evaluate.multiply (a := input.ids.length) (b := 2) (by rfl) (by rfl) (by have := input.countBound; omega))
      (by have := input.countBound; omega))
  have bodyRun := Command.Evaluates.letValue (type := Syntax.i32) bodyRead
    (after_body (program := program) (calls := calls) owned)
  have validated := Command.Evaluates.sequenceNext
    (reject_false (by rfl) (Header.counts (program := program) (world := world) (input := input) (cell := cell))) bodyRun
  have sizeRead := Evaluate.pure (calls := calls) (by rfl)
    (Evaluate.read (program := program)
      (environment := (Environment.initial input cell).push (.signed .i32 input.ids.length))
      (index := Syntax.number 5) (by decide) (by rfl) owned (by rfl) input.header.2.2.2.2.2)
  have sizeRun := Command.Evaluates.letValue (type := Syntax.i32) sizeRead validated
  have countRead := Evaluate.pure (calls := calls) (by rfl)
    (Evaluate.read (program := program) (environment := Environment.initial input cell)
      (index := Syntax.number 4) (by decide) (by rfl) owned (by rfl) input.header.2.2.2.2.1)
  have countRun := Command.Evaluates.letValue (type := Syntax.i32) countRead sizeRun
  have headerRun := Command.Evaluates.sequenceNext (reject_false (by rfl) (Header.header owned)) countRun
  have run := Command.Evaluates.sequenceNext (reject_false (by rfl)
    (Header.length_sufficient (program := program) (world := world) (input := input) (cell := cell))) headerRun
  simpa only [Syntax.command, Environment.body, Environment.counts, Env.pop_push] using run

end Lanius.X86.Select.Execution
