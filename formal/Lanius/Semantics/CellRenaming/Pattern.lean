import Lanius.Semantics.CellRenaming.Scalar
import Lanius.Semantics.CellRenaming.CallState

namespace Lanius.Semantics.CellRenaming
open Lanius.Core

private theorem scalarRight (rename : CellId → CellId) (expected actual : Value) :
    Semantics.scalarEqual expected (value rename actual) = Semantics.scalarEqual expected actual := by
  cases expected <;> cases actual <;> rfl

mutual
  theorem matchPattern (rename : CellId → CellId) (pattern : Pattern) (entry : Value) :
      Semantics.matchPattern pattern (value rename entry) =
        (Semantics.matchPattern pattern entry).map (bindings rename) := by
    cases pattern with
    | wildcard => rfl
    | bind id => rfl
    | literal expected =>
        simp only [Semantics.matchPattern, scalarRight]
        cases Semantics.scalarEqual expected entry with
        | none => rfl
        | some equal => cases equal <;> rfl
    | enumVariant expectedType expectedVariant patterns =>
        cases entry <;> simp only [value, Semantics.matchPattern]
        all_goals try rfl
        split
        · exact matchPatterns rename _ _
        · rfl
  termination_by sizeOf pattern

  theorem matchPatterns (rename : CellId → CellId) (patterns : List Pattern) (entries : List Value) :
      Semantics.matchPatterns patterns (values rename entries) =
        (Semantics.matchPatterns patterns entries).map (bindings rename) := by
    cases patterns with
    | nil => cases entries <;> rfl
    | cons pattern rest =>
        cases entries with
        | nil => rfl
        | cons entry entries =>
            simp only [values, Semantics.matchPatterns, matchPattern rename pattern entry,
              matchPatterns rename rest entries]
            cases Semantics.matchPattern pattern entry <;> cases Semantics.matchPatterns rest entries <;>
              simp [bindings]
  termination_by sizeOf patterns
end

end Lanius.Semantics.CellRenaming
