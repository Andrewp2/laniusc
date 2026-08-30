import Lanius.FunctionalViewCoreSimulation

namespace Lanius.FunctionalView.Core.ReadOnly

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.FunctionalView
open Lanius.FunctionalView.Core

/-! # Standard read-only structural-Core dialect

This is the reusable semantic vocabulary for lexer/parser computations over
scalars, program constants, and zero-based `i32` slices. The abstract world
contains mathematical slice contents rather than Core allocation details.
-/

structure World where
  i32Slice? : CellId → Option (List Int)

/-- Functional replacement of one abstract `i32`-slice resource.  Stateful
    FunctionalView actions use this operation; read-only clients are
    unaffected. -/
def World.setI32Slice
    (world : World) (cell : CellId) (values : List Int) : World := {
  i32Slice? := fun candidate =>
    if candidate = cell then some values else world.i32Slice? candidate
}

@[simp] theorem World.setI32Slice_same :
    (World.setI32Slice world cell values).i32Slice? cell = some values := by
  simp [World.setI32Slice]

theorem World.setI32Slice_other
    (different : candidate ≠ cell) :
    (World.setI32Slice world cell values).i32Slice? candidate =
      world.i32Slice? candidate := by
  simp [World.setI32Slice, different]

/-- A read-only proof world containing one encoded `i32` slice. -/
def World.singleton (cell : CellId) (values : List Int) : World := {
  i32Slice? := fun candidate => if candidate = cell then some values else none
}

/-- A proof world containing two distinct encoded slices.  Parser phases use
    this for the immutable grammar and mutable workspace without introducing
    a parser-specific world type. -/
def World.pair (firstCell : CellId) (firstValues : List Int)
    (secondCell : CellId) (secondValues : List Int) : World := {
  i32Slice? := fun candidate =>
    if candidate = firstCell then some firstValues
    else if candidate = secondCell then some secondValues
    else none
}

@[simp] theorem World.pair_finds_first :
    (World.pair firstCell firstValues secondCell secondValues).i32Slice?
      firstCell = some firstValues := by
  simp [World.pair]

@[simp] theorem World.pair_finds_second (different : secondCell ≠ firstCell) :
    (World.pair firstCell firstValues secondCell secondValues).i32Slice?
      secondCell = some secondValues := by
  simp [World.pair, different]

@[simp] theorem World.singleton_finds :
    (World.singleton cell values).i32Slice? cell = some values := by
  simp [World.singleton]

@[simp] theorem World.setI32Slice_singleton :
    World.setI32Slice (World.singleton cell before) cell after =
      World.singleton cell after := by
  apply congrArg World.mk
  funext candidate
  by_cases same : candidate = cell
  · subst candidate
    simp
  · simp [World.setI32Slice, World.singleton, same]

/-- Replacing the second resource in a two-slice world preserves the first
    resource and produces the corresponding canonical pair world. -/
@[simp] theorem World.setI32Slice_pair_second
    (different : secondCell ≠ firstCell) :
    World.setI32Slice
        (World.pair firstCell firstValues secondCell beforeValues)
        secondCell afterValues =
      World.pair firstCell firstValues secondCell afterValues := by
  apply congrArg World.mk
  funext candidate
  by_cases second : candidate = secondCell
  · subst candidate
    simp [World.setI32Slice, World.pair, different]
  · simp [World.setI32Slice, World.pair, second]

def World.Represents (world : World) (state : State) : Prop :=
  ∀ cell values, world.i32Slice? cell = some values →
    state.cellEntry? cell = some {
      id := cell
      value := some (.array (signedI32Values values))
    } ∧ cell < state.nextCell

/-- Separation-logic ownership of every slice named by an abstract world.
    Unlike `Represents`, the assertion stores allocation in its `allocated`
    law, which makes it stable under framed state changes. -/
def World.owns (world : World) : Assertion where
  footprint := fun cell => ∃ values, world.i32Slice? cell = some values
  holds := fun state =>
    ∀ cell values, world.i32Slice? cell = some values →
      state.cellEntry? cell = some {
        id := cell
        value := some (.array (signedI32Values values))
      }
  stable := by
    intro before after agreement held cell values found
    exact (agreement.cell cell ⟨values, found⟩).trans
      (held cell values found)
  allocated := by
    intro state held wellFormed cell member
    obtain ⟨values, found⟩ := member
    exact StateWellFormed.cell_lt_next_of_entry wellFormed
      (held cell values found)

theorem World.owns_iff_represents
    (wellFormed : StateWellFormed state) :
    (World.owns world).holds state ↔ World.Represents world state := by
  constructor
  · intro held cell values found
    have backing := held cell values found
    exact ⟨backing,
      StateWellFormed.cell_lt_next_of_entry wellFormed backing⟩
  · intro represented cell values found
    exact (represented cell values found).1

/-- The standard representation proof for a single encoded slice. -/
theorem World.singleton_represents
    (wellFormed : StateWellFormed state)
    (backing : state.cellEntry? cell = some {
      id := cell
      value := some (.array (signedI32Values values)) }) :
    World.Represents (World.singleton cell values) state := by
  intro candidate contents found
  by_cases same : candidate = cell
  · subst candidate
    have contentsEq : contents = values := by
      simpa [World.singleton] using found.symm
    subst contents
    exact ⟨backing, StateWellFormed.cell_lt_next_of_entry wellFormed backing⟩
  · simp [World.singleton, same] at found

/-- Representation of two distinct encoded slices. -/
theorem World.pair_represents
    (wellFormed : StateWellFormed state)
    (different : secondCell ≠ firstCell)
    (firstBacking : state.cellEntry? firstCell = some {
      id := firstCell
      value := some (.array (signedI32Values firstValues)) })
    (secondBacking : state.cellEntry? secondCell = some {
      id := secondCell
      value := some (.array (signedI32Values secondValues)) }) :
    World.Represents
      (World.pair firstCell firstValues secondCell secondValues) state := by
  intro candidate contents found
  by_cases first : candidate = firstCell
  · subst candidate
    have contentsEq : contents = firstValues := by
      simpa [World.pair] using found.symm
    subst contents
    exact ⟨firstBacking,
      StateWellFormed.cell_lt_next_of_entry wellFormed firstBacking⟩
  · by_cases second : candidate = secondCell
    · subst candidate
      have contentsEq : contents = secondValues := by
        simpa [World.pair, different] using found.symm
      subst contents
      exact ⟨secondBacking,
        StateWellFormed.cell_lt_next_of_entry wellFormed secondBacking⟩
    · simp [World.pair, first, second] at found

