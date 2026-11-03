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

/-! ## Dying homes -/

mutual
/-- A value held against `own ++ places` that names none of `own`'s cells is
held against `places`: only a borrowed slice names a place. -/
theorem SrcType.HoldsAt.drop {sx : Statics} {own places : List Addressed} :
    ∀ {ty : SrcType} {v : Value} {env : Env} {slot : Nat},
      ty.HoldsAt sx (own ++ places) v env slot → (∀ y ∈ own, ¬ v.Names y.cell) → ty.HoldsAt sx places v env slot
  | _, _, _, _, .i32 h, _ => .i32 h
  | _, _, _, _, .bool h, _ => .bool h
  | _, _, _, _, .uint h, _ => .uint h
  | _, _, _, _, .struct h, no => .struct (FieldsHold.drop h fun y my _ mw nm => no y my (.structure mw nm))
  | _, _, _, _, .enum found tag payload, no =>
    .enum found tag (FieldsHold.drop payload fun y my _ mw nm => no y my (.enumeration mw nm))
  | _, _, _, _, .ptr h, _ => .ptr h
  | _, _, _, _, .slice len small, _ => .slice len small
  | _, _, _, _, .borrowed mem sliced root ty packed pointer len small, no => by
    rcases List.mem_append.mp mem with m | m
    · exact absurd .slice (no _ m)
    · exact .borrowed m sliced root ty packed pointer len small
  | _, _, _, _, .array h, no => .array (FieldsHold.drop h fun y my _ mw nm => no y my (.array mw nm))
  | _, _, _, _, .unit, _ => .unit
  | _, _, _, _, .isize h, _ => .isize h
  | _, _, _, _, .char h, _ => .char h
  | _, _, _, _, .float h, _ => .float h
  | _, _, _, _, .sint h, _ => .sint h
  | _, _, _, _, .view len h, _ => .view len h
  | _, _, _, _, .str base len small bytes, _ => .str base len small bytes

theorem FieldsHold.drop {sx : Statics} {own places : List Addressed} :
    ∀ {fs : List SrcType} {vs : List Value} {env : Env} {slot : Nat},
      FieldsHold sx (own ++ places) fs vs env slot → (∀ y ∈ own, ∀ w ∈ vs, ¬ w.Names y.cell) →
        FieldsHold sx places fs vs env slot
  | _, _, _, _, .nil, _ => .nil
  | _, _, _, _, .cons head rest, no =>
    .cons (SrcType.HoldsAt.drop head fun y my nm => no y my _ List.mem_cons_self nm)
      (FieldsHold.drop rest fun y my w mw nm => no y my w (List.mem_cons_of_mem _ mw) nm)
end

theorem RefTo.drop {places : List Addressed} {x : Addressed} {ty : SrcType} {cell : Lanius.CellId}
    {path : List ValueProjection} {w : BitVec 64} (h : RefTo (x :: places) ty cell path w) (ne : cell ≠ x.cell) :
    RefTo places ty cell path w := by
  obtain ⟨y, my, yc, ys⟩ := h
  rcases List.mem_cons.mp my with rfl | my
  · exact absurd yc.symm ne
  · exact ⟨y, my, yc, ys⟩

theorem RefTo.mono {places : List Addressed} {x : Addressed} {ty : SrcType} {cell : Lanius.CellId}
    {path : List ValueProjection} {w : BitVec 64} (h : RefTo places ty cell path w) :
    RefTo (x :: places) ty cell path w := by
  obtain ⟨y, my, rest⟩ := h
  exact ⟨y, List.mem_cons_of_mem _ my, rest⟩

