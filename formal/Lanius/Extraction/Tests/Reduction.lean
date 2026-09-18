import Lanius.Extraction.Reduction
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Reduction

def rows : { actual : List Nat // actual = (List.range 5).map (· + 7) } :=
  reduce_data% ((List.range 5).map (· + 7))

example : rows.val = [7, 8, 9, 10, 11] := by decide
example : rows.val = (List.range 5).map (· + 7) := rows.property

def bounded : { actual : Fin 7 // actual = (⟨3 + 2, by decide⟩ : Fin 7) } :=
  reduce_data% (⟨3 + 2, by decide⟩ : Fin 7)

example : bounded.val.val = 5 := by decide
example : bounded.val.val < 7 := bounded.val.isLt

def absent : { actual : Option Nat // actual = ([2, 4, 6].find? (· == 7)) } :=
  reduce_data% ([2, 4, 6].find? (· == 7))

example : absent.val = none := by decide

def found : { actual : Option (List Nat) // actual = some ((List.range 5).map (· + 7)) } :=
  reduce_data% (some ((List.range 5).map (· + 7)))

theorem found_success : found.val.isSome = true := by decide

def foundValues : List Nat := found.val.get found_success

example : some foundValues = some ((List.range 5).map (· + 7)) :=
  (Option.some_get found_success).trans found.property

structure Evidence where
  number : Nat
  positive : 0 < number

structure Record where
  size : Nat
  rows : List Evidence

def retained : { actual : Record //
    actual = ⟨3 + 4, [⟨2 + 3, by decide⟩]⟩ } :=
  reduce_data% retaining [Evidence] (⟨3 + 4, [⟨2 + 3, by decide⟩]⟩ : Record)

example : retained.val.size = 7 := by decide
example : retained.val.rows.map (·.number) = [5] := by decide
example : retained.val = ⟨3 + 4, [⟨2 + 3, by decide⟩]⟩ := retained.property

run_elab do
  for name in #[``rows, ``bounded, ``absent, ``found, ``found_success, ``foundValues,
      ``retained] do
    for assumption in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "Materialized data {name} adds unexpected axiom {assumption}"

end Lanius.Extraction.Tests.Reduction
