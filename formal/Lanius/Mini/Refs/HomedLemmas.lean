module

public import Lanius.Mini.Refs.Homed
public import Lanius.Mini.Refs.Place
public import Lanius.Mini.Refs.Store
public import Lanius.Mini.LowerStmt
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.widthOf
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.render

@[expose] public section

/-! # References: stage 2 facts without Source's reference type (F5)

A sub-place's address is inside its home block, so below `2 ^ 62`
(`Homes.sub_lt`); binding a callee's parameters (`coreLocal_bindLocals`);
and the facts about `HomedCorr`.
-/

namespace Lanius.Mini

open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-! ## A sub-place is inside its home -/

/-- The bytes a value of `t` reaches from its lowest byte: a packed element's
width, else its words. -/
def SrcType.ext (t : SrcType) : Nat := if t.accessKind.narrow then t.accessKind.bytes else 8 * t.words

theorem SrcType.ext_le (t : SrcType) : t.ext ≤ 8 * t.words := by
  unfold SrcType.ext
  cases hn : t.accessKind.narrow with
  | false => simp
  | true =>
    rcases SrcType.narrow_cases hn with rfl | rfl <;>
      simp [SrcType.accessKind, SrcType.words, Access.bytes, MemWidth.bytes]

theorem fieldWords_take : ∀ {fs : List SrcType} {k : Nat} {t : SrcType}, fs[k]? = some t →
    fieldWords (fs.take k) + t.words ≤ fieldWords fs
  | [], _, _, h => by simp at h
  | f :: rest, 0, t, h => by
    simp only [List.getElem?_cons_zero, Option.some.injEq] at h
    subst h
    simp [fieldWords]
  | f :: rest, k + 1, t, h => by
    simp only [List.getElem?_cons_succ] at h
    have := fieldWords_take h
    simp only [List.take_succ_cons, fieldWords]
    omega