def readI32Slice (world : World) (base index : Value) : Except Trap Value :=
  match base, index with
  | .slice (.scalar (.signed .i32)) cell [] 0 length,
      .signed .i32 integer =>
      if _negative : integer < 0 then
        .error .arrayBounds
      else
        match world.i32Slice? cell with
        | none => .error .invalidPointer
        | some values =>
            if _sameLength : length = values.length then
              let position := integer.toNat
              if inBounds : position < values.length then
                .ok (.signed .i32 (values.get ⟨position, inBounds⟩))
              else
                .error .arrayBounds
            else
              .error .arrayBounds
  | _, _ => .error .typeMismatch

def readStructureField (base : Value) (field : FieldId) : Except Trap Value :=
  match base with
  | .structure _ fields =>
      match fields[field]? with
      | some value => .ok value
      | none => .error .typeMismatch
  | _ => .error .typeMismatch

def evaluateOperation (program : Program) (world : World) :
    Operation → List Value → Except Trap (Value × World)
  | .cast _ target, [operand] => do
      let value ← evalScalarCast program.target target operand
      .ok (value, world)
  | .unary operation _ _, [operand] => do
      let value ← evalUnaryValue program.target operation operand
      .ok (value, world)
  | .binary operation _ _ _, [left, right] => do
      let value ← evalBinaryValue program.target operation left right
      .ok (value, world)
  | Operation.index _ _ _, [base, index] => do
      let value ← readI32Slice world base index
      .ok (value, world)
  | .structValue typeId _, values =>
      .ok (.structure typeId values, world)
  | .field _ field _, [base] => do
      let value ← readStructureField base field
      .ok (value, world)
  | .constant id _, [] =>
      match program.constant? id with
      | some declaration => .ok (declaration.value, world)
      | none => .error .invalidPointer
  | .call _ _ _, _ => .error .typeMismatch
  | _, _ => .error .typeMismatch

def machine (program : Program) : Machine signature := {
  World := World
  evalOperation := evaluateOperation program
}

theorem evaluateOperation_world_eq
    (evaluated : evaluateOperation program world operation arguments =
      .ok (value, afterWorld)) :
    afterWorld = world := by
  cases operation <;> simp only [evaluateOperation] at evaluated
  all_goals
    repeat' first
      | split at evaluated
      | contradiction
      | simp only [bind, Except.bind] at evaluated
      | cases evaluated
      | rfl

mutual

  theorem Term.evaluate_world_eq
      (evaluated : Term.evaluate (machine program) world environment term =
        .ok (value, afterWorld)) :
      afterWorld = world := by
    cases term with
    | reference reference =>
        simp only [Term.evaluate] at evaluated
        cases evaluated
        rfl
    | apply operation arguments =>
        rw [Term.evaluate] at evaluated
        cases argumentsResult :
          evaluateTerms (machine program) world environment arguments with
        | error reason =>
            rw [argumentsResult] at evaluated
            contradiction
        | ok result =>
            obtain ⟨values, argumentsWorld⟩ := result
            rw [argumentsResult] at evaluated
            have operationWorld := evaluateOperation_world_eq evaluated
            have argumentsWorldEq := evaluateTerms_world_eq argumentsResult
            exact operationWorld.trans argumentsWorldEq
    | logicalAnd left right =>
        rw [Term.evaluate] at evaluated
        cases leftResult : Term.evaluate (machine program) world environment left with
        | error reason =>
            simp only [leftResult, bind, Except.bind] at evaluated
            contradiction
        | ok result =>
            obtain ⟨leftValue, leftWorld⟩ := result
            simp only [leftResult, bind, Except.bind] at evaluated
            have leftWorldEq := Term.evaluate_world_eq leftResult
            cases leftValue with
            | boolean value =>
                cases value with
                | false =>
                    cases evaluated
                    exact leftWorldEq
                | true =>
                    exact (Term.evaluate_world_eq evaluated).trans leftWorldEq
            | _ => contradiction
    | logicalOr left right =>
        rw [Term.evaluate] at evaluated
        cases leftResult : Term.evaluate (machine program) world environment left with
        | error reason =>
            simp only [leftResult, bind, Except.bind] at evaluated
            contradiction
        | ok result =>
            obtain ⟨leftValue, leftWorld⟩ := result
            simp only [leftResult, bind, Except.bind] at evaluated
            have leftWorldEq := Term.evaluate_world_eq leftResult
            cases leftValue with
            | boolean value =>
                cases value with
                | false =>
                    exact (Term.evaluate_world_eq evaluated).trans leftWorldEq
                | true =>
                    cases evaluated
                    exact leftWorldEq
            | _ => contradiction

  theorem evaluateTerms_world_eq
      (evaluated : evaluateTerms (machine program) world environment terms =
        .ok (values, afterWorld)) :
      afterWorld = world := by
    cases terms with
    | nil =>
        simp only [evaluateTerms] at evaluated
        cases evaluated
        rfl
    | cons head tail =>
        rw [evaluateTerms] at evaluated
        cases headResult : Term.evaluate (machine program) world environment head with
        | error reason =>
            rw [headResult] at evaluated
            contradiction
        | ok result =>
            obtain ⟨headValue, headWorld⟩ := result
            rw [headResult] at evaluated
            simp only [bind, Except.bind] at evaluated
            cases tailResult :
              evaluateTerms (machine program) headWorld environment tail with
            | error reason =>
                rw [tailResult] at evaluated
                contradiction
            | ok result =>
                obtain ⟨tailValues, tailWorld⟩ := result
                rw [tailResult] at evaluated
                cases evaluated
                exact (evaluateTerms_world_eq tailResult).trans
                  (Term.evaluate_world_eq headResult)

end

theorem evaluateOperation_constant
    {id : ConstantId} {declaration : Constant}
    (found : program.constant? id = some declaration) :
    evaluateOperation program world (.constant id type) [] =
      .ok (declaration.value, world) := by
  simp [evaluateOperation, found]

