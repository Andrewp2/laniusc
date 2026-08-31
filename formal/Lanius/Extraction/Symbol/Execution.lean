import Lanius.Extraction.Symbol.Behavior
import Lanius.Extraction.Symbol.Structure
import Lanius.FunctionalViewStatefulAcyclic

namespace Lanius.Extraction.Symbol.Execution

open Lanius
open Lanius.Core
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful

abbrev operationEvaluator : OperationEvaluator :=
  Lanius.FunctionalView.Core.Effectful.evaluateOperation
    verifiedFrontendCore Calls.helperCalls

abbrev termEvaluationMachine : Lanius.FunctionalView.Machine Core.signature := {
  World := ReadOnly.World
  evalOperation := operationEvaluator
}

abbrev commandEvaluationMachine :
    Lanius.FunctionalView.Stateful.Machine termEvaluationMachine actions := {
  evalLocalUpdate := fun operation current right =>
    Lanius.Semantics.evalAssignValue verifiedFrontendCore.target operation
      (some current) right
  evalAction := Lanius.FunctionalView.Core.Stateful.evaluateActionWith
    operationEvaluator
}

def caseEnvironment (baseEnvironment : Env 3) (first second third : Int) : Env 6 :=
  ((baseEnvironment.push (.signed .i32 first)).push
    (.signed .i32 second)).push (.signed .i32 third)

def sourceSlice (source : List Int) : Value :=
  .slice (.scalar (.signed .i32)) 0 [] 0 source.length

def sourceEnvironment (source : List Int) (sourceLength start : Nat) : Env 3
  | ⟨0, _⟩ => sourceSlice source
  | ⟨1, _⟩ => .signed .i32 sourceLength
  | ⟨2, _⟩ => .signed .i32 start

theorem evaluate_source_index
    (source : List Int) (position : Nat)
    (sourceFound : world.i32Slice? 0 = some source)
    (inBounds : position < source.length)
    (environment : Env arity)
    (base positionTerm : Term Core.signature arity)
    (baseResult : Term.evaluate termEvaluationMachine world environment base =
      .ok (sourceSlice source, world))
    (positionResult : Term.evaluate termEvaluationMachine world environment
      positionTerm = .ok (.signed .i32 position, world)) :
    Term.evaluate termEvaluationMachine world environment
        (.apply (.index (.slice Structure.i32) Structure.i32 Structure.i32)
          [base, positionTerm]) =
      .ok (.signed .i32 (source.get ⟨position, inBounds⟩), world) := by
  apply Term.evaluate_apply2 baseResult positionResult
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedFrontendCore world
      (.index (.slice Structure.i32) Structure.i32 Structure.i32)
      [sourceSlice source, .signed .i32 position] = _
  simpa [sourceSlice] using
    (Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_index
      (program := verifiedFrontendCore) (world := world)
      (baseType := .slice Structure.i32) (indexType := Structure.i32)
      (elementType := Structure.i32) sourceFound inBounds)

theorem evaluate_add_nat
    (environment : Env arity) (left right : Nat)
    (leftTerm rightTerm : Term Core.signature arity)
    (leftResult : Term.evaluate termEvaluationMachine world environment
      leftTerm = .ok (.signed .i32 left, world))
    (rightResult : Term.evaluate termEvaluationMachine world environment
      rightTerm = .ok (.signed .i32 right, world))
    (bounded : left + right ≤ 2147483647) :
    Term.evaluate termEvaluationMachine world environment
        (.apply (.binary .add Structure.i32 Structure.i32 Structure.i32)
          [leftTerm, rightTerm]) =
      .ok (.signed .i32 (left + right), world) := by
  apply Term.evaluate_apply2 leftResult rightResult
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedFrontendCore world
      (.binary .add Structure.i32 Structure.i32 Structure.i32)
      [.signed .i32 left, .signed .i32 right] = _
  exact Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_add
    (program := verifiedFrontendCore) (world := world)
    (leftType := Structure.i32) (rightType := Structure.i32)
    (outputType := Structure.i32) left right bounded

theorem evaluate_less_nat
    (environment : Env arity) (left right : Nat)
    (leftTerm rightTerm : Term Core.signature arity)
    (leftResult : Term.evaluate termEvaluationMachine world environment
      leftTerm = .ok (.signed .i32 left, world))
    (rightResult : Term.evaluate termEvaluationMachine world environment
      rightTerm = .ok (.signed .i32 right, world)) :
    Term.evaluate termEvaluationMachine world environment
        (.apply (.binary .less Structure.i32 Structure.i32 Structure.bool)
          [leftTerm, rightTerm]) =
      .ok (.boolean (decide (left < right)), world) := by
  apply Term.evaluate_apply2 leftResult rightResult
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedFrontendCore world
      (.binary .less Structure.i32 Structure.i32 Structure.bool)
      [.signed .i32 left, .signed .i32 right] = _
  exact Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_less
    (program := verifiedFrontendCore) (world := world)
    (leftType := Structure.i32) (rightType := Structure.i32)
    (outputType := Structure.bool) left right

theorem evaluate_negate_one (environment : Env arity) :
    Term.evaluate termEvaluationMachine world environment
        (Structure.unary .negate (Structure.integer 1)).denote =
      .ok (.signed .i32 (-1), world) := by
  rw [Structure.unary_denote, Structure.integer_denote]
  apply Term.evaluate_apply1 (by rfl)
  change Lanius.FunctionalView.Core.ReadOnly.evaluateOperation
    verifiedFrontendCore world
      (.unary .negate Structure.i32 Structure.i32)
      [.signed .i32 1] = _
  exact Lanius.FunctionalView.Core.ReadOnly.evaluateOperation_i32_negate_one

