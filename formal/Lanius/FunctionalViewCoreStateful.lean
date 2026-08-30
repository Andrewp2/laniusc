import Lanius.FunctionalViewCoreReadOnly
import Lanius.FunctionalViewStateful

namespace Lanius.FunctionalView.Core.Stateful

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Stateful

/-! # Stateful FunctionalView adapter for structural Core

The generic command language does not know how a dialect action is encoded.
`ActionAdapter` supplies that one leaf conversion; local assignment and every
control construct are converted here exactly once.
-/

structure ActionAdapter (actions : ActionSignature signature) where
  toCoreStmt : {arity : Nat} → Layout arity → actions.Action arity → Stmt

/-- Number of fresh Core local identifiers needed along one command path.
    A loop body reuses the same lexical identifiers on each iteration. -/
def localCapacity (adapter : ActionAdapter actions) :
    Command signature actions arity → Nat
  | .skip | .setLocal _ _ | .updateLocal _ _ _ | .action _ | .returnValue _ |
      .breakLoop | .continueLoop => 0
  | .sequence first second =>
      localCapacity adapter first + localCapacity adapter second
  | .letValue _ _ body => 1 + localCapacity adapter body
  | .ifThenElse _ thenBranch elseBranch =>
      max (localCapacity adapter thenBranch) (localCapacity adapter elseBranch)
  | .whileLoop _ body => localCapacity adapter body

def toCoreCompletion : Lanius.FunctionalView.Stateful.Completion →
    Lanius.Semantics.Completion
  | .next => .next
  | .returned value => .returned value
  | .breakLoop => .breakLoop
  | .continueLoop => .continueLoop

/-- Exact structural conversion.  Ghost mutation state and loop measures do
    not occur in the emitted Core statement. -/
def toCoreStmt (adapter : ActionAdapter actions) (layout : Layout arity)
    (nextLocal : VarId) : Command signature actions arity → Stmt
  | .skip => .skip
  | .sequence first second =>
      .sequence (toCoreStmt adapter layout nextLocal first)
        (toCoreStmt adapter layout
          (nextLocal + localCapacity adapter first) second)
  | .letValue type initializer body =>
      .letLocal nextLocal type (Core.toCoreExpr layout initializer)
        (toCoreStmt adapter (Layout.push layout nextLocal) (nextLocal + 1) body)
  | .setLocal target value =>
      .expression (.assign .set (.local (layout target))
        (Core.toCoreExpr layout value))
  | .updateLocal operation target value =>
      .expression (.assign operation (.local (layout target))
        (Core.toCoreExpr layout value))
  | .action operation => adapter.toCoreStmt layout operation
  | .ifThenElse condition thenBranch elseBranch =>
      .ifThenElse (Core.toCoreExpr layout condition)
        (toCoreStmt adapter layout nextLocal thenBranch)
        (toCoreStmt adapter layout nextLocal elseBranch)
  | .whileLoop condition body =>
      .whileLoop (Core.toCoreExpr layout condition)
        (toCoreStmt adapter layout nextLocal body)
  | .returnValue none => .returnValue none
  | .returnValue (some value) =>
      .returnValue (some (Core.toCoreExpr layout value))
  | .breakLoop => .breakLoop
  | .continueLoop => .continueLoop

/-! ## Standard mutable `i32`-slice action

Parser workspaces are zero-based `i32` slices.  The base is deliberately a
scoped local reference rather than an arbitrary term: Core assignment needs a
place, and this restriction prevents a proof view from pretending that every
value expression is assignable.
-/

inductive Action : Nat → Type where
  | setI32Index {arity : Nat} (base : Fin arity)
      (index value : Term Core.signature arity) : Action arity

abbrev actions : ActionSignature Core.signature := {
  Action := Action
  effect := fun _ => .write
}

def actionAdapter : ActionAdapter actions where
  toCoreStmt := fun layout action =>
    match action with
    | .setI32Index base index value =>
        .expression (.assign .set
          (.index (.local (layout base)) (Core.toCoreExpr layout index))
          (Core.toCoreExpr layout value))