theorem evaluateOperation_i32_index
    (found : world.i32Slice? cell = some values)
    (inBounds : position < values.length) :
    evaluateOperation program world
        (.index baseType indexType elementType)
        [.slice (.scalar (.signed .i32)) cell [] 0 values.length,
          .signed .i32 (Int.ofNat position)] =
      .ok (.signed .i32 (values.get ⟨position, inBounds⟩), world) := by
  have nonnegative : ¬(↑position : Int) < 0 := by omega
  simp [evaluateOperation, readI32Slice, found, inBounds, nonnegative, bind,
    Except.bind]

theorem evaluateOperation_i32_equal (left right : Nat) :
    evaluateOperation program world
        (.binary .equal leftType rightType outputType)
        [.signed .i32 (Int.ofNat left), .signed .i32 (Int.ofNat right)] =
      .ok (.boolean (decide (left = right)), world) := by
  by_cases same : left = right
  · subst right
    simp [evaluateOperation, evalBinaryValue, scalarEqual, bind, Except.bind]
  · have castDifferent : Int.ofNat left ≠ Int.ofNat right := by
      exact fun equal => same (Int.ofNat_inj.mp equal)
    simp [evaluateOperation, evalBinaryValue, scalarEqual, same,
      bind, Except.bind]
    simpa using castDifferent

theorem evaluateOperation_i32_notEqual_int (left right : Int) :
    evaluateOperation program world
        (.binary .notEqual leftType rightType outputType)
        [.signed .i32 left, .signed .i32 right] =
      .ok (.boolean (decide (left ≠ right)), world) := by
  by_cases same : left = right
  · subst right
    simp [evaluateOperation, evalBinaryValue, scalarEqual, bind, Except.bind]
  · simp [evaluateOperation, evalBinaryValue, scalarEqual, same,
      bind, Except.bind]

theorem decide_intOfNat_notEqual (left right : Nat) :
    decide (Int.ofNat left ≠ Int.ofNat right) = (left != right) := by
  apply Bool.eq_iff_iff.mpr
  constructor
  · intro decided
    have castDifferent : Int.ofNat left ≠ Int.ofNat right :=
      of_decide_eq_true decided
    exact bne_iff_ne.mpr (fun equal =>
      castDifferent (congrArg Int.ofNat equal))
  · intro different
    apply decide_eq_true
    intro equal
    exact bne_iff_ne.mp different (Int.ofNat_inj.mp equal)

theorem evaluateOperation_i32_greaterEqual (left right : Nat) :
    evaluateOperation program world
        (.binary .greaterEqual leftType rightType outputType)
        [.signed .i32 (Int.ofNat left), .signed .i32 (Int.ofNat right)] =
      .ok (.boolean (decide (left ≥ right)), world) := by
  simp [evaluateOperation, evalBinaryValue, evalSignedBinary, bind, Except.bind]

theorem evaluateOperation_i32_greaterEqual_int (left right : Int) :
    evaluateOperation program world
        (.binary .greaterEqual leftType rightType outputType)
        [.signed .i32 left, .signed .i32 right] =
      .ok (.boolean (decide (left ≥ right)), world) := by
  simp [evaluateOperation, evalBinaryValue, evalSignedBinary, bind, Except.bind]

theorem evaluateOperation_i32_lessEqual_int (left right : Int) :
    evaluateOperation program world
        (.binary .lessEqual leftType rightType outputType)
        [.signed .i32 left, .signed .i32 right] =
      .ok (.boolean (decide (left ≤ right)), world) := by
  simp [evaluateOperation, evalBinaryValue, evalSignedBinary, bind, Except.bind]

theorem evaluateOperation_i32_less_int (left right : Int) :
    evaluateOperation program world
        (.binary .less leftType rightType outputType)
        [.signed .i32 left, .signed .i32 right] =
      .ok (.boolean (decide (left < right)), world) := by
  simp [evaluateOperation, evalBinaryValue, evalSignedBinary, bind, Except.bind]

theorem evaluateOperation_i32_greater_int (left right : Int) :
    evaluateOperation program world
        (.binary .greater leftType rightType outputType)
        [.signed .i32 left, .signed .i32 right] =
      .ok (.boolean (decide (left > right)), world) := by
  simp [evaluateOperation, evalBinaryValue, evalSignedBinary, bind, Except.bind]

theorem evaluateOperation_i32_less (left right : Nat) :
    evaluateOperation program world
        (.binary .less leftType rightType outputType)
        [.signed .i32 (Int.ofNat left), .signed .i32 (Int.ofNat right)] =
      .ok (.boolean (decide (left < right)), world) := by
  simpa [Int.ofNat_lt] using
    (evaluateOperation_i32_less_int (program := program) (world := world)
      (leftType := leftType) (rightType := rightType)
      (outputType := outputType) (Int.ofNat left) (Int.ofNat right))

theorem evaluateOperation_i32_greater (left right : Nat) :
    evaluateOperation program world
        (.binary .greater leftType rightType outputType)
        [.signed .i32 (Int.ofNat left), .signed .i32 (Int.ofNat right)] =
      .ok (.boolean (decide (left > right)), world) := by
  simpa [Int.ofNat_lt] using
    (evaluateOperation_i32_greater_int (program := program) (world := world)
      (leftType := leftType) (rightType := rightType)
      (outputType := outputType) (Int.ofNat left) (Int.ofNat right))

theorem evaluateOperation_i32_subtract_int (left right : Int) :
    evaluateOperation program world
        (.binary .subtract leftType rightType outputType)
        [.signed .i32 left, .signed .i32 right] =
      .ok (.signed .i32 (wrapSigned program.target .i32 (left - right)),
        world) := by
  simp [evaluateOperation, evalBinaryValue, evalSignedBinary, bind, Except.bind]

theorem evaluateOperation_i32_subtract (left right : Nat)
    (lower : right ≤ left) (bounded : left - right ≤ 2147483647) :
    evaluateOperation program world
        (.binary .subtract leftType rightType outputType)
        [.signed .i32 (Int.ofNat left), .signed .i32 (Int.ofNat right)] =
      .ok (.signed .i32 (Int.ofNat (left - right)), world) := by
  rw [evaluateOperation_i32_subtract_int]
  have difference : Int.ofNat left - Int.ofNat right =
      Int.ofNat (left - right) := (Int.ofNat_sub lower).symm
  rw [difference, wrapSigned_i32_ofNat program.target _ bounded]

theorem evaluateOperation_bool_and (left right : Bool) :
    evaluateOperation program world
        (.binary .logicalAnd leftType rightType outputType)
        [.boolean left, .boolean right] =
      .ok (.boolean (left && right), world) := by
  simp [evaluateOperation, evalBinaryValue, bind, Except.bind]