def optionalAt (source : List Int) (position : Nat) : Int :=
  source[position]?.getD (-1)

theorem readSecond_run
    (world : ReadOnly.World) (source : List Int) (start : Nat)
    (first third : Int)
    (sourceFound : world.i32Slice? 0 = some source)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    Acyclic.run? termEvaluationMachine commandEvaluationMachine world
        (caseEnvironment (sourceEnvironment source source.length start)
          first (-1) third) Structure.readSecond.denote =
      some (.next, world,
        caseEnvironment (sourceEnvironment source source.length start)
          first (optionalAt source (start + 1)) third) := by
  have sumBound : start + 1 ≤ 2147483647 := by omega
  have added := evaluate_add_nat
    (world := world)
    (caseEnvironment (sourceEnvironment source source.length start)
      first (-1) third)
    start 1 (Structure.slot 2).denote (Structure.integer 1).denote
    (by rw [Structure.slot_denote]; rfl)
    (by rw [Structure.integer_denote]; rfl) sumBound
  have condition := evaluate_less_nat
    (world := world)
    (caseEnvironment (sourceEnvironment source source.length start)
      first (-1) third)
    (start + 1) source.length
    (Structure.add (Structure.slot 2) (Structure.integer 1)).denote
    (Structure.slot 1).denote
    (by rw [Structure.add_denote]; exact added)
    (by rw [Structure.slot_denote]; rfl)
  unfold Structure.readSecond
  rw [Structure.ifThenElse_denote, Structure.less_denote]
  simp only [Acyclic.run?.eq_7]
  rw [condition]
  by_cases inBounds : start + 1 < source.length
  · simp only [inBounds, decide_true]
    rw [Structure.sequence_denote, Structure.setLocal_denote,
      Structure.index_denote,
      Acyclic.run?.eq_2, Acyclic.run?.eq_4]
    have indexed := evaluate_source_index source (start + 1) sourceFound
      inBounds
      (caseEnvironment (sourceEnvironment source source.length start)
        first (-1) third)
      (Structure.slot 0).denote
      (Structure.add (Structure.slot 2) (Structure.integer 1)).denote
      (by rw [Structure.slot_denote]; rfl)
      (by rw [Structure.add_denote]; exact added)
    rw [indexed]
    simp only [Structure.skip_denote, Acyclic.run?.eq_1]
    simp [caseEnvironment, optionalAt, inBounds, Env.set,
      sourceEnvironment]
    funext ⟨index, bound⟩
    have cases : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 ∨
        index = 4 ∨ index = 5 := by omega
    rcases cases with h | h | h | h | h | h <;> subst index <;> rfl
  · simp only [inBounds, decide_false, Structure.skip_denote,
      Acyclic.run?.eq_1]
    simp [optionalAt, inBounds]

theorem readThird_run
    (world : ReadOnly.World) (source : List Int) (start : Nat)
    (first second : Int)
    (sourceFound : world.i32Slice? 0 = some source)
    (startTwoBound : start + 2 ≤ 2147483647) :
    Acyclic.run? termEvaluationMachine commandEvaluationMachine world
        (caseEnvironment (sourceEnvironment source source.length start)
          first second (-1)) Structure.readThird.denote =
      some (.next, world,
        caseEnvironment (sourceEnvironment source source.length start)
          first second (optionalAt source (start + 2))) := by
  have added := evaluate_add_nat
    (world := world)
    (caseEnvironment (sourceEnvironment source source.length start)
      first second (-1))
    start 2 (Structure.slot 2).denote (Structure.integer 2).denote
    (by rw [Structure.slot_denote]; rfl)
    (by rw [Structure.integer_denote]; rfl) startTwoBound
  have condition := evaluate_less_nat
    (world := world)
    (caseEnvironment (sourceEnvironment source source.length start)
      first second (-1))
    (start + 2) source.length
    (Structure.add (Structure.slot 2) (Structure.integer 2)).denote
    (Structure.slot 1).denote
    (by rw [Structure.add_denote]; exact added)
    (by rw [Structure.slot_denote]; rfl)
  unfold Structure.readThird
  rw [Structure.ifThenElse_denote, Structure.less_denote]
  simp only [Acyclic.run?.eq_7]
  rw [condition]
  by_cases inBounds : start + 2 < source.length
  · simp only [inBounds, decide_true]
    rw [Structure.sequence_denote, Structure.setLocal_denote,
      Structure.index_denote, Acyclic.run?.eq_2, Acyclic.run?.eq_4]
    have indexed := evaluate_source_index source (start + 2) sourceFound
      inBounds
      (caseEnvironment (sourceEnvironment source source.length start)
        first second (-1))
      (Structure.slot 0).denote
      (Structure.add (Structure.slot 2) (Structure.integer 2)).denote
      (by rw [Structure.slot_denote]; rfl)
      (by rw [Structure.add_denote]; exact added)
    rw [indexed]
    simp only [Structure.skip_denote, Acyclic.run?.eq_1]
    simp [caseEnvironment, optionalAt, inBounds, Env.set,
      sourceEnvironment]
    funext ⟨index, bound⟩
    have cases : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 ∨
        index = 4 ∨ index = 5 := by omega
    rcases cases with h | h | h | h | h | h <;> subst index <;> rfl
  · simp only [inBounds, decide_false, Structure.skip_denote,
      Acyclic.run?.eq_1]
    simp [optionalAt, inBounds]

