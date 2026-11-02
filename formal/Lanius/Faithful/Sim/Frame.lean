module

public import Lanius.Faithful.Sim.State
public import Lanius.Faithful.Agree

@[expose] public section
/-! # What a statement keeps

Expressions of the pure subset only append cells (`Step`). A statement may
also assign a local, which writes the cell its newest binding names. So a
statement keeps a `Frame`: every cell that no visible local names (a
shadowed local's, a caller's) keeps its value, the others keep their ids,
and new cells come after. `Locs`: distinct visible locals name distinct
allocated cells, so an assignment changes no other visible local. On the
pure side an assignment replaces the newest binding of its local
(`Env.set`), and a statement keeps every binding a newer one of the same
local hides (`Agree`). -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State HeapReads restoreLocals replaceCell evalExpr execStmt Completion)

/-! ## Cells -/

/-- A cell that a visible local names: the newest binding of some local. -/
def _root_.Lanius.Semantics.State.Visible (st : State) (c : Nat) : Prop := ∃ y, st.cellId? y = some c

/-- `cs'` has the cells of `cs`, in order and with their ids, and then
more; a cell whose id is not `vis` keeps its value. -/
def CellsKeep (vis : Nat → Prop) : List Semantics.Cell → List Semantics.Cell → Prop
  | [], _ => True
  | c :: cs, c' :: cs' => c'.id = c.id ∧ (¬ vis c.id → c' = c) ∧ CellsKeep vis cs cs'
  | _ :: _, [] => False

theorem CellsKeep.append (vis : Nat → Prop) : ∀ (cs extra : List Semantics.Cell), CellsKeep vis cs (cs ++ extra)
  | [], _ => trivial
  | _ :: cs, extra => ⟨rfl, fun _ => rfl, CellsKeep.append vis cs extra⟩

theorem CellsKeep.refl (vis : Nat → Prop) (cs : List Semantics.Cell) : CellsKeep vis cs cs := by
  simpa using CellsKeep.append vis cs []

theorem CellsKeep.trans {vis : Nat → Prop} :
    ∀ {a b c : List Semantics.Cell}, CellsKeep vis a b → CellsKeep vis b c → CellsKeep vis a c
  | [], _, _, _, _ => trivial
  | _ :: _, [], _, h, _ => h.elim
  | _ :: _, _ :: _, [], _, h => h.elim
  | x :: a, y :: b, z :: c, ⟨i1, k1, r1⟩, ⟨i2, k2, r2⟩ =>
    ⟨i2.trans i1, fun nv => by rw [k2 (by rw [i1]; exact nv), k1 nv], CellsKeep.trans r1 r2⟩