theorem evaluateOperation_i32_negate_one :
    evaluateOperation program world
        (.unary .negate inputType outputType)
        [.signed .i32 1] = .ok (.signed .i32 (-1), world) := by
  simp [evaluateOperation, evalUnaryValue, wrapSigned_i32_neg_one, bind,
    Except.bind]

theorem evaluateOperation_i32_add (left right : Nat)
    (bounded : left + right ≤ 2147483647) :
    evaluateOperation program world
        (.binary .add leftType rightType outputType)
        [.signed .i32 (Int.ofNat left), .signed .i32 (Int.ofNat right)] =
      .ok (.signed .i32 (Int.ofNat (left + right)), world) := by
  have cast : Int.ofNat left + Int.ofNat right = Int.ofNat (left + right) :=
    (Int.natCast_add left right).symm
  simp [evaluateOperation, evalBinaryValue, evalSignedBinary, bind, Except.bind]
  rw [show (↑left : Int) + ↑right = Int.ofNat (left + right) by
    exact cast]
  exact wrapSigned_i32_ofNat program.target (left + right) bounded

theorem evaluateOperation_i32_divide_two (value : Nat)
    (bounded : value / 2 ≤ 2147483647) :
    evaluateOperation program world
        (.binary .divide leftType rightType outputType)
        [.signed .i32 (Int.ofNat value), .signed .i32 2] =
      .ok (.signed .i32 (Int.ofNat (value / 2)), world) := by
  have quotient : truncDiv (Int.ofNat value) 2 = Int.ofNat (value / 2) := by
    simp [truncDiv]
  simp [evaluateOperation, evalBinaryValue, evalSignedBinary, bind, Except.bind]
  rw [show truncDiv (↑value) 2 = Int.ofNat (value / 2) by simpa using quotient]
  rw [wrapSigned_i32_ofNat program.target (value / 2) bounded]
  rfl

theorem evaluateOperation_i32_remainder_two (value : Nat) :
    evaluateOperation program world
        (.binary .remainder leftType rightType outputType)
        [.signed .i32 (Int.ofNat value), .signed .i32 2] =
      .ok (.signed .i32 (Int.ofNat (value % 2)), world) := by
  have remainder : Int.ofNat value - truncDiv (Int.ofNat value) 2 * 2 =
      Int.ofNat (value % 2) := by
    have sameDivision : truncDiv (Int.ofNat value) 2 =
        (Int.ofNat value).tdiv 2 := by
      rw [show truncDiv (Int.ofNat value) 2 = Int.ofNat (value / 2) by
        simp [truncDiv]]
      exact Int.ofNat_tdiv value 2
    calc
      Int.ofNat value - truncDiv (Int.ofNat value) 2 * 2 =
          Int.ofNat value - 2 * (Int.ofNat value).tdiv 2 := by
            rw [sameDivision, Int.mul_comm]
      _ = (Int.ofNat value).tmod 2 :=
        (Int.tmod_def (Int.ofNat value) 2).symm
      _ = Int.ofNat (value % 2) :=
        (Int.ofNat_tmod value 2).symm
  simp [evaluateOperation, evalBinaryValue, evalSignedBinary, bind, Except.bind]
  rw [show (↑value : Int) - truncDiv (↑value) 2 * 2 =
      Int.ofNat (value % 2) by simpa using remainder]
  rw [wrapSigned_i32_ofNat program.target (value % 2) (by omega)]
  rfl

theorem Term.evaluate_constant
    {id : ConstantId} {declaration : Constant}
    (found : program.constant? id = some declaration) :
    Term.evaluate (machine program) world environment
        (.apply (.constant id type) []) =
      .ok (declaration.value, world) :=
  Term.evaluate_apply0 (evaluateOperation_constant (type := type) found)

theorem Term.evaluate_i32_index
    (baseResult : Term.evaluate (machine program) world environment base =
      .ok (.slice (.scalar (.signed .i32)) cell [] 0 values.length, world))
    (indexResult : Term.evaluate (machine program) world environment index =
      .ok (.signed .i32 (Int.ofNat position), world))
    (found : world.i32Slice? cell = some values)
    (inBounds : position < values.length) :
    Term.evaluate (machine program) world environment
        (.apply
          (.index baseType indexType elementType)
          [base, index]) =
      .ok (.signed .i32 (values.get ⟨position, inBounds⟩), world) :=
  Term.evaluate_apply2 baseResult indexResult
    (evaluateOperation_i32_index (program := program) (baseType := baseType)
      (indexType := indexType) (elementType := elementType) found inBounds)

/-- Read an `i32` slice element and immediately rewrite its mathematical
    value. This lets table-layout facts participate directly in compositional
    evaluation instead of requiring a named intermediate read theorem. -/
theorem Term.evaluate_i32_index_as
    (baseResult : Term.evaluate (machine program) world environment base =
      .ok (.slice (.scalar (.signed .i32)) cell [] 0 values.length, world))
    (indexResult : Term.evaluate (machine program) world environment index =
      .ok (.signed .i32 (Int.ofNat position), world))
    (found : world.i32Slice? cell = some values)
    (inBounds : position < values.length)
    (same : values.get ⟨position, inBounds⟩ = expected) :
    Term.evaluate (machine program) world environment
        (.apply
          (.index baseType indexType elementType)
          [base, index]) =
      .ok (.signed .i32 expected, world) := by
  apply Term.evaluate_congr
    (Term.evaluate_i32_index baseResult indexResult found inBounds)
  exact congrArg (Value.signed .i32) same

theorem Term.evaluate_i32_equal
    (leftResult : Term.evaluate (machine program) world environment left =
      .ok (.signed .i32 (Int.ofNat leftValue), world))
    (rightResult : Term.evaluate (machine program) world environment right =
      .ok (.signed .i32 (Int.ofNat rightValue), world)) :
    Term.evaluate (machine program) world environment
        (.apply
          (.binary .equal leftType rightType outputType)
          [left, right]) =
      .ok (.boolean (decide (leftValue = rightValue)), world) :=
  Term.evaluate_apply2 leftResult rightResult
    (evaluateOperation_i32_equal (leftType := leftType)
      (rightType := rightType) (outputType := outputType)
      leftValue rightValue)

