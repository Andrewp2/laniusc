import Lanius.Semantics.Relocation.State

namespace Lanius.Semantics.Relocation

open Lanius.Core

/-- Raw i32 storage contains no relocatable identifiers. -/
theorem encodeI32Array (symbols : Core.Relocation.Symbols) (entries : List Value) :
    Semantics.encodeI32Array (Core.Relocation.values symbols entries) =
      Semantics.encodeI32Array entries := by
  induction entries with
  | nil => rfl
  | cons first rest induction =>
      cases first <;> simp only [Core.Relocation.values, Core.Relocation.value, Semantics.encodeI32Array]
      all_goals try rfl
      rename_i type integer
      cases type <;> simp only [Semantics.encodeI32Array, induction]

theorem decodeI32Array (symbols : Core.Relocation.Symbols) (length : Nat) (bytes : List UInt8) :
    (Semantics.decodeI32Array length bytes).map (Core.Relocation.values symbols) =
      Semantics.decodeI32Array length bytes := by
  induction length generalizing bytes with
  | zero => simp only [Semantics.decodeI32Array]; split <;> rfl
  | succ length induction =>
      simp only [Semantics.decodeI32Array]
      split
      · rfl
      · have unchanged := induction (bytes.drop 4)
        cases decoded : Semantics.decodeI32Array length (bytes.drop 4) with
        | error reason => rfl
        | ok entries =>
            simp only [decoded, Except.map, Except.ok.injEq] at unchanged
            simp only [Except.map, Core.Relocation.values, Core.Relocation.value, unchanged]

end Lanius.Semantics.Relocation