theorem SrcType.subStep_ext {ty : SrcType} {p : ValueProjection} {o : Nat} {child : SrcType}
    (h : ty.subStep p = some (o, child)) : o + child.ext ≤ 8 * ty.words := by
  cases ty with
  | struct id fields =>
    cases p with
    | index _ => simp [SrcType.subStep] at h
    | field f =>
      simp only [SrcType.subStep] at h
      split at h
      · rename_i fty hf
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        have a := fieldWords_take hf
        have b := SrcType.ext_le fty
        have m : fieldWords fields ≤ max 1 (fieldWords fields) := Nat.le_max_right _ _
        simp only [SrcType.words]
        omega
      · cases h
  | array e n =>
    cases p with
    | field _ => simp [SrcType.subStep] at h
    | index i =>
      simp only [SrcType.subStep] at h
      split at h
      · rename_i lt
        cases hn : e.accessKind.narrow with
        | true =>
          simp only [hn, if_true, Option.some.injEq, Prod.mk.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          simp only [SrcType.ext, SrcType.words, hn, if_true]
          rcases SrcType.narrow_cases hn with rfl | rfl <;>
            simp only [SrcType.accessKind, Access.bytes, MemWidth.bytes] <;> omega
        | false =>
          simp only [hn, Bool.false_eq_true, if_false, Option.some.injEq, Prod.mk.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          simp only [SrcType.ext, SrcType.words, hn, Bool.false_eq_true, if_false]
          have h1 : (i + 1) * e.words ≤ n * e.words := Nat.mul_le_mul_right _ lt
          have h2 : e.words ≤ (i + 1) * e.words := Nat.le_mul_of_pos_left _ (Nat.succ_pos _)
          omega
      · cases h
  | i32 => simp [SrcType.subStep] at h
  | bool => simp [SrcType.subStep] at h
  | uint => simp [SrcType.subStep] at h
  | enum => simp [SrcType.subStep] at h
  | ptr => simp [SrcType.subStep] at h
  | slice => simp [SrcType.subStep] at h
  | unit => simp [SrcType.subStep] at h
  | isize => simp [SrcType.subStep] at h
  | char => simp [SrcType.subStep] at h
  | float => simp [SrcType.subStep] at h
  | sint => simp [SrcType.subStep] at h
  | view => simp [SrcType.subStep] at h
  | str => simp [SrcType.subStep] at h

theorem SrcType.sub_ext : ∀ (path : List ValueProjection) {ty t : SrcType} {off : Nat},
    ty.sub path = some (off, t) → off + t.ext ≤ 8 * ty.words
  | [], ty, t, off, h => by
    simp only [SrcType.sub, Option.some.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    simpa using SrcType.ext_le ty
  | q :: rest, ty, t, off, h => by
    obtain ⟨o, child, inner, hstep, hrest, rfl⟩ := SrcType.sub_cons h
    have step := SrcType.subStep_ext hstep
    cases hn : child.accessKind.narrow with
    | true =>
      cases rest with
      | nil =>
        simp only [SrcType.sub, Option.some.injEq, Prod.mk.injEq] at hrest
        obtain ⟨rfl, rfl⟩ := hrest
        simpa using step
      | cons q' rest' =>
        obtain ⟨o', c', inner', hstep', -, -⟩ := SrcType.sub_cons hrest
        rcases SrcType.narrow_cases hn with rfl | rfl <;> simp [SrcType.subStep] at hstep'
    | false =>
      have ih := SrcType.sub_ext rest hrest
      have ce : child.ext = 8 * child.words := by simp [SrcType.ext, hn]
      omega

/-- A sub-place of a home is below `2 ^ 62`. -/
theorem Homes.sub_lt {sx : Statics} {bud : Budget} {places : List Addressed} {st : State} {hp : Heap}
    (homes : Homes sx bud places st hp) {x : Addressed} (mem : x ∈ places) {path : List ValueProjection}
    {a : Nat} {t : SrcType} (h : x.sub path = some (a, t)) : a < 2 ^ 62 := by
  have small := homes.small x mem
  simp only [Addressed.sub] at h
  split at h
  · cases h
  rename_i off t' hs
  simp only [Option.some.injEq, Prod.mk.injEq] at h
  obtain ⟨rfl, rfl⟩ := h
  have := SrcType.sub_ext path hs
  omega

theorem toNat_ofNat_small {a : Nat} (lt : a < 2 ^ 62) : (BitVec.ofNat 64 a).toNat = a := by
  simp only [BitVec.toNat_ofNat]
  exact Nat.mod_eq_of_lt (by omega)

/-! ## Binding parameters -/

theorem coreLocal_bindLocal {s : State} (cells : ∀ e ∈ s.cells, e.id < s.nextCell)
    (locs : ∀ b ∈ s.locals, b.2 < s.nextCell) (id' id : Lanius.VarId) (v : Value) :
    coreLocal (s.bindLocal id' v) id = if id' = id then some v else coreLocal s id := by
  have none_old : s.cells.find? (fun cell => cell.id == s.nextCell) = none := by
    rw [List.find?_eq_none]
    intro e mem
    have := cells e mem
    simp only [beq_iff_eq]
    cell_omega
  by_cases same : id' = id
  · subst same
    simp [coreLocal, State.bindLocal, State.bindCell, State.cellId?, State.cellEntry?, List.find?_append,
      none_old]
  · simp only [coreLocal, State.bindLocal, State.bindCell, State.cellId?, State.cellEntry?, if_neg same]
    rw [List.find?_cons_of_neg (by simpa using same)]
    cases hf : s.locals.find? (fun binding => binding.1 == id) with
    | none => rfl
    | some b =>
      have lt := locs b (List.mem_of_find?_eq_some hf)
      simp only [Option.map_some, List.find?_append]
      cases he : s.cells.find? (fun cell => cell.id == b.2) with
      | some e => rfl
      | none =>
        have : [({ id := s.nextCell, value := some v } : Semantics.Cell)].find? (fun cell => cell.id == b.2) =
            none := by
          simp only [List.find?_cons, List.find?_nil]
          split <;> first | rfl | cell_omega
        simp [this]

theorem coreLocal_bindLocals : ∀ (bs : List (Lanius.VarId × Value)) (s : State),
    (∀ e ∈ s.cells, e.id < s.nextCell) → (∀ b ∈ s.locals, b.2 < s.nextCell) →
    ∀ id w, coreLocal (s.bindLocals bs) id = some w → (∃ v, (id, v) ∈ bs ∧ w = v) ∨ coreLocal s id = some w
  | [], s, _, _, id, w, h => .inr h
  | (id', v') :: rest, s, cells, locs, id, w, h => by
    have eq : s.bindLocals ((id', v') :: rest) = (s.bindLocal id' v').bindLocals rest := by
      simp [State.bindLocals]
    rw [eq] at h
    have cells' : ∀ e ∈ (s.bindLocal id' v').cells, e.id < (s.bindLocal id' v').nextCell := by
      intro e mem
      simp only [State.bindLocal, State.bindCell, List.mem_append, List.mem_singleton] at mem ⊢
      rcases mem with mem | rfl
      · have := cells e mem; cell_omega
      · simp
    have locs' : ∀ b ∈ (s.bindLocal id' v').locals, b.2 < (s.bindLocal id' v').nextCell := by
      intro b mem
      simp only [State.bindLocal, State.bindCell, List.mem_cons] at mem ⊢
      rcases mem with rfl | mem
      · simp
      · have := locs b mem; cell_omega
    rcases coreLocal_bindLocals rest _ cells' locs' id w h with ⟨v, mem, hv⟩ | h'
    · exact .inl ⟨v, List.mem_cons_of_mem _ mem, hv⟩
    · rw [coreLocal_bindLocal cells locs] at h'
      split at h'
      · rename_i same
        subst same
        simp only [Option.some.injEq] at h'
        exact .inl ⟨v', List.mem_cons_self, h'.symm⟩
      · exact .inr h'

/-! ## `HomedCorr` -/

theorem HomedCorr.cellId {sx : Statics} {places : List Addressed} {scope : List Binding} {frame : Nat → Nat}
    {c : RCtx} {st : State} {env : Env} (hc : HomedCorr sx places scope frame c st env) (id : Nat) :
    st.cellId? id = (lookup scope id).map fun b => frame b.slot := by
  simp only [State.cellId?, hc.locals, find_locals, Option.map_map]
  rfl

theorem HomedCorr.ofCorr {sx : Statics} {places : List Addressed} {scope : List Binding} {frame : Nat → Nat}
    {c : RCtx} {st : State} {env : Env} (corr : Corr sx places scope frame st env)
    (agree : RefsAgree c places st env) (hc : c.homes = []) : HomedCorr sx places scope frame c st env :=
  { locals := corr.locals
    values := fun b mem _ => corr.values b mem
    unviewed := fun v vm b mem _ nv => corr.unviewed v vm b mem nv
    viewed := fun b mem _ n hty => corr.viewed b mem n hty
    refs := agree
    homedTy := fun _ _ _ _ _ hl => by simp [hc] at hl
    unhomed := fun _ b found _ x xm => corr.apart x xm b (lookup_mem found).1 }

theorem HomedCorr.local {sx : Statics} {bud : Budget} {places : List Addressed} {scope : List Binding}
    {frame : Nat → Nat} {c : RCtx} {st : State} {env : Env} {hp : Heap} (prog : Lanius.Core.Program)
    (hc : HomedCorr sx places scope frame c st env) (homes : Homes sx bud places st hp) {id : Nat} {b : Binding}
    (found : lookup scope id = some b) :
    ∃ v, (∀ fuel, Semantics.evalExpr (fuel + 1) prog st (.local id) = .done v st) ∧
      ((c.homes.lookup id = none ∧ b.ty.HoldsAt sx places v env b.slot) ∨
        ∃ (offset i : Nat) (x : Addressed), c.homes.lookup id = some (offset, b.ty) ∧ places[i]? = some x ∧
          x.cell = frame b.slot ∧ x.ty = b.ty ∧ x.address = (env c.frame).toNat + offset ∧
          x.ty.HoldsAt sx (places.drop (i + 1)) v (x.ty.homeView x.address hp) 0) := by
  have cid : st.cellId? id = some (frame b.slot) := by rw [hc.cellId, found]; rfl
  cases hl : c.homes.lookup id with
  | none =>
    obtain ⟨v, entry, holds⟩ := hc.values b (lookup_mem found).1 (hc.unhomed id b found hl)
    refine ⟨v, fun fuel => CoreRefs.evalExpr_local ?_ fuel, .inl ⟨rfl, holds⟩⟩
    simp [coreLocal, cid, entry]
  | some ot =>
    obtain ⟨offset, ty⟩ := ot
    obtain rfl := hc.homedTy id b offset ty found hl
    obtain ⟨x, mem, cell, hcell, xcell, xty, xaddr⟩ := hc.refs.homes id offset _ hl
    rw [cid, Option.some.injEq] at hcell
    subst hcell
    obtain ⟨i, hi⟩ := List.mem_iff_getElem?.mp mem
    obtain ⟨v, hread, hold⟩ := homes.holds i x hi
    obtain ⟨cid', root, entry, hroot⟩ := CoreRefs.readCell_ok hread
    simp only [Semantics.projectedValue, Except.ok.injEq] at hroot
    subst hroot
    refine ⟨root, fun fuel => CoreRefs.evalExpr_local ?_ fuel, .inr ⟨offset, i, x, rfl, hi, xcell, xty, xaddr, hold⟩⟩
    simp [coreLocal, cid, ← xcell, entry]

theorem HomedCorr.keeps {sx : Statics} {places : List Addressed} {scope : List Binding} {frame : Nat → Nat}
    {c : RCtx} {st st' : State} {env : Env} (hc : HomedCorr sx places scope frame c st env) (fresh : st.Fresh)
    (keeps : Keeps places st.nextCell st st') (locals : st'.locals = st.locals) :
    HomedCorr sx places scope frame c st' env := by
  have below : ∀ b ∈ scope, Unhomed places frame b → frame b.slot < st.nextCell := fun b mem un => by
    obtain ⟨v, entry, -⟩ := hc.values b mem un
    exact fresh.below entry
  have kept : ∀ b ∈ scope, Unhomed places frame b → viewedType b.ty = false →
      st'.cellEntry? (frame b.slot) = st.cellEntry? (frame b.slot) := fun b mem un nv =>
    keeps.cells _ (below b mem un) (fun x xm => un x xm) fun v vm => hc.unviewed v vm b mem un nv
  have viewVal : ∀ b ∈ scope, Unhomed places frame b → ∀ n, b.ty = .view n → ∃ vs,
      st'.cellEntry? (frame b.slot) = some ⟨frame b.slot, some (.array vs)⟩ ∧
        b.ty.HoldsAt sx places (.array vs) env b.slot := by
    intro b mem un n hty
    obtain ⟨w, wm, root, -, wlen, -⟩ := hc.viewed b mem un n hty
    obtain ⟨v0, entry, holds⟩ := hc.values b mem un
    rw [hty] at holds
    cases holds with
    | view len i32s =>
      obtain ⟨vs, entry', len', i32s'⟩ := keeps.arrays w wm ⟨_, root ▸ entry, len.trans wlen.symm, i32s⟩
      exact ⟨vs, root ▸ entry', by rw [hty]; exact .view (len'.trans wlen) i32s'⟩
  have cidEq : ∀ id, st'.cellId? id = st.cellId? id := fun id => by simp [State.cellId?, locals]
  refine
    { locals := locals.trans hc.locals
      values := fun b mem un => ?_
      unviewed := fun v vm b mem un nv =>
        keeps.unrooted (below b mem un) (fun w wm => hc.unviewed w wm b mem un nv) v vm
      viewed := fun b mem un n hty => by
        obtain ⟨w, wm, rest⟩ := hc.viewed b mem un n hty
        exact ⟨w, keeps.persist w wm, rest⟩
      refs := ⟨fun id offset ty hl => ?_, fun id T cell path hl hloc => ?_⟩
      homedTy := hc.homedTy
      unhomed := hc.unhomed }
  · cases nv : viewedType b.ty
    · rw [kept b mem un nv]
      exact hc.values b mem un
    · obtain ⟨n, hty⟩ := viewedType_true nv
      obtain ⟨vs, entry, holds⟩ := viewVal b mem un n hty
      exact ⟨_, entry, holds⟩
  · obtain ⟨x, mem, cell, hcell, rest⟩ := hc.refs.homes id offset ty hl
    exact ⟨x, mem, cell, by rw [cidEq]; exact hcell, rest⟩
  · apply hc.refs.refs id T cell path hl
    have cid := hc.cellId id
    unfold coreLocal at hloc ⊢
    rw [cidEq, cid] at hloc
    rw [cid]
    cases found : lookup scope id with
    | none => simp [found] at hloc
    | some b =>
      rw [found] at hloc
      simp only [Option.map_some] at hloc ⊢
      have un := hc.unhomed id b found hl
      have mem := (lookup_mem found).1
      cases nv : viewedType b.ty
      · rw [kept b mem un nv] at hloc
        exact hloc
      · obtain ⟨n, hty⟩ := viewedType_true nv
        obtain ⟨vs, entry, -⟩ := viewVal b mem un n hty
        simp [entry] at hloc

end Lanius.Mini