theorem evaluate_equal_at
    (environment : Env arity) (index : Fin arity)
    (actual expected : Int)
    (found : environment index = .signed .i32 actual) :
    Term.evaluate termEvaluationMachine world environment
        (Structure.equal (Structure.slot index)
          (Structure.integer expected)).denote =
      .ok (.boolean (decide (actual = expected)), world) := by
  rw [Structure.equal_denote, Structure.slot_denote,
    Structure.integer_denote]
  simp [Term.evaluate, evaluateTerms, Ref.evaluate, bind, Except.bind,
    termEvaluationMachine, operationEvaluator,
    Lanius.FunctionalView.Core.Effectful.evaluateOperation,
    Lanius.FunctionalView.Core.ReadOnly.evaluateOperation,
    Lanius.Semantics.evalBinaryValue, Lanius.Semantics.scalarEqual, found]
  congr 2

@[simp] theorem evaluate_equal_first (world : ReadOnly.World)
    (baseEnvironment : Env 3) (first second third expected : Int) :
    Term.evaluate termEvaluationMachine world
        (caseEnvironment baseEnvironment first second third)
        (Structure.equal (Structure.slot 3)
          (Structure.integer expected)).denote =
      .ok (.boolean (decide (first = expected)), world) := by
  exact evaluate_equal_at _ _ first expected rfl

@[simp] theorem evaluate_equal_second (world : ReadOnly.World)
    (baseEnvironment : Env 3) (first second third expected : Int) :
    Term.evaluate termEvaluationMachine world
        (caseEnvironment baseEnvironment first second third)
        (Structure.equal (Structure.slot 4)
          (Structure.integer expected)).denote =
      .ok (.boolean (decide (second = expected)), world) := by
  exact evaluate_equal_at _ _ second expected rfl

@[simp] theorem evaluate_equal_third (world : ReadOnly.World)
    (baseEnvironment : Env 3) (first second third expected : Int) :
    Term.evaluate termEvaluationMachine world
        (caseEnvironment baseEnvironment first second third)
        (Structure.equal (Structure.slot 5)
          (Structure.integer expected)).denote =
      .ok (.boolean (decide (third = expected)), world) := by
  exact evaluate_equal_at _ _ third expected rfl

theorem evaluate_tokenMatch
    (kind length : Int) (environment : Env arity)
    (declaration : Constant)
    (found : verifiedFrontendCore.constant?
      (Structure.tokenKindConstantId kind) = some declaration)
    (constantValue : declaration.value = .signed .i32 kind) :
    Term.evaluate termEvaluationMachine world environment
        (Structure.tokenMatch kind length).denote =
      .ok (Semantics.value kind length, world) := by
  rw [Structure.tokenMatch_denote, Structure.tokenKind_denote,
    Structure.integer_denote]
  simp [
    Term.evaluate, evaluateTerms, Ref.evaluate, bind, Except.bind,
    termEvaluationMachine, operationEvaluator,
    Lanius.FunctionalView.Core.Effectful.evaluateOperation,
    Lanius.FunctionalView.Core.ReadOnly.evaluateOperation,
    found, constantValue, Calls.helperCalls, Calls.tokenMatchCalls,
    Calls.tokenMatchKindCalls, Calls.tokenMatchLengthCalls,
    Calls.accessorCalls, Semantics.value]
  exact Calls.helperCalls_tokenMatch world kind length

theorem returnMatch_run
    (kind length : Int) (environment : Env arity)
    (declaration : Constant)
    (found : verifiedFrontendCore.constant?
      (Structure.tokenKindConstantId kind) = some declaration)
    (constantValue : declaration.value = .signed .i32 kind) :
    Acyclic.run? termEvaluationMachine commandEvaluationMachine world
        environment (Structure.returnMatch kind length).denote =
      some (.returned (some (Semantics.value kind length)), world,
        environment) := by
  rw [Structure.returnMatch_denote, Acyclic.run?.eq_2,
    Acyclic.run?.eq_10]
  rw [evaluate_tokenMatch kind length environment declaration found
    constantValue]

theorem returnMatch_run_id
    (kind length : Int) (id : ConstantId) (environment : Env arity)
    (idEq : Structure.tokenKindConstantId kind = id)
    (found : verifiedFrontendCore.constant? id = some {
      id := id
      type := Structure.i32
      value := .signed .i32 kind
    }) :
    Acyclic.run? termEvaluationMachine commandEvaluationMachine world
        environment (Structure.returnMatch kind length).denote =
      some (.returned (some (Semantics.value kind length)), world,
        environment) := by
  subst id
  exact returnMatch_run kind length environment _ found rfl