theorem Term.evaluate_i32_notEqual_int
    (leftResult : Term.evaluate (machine program) world environment left =
      .ok (.signed .i32 leftValue, world))
    (rightResult : Term.evaluate (machine program) world environment right =
      .ok (.signed .i32 rightValue, world)) :
    Term.evaluate (machine program) world environment
        (.apply
          (.binary .notEqual leftType rightType outputType)
          [left, right]) =
      .ok (.boolean (decide (leftValue ≠ rightValue)), world) :=
  Term.evaluate_apply2 leftResult rightResult
    (evaluateOperation_i32_notEqual_int (leftType := leftType)
      (rightType := rightType) (outputType := outputType)
      leftValue rightValue)

theorem Term.evaluate_i32_greaterEqual
    (leftResult : Term.evaluate (machine program) world environment left =
      .ok (.signed .i32 (Int.ofNat leftValue), world))
    (rightResult : Term.evaluate (machine program) world environment right =
      .ok (.signed .i32 (Int.ofNat rightValue), world)) :
    Term.evaluate (machine program) world environment
        (.apply
          (.binary .greaterEqual leftType rightType outputType)
          [left, right]) =
      .ok (.boolean (decide (leftValue ≥ rightValue)), world) :=
  Term.evaluate_apply2 leftResult rightResult
    (evaluateOperation_i32_greaterEqual (leftType := leftType)
      (rightType := rightType) (outputType := outputType)
      leftValue rightValue)

theorem Term.evaluate_i32_greaterEqual_int
    (leftResult : Term.evaluate (machine program) world environment left =
      .ok (.signed .i32 leftValue, world))
    (rightResult : Term.evaluate (machine program) world environment right =
      .ok (.signed .i32 rightValue, world)) :
    Term.evaluate (machine program) world environment
        (.apply
          (.binary .greaterEqual leftType rightType outputType)
          [left, right]) =
      .ok (.boolean (decide (leftValue ≥ rightValue)), world) :=
  Term.evaluate_apply2 leftResult rightResult
    (evaluateOperation_i32_greaterEqual_int (leftType := leftType)
      (rightType := rightType) (outputType := outputType)
      leftValue rightValue)

theorem Term.evaluate_i32_lessEqual_int
    (leftResult : Term.evaluate (machine program) world environment left =
      .ok (.signed .i32 leftValue, world))
    (rightResult : Term.evaluate (machine program) world environment right =
      .ok (.signed .i32 rightValue, world)) :
    Term.evaluate (machine program) world environment
        (.apply
          (.binary .lessEqual leftType rightType outputType)
          [left, right]) =
      .ok (.boolean (decide (leftValue ≤ rightValue)), world) :=
  Term.evaluate_apply2 leftResult rightResult
    (evaluateOperation_i32_lessEqual_int (leftType := leftType)
      (rightType := rightType) (outputType := outputType)
      leftValue rightValue)

theorem Term.evaluate_i32_less_int
    (leftResult : Term.evaluate (machine program) world environment left =
      .ok (.signed .i32 leftValue, world))
    (rightResult : Term.evaluate (machine program) world environment right =
      .ok (.signed .i32 rightValue, world)) :
    Term.evaluate (machine program) world environment
        (.apply
          (.binary .less leftType rightType outputType)
          [left, right]) =
      .ok (.boolean (decide (leftValue < rightValue)), world) :=
  Term.evaluate_apply2 leftResult rightResult
    (evaluateOperation_i32_less_int (leftType := leftType)
      (rightType := rightType) (outputType := outputType)
      leftValue rightValue)

theorem Term.evaluate_i32_greater_int
    (leftResult : Term.evaluate (machine program) world environment left =
      .ok (.signed .i32 leftValue, world))
    (rightResult : Term.evaluate (machine program) world environment right =
      .ok (.signed .i32 rightValue, world)) :
    Term.evaluate (machine program) world environment
        (.apply
          (.binary .greater leftType rightType outputType)
          [left, right]) =
      .ok (.boolean (decide (leftValue > rightValue)), world) :=
  Term.evaluate_apply2 leftResult rightResult
    (evaluateOperation_i32_greater_int (leftType := leftType)
      (rightType := rightType) (outputType := outputType)
      leftValue rightValue)

theorem Term.evaluate_i32_less
    (leftResult : Term.evaluate (machine program) world environment left =
      .ok (.signed .i32 (Int.ofNat leftValue), world))
    (rightResult : Term.evaluate (machine program) world environment right =
      .ok (.signed .i32 (Int.ofNat rightValue), world)) :
    Term.evaluate (machine program) world environment
        (.apply
          (.binary .less leftType rightType outputType)
          [left, right]) =
      .ok (.boolean (decide (leftValue < rightValue)), world) :=
  Term.evaluate_apply2 leftResult rightResult
    (evaluateOperation_i32_less (leftType := leftType)
      (rightType := rightType) (outputType := outputType)
      leftValue rightValue)

theorem Term.evaluate_i32_greater
    (leftResult : Term.evaluate (machine program) world environment left =
      .ok (.signed .i32 (Int.ofNat leftValue), world))
    (rightResult : Term.evaluate (machine program) world environment right =
      .ok (.signed .i32 (Int.ofNat rightValue), world)) :
    Term.evaluate (machine program) world environment
        (.apply
          (.binary .greater leftType rightType outputType)
          [left, right]) =
      .ok (.boolean (decide (leftValue > rightValue)), world) :=
  Term.evaluate_apply2 leftResult rightResult
    (evaluateOperation_i32_greater (leftType := leftType)
      (rightType := rightType) (outputType := outputType)
      leftValue rightValue)

theorem Term.evaluate_i32_subtract_int
    (leftResult : Term.evaluate (machine program) world environment left =
      .ok (.signed .i32 leftValue, world))
    (rightResult : Term.evaluate (machine program) world environment right =
      .ok (.signed .i32 rightValue, world)) :
    Term.evaluate (machine program) world environment
        (.apply
          (.binary .subtract leftType rightType outputType)
          [left, right]) =
      .ok (.signed .i32
        (wrapSigned program.target .i32 (leftValue - rightValue)), world) :=
  Term.evaluate_apply2 leftResult rightResult
    (evaluateOperation_i32_subtract_int (leftType := leftType)
      (rightType := rightType) (outputType := outputType)
      leftValue rightValue)

