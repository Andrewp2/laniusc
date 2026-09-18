import Lanius.X86.Select.Loops

namespace Lanius.X86.Select.Header

open Lanius.Core Lanius.FunctionalView Lanius.FunctionalView.Core Lanius.FunctionalView.Core.ReadOnly

variable {program : Program} {world : World} {environment : Env arity}

theorem ne
    (leftResult : Term.evaluate (ReadOnly.machine program) world environment left = .ok (.signed .i32 a, world))
    (rightResult : Term.evaluate (ReadOnly.machine program) world environment right = .ok (.signed .i32 b, world)) :
    Term.evaluate (ReadOnly.machine program) world environment (Syntax.ne left right) =
      .ok (.boolean (decide (a ≠ b)), world) := Term.evaluate_i32_notEqual_int leftResult rightResult

theorem eq
    (leftResult : Term.evaluate (ReadOnly.machine program) world environment left = .ok (.signed .i32 (a : Nat), world))
    (rightResult : Term.evaluate (ReadOnly.machine program) world environment right = .ok (.signed .i32 (b : Nat), world)) :
    Term.evaluate (ReadOnly.machine program) world environment (Syntax.eq left right) =
      .ok (.boolean (decide (a = b)), world) := Term.evaluate_i32_equal leftResult rightResult

theorem lt
    (leftResult : Term.evaluate (ReadOnly.machine program) world environment left = .ok (.signed .i32 (a : Nat), world))
    (rightResult : Term.evaluate (ReadOnly.machine program) world environment right = .ok (.signed .i32 (b : Nat), world)) :
    Term.evaluate (ReadOnly.machine program) world environment (Syntax.lt left right) =
      .ok (.boolean (decide (a < b)), world) := Term.evaluate_i32_less leftResult rightResult

theorem gt
    (leftResult : Term.evaluate (ReadOnly.machine program) world environment left = .ok (.signed .i32 (a : Nat), world))
    (rightResult : Term.evaluate (ReadOnly.machine program) world environment right = .ok (.signed .i32 (b : Nat), world)) :
    Term.evaluate (ReadOnly.machine program) world environment (Syntax.gt left right) =
      .ok (.boolean (decide (b < a)), world) := Term.evaluate_i32_greater leftResult rightResult

theorem add
    (leftResult : Term.evaluate (ReadOnly.machine program) world environment left = .ok (.signed .i32 (a : Nat), world))
    (rightResult : Term.evaluate (ReadOnly.machine program) world environment right = .ok (.signed .i32 (b : Nat), world))
    (bounded : a + b ≤ 2147483647) :
    Term.evaluate (ReadOnly.machine program) world environment (Syntax.add left right) =
      .ok (.signed .i32 (a + b : Nat), world) := Term.evaluate_i32_add leftResult rightResult bounded

theorem header (owned : world.i32Slice? cell = some (input : Input).words) :
    Term.evaluate (ReadOnly.machine program) world (Environment.initial input cell) Syntax.header =
      .ok (.boolean false, world) := by
  have read0 := Evaluate.read (program := program) (environment := Environment.initial input cell)
    (index := Syntax.number 0) (by decide) (by rfl) owned (by rfl) input.header.1
  have read1 := Evaluate.read (program := program) (environment := Environment.initial input cell)
    (index := Syntax.number 1) (by decide) (by rfl) owned (by rfl) input.header.2.1
  have read2 := Evaluate.read (program := program) (environment := Environment.initial input cell)
    (index := Syntax.number 2) (by decide) (by rfl) owned (by rfl) input.header.2.2.1
  have read3 := Evaluate.read (program := program) (environment := Environment.initial input cell)
    (index := Syntax.number 3) (by decide) (by rfl) owned (by rfl) input.header.2.2.2.1
  have result := Term.evaluate_logicalOr_bool
    (Term.evaluate_logicalOr_bool (Term.evaluate_logicalOr_bool
      (ne read0 (right := Syntax.number 1) (by rfl)) (ne read1 (right := Syntax.number 64) (by rfl)))
      (lt read2 (right := Syntax.number 0) (by rfl)))
    (ne read3 (right := Syntax.number 1) (by rfl))
  simpa only [Syntax.header, ne_eq, not_true_eq_false, decide_false, Bool.false_or,
    Nat.not_lt_zero] using result

