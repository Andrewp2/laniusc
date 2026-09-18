import Lanius.X86.Select.Environment
import Lanius.FunctionalViewCoreEffectful

namespace Lanius.X86.Select.Evaluate

open Lanius.Core Lanius.Semantics Lanius.FunctionalView Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly

variable {program : Program} {world : World} {environment : Env arity}

theorem pure {calls : Effectful.CallModel} {term : Syntax.T arity}
    (free : Effectful.termCallFree term = true)
    (evaluated : Term.evaluate (ReadOnly.machine program) world environment term = .ok (value, world)) :
    Term.evaluate (Effectful.machine program calls) world environment term = .ok (value, world) := by
  exact (Effectful.term_evaluate_eq_readOnly_of_callFree term free).trans evaluated

theorem multiply
    (leftResult : Term.evaluate (ReadOnly.machine program) world environment left = .ok (.signed .i32 (a : Nat), world))
    (rightResult : Term.evaluate (ReadOnly.machine program) world environment right = .ok (.signed .i32 (b : Nat), world))
    (bounded : a * b ≤ 2147483647) :
    Term.evaluate (ReadOnly.machine program) world environment (Syntax.mul left right) =
      .ok (.signed .i32 (a * b : Nat), world) := by
  apply Term.evaluate_apply2 leftResult rightResult
  change ReadOnly.evaluateOperation program world (.binary .multiply Syntax.i32 Syntax.i32 Syntax.i32)
    [.signed .i32 a, .signed .i32 b] = .ok (.signed .i32 (a * b : Nat), world)
  simp only [ReadOnly.evaluateOperation, evalBinaryValue, evalSignedBinary, bind, Except.bind, beq_self_eq_true, if_true]
  rw [show (a : Int) * b = (a * b : Nat) by exact (Int.natCast_mul a b).symm]
  change Except.ok (Value.signed .i32 (wrapSigned program.target .i32 (Int.ofNat (a * b))), world) = _
  rw [wrapSigned_i32_ofNat program.target (a * b) bounded]
  rfl

theorem read (positive : 0 < arity)
    (base : environment ⟨0, positive⟩ = .slice Syntax.i32 cell [] 0 input.words.length)
    (owned : world.i32Slice? cell = some (input : Input).words)
    (evaluated : Term.evaluate (ReadOnly.machine program) world environment index = .ok (.signed .i32 (offset : Nat), world))
    (found : input.words[offset]? = some value) :
    Term.evaluate (ReadOnly.machine program) world environment (Syntax.get index positive) =
      .ok (.signed .i32 value, world) := by
  obtain ⟨bound, entry⟩ := List.getElem?_eq_some_iff.mp found
  exact Term.evaluate_i32_index_as (Term.evaluate_slot base) evaluated owned bound entry

theorem id_at (positive : 0 < arity)
    (base : environment ⟨0, positive⟩ = .slice Syntax.i32 cell [] 0 input.words.length)
    (owned : world.i32Slice? cell = some (input : Input).words)
    (index : Fin input.ids.length)
    (evaluated : Term.evaluate (ReadOnly.machine program) world environment term = .ok (.signed .i32 index.val, world)) :
    Term.evaluate (ReadOnly.machine program) world environment (Syntax.idAt term positive) =
      .ok (.signed .i32 (input.ids.get index), world) := by
  apply read positive base owned (offset := 6 + index.val * 2) _ (input.word_field index).1
  apply Term.evaluate_i32_add (by rfl) (multiply evaluated (by rfl) ?_) ?_ <;>
    have := index.isLt <;> have := input.countBound <;> omega

theorem type_at (positive : 0 < arity)
    (base : environment ⟨0, positive⟩ = .slice Syntax.i32 cell [] 0 input.words.length)
    (owned : world.i32Slice? cell = some (input : Input).words)
    (index : Fin input.ids.length)
    (evaluated : Term.evaluate (ReadOnly.machine program) world environment term = .ok (.signed .i32 index.val, world)) :
    Term.evaluate (ReadOnly.machine program) world environment (Syntax.typeAt term positive) =
      .ok (.signed .i32 1, world) := by
  apply read positive base owned (offset := 7 + index.val * 2) _ (input.word_field index).2
  apply Term.evaluate_i32_add (by rfl) (multiply evaluated (by rfl) ?_) ?_ <;>
    have := index.isLt <;> have := input.countBound <;> omega