theorem Term.evaluate_i32_subtract
    (leftResult : Term.evaluate (machine program) world environment left =
      .ok (.signed .i32 (Int.ofNat leftValue), world))
    (rightResult : Term.evaluate (machine program) world environment right =
      .ok (.signed .i32 (Int.ofNat rightValue), world))
    (lower : rightValue ≤ leftValue)
    (bounded : leftValue - rightValue ≤ 2147483647) :
    Term.evaluate (machine program) world environment
        (.apply
          (.binary .subtract leftType rightType outputType)
          [left, right]) =
      .ok (.signed .i32 (Int.ofNat (leftValue - rightValue)), world) :=
  Term.evaluate_apply2 leftResult rightResult
    (evaluateOperation_i32_subtract (leftType := leftType)
      (rightType := rightType) (outputType := outputType)
      leftValue rightValue lower bounded)

theorem Term.evaluate_bool_and
    (leftResult : Term.evaluate (machine program) world environment left =
      .ok (.boolean leftValue, world))
    (rightResult : Term.evaluate (machine program) world environment right =
      .ok (.boolean rightValue, world)) :
    Term.evaluate (machine program) world environment
        (.apply
          (.binary .logicalAnd leftType rightType outputType)
          [left, right]) =
      .ok (.boolean (leftValue && rightValue), world) :=
  Term.evaluate_apply2 leftResult rightResult
    (evaluateOperation_bool_and (leftType := leftType)
      (rightType := rightType) (outputType := outputType)
      leftValue rightValue)

/-- Read-only short-circuit conjunction.  The right-hand proof is accepted
    uniformly, but evaluation uses it only when the left operand is true. -/
theorem Term.evaluate_logicalAnd_bool
    (leftResult : Term.evaluate (machine program) world environment left =
      .ok (.boolean leftValue, world))
    (rightResult : Term.evaluate (machine program) world environment right =
      .ok (.boolean rightValue, world)) :
    Term.evaluate (machine program) world environment
        (.logicalAnd left right) =
      .ok (.boolean (leftValue && rightValue), world) := by
  cases leftValue
  · simpa using Term.evaluate_logicalAnd_false leftResult
  · simpa using Term.evaluate_logicalAnd_true leftResult rightResult

/-- Read-only short-circuit disjunction. -/
theorem Term.evaluate_logicalOr_bool
    (leftResult : Term.evaluate (machine program) world environment left =
      .ok (.boolean leftValue, world))
    (rightResult : Term.evaluate (machine program) world environment right =
      .ok (.boolean rightValue, world)) :
    Term.evaluate (machine program) world environment
        (.logicalOr left right) =
      .ok (.boolean (leftValue || rightValue), world) := by
  cases leftValue
  · simpa using Term.evaluate_logicalOr_false leftResult rightResult
  · simpa using Term.evaluate_logicalOr_true leftResult

theorem Term.evaluate_i32_negate_one :
    Term.evaluate (machine program) world environment
        (.apply
          (.unary .negate inputType outputType)
          [.reference (.literal (.signed .i32 1))]) =
      .ok (.signed .i32 (-1), world) :=
  Term.evaluate_apply1 (by rfl)
    (evaluateOperation_i32_negate_one (inputType := inputType)
      (outputType := outputType))

theorem Term.evaluate_i32_add
    (leftResult : Term.evaluate (machine program) world environment left =
      .ok (.signed .i32 (Int.ofNat leftValue), world))
    (rightResult : Term.evaluate (machine program) world environment right =
      .ok (.signed .i32 (Int.ofNat rightValue), world))
    (bounded : leftValue + rightValue ≤ 2147483647) :
    Term.evaluate (machine program) world environment
        (.apply
          (.binary .add leftType rightType outputType)
          [left, right]) =
      .ok (.signed .i32 (Int.ofNat (leftValue + rightValue)), world) :=
  Term.evaluate_apply2 leftResult rightResult
    (evaluateOperation_i32_add (leftType := leftType)
      (rightType := rightType) (outputType := outputType)
      leftValue rightValue bounded)

theorem Term.evaluate_i32_divide_two
    (valueResult : Term.evaluate (machine program) world environment value =
      .ok (.signed .i32 (Int.ofNat natural), world))
    (bounded : natural / 2 ≤ 2147483647) :
    Term.evaluate (machine program) world environment
        (.apply
          (.binary .divide leftType rightType outputType)
          [value, .reference (.literal (.signed .i32 2))]) =
      .ok (.signed .i32 (Int.ofNat (natural / 2)), world) :=
  Term.evaluate_apply2 valueResult (by rfl)
    (evaluateOperation_i32_divide_two (leftType := leftType)
      (rightType := rightType) (outputType := outputType) natural bounded)

theorem Term.evaluate_i32_remainder_two
    (valueResult : Term.evaluate (machine program) world environment value =
      .ok (.signed .i32 (Int.ofNat natural), world)) :
    Term.evaluate (machine program) world environment
        (.apply
          (.binary .remainder leftType rightType outputType)
          [value, .reference (.literal (.signed .i32 2))]) =
      .ok (.signed .i32 (Int.ofNat (natural % 2)), world) :=
  Term.evaluate_apply2 valueResult (by rfl)
    (evaluateOperation_i32_remainder_two (leftType := leftType)
      (rightType := rightType) (outputType := outputType) natural)

section FunctionalEvalTactic

open Lean Elab Tactic Meta

private partial def visitFunctionalEvalGoals (deferred : List MVarId) :
    TacticM Unit := do
  match ← getGoals with
  | [] => setGoals deferred.reverse
  | goal :: rest =>
      setGoals [goal]
      let progressed ←
        try
          evalTactic (← `(tactic|
            first
            | assumption
            | rfl
            | omega
            | apply Term.evaluate_logicalAnd_bool
            | apply Term.evaluate_logicalOr_bool
            | apply Term.evaluate_bool_and
            | apply Term.evaluate_i32_equal
            | apply Term.evaluate_i32_notEqual_int
            | apply Term.evaluate_i32_greaterEqual
            | apply Term.evaluate_i32_greaterEqual_int
            | apply Term.evaluate_i32_lessEqual_int
            | apply Term.evaluate_i32_less
            | apply Term.evaluate_i32_less_int
            | apply Term.evaluate_i32_greater
            | apply Term.evaluate_i32_greater_int
            | apply Term.evaluate_i32_subtract
            | apply Term.evaluate_i32_subtract_int
            | apply Term.evaluate_i32_remainder_two
            | apply Term.evaluate_i32_add
            | apply Term.evaluate_i32_divide_two
            | apply Term.evaluate_i32_index_as
            | apply Term.evaluate_i32_index
            | apply Term.evaluate_constant
            | apply Term.evaluate_slot))
          pure true
        catch _ =>
          pure false
      if progressed then
        let children ← getGoals
        setGoals (children ++ rest)
        visitFunctionalEvalGoals deferred
      else
        setGoals rest
        visitFunctionalEvalGoals (goal :: deferred)

/-- Evaluate a term in the supported read-only FunctionalView fragment by
    composing its primitive semantic rules on every generated subgoal. Local
    hypotheses discharge exact constant-table contents, slice membership, and
    integer bounds. -/
elab "functional_eval" : tactic => do
  visitFunctionalEvalGoals []
  evalTactic (← `(tactic| all_goals simp_all))