/-- The cells of `cs` are kept, when the last one of `cs ++ [n]` is dropped. -/
theorem CellsKeep.init {vis : Nat → Prop} {n : Semantics.Cell} :
    ∀ {cs cs' : List Semantics.Cell}, CellsKeep vis (cs ++ [n]) cs' → CellsKeep vis cs cs'
  | [], _, _ => trivial
  | _ :: _, [], h => h.elim
  | _ :: cs, _ :: _, ⟨i, k, r⟩ => ⟨i, k, CellsKeep.init (cs := cs) r⟩

theorem CellsKeep.mono {vis vis' : Nat → Prop} :
    ∀ {cs cs' : List Semantics.Cell}, (∀ c ∈ cs, vis c.id → vis' c.id) → CellsKeep vis cs cs' → CellsKeep vis' cs cs'
  | [], _, _, _ => trivial
  | _ :: _, [], _, h => h.elim
  | c :: _, _ :: _, sub, ⟨i, k, r⟩ =>
    ⟨i, fun nv => k fun v => nv (sub c List.mem_cons_self v),
      CellsKeep.mono (fun c' m => sub c' (List.mem_cons_of_mem _ m)) r⟩

theorem CellsKeep.find {vis : Nat → Prop} {x : Nat} {e : Semantics.Cell} (nv : ¬ vis x) :
    ∀ {cs cs' : List Semantics.Cell}, CellsKeep vis cs cs' → cs.find? (fun cell => cell.id == x) = some e →
      cs'.find? (fun cell => cell.id == x) = some e
  | [], _, _, h => by simp at h
  | _ :: _, [], h, _ => h.elim
  | c :: cs, c' :: cs', ⟨i, k, r⟩, h => by
    by_cases hx : c.id = x
    · have hc : (c.id == x) = true := by simpa using hx
      have hc' : (c'.id == x) = true := by simpa [i] using hx
      simp only [List.find?_cons, hc, Option.some.injEq] at h
      subst h
      rw [List.find?_cons, hc', k (by rw [hx]; exact nv)]
    · have hc : (c.id == x) = false := by simpa using hx
      have hc' : (c'.id == x) = false := by simpa [i] using hx
      simp only [List.find?_cons, hc] at h
      rw [List.find?_cons, hc']
      exact CellsKeep.find nv r h

theorem CellsKeep.isSome {vis : Nat → Prop} {x : Nat} :
    ∀ {cs cs' : List Semantics.Cell}, CellsKeep vis cs cs' → (cs.find? fun cell => cell.id == x).isSome →
      (cs'.find? fun cell => cell.id == x).isSome
  | [], _, _, h => by simp at h
  | _ :: _, [], h, _ => h.elim
  | c :: cs, c' :: cs', ⟨i, _, r⟩, h => by
    by_cases hx : c.id = x
    · have hc' : (c'.id == x) = true := by simpa [i] using hx
      simp [hc']
    · have hc : (c.id == x) = false := by simpa using hx
      have hc' : (c'.id == x) = false := by simpa [i] using hx
      simp only [List.find?_cons, hc] at h
      rw [List.find?_cons, hc']
      exact CellsKeep.isSome r h

theorem CellsKeep.replace {vis : Nat → Prop} {x : Nat} (hv : vis x) (v : Value) :
    ∀ (cs : List Semantics.Cell), CellsKeep vis cs (replaceCell cs x v)
  | [] => trivial
  | c :: cs => by
    simp only [replaceCell]
    split
    · rename_i h
      have hx : c.id = x := by simpa using h
      exact ⟨rfl, fun nv => absurd (hx ▸ hv) nv, CellsKeep.replace hv v cs⟩
    · exact ⟨rfl, fun _ => rfl, CellsKeep.replace hv v cs⟩

/-! ## Frames -/

/-- What a statement keeps of the state it ran from. -/
structure Frame (st st' : State) : Prop where
  cells : CellsKeep st.Visible st.cells st'.cells
  reads : HeapReads st.heap st'.heap
  ranges : HeapRanges st.heap st'.heap

theorem Step.frame {st st' : State} (step : Step st st') : Frame st st' := by
  obtain ⟨extra, eq⟩ := step.cells
  exact ⟨by rw [← eq]; exact CellsKeep.append _ _ _, step.reads, step.ranges⟩

theorem Frame.refl (st : State) : Frame st st := (Step.refl st).frame

theorem _root_.Lanius.Semantics.State.visible_locals {st st' : State} (locals : st'.locals = st.locals) : st'.Visible = st.Visible := by
  funext c
  simp [State.Visible, State.cellId?, locals]

theorem Frame.trans {a b c : State} (first : Frame a b) (second : Frame b c) (locals : b.locals = a.locals) :
    Frame a c := by
  have second' := second.cells
  rw [State.visible_locals locals] at second'
  exact ⟨first.cells.trans second', first.reads.trans second.reads, first.ranges.trans second.ranges⟩

theorem Frame.restore {st st' : State} (s : State) (fr : Frame st st') : Frame st (restoreLocals s st') :=
  ⟨fr.cells, fr.reads, fr.ranges⟩

theorem Frame.entry {st st' : State} (fr : Frame st st') {c : Nat} {e : Semantics.Cell} (nv : ¬ st.Visible c)
    (found : st.cellEntry? c = some e) : st'.cellEntry? c = some e :=
  CellsKeep.find nv fr.cells found

theorem Frame.isSome {st st' : State} (fr : Frame st st') {c : Nat} (found : (st.cellEntry? c).isSome) :
    (st'.cellEntry? c).isSome :=
  CellsKeep.isSome fr.cells found

/-! ## Distinct allocated locals -/

/-- Distinct visible locals name distinct allocated cells. -/
structure Locs (st : State) : Prop where
  distinct : ∀ x y c, st.cellId? x = some c → st.cellId? y = some c → x = y
  alloc : ∀ x c, st.cellId? x = some c → (st.cellEntry? c).isSome

theorem cellEntry?_lt {st : State} (inv : Inv st) {c : Nat} (h : (st.cellEntry? c).isSome) : c < st.nextCell := by
  simp only [State.cellEntry?, Option.isSome_iff_exists] at h
  obtain ⟨e, he⟩ := h
  have mem := List.mem_of_find?_eq_some he
  have eq : e.id = c := by simpa using List.find?_some he
  exact eq ▸ inv.fresh e mem

theorem cellId?_bindLocal {st : State} (id : Nat) (v : Value) (x : Nat) :
    (st.bindLocal id v).cellId? x = if id = x then some st.nextCell else st.cellId? x := by
  by_cases h : id = x
  · subst h
    simp [State.cellId?, State.bindLocal, State.bindCell]
  · have hb : (id == x) = false := by simpa using h
    simp [State.cellId?, State.bindLocal, State.bindCell, hb, h]

theorem cellEntry?_bindLocal {st : State} {id : Nat} {v : Value} {c : Nat} {e : Semantics.Cell}
    (found : st.cellEntry? c = some e) : (st.bindLocal id v).cellEntry? c = some e :=
  cellEntry?_prefix (Step.bindLocal st id v).cells found

theorem Locs.bindLocal {st : State} (inv : Inv st) (h : Locs st) (id : Nat) (v : Value) :
    Locs (st.bindLocal id v) := by
  constructor
  · intro x y c hx hy
    rw [cellId?_bindLocal] at hx hy
    by_cases ex : id = x <;> by_cases ey : id = y
    · exact ex.symm.trans ey
    · rw [if_pos ex] at hx
      rw [if_neg ey] at hy
      cases hx
      exact absurd (cellEntry?_lt inv (h.alloc y _ hy)) (Nat.lt_irrefl _)
    · rw [if_neg ex] at hx
      rw [if_pos ey] at hy
      cases hy
      exact absurd (cellEntry?_lt inv (h.alloc x _ hx)) (Nat.lt_irrefl _)
    · rw [if_neg ex] at hx
      rw [if_neg ey] at hy
      exact h.distinct x y c hx hy
  · intro x c hx
    rw [cellId?_bindLocal] at hx
    by_cases ex : id = x
    · simp only [ex, if_true, Option.some.injEq] at hx
      subst hx
      simp [State.cellEntry?, State.bindLocal, State.bindCell, List.find?_append]
    · simp only [ex, if_false] at hx
      obtain ⟨e, he⟩ := Option.isSome_iff_exists.mp (h.alloc x c hx)
      rw [cellEntry?_bindLocal he]
      rfl

theorem Locs.keep {st st' : State} (h : Locs st) (keep : ∀ c, (st.cellEntry? c).isSome → (st'.cellEntry? c).isSome)
    (locals : st'.locals = st.locals) : Locs st' := by
  have ids : ∀ x, st'.cellId? x = st.cellId? x := fun x => by simp [State.cellId?, locals]
  exact ⟨fun x y c hx hy => h.distinct x y c (ids x ▸ hx) (ids y ▸ hy),
    fun x c hx => keep c (h.alloc x c (ids x ▸ hx))⟩

theorem Locs.step {st st' : State} (h : Locs st) (step : Step st st') (locals : st'.locals = st.locals) :
    Locs st' :=
  h.keep (fun _ hc => step.frame.isSome hc) locals

theorem Locs.frame {st st' : State} (h : Locs st) (fr : Frame st st') (locals : st'.locals = st.locals) :
    Locs st' :=
  h.keep (fun _ hc => fr.isSome hc) locals

theorem Locs.restore {s st : State} (h : Locs s) (keep : ∀ c, (s.cellEntry? c).isSome → (st.cellEntry? c).isSome) :
    Locs (restoreLocals s st) := by
  have ids : ∀ x, (restoreLocals s st).cellId? x = s.cellId? x := fun x => by
    simp [State.cellId?, restoreLocals]
  have entry : ∀ c, (restoreLocals s st).cellEntry? c = st.cellEntry? c := fun c => by
    simp [State.cellEntry?, restoreLocals]
  exact ⟨fun x y c hx hy => h.distinct x y c (ids x ▸ hx) (ids y ▸ hy),
    fun x c hx => by rw [entry]; exact keep c (h.alloc x c (ids x ▸ hx))⟩

theorem Locs.nil (st : State) : Locs { st with locals := [] } :=
  ⟨fun x _ c hx _ => by simp [State.cellId?] at hx, fun x c hx => by simp [State.cellId?] at hx⟩

theorem Locs.bindLocals : ∀ (bs : List (Nat × Value)) {st : State}, Inv st → Locs st → Locs (st.bindLocals bs)
  | [], _, _, h => h
  | b :: bs, st, inv, h => by
    rw [bindLocals_cons]
    exact Locs.bindLocals bs (inv.bindLocal b.1 b.2) (h.bindLocal inv b.1 b.2)

/-- A callee's entry state: its parameters, each in a fresh cell. -/
theorem Locs.entry {st : State} (inv : Inv st) (bs : List (Nat × Value)) :
    Locs (({ st with locals := [] } : State).bindLocals bs) :=
  Locs.bindLocals bs inv.clear (Locs.nil st)

/-- The cell a `let`'s local shadows is not visible in its body. -/
theorem not_visible_shadowed {st : State} (inv : Inv st) (h : Locs st) {id c : Nat} {v : Value}
    (hc : st.cellId? id = some c) : ¬ (st.bindLocal id v).Visible c := by
  rintro ⟨y, hy⟩
  rw [cellId?_bindLocal] at hy
  by_cases ey : id = y
  · simp only [ey, if_true, Option.some.injEq] at hy
    subst hy
    exact absurd (cellEntry?_lt inv (h.alloc id _ hc)) (Nat.lt_irrefl _)
  · simp only [ey, if_false] at hy
    exact ey (h.distinct id y c hc hy)

/-- A cell of `st` that is not visible in `st` is not visible in a `let`'s body. -/
theorem visible_bindLocal {st : State} (inv : Inv st) {id : Nat} {v : Value} {c : Nat}
    (mem : (st.cellEntry? c).isSome) (vis : (st.bindLocal id v).Visible c) : st.Visible c := by
  obtain ⟨y, hy⟩ := vis
  rw [cellId?_bindLocal] at hy
  by_cases ey : id = y
  · simp only [ey, if_true, Option.some.injEq] at hy
    subst hy
    exact absurd (cellEntry?_lt inv mem) (Nat.lt_irrefl _)
  · simp only [ey, if_false] at hy
    exact ⟨y, hy⟩

/-- A `let`'s body kept a frame of the state it bound: the `let` keeps one of
the state it ran from. -/
theorem Frame.unbind {st s : State} (inv : Inv st) {id : Nat} {v : Value} (fr : Frame (st.bindLocal id v) s) :
    Frame st (restoreLocals st s) := by
  have cells : CellsKeep (st.bindLocal id v).Visible (st.cells ++ [{ id := st.nextCell, value := some v }]) s.cells :=
    fr.cells
  refine ⟨CellsKeep.mono ?_ (CellsKeep.init cells), fr.reads, fr.ranges⟩
  intro c mem vis
  have found : (st.cellEntry? c.id).isSome := by
    simp only [State.cellEntry?]
    exact List.find?_isSome.mpr ⟨c, mem, by simp⟩
  exact visible_bindLocal inv found vis

/-! ## Assignment -/

theorem find?_replaceCell_ne {c x : Nat} (ne : x ≠ c) (w : Value) :
    ∀ (cs : List Semantics.Cell), (replaceCell cs c w).find? (fun cell => cell.id == x) =
      cs.find? (fun cell => cell.id == x)
  | [] => rfl
  | cell :: cs => by
    simp only [replaceCell]
    split
    · rename_i h
      have hc : cell.id = c := by simpa using h
      have hx : (cell.id == x) = false := by simp [hc, Ne.symm ne]
      rw [List.find?_cons, List.find?_cons]
      simp only [hx]
      exact find?_replaceCell_ne ne w cs
    · rw [List.find?_cons, List.find?_cons]
      split
      · rfl
      · exact find?_replaceCell_ne ne w cs

theorem find?_replaceCell_self {c : Nat} (w : Value) :
    ∀ (cs : List Semantics.Cell), (replaceCell cs c w).find? (fun cell => cell.id == c) =
      (cs.find? (fun cell => cell.id == c)).map fun e => { e with value := some w }
  | [] => rfl
  | cell :: cs => by
    simp only [replaceCell]
    split
    · rename_i h
      rw [List.find?_cons, List.find?_cons]
      simp [h]
    · rename_i h
      rw [List.find?_cons, List.find?_cons]
      simp only [h]
      exact find?_replaceCell_self w cs

theorem mem_replaceCell {c : Nat} {w : Value} :
    ∀ {cs : List Semantics.Cell} {x : Semantics.Cell}, x ∈ replaceCell cs c w → ∃ y ∈ cs, y.id = x.id
  | [], _, h => by simp [replaceCell] at h
  | cell :: cs, x, h => by
    simp only [replaceCell] at h
    split at h
    · rcases List.mem_cons.mp h with h | h
      · exact ⟨cell, List.mem_cons_self, by rw [h]⟩
      · obtain ⟨y, m, e⟩ := mem_replaceCell h
        exact ⟨y, List.mem_cons_of_mem _ m, e⟩
    · rcases List.mem_cons.mp h with h | h
      · exact ⟨cell, List.mem_cons_self, by rw [h]⟩
      · obtain ⟨y, m, e⟩ := mem_replaceCell h
        exact ⟨y, List.mem_cons_of_mem _ m, e⟩

/-- The state after `id = w`, the cell `c` of `id`'s newest binding written. -/
abbrev _root_.Lanius.Semantics.State.assigned (st : State) (c : Nat) (w : Value) : State := { st with cells := replaceCell st.cells c w }

theorem Inv.assigned {st : State} (inv : Inv st) (c : Nat) (w : Value) : Inv (st.assigned c w) := by
  refine ⟨inv.views, ?_, inv.below, inv.unique⟩
  intro x mem
  obtain ⟨y, m, e⟩ := mem_replaceCell mem
  exact e ▸ inv.fresh y m

theorem Frame.assigned {st : State} {id c : Nat} (hc : st.cellId? id = some c) (w : Value) :
    Frame st (st.assigned c w) :=
  ⟨CellsKeep.replace ⟨id, hc⟩ w st.cells, HeapReads.refl _, HeapRanges.refl _⟩

theorem Locs.assigned {st : State} (h : Locs st) {id c : Nat} (hc : st.cellId? id = some c) (w : Value) :
    Locs (st.assigned c w) :=
  h.frame (Frame.assigned hc w) rfl

section
variable {P : Core.Program} {boxes : Boxes}

/-- **An assignment's local has the new value, and the other locals theirs.** -/
theorem EnvRel.assign {heap : Memory.Heap} {tenv : TEnv} {env e : Env} {st : State} {id c : Nat} {t : SrcType}
    {w p : Value} (locs : Locs st) (rel : EnvRel P boxes heap tenv env st) (hc : st.cellId? id = some c)
    (ht : tenv.get? id = some t) (r : VRel P boxes heap t w p) (hs : env.set id p = some e) :
    EnvRel P boxes heap tenv e (st.assigned c w) := by
  intro x tx hx
  have ids : (st.assigned c w).cellId? x = st.cellId? x := rfl
  by_cases same : x = id
  · subst same
    rw [ht, Option.some.injEq] at hx
    subst hx
    obtain ⟨e0, he0⟩ := Option.isSome_iff_exists.mp (locs.alloc x c hc)
    refine ⟨w, p, ?_, Env.set_get_self hs, r⟩
    simp only [State.local?, ids, hc, Option.bind_some, State.cell?, State.cellEntry?, State.assigned]
    rw [find?_replaceCell_self]
    simp only [State.cellEntry?] at he0
    rw [he0]
    rfl
  · obtain ⟨v, q, hv, hq, rq⟩ := rel x tx hx
    refine ⟨v, q, ?_, by rw [Env.set_get_ne hs same]; exact hq, rq⟩
    simp only [State.local?] at hv ⊢
    rw [ids]
    cases hcx : st.cellId? x with
    | none => rw [hcx] at hv; cases hv
    | some cx =>
      rw [hcx] at hv
      have ne : cx ≠ c := fun eq => same (locs.distinct x id c (eq ▸ hcx) hc)
      simp only [Option.bind_some, State.cell?, State.cellEntry?] at hv ⊢
      rw [find?_replaceCell_ne ne]
      exact hv

theorem local?_restore (st s : State) (x : Nat) :
    (restoreLocals st s).local? x = (st.cellId? x).bind s.cell? := rfl

/-- **After a `let`'s body: the locals below the `let`'s are related, and the
one its local shadowed.** -/
theorem EnvRel.pop {tenv : TEnv} {env e : Env} {st s : State} {id : Nat} {t : SrcType} {v p : Value}
    (inv : Inv st) (locs : Locs st) (rel0 : EnvRel P boxes st.heap tenv env st)
    (relB : EnvRel P boxes s.heap ((id, t) :: tenv) e s) (ag : Agree [] ((id, p) :: env) e)
    (fr : Frame (st.bindLocal id v) s) (locals : s.locals = (st.bindLocal id v).locals) :
    EnvRel P boxes s.heap tenv e.tail (restoreLocals st s) := by
  obtain ⟨ag', getId, w, he⟩ := ag.pop
  intro x tx hx
  by_cases same : id = x
  · subst same
    obtain ⟨v0, p0, hv0, hp0, r0⟩ := rel0 id tx hx
    refine ⟨v0, p0, ?_, by rw [getId]; exact hp0, r0.mono fr.reads fr.ranges⟩
    rw [local?_restore]
    simp only [State.local?] at hv0
    cases hc : st.cellId? id with
    | none => rw [hc] at hv0; cases hv0
    | some c0 =>
      rw [hc, Option.bind_some] at hv0
      simp only [Option.bind_some, State.cell?] at hv0 ⊢
      cases he0 : st.cellEntry? c0 with
      | none => rw [he0] at hv0; cases hv0
      | some e0 =>
        rw [he0] at hv0
        rw [fr.entry (not_visible_shadowed inv locs hc) (cellEntry?_bindLocal he0)]
        exact hv0
  · have hx' : TEnv.get? ((id, t) :: tenv) x = some tx := by rw [TEnv.get?_cons, if_neg same]; exact hx
    obtain ⟨v1, q1, hv1, hq1, r1⟩ := relB x tx hx'
    refine ⟨v1, q1, ?_, ?_, r1⟩
    · rw [local?_restore]
      have ids : s.cellId? x = st.cellId? x := by
        have := cellId?_bindLocal (st := st) id v x
        rw [if_neg same] at this
        rw [← this]
        simp [State.cellId?, locals]
      simp only [State.local?, ids] at hv1
      exact hv1
    · rw [he, Env.get?_cons'', if_neg same] at hq1
      exact hq1

end

/-- **What Core's `id = e` did**: it evaluated `e`, then wrote the cell of
`id`'s newest binding. -/
theorem assignLocal_inv {P : Core.Program} {k : Nat} {st st' : State} {id : Nat} {e : Core.Expr} {v : Value}
    (h : evalExpr k P st (.assign .set (.local id) e) = .done v st') :
    ∃ j c w s1, k = j + 1 ∧ st.cellId? id = some c ∧ evalExpr j P st e = .done w s1 ∧ v = .unit ∧
      (s1.cellEntry? c).isSome ∧
      (st' = s1.assigned c w ∨ Semantics.syncI32ViewsToHeap (s1.assigned c w) = .ok st') := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    cases j with
    | zero => simp [Semantics.evalPlace] at h
    | succ i =>
      simp only [Semantics.evalPlace] at h
      cases hc : st.cellId? id with
      | none => simp [hc] at h
      | some c =>
        cases he : st.cellEntry? c with
        | none => simp [hc, he] at h
        | some entry =>
          simp only [hc, he] at h
          cases hrun : evalExpr (i + 1) P st e with
          | done w s1 =>
            simp only [hrun, Semantics.evalAssignValue, Semantics.assignOpBinary?,
              Semantics.writeResolvedPlaceNative, Semantics.writeResolvedPlace, Semantics.State.assignCell] at h
            by_cases hs : (s1.cellEntry? c).isSome = true
            · rw [if_pos hs] at h
              simp only at h
              refine ⟨i + 1, c, w, s1, rfl, rfl, hrun, ?_⟩
              by_cases hv : ({ root := c, projections := [], value := entry.value } : Semantics.ResolvedPlace).viewFreeRootWrite w = true
              · rw [if_pos hv] at h
                simp only [Semantics.Outcome.done.injEq] at h
                exact ⟨h.1.symm, hs, .inl h.2.symm⟩
              · rw [if_neg hv] at h
                cases hsync : Semantics.syncI32ViewsToHeap (s1.assigned c w) with
                | ok coherent =>
                  rw [hsync] at h
                  simp only [Semantics.Outcome.done.injEq] at h
                  obtain ⟨h1, rfl⟩ := h
                  exact ⟨h1.symm, hs, .inr rfl⟩
                | error reason => rw [hsync] at h; simp at h
            · rw [if_neg hs] at h
              simp at h
          | trapped r s => simp [hrun] at h
          | exited code s => simp [hrun] at h
          | outOfFuel => simp [hrun] at h

/-- **Where Core's `id = e` traps**, within the heap bound, for a bound `id`
whose cell outlives `e` with views gone: in `e`. -/
theorem assignLocal_trap {P : Core.Program} {k : Nat} {st st' : State} {id : Nat} {e : Core.Expr}
    {r : Lanius.Trap} (h : evalExpr k P st (.assign .set (.local id) e) = .trapped r st')
    (bound : st'.heap.nextAddress ≤ 2 ^ 64) {v : Value} (hv : st.local? id = some v)
    (views : ∀ j w s1, k = j + 1 → evalExpr j P st e = .done w s1 → s1.heap.nextAddress ≤ 2 ^ 64 →
      s1.i32ArrayViews = [])
    (cell : ∀ j w s1 c, k = j + 1 → evalExpr j P st e = .done w s1 → st.cellId? id = some c →
      s1.heap.nextAddress ≤ 2 ^ 64 → (s1.cellEntry? c).isSome) :
    ∃ j, k = j + 1 ∧ evalExpr j P st e = .trapped r st' := by
  cases k with
  | zero => simp [evalExpr] at h
  | succ j =>
    simp only [evalExpr] at h
    cases j with
    | zero => simp [Semantics.evalPlace] at h
    | succ i =>
      simp only [Semantics.evalPlace] at h
      cases hc : st.cellId? id with
      | none => simp [State.local?, hc] at hv
      | some c =>
        cases he : st.cellEntry? c with
        | none => simp [State.local?, State.cell?, hc, he] at hv
        | some entry =>
          simp only [hc, he] at h
          cases hrun : evalExpr (i + 1) P st e with
          | done w s1 =>
            simp only [hrun, Semantics.evalAssignValue, Semantics.assignOpBinary?,
              Semantics.writeResolvedPlaceNative, Semantics.writeResolvedPlace, Semantics.State.assignCell] at h
            by_cases hs : (s1.cellEntry? c).isSome = true
            · rw [if_pos hs] at h
              simp only at h
              by_cases hw : ({ root := c, projections := [], value := entry.value } : Semantics.ResolvedPlace).viewFreeRootWrite w = true
              · rw [if_pos hw] at h
                simp at h
              · rw [if_neg hw] at h
                split at h
                · simp at h
                · rename_i reason hsync
                  simp only [Semantics.Outcome.trapped.injEq] at h
                  obtain ⟨-, rfl⟩ := h
                  have vs := views (i + 1) w s1 rfl hrun bound
                  simp [Semantics.syncI32ViewsToHeap, Semantics.syncI32ViewsToHeapFrom, vs] at hsync
            · rw [if_neg hs] at h
              simp only [Semantics.Outcome.trapped.injEq] at h
              obtain ⟨-, rfl⟩ := h
              exact absurd (cell (i + 1) w s1 c rfl hrun hc bound) hs
          | trapped r' s =>
            simp only [hrun] at h
            exact ⟨i + 1, rfl, hrun.trans h⟩
          | exited code s => simp [hrun] at h
          | outOfFuel => simp [hrun] at h

/-- With views gone, an assignment's state is the written one. -/
theorem assigned_eq {s st' : State} (views : s.i32ArrayViews = [])
    (h : st' = s ∨ Semantics.syncI32ViewsToHeap s = .ok st') : st' = s := by
  rcases h with h | h
  · exact h
  · simp only [Semantics.syncI32ViewsToHeap, views, Semantics.syncI32ViewsToHeapFrom, Except.ok.injEq] at h
    exact h.symm

/-! ## A callee's frame -/

theorem CellsKeep.prefix {vis : Nat → Prop} :
    ∀ {A B cs : List Semantics.Cell}, CellsKeep vis (A ++ B) cs → (∀ c ∈ A, ¬ vis c.id) → A <+: cs
  | [], _, _, _, _ => List.nil_prefix
  | _ :: _, _, [], h, _ => h.elim
  | a :: A, B, c :: cs, ⟨_, k, r⟩, nv => by
    have e := k (nv a List.mem_cons_self)
    subst e
    exact List.cons_prefix_cons.mpr ⟨rfl, CellsKeep.prefix r fun c m => nv c (List.mem_cons_of_mem _ m)⟩

theorem visible_bindLocals : ∀ (bs : List (Nat × Value)) {st : State} {x : Nat},
    (st.bindLocals bs).Visible x → st.Visible x ∨ st.nextCell ≤ x
  | [], _, _, h => .inl h
  | b :: bs, st, x, h => by
    rw [bindLocals_cons] at h
    rcases visible_bindLocals bs h with h | h
    · obtain ⟨y, hy⟩ := h
      rw [cellId?_bindLocal] at hy
      split at hy
      · simp only [Option.some.injEq] at hy
        exact .inr (Nat.le_of_eq hy)
      · exact .inl ⟨y, hy⟩
    · exact .inr (Nat.le_of_succ_le h)

/-- A callee's body keeps its caller's cells: its visible locals are its own. -/
theorem Frame.callee {st s : State} (inv : Inv st) (bs : List (Nat × Value))
    (fr : Frame (({ st with locals := [] } : State).bindLocals bs) s) : st.cells <+: s.cells := by
  have pre : st.cells <+: (({ st with locals := [] } : State).bindLocals bs).cells :=
    ((Step.clear st).trans (Step.bindLocals bs _)).cells
  obtain ⟨B, hB⟩ := pre
  have cells := fr.cells
  rw [← hB] at cells
  refine CellsKeep.prefix cells fun c m vis => ?_
  rcases visible_bindLocals bs vis with ⟨y, hy⟩ | le
  · simp [State.cellId?] at hy
  · exact absurd (inv.fresh c m) (Nat.not_lt.mpr le)

end Lanius.Faithful
