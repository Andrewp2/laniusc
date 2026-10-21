import Lanius.Semantics.Typing.Projection
import Lanius.Semantics.Assignment

namespace Lanius.Semantics

open Lanius.Core

/-- Different aggregate branches, possibly below a common prefix. This
    describes storage independence, not exclusive ownership of references. -/
inductive ProjectionApart : List ValueProjection → List ValueProjection → Prop where
  | field {left right : Nat} {first second : List ValueProjection} (different : left ≠ right) :
      ProjectionApart (.field left :: first) (.field right :: second)
  | index {left right : Nat} {first second : List ValueProjection} (different : left ≠ right) :
      ProjectionApart (.index left :: first) (.index right :: second)
  | step {first second : List ValueProjection} {head : ValueProjection} (apart : ProjectionApart first second) :
      ProjectionApart (head :: first) (head :: second)

theorem ProjectionApart.symm (apart : ProjectionApart first second) : ProjectionApart second first := by
  induction apart with
  | field different => exact .field (Ne.symm different)
  | index different => exact .index (Ne.symm different)
  | step _ ih => exact .step ih

/-- Typed i32-array leaves cannot properly contain one another. Two such
    paths from the same declared root either coincide or are independent. -/
theorem ProjectionHasType.i32ArrayApart
    (first : ProjectionHasType program rootType firstPath (.array (.scalar (.signed .i32)) firstCount))
    (second : ProjectionHasType program rootType secondPath (.array (.scalar (.signed .i32)) secondCount)) :
    firstPath = secondPath ∨ ProjectionApart firstPath secondPath := by
  induction firstPath generalizing rootType secondPath firstCount secondCount with
  | nil =>
    cases first
    cases second with
    | root => exact Or.inl rfl
    | index bounded rest => cases rest
  | cons head tail ih =>
    cases first with
    | field declaration found fieldFound rest =>
      rename_i leftType owner left
      cases second with
      | field other otherFound otherFieldFound otherRest =>
        rename_i rightType rightPath right
        have sameDecl : other = declaration := Option.some.inj (otherFound.symm.trans found)
        subst other
        by_cases same : left = right
        · subst right
          have sameType := Option.some.inj (fieldFound.symm.trans otherFieldFound)
          subst sameType
          rcases ih rest otherRest with same | apart
          · exact Or.inl (congrArg (List.cons (.field left)) same)
          · exact Or.inr (.step apart)
        · exact Or.inr (.field same)
    | index bounded rest =>
      rename_i left total elementType
      cases second with
      | root => cases rest
      | index otherBound otherRest =>
        rename_i right rightPath
        by_cases same : left = right
        · subst right
          rcases ih rest otherRest with same | apart
          · exact Or.inl (congrArg (List.cons (.index left)) same)
          · exact Or.inr (.step apart)
        · exact Or.inr (.index same)

/-- Updating one branch retains reads from every independent branch, at any
    struct/array depth. Internal update success is supplied by the typed writer. -/
theorem replaceProjectedValue_frame (apart : ProjectionApart destination observed)
    (written : replaceProjectedValue root destination replacement = .ok updated)
    (read : projectedValue root observed = .ok value) : projectedValue updated observed = .ok value := by
  induction apart generalizing root updated with
  | @field left right first second different =>
    cases root <;> simp only [replaceProjectedValue] at written <;> try cases written
    case «structure» id fields =>
      cases found : fields[left]? with
      | none => simp only [found] at written; cases written
      | some old =>
        cases changed : replaceProjectedValue old first replacement with
        | error reason => simp only [found, changed] at written; cases written
        | ok next =>
          simp only [found, changed, Except.ok.injEq] at written
          subst updated
          simpa only [projectedValue, setValue_eq_set, List.getElem?_set_ne different] using read
  | @index left right first second different =>
    cases root <;> simp only [replaceProjectedValue] at written <;> try cases written
    case array elements =>
      cases found : elements[left]? with
      | none => simp only [found] at written; cases written
      | some old =>
        cases changed : replaceProjectedValue old first replacement with
        | error reason => simp only [found, changed] at written; cases written
        | ok next =>
          simp only [found, changed, Except.ok.injEq] at written
          subst updated
          simpa only [projectedValue, setValue_eq_set, List.getElem?_set_ne different] using read
  | @step first second head apart ih =>
    cases root <;> cases head <;> simp only [replaceProjectedValue] at written <;> try cases written
    case «structure».field id fields field =>
      cases found : fields[field]? with
      | none => simp only [found] at written; cases written
      | some old =>
        cases changed : replaceProjectedValue old first replacement with
        | error reason => simp only [found, changed] at written; cases written
        | ok next =>
          simp only [found, changed, Except.ok.injEq] at written
          subst updated
          have bound := (List.getElem?_eq_some_iff.mp found).1
          have oldRead : projectedValue old second = .ok value := by simpa only [projectedValue, found] using read
          simpa only [projectedValue, setValue_eq_set, List.getElem?_set_self bound] using ih changed oldRead
    case array.index elements index =>
      cases found : elements[index]? with
      | none => simp only [found] at written; cases written
      | some old =>
        cases changed : replaceProjectedValue old first replacement with
        | error reason => simp only [found, changed] at written; cases written
        | ok next =>
          simp only [found, changed, Except.ok.injEq] at written
          subst updated
          have bound := (List.getElem?_eq_some_iff.mp found).1
          have oldRead : projectedValue old second = .ok value := by simpa only [projectedValue, found] using read
          simpa only [projectedValue, setValue_eq_set, List.getElem?_set_self bound] using ih changed oldRead

theorem CellEffect.projectedRead (effect : CellEffect before after cell updated)
    (apart : cell ≠ queried ∨ ProjectionApart destination observed)
    (stored : before.cellEntry? cell = some { id := cell, value := some root })
    (written : replaceProjectedValue root destination replacement = .ok updated)
    (read : readCellProjection before queried observed = .ok value) :
    readCellProjection after queried observed = .ok value := by
  by_cases same : queried = cell
  · subst queried
    rcases apart with different | apart
    · exact (different rfl).elim
    · have found : after.cellEntry? cell = some { id := cell, value := some updated } := by
        unfold State.cellEntry? at stored ⊢
        rw [effect.cells, replaceCell_find_same before.cells cell updated _ stored]
      have oldRead : projectedValue root observed = .ok value := by
        simpa only [readCellProjection, stored] using read
      simpa only [readCellProjection, found] using replaceProjectedValue_frame apart written oldRead
  · cases found : before.cellEntry? queried with
    | none => simp only [readCellProjection, found] at read; cases read
    | some entry =>
      simpa only [readCellProjection, found, effect.otherCell same found] using read

#print axioms replaceProjectedValue_frame
#print axioms CellEffect.projectedRead
#print axioms ProjectionHasType.i32ArrayApart

end Lanius.Semantics