theorem first60_run (world : ReadOnly.World)
    (baseEnvironment : Env 3) (first second third : Int) :
    Acyclic.run? termEvaluationMachine commandEvaluationMachine world
        (caseEnvironment baseEnvironment first second third) Structure.first60.denote =
      some (.returned (some (Semantics.value
        (Behavior.classify 60 second third).kind
        (Behavior.classify 60 second third).length)),
        world, caseEnvironment baseEnvironment first second third) := by
  simp only [Structure.first60, Structure.orderedCases, List.foldr,
    Structure.sequence_denote, Structure.ifThenElse_denote,
    Structure.skip_denote]
  by_cases second60 : second = 60
  · by_cases third61 : third = 61
    · subst second; subst third
      simp only [Acyclic.run?.eq_2, Acyclic.run?.eq_7,
        evaluate_equal_second, evaluate_equal_third, decide_true,
        Behavior.classify, if_pos]
      rw [returnMatch_run_id 52 3 54 _ (by native_decide) (by rfl)]
    · subst second
      simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
        evaluate_equal_second, evaluate_equal_third, decide_true,
        decide_false, third61, Behavior.classify, if_pos, if_false]
      rw [returnMatch_run_id 43 2 45 _ (by native_decide) (by rfl)]
  · by_cases second61 : second = 61
    · subst second
      simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
        evaluate_equal_second, decide_true, decide_false,
        second60, Behavior.classify, if_pos, if_false]
      rw [returnMatch_run_id 14 2 20 _ (by native_decide) (by rfl)]
    · by_cases second62 : second = 62
      · subst second
        simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
          evaluate_equal_second, decide_true, decide_false,
          second60, second61, Behavior.classify, if_pos, if_false]
        rw [returnMatch_run_id 24 2 30 _ (by native_decide) (by rfl)]
      · simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
          evaluate_equal_second, decide_false,
          second60, second61, second62, Behavior.classify,
          if_pos, if_false]
        rw [returnMatch_run_id 12 1 18 _ (by native_decide) (by rfl)]

theorem first62_run (world : ReadOnly.World)
    (baseEnvironment : Env 3) (first second third : Int) :
    Acyclic.run? termEvaluationMachine commandEvaluationMachine world
        (caseEnvironment baseEnvironment first second third) Structure.first62.denote =
      some (.returned (some (Semantics.value
        (Behavior.classify 62 second third).kind
        (Behavior.classify 62 second third).length)),
        world, caseEnvironment baseEnvironment first second third) := by
  simp only [Structure.first62, Structure.orderedCases, List.foldr,
    Structure.sequence_denote, Structure.ifThenElse_denote,
    Structure.skip_denote]
  by_cases second62 : second = 62
  · by_cases third61 : third = 61
    · subst second; subst third
      simp only [Acyclic.run?.eq_2, Acyclic.run?.eq_7,
        evaluate_equal_second, evaluate_equal_third, decide_true,
        Behavior.classify, if_pos, if_false]
      rw [returnMatch_run_id 53 3 55 _ (by native_decide) (by rfl)]
      simp [Behavior.classify]
    · subst second
      simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
        evaluate_equal_second, evaluate_equal_third, decide_true,
        decide_false, third61, Behavior.classify, if_pos, if_false]
      rw [returnMatch_run_id 44 2 46 _ (by native_decide) (by rfl)]
      simp [Behavior.classify]
  · by_cases second61 : second = 61
    · subst second
      simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
        evaluate_equal_second, decide_true, decide_false,
        second62, Behavior.classify, if_pos, if_false]
      rw [returnMatch_run_id 15 2 21 _ (by native_decide) (by rfl)]
      simp [Behavior.classify]
    · simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
        evaluate_equal_second, decide_false, second62, second61,
        Behavior.classify, if_pos, if_false]
      rw [returnMatch_run_id 13 1 19 _ (by native_decide) (by rfl)]
      simp [Behavior.classify]

theorem first43_run (world : ReadOnly.World)
    (baseEnvironment : Env 3) (first second third : Int) :
    Acyclic.run? termEvaluationMachine commandEvaluationMachine world
        (caseEnvironment baseEnvironment first second third) Structure.first43.denote =
      some (.returned (some (Semantics.value
        (Behavior.classify 43 second third).kind
        (Behavior.classify 43 second third).length)),
        world, caseEnvironment baseEnvironment first second third) := by
  simp only [Structure.first43, Structure.orderedCases, List.foldr,
    Structure.sequence_denote, Structure.ifThenElse_denote,
    Structure.skip_denote]
  by_cases second61 : second = 61
  · subst second
    simp only [Acyclic.run?.eq_2, Acyclic.run?.eq_7,
      evaluate_equal_second, decide_true, Behavior.classify, if_pos, if_false]
    rw [returnMatch_run_id 46 2 48 _ (by native_decide) (by rfl)]
    simp [Behavior.classify]
  · by_cases second43 : second = 43
    · subst second
      simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
        evaluate_equal_second, decide_true, decide_false, second61,
        Behavior.classify, if_pos, if_false]
      rw [returnMatch_run_id 56 2 58 _ (by native_decide) (by rfl)]
      simp [Behavior.classify]
    · simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
        evaluate_equal_second, decide_false, second61, second43,
        Behavior.classify, if_pos, if_false]
      rw [returnMatch_run_id 6 1 12 _ (by native_decide) (by rfl)]
      simp [Behavior.classify]