def writeI32Slice (world : ReadOnly.World) (base index replacement : Value) :
    Except Trap ReadOnly.World :=
  match base, index, replacement with
  | .slice (.scalar (.signed .i32)) cell [] 0 length,
      .signed .i32 integer, .signed .i32 replacement =>
      if _negative : integer < 0 then
        .error .arrayBounds
      else
        match world.i32Slice? cell with
        | none => .error .invalidPointer
        | some values =>
            if _sameLength : length = values.length then
              let position := integer.toNat
              if _inBounds : position < values.length then
                .ok (ReadOnly.World.setI32Slice world cell
                  (setI32Value values position replacement))
              else
                .error .arrayBounds
            else
              .error .arrayBounds
  | _, _, _ => .error .typeMismatch

abbrev OperationEvaluator := ReadOnly.World → Operation → List Value →
  Except Trap (Value × ReadOnly.World)

/-- A Core FunctionalView machine whose operation semantics is supplied by
    the caller.  The abstract world stays fixed to the separation-backed
    slice world, so read-only and call-capable terms can share the same
    stateful command language. -/
def termMachine (evaluateOperation : OperationEvaluator) :
    Lanius.FunctionalView.Machine Core.signature := {
  World := ReadOnly.World
  evalOperation := evaluateOperation
}

def evaluateActionWith (evaluateOperation : OperationEvaluator)
    (world : ReadOnly.World)
    (environment : Env arity) : Action arity → Except Trap ReadOnly.World
  | .setI32Index base index value => do
      let (indexValue, afterIndex) ←
        Term.evaluate (termMachine evaluateOperation) world environment index
      let (replacement, afterValue) ←
        Term.evaluate (termMachine evaluateOperation) afterIndex environment value
      writeI32Slice afterValue (environment base) indexValue replacement

def machineWith (program : Program) (evaluateOperation : OperationEvaluator) :
    Lanius.FunctionalView.Stateful.Machine
      (termMachine evaluateOperation) actions := {
  evalLocalUpdate := fun operation current right =>
    evalAssignValue program.target operation (some current) right
  evalAction := evaluateActionWith evaluateOperation
}

/-- Read-only compatibility specialization.  Existing proofs retain their
    source shape while the same stateful engine is available to effectful
    FunctionalView terms. -/
def evaluateAction (program : Program) :
    ReadOnly.World → Env arity → Action arity → Except Trap ReadOnly.World :=
  evaluateActionWith (ReadOnly.evaluateOperation program)

def machine (program : Program) :
    Lanius.FunctionalView.Stateful.Machine
      (ReadOnly.machine program) actions :=
  machineWith program (ReadOnly.evaluateOperation program)

theorem evaluateAction_setI32Index
    (baseValue : environment base =
      .slice (.scalar (.signed .i32)) cell [] 0 values.length)
    (indexResult : Term.evaluate (ReadOnly.machine program) world environment
      index = .ok (.signed .i32 (Int.ofNat position), world))
    (valueResult : Term.evaluate (ReadOnly.machine program) world environment
      value = .ok (.signed .i32 replacement, world))
    (found : world.i32Slice? cell = some values)
    (inBounds : position < values.length) :
    evaluateAction program world environment
        (.setI32Index base index value) =
      .ok (ReadOnly.World.setI32Slice world cell
        (setI32Value values position replacement)) := by
  have nonnegative : ¬(Int.ofNat position < 0) := by simp
  have indexResult' : Term.evaluate
      (termMachine (ReadOnly.evaluateOperation program)) world environment
      index = .ok (.signed .i32 (Int.ofNat position), world) := by
    simpa [termMachine, ReadOnly.machine] using indexResult
  have valueResult' : Term.evaluate
      (termMachine (ReadOnly.evaluateOperation program)) world environment
      value = .ok (.signed .i32 replacement, world) := by
    simpa [termMachine, ReadOnly.machine] using valueResult
  change evaluateActionWith (ReadOnly.evaluateOperation program) world
      environment (.setI32Index base index value) = _
  simp [evaluateActionWith, writeI32Slice, indexResult', valueResult', baseValue,
    found, inBounds, nonnegative, bind, Except.bind]

/-- Functional execution rule for the parser/lexer cursor idiom
    `slice[cursor] = replacement; cursor += 1`.  It packages the action,
    wrapped `i32` increment, and structural trailing `skip` into one rule. -/