theorem coreLocal_entry {st : State} {id : Lanius.VarId} {w : Value} (h : coreLocal st id = some w) :
    ∃ cl, st.cellId? id = some cl ∧ st.cellEntry? cl = some ⟨cl, some w⟩ := by
  unfold coreLocal at h
  cases hc : st.cellId? id with
  | none => simp [hc] at h
  | some cl =>
    cases he : st.cellEntry? cl with
    | none => simp [hc, he] at h
    | some entry =>
      obtain ⟨cid, value⟩ := entry
      cases value with
      | none => simp [hc, he] at h
      | some w' =>
        simp only [hc, he, Option.some.injEq] at h
        subst h
        have := (cellEntry_mem he).2
        simp only at this
        subst this
        exact ⟨cid, rfl, he⟩

/-- Dropping the youngest home keeps the older ones; its block is free for a
new home of its type. -/
theorem Homes.popHome {sx : Statics} {bud : Budget} {x : Addressed} {places : List Addressed} {st st' : State}
    {hp : Heap} (homes : Homes sx bud (x :: places) st hp)
    (same : ∀ y ∈ places, Semantics.readCellProjection st' y.cell [] = Semantics.readCellProjection st y.cell [])
    (views : st'.i32ArrayViews = st.i32ArrayViews) :
    Homes sx bud places st' hp ∧
      ∀ x' : Addressed, x'.address = x.address → x'.ty = x.ty → (∀ y ∈ places, x'.cell ≠ y.cell) →
        hp.fsp ≤ x'.address ∧ hp.limit ≤ x'.address ∧ x'.address + 8 * x'.ty.words ≤ hp.top ∧
        x'.address + 8 * x'.ty.words < 2 ^ 62 ∧
        ∀ y ∈ places, x'.cell ≠ y.cell ∧
          (x'.address + 8 * x'.ty.words ≤ y.address ∨ y.address + 8 * y.ty.words ≤ x'.address) := by
  refine ⟨{ holds := fun i y hy => ?_
            roots := fun y m => homes.roots y (List.mem_cons_of_mem _ m)
            sliced := fun y m => homes.sliced y (List.mem_cons_of_mem _ m)
            layout := fun y m => homes.layout y (List.mem_cons_of_mem _ m)
            inside := fun y m => homes.inside y (List.mem_cons_of_mem _ m)
            small := fun y m => homes.small y (List.mem_cons_of_mem _ m)
            apart := fun i j y z hy hz ne =>
              homes.apart (i + 1) (j + 1) y z (by simpa using hy) (by simpa using hz) (by omega)
            unviewed := by rw [views]; exact fun v vm y m => homes.unviewed v vm y (List.mem_cons_of_mem _ m)
            room := homes.room
            ceiling := homes.ceiling
            bounded := homes.bounded
            statics := homes.statics }, fun x' ha ht hc => ?_⟩
  · obtain ⟨v, hr, hold⟩ := homes.holds (i + 1) y (by simpa using hy)
    exact ⟨v, by rw [same y (List.mem_of_getElem? hy)]; exact hr, by simpa using hold⟩
  · have inside := homes.inside x List.mem_cons_self
    have small := homes.small x List.mem_cons_self
    rw [ha, ht]
    refine ⟨inside.1, inside.2.1, inside.2.2, small, fun y my => ⟨by rw [← ha, ← ht] at *; exact hc y my, ?_⟩⟩
    obtain ⟨j, hj⟩ := List.mem_iff_getElem?.mp my
    exact (homes.apart 0 (j + 1) x y rfl (by simpa using hj) (by omega)).2

/-! ## A homed `let` -/

theorem lookup_cons_self (id next : Nat) (ty : SrcType) (scope : List Binding) :
    lookup (⟨id, next, ty⟩ :: scope) id = some ⟨id, next, ty⟩ := by
  simp [lookup]

theorem lookup_cons_ne {id id' next : Nat} {ty : SrcType} (scope : List Binding) (ne : id' ≠ id) :
    lookup (⟨id, next, ty⟩ :: scope) id' = lookup scope id' := by
  simp [lookup, Ne.symm ne]

theorem homes_lookup_ne {id id' : Lanius.VarId} {e : Nat × SrcType} (homes : List (Lanius.VarId × Nat × SrcType))
    (ne : id' ≠ id) : ((id, e) :: homes).lookup id' = homes.lookup id' := by
  have : (id' == id) = false := by simpa using ne
  simp [List.lookup, this]

theorem homes_lookup_self {id : Lanius.VarId} {e : Nat × SrcType} (homes : List (Lanius.VarId × Nat × SrcType)) :
    ((id, e) :: homes).lookup id = some e := by
  simp [List.lookup]

theorem HomedCorr.pushHome {sx : Statics} {places : List Addressed} {scope : List Binding} {frame : Nat → Nat}
    {c : RCtx} {st : State} {env env' : Env} {base next id offset : Nat} {ty : SrcType} {v : Value}
    {x : Addressed} (hc : HomedCorr sx places scope frame c st env) (fr : Layout scope frame base next)
    (fresh : st.Fresh) (agree : ScopeAgree scope env env') (under : ∀ y ∈ places, y.cell < st.nextCell)
    (hframe : env' c.frame = env c.frame)
    (hslots : ∀ id', c.homes.lookup id' = none → env' (c.slotOf id') = env (c.slotOf id'))
    (hxcell : x.cell = st.nextCell) (hxty : x.ty = ty) (hxaddr : x.address = (env c.frame).toNat + offset) :
    HomedCorr sx (x :: places) (⟨id, next, ty⟩ :: scope) (upd frame next st.nextCell)
      { c with homes := (id, offset, ty) :: c.homes } (st.bindLocal id v) env' := by
  have below : ∀ b ∈ scope, frame b.slot < st.nextCell := fun b mem => by
    by_cases un : Unhomed places frame b
    · obtain ⟨w, entry, -⟩ := hc.values b mem un
      exact fresh.below entry
    · have : ∃ y ∈ places, y.cell = frame b.slot :=
        Classical.byContradiction fun hne => un fun y my eq => hne ⟨y, my, eq⟩
      obtain ⟨y, my, hy⟩ := this
      rw [← hy]
      exact under y my
  have same := upd_scope fr st.nextCell
  have locs : ∀ p ∈ st.locals, p.2 < st.nextCell := by
    rw [hc.locals]
    intro p mem
    obtain ⟨b, mb, rfl⟩ := List.mem_map.mp mem
    exact below b mb
  have unNew : ∀ b ∈ scope, Unhomed (x :: places) (upd frame next st.nextCell) b → Unhomed places frame b :=
    fun b mem un y my => by rw [← same b mem]; exact un y (List.mem_cons_of_mem _ my)
  have unOld : ∀ b ∈ scope, Unhomed places frame b → Unhomed (x :: places) (upd frame next st.nextCell) b := by
    intro b mem un y my
    rw [same b mem]
    rcases List.mem_cons.mp my with rfl | my
    · have := below b mem
      rw [hxcell]
      cell_omega
    · exact un y my
  have newHomed : ¬ Unhomed (x :: places) (upd frame next st.nextCell) ⟨id, next, ty⟩ :=
    fun un => un x List.mem_cons_self (by simp [upd, hxcell])
  have cidNe : ∀ id', id' ≠ id → (st.bindLocal id v).cellId? id' = st.cellId? id' := by
    intro id' ne
    simp [State.cellId?, State.bindLocal, State.bindCell, Ne.symm ne]
  have cidNew : (st.bindLocal id v).cellId? id = some st.nextCell := by
    simp [State.cellId?, State.bindLocal, State.bindCell]
  refine
    { locals := ?_
      values := fun b mem un => ?_
      unviewed := fun w wm b mem un nv => ?_
      viewed := fun b mem un n hty => ?_
      refs := ⟨fun id' o t hl => ?_, fun id' T cell path hl hloc => ?_⟩
      homedTy := fun id' b o t hs hl => ?_
      unhomed := fun id' b hs hl => ?_ }
  · simp only [State.bindLocal, State.bindCell, List.map_cons, hc.locals, upd, if_pos]
    congr 1
    apply List.map_congr_left
    intro b mem
    rw [← upd, same b mem]
  · rcases List.mem_cons.mp mem with rfl | mb
    · exact absurd un newHomed
    · obtain ⟨w, entry, holds⟩ := hc.values b mb (unNew b mb un)
      refine ⟨w, ?_, (holds.mono fun y m => List.mem_cons_of_mem _ m).congr (agree b mb)⟩
      rw [same b mb, bindLocal_entry (below b mb)]
      exact entry
  · rcases List.mem_cons.mp mem with rfl | mb
    · exact absurd un newHomed
    · rw [same b mb]
      exact hc.unviewed w wm b mb (unNew b mb un) nv
  · rcases List.mem_cons.mp mem with rfl | mb
    · exact absurd un newHomed
    · obtain ⟨w, wm, root, address, length, pos⟩ := hc.viewed b mb (unNew b mb un) n hty
      refine ⟨w, wm, by rw [same b mb]; exact root, ?_, length, pos⟩
      have := agree b mb 0 (by rw [hty]; exact pos)
      simp only [Nat.add_zero] at this
      rw [this]
      exact address
  · by_cases eq : id' = id
    · subst eq
      rw [homes_lookup_self, Option.some.injEq, Prod.mk.injEq] at hl
      obtain ⟨rfl, rfl⟩ := hl
      exact ⟨x, List.mem_cons_self, st.nextCell, cidNew, hxcell, hxty, by rw [hframe]; exact hxaddr⟩
    · rw [homes_lookup_ne _ eq] at hl
      obtain ⟨y, my, cell, hcell, yc, yt, ya⟩ := hc.refs.homes id' o t hl
      exact ⟨y, List.mem_cons_of_mem _ my, cell, by rw [cidNe id' eq]; exact hcell, yc, yt,
        by rw [hframe]; exact ya⟩
  · by_cases eq : id' = id
    · subst eq
      simp at hl
    · rw [homes_lookup_ne _ eq] at hl
      rw [coreLocal_bindLocal fresh.1 locs, if_neg (Ne.symm eq)] at hloc
      have r := hc.refs.refs id' T cell path hl hloc
      rw [hslots id' hl]
      exact r.mono
  · by_cases eq : id' = id
    · subst eq
      rw [lookup_cons_self, Option.some.injEq] at hs
      rw [homes_lookup_self, Option.some.injEq, Prod.mk.injEq] at hl
      obtain ⟨-, rfl⟩ := hl
      rw [← hs]
    · rw [lookup_cons_ne _ eq] at hs
      rw [homes_lookup_ne _ eq] at hl
      exact hc.homedTy id' b o t hs hl
  · by_cases eq : id' = id
    · subst eq
      simp at hl
    · rw [lookup_cons_ne _ eq] at hs
      rw [homes_lookup_ne _ eq] at hl
      exact unOld b (lookup_mem hs).1 (hc.unhomed id' b hs hl)

theorem HomedCorr.popHome {sx : Statics} {places : List Addressed} {scope : List Binding} {frame : Nat → Nat}
    {c : RCtx} {st₀ st st' : State} {env₀ env : Env} {base next id offset : Nat} {ty : SrcType} {x : Addressed}
    (hc₀ : HomedCorr sx places scope frame c st₀ env₀)
    (hc : HomedCorr sx (x :: places) (⟨id, next, ty⟩ :: scope) (upd frame next x.cell)
      { c with homes := (id, offset, ty) :: c.homes } st env)
    (fr : Layout scope frame base next) (apartCell : ∀ b ∈ scope, frame b.slot ≠ x.cell)
    (locals : st'.locals = st₀.locals) (cells : st'.cells = st.cells) (views : st'.i32ArrayViews = st.i32ArrayViews)
    (hframe : env c.frame = env₀ c.frame)
    (noName : ∀ b ∈ scope, ∀ w, st.cellEntry? (frame b.slot) = some ⟨frame b.slot, some w⟩ → ¬ w.Names x.cell)
    (shadow : c.homes.lookup id = none → coreLocal st' id = coreLocal st₀ id ∧ env (c.slotOf id) = env₀ (c.slotOf id)) :
    HomedCorr sx places scope frame c st' env := by
  have same := upd_scope fr x.cell
  have un' : ∀ b ∈ scope, Unhomed places frame b → Unhomed (x :: places) (upd frame next x.cell) b := by
    intro b mem un y my
    rw [same b mem]
    rcases List.mem_cons.mp my with rfl | my
    · exact (apartCell b mem).symm
    · exact un y my
  have entryEq : ∀ cl, st'.cellEntry? cl = st.cellEntry? cl := fun cl => by simp [State.cellEntry?, cells]
  have cidEq : ∀ id', st'.cellId? id' = st₀.cellId? id' := fun id' => by simp [State.cellId?, locals]
  refine
    { locals := locals.trans hc₀.locals
      values := fun b mem un => ?_
      unviewed := fun w wm b mem un nv => ?_
      viewed := fun b mem un n hty => ?_
      refs := ⟨fun id' o t hl => ?_, fun id' T cell path hl hloc => ?_⟩
      homedTy := hc₀.homedTy
      unhomed := hc₀.unhomed }
  · obtain ⟨w, entry, holds⟩ := hc.values b (List.mem_cons_of_mem _ mem) (un' b mem un)
    rw [same b mem] at entry
    refine ⟨w, by rw [entryEq]; exact entry, SrcType.HoldsAt.drop (own := [x]) holds fun y my => ?_⟩
    rw [List.mem_singleton] at my
    subst my
    exact noName b mem w entry
  · rw [views] at wm
    have := hc.unviewed w wm b (List.mem_cons_of_mem _ mem) (un' b mem un) nv
    rwa [same b mem] at this
  · obtain ⟨w, wm, root, rest⟩ := hc.viewed b (List.mem_cons_of_mem _ mem) (un' b mem un) n hty
    exact ⟨w, by rw [views]; exact wm, by rw [← same b mem]; exact root, rest⟩
  · obtain ⟨y, my, cell, hcell, yc, yt, ya⟩ := hc₀.refs.homes id' o t hl
    exact ⟨y, my, cell, by rw [cidEq]; exact hcell, yc, yt, by rw [hframe]; exact ya⟩
  · by_cases eq : id' = id
    · subst eq
      obtain ⟨h1, h2⟩ := shadow hl
      rw [h1] at hloc
      rw [h2]
      exact hc₀.refs.refs id' T cell path hl hloc
    · have hl' : ({ c with homes := (id, offset, ty) :: c.homes } : RCtx).homes.lookup id' = none := by
        rw [homes_lookup_ne _ eq]; exact hl
      have c1 : st'.cellId? id' = st.cellId? id' := by
        rw [cidEq, hc₀.cellId, hc.cellId, lookup_cons_ne _ eq]
        cases found : lookup scope id' with
        | none => rfl
        | some b => simp [same b (lookup_mem found).1]
      have hloc' : coreLocal st id' = some (.reference T cell path) := by
        unfold coreLocal at hloc ⊢
        rw [← c1]
        cases h : st'.cellId? id' with
        | none => rw [h] at hloc; exact hloc
        | some cl => rw [h] at hloc; simp only [entryEq] at hloc; exact hloc
      have r := hc.refs.refs id' T cell path hl' hloc'
      refine r.drop fun hcx => ?_
      obtain ⟨cl, hcl, hent⟩ := coreLocal_entry hloc'
      rw [hc.cellId, lookup_cons_ne _ eq] at hcl
      cases found : lookup scope id' with
      | none => simp [found] at hcl
      | some b =>
        have mb := (lookup_mem found).1
        simp only [found, Option.map_some, Option.some.injEq, same b mb] at hcl
        subst hcl
        subst hcx
        exact noName b mb _ hent .reference

end Lanius.Mini