end FunctionalEvalTactic

theorem World.Represents.bindLocal
    {id : VarId} {value : Value}
    (represented : World.Represents world state) :
    World.Represents world (state.bindLocal id value) := by
  intro cell values found
  obtain ⟨backing, old⟩ := represented cell values found
  constructor
  · exact (bindCell_preserves_old_cell state id (some value) cell old).trans
      backing
  · simpa [State.bindLocal, State.bindCell] using Nat.lt_succ_of_lt old

theorem World.Represents.restoreLocals
    (represented : World.Represents world completed) :
    World.Represents world
      (Lanius.Semantics.restoreLocals caller completed) := by
  intro cell values found
  obtain ⟨backing, old⟩ := represented cell values found
  exact ⟨by
    simpa [Lanius.Semantics.restoreLocals, State.cellEntry?] using backing,
    by simpa [Lanius.Semantics.restoreLocals] using old⟩

private theorem logicalAnd_result
    (evaluated : evalBinaryValue target .logicalAnd left right = .ok result) :
    ∃ leftBool rightBool,
      left = .boolean leftBool ∧ right = .boolean rightBool ∧
      result = .boolean (leftBool && rightBool) := by
  cases left <;> cases right <;>
    simp [evalBinaryValue, evalSignedBinary, evalUnsignedBinary,
      evalF32Binary, evalF64Binary, evalCharBinary] at evaluated
  exact ⟨_, _, rfl, rfl, evaluated.symm⟩

private theorem logicalOr_result
    (evaluated : evalBinaryValue target .logicalOr left right = .ok result) :
    ∃ leftBool rightBool,
      left = .boolean leftBool ∧ right = .boolean rightBool ∧
      result = .boolean (leftBool || rightBool) := by
  cases left <;> cases right <;>
    simp [evalBinaryValue, evalSignedBinary, evalUnsignedBinary,
      evalF32Binary, evalF64Binary, evalCharBinary] at evaluated
  exact ⟨_, _, rfl, rfl, evaluated.symm⟩

theorem readI32Slice_result
    (evaluated : readI32Slice world base index = .ok result) :
    ∃ cell values position, ∃ inBounds : position < values.length,
      world.i32Slice? cell = some values ∧
      base = .slice (.scalar (.signed .i32)) cell [] 0 values.length ∧
      index = .signed .i32 (Int.ofNat position) ∧
      result = .signed .i32 (values.get ⟨position, inBounds⟩) := by
  cases base
  case slice elementType cell projections start length =>
    cases index
    case signed integerType integer =>
      simp [readI32Slice] at evaluated
      split at evaluated <;> try simp_all
      split at evaluated <;> try simp_all
      split at evaluated <;> try simp_all
      split at evaluated <;> try simp_all
      split at evaluated <;> try simp_all
      obtain ⟨rfl, rfl, rfl, rfl, rfl⟩ :
          elementType = .scalar (.signed .i32) ∧ cell = _ ∧
            projections = [] ∧ start = 0 ∧ length = _ := by
        assumption
      obtain ⟨rfl, rfl⟩ : integerType = .i32 ∧ integer = _ := by
        assumption
      refine ⟨cell, _, ‹_›, ⟨rfl, rfl⟩, integer.toNat, ?_, ?_⟩
      · exact (Int.toNat_of_nonneg (by omega)).symm
      · subst result
        exact ⟨by omega, rfl⟩
    all_goals simp [readI32Slice] at evaluated
  all_goals cases index <;> simp [readI32Slice] at evaluated

theorem readStructureField_result
    (evaluated : readStructureField base field = .ok value) :
    ∃ structureId fields,
      base = .structure structureId fields ∧ fields[field]? = some value := by
  cases base <;> simp [readStructureField] at evaluated
  next structureId fields =>
    cases found : fields[field]? with
    | none => simp [found] at evaluated
    | some result =>
        simp [found] at evaluated
        subst result
        exact ⟨structureId, fields, rfl, found⟩

private theorem cast_sound
    (arguments : ExpressionsEvaluate program state expressions values)
    (evaluated : evaluateOperation program world
      (.cast source target) values = .ok (value, afterWorld)) :
    Evaluates program state
        (Operation.toCoreExpr (.cast source target) expressions)
        value state ∧ afterWorld = world := by
  cases arguments with
  | nil => simp [evaluateOperation] at evaluated
  | cons operand rest =>
      cases rest with
      | cons _ _ => simp [evaluateOperation] at evaluated
      | nil =>
          simp only [evaluateOperation, bind, Except.bind] at evaluated
          cases operationResult : evalScalarCast program.target target _ with
          | error reason =>
              rw [operationResult] at evaluated
              contradiction
          | ok result =>
              rw [operationResult] at evaluated
              obtain ⟨rfl, rfl⟩ := evaluated
              exact ⟨evaluatesCast operand operationResult, rfl⟩

private theorem field_sound
    (arguments : ExpressionsEvaluate program state expressions values)
    (evaluated : evaluateOperation program world
      (.field baseType field resultType) values = .ok (value, afterWorld)) :
    Evaluates program state
        (Operation.toCoreExpr (.field baseType field resultType) expressions)
        value state ∧ afterWorld = world := by
  cases arguments with
  | nil => simp [evaluateOperation] at evaluated
  | cons base rest =>
      cases rest with
      | cons _ _ => simp [evaluateOperation] at evaluated
      | nil =>
          simp only [evaluateOperation, bind, Except.bind] at evaluated
          cases fieldResult : readStructureField _ field with
          | error reason =>
              rw [fieldResult] at evaluated
              contradiction
          | ok result =>
              rw [fieldResult] at evaluated
              obtain ⟨rfl, rfl⟩ := evaluated
              obtain ⟨structureId, fields, rfl, found⟩ :=
                readStructureField_result fieldResult
              exact ⟨evaluatesStructureField base found, rfl⟩