theorem evaluatesSetI32AtCursorThenIncrementAndSkip
    {arity : Nat} {program : Program} {world : ReadOnly.World}
    {environment : Env arity} {base cursor : Fin arity}
    {replacement : Term Core.signature arity}
    {cell : CellId} {values : List Int} {position : Nat}
    {replacementValue : Int}
    (baseValue : environment base =
      .slice (.scalar (.signed .i32)) cell [] 0 values.length)
    (cursorValue : environment cursor =
      .signed .i32 (Int.ofNat position))
    (replacementResult : Term.evaluate (ReadOnly.machine program) world
      environment replacement = .ok (.signed .i32 replacementValue, world))
    (found : world.i32Slice? cell = some values)
    (inBounds : position < values.length)
    (incrementBound : position + 1 ≤ 2147483647) :
    Command.Evaluates (ReadOnly.machine program) (machine program) world
      environment
      (.sequence
        (.action (.setI32Index base (.reference (.slot cursor)) replacement))
        (.sequence
          (.updateLocal .add cursor
            (.reference (.literal (.signed .i32 1))))
          .skip))
      .next
      (ReadOnly.World.setI32Slice world cell
        (setI32Value values position replacementValue))
      (Env.set environment cursor
        (.signed .i32 (Int.ofNat (position + 1)))) := by
  have indexResult : Term.evaluate (ReadOnly.machine program) world environment
      (.reference (.slot cursor)) =
      .ok (.signed .i32 (Int.ofNat position), world) := by
    simp [Term.evaluate, Ref.evaluate, cursorValue]
  have actionResult : evaluateAction program world environment
      (.setI32Index base (.reference (.slot cursor)) replacement) =
      .ok (ReadOnly.World.setI32Slice world cell
        (setI32Value values position replacementValue)) :=
    evaluateAction_setI32Index baseValue indexResult replacementResult found
      inBounds
  have oneResult : Term.evaluate (ReadOnly.machine program)
      (ReadOnly.World.setI32Slice world cell
        (setI32Value values position replacementValue)) environment
      (.reference (.literal (.signed .i32 1))) =
      .ok (.signed .i32 1, ReadOnly.World.setI32Slice world cell
        (setI32Value values position replacementValue)) := by
    rfl
  have addition : Int.ofNat position + 1 = Int.ofNat (position + 1) := by
    simpa using (Int.natCast_add position 1).symm
  have wrapped := wrapSigned_i32_ofNat program.target (position + 1)
    incrementBound
  have updated : evalAssignValue program.target .add
      (some (.signed .i32 (Int.ofNat position))) (.signed .i32 1) =
      .ok (.signed .i32 (Int.ofNat (position + 1))) := by
    simp only [evalAssignValue, assignOpBinary?, evalBinaryValue,
      beq_self_eq_true, if_true, evalSignedBinary]
    rw [addition, wrapped]
  exact .sequenceNext (.action actionResult)
    (.sequenceNext (.updateLocal oneResult (by
      simpa [machine, machineWith, cursorValue] using updated)) .skip)

theorem writeI32Slice_result
    (evaluated : writeI32Slice world base index replacement = .ok afterWorld) :
    ∃ cell values position replacementInteger,
      base = .slice (.scalar (.signed .i32)) cell [] 0 values.length ∧
      index = .signed .i32 (Int.ofNat position) ∧
      replacement = .signed .i32 replacementInteger ∧
      world.i32Slice? cell = some values ∧
      position < values.length ∧
      afterWorld = ReadOnly.World.setI32Slice world cell
        (setI32Value values position replacementInteger) := by
  cases base
  case slice elementType cell projections start length =>
    cases index
    case signed integerType integer =>
      cases replacement
      case signed replacementType replacementInteger =>
        simp [writeI32Slice] at evaluated
        split at evaluated <;> try simp_all
        split at evaluated <;> try simp_all
        split at evaluated <;> try simp_all
        split at evaluated <;> try simp_all
        split at evaluated <;> try simp_all
        obtain ⟨rfl, rfl, rfl, rfl, rfl⟩ :
            elementType = .scalar (.signed .i32) ∧ cell = _ ∧
              projections = [] ∧ start = 0 ∧ length = _ := by
          assumption
        obtain ⟨rfl, rfl⟩ :
            integerType = .i32 ∧ integer = _ := by
          assumption
        obtain ⟨rfl, rfl⟩ :
            replacementType = .i32 ∧ replacementInteger = _ := by
          assumption
        refine ⟨cell, _, ⟨rfl, rfl⟩, integer.toNat, ?_, ?_, ?_, ?_⟩
        · exact (Int.toNat_of_nonneg (by omega)).symm
        · assumption
        · omega
        · exact evaluated.symm
      all_goals simp [writeI32Slice] at evaluated
    all_goals cases replacement <;> simp [writeI32Slice] at evaluated
  all_goals cases index <;> cases replacement <;>
    simp [writeI32Slice] at evaluated