theorem first45_run (world : ReadOnly.World)
    (baseEnvironment : Env 3) (first second third : Int) :
    Acyclic.run? termEvaluationMachine commandEvaluationMachine world
        (caseEnvironment baseEnvironment first second third) Structure.first45.denote =
      some (.returned (some (Semantics.value
        (Behavior.classify 45 second third).kind
        (Behavior.classify 45 second third).length)),
        world, caseEnvironment baseEnvironment first second third) := by
  simp only [Structure.first45, Structure.orderedCases, List.foldr,
    Structure.sequence_denote, Structure.ifThenElse_denote,
    Structure.skip_denote]
  by_cases second61 : second = 61
  · subst second
    simp only [Acyclic.run?.eq_2, Acyclic.run?.eq_7,
      evaluate_equal_second, decide_true, Behavior.classify, if_pos, if_false]
    rw [returnMatch_run_id 47 2 49 _ (by native_decide) (by rfl)]
    simp [Behavior.classify]
  · by_cases second45 : second = 45
    · subst second
      simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
        evaluate_equal_second, decide_true, decide_false, second61,
        Behavior.classify, if_pos, if_false]
      rw [returnMatch_run_id 57 2 59 _ (by native_decide) (by rfl)]
      simp [Behavior.classify]
    · by_cases second62 : second = 62
      · subst second
        simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
          evaluate_equal_second, decide_true, decide_false, second61,
          second45, Behavior.classify, if_pos, if_false]
        rw [returnMatch_run_id 75 2 69 _ (by native_decide) (by rfl)]
        simp [Behavior.classify]
      · simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
          evaluate_equal_second, decide_false, second61, second45,
          second62, Behavior.classify, if_pos, if_false]
        rw [returnMatch_run_id 27 1 33 _ (by native_decide) (by rfl)]
        simp [Behavior.classify]

theorem first61_run (world : ReadOnly.World)
    (baseEnvironment : Env 3) (first second third : Int) :
    Acyclic.run? termEvaluationMachine commandEvaluationMachine world
        (caseEnvironment baseEnvironment first second third) Structure.first61.denote =
      some (.returned (some (Semantics.value
        (Behavior.classify 61 second third).kind
        (Behavior.classify 61 second third).length)),
        world, caseEnvironment baseEnvironment first second third) := by
  simp only [Structure.first61, Structure.orderedCases, List.foldr,
    Structure.sequence_denote, Structure.ifThenElse_denote,
    Structure.skip_denote]
  by_cases second61 : second = 61
  · subst second
    simp only [Acyclic.run?.eq_2, Acyclic.run?.eq_7,
      evaluate_equal_second, decide_true, Behavior.classify, if_pos, if_false]
    rw [returnMatch_run_id 16 2 22 _ (by native_decide) (by rfl)]
    simp [Behavior.classify]
  · by_cases second62 : second = 62
    · subst second
      simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
        evaluate_equal_second, decide_true, decide_false, second61,
        Behavior.classify, if_pos, if_false]
      rw [returnMatch_run_id 113 2 86 _ (by native_decide) (by rfl)]
      simp [Behavior.classify]
    · simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
        evaluate_equal_second, decide_false, second61, second62,
        Behavior.classify, if_pos, if_false]
      rw [returnMatch_run_id 8 1 14 _ (by native_decide) (by rfl)]
      simp [Behavior.classify]

theorem first47_run (world : ReadOnly.World)
    (baseEnvironment : Env 3) (first second third : Int) :
    Acyclic.run? termEvaluationMachine commandEvaluationMachine world
        (caseEnvironment baseEnvironment first second third) Structure.first47.denote =
      some (.returned (some (Semantics.value
        (Behavior.classify 47 second third).kind
        (Behavior.classify 47 second third).length)),
        world, caseEnvironment baseEnvironment first second third) := by
  simp only [Structure.first47, Structure.orderedCases, List.foldr,
    Structure.sequence_denote, Structure.ifThenElse_denote,
    Structure.skip_denote]
  by_cases second47 : second = 47
  · subst second
    simp only [Acyclic.run?.eq_2, Acyclic.run?.eq_7,
      evaluate_equal_second, decide_true, Behavior.classify, if_pos, if_false]
    rw [returnMatch_run_id 10 2 16 _ (by native_decide) (by rfl)]
    simp [Behavior.classify]
  · by_cases second42 : second = 42
    · subst second
      simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
        evaluate_equal_second, decide_true, decide_false, second47,
        Behavior.classify, if_pos, if_false]
      rw [returnMatch_run_id 11 2 17 _ (by native_decide) (by rfl)]
      simp [Behavior.classify]
    · by_cases second61 : second = 61
      · subst second
        simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
          evaluate_equal_second, decide_true, decide_false, second47,
          second42, Behavior.classify, if_pos, if_false]
        rw [returnMatch_run_id 49 2 51 _ (by native_decide) (by rfl)]
        simp [Behavior.classify]
      · simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
          evaluate_equal_second, decide_false, second47, second42,
          second61, Behavior.classify, if_pos, if_false]
        rw [returnMatch_run_id 9 1 15 _ (by native_decide) (by rfl)]
        simp [Behavior.classify]

theorem first38_run (world : ReadOnly.World)
    (baseEnvironment : Env 3) (first second third : Int) :
    Acyclic.run? termEvaluationMachine commandEvaluationMachine world
        (caseEnvironment baseEnvironment first second third) Structure.first38.denote =
      some (.returned (some (Semantics.value
        (Behavior.classify 38 second third).kind
        (Behavior.classify 38 second third).length)),
        world, caseEnvironment baseEnvironment first second third) := by
  simp only [Structure.first38, Structure.orderedCases, List.foldr,
    Structure.sequence_denote, Structure.ifThenElse_denote,
    Structure.skip_denote]
  by_cases second38 : second = 38
  · subst second
    simp only [Acyclic.run?.eq_2, Acyclic.run?.eq_7,
      evaluate_equal_second, decide_true, Behavior.classify, if_pos, if_false]
    rw [returnMatch_run_id 17 2 23 _ (by native_decide) (by rfl)]
    simp [Behavior.classify]
  · by_cases second61 : second = 61
    · subst second
      simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
        evaluate_equal_second, decide_true, decide_false, second38,
        Behavior.classify, if_pos, if_false]
      rw [returnMatch_run_id 54 2 56 _ (by native_decide) (by rfl)]
      simp [Behavior.classify]
    · simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
        evaluate_equal_second, decide_false, second38, second61,
        Behavior.classify, if_pos, if_false]
      rw [returnMatch_run_id 25 1 31 _ (by native_decide) (by rfl)]
      simp [Behavior.classify]

