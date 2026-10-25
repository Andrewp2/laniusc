import Lanius.Faithful.Sim.Inv
import Lanius.Faithful.Sim.Rel

/-! # Core states the pure subset runs through

`Inv`: no i32 views, cell ids below `nextCell`, heap blocks below the cursor
with distinct bases. `Step st st'`: the pure subset only appends cells and
keeps every heap read (it allocates, and writes only fresh blocks). `EnvRel`:
each local the types know has a Core value that means its pure value. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State HeapReads restoreLocals)
open Lanius.Memory (HeapBlocksBelowNext HeapBlockBasesUnique)

structure Inv (st : State) : Prop where
  views : st.i32ArrayViews = []
  fresh : ∀ c ∈ st.cells, c.id < st.nextCell
  below : HeapBlocksBelowNext st.heap
  unique : HeapBlockBasesUnique st.heap

structure Step (st st' : State) : Prop where
  cells : st.cells <+: st'.cells
  reads : HeapReads st.heap st'.heap

theorem Step.refl (st : State) : Step st st := ⟨List.prefix_refl _, HeapReads.refl _⟩

theorem Step.trans {a b c : State} (first : Step a b) (second : Step b c) : Step a c :=
  ⟨first.cells.trans second.cells, first.reads.trans second.reads⟩

theorem Step.restore {st st' : State} (s : State) (step : Step st st') : Step st (restoreLocals s st') :=
  ⟨step.cells, step.reads⟩

theorem Step.restore_left {st st' : State} (s : State) (step : Step st st') : Step (restoreLocals s st) st' :=
  ⟨step.cells, step.reads⟩

theorem Inv.restore {st : State} (s : State) (inv : Inv st) : Inv (restoreLocals s st) :=
  ⟨inv.views, inv.fresh, inv.below, inv.unique⟩

theorem Inv.clear {st : State} (inv : Inv st) : Inv { st with locals := [] } :=
  ⟨inv.views, inv.fresh, inv.below, inv.unique⟩

theorem Step.clear (st : State) : Step st { st with locals := [] } := ⟨List.prefix_refl _, HeapReads.refl _⟩

theorem Step.clear_left {st st' : State} (step : Step { st with locals := [] } st') : Step st st' :=
  ⟨step.cells, step.reads⟩

theorem Inv.bindLocal {st : State} (inv : Inv st) (id : Nat) (v : Value) : Inv (st.bindLocal id v) := by
  refine ⟨inv.views, ?_, inv.below, inv.unique⟩
  intro c mem
  show c.id < st.nextCell + 1
  have mem' : c ∈ st.cells ++ [{ id := st.nextCell, value := some v }] := mem
  rcases List.mem_append.mp mem' with mem | mem
  · exact Nat.lt_succ_of_lt (inv.fresh c mem)
  · rw [List.mem_singleton] at mem
    subst mem
    exact Nat.lt_succ_self _

theorem Step.bindLocal (st : State) (id : Nat) (v : Value) : Step st (st.bindLocal id v) :=
  ⟨by simp [State.bindLocal, State.bindCell], HeapReads.refl _⟩

theorem bindLocals_cons (st : State) (b : Nat × Value) (bs : List (Nat × Value)) :
    st.bindLocals (b :: bs) = (st.bindLocal b.1 b.2).bindLocals bs := rfl

theorem Inv.bindLocals : ∀ (bs : List (Nat × Value)) {st : State}, Inv st → Inv (st.bindLocals bs)
  | [], _, inv => inv
  | b :: bs, st, inv => by rw [bindLocals_cons]; exact Inv.bindLocals bs (inv.bindLocal b.1 b.2)

theorem Step.bindLocals : ∀ (bs : List (Nat × Value)) (st : State), Step st (st.bindLocals bs)
  | [], st => Step.refl st
  | b :: bs, st => by
    rw [bindLocals_cons]
    exact (Step.bindLocal st b.1 b.2).trans (Step.bindLocals bs _)

/-! ## Locals -/

theorem cellEntry?_prefix {st st' : State} (pre : st.cells <+: st'.cells) {c : Nat} {e : Semantics.Cell}
    (found : st.cellEntry? c = some e) : st'.cellEntry? c = some e := by
  obtain ⟨extra, eq⟩ := pre
  simp only [State.cellEntry?] at found ⊢
  rw [← eq, List.find?_append, found, Option.some_or]

theorem cell?_prefix {st st' : State} (pre : st.cells <+: st'.cells) {c : Nat} {v : Value}
    (found : st.cell? c = some v) : st'.cell? c = some v := by
  unfold State.cell? at found ⊢
  cases he : st.cellEntry? c with
  | none => rw [he] at found; cases found
  | some e => rw [he] at found; rw [cellEntry?_prefix pre he]; exact found

theorem local?_step {st st' : State} (step : Step st st') (locals : st'.locals = st.locals) {id : Nat} {v : Value}
    (found : st.local? id = some v) : st'.local? id = some v := by
  unfold State.local? State.cellId? at found ⊢
  rw [locals]
  cases hc : (st.locals.find? fun binding => binding.1 == id) with
  | none => rw [hc] at found; cases found
  | some b => rw [hc] at found; exact cell?_prefix step.cells found

theorem local?_bindLocal_self {st : State} (inv : Inv st) (id : Nat) (v : Value) :
    (st.bindLocal id v).local? id = some v := by
  have none : st.cells.find? (fun cell => cell.id == st.nextCell) = none := by
    apply List.find?_eq_none.mpr
    intro c mem
    simp only [beq_iff_eq]
    exact Nat.ne_of_lt (inv.fresh c mem)
  simp [State.local?, State.cellId?, State.cell?, State.cellEntry?, State.bindLocal, State.bindCell,
    List.find?_append, none]

theorem local?_bindLocal_other {st : State} {id x : Nat} (ne : id ≠ x) (v : Value) {w : Value}
    (found : st.local? x = some w) : (st.bindLocal id v).local? x = some w := by
  have pre : st.cells <+: (st.bindLocal id v).cells := (Step.bindLocal st id v).cells
  have hb : ((id, st.nextCell).1 == x) = false := by simpa using ne
  unfold State.local? State.cellId? at found ⊢
  show (Option.map Prod.snd (List.find? (fun binding => binding.1 == x) ((id, st.nextCell) :: st.locals))).bind
    (st.bindLocal id v).cell? = some w
  simp only [List.find?_cons, hb]
  cases hc : (st.locals.find? fun binding => binding.1 == x) with
  | none => rw [hc] at found; cases found
  | some b => rw [hc] at found; exact cell?_prefix pre found

/-! ## Local values -/

section
variable (P : Core.Program) (boxes : Boxes)

/-- Each local `tenv` types has a Core value meaning its pure value. -/
def EnvRel (heap : Memory.Heap) (tenv : TEnv) (env : Env) (st : State) : Prop :=
  ∀ x t, tenv.get? x = some t → ∃ v p, st.local? x = some v ∧ env.get? x = some p ∧ VRel P boxes heap t v p

variable {P boxes}

theorem EnvRel.step {tenv : TEnv} {env : Env} {st st' : State} (rel : EnvRel P boxes st.heap tenv env st)
    (step : Step st st') (locals : st'.locals = st.locals) : EnvRel P boxes st'.heap tenv env st' := by
  intro x t found
  obtain ⟨v, p, hv, hp, r⟩ := rel x t found
  exact ⟨v, p, local?_step step locals hv, hp, r.mono step.reads⟩

theorem EnvRel.bind {heap : Memory.Heap} {tenv : TEnv} {env : Env} {st : State} (inv : Inv st)
    (rel : EnvRel P boxes heap tenv env st) {id : Nat} {t : SrcType} {v p : Value} (r : VRel P boxes heap t v p) :
    EnvRel P boxes heap ((id, t) :: tenv) ((id, p) :: env) (st.bindLocal id v) := by
  intro x tx found
  rw [TEnv.get?_cons] at found
  by_cases same : id = x
  · subst same
    simp only [if_true, Option.some.injEq] at found
    subst found
    exact ⟨v, p, local?_bindLocal_self inv id v, by simp [Env.get?_cons'], r⟩
  · simp only [same, if_false] at found
    obtain ⟨w, q, hw, hq, rq⟩ := rel x tx found
    exact ⟨w, q, local?_bindLocal_other same v hw, by simp [Env.get?_cons', same, hq], rq⟩

theorem EnvRel.bindAll {heap : Memory.Heap} :
    ∀ (bs : List Nat) {ts : List SrcType} {vs ps : List Value} {tenv : TEnv} {env : Env} {st : State},
      Inv st → EnvRel P boxes heap tenv env st → VRels P boxes heap ts vs ps → bs.length = ts.length →
      EnvRel P boxes heap (tenv.bindAll (bs.zip ts)) (env.bindAll (bs.zip ps)) (st.bindLocals (bs.zip vs))
  | [], _, _, _, _, _, _, _, rel, _, _ => rel
  | b :: bs, _, _, _, _, _, st, inv, rel, .cons r rs, len => by
    simp only [List.length_cons, Nat.add_right_cancel_iff] at len
    simp only [List.zip_cons_cons]
    rw [bindLocals_cons]
    exact EnvRel.bindAll bs (inv.bindLocal b _) (rel.bind inv r) rs len
  | _ :: _, _, _, _, _, _, _, _, _, .nil, len => by simp at len

theorem paramBindings_eq : ∀ (params : List SrcParam) (values : List Value),
    paramBindings params values = (params.map SrcParam.id).zip values
  | [], _ => by simp [paramBindings]
  | _ :: _, [] => by simp [paramBindings]
  | p :: ps, v :: vs => by
    simp only [paramBindings, List.map_cons, List.zip_cons_cons] at *
    rw [← paramBindings_eq ps vs]
    rfl

theorem paramTEnv_eq (params : List SrcParam) :
    paramTEnv params = TEnv.bindAll [] ((params.map SrcParam.id).zip (params.map SrcParam.ty)) := by
  simp only [paramTEnv]
  congr 1
  induction params with
  | nil => rfl
  | cons p ps ih => simp [ih]

/-- A callee's parameters, bound to argument values that mean `ps`. -/
theorem EnvRel.entry {heap : Memory.Heap} {params : List SrcParam} {values ps : List Value} {st : State}
    (inv : Inv st) (args : VRels P boxes heap (params.map SrcParam.ty) values ps) :
    EnvRel P boxes heap (paramTEnv params) (paramEnv params ps)
      (({ st with locals := [] } : State).bindLocals (paramBindings params values)) := by
  rw [paramTEnv_eq, paramBindings_eq]
  simp only [paramEnv, paramBindings_eq]
  have empty : EnvRel P boxes heap [] [] ({ st with locals := [] } : State) := by
    intro x t found
    simp [TEnv.get?] at found
  exact EnvRel.bindAll _ inv.clear empty args (by simp)

end

end Lanius.Faithful