/-- Separation-logic kernel for one workspace write.  Its expression premises
    are already structural-Core evaluations, which lets callers forget the
    proof-view evaluator before destructuring the resulting scalar values. -/
theorem executes_setI32IndexCore
    (wellFormed : StateWellFormed state)
    (owned : (ReadOnly.World.owns world).holds state)
    (baseLocal : state.local? (layout base) = some
      (.slice (.scalar (.signed .i32)) cell [] 0 values.length))
    (indexSound : Evaluates program state (Core.toCoreExpr layout index)
      (.signed .i32 (Int.ofNat position)) state)
    (valueSound : Evaluates program state (Core.toCoreExpr layout value)
      (.signed .i32 replacement) state)
    (found : world.i32Slice? cell = some values)
    (inBounds : position < values.length) :
    ∃ after,
      Executes program state
        (actionAdapter.toCoreStmt layout (.setI32Index base index value))
        .next after ∧
      StateWellFormed after ∧
      (ReadOnly.World.owns
        (ReadOnly.World.setI32Slice world cell
          (setI32Value values position replacement))).holds after ∧
      ModifiesOnly (CellSet.singleton cell) state after := by
  have backing := owned cell values found
  obtain ⟨after, written, afterWellFormed, afterBacking, effect⟩ :=
    evaluatesSetSignedI32SliceIndexFromEmpty program state state state values
      (layout base) (Core.toCoreExpr layout index)
      (Core.toCoreExpr layout value) cell position replacement inBounds
      baseLocal indexSound wellFormed (ModifiesOnly.refl state)
      valueSound wellFormed (ModifiesOnly.refl state) backing
  have afterOwned : (ReadOnly.World.owns
      (ReadOnly.World.setI32Slice world cell
        (setI32Value values position replacement))).holds after := by
    intro candidate contents candidateFound
    by_cases same : candidate = cell
    · subst candidate
      have contentsEq : contents =
          setI32Value values position replacement := by
        simpa using candidateFound.symm
      subst contents
      exact afterBacking
    · have oldFound : world.i32Slice? candidate = some contents := by
        simpa [ReadOnly.World.setI32Slice, same] using candidateFound
      have oldBacking := owned candidate contents oldFound
      exact effect.preserves_entry wellFormed oldBacking (by
        simpa [CellSet.singleton] using same)
  exact ⟨after, executesExpression written, afterWellFormed, afterOwned,
    effect⟩

/-- FunctionalView wrapper for `executes_setI32IndexCore`. -/
theorem executes_setI32Index
    (wellFormed : StateWellFormed state)
    (owned : (ReadOnly.World.owns world).holds state)
    (environmentMatches : EnvironmentMatches layout environment state)
    (baseValue : environment base =
      .slice (.scalar (.signed .i32)) cell [] 0 values.length)
    (indexResult : Term.evaluate (ReadOnly.machine program) world environment
      index = .ok (.signed .i32 (Int.ofNat position), world))
    (valueResult : Term.evaluate (ReadOnly.machine program) world environment
      value = .ok (.signed .i32 replacement, world))
    (found : world.i32Slice? cell = some values)
    (inBounds : position < values.length) :
    ∃ after,
      Executes program state
        (actionAdapter.toCoreStmt layout (.setI32Index base index value))
        .next after ∧
      StateWellFormed after ∧
      (ReadOnly.World.owns
        (ReadOnly.World.setI32Slice world cell
          (setI32Value values position replacement))).holds after ∧
      ModifiesOnly (CellSet.singleton cell) state after := by
  have represented : ReadOnly.World.Represents world state :=
    (ReadOnly.World.owns_iff_represents wellFormed).mp owned
  have indexSound := Core.term_evaluates (ReadOnly.bridge program) represented
    environmentMatches indexResult
  have valueSound := Core.term_evaluates (ReadOnly.bridge program) represented
    environmentMatches valueResult
  have baseLocal : state.local? (layout base) = some
      (.slice (.scalar (.signed .i32)) cell [] 0 values.length) := by
    rw [environmentMatches base, baseValue]
  exact executes_setI32IndexCore wellFormed owned baseLocal indexSound.1
    valueSound.1 found inBounds

end Lanius.FunctionalView.Core.Stateful
