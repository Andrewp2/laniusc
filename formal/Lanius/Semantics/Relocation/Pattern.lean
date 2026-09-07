import Lanius.Semantics.Relocation.Scalar
import Lanius.Semantics.Relocation.CallState

namespace Lanius.Semantics.Relocation

open Lanius.Core

private theorem typeEquality (symbols : Core.Relocation.Symbols)
    (injective : Function.Injective symbols.typeId) (left right : TypeId) :
    (symbols.typeId left == symbols.typeId right) = (left == right) := by
  by_cases same : left = right
  · simp [same]
  · have different : symbols.typeId left ≠ symbols.typeId right := fun h => same (injective h)
    have leftFalse : (symbols.typeId left == symbols.typeId right) = false := beq_eq_false_iff_ne.mpr different
    have rightFalse : (left == right) = false := beq_eq_false_iff_ne.mpr same
    rw [leftFalse, rightFalse]

mutual
  theorem matchPattern (symbols : Core.Relocation.Symbols)
      (injective : Function.Injective symbols.typeId) (p : Pattern) (v : Value) :
      Semantics.matchPattern (Core.Relocation.pattern symbols p) (Core.Relocation.value symbols v) =
        (Semantics.matchPattern p v).map (bindings symbols) := by
    cases p with
    | wildcard => rfl
    | bind id => rfl
    | literal expected =>
        simp only [Core.Relocation.pattern, Semantics.matchPattern, scalarEqual]
        cases Semantics.scalarEqual expected v with
        | none => rfl
        | some equal => cases equal <;> rfl
    | enumVariant expectedType expectedVariant patterns =>
        cases v <;> simp only [Core.Relocation.pattern, Core.Relocation.value, Semantics.matchPattern]
        all_goals try rfl
        simp only [typeEquality symbols injective]
        split
        · exact matchPatterns symbols injective _ _
        · rfl
  termination_by sizeOf p

  theorem matchPatterns (symbols : Core.Relocation.Symbols)
      (injective : Function.Injective symbols.typeId) (ps : List Pattern) (vs : List Value) :
      Semantics.matchPatterns (Core.Relocation.patterns symbols ps) (Core.Relocation.values symbols vs) =
        (Semantics.matchPatterns ps vs).map (bindings symbols) := by
    cases ps with
    | nil => cases vs <;> rfl
    | cons p ps =>
        cases vs with
        | nil => rfl
        | cons v vs =>
            simp only [Core.Relocation.patterns, Core.Relocation.values, Semantics.matchPatterns,
              matchPattern symbols injective p v, matchPatterns symbols injective ps vs]
            cases Semantics.matchPattern p v <;> cases Semantics.matchPatterns ps vs <;>
              simp [bindings]
  termination_by sizeOf ps
end

end Lanius.Semantics.Relocation