theorem counts :
    Term.evaluate (ReadOnly.machine program) world (Environment.counts input cell) Syntax.counts =
      .ok (.boolean false, world) := by
  have lower := lt (program := program) (world := world) (environment := Environment.counts input cell)
    (left := Syntax.slot 2) (right := Syntax.number 1) (by rfl) (by rfl)
  have upper := gt (program := program) (world := world) (environment := Environment.counts input cell)
    (left := Syntax.slot 2) (right := Syntax.number 6) (by rfl) (by rfl)
  have four := ne (program := program) (world := world) (environment := Environment.counts input cell)
    (left := Syntax.slot 3) (right := Syntax.number 4) (by rfl) (by rfl)
  have six := ne (program := program) (world := world) (environment := Environment.counts input cell)
    (left := Syntax.slot 3) (right := Syntax.number 6) (by rfl) (by rfl)
  have result := Term.evaluate_logicalOr_bool (Term.evaluate_logicalOr_bool lower upper)
    (Term.evaluate_logicalAnd_bool four six)
  have small : ¬ input.ids.length < 1 := by have := input.bounds.1; omega
  have large : ¬ 6 < input.ids.length := by have := input.countBound; omega
  cases trailing : input.trailing <;>
    simpa [Syntax.counts, Input.bodyLength, trailing, small, large] using result

theorem return_tags (owned : world.i32Slice? cell = some (input : Input).words) :
    Term.evaluate (ReadOnly.machine program) world (Environment.first input cell input.returnStart) Syntax.returnTags =
      .ok (.boolean false, world) := by
  have bounded : input.returnStart + 2 ≤ 2147483647 := by have := input.bounds; omega
  have read0 := Evaluate.read (program := program) (environment := Environment.first input cell input.returnStart)
    (index := Syntax.slot 5) (by decide) (by rfl) owned (by rfl) input.return_tags.1
  have read1 := Evaluate.read (program := program) (environment := Environment.first input cell input.returnStart)
    (index := Syntax.add (Syntax.slot 5) (Syntax.number 1)) (by decide) (by rfl) owned
    (add (by rfl) (by rfl) (by omega)) input.return_tags.2.1
  have read2 := Evaluate.read (program := program) (environment := Environment.first input cell input.returnStart)
    (index := Syntax.add (Syntax.slot 5) (Syntax.number 2)) (by decide) (by rfl) owned
    (add (by rfl) (by rfl) bounded) input.return_tags.2.2.1
  have result := Term.evaluate_logicalOr_bool (Term.evaluate_logicalOr_bool
    (ne read0 (right := Syntax.number 10) (by rfl)) (ne read1 (right := Syntax.number 1) (by rfl)))
    (ne read2 (right := Syntax.number 1) (by rfl))
  simpa [Syntax.returnTags] using result

theorem unwrap_tags (owned : world.i32Slice? cell = some (input : Input).words) (trailing : input.trailing = true) :
    Term.evaluate (ReadOnly.machine program) world (Environment.first input cell input.bodyStart)
      (.logicalOr (Syntax.ne (Syntax.get (Syntax.slot 4)) (Syntax.number 2))
        (Syntax.ne (Syntax.get (Syntax.add (Syntax.slot 4) (Syntax.number 5))) (Syntax.number 0))) =
      .ok (.boolean false, world) := by
  have read0 := Evaluate.read (program := program) (environment := Environment.first input cell input.bodyStart)
    (index := Syntax.slot 4) (by decide) (by rfl) owned (by rfl) (input.unwrap_tags trailing).1
  have read5 := Evaluate.read (program := program) (environment := Environment.first input cell input.bodyStart)
    (index := Syntax.add (Syntax.slot 4) (Syntax.number 5)) (by decide) (by rfl) owned
    (add (by rfl) (by rfl) (by have := input.bounds; omega)) (input.unwrap_tags trailing).2
  exact Term.evaluate_logicalOr_bool (ne read0 (right := Syntax.number 2) (by rfl))
    (ne read5 (right := Syntax.number 0) (by rfl))

theorem length_valid :
    Term.evaluate (ReadOnly.machine program) world (Environment.body input cell)
      (Syntax.ne (Syntax.slot 1) (Syntax.add (Syntax.slot 4) (Syntax.slot 3))) = .ok (.boolean false, world) := by
  have sum := add (program := program) (world := world) (environment := Environment.body input cell)
    (left := Syntax.slot 4) (right := Syntax.slot 3) (by rfl) (by rfl)
    (by have := input.bounds; have := input.words_length; omega)
  have result := ne (program := program) (world := world) (environment := Environment.body input cell)
    (left := Syntax.slot 1) (by rfl) sum
  simpa only [input.words_length, ne_eq, not_true_eq_false, decide_false] using result

theorem length_sufficient :
    Term.evaluate (ReadOnly.machine program) world (Environment.initial input cell)
      (Syntax.lt (Syntax.slot 1) (Syntax.number 6)) = .ok (.boolean false, world) := by
  have result := lt (program := program) (world := world) (environment := Environment.initial input cell)
    (left := Syntax.slot 1) (right := Syntax.number 6) (by rfl) (by rfl)
  have enough : ¬ input.words.length < 6 := by
    have := input.words_length
    simp only [Input.bodyStart] at this
    omega
  simpa only [enough, decide_false] using result

end Lanius.X86.Select.Header