theorem first124_run (world : ReadOnly.World)
    (baseEnvironment : Env 3) (first second third : Int) :
    Acyclic.run? termEvaluationMachine commandEvaluationMachine world
        (caseEnvironment baseEnvironment first second third) Structure.first124.denote =
      some (.returned (some (Semantics.value
        (Behavior.classify 124 second third).kind
        (Behavior.classify 124 second third).length)),
        world, caseEnvironment baseEnvironment first second third) := by
  simp only [Structure.first124, Structure.orderedCases, List.foldr,
    Structure.sequence_denote, Structure.ifThenElse_denote,
    Structure.skip_denote]
  by_cases second124 : second = 124
  · subst second
    simp only [Acyclic.run?.eq_2, Acyclic.run?.eq_7,
      evaluate_equal_second, decide_true, Behavior.classify, if_pos, if_false]
    rw [returnMatch_run_id 18 2 24 _ (by native_decide) (by rfl)]
    simp [Behavior.classify]
  · by_cases second61 : second = 61
    · subst second
      simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
        evaluate_equal_second, decide_true, decide_false, second124,
        Behavior.classify, if_pos, if_false]
      rw [returnMatch_run_id 55 2 57 _ (by native_decide) (by rfl)]
      simp [Behavior.classify]
    · simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
        evaluate_equal_second, decide_false, second124, second61,
        Behavior.classify, if_pos, if_false]
      rw [returnMatch_run_id 26 1 32 _ (by native_decide) (by rfl)]
      simp [Behavior.classify]

theorem first33_run (world : ReadOnly.World)
    (baseEnvironment : Env 3) (first second third : Int) :
    Acyclic.run? termEvaluationMachine commandEvaluationMachine world
        (caseEnvironment baseEnvironment first second third) Structure.first33.denote =
      some (.returned (some (Semantics.value
        (Behavior.classify 33 second third).kind
        (Behavior.classify 33 second third).length)),
        world, caseEnvironment baseEnvironment first second third) := by
  simp only [Structure.first33, Structure.orderedCases, List.foldr,
    Structure.sequence_denote, Structure.ifThenElse_denote,
    Structure.skip_denote]
  by_cases second61 : second = 61
  · subst second
    simp only [Acyclic.run?.eq_2, Acyclic.run?.eq_7,
      evaluate_equal_second, decide_true, Behavior.classify, if_pos, if_false]
    rw [returnMatch_run_id 40 2 42 _ (by native_decide) (by rfl)]
    simp [Behavior.classify]
  · simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
      evaluate_equal_second, decide_false, second61,
      Behavior.classify, if_pos, if_false]
    rw [returnMatch_run_id 19 1 25 _ (by native_decide) (by rfl)]
    simp [Behavior.classify]

theorem first42_run (world : ReadOnly.World)
    (baseEnvironment : Env 3) (first second third : Int) :
    Acyclic.run? termEvaluationMachine commandEvaluationMachine world
        (caseEnvironment baseEnvironment first second third) Structure.first42.denote =
      some (.returned (some (Semantics.value
        (Behavior.classify 42 second third).kind
        (Behavior.classify 42 second third).length)),
        world, caseEnvironment baseEnvironment first second third) := by
  simp only [Structure.first42, Structure.orderedCases, List.foldr,
    Structure.sequence_denote, Structure.ifThenElse_denote,
    Structure.skip_denote]
  by_cases second61 : second = 61
  · subst second
    simp only [Acyclic.run?.eq_2, Acyclic.run?.eq_7,
      evaluate_equal_second, decide_true, Behavior.classify, if_pos, if_false]
    rw [returnMatch_run_id 48 2 50 _ (by native_decide) (by rfl)]
    simp [Behavior.classify]
  · simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
      evaluate_equal_second, decide_false, second61,
      Behavior.classify, if_pos, if_false]
    rw [returnMatch_run_id 7 1 13 _ (by native_decide) (by rfl)]
    simp [Behavior.classify]

theorem first37_run (world : ReadOnly.World)
    (baseEnvironment : Env 3) (first second third : Int) :
    Acyclic.run? termEvaluationMachine commandEvaluationMachine world
        (caseEnvironment baseEnvironment first second third) Structure.first37.denote =
      some (.returned (some (Semantics.value
        (Behavior.classify 37 second third).kind
        (Behavior.classify 37 second third).length)),
        world, caseEnvironment baseEnvironment first second third) := by
  simp only [Structure.first37, Structure.orderedCases, List.foldr,
    Structure.sequence_denote, Structure.ifThenElse_denote,
    Structure.skip_denote]
  by_cases second61 : second = 61
  · subst second
    simp only [Acyclic.run?.eq_2, Acyclic.run?.eq_7,
      evaluate_equal_second, decide_true, Behavior.classify, if_pos, if_false]
    rw [returnMatch_run_id 50 2 52 _ (by native_decide) (by rfl)]
    simp [Behavior.classify]
  · simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
      evaluate_equal_second, decide_false, second61,
      Behavior.classify, if_pos, if_false]
    rw [returnMatch_run_id 41 1 43 _ (by native_decide) (by rfl)]
    simp [Behavior.classify]