theorem earlier_condition {id : Nat} :
    Term.evaluate (ReadOnly.machine program) world (Environment.earlier input cell value index id previous)
      Syntax.earlierCondition = .ok (.boolean (decide (previous < index)), world) :=
  Term.evaluate_i32_less (by rfl) (by rfl)

theorem duplicate_false
    (owned : world.i32Slice? cell = some (input : Input).words)
    (index : Fin input.ids.length) (previous : Nat) (earlier : previous < index.val) :
    Term.evaluate (ReadOnly.machine program) world
      (Environment.earlier input cell value index.val (input.ids.get index) previous)
      (Syntax.eq (Syntax.idAt (Syntax.slot 10)) (Syntax.slot 9)) = .ok (.boolean false, world) := by
  have distinct : input.ids.get ⟨previous, Nat.lt_trans earlier index.isLt⟩ ≠ input.ids.get index := by
    intro equal
    have same := (input.id_equal _ _).mp equal
    exact (Nat.ne_of_lt earlier) same
  have evaluated := Term.evaluate_i32_equal
    (leftType := Syntax.i32) (rightType := Syntax.i32) (outputType := Syntax.bool)
    (id_at (by decide) (by rfl) owned ⟨previous, Nat.lt_trans earlier index.isLt⟩ (by rfl))
    (program := program) (environment := Environment.earlier input cell value index.val (input.ids.get index) previous)
    (left := Syntax.idAt (Syntax.slot 10)) (right := Syntax.slot 9) (by rfl)
  simpa only [Syntax.eq, Syntax.binary, decide_eq_false distinct] using evaluated

theorem iteration_valid
    (owned : world.i32Slice? cell = some (input : Input).words) (index : Fin input.ids.length) :
    Term.evaluate (ReadOnly.machine program) world
      (Environment.identified input cell value index.val (input.ids.get index))
      (.logicalOr (Syntax.lt (Syntax.slot 9) (Syntax.number 0))
        (Syntax.ne (Syntax.typeAt (Syntax.slot 8)) (Syntax.number 1))) = .ok (.boolean false, world) := by
  have positive := Term.evaluate_i32_less (program := program) (world := world)
    (leftType := Syntax.i32) (rightType := Syntax.i32) (outputType := Syntax.bool)
    (environment := Environment.identified input cell value index.val (input.ids.get index))
    (left := Syntax.slot 9) (right := Syntax.number 0) (by rfl) (by rfl)
  have type := Term.evaluate_i32_notEqual_int
    (leftType := Syntax.i32) (rightType := Syntax.i32) (outputType := Syntax.bool)
    (type_at (by decide) (by rfl) owned index (by rfl))
    (program := program) (environment := Environment.identified input cell value index.val (input.ids.get index))
    (left := Syntax.typeAt (Syntax.slot 8)) (right := Syntax.number 1) (by rfl)
  simpa [Syntax.lt, Syntax.ne, Syntax.binary] using Term.evaluate_logicalOr_bool positive type

theorem selected_condition (index : Fin input.ids.length) :
    Term.evaluate (ReadOnly.machine program) world
      (Environment.earlier input cell value index.val (input.ids.get index) previous)
      (Syntax.eq (Syntax.slot 9) (Syntax.slot 6)) =
      .ok (.boolean (decide (index.val = input.position.val)), world) := by
  have evaluated := Term.evaluate_i32_equal (program := program) (world := world)
    (leftType := Syntax.i32) (rightType := Syntax.i32) (outputType := Syntax.bool)
    (environment := Environment.earlier input cell value index.val (input.ids.get index) previous)
    (left := Syntax.slot 9) (right := Syntax.slot 6) (by rfl) (by rfl)
  simpa only [Syntax.eq, Syntax.binary, Input.returnedId, input.id_equal] using evaluated

theorem loop_condition :
    Term.evaluate (ReadOnly.machine program) world (Environment.indexed input cell value index)
      (Syntax.lt (Syntax.slot 8) (Syntax.slot 2)) =
      .ok (.boolean (decide (index < input.ids.length)), world) :=
  Term.evaluate_i32_less (by rfl) (by rfl)

end Lanius.X86.Select.Evaluate
