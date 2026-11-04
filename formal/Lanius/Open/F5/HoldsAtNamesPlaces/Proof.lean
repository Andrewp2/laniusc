import Lanius.Open.F5.HoldsAtNamesPlaces.Stmt

open Lanius.Mini
open Lanius.Core (Value)

set_option linter.unusedSimpArgs false

namespace Lanius.Open.HoldsAtNamesPlaces

/-- A scalar's value names no cell. -/
theorem scalar_names {ty : SrcType} {v : Value} {bits : BitVec 64} {cell : Lanius.CellId}
    (h : ty.Holds v bits) (nm : v.Names cell) : False := by
  cases nm <;> cases ty <;>
    simp_all [SrcType.Holds, UintTy.SintHolds, NarrowHolds, FloatTy.value] <;>
    rename_i kind <;> cases kind <;> simp_all [UintTy.SintHolds, NarrowHolds]

mutual
theorem holds {sx : Statics} {places : List Addressed} {cell : Lanius.CellId} :
    ∀ {ty : SrcType} {v : Value} {env : Env} {slot : Nat},
      ty.HoldsAt sx places v env slot → v.Names cell → ∃ x ∈ places, x.cell = cell
  | _, _, _, _, .i32 h, nm => (scalar_names h nm).elim
  | _, _, _, _, .bool h, nm => (scalar_names h nm).elim
  | _, _, _, _, .uint h, nm => (scalar_names h nm).elim
  | _, _, _, _, .struct h, nm => by cases nm with | «structure» mw n => exact fields h _ mw n
  | _, _, _, _, .enum _ _ payload, nm => by cases nm with | enumeration mw n => exact fields payload _ mw n
  | _, _, _, _, .ptr h, nm => (scalar_names h nm).elim
  | _, _, _, _, .slice _ _, nm => by cases nm
  | _, _, _, _, .borrowed mem _ _ _ _ _ _ _, nm => by cases nm with | slice => exact ⟨_, mem, rfl⟩
  | _, _, _, _, .array h, nm => by cases nm with | array mw n => exact fields h _ mw n
  | _, _, _, _, .unit, nm => by cases nm
  | _, _, _, _, .isize h, nm => (scalar_names h nm).elim
  | _, _, _, _, .char h, nm => (scalar_names h nm).elim
  | _, _, _, _, .float h, nm => (scalar_names h nm).elim
  | _, _, _, _, .sint h, nm => (scalar_names h nm).elim
  | _, _, _, _, .view _ h, nm => by
    cases nm with
    | array mw n =>
      obtain ⟨i, rfl, -⟩ := h _ mw
      cases n
  | _, _, _, _, .str _ _ _ _, nm => by cases nm
  | _, _, _, _, .ref ⟨c, path, hv, x, mem, hc, _⟩, nm => by
    subst hv
    cases nm with
    | reference => exact ⟨x, mem, hc⟩

theorem fields {sx : Statics} {places : List Addressed} {cell : Lanius.CellId} :
    ∀ {fs : List SrcType} {vs : List Value} {env : Env} {slot : Nat},
      FieldsHold sx places fs vs env slot → ∀ (w : Value), w ∈ vs → w.Names cell → ∃ x ∈ places, x.cell = cell
  | _, _, _, _, .nil, _, mw, _ => by cases mw
  | _, _, _, _, .cons head rest, _, mw, nm => by
    have ih1 := holds (cell := cell) head
    have ih2 := fields (cell := cell) rest
    rcases List.mem_cons.mp mw with rfl | mw
    · exact ih1 nm
    · exact ih2 _ mw nm
end

end Lanius.Open.HoldsAtNamesPlaces

theorem Lanius.Open.HoldsAtNamesPlaces.proof : Lanius.Open.HoldsAtNamesPlaces :=
  fun _ _ _ _ _ _ _ h nm => Lanius.Open.HoldsAtNamesPlaces.holds h nm
