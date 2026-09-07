import Lanius.Semantics.Relocation.Execution.Step
import Lanius.Core.Relocation.Program
import Std.Tactic

namespace Lanius.Semantics.Relocation.Execution

open Lanius.Core

/-- Frontend modules have bodies for every callable declaration. External
runtime contracts require a separate transport argument; they are not silently
treated as pure functions here. -/
def Internal (program : Program) : Prop :=
  ∀ id declaration, program.function? id = some declaration → declaration.body.isSome = true

private theorem bodyPresent (internal : Internal program) {id : FunctionId} {declaration : Function}
    (found : program.function? id = some declaration) (missing : declaration.body = none) : False := by
  have present := internal id declaration found
  simp [missing] at present

private theorem cellId (symbols : Core.Relocation.Symbols) (before : State) (id : VarId) :
    (state symbols before).cellId? id = before.cellId? id := rfl

private theorem heap (symbols : Core.Relocation.Symbols) (before : State) :
    (state symbols before).heap = before.heap := rfl

private theorem world (symbols : Core.Relocation.Symbols) (before : State) :
    (state symbols before).world = before.world := rfl

private theorem unitType (symbols : Core.Relocation.Symbols) (type : Ty) :
    (Core.Relocation.ty symbols type = .unit) ↔ type = .unit := by
  cases type <;> simp [Core.Relocation.ty]

private theorem scalarType (symbols : Core.Relocation.Symbols) (type : ScalarTy) :
    Core.Relocation.ty symbols (.scalar type) = .scalar type := rfl

private theorem allocateArray (symbols : Core.Relocation.Symbols) (before : State) (entries : List Value) :
    (state symbols before).allocateTemporary (.array (Core.Relocation.values symbols entries)) =
      ((before.allocateTemporary (.array entries)).1,
        state symbols (before.allocateTemporary (.array entries)).2) := by
  simpa only [Core.Relocation.value] using
    allocateTemporary symbols before (.array entries)

private theorem mapOk (f : α → β) (v : α) :
    (Except.ok v : Except ε α).map f = .ok (f v) := rfl
private theorem mapError (f : α → β) (e : ε) :
    (Except.error e : Except ε α).map f = .error e := rfl
private theorem valuesLength (symbols : Core.Relocation.Symbols) (entries : List Value) :
    (Core.Relocation.values symbols entries).length = entries.length := by
  simp [Core.Relocation.values_eq_map]
private theorem valuesIndex (symbols : Core.Relocation.Symbols) (entries : List Value) (index : Nat) :
    (Core.Relocation.values symbols entries)[index]? =
      (entries[index]?).map (Core.Relocation.value symbols) := by
  simp [Core.Relocation.values_eq_map]

private theorem withHeap (symbols : Core.Relocation.Symbols) (before : State) (heap : Memory.Heap) :
    { state symbols before with heap, world := before.world } = state symbols { before with heap } := rfl

private theorem withWorld (symbols : Core.Relocation.Symbols) (before : State) (world : World.State) :
    { state symbols before with heap := before.heap, world } = state symbols { before with world } := rfl

private theorem callLocals (symbols : Core.Relocation.Symbols) (before : State)
    (entries : List (VarId × Value)) :
    ({ state symbols before with locals := [], heap := before.heap, world := before.world }).bindLocals
        (bindings symbols entries) =
      state symbols (({ before with locals := [] }).bindLocals entries) :=
  (bindLocals symbols { before with locals := [] } entries).symm

private theorem writePlaceFields (symbols : Core.Relocation.Symbols) (before : State)
    (place : ResolvedPlace) (value : Value) :
    Semantics.writeResolvedPlace (state symbols before)
        { root := place.root, projections := place.projections,
          value := place.value.map (Core.Relocation.value symbols) } (Core.Relocation.value symbols value) =
      (Semantics.writeResolvedPlace before place value).map (state symbols) :=
  writeResolvedPlace symbols before place value

private theorem missingPlace (place : ResolvedPlace) (missing : place.value = none) :
    place = { root := place.root, projections := place.projections, value := none } := by
  cases place
  cases missing
  rfl

theorem expression (step : Step fuel symbols smaller larger)
    (matching : Core.Relocation.ProgramMatch symbols smaller larger) (internal : Internal smaller)
    (before : State) (expression : Expr) (result : Value) (after : State)
    (evaluated : evalExpr (fuel + 1) smaller before expression = .done result after) :
    evalExpr (fuel + 1) larger (state symbols before) (Core.Relocation.expression symbols expression) =
      .done (Core.Relocation.value symbols result) (state symbols after) := by
  cases expression <;> simp only [Core.Relocation.expression, evalExpr] at evaluated ⊢
  all_goals
    repeat' first
      | contradiction
      | exact False.elim (bodyPresent internal (by assumption) (by assumption))
      | rw [step.expression (by assumption)]
      | rw [step.expressions (by assumption)]
      | (have transported := step.expressions (by assumption)
         simp only [Core.Relocation.expressions] at transported
         rw [transported])
      | rw [step.place (by assumption)]
      | rw [step.arms (by assumption)]
      | rw [step.statement (by assumption)]
      | rw [matching.constant (by assumption)]
      | rw [matching.function (by assumption)]
      | simp_all only [Expr.binary.injEq, Outcome.done.injEq,
          Core.Relocation.value, Core.Relocation.values, Core.Relocation.function,
          Core.Relocation.constant, Core.Relocation.expressions, completion, outcome,
          Option.map_some, Option.map_none, mapOk, mapError, resolvedPlace, cellId, cellEntry, cell, heap, world,
          valuesLength, valuesIndex,
          expressionPlace, integerIndex, cast, unary, binary, assignment,
          sliceValues, dereferenceValue, writeResolvedPlace, bindParameters,
          ← bindLocals, callLocals, withHeap, withWorld, writePlaceFields, allocateArray, syncToHeap, syncFromHeap,
          mapI32ArrayView, mapRawI32Slice, mapI32SliceDataPtr, mapStringDataPtr,
          ← matching.target, unitType, scalarType]
      | split at evaluated
    all_goals first
      | exact step.expression evaluated
      | exact step.arms evaluated
      | skip
    all_goals try obtain ⟨rfl, rfl⟩ := evaluated
    all_goals try simp only [Core.Relocation.value, Core.Relocation.values_eq_map]
    all_goals try rfl
    all_goals grind only [Internal, Relocation.restoreLocals,
      Core.Relocation.value, Core.Relocation.values_eq_map, completion, unitType,
      Option.map_eq_none_iff, → missingPlace]

end Lanius.Semantics.Relocation.Execution