theorem first94_run (world : ReadOnly.World)
    (baseEnvironment : Env 3) (first second third : Int) :
    Acyclic.run? termEvaluationMachine commandEvaluationMachine world
        (caseEnvironment baseEnvironment first second third) Structure.first94.denote =
      some (.returned (some (Semantics.value
        (Behavior.classify 94 second third).kind
        (Behavior.classify 94 second third).length)),
        world, caseEnvironment baseEnvironment first second third) := by
  simp only [Structure.first94, Structure.orderedCases, List.foldr,
    Structure.sequence_denote, Structure.ifThenElse_denote,
    Structure.skip_denote]
  by_cases second61 : second = 61
  · subst second
    simp only [Acyclic.run?.eq_2, Acyclic.run?.eq_7,
      evaluate_equal_second, decide_true, Behavior.classify, if_pos, if_false]
    rw [returnMatch_run_id 51 2 53 _ (by native_decide) (by rfl)]
    simp [Behavior.classify]
  · simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
      evaluate_equal_second, decide_false, second61,
      Behavior.classify, if_pos, if_false]
    rw [returnMatch_run_id 42 1 44 _ (by native_decide) (by rfl)]
    simp [Behavior.classify]

theorem first46_run (world : ReadOnly.World)
    (baseEnvironment : Env 3) (first second third : Int) :
    Acyclic.run? termEvaluationMachine commandEvaluationMachine world
        (caseEnvironment baseEnvironment first second third) Structure.first46.denote =
      some (.returned (some (Semantics.value
        (Behavior.classify 46 second third).kind
        (Behavior.classify 46 second third).length)),
        world, caseEnvironment baseEnvironment first second third) := by
  simp only [Structure.first46, Structure.orderedCases, List.foldr,
    Structure.sequence_denote, Structure.ifThenElse_denote,
    Structure.skip_denote]
  by_cases second46 : second = 46
  · subst second
    simp only [Acyclic.run?.eq_2, Acyclic.run?.eq_7,
      evaluate_equal_second, decide_true, Behavior.classify, if_pos, if_false]
    rw [returnMatch_run_id 182 2 87 _ (by native_decide) (by rfl)]
    simp [Behavior.classify]
  · simp only [Acyclic.run?.eq_1, Acyclic.run?.eq_2, Acyclic.run?.eq_7,
      evaluate_equal_second, decide_false, second46,
      Behavior.classify, if_pos, if_false]
    rw [returnMatch_run_id 35 1 37 _ (by native_decide) (by rfl)]
    simp [Behavior.classify]