private theorem unary_sound
    (arguments : ExpressionsEvaluate program state expressions values)
    (evaluated : evaluateOperation program world
      (.unary operation input output) values = .ok (value, afterWorld)) :
    Evaluates program state
        (Operation.toCoreExpr (.unary operation input output) expressions)
        value state ∧ afterWorld = world := by
  cases arguments with
  | nil => simp [evaluateOperation] at evaluated
  | cons operand rest =>
      cases rest with
      | cons _ _ => simp [evaluateOperation] at evaluated
      | nil =>
          simp only [evaluateOperation, bind, Except.bind] at evaluated
          cases operationResult : evalUnaryValue program.target operation _ with
          | error reason =>
              rw [operationResult] at evaluated
              simp only at evaluated
              contradiction
          | ok result =>
              rw [operationResult] at evaluated
              simp only at evaluated
              obtain ⟨rfl, rfl⟩ := evaluated
              exact ⟨evaluatesUnary operand operationResult, rfl⟩

private theorem binary_sound
    (arguments : ExpressionsEvaluate program state expressions values)
    (evaluated : evaluateOperation program world
      (.binary operation leftType rightType outputType) values =
        .ok (value, afterWorld)) :
    Evaluates program state
        (Operation.toCoreExpr
          (.binary operation leftType rightType outputType) expressions)
        value state ∧ afterWorld = world := by
  cases arguments with
  | nil => simp [evaluateOperation] at evaluated
  | cons left rest =>
      cases rest with
      | nil => simp [evaluateOperation] at evaluated
      | cons right tail =>
          cases tail with
          | cons _ _ => simp [evaluateOperation] at evaluated
          | nil =>
              simp only [evaluateOperation, bind, Except.bind] at evaluated
              cases operationResult :
                evalBinaryValue program.target operation _ _ with
              | error reason =>
                  rw [operationResult] at evaluated
                  simp only at evaluated
                  contradiction
              | ok result =>
                  rw [operationResult] at evaluated
                  simp only at evaluated
                  obtain ⟨rfl, rfl⟩ := evaluated
                  cases operation with
                  | logicalAnd =>
                      obtain ⟨leftBool, rightBool, rfl, rfl, rfl⟩ :=
                        logicalAnd_result operationResult
                      exact ⟨evaluatesPureLogicalAnd left right, rfl⟩
                  | logicalOr =>
                      obtain ⟨leftBool, rightBool, rfl, rfl, rfl⟩ :=
                        logicalOr_result operationResult
                      exact ⟨evaluatesPureLogicalOr left right, rfl⟩
                  | equal | notEqual | less | lessEqual | greater |
                      greaterEqual | add | subtract | multiply | divide |
                      remainder | bitAnd | bitOr | bitXor | shiftLeft |
                      shiftRight =>
                      exact ⟨evaluatesEagerBinary (by decide) (by decide)
                        left right operationResult, rfl⟩

private theorem index_sound
    (represented : World.Represents world state)
    (arguments : ExpressionsEvaluate program state expressions values)
    (evaluated : evaluateOperation program world
      (Operation.index baseType indexType elementType) values =
        .ok (value, afterWorld)) :
    Evaluates program state
        (Operation.toCoreExpr
          (Operation.index baseType indexType elementType) expressions)
        value state ∧ afterWorld = world := by
  cases arguments with
  | nil => simp [evaluateOperation] at evaluated
  | cons base rest =>
      cases rest with
      | nil => simp [evaluateOperation] at evaluated
      | cons index tail =>
          cases tail with
          | cons _ _ => simp [evaluateOperation] at evaluated
          | nil =>
              simp only [evaluateOperation, bind, Except.bind] at evaluated
              cases readResult : readI32Slice world _ _ with
              | error reason =>
                  rw [readResult] at evaluated
                  simp only at evaluated
                  contradiction
              | ok result =>
                  rw [readResult] at evaluated
                  simp only at evaluated
                  obtain ⟨rfl, rfl⟩ := evaluated
                  obtain ⟨cell, sliceValues, position, inBounds, found,
                    rfl, rfl, rfl⟩ := readI32Slice_result readResult
                  have backing := (represented cell sliceValues found).1
                  exact ⟨evaluatesSignedI32SliceIndex program state state state
                    sliceValues _ _ cell position inBounds base index backing,
                    rfl⟩

def bridge (program : Program) :
    ReadOnlyBridge (machine program) program where
  Represents := World.Represents
  operation := by
    intro beforeWorld afterWorld state operation expressions values value
      represented arguments evaluated
    cases operation with
    | cast source target =>
        obtain ⟨execution, rfl⟩ := cast_sound arguments evaluated
        exact ⟨execution, represented⟩
    | unary operation input output =>
        obtain ⟨execution, rfl⟩ := unary_sound arguments evaluated
        exact ⟨execution, represented⟩
    | binary operation leftType rightType outputType =>
        obtain ⟨execution, rfl⟩ := binary_sound arguments evaluated
        exact ⟨execution, represented⟩
    | index baseType indexType elementType =>
        obtain ⟨execution, rfl⟩ := index_sound represented arguments evaluated
        exact ⟨execution, represented⟩
    | structValue typeId fieldTypes =>
        simp only [machine, evaluateOperation] at evaluated
        obtain ⟨rfl, rfl⟩ := evaluated
        exact ⟨evaluatesStructValue arguments.toArgumentsEvaluateTo,
          represented⟩
    | field baseType field resultType =>
        obtain ⟨execution, rfl⟩ := field_sound arguments evaluated
        exact ⟨execution, represented⟩
    | constant id type =>
        cases arguments with
        | cons _ _ => simp [machine, evaluateOperation] at evaluated
        | nil =>
            cases found : program.constant? id with
            | none => simp [machine, evaluateOperation, found] at evaluated
            | some declaration =>
                simp [machine, evaluateOperation, found] at evaluated
                obtain ⟨rfl, rfl⟩ := evaluated
                exact ⟨evaluatesConstant found, represented⟩
    | call function arguments result =>
        simp [machine, evaluateOperation] at evaluated
  bindLocal := World.Represents.bindLocal
  restoreLocals := World.Represents.restoreLocals

end Lanius.FunctionalView.Core.ReadOnly