macro "simplify_symbol_cases" : tactic =>
  `(tactic|
    simp only [Structure.symbolCases, Structure.orderedCases, List.foldr,
      Structure.sequence_denote, Structure.ifThenElse_denote,
      Structure.skip_denote, Acyclic.run?.eq_1, Acyclic.run?.eq_2,
      Acyclic.run?.eq_7, evaluate_equal_first, decide_true, decide_false,
      Int.reduceEq, if_pos, if_false])

theorem symbolCases_run (world : ReadOnly.World)
    (baseEnvironment : Env 3) (first second third : Int) :
    Acyclic.run? termEvaluationMachine commandEvaluationMachine world
        (caseEnvironment baseEnvironment first second third) Structure.symbolCases.denote =
      some (.returned (some (Semantics.value
        (Behavior.classify first second third).kind
        (Behavior.classify first second third).length)),
        world, caseEnvironment baseEnvironment first second third) := by
  by_cases first60 : first = 60
  · subst first
    simplify_symbol_cases
    rw [first60_run]
  · by_cases first62 : first = 62
    · subst first
      simplify_symbol_cases
      rw [first62_run]
    · by_cases first43 : first = 43
      · subst first
        simplify_symbol_cases
        rw [first43_run]
      · by_cases first45 : first = 45
        · subst first
          simplify_symbol_cases
          rw [first45_run]
        · by_cases first61 : first = 61
          · subst first
            simplify_symbol_cases
            rw [first61_run]
          · by_cases first47 : first = 47
            · subst first
              simplify_symbol_cases
              rw [first47_run]
            · by_cases first38 : first = 38
              · subst first
                simplify_symbol_cases
                rw [first38_run]
              · by_cases first124 : first = 124
                · subst first
                  simplify_symbol_cases
                  rw [first124_run]
                · by_cases first33 : first = 33
                  · subst first
                    simplify_symbol_cases
                    rw [first33_run]
                  · by_cases first42 : first = 42
                    · subst first
                      simplify_symbol_cases
                      rw [first42_run]
                    · by_cases first37 : first = 37
                      · subst first
                        simplify_symbol_cases
                        rw [first37_run]
                      · by_cases first94 : first = 94
                        · subst first
                          simplify_symbol_cases
                          rw [first94_run]
                        · by_cases first46 : first = 46
                          · subst first
                            simplify_symbol_cases
                            rw [first46_run]
                          · by_cases first40 : first = 40
                            · subst first
                              simplify_symbol_cases
                              rw [returnMatch_run_id 4 1 10 _
                                (by native_decide) (by rfl)]
                              simp [Behavior.classify]
                            · by_cases first41 : first = 41
                              · subst first
                                simplify_symbol_cases
                                rw [returnMatch_run_id 5 1 11 _
                                  (by native_decide) (by rfl)]
                                simp [Behavior.classify]
                              · by_cases first91 : first = 91
                                · subst first
                                  simplify_symbol_cases
                                  rw [returnMatch_run_id 20 1 26 _
                                    (by native_decide) (by rfl)]
                                  simp [Behavior.classify]
                                · by_cases first93 : first = 93
                                  · subst first
                                    simplify_symbol_cases
                                    rw [returnMatch_run_id 21 1 27 _
                                      (by native_decide) (by rfl)]
                                    simp [Behavior.classify]
                                  · by_cases first123 : first = 123
                                    · subst first
                                      simplify_symbol_cases
                                      rw [returnMatch_run_id 22 1 28 _
                                        (by native_decide) (by rfl)]
                                      simp [Behavior.classify]
                                    · by_cases first125 : first = 125
                                      · subst first
                                        simplify_symbol_cases
                                        rw [returnMatch_run_id 23 1 29 _
                                          (by native_decide) (by rfl)]
                                        simp [Behavior.classify]
                                      · by_cases first126 : first = 126
                                        · subst first
                                          simplify_symbol_cases
                                          rw [returnMatch_run_id 45 1 47 _
                                            (by native_decide) (by rfl)]
                                          simp [Behavior.classify]
                                        · by_cases first44 : first = 44
                                          · subst first
                                            simplify_symbol_cases
                                            rw [returnMatch_run_id 36 1 38 _
                                              (by native_decide) (by rfl)]
                                            simp [Behavior.classify]
                                          · by_cases first59 : first = 59
                                            · subst first
                                              simplify_symbol_cases
                                              rw [returnMatch_run_id 37 1 39 _
                                                (by native_decide) (by rfl)]
                                              simp [Behavior.classify]
                                            · by_cases first58 : first = 58
                                              · subst first
                                                simplify_symbol_cases
                                                rw [returnMatch_run_id 38 1 40 _
                                                  (by native_decide) (by rfl)]
                                                simp [Behavior.classify]
                                              · simp only [Structure.symbolCases,
                                                  Structure.orderedCases,
                                                  List.foldr,
                                                  Structure.sequence_denote,
                                                  Structure.ifThenElse_denote,
                                                  Structure.skip_denote,
                                                  Acyclic.run?.eq_1,
                                                  Acyclic.run?.eq_2,
                                                  Acyclic.run?.eq_7,
                                                  evaluate_equal_first,
                                                  first60, first62, first43,
                                                  first45, first61, first47,
                                                  first38, first124, first33,
                                                  first42, first37, first94,
                                                  first46, first40, first41,
                                                  first91, first93, first123,
                                                  first125, first126, first44,
                                                  first59, first58,
                                                  decide_false, if_false]
                                                rw [returnMatch_run_id 39 1 41 _
                                                  (by native_decide) (by rfl)]
                                                simp [Behavior.classify, *]

theorem matchSymbolHeadCommand_run
    (world : ReadOnly.World) (source : List Int) (start : Nat)
    (sourceFound : world.i32Slice? 0 = some source)
    (sourceBound : source.length ≤ 2147483646)
    (startInBounds : start < source.length) :
    Acyclic.run? termEvaluationMachine commandEvaluationMachine world
        (sourceEnvironment source source.length start)
        Structure.matchSymbolHeadCommand =
      some (.returned (some (Semantics.value
        (Behavior.classify (source.get ⟨start, startInBounds⟩)
          (optionalAt source (start + 1))
          (optionalAt source (start + 2))).kind
        (Behavior.classify (source.get ⟨start, startInBounds⟩)
          (optionalAt source (start + 1))
          (optionalAt source (start + 2))).length)),
        world, sourceEnvironment source source.length start) := by
  have firstEvaluation := evaluate_source_index source start sourceFound
    startInBounds (sourceEnvironment source source.length start)
    (Structure.slot 0).denote (Structure.slot 2).denote
    (by rw [Structure.slot_denote]; rfl)
    (by rw [Structure.slot_denote]; rfl)
  have startTwoBound : start + 2 ≤ 2147483647 := by omega
  unfold Structure.matchSymbolHeadCommand Structure.matchSymbolHeadPattern
  rw [Structure.letValue_denote, Structure.index_denote]
  simp only [Acyclic.run?.eq_3]
  rw [firstEvaluation]
  rw [Structure.letValue_denote]
  simp only [Acyclic.run?.eq_3]
  rw [evaluate_negate_one]
  rw [Structure.letValue_denote]
  simp only [Acyclic.run?.eq_3]
  rw [evaluate_negate_one]
  simp only
  rw [Structure.sequence_denote, Acyclic.run?.eq_2]
  have secondRun := readSecond_run world source start
    (source.get ⟨start, startInBounds⟩) (-1) sourceFound
    (by omega) startInBounds
  unfold caseEnvironment at secondRun
  rw [secondRun]
  simp only
  rw [Structure.sequence_denote, Acyclic.run?.eq_2]
  have thirdRun := readThird_run world source start
    (source.get ⟨start, startInBounds⟩)
    (optionalAt source (start + 1)) sourceFound startTwoBound
  unfold caseEnvironment at thirdRun
  rw [thirdRun]
  simp only
  have casesRun := symbolCases_run world
    (sourceEnvironment source source.length start)
    (source.get ⟨start, startInBounds⟩)
    (optionalAt source (start + 1)) (optionalAt source (start + 2))
  unfold caseEnvironment at casesRun
  rw [casesRun]
  simp

end Lanius.Extraction.Symbol.Execution
