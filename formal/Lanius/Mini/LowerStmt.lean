import Lanius.Mini.CompileCorrect
import Lanius.Mini.HeapCorr
import Lanius.Mini.ElementLayout
import Lanius.Mini.Guard

/-! Statements and calls: a lowered subset statement that Core runs to
completion has a mini derivation with the same result.

Core keeps a function's locals in cells that it allocates above every cell of
its callers. `frame` maps a mini slot to the cell of the binding that owns it;
`Keeps base` says the cells below `base` (the callers') are untouched. -/

namespace Lanius.Mini

open Lanius.Core (Value)
open Lanius.Semantics (State Cell Completion evalExpr evalExprs execStmt restoreLocals)

/-! ## Core cells -/

/-- `omega` through `CellId`, which it does not unfold. -/
macro "cell_omega" : tactic =>
  `(tactic| (try simp only [beq_iff_eq, beq_eq_false_iff_ne, ne_eq, Lanius.CellId] at *) <;> omega)

/-- Every cell id is below the next one to be allocated, and no array views
exist (so a struct write has nothing to synchronize). -/
def _root_.Lanius.Semantics.State.Fresh (st : State) : Prop :=
  (∀ c ∈ st.cells, c.id < st.nextCell) ∧ st.i32ArrayViews = []

/-- `st'` grew from `st` and left the cells below `base` alone. -/
structure Keeps (base : Nat) (st st' : State) : Prop where
  cells : ∀ c < base, st'.cellEntry? c = st.cellEntry? c
  next : st.nextCell ≤ st'.nextCell

theorem Keeps.refl (base : Nat) (st : State) : Keeps base st st := ⟨fun _ _ => rfl, Nat.le_refl _⟩

theorem Keeps.trans {base : Nat} {a b c : State} (first : Keeps base a b) (second : Keeps base b c) :
    Keeps base a c :=
  ⟨fun cell below => (second.cells cell below).trans (first.cells cell below),
    Nat.le_trans first.next second.next⟩

theorem Keeps.lower {base low : Nat} {st st' : State} (keeps : Keeps base st st') (le : low ≤ base) :
    Keeps low st st' :=
  ⟨fun c below => keeps.cells c (Nat.lt_of_lt_of_le below le), keeps.next⟩

theorem cellEntry_mem {st : State} {c : Nat} {e : Cell} (found : st.cellEntry? c = some e) :
    e ∈ st.cells ∧ e.id = c := by
  simp only [State.cellEntry?] at found
  exact ⟨List.mem_of_find?_eq_some found, by simpa using List.find?_some found⟩

theorem _root_.Lanius.Semantics.State.Fresh.below {st : State} (fresh : st.Fresh) {c : Nat} {e : Cell}
    (found : st.cellEntry? c = some e) : c < st.nextCell := by
  obtain ⟨mem, rfl⟩ := cellEntry_mem found
  exact fresh.1 e mem

theorem bindLocal_entry {st : State} {c : Nat} (below : c < st.nextCell) (id : Nat) (v : Value) :
    (st.bindLocal id v).cellEntry? c = st.cellEntry? c := by
  simp only [State.cellEntry?, State.bindLocal, State.bindCell, List.find?_append]
  cases st.cells.find? (fun cell => cell.id == c) with
  | some e => rfl
  | none =>
    have : (st.nextCell == c) = false := by cell_omega
    simp [List.find?, this]

theorem bindLocal_self {st : State} (fresh : st.Fresh) (id : Nat) (v : Value) :
    (st.bindLocal id v).cellEntry? st.nextCell = some ⟨st.nextCell, some v⟩ := by
  simp only [State.cellEntry?, State.bindLocal, State.bindCell, List.find?_append]
  have : st.cells.find? (fun cell => cell.id == st.nextCell) = none := by
    rw [List.find?_eq_none]
    intro cell mem
    have := fresh.1 cell mem
    simp; cell_omega
  simp [this, List.find?]

theorem bindLocal_fresh {st : State} (fresh : st.Fresh) (id : Nat) (v : Value) :
    (st.bindLocal id v).Fresh := by
  refine ⟨fun cell mem => ?_, fresh.2⟩
  simp only [State.bindLocal, State.bindCell, List.mem_append, List.mem_singleton] at mem ⊢
  rcases mem with old | rfl
  · exact Nat.lt_succ_of_lt (fresh.1 cell old)
  · exact Nat.lt_succ_self _

theorem bindLocal_keeps {st : State} {base : Nat} (le : base ≤ st.nextCell) (id : Nat) (v : Value) :
    Keeps base st (st.bindLocal id v) :=
  ⟨fun _ below => bindLocal_entry (Nat.lt_of_lt_of_le below le) id v,
    Nat.le_succ _⟩

theorem find_replaceCell (cells : List Cell) (target c : Nat) (v : Value) :
    (Semantics.replaceCell cells target v).find? (fun cell => cell.id == c) =
      if c = target then
        (cells.find? (fun cell => cell.id == c)).map fun cell => { cell with value := some v }
      else cells.find? (fun cell => cell.id == c) := by
  induction cells with
  | nil => simp [Semantics.replaceCell]
  | cons head rest ih =>
    simp only [Semantics.replaceCell]
    by_cases ht : head.id = target
    · rw [if_pos (by simp [ht])]
      by_cases hc : c = target
      · subst hc
        rw [List.find?_cons_of_pos (by simp [ht]), List.find?_cons_of_pos (by simp [ht])]
        simp
      · rw [List.find?_cons_of_neg (by simp; cell_omega), List.find?_cons_of_neg (by simp; cell_omega), ih]
    · rw [if_neg (by simp [ht])]
      by_cases hh : head.id = c
      · rw [List.find?_cons_of_pos (by simp [hh]), List.find?_cons_of_pos (by simp [hh])]
        have : c ≠ target := by cell_omega
        simp [this]
      · rw [List.find?_cons_of_neg (by simp [hh]), List.find?_cons_of_neg (by simp [hh]), ih]

theorem assignCell_some {st : State} {c : Nat} {e : Cell} (found : st.cellEntry? c = some e) (v : Value) :
    st.assignCell c v = some { st with cells := Semantics.replaceCell st.cells c v } := by
  simp [State.assignCell, found]

theorem assigned_entry (st : State) (target c : Nat) (v : Value) :
    ({ st with cells := Semantics.replaceCell st.cells target v } : State).cellEntry? c =
      if c = target then (st.cellEntry? c).map fun cell => { cell with value := some v }
      else st.cellEntry? c := by
  simp only [State.cellEntry?, find_replaceCell]

theorem mem_replaceCell {cells : List Cell} {target : Nat} {v : Value} {cell : Cell}
    (mem : cell ∈ Semantics.replaceCell cells target v) : ∃ old ∈ cells, old.id = cell.id := by
  induction cells with
  | nil => simp [Semantics.replaceCell] at mem
  | cons head rest ih =>
    simp only [Semantics.replaceCell] at mem
    split at mem <;> simp only [List.mem_cons] at mem <;> rcases mem with rfl | mem
    · exact ⟨head, List.mem_cons_self .., rfl⟩
    · obtain ⟨old, oldMem, eq⟩ := ih mem; exact ⟨old, List.mem_cons_of_mem _ oldMem, eq⟩
    · exact ⟨_, List.mem_cons_self .., rfl⟩
    · obtain ⟨old, oldMem, eq⟩ := ih mem; exact ⟨old, List.mem_cons_of_mem _ oldMem, eq⟩

theorem assigned_fresh {st : State} (fresh : st.Fresh) (target : Nat) (v : Value) :
    ({ st with cells := Semantics.replaceCell st.cells target v } : State).Fresh := by
  refine ⟨fun cell mem => ?_, fresh.2⟩
  obtain ⟨old, oldMem, eq⟩ := mem_replaceCell mem
  rw [← eq]
  exact fresh.1 old oldMem

/-! ## Frames -/

def upd (frame : Nat → Nat) (slot cell : Nat) : Nat → Nat :=
  fun other => if other = slot then cell else frame other

/-- Each binding's slots are below `next` and are not shared with another
binding, its cell is at or above `base`, and no two bindings share a cell. -/
structure Layout (scope : List Binding) (frame : Nat → Nat) (base next : Nat) : Prop where
  slots : ∀ b ∈ scope, b.slot + b.ty.size ≤ next
  sized : ∀ b ∈ scope, 0 < b.ty.size
  above : ∀ b ∈ scope, base ≤ frame b.slot
  inj : ∀ a ∈ scope, ∀ b ∈ scope, frame a.slot = frame b.slot → a = b
  apart : ∀ a ∈ scope, ∀ b ∈ scope, a ≠ b →
    a.slot + a.ty.size ≤ b.slot ∨ b.slot + b.ty.size ≤ a.slot

/-- `env'` agrees with `env` on every slot of the scope. -/
def ScopeAgree (scope : List Binding) (env env' : Env) : Prop :=
  ∀ b ∈ scope, ∀ i < b.ty.size, env' (b.slot + i) = env (b.slot + i)

theorem Layout.agree {scope frame base next} (fr : Layout scope frame base next) {env env' : Env}
    (same : ∀ j < next, env' j = env j) : ScopeAgree scope env env' :=
  fun b mem i below => same _ (by have := fr.slots b mem; omega)

theorem Corr.below {scope frame st env} (corr : Corr scope frame st env) (fresh : st.Fresh) :
    ∀ b ∈ scope, frame b.slot < st.nextCell := by
  intro b mem
  obtain ⟨v, entry, _⟩ := corr.values b mem
  exact fresh.below entry

theorem upd_scope {scope : List Binding} {frame : Nat → Nat} {base next : Nat}
    (fr : Layout scope frame base next) (cell : Nat) :
    ∀ b ∈ scope, upd frame next cell b.slot = frame b.slot := by
  intro b mem
  have := fr.slots b mem
  have := fr.sized b mem
  simp only [upd]
  rw [if_neg (by omega)]

theorem Layout.push {scope frame base next} (fr : Layout scope frame base next) {cell : Nat}
    (below : ∀ b ∈ scope, frame b.slot < cell) (le : base ≤ cell) (id : Nat) {ty : SrcType}
    (sized : 0 < ty.size) :
    Layout (⟨id, next, ty⟩ :: scope) (upd frame next cell) base (next + ty.size) := by
  have same := upd_scope fr cell
  have self : upd frame next cell next = cell := by simp [upd]
  refine ⟨?_, ?_, ?_, ?_, ?_⟩
  · intro b mem
    simp only [List.mem_cons] at mem
    rcases mem with rfl | mem
    · exact Nat.le_refl _
    · have := fr.slots b mem; omega
  · intro b mem
    simp only [List.mem_cons] at mem
    rcases mem with rfl | mem
    · exact sized
    · exact fr.sized b mem
  · intro b mem
    simp only [List.mem_cons] at mem
    rcases mem with rfl | mem
    · simpa [self] using le
    · rw [same b mem]; exact fr.above b mem
  · intro a amem b bmem eq
    simp only [List.mem_cons] at amem bmem
    rcases amem with rfl | amem <;> rcases bmem with rfl | bmem
    · rfl
    · rw [self, same b bmem] at eq
      have := below b bmem
      omega
    · rw [self, same a amem] at eq
      have := below a amem
      omega
    · rw [same a amem, same b bmem] at eq
      exact fr.inj a amem b bmem eq
  · intro a amem b bmem ne
    simp only [List.mem_cons] at amem bmem
    rcases amem with rfl | amem <;> rcases bmem with rfl | bmem
    · exact absurd rfl ne
    · exact .inr (fr.slots b bmem)
    · exact .inl (fr.slots a amem)
    · exact fr.apart a amem b bmem ne

theorem Layout.mono {scope frame base next} (fr : Layout scope frame base next) {next' : Nat}
    (le : next ≤ next') : Layout scope frame base next' :=
  ⟨fun b mem => Nat.le_trans (fr.slots b mem) le, fr.sized, fr.above, fr.inj, fr.apart⟩

theorem Corr.env_congr {scope frame st env env'} (corr : Corr scope frame st env)
    (agree : ScopeAgree scope env env') : Corr scope frame st env' :=
  ⟨corr.locals, fun b mem => by
    obtain ⟨v, entry, holds⟩ := corr.values b mem
    exact ⟨v, entry, holds.congr (agree b mem)⟩⟩

theorem Corr.cells_congr {scope frame st env} {st' : State} (corr : Corr scope frame st env)
    (locals : st'.locals = st.locals)
    (cells : ∀ b ∈ scope, st'.cellEntry? (frame b.slot) = st.cellEntry? (frame b.slot)) :
    Corr scope frame st' env :=
  ⟨locals.trans corr.locals, fun b mem => by rw [cells b mem]; exact corr.values b mem⟩

theorem Corr.keeps {scope frame st env} {st' : State} (corr : Corr scope frame st env)
    (fresh : st.Fresh) (keeps : Keeps st.nextCell st st') (locals : st'.locals = st.locals) :
    Corr scope frame st' env :=
  corr.cells_congr locals fun b mem => keeps.cells _ (corr.below fresh b mem)

theorem Corr.push {scope frame st env base next} (corr : Corr scope frame st env)
    (fr : Layout scope frame base next) (fresh : st.Fresh) {env' : Env}
    (agree : ScopeAgree scope env env') {id : Nat} {ty : SrcType} {v : Value}
    (holds : ty.HoldsAt v env' next) :
    Corr (⟨id, next, ty⟩ :: scope) (upd frame next st.nextCell) (st.bindLocal id v) env' := by
  have same := upd_scope fr st.nextCell
  refine ⟨?_, ?_⟩
  · simp only [State.bindLocal, State.bindCell, List.map_cons, corr.locals, upd, if_pos]
    congr 1
    apply List.map_congr_left
    intro b mem
    rw [← upd, same b mem]
  · intro b mem
    simp only [List.mem_cons] at mem
    rcases mem with rfl | mem
    · refine ⟨v, ?_, holds⟩
      simp only [upd, if_pos]
      exact bindLocal_self fresh id v
    · obtain ⟨w, entry, holdsb⟩ := corr.values b mem
      refine ⟨w, ?_, holdsb.congr (agree b mem)⟩
      rw [same b mem, bindLocal_entry (corr.below fresh b mem)]
      exact entry

/-- Leaving a `let`: Core restores the outer locals and the cells stay. -/
theorem Corr.pop {scope frame base next id ty cell st env} {st' : State}
    (corr : Corr (⟨id, next, ty⟩ :: scope) (upd frame next cell) st env)
    (fr : Layout scope frame base next) (locals : st'.locals = scope.map fun b => (b.id, frame b.slot))
    (cells : st'.cells = st.cells) : Corr scope frame st' env := by
  have same := upd_scope fr cell
  refine ⟨locals, fun b mem => ?_⟩
  obtain ⟨w, entry, holds⟩ := corr.values b (List.mem_cons_of_mem _ mem)
  rw [same b mem] at entry
  refine ⟨w, ?_, holds⟩
  simpa [State.cellEntry?, cells] using entry

/-! ## Mini derivations -/

theorem Exec.mono {prog : Program} {d : Nat} {env : Env} {heap : Heap} {s : Stmt} {out : Outcome}
    (exec : Exec prog d env heap s out) {d' : Nat} (le : d ≤ d') : Exec prog d' env heap s out := by
  induction exec with
  | skip => exact .skip
  | assign => exact .assign
  | seq _ _ ih1 ih2 => exact .seq (ih1 le) (ih2 le)
  | seqReturned _ ih => exact .seqReturned (ih le)
  | ifTrue c _ ih => exact .ifTrue c (ih le)
  | ifFalse c _ ih => exact .ifFalse c (ih le)
  | loopDone c => exact .loopDone c
  | loopNext c _ _ ih1 ih2 => exact .loopNext c (ih1 le) (ih2 le)
  | loopReturned c _ ih => exact .loopReturned c (ih le)
  | seqBroke _ ih => exact .seqBroke (ih le)
  | seqContinued _ ih => exact .seqContinued (ih le)
  | loopBroke c _ ih => exact .loopBroke c (ih le)
  | loopContinued c _ _ ih1 ih2 => exact .loopContinued c (ih1 le) (ih2 le)
  | brk => exact .brk
  | cont => exact .cont
  | call found arity counted inner body _ => exact .call found arity counted (Nat.lt_of_lt_of_le inner le) body
  | ret => exact .ret
  | alloc room => exact .alloc room
  | loadByte inside => exact .loadByte inside
  | storeByte inside => exact .storeByte inside
  | loadWord inside => exact .loadWord inside
  | storeWord inside => exact .storeWord inside
  | divide defined => exact .divide defined
  | sys ran => exact .sys ran

/-! ## Programs -/

theorem sigs_get (funcs : List SrcFunc) (i : Nat) :
    (sigs funcs)[i]? = (funcs[i]?).map fun f => ({ params := paramTypes f.params, ret := f.ret } : Sig) := by
  induction funcs generalizing i with
  | nil => simp [sigs]
  | cons head rest ih => cases i <;> simp [sigs, ih]

/-- A callee with a signature is one of the program's functions. -/
theorem sigs_inside {funcs : List SrcFunc} {i : Nat} {s : Sig} (found : (sigs funcs)[i]? = some s) :
    i < funcs.length := by
  rw [sigs_get] at found
  cases f : funcs[i]? with
  | none => simp [f] at found
  | some _ => exact (List.getElem?_eq_some_iff.mp f).1

theorem lowerCall_inside {funcs : List SrcFunc} {scope : List Binding} {callee : Nat} {args : List SrcExpr}
    {ty : SrcType} {es : List Expr} (ok : lowerCall (sigs funcs) scope callee args ty = some es) :
    callee < funcs.length := by
  simp only [lowerCall] at ok
  split at ok
  · simp at ok
  · rename_i found
    exact sigs_inside found

theorem lowerFuncs_get {sg : List Sig} {ds : SrcDecls} {funcs : List SrcFunc} {lowered : List Func}
    (ok : lowerFuncs sg ds funcs = some lowered) {i : Nat} {f : SrcFunc} (found : funcs[i]? = some f) :
    ∃ g, lowered[i]? = some g ∧ lowerFunc sg ds f = some g := by
  induction funcs generalizing lowered i with
  | nil => simp at found
  | cons head rest ih =>
    simp only [lowerFuncs, lowerFuncCons] at ok
    split at ok
    · simp at ok
    rename_i g headOk
    split at ok
    · simp at ok
    rename_i gs restOk
    simp only [Option.some.injEq] at ok
    subst ok
    cases i with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst found
      exact ⟨g, rfl, headOk⟩
    | succ i =>
      simp only [List.getElem?_cons_succ] at found ⊢
      exact ih restOk found

theorem lowerFunc_some {sg : List Sig} {ds : SrcDecls} {f : SrcFunc} {g : Func} (ok : lowerFunc sg ds f = some g) :
    g.params = paramsSize f.params ∧ 0 < f.ret.size ∧ paramsValid f.params = true ∧ f.body.breaksOut = false ∧
      ∃ b, f.body.lower sg ds f.ret (paramScope f.params 0 []) (paramsSize f.params) = some b ∧
        unitTail f.ret (some b) = some g.body := by
  simp only [lowerFunc] at ok
  split at ok
  · rename_i checks
    simp only [Bool.and_eq_true, decide_eq_true_eq] at checks
    simp only [lowerBody] at ok
    split at ok
    · simp at ok
    rename_i body bodyOk
    simp only [Option.some.injEq] at ok
    subst ok
    simp only [unitTail] at bodyOk
    split at bodyOk
    · split at bodyOk
      · simp at bodyOk
      rename_i b lowered
      exact ⟨rfl, checks.1.1, checks.1.2, by simpa using checks.2, b, lowered, by simp only [unitTail, bodyOk, ‹f.ret.isUnit = true›, if_true]⟩
    · exact ⟨rfl, checks.1.1, checks.1.2, by simpa using checks.2, body, bodyOk, by simp only [unitTail, if_neg (by assumption)]⟩
  · simp at ok

theorem paramTypes_length (params : List SrcParam) : (paramTypes params).length = params.length := by
  induction params with
  | nil => rfl
  | cons head rest ih => simp [paramTypes, ih]

theorem paramsSize_eq (params : List SrcParam) : paramsSize params = sizes (paramTypes params) := by
  induction params with
  | nil => rfl
  | cons head rest ih => simp [paramsSize, paramTypes, sizes, ih] at *

/-! ## Values -/

theorem FieldsHold.congr_all {tys vs env slot} (holds : FieldsHold tys vs env slot) {env' : Env}
    {slot' : Nat} (agree : ∀ i, env' (slot' + i) = env (slot + i)) : FieldsHold tys vs env' slot' :=
  holds.congr fun i _ => agree i

theorem evalAll_append (env : Env) (xs ys : List Expr) :
    Expr.evalAll env (xs ++ ys) = Expr.evalAll env xs ++ Expr.evalAll env ys := by
  induction xs with
  | nil => rfl
  | cons x rest ih => simp [Expr.evalAll, ih]

theorem evalAll_getElem? (env : Env) (xs : List Expr) (i : Nat) :
    (Expr.evalAll env xs)[i]? = xs[i]?.map (Expr.eval env) := by
  induction xs generalizing i with
  | nil => simp [Expr.evalAll]
  | cons x rest ih => cases i <;> simp [Expr.evalAll, ih]

theorem entry_evalAll (env : Env) (xs : List Expr) (i : Nat) (x : Expr) (found : xs[i]? = some x) :
    Func.entry (Expr.evalAll env xs) i = x.eval env := by
  simp [Func.entry, List.getD_eq_getElem?_getD, evalAll_getElem?, found]

theorem entry_append_left (bs cs : List (BitVec 64)) {i : Nat} (below : i < bs.length) :
    Func.entry (bs ++ cs) i = Func.entry bs i := by
  simp [Func.entry, List.getD_eq_getElem?_getD, List.getElem?_append_left below]

theorem entry_append_right (bs cs : List (BitVec 64)) (i : Nat) :
    Func.entry (bs ++ cs) (bs.length + i) = Func.entry cs i := by
  simp [Func.entry, List.getD_eq_getElem?_getD, List.getElem?_append_right]

/-- The mini expressions `xs`, one per slot, represent the Core value `v` of
type `ty`. -/
structure FlatValue (ty : SrcType) (v : Value) (env : Env) (xs : List Expr) : Prop where
  length : xs.length = ty.size
  holds : ty.HoldsAt v (Func.entry (Expr.evalAll env xs)) 0

theorem slotVars_length (slot count : Nat) : (slotVars slot count).length = count := by
  induction count generalizing slot with
  | zero => simp [slotVars]
  | succ count ih => rw [slotVars]; simp [ih]

theorem slotVars_get (slot count i : Nat) (below : i < count) :
    (slotVars slot count)[i]? = some (.var (slot + i)) := by
  induction count generalizing slot i with
  | zero => omega
  | succ count ih =>
    rw [slotVars]
    cases i with
    | zero => simp
    | succ i =>
      simp only [Nat.add_one_ne_zero, ↓reduceIte, Nat.add_sub_cancel, List.getElem?_cons_succ]
      rw [ih _ _ (by omega)]
      congr 2
      omega

theorem lowerAs_some {scope : List Binding} {e : SrcExpr} {ty : SrcType} {x : Expr}
    (ok : lowerAs scope e ty = some x) : ∃ t, e.lower scope = some t ∧ t.ty = ty ∧ t.expr = x := by
  simp only [lowerAs] at ok
  split at ok
  · simp at ok
  rename_i t lowered
  simp only [expectType] at ok
  split at ok
  · rename_i same
    simp only [Option.some.injEq] at ok
    exact ⟨t, lowered, SrcType.same_eq same, ok⟩
  · simp at ok

/-- A lowered expression of type `ty`, as `lower_sound` sees it. -/
theorem lowerAs_sound {scope frame st env} {prog : Core.Program} (corr : Corr scope frame st env)
    (target : prog.target = .x86_64) {e : SrcExpr} {ty : SrcType} {x : Expr}
    (ok : lowerAs scope e ty = some x) {fuel : Nat} {v : Value} {st' : State}
    (run : evalExpr fuel prog st e.toCore = .done v st') : st' = st ∧ ty.Holds v (x.eval env) := by
  obtain ⟨t, lowered, rfl, rfl⟩ := lowerAs_some ok
  exact e.lower_sound corr target lowered run

/-- Where a lowered value's slots come from. -/
inductive ValueShape (scope : List Binding) : List Expr → Prop where
  /-- a scalar expression over the scope -/
  | single {x : Expr} {t : Typed} {e : SrcExpr} : e.lower scope = some t → t.expr = x →
      ValueShape scope [x]
  /-- a copy of binding `b` -/
  | copy {b : Binding} : b ∈ scope → ValueShape scope (slotVars b.slot b.ty.size)
  /-- the slots `off ..< off + n` of binding `b` -/
  | part {b : Binding} {off n : Nat} : b ∈ scope → 0 < n → off + n ≤ b.ty.size →
      ValueShape scope (slotVars (b.slot + off) n)

theorem lowerValue_sound {scope frame st env} {prog : Core.Program} (corr : Corr scope frame st env)
    (target : prog.target = .x86_64) {e : SrcExpr} {ty : SrcType} {xs : List Expr}
    (ok : lowerValue scope e ty = some xs) {fuel : Nat} {v : Value} {st' : State}
    (run : evalExpr fuel prog st e.toCore = .done v st') :
    st' = st ∧ FlatValue ty v env xs ∧ ValueShape scope xs := by
  simp only [lowerValue] at ok
  split at ok
  · rename_i scalar
    simp only [lowerSingle] at ok
    split at ok
    · simp at ok
    rename_i x valueOk
    simp only [Option.some.injEq] at ok
    subst ok
    obtain ⟨rfl, holds⟩ := lowerAs_sound corr target valueOk run
    obtain ⟨t, lowered, _, rfl⟩ := lowerAs_some valueOk
    refine ⟨rfl, ⟨by simp [SrcType.size_scalar scalar], ?_⟩, .single lowered rfl⟩
    rw [SrcType.holdsAt_scalar scalar]
    simpa [Func.entry, Expr.evalAll] using holds
  · cases e with
    | «local» id =>
      simp only [lowerCopy, copyBinding] at ok
      split at ok
      · simp at ok
      rename_i b found
      split at ok
      · rename_i same
        simp only [Option.some.injEq] at ok
        subst ok
        have tyEq := SrcType.same_eq same
        subst tyEq
        cases fuel with
        | zero => simp [evalExpr] at run
        | succ fuel =>
          obtain ⟨w, eval, holds⟩ := corr.local found fuel prog
          simp only [SrcExpr.toCore, eval, Semantics.Outcome.done.injEq] at run
          obtain ⟨rfl, rfl⟩ := run
          refine ⟨rfl, ⟨slotVars_length _ _, holds.congr fun i below => ?_⟩, .copy (lookup_mem found).1⟩
          rw [Nat.zero_add, entry_evalAll env _ i _ (slotVars_get _ _ i below)]
          rfl
      · simp at ok
    | field id index =>
      simp only [lowerCopy, copyField] at ok
      split at ok
      · simp at ok
      rename_i b found
      simp only [copyFieldOf] at ok
      split at ok
      · simp at ok
      · simp at ok
      · simp at ok
      rename_i sid fields hty
      simp only [copyFieldAt] at ok
      split at ok
      · simp at ok
      rename_i f fieldFound
      split at ok
      · rename_i cond
        simp only [Bool.and_eq_true, decide_eq_true_eq] at cond
        obtain ⟨same, sized⟩ := cond
        simp only [Option.some.injEq] at ok
        subst ok
        have tyEq := SrcType.same_eq same
        subst tyEq
        cases fuel with
        | zero => simp [evalExpr] at run
        | succ fuel =>
          cases fuel with
          | zero => simp [SrcExpr.toCore, evalExpr] at run
          | succ fuel =>
            obtain ⟨w, eval, holds⟩ := corr.local found fuel prog
            rw [hty] at holds
            cases holds with
            | struct fieldsHold =>
              obtain ⟨fv, got, holdsField⟩ := fieldsHold.get fieldFound
              simp only [SrcExpr.toCore, evalExpr] at run
              simp only [evalExpr] at eval
              rw [eval] at run
              simp only [got, Semantics.Outcome.done.injEq] at run
              obtain ⟨rfl, rfl⟩ := run
              refine ⟨rfl, ⟨slotVars_length _ _, holdsField.congr fun i below => ?_⟩,
                .part (lookup_mem found).1 sized ?_⟩
              · rw [Nat.zero_add, entry_evalAll env _ i _ (slotVars_get _ _ i below)]
                rfl
              · rw [hty]
                simp only [SrcType.size]
                exact fieldOffset_lt fieldFound
      · simp at ok
      all_goals simp at ok
    | _ => simp [lowerCopy] at ok

theorem lowerArgs_sound {scope frame st env} {prog : Core.Program} (corr : Corr scope frame st env)
    (target : prog.target = .x86_64) :
    ∀ {args : List SrcExpr} {types : List SrcType} {es : List Expr} {fuel : Nat} {vs : List Value}
      {st' : State}, lowerArgs scope args types = some es →
      evalExprs fuel prog st (args.map SrcExpr.toCore) = .done vs st' →
      st' = st ∧ FieldsHold types vs (Func.entry (Expr.evalAll env es)) 0 ∧ es.length = sizes types ∧
        ∀ x ∈ es, ∃ xs, ValueShape scope xs ∧ x ∈ xs := by
  intro args
  induction args with
  | nil =>
    intro types es fuel vs st' ok run
    cases fuel with
    | zero => simp [evalExprs] at run
    | succ fuel =>
      cases types with
      | cons => simp [lowerArgs] at ok
      | nil =>
        simp only [lowerArgs, Option.some.injEq] at ok
        subst ok
        simp only [List.map_nil, evalExprs, Semantics.Outcome.done.injEq] at run
        obtain ⟨rfl, rfl⟩ := run
        exact ⟨rfl, .nil, rfl, by simp⟩
  | cons arg rest ih =>
    intro types es fuel vs st' ok run
    cases fuel with
    | zero => simp [evalExprs] at run
    | succ fuel =>
      cases types with
      | nil => simp [lowerArgs] at ok
      | cons ty more =>
        simp only [lowerArgs, lowerAppend] at ok
        split at ok
        · simp at ok
        rename_i xs argOk
        split at ok
        · simp at ok
        rename_i ys restOk
        simp only [Option.some.injEq] at ok
        subst ok
        simp only [List.map_cons, evalExprs] at run
        split at run
        · rename_i v mid argRun
          obtain ⟨rfl, flat, shape⟩ := lowerValue_sound corr target argOk argRun
          split at run
          · rename_i rvs fin restRun
            simp only [Semantics.Outcome.done.injEq] at run
            obtain ⟨rfl, rfl⟩ := run
            obtain ⟨rfl, restHolds, len, shapes⟩ := ih restOk restRun
            have lenAll := evalAll_length env xs
            refine ⟨rfl, .cons ?_ ?_, by simp [sizes, len, flat.length], ?_⟩
            · refine flat.holds.congr fun i below => ?_
              simp only [evalAll_append, Nat.zero_add]
              rw [entry_append_left _ _ (by rw [lenAll, flat.length]; exact below)]
            · refine restHolds.congr_all fun i => ?_
              simp only [evalAll_append, Nat.zero_add]
              rw [← flat.length, ← lenAll, entry_append_right]
            · intro x mem
              rcases List.mem_append.mp mem with here | there
              · exact ⟨xs, shape, here⟩
              · exact shapes x there
          all_goals simp at run
        all_goals simp at run

/-! ## Checks that pass -/

theorem lowerAs_guard {scope frame st env} {prog : Core.Program} (corr : Corr scope frame st env)
    (target : prog.target = .x86_64) {e : SrcExpr} {ty : SrcType} {x : Expr}
    (ok : lowerAs scope e ty = some x) {fuel : Nat} {v : Value} {st' : State}
    (run : evalExpr fuel prog st e.toCore = .done v st') : (e.guard scope).eval env = 1 := by
  obtain ⟨t, lowered, -, -⟩ := lowerAs_some ok
  exact e.guard_sound corr target lowered run

theorem lowerValue_guard {scope frame st env} {prog : Core.Program} (corr : Corr scope frame st env)
    (target : prog.target = .x86_64) {e : SrcExpr} {ty : SrcType} {xs : List Expr}
    (ok : lowerValue scope e ty = some xs) {fuel : Nat} {v : Value} {st' : State}
    (run : evalExpr fuel prog st e.toCore = .done v st') : (e.guard scope).eval env = 1 := by
  simp only [lowerValue] at ok
  split at ok
  · simp only [lowerSingle] at ok
    split at ok
    · simp at ok
    rename_i x valueOk
    exact lowerAs_guard corr target valueOk run
  · cases e <;> first | rfl | simp [lowerCopy] at ok

theorem lowerIndex_guard {scope frame st env} {prog : Core.Program} (corr : Corr scope frame st env)
    (target : prog.target = .x86_64) {e : SrcExpr} {x : Expr}
    (ok : lowerIndex scope e = some x) {fuel : Nat} {v : Value} {st' : State}
    (run : evalExpr fuel prog st e.toCore = .done v st') : (e.guard scope).eval env = 1 := by
  simp only [lowerIndex] at ok
  split at ok
  · simp at ok
  rename_i t lowered
  exact e.guard_sound corr target lowered run

theorem lowerArgs_guard {scope frame st env} {prog : Core.Program} (corr : Corr scope frame st env)
    (target : prog.target = .x86_64) :
    ∀ {args : List SrcExpr} {types : List SrcType} {es : List Expr} {fuel : Nat} {vs : List Value}
      {st' : State}, lowerArgs scope args types = some es →
      evalExprs fuel prog st (args.map SrcExpr.toCore) = .done vs st' → (guardAll scope args).eval env = 1 := by
  intro args
  induction args with
  | nil => intro _ _ _ _ _ _ _; rfl
  | cons arg rest ih =>
    intro types es fuel vs st' ok run
    cases fuel with
    | zero => simp [evalExprs] at run
    | succ fuel =>
      cases types with
      | nil => simp [lowerArgs] at ok
      | cons ty more =>
        simp only [lowerArgs, lowerAppend] at ok
        split at ok
        · simp at ok
        rename_i xs argOk
        split at ok
        · simp at ok
        rename_i ys restOk
        simp only [List.map_cons, evalExprs] at run
        split at run
        · rename_i v mid argRun
          have g := lowerValue_guard corr target argOk argRun
          obtain ⟨rfl, -, -⟩ := lowerValue_sound corr target argOk argRun
          split at run
          · rename_i rvs fin restRun
            exact guardAnd_one g (ih restOk restRun)
          all_goals simp at run
        all_goals simp at run

/-- Operands Core evaluates first, one after another, pass their checks. -/
theorem prefix_guards {scope frame st env} {prog : Core.Program} (corr : Corr scope frame st env)
    (target : prog.target = .x86_64) :
    ∀ {es : List SrcExpr} {rest : List Core.Expr} {fuel : Nat} {vs : List Value} {st' : State},
      (∀ e ∈ es, ∃ ty x, lowerAs scope e ty = some x) →
      evalExprs fuel prog st (es.map SrcExpr.toCore ++ rest) = .done vs st' →
      ∀ e ∈ es, (e.guard scope).eval env = 1
  | [], _, _, _, _, _, _ => by simp
  | e :: es, rest, fuel, vs, st', lowers, run => by
    cases fuel with
    | zero => simp [evalExprs] at run
    | succ fuel =>
      obtain ⟨ty, x, ok⟩ := lowers e List.mem_cons_self
      simp only [List.map_cons, List.cons_append, evalExprs] at run
      split at run
      · rename_i v mid headRun
        have g := lowerAs_guard corr target ok headRun
        obtain ⟨rfl, -⟩ := lowerAs_sound corr target ok headRun
        split at run
        · rename_i rvs fin restRun
          intro e' mem
          rcases List.mem_cons.mp mem with rfl | mem
          · exact g
          · exact prefix_guards corr target (fun e'' m => lowers e'' (List.mem_cons_of_mem _ m)) restRun e' mem
        all_goals simp at run
      all_goals simp at run

/-! ## Calls -/

theorem restore_fresh {caller st : State} (fresh : st.Fresh) : (restoreLocals caller st).Fresh := fresh

theorem restore_keeps (base : Nat) (caller st : State) : Keeps base st (restoreLocals caller st) :=
  ⟨fun _ _ => rfl, Nat.le_refl _⟩

/-- Binding the parameters gives the callee's frame. -/
theorem entry_corr (env : Env) (base : Nat) :
    ∀ (params : List SrcParam) {values : List Value} {k : Nat} {scope : List Binding}
      {frame : Nat → Nat} {st : State},
      FieldsHold (paramTypes params) values env k → paramsValid params = true →
      base ≤ st.nextCell → st.Fresh →
      Corr scope frame st env → Layout scope frame base k →
      ∃ frame', Corr (paramScope params k scope) frame' (st.bindLocals (paramBindings params values)) env ∧
        Layout (paramScope params k scope) frame' base (k + paramsSize params) ∧
        (st.bindLocals (paramBindings params values)).Fresh ∧
        Keeps base st (st.bindLocals (paramBindings params values)) := by
  intro params
  induction params with
  | nil =>
    intro values k scope frame st holds _ _ fresh corr fr
    cases holds
    simp only [paramScope, paramBindings, List.map_nil, List.zip_nil_left, State.bindLocals,
      List.foldl_nil, paramsSize, Nat.add_zero]
    exact ⟨frame, corr, fr, fresh, Keeps.refl _ _⟩
  | cons p ps ih =>
    intro values k scope frame st holds valid le fresh corr fr
    simp only [paramTypes] at holds
    cases holds with
    | cons holdsHead holdsRest =>
    rename_i v vs
    simp only [paramsValid, Bool.and_eq_true, decide_eq_true_eq] at valid
    have bindEq : st.bindLocals (paramBindings (p :: ps) (v :: vs)) =
        (st.bindLocal p.id v).bindLocals (paramBindings ps vs) := by
      simp [paramBindings, State.bindLocals]
    rw [bindEq]
    simp only [paramScope]
    have pushed := corr.push fr fresh (env' := env) (fun _ _ _ _ => rfl) (id := p.id) holdsHead
    have frPushed := fr.push (corr.below fresh) le p.id valid.1
    obtain ⟨frame', corr', fr', fresh', keeps'⟩ := ih holdsRest valid.2
      (Nat.le_trans le (Nat.le_succ _)) (bindLocal_fresh fresh p.id v) pushed frPushed
    refine ⟨frame', corr', ?_, fresh', (bindLocal_keeps le p.id v).trans keeps'⟩
    simpa [paramsSize, Nat.add_assoc] using fr'

/-! ## The simulation -/

/-- The slots a return stores: the value, or nothing that matters for
`return;` in a unit function. -/
def RetHolds (ret : SrcType) : Option Value → List (BitVec 64) → Prop
  | some v, bits => ret.HoldsAt v (Func.entry bits) 0
  | none, _ => ret = .unit

/-- A Core completion and a mini outcome that agree: both fall through with
the scope still in correspondence, or both return represented values, and
the heaps agree. -/
inductive Matches (ret : SrcType) (scope : List Binding) (frame : Nat → Nat) (st : State) :
    Completion → Outcome → Prop where
  | next {env : Env} {hp : Heap} : Corr scope frame st env → HeapCorr st.heap st.world hp →
      Matches ret scope frame st .next (.normal env hp)
  | returned {v : Option Value} {bits : List (BitVec 64)} {hp : Heap} :
      RetHolds ret v bits → bits.length = ret.size → HeapCorr st.heap st.world hp →
      Matches ret scope frame st (.returned v) (.returned bits hp)
  | broke {env : Env} {hp : Heap} : Corr scope frame st env → HeapCorr st.heap st.world hp →
      Matches ret scope frame st .breakLoop (.broke env hp)
  | continued {env : Env} {hp : Heap} : Corr scope frame st env → HeapCorr st.heap st.world hp →
      Matches ret scope frame st .continueLoop (.continued env hp)

/-- Core went from `st` to `st'` with completion `c`; the mini statement has a
derivation from `env` and `hp` with a matching outcome. -/
abbrev Simulates (mp : Program) (hp : Heap) (ret : SrcType) (scope : List Binding) (frame : Nat → Nat)
    (base : Nat) (st : State) (env : Env) (stmt : Stmt) (c : Completion) (st' : State) : Prop :=
  st'.Fresh ∧ Keeps base st st' ∧ ∃ d out, Exec mp d env hp stmt out ∧ Matches ret scope frame st' c out

/-- A statement after a check that passes. -/
theorem Simulates.checked {mp : Program} {hp : Heap} {ret : SrcType} {scope : List Binding} {frame : Nat → Nat}
    {base : Nat} {st : State} {env : Env} {stmt : Stmt} {c : Completion} {st' : State} {slot : Nat} {g : Expr}
    (one : g.eval env = 1) (sim : Simulates mp hp ret scope frame base st env stmt c st') :
    Simulates mp hp ret scope frame base st env (checkThen slot g stmt) c st' := by
  obtain ⟨fresh, keeps, d, out, exec, matched⟩ := sim
  exact ⟨fresh, keeps, d, out, exec.checkThen one, matched⟩

/-- Every statement lowered for `sp` that Core runs to completion with `fuel`,
ending with its heap cursor within the mini heap's limit, has a mini
derivation with a matching outcome. -/
def StmtSound (sp : SrcProgram) (mp : Program) (fuel : Nat) : Prop :=
  ∀ {hp : Heap} {s : SrcStmt} {ret : SrcType} {scope : List Binding} {next : Nat} {stmt : Stmt}
    {frame : Nat → Nat} {base : Nat} {st : State} {env : Env} {c : Completion} {st' : State},
    s.lower (sigs sp.funcs) sp.decls ret scope next = some stmt →
    Corr scope frame st env → Layout scope frame base next → st.Fresh → base ≤ st.nextCell →
    HeapCorr st.heap st.world hp → execStmt fuel sp.toCore st s.toCore = .done c st' →
    st'.heap.nextAddress ≤ hp.limit →
    Simulates mp hp ret scope frame base st env stmt c st'

theorem SrcProgram.target_toCore (sp : SrcProgram) : sp.toCore.target = .x86_64 := rfl

/-- A function body Core runs to a return is a mini `Returns`. -/
theorem body_sound {sp : SrcProgram} {mp : Program}
    (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) {fuel : Nat}
    (ih : StmtSound sp mp fuel) {callee : Nat} {f : SrcFunc} (found : sp.funcs[callee]? = some f)
    {hp : Heap} {st : State} (fresh : st.Fresh) (hc : HeapCorr st.heap st.world hp) {values : List Value}
    {bits : List (BitVec 64)} (holds : FieldsHold (paramTypes f.params) values (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize f.params) {v : Value} {c : Completion} {completed : State}
    (run : execStmt fuel sp.toCore (({ st with locals := [] } : State).bindLocals
      (paramBindings f.params values)) f.body.toCore = .done c completed)
    (result : CallResult f.ret c v)
    (bound : completed.heap.nextAddress ≤ hp.limit) :
    completed.Fresh ∧ Keeps st.nextCell st completed ∧
      ∃ d rs hp', mp.Returns d callee bits hp rs hp' ∧ f.ret.HoldsAt v (Func.entry rs) 0 ∧
        rs.length = f.ret.size ∧ HeapCorr completed.heap completed.world hp' := by
  obtain ⟨g, gFound, gOk⟩ := lowerFuncs_get lowered found
  obtain ⟨gParams, _, valid, inside, b, bodyOk, tail⟩ := lowerFunc_some gOk
  obtain ⟨frame, corr, fr, fresh0, keeps0⟩ := entry_corr (Func.entry bits) st.nextCell f.params
    (k := 0) (scope := []) (frame := fun _ => 0) (st := { st with locals := [] }) holds valid
    (Nat.le_refl _) fresh ⟨rfl, fun _ mem => by simp at mem⟩
    ⟨fun _ mem => by simp at mem, fun _ mem => by simp at mem, fun _ mem => by simp at mem,
      fun _ mem => by simp at mem, fun _ mem => by simp at mem⟩
  rw [Nat.zero_add] at fr
  have hc0 : HeapCorr (({ st with locals := [] } : State).bindLocals (paramBindings f.params values)).heap (({ st with locals := [] } : State).bindLocals (paramBindings f.params values)).world hp := by
    rw [(bindLocals_same _ _).1, bindLocals_world]
    exact hc
  obtain ⟨freshDone, keepsDone, d, out, exec, agree⟩ :=
    ih (hp := hp) bodyOk corr fr fresh0 keeps0.next hc0 run bound
  have keeps : Keeps st.nextCell st completed :=
    ⟨fun c below => (keepsDone.cells c below).trans (keeps0.cells c below), Nat.le_trans keeps0.next keepsDone.next⟩
  have arity : bits.length = g.params := by rw [gParams, bitsLen]
  have returns : ∀ {rs hp'}, Exec mp d (Func.entry bits) hp b (.returned rs hp') →
      Exec mp d (Func.entry bits) hp g.body (.returned rs hp') := by
    intro rs hp' e
    simp only [unitTail] at tail
    split at tail
    · simp only [Option.some.injEq] at tail
      rw [← tail]
      exact .seqReturned e
    · simp only [Option.some.injEq] at tail
      rw [← tail]
      exact e
  cases c with
  | returned w =>
    cases agree with
    | returned holdsRet len hcDone =>
      cases w with
      | some w =>
        simp only [CallResult] at result
        subst result
        exact ⟨freshDone, keeps, d, _, _, ⟨g, gFound, arity, returns exec⟩, holdsRet, len, hcDone⟩
      | none =>
        obtain ⟨unit, rfl⟩ := result
        rw [unit] at len ⊢
        exact ⟨freshDone, keeps, d, _, _, ⟨g, gFound, arity, returns exec⟩, .unit, len, hcDone⟩
  | next =>
    obtain ⟨unit, rfl⟩ := result
    cases agree with
    | @next envDone hpDone corrDone hcDone =>
      simp only [unitTail, unit, SrcType.isUnit, if_true, Option.some.injEq] at tail
      have exec' : Exec mp d (Func.entry bits) hp g.body
          (.returned (Expr.evalAll envDone [.lit 0]) hpDone) := by
        rw [← tail]
        exact .seq exec .ret
      rw [unit]
      exact ⟨freshDone, keeps, d, _, _, ⟨g, gFound, arity, exec'⟩, .unit, rfl, hcDone⟩
  | breakLoop => simp [CallResult] at result
  | continueLoop => simp [CallResult] at result

/-- A lowered call that Core completes: the caller's locals and cells are as
they were, and the mini call stores slots representing the result. -/
theorem call_sound {sp : SrcProgram} {mp : Program}
    (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) {fuel : Nat}
    (ih : StmtSound sp mp fuel) {hp : Heap} {scope frame st env} (corr : Corr scope frame st env)
    (fresh : st.Fresh) (hc : HeapCorr st.heap st.world hp) {callee : Nat} {args : List SrcExpr} {ty : SrcType}
    {es : List Expr} (ok : lowerCall (sigs sp.funcs) scope callee args ty = some es) {v : Value} {st' : State}
    (run : evalExpr (fuel + 1) sp.toCore st (.call callee (args.map SrcExpr.toCore)) = .done v st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    st'.Fresh ∧ Keeps st.nextCell st st' ∧ st'.locals = st.locals ∧ 0 < ty.size ∧
      ∃ d rs hp', ty.HoldsAt v (Func.entry rs) 0 ∧ rs.length = ty.size ∧ HeapCorr st'.heap st'.world hp' ∧
        ∀ target, Exec mp d env hp (.call target ty.size callee es) (.normal (env.setMany target rs) hp') := by
  obtain ⟨f, values, afterArgs, completed, c, argsRun, found, _, bodyRun, result, rfl⟩ := call_inv (lowerCall_inside ok) run
  simp only [lowerCall, sigs_get, found, Option.map_some, lowerCallSig] at ok
  split at ok
  · rename_i same
    have tyEq := SrcType.same_eq same
    subst tyEq
    obtain ⟨rfl, holds, esLen, -⟩ := lowerArgs_sound corr (SrcProgram.target_toCore sp) ok argsRun
    obtain ⟨freshDone, keeps, d, rs, hp', ⟨g, gFound, arity, exec⟩, holdsRet, len, hcDone⟩ :=
      body_sound lowered ih found (hp := hp) fresh hc holds (by rw [evalAll_length, esLen, paramsSize_eq])
        bodyRun result bound
    obtain ⟨g', -, gOk⟩ := lowerFuncs_get lowered found
    refine ⟨restore_fresh freshDone, keeps.trans (restore_keeps _ _ _), rfl, (lowerFunc_some gOk).2.1, d + 1, rs,
      hp', holdsRet, len, hcDone, fun target => .call gFound ?_ len (Nat.lt_succ_self d) exec⟩
    rw [← arity, evalAll_length]
  · simp at ok

/-- A call's arguments pass their checks. -/
theorem lowerCall_guard {sp : SrcProgram} {scope frame st env} (corr : Corr scope frame st env)
    {callee : Nat} {args : List SrcExpr} {ty : SrcType} {es : List Expr}
    (ok : lowerCall (sigs sp.funcs) scope callee args ty = some es) {fuel : Nat} {v : Value} {st' : State}
    (run : evalExpr (fuel + 1) sp.toCore st (.call callee (args.map SrcExpr.toCore)) = .done v st') :
    (guardAll scope args).eval env = 1 := by
  obtain ⟨f, values, afterArgs, completed, c, argsRun, found, _, bodyRun, result, rfl⟩ := call_inv (lowerCall_inside ok) run
  simp only [lowerCall, sigs_get, found, Option.map_some, lowerCallSig] at ok
  split at ok
  · exact lowerArgs_guard corr (SrcProgram.target_toCore sp) ok argsRun
  · simp at ok

/-- The slots a call stores hold the value its callee returned. -/
theorem setMany_holds {ty : SrcType} {v : Value} {rs : List (BitVec 64)} (holds : ty.HoldsAt v (Func.entry rs) 0)
    (len : rs.length = ty.size) (env : Env) (slot : Nat) : ty.HoldsAt v (env.setMany slot rs) slot :=
  holds.congr fun i below => by
    rw [setMany_eq, if_pos (by omega), Nat.zero_add, Nat.add_sub_cancel_left]
    rfl

/-! ## Assignment and `let` -/

/-- Core's `id = e` on a local of the scope: it evaluates `e`, then replaces
the local's cell. -/
theorem assign_step {P : Core.Program} {scope frame st env} (corr : Corr scope frame st env)
    {id : Nat} {b : Binding} (found : lookup scope id = some b) {e : Core.Expr} {k : Nat}
    {u : Value} {st' : State}
    (run : evalExpr (k + 1) P st (.assign .set (.local id) e) = .done u st')
    (after : ∀ {rv st2}, evalExpr k P st e = .done rv st2 → st2.i32ArrayViews = []) :
    ∃ rv st2, evalExpr k P st e = .done rv st2 ∧
      st' = { st2 with cells := Semantics.replaceCell st2.cells (frame b.slot) rv } := by
  cases k with
  | zero => simp [evalExpr, Semantics.evalPlace] at run
  | succ j =>
    obtain ⟨v0, entry, _⟩ := corr.values b (lookup_mem found).1
    have place : Semantics.evalPlace (j + 1) P st .address (.local id) =
        .done { root := frame b.slot, projections := [], value := some v0 } st := by
      simp [Semantics.evalPlace, corr.cellId, found, entry]
    simp only [evalExpr, place] at run
    split at run
    · rename_i rv st2 valueRun
      have views := after valueRun
      cases present : (st2.cellEntry? (frame b.slot)).isSome with
      | false =>
        simp [Semantics.evalAssignValue, Semantics.assignOpBinary?, Semantics.writeResolvedPlaceNative,
          Semantics.writeResolvedPlace, Semantics.State.assignCell, present] at run
      | true =>
        obtain ⟨e2, entry2⟩ := Option.isSome_iff_exists.mp present
        have synced := sync_ok (st := { st2 with cells := Semantics.replaceCell st2.cells (frame b.slot) rv }) views
        simp only [Semantics.evalAssignValue, Semantics.assignOpBinary?,
          Semantics.writeResolvedPlaceNative, Semantics.writeResolvedPlace, assignCell_some entry2,
          synced, ite_self, Semantics.Outcome.done.injEq] at run
        exact ⟨rv, st2, valueRun, run.2.symm⟩
    all_goals simp at run

/-- Core's `id.index = e` on a struct local of the scope. -/
theorem field_assign_step {P : Core.Program} {scope frame st env} (corr : Corr scope frame st env)
    {id : Nat} {b : Binding} (found : lookup scope id = some b) {sid : Nat} {vs : List Value}
    (entry : st.cellEntry? (frame b.slot) = some ⟨frame b.slot, some (.structure sid vs)⟩)
    {index : Nat} {old : Value} (got : vs[index]? = some old) (views : st.i32ArrayViews = [])
    {e : Core.Expr} {k : Nat} {u : Value} {st' : State}
    (run : evalExpr (k + 1) P st (.assign .set (.field (.local id) index) e) = .done u st')
    (after : ∀ {rv st2}, evalExpr k P st e = .done rv st2 → st2 = st) :
    ∃ rv, evalExpr k P st e = .done rv st ∧
      st' = { st with cells := Semantics.replaceCell st.cells (frame b.slot) (.structure sid (Semantics.setValue vs index rv)) } := by
  cases k with
  | zero => simp [evalExpr, Semantics.evalPlace] at run
  | succ j =>
    cases j with
    | zero => simp [evalExpr, Semantics.evalPlace] at run
    | succ m =>
      have place : Semantics.evalPlace (m + 2) P st .address (.field (.local id) index) =
          .done { root := frame b.slot, projections := [.field index], value := some old } st := by
        simp [Semantics.evalPlace, corr.cellId, found, entry, got]
      simp only [evalExpr, place] at run
      split at run
      · rename_i rv st2 valueRun
        have := after valueRun
        subst this
        have synced := sync_ok
          (st := { st2 with cells := Semantics.replaceCell st2.cells (frame b.slot) (.structure sid (Semantics.setValue vs index rv)) })
          views
        simp only [Semantics.evalAssignValue, Semantics.assignOpBinary?,
          Semantics.writeResolvedPlaceNative, Semantics.writeResolvedPlace, entry,
          Semantics.replaceProjectedValue, got, assignCell_some entry, synced, ite_self,
          Semantics.Outcome.done.injEq] at run
        exact ⟨rv, valueRun, run.2.symm⟩
      all_goals simp at run

/-- Writing binding `b`'s cell, with the mini slots of `b` changed to match. -/
theorem Corr.assign {scope frame st env base next} (corr : Corr scope frame st env)
    (fr : Layout scope frame base next) {b : Binding} (bmem : b ∈ scope) {rv : Value} {env' : Env}
    (outside : ∀ j, j < b.slot ∨ b.slot + b.ty.size ≤ j → env' j = env j)
    (holds : b.ty.HoldsAt rv env' b.slot) :
    Corr scope frame { st with cells := Semantics.replaceCell st.cells (frame b.slot) rv } env' := by
  refine ⟨corr.locals, fun a mem => ?_⟩
  rw [assigned_entry]
  by_cases same : frame a.slot = frame b.slot
  · have := fr.inj a mem b bmem same
    subst this
    obtain ⟨v0, entry, _⟩ := corr.values a mem
    rw [if_pos rfl, entry]
    exact ⟨rv, rfl, holds⟩
  · rw [if_neg same]
    obtain ⟨v1, entry, holds1⟩ := corr.values a mem
    have ne : a ≠ b := fun eq => same (by rw [eq])
    refine ⟨v1, entry, holds1.congr fun i below => outside _ ?_⟩
    rcases fr.apart a mem b bmem ne with left | right
    · omega
    · omega

theorem assigned_keeps {base cell : Nat} (above : base ≤ cell) (st : State) (rv : Value) :
    Keeps base st { st with cells := Semantics.replaceCell st.cells cell rv } :=
  ⟨fun c below => by rw [assigned_entry, if_neg (by cell_omega)], Nat.le_refl _⟩

/-- The mini environment after `assignFrom slot xs`. -/
def Env.setFrom (env : Env) : Nat → List Expr → Env
  | _, [] => env
  | slot, x :: xs => Env.setFrom (env.set slot (x.eval env)) (slot + 1) xs

theorem assignFrom_exec {mp : Program} {d : Nat} {hp : Heap} {rest : Stmt} {out : Outcome} :
    ∀ (xs : List Expr) (slot : Nat) {env : Env}, Exec mp d (env.setFrom slot xs) hp rest out →
      Exec mp d env hp (assignFrom slot xs rest) out
  | [], _, _, exec => exec
  | _ :: more, slot, _, exec => .seq .assign (assignFrom_exec more (slot + 1) exec)

theorem setFrom_outside : ∀ (xs : List Expr) (slot : Nat) (env : Env) (j : Nat),
    j < slot ∨ slot + xs.length ≤ j → env.setFrom slot xs j = env j
  | [], _, _, _, _ => rfl
  | x :: more, slot, env, j, away => by
    simp only [Env.setFrom]
    rw [setFrom_outside more (slot + 1) _ j (by simp at away; omega)]
    simp only [Env.set]
    rw [if_neg (by simp at away; omega)]

/-- Expression `i` of `xs` does not read the slots stored before it. -/
def Insens (xs : List Expr) (slot : Nat) : Prop :=
  ∀ i (x : Expr), xs[i]? = some x → ∀ j < i, ∀ (E : Env) (w : BitVec 64),
    x.eval (E.set (slot + j) w) = x.eval E

theorem setFrom_value : ∀ (xs : List Expr) (slot : Nat) (env : Env), Insens xs slot →
    ∀ i (x : Expr), xs[i]? = some x → env.setFrom slot xs (slot + i) = x.eval env
  | [], _, _, _, i, x, found => by simp at found
  | y :: more, slot, env, insens, i, x, found => by
    simp only [Env.setFrom]
    cases i with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst found
      rw [setFrom_outside more (slot + 1) _ _ (by omega)]
      simp [Env.set]
    | succ i =>
      simp only [List.getElem?_cons_succ] at found
      have restInsens : Insens more (slot + 1) := fun i' x' found' j below E w => by
        have := insens (i' + 1) x' (by simpa using found') (j + 1) (by omega) E w
        rwa [show slot + (j + 1) = slot + 1 + j by omega] at this
      rw [show slot + (i + 1) = slot + 1 + i by omega,
        setFrom_value more (slot + 1) _ restInsens i x found]
      exact insens (i + 1) x (by simpa using found) 0 (by omega) env _

theorem FlatValue.store {ty : SrcType} {v : Value} {env : Env} {xs : List Expr}
    (flat : FlatValue ty v env xs) {dst : Nat} (insens : Insens xs dst) :
    ty.HoldsAt v (env.setFrom dst xs) dst := by
  refine flat.holds.congr fun i below => ?_
  have : i < xs.length := by rw [flat.length]; exact below
  obtain ⟨x, found⟩ : ∃ x, xs[i]? = some x := ⟨xs[i], by simp [this]⟩
  rw [setFrom_value xs dst env insens i x found, Nat.zero_add, entry_evalAll env xs i x found]

theorem Insens.single (x : Expr) (slot : Nat) : Insens [x] slot := by
  intro i y found j below
  cases i with
  | zero => omega
  | succ i => simp at found

/-- `e` reads no slot at or above `n`. -/
def Expr.Below (n : Nat) : Expr → Prop
  | .lit _ => True
  | .var i => i < n
  | .neg e => e.Below n
  | .binary _ _ l r => l.Below n ∧ r.Below n
  | .compare _ _ l r => l.Below n ∧ r.Below n

theorem Expr.Below.eval_set {n : Nat} : ∀ {x : Expr}, x.Below n → ∀ {j : Nat}, n ≤ j →
    ∀ (E : Env) (w : BitVec 64), x.eval (E.set j w) = x.eval E
  | .lit _, _, _, _, _, _ => rfl
  | .var i, below, j, le, E, w => by
    simp only [Expr.Below] at below
    simp only [Expr.eval, Env.set]
    rw [if_neg (by omega)]
  | .neg e, below, j, le, E, w => by
    simp only [Expr.eval, Expr.Below.eval_set (x := e) below le]
  | .binary _ _ l r, below, j, le, E, w => by
    simp only [Expr.eval, Expr.Below.eval_set below.1 le, Expr.Below.eval_set below.2 le]
  | .compare _ _ l r, below, j, le, E, w => by
    simp only [Expr.eval, Expr.Below.eval_set below.1 le, Expr.Below.eval_set below.2 le]

theorem Insens.below {xs : List Expr} {slot : Nat} (all : ∀ x ∈ xs, x.Below slot) : Insens xs slot :=
  fun _ x found _ _ E w => (all x (List.mem_of_getElem? found)).eval_set (by omega) E w

theorem Insens.copy {src dst n : Nat} (apart : src = dst ∨ src + n ≤ dst ∨ dst + n ≤ src) :
    Insens (slotVars src n) dst := by
  intro i x found j below E w
  have inRange : i < n := by
    obtain ⟨h, _⟩ := List.getElem?_eq_some_iff.mp found
    rw [slotVars_length] at h
    exact h
  rw [slotVars_get src n i inRange, Option.some.injEq] at found
  subst found
  simp only [Expr.eval, Env.set]
  rw [if_neg (by omega)]

theorem Expr.Below.wrap {n : Nat} {e : Expr} (below : e.Below n) (k : UintTy) : (wrap k e).Below n := by
  unfold Lanius.Mini.wrap
  split
  · exact below
  · exact ⟨below, trivial⟩

theorem Expr.Below.norm {n : Nat} {e : Expr} (below : e.Below n) (k : UintTy) : (norm k e).Below n :=
  ⟨⟨below, trivial⟩, trivial⟩

theorem Expr.Below.fromI32 {n : Nat} {e : Expr} (below : e.Below n) (k : UintTy) : (fromI32 k e).Below n := by
  unfold Lanius.Mini.fromI32
  split
  · exact ⟨below, ⟨below, trivial⟩, trivial⟩
  · exact below.wrap k

theorem castToIsize_below {n : Nat} {inner t : Typed} (h : castToIsize inner = some t)
    (below : inner.expr.Below n) : t.expr.Below n := by
  simp only [castToIsize] at h
  split at h <;> simp only [Option.some.injEq, reduceCtorEq] at h <;> subst h
  · exact below.fromI32 .uint64
  · exact below
  · exact below
  · exact below
  · simp only [sintToWide]
    split
    · exact below
    · exact below.fromI32 .uint64

theorem castTo_below {n : Nat} {ty : SrcType} {inner t : Typed} (h : castTo ty inner = some t)
    (below : inner.expr.Below n) : t.expr.Below n := by
  cases ty with
  | i32 =>
    simp only [castTo, castToI32] at h
    split at h <;> simp only [Option.some.injEq, reduceCtorEq] at h <;> subst h
    · exact below
    · exact below.wrap .uint32
    · exact below.wrap .uint32
    · exact below.wrap .uint32
    · simp only [sintToI32]
      split
      · exact below.wrap .uint32
      · exact below
  | uint kind =>
    simp only [castTo, castToUint] at h
    split at h <;> simp only [Option.some.injEq, reduceCtorEq] at h <;> subst h
    · simp only [fromI32]
      split
      · exact ⟨below, ⟨below, trivial⟩, trivial⟩
      · exact below.wrap kind
    · exact below.wrap kind
    · exact below.wrap kind
    · exact below.wrap kind
    · simp only [sintToUint]
      split
      · exact below.wrap kind
      · exact below.fromI32 kind
  | isize => exact castToIsize_below h below
  | char => simp [castTo] at h
  | sint kind =>
    simp only [castTo, castToSint] at h
    split at h
    · cases hc : castToIsize inner with
      | none => simp [hc] at h
      | some t' =>
        simp only [hc, Option.some.injEq] at h
        subst h
        exact (castToIsize_below hc below : t'.expr.Below n)
    split at h
    · simp only [Option.some.injEq] at h
      subst h
      exact below.norm kind
    · simp at h
  | bool => simp [castTo] at h
  | struct => simp [castTo] at h
  | enum => simp [castTo] at h
  | ptr => simp [castTo] at h
  | slice => simp [castTo] at h
  | unit => simp [castTo] at h

theorem SrcExpr.lower_below {scope : List Binding} {next : Nat}
    (slots : ∀ b ∈ scope, b.slot + b.ty.size ≤ next) :
    ∀ (e : SrcExpr) {t : Typed}, e.lower scope = some t → t.expr.Below next := by
  intro e
  induction e with
  | int x => intro t lowered; simp only [SrcExpr.lower, Option.some.injEq] at lowered; subst lowered; trivial
  | boolean x => intro t lowered; simp only [SrcExpr.lower, Option.some.injEq] at lowered; subst lowered; trivial
  | null => intro t lowered; simp only [SrcExpr.lower, Option.some.injEq] at lowered; subst lowered; trivial
  | unsigned kind x =>
    intro t lowered
    simp only [SrcExpr.lower, lowerUnsigned] at lowered
    split at lowered <;> simp only [Option.some.injEq, reduceCtorEq] at lowered
    subst lowered
    trivial
  | «local» id =>
    intro t lowered
    simp only [SrcExpr.lower, lowerLocal] at lowered
    split at lowered
    · simp at lowered
    rename_i b found
    simp only [lowerScalarLocal] at lowered
    split at lowered
    · rename_i scalar
      simp only [Option.some.injEq] at lowered
      subst lowered
      have := slots b (lookup_mem found).1
      rw [SrcType.size_scalar scalar] at this
      simp only [Expr.Below]
      omega
    · simp at lowered
  | field id index =>
    intro t lowered
    simp only [SrcExpr.lower, lowerField] at lowered
    split at lowered
    · simp at lowered
    rename_i b found
    simp only [lowerFieldOf] at lowered
    split at lowered
    · simp at lowered
    · simp at lowered
    · simp at lowered
    case h_5 => simp at lowered
    case h_6 => simp at lowered
    case h_7 => simp at lowered
    case h_8 => simp at lowered
    case h_9 => simp at lowered
    case h_10 => simp at lowered
    case h_11 => simp at lowered
    rename_i sid fields hty
    simp only [lowerFieldAt] at lowered
    split at lowered
    · simp at lowered
    rename_i f fieldFound
    split at lowered
    · rename_i scalar
      simp only [Option.some.injEq] at lowered
      subst lowered
      have := slots b (lookup_mem found).1
      rw [hty] at this
      have := fieldOffset_lt fieldFound
      have := SrcType.size_scalar scalar
      simp only [SrcType.size] at *
      simp only [Expr.Below]
      omega
    · simp at lowered
  | negate operand ih =>
    intro t lowered
    simp only [SrcExpr.lower, lowerNegate] at lowered
    split at lowered
    · simp at lowered
    rename_i inner innerLowered
    simp only [lowerNegateTyped] at lowered
    split at lowered
    · simp only [Option.some.injEq] at lowered
      subst lowered
      exact ih (t := inner) innerLowered
    split at lowered
    · simp only [Option.some.injEq] at lowered
      subst lowered
      exact ⟨trivial, ih (t := inner) innerLowered⟩
    split at lowered
    · simp at lowered
    · simp only [Option.some.injEq] at lowered
      subst lowered
      rename_i k _
      simp only [negateSigned]
      split
      · exact ⟨trivial, ih (t := inner) innerLowered⟩
      · exact Expr.Below.norm (e := .neg _) (ih (t := inner) innerLowered) k
  | not operand ih =>
    intro t lowered
    simp only [SrcExpr.lower, lowerNot] at lowered
    split at lowered
    · simp at lowered
    rename_i inner innerLowered
    simp only [lowerNotTyped] at lowered
    split at lowered
    · simp only [Option.some.injEq] at lowered
      subst lowered
      exact ⟨ih (t := inner) innerLowered, trivial⟩
    · simp at lowered
  | apply op left right ihl ihr =>
    intro t lowered
    simp only [SrcExpr.lower, lowerApply] at lowered
    split at lowered
    · simp at lowered
    rename_i tl leftLowered
    split at lowered
    · simp at lowered
    rename_i tr rightLowered
    have bl := ihl leftLowered
    have br := ihr rightLowered
    cases op
    case plus | minus | times | bitAnd | bitOr | bitXor | shiftLeft | shiftRight =>
      simp only [SrcOp.lower, arithShiftRight, lowerShift] at lowered
      try
        rcases offsetOrArith_some lowered with ⟨-, -, rfl⟩ | lowered
        · exact ⟨bl, br⟩
      try split at lowered
      all_goals try (split at lowered; rotate_left; · simp at lowered)
      all_goals first | (simp at lowered; done) | skip
      all_goals
        simp only [arith] at lowered
        split at lowered
        · simp only [Option.some.injEq] at lowered
          subst lowered
          exact ⟨bl, br⟩
        split at lowered
        · simp only [Option.some.injEq] at lowered
          subst lowered
          exact ⟨bl, br⟩
        split at lowered
        · cases hk : tl.ty.sintKind <;> rw [hk] at lowered <;> simp only [arithSint, reduceCtorEq] at lowered
          split at lowered
          · simp only [Option.some.injEq] at lowered
            subst lowered
            exact ⟨bl, br⟩
          split at lowered
          · simp only [Option.some.injEq] at lowered
            subst lowered
            exact Expr.Below.norm (e := .binary .s32 _ _ _) ⟨bl, br⟩ _
          · simp at lowered
        · obtain ⟨k, -, -, rfl⟩ := arithUint_some lowered
          exact Expr.Below.wrap (e := .binary .u64 _ _ _) ⟨bl, br⟩ k
    case less | lessEq | greater | greaterEq =>
      simp only [SrcOp.lower, order] at lowered
      split at lowered
      · simp only [Option.some.injEq] at lowered
        subst lowered
        exact ⟨bl, br⟩
      split at lowered
      · simp only [Option.some.injEq] at lowered
        subst lowered
        exact ⟨⟨bl, trivial⟩, ⟨br, trivial⟩⟩
      split at lowered
      · cases hk : tl.ty.sintKind <;> rw [hk] at lowered <;> simp only [orderSint, reduceCtorEq] at lowered
        split at lowered
        · simp only [Option.some.injEq] at lowered
          subst lowered
          exact ⟨⟨bl, trivial⟩, ⟨br, trivial⟩⟩
        split at lowered
        · simp only [Option.some.injEq] at lowered
          subst lowered
          exact ⟨bl, br⟩
        · simp at lowered
      split at lowered
      · simp only [Option.some.injEq] at lowered
        subst lowered
        exact ⟨bl, br⟩
      · obtain ⟨k, -, -, rfl⟩ := orderUint_some lowered
        exact ⟨bl, br⟩
    all_goals
      simp only [SrcOp.lower, equality, conjunction, disjunction] at lowered
      split at lowered <;> simp only [Option.some.injEq, reduceCtorEq] at lowered <;> subst lowered <;>
      first | exact ⟨bl, br⟩ | exact ⟨⟨bl, br⟩, trivial⟩
  | cast ty operand ih =>
    intro t lowered
    simp only [SrcExpr.lower, lowerCast] at lowered
    split at lowered
    · simp at lowered
    rename_i inner innerLowered
    exact castTo_below lowered (ih innerLowered)
  | char c => intro t lowered; simp only [SrcExpr.lower, Option.some.injEq] at lowered; subst lowered; trivial

theorem ValueShape.sized {scope frame base next} {xs : List Expr} (shape : ValueShape scope xs)
    (fr : Layout scope frame base next) : 0 < xs.length := by
  cases shape with
  | single => simp
  | copy mem => rw [slotVars_length]; exact fr.sized _ mem
  | part _ pos _ => rw [slotVars_length]; exact pos

theorem ValueShape.insens_next {scope frame base next} {xs : List Expr} (shape : ValueShape scope xs)
    (fr : Layout scope frame base next) : Insens xs next := by
  cases shape with
  | single => exact Insens.single _ _
  | copy mem => exact Insens.copy (.inr (.inl (fr.slots _ mem)))
  | part mem _ within => exact Insens.copy (.inr (.inl (by have := fr.slots _ mem; omega)))

theorem ValueShape.insens_self {scope frame base next} {xs : List Expr} (shape : ValueShape scope xs)
    (fr : Layout scope frame base next) {b : Binding} (bmem : b ∈ scope) (len : xs.length = b.ty.size) :
    Insens xs b.slot := by
  cases shape with
  | single => exact Insens.single _ _
  | copy mem =>
    rename_i a
    rw [slotVars_length] at len
    by_cases same : a = b
    · subst same; exact Insens.copy (.inl rfl)
    · rcases fr.apart a mem b bmem same with left | right
      · exact Insens.copy (.inr (.inl left))
      · exact Insens.copy (.inr (.inr (by rw [len]; exact right)))
  | part mem pos within =>
    rename_i a off n
    rw [slotVars_length] at len
    by_cases same : a = b
    · subst same
      obtain rfl : off = 0 := by omega
      exact Insens.copy (.inl rfl)
    · rcases fr.apart a mem b bmem same with left | right
      · exact Insens.copy (.inr (.inl (by omega)))
      · exact Insens.copy (.inr (.inr (by omega)))

theorem slotVars_mem {slot count : Nat} {x : Expr} (mem : x ∈ slotVars slot count) :
    ∃ j, x = .var j ∧ slot ≤ j ∧ j < slot + count := by
  obtain ⟨i, found⟩ := List.mem_iff_getElem?.mp mem
  have below : i < count := by
    have := (List.getElem?_eq_some_iff.mp found).1
    rwa [slotVars_length] at this
  rw [slotVars_get _ _ _ below, Option.some.injEq] at found
  exact ⟨slot + i, found.symm, by omega, by omega⟩

theorem ValueShape.below {scope next} {xs : List Expr} (shape : ValueShape scope xs)
    (slots : ∀ b ∈ scope, b.slot + b.ty.size ≤ next) : ∀ x ∈ xs, x.Below next := by
  cases shape with
  | single lowered same =>
    intro x mem
    simp only [List.mem_singleton] at mem
    subst mem
    rw [← same]
    exact SrcExpr.lower_below slots _ lowered
  | copy bmem =>
    intro x mem
    obtain ⟨j, rfl, _, below⟩ := slotVars_mem mem
    have := slots _ bmem
    simp only [Expr.Below]
    omega
  | part bmem _ within =>
    intro x mem
    obtain ⟨j, rfl, _, below⟩ := slotVars_mem mem
    have := slots _ bmem
    simp only [Expr.Below]
    omega

/-- The body of a `let`, from the state after its initializer. -/
theorem let_tail {sp : SrcProgram} {mp : Program} {fuel : Nat} (ih : StmtSound sp mp fuel)
    {body : SrcStmt} {ret : SrcType} {scope : List Binding} {next : Nat} {bstmt : Stmt}
    {id : Nat} {ty : SrcType} {hp : Heap}
    (bodyOk : body.lower (sigs sp.funcs) sp.decls ret (⟨id, next, ty⟩ :: scope) (next + ty.size) = some bstmt)
    {frame base st env} (corr : Corr scope frame st env) (fr : Layout scope frame base next)
    (fresh : st.Fresh) (le : base ≤ st.nextCell) (sized : 0 < ty.size) {v : Value} {env' : Env}
    (agree : ScopeAgree scope env env') (holds : ty.HoldsAt v env' next)
    (hc : HeapCorr st.heap st.world hp) {c : Completion} {st' : State}
    (run : Semantics.restoreOutcomeLocals st
      (execStmt fuel sp.toCore (st.bindLocal id v) body.toCore) = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    st'.Fresh ∧ Keeps base st st' ∧
      ∃ d out, Exec mp d env' hp bstmt out ∧ Matches ret scope frame st' c out := by
  cases bodyRun : execStmt fuel sp.toCore (st.bindLocal id v) body.toCore with
  | done c' st'' =>
    simp only [bodyRun, Semantics.restoreOutcomeLocals, Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    have pushed := corr.push fr fresh agree (id := id) holds
    have frPushed := fr.push (corr.below fresh) le id sized
    obtain ⟨fresh'', keeps'', d, out, exec, matched⟩ :=
      ih (hp := hp) bodyOk pushed frPushed (bindLocal_fresh fresh id v)
        (Nat.le_trans le (Nat.le_succ _)) hc bodyRun bound
    refine ⟨restore_fresh fresh'', (bindLocal_keeps le id v).trans
      (keeps''.trans (restore_keeps _ _ _)), d, out, exec, ?_⟩
    cases matched with
    | next corr'' hc'' => exact .next (corr''.pop fr corr.locals rfl) hc''
    | returned holdsRet len hc'' => exact .returned holdsRet len hc''
    | broke corr'' hc'' => exact .broke (corr''.pop fr corr.locals rfl) hc''
    | continued corr'' hc'' => exact .continued (corr''.pop fr corr.locals rfl) hc''
  | trapped => simp [bodyRun, Semantics.restoreOutcomeLocals] at run
  | exited => simp [bodyRun, Semantics.restoreOutcomeLocals] at run
  | outOfFuel => simp [bodyRun, Semantics.restoreOutcomeLocals] at run

/-! ## Enums and `match` -/

/-- Like `Corr.push`, for a binding on a slot no binding of the scope owns: a
match binder names a payload slot of the scrutinee. -/
theorem Corr.alias {scope frame st env} (corr : Corr scope frame st env) (fresh : st.Fresh)
    {j : Nat} (away : ∀ b ∈ scope, b.slot ≠ j) (id : Nat) {ty : SrcType} {v : Value}
    (holds : ty.HoldsAt v env j) :
    Corr (⟨id, j, ty⟩ :: scope) (upd frame j st.nextCell) (st.bindLocal id v) env := by
  have same : ∀ b ∈ scope, upd frame j st.nextCell b.slot = frame b.slot := fun b mem => by
    simp only [upd]
    rw [if_neg (away b mem)]
  refine ⟨?_, ?_⟩
  · simp only [State.bindLocal, State.bindCell, List.map_cons, corr.locals, upd, if_pos]
    congr 1
    apply List.map_congr_left
    intro b mem
    rw [← upd, same b mem]
  · intro b mem
    simp only [List.mem_cons] at mem
    rcases mem with rfl | mem
    · refine ⟨v, ?_, holds⟩
      simp only [upd, if_pos]
      exact bindLocal_self fresh id v
    · obtain ⟨w, entry, holdsb⟩ := corr.values b mem
      refine ⟨w, ?_, holdsb⟩
      rw [same b mem, bindLocal_entry (corr.below fresh b mem)]
      exact entry

theorem bindLocals_cons (st : State) (id : Nat) (v : Value) (rest : List (Nat × Value)) :
    st.bindLocals ((id, v) :: rest) = (st.bindLocal id v).bindLocals rest := rfl

/-- Binding an arm's payload gives the arm's scope. -/
theorem armScope_corr :
    ∀ (binders : List Nat) {types : List SrcType} {vs : List Value} {slot : Nat}
      {scope s' : List Binding} {frame : Nat → Nat} {st : State} {env : Env},
      armScope binders types slot scope = some s' → FieldsHold types vs env slot →
      (∀ b ∈ scope, b.slot < slot ∨ slot + sizes types ≤ b.slot) →
      Corr scope frame st env → st.Fresh →
      ∃ frame', Corr s' frame' (st.bindLocals (binders.zip vs)) env ∧
        (st.bindLocals (binders.zip vs)).Fresh ∧
        Keeps st.nextCell st (st.bindLocals (binders.zip vs)) ∧ binders.length = vs.length
  | [], types, vs, slot, scope, s', frame, st, env, ok, holds, _, corr, fresh => by
    cases types with
    | cons => simp [armScope] at ok
    | nil =>
      simp only [armScope, Option.some.injEq] at ok
      subst ok
      cases holds
      exact ⟨frame, corr, fresh, Keeps.refl _ _, rfl⟩
  | binder :: rest, types, vs, slot, scope, s', frame, st, env, ok, holds, clear, corr, fresh => by
    cases types with
    | nil => simp [armScope] at ok
    | cons f more =>
      simp only [armScope] at ok
      split at ok
      · rename_i sized
        cases holds with
        | cons head tail =>
        rename_i v vs'
        rw [List.zip_cons_cons, bindLocals_cons]
        have pushed := corr.alias fresh (j := slot) (fun b mem => by
          have := clear b mem
          simp only [sizes] at this
          omega) binder head
        obtain ⟨frame', corr', fresh', keeps', len⟩ := armScope_corr rest ok tail (fun b mem => by
            simp only [List.mem_cons] at mem
            rcases mem with rfl | mem
            · left
              show slot < slot + f.size
              omega
            · have := clear b mem
              simp only [sizes] at this
              omega) pushed (bindLocal_fresh fresh binder v)
        exact ⟨frame', corr', fresh', (bindLocal_keeps (Nat.le_refl _) binder v).trans
          (keeps'.lower (Nat.le_succ _)), by simp [len]⟩
      · simp at ok

/-- The arm's scope stays below `n` when its payload does. -/
theorem armScope_slots : ∀ (binders : List Nat) {types : List SrcType} {slot : Nat}
    {scope s' : List Binding} {n : Nat}, armScope binders types slot scope = some s' →
    (∀ b ∈ scope, b.slot + b.ty.size ≤ n) → slot + sizes types ≤ n → ∀ b ∈ s', b.slot + b.ty.size ≤ n
  | [], types, slot, scope, s', n, ok, slots, _ => by
    cases types with
    | cons => simp [armScope] at ok
    | nil =>
      simp only [armScope, Option.some.injEq] at ok
      subst ok
      exact slots
  | binder :: rest, types, slot, scope, s', n, ok, slots, within => by
    cases types with
    | nil => simp [armScope] at ok
    | cons f more =>
      simp only [armScope] at ok
      split at ok
      · simp only [sizes] at within
        refine armScope_slots rest ok (fun b mem => ?_) (by omega)
        simp only [List.mem_cons] at mem
        rcases mem with rfl | mem
        · show slot + f.size ≤ n
          omega
        · exact slots b mem
      · simp at ok

theorem matchBinds : ∀ (binders : List Nat) (vs : List Value), binders.length = vs.length →
    Semantics.matchPatterns (binders.map Core.Pattern.bind) vs = some (binders.zip vs)
  | [], [], _ => by simp [Semantics.matchPatterns]
  | [], _ :: _, len => by simp at len
  | _ :: _, [], len => by simp at len
  | b :: bs, v :: vs, len => by
    simp only [List.length_cons, Nat.add_right_cancel_iff] at len
    simp [Semantics.matchPatterns, Semantics.matchPattern, matchBinds bs vs len]

theorem ofNat_ne {a b : Nat} (ha : a < 2 ^ 64) (hb : b < 2 ^ 64) (ne : a ≠ b) :
    BitVec.ofNat 64 a ≠ BitVec.ofNat 64 b := by
  intro h
  have := congrArg BitVec.toNat h
  simp only [BitVec.toNat_ofNat, Nat.mod_eq_of_lt ha, Nat.mod_eq_of_lt hb] at this
  exact ne this

theorem sizes_le_maxSize_of_mem : ∀ {variants : List (List SrcType)} {fs : List SrcType},
    fs ∈ variants → sizes fs ≤ maxSize variants
  | [], _, mem => by simp at mem
  | v :: rest, fs, mem => by
    simp only [List.mem_cons] at mem
    simp only [maxSize]
    rcases mem with rfl | mem
    · omega
    · have := sizes_le_maxSize_of_mem mem
      omega

/-- The tag tests pick the arm Core picks, and it stores that arm's value. -/
theorem lowerArms_sound {P : Core.Program} {mp : Program} {hp : Heap} (target : P.target = .x86_64)
    {scope frame st env} (corr : Corr scope frame st env) (fresh : st.Fresh)
    {slot dst eid : Nat} {ty : SrcType} (slots : ∀ b ∈ scope, b.slot + b.ty.size ≤ dst) :
    ∀ (arms : List SrcArm) {variants : List (List SrcType)} {k kv : Nat} {stmt : Stmt} {fuel : Nat}
      {fs : List SrcType} {vs : List Value} {v : Value} {st' : State},
      lowerArms scope slot dst ty k variants arms = some stmt → arms.length = variants.length →
      (∀ fs ∈ variants, ∀ b ∈ scope, b.slot < slot + 1 ∨ slot + 1 + sizes fs ≤ b.slot) →
      (∀ fs ∈ variants, slot + 1 + sizes fs ≤ dst) → k ≤ kv → variants[kv - k]? = some fs → kv < 2 ^ 64 →
      env slot = BitVec.ofNat 64 kv → FieldsHold fs vs env (slot + 1) →
      Semantics.evalMatchArms fuel P st (.enumeration eid kv vs) (coreArms eid k arms) = .done v st' →
      st'.Fresh ∧ Keeps st.nextCell st st' ∧ st'.locals = st.locals ∧
        ∃ xs, FlatValue ty v env xs ∧ Insens xs dst ∧
          ∀ d, Exec mp d env hp stmt (.normal (env.setFrom dst xs) hp) := by
  intro arms
  induction arms with
  | nil =>
    intro variants k kv stmt fuel fs vs v st' ok
    simp [lowerArms] at ok
  | cons arm rest ih =>
    intro variants k kv stmt fuel fs vs v st' ok len clear room le found bound tag payload run
    cases variants with
    | nil => simp [lowerArms] at ok
    | cons types more =>
      cases fuel with
      | zero => simp [Semantics.evalMatchArms] at run
      | succ fuel =>
        simp only [lowerArms, lowerArm] at ok
        split at ok
        · simp at ok
        rename_i xs valueOk
        simp only [coreArms, Semantics.evalMatchArms, Semantics.matchPattern] at run
        by_cases hk : k = kv
        · subst hk
          simp only [Nat.sub_self, List.getElem?_cons_zero, Option.some.injEq] at found
          subst found
          simp only [lowerArmValue] at valueOk
          split at valueOk
          · simp at valueOk
          rename_i s' scopeOk
          obtain ⟨frame', corr', fresh', keeps', blen⟩ := armScope_corr arm.binders scopeOk payload
            (clear _ (List.mem_cons_self ..)) corr fresh
          simp only [beq_self_eq_true, Bool.and_self, ↓reduceIte, matchBinds _ _ blen] at run
          cases armRun : evalExpr fuel P (st.bindLocals (arm.binders.zip vs)) arm.value.toCore with
          | done w st2 =>
            simp only [armRun, Semantics.restoreOutcomeLocals, Semantics.Outcome.done.injEq] at run
            obtain ⟨rfl, rfl⟩ := run
            have one : (armGuard (armScope arm.binders types (slot + 1) scope) arm.value).eval env = 1 := by
              rw [scopeOk]
              exact lowerValue_guard corr' target valueOk armRun
            obtain ⟨rfl, flat, shape⟩ := lowerValue_sound corr' target valueOk armRun
            have slots' := armScope_slots arm.binders scopeOk slots (room _ (List.mem_cons_self ..))
            refine ⟨restore_fresh fresh', keeps'.trans (restore_keeps _ _ _), rfl, xs, flat,
              Insens.below fun x mem => shape.below slots' x mem, fun d => ?_⟩
            split at ok
            · simp only [Option.some.injEq] at ok
              subst ok
              exact (assignFrom_exec xs dst .skip).checkThen one
            · split at ok
              · simp at ok
              · simp only [Option.some.injEq] at ok
                subst ok
                exact .ifTrue (by simp [Expr.eval, Word.holds, CmpOp.holdsU, tag])
                  ((assignFrom_exec xs dst .skip).checkThen one)
          | trapped => simp [armRun, Semantics.restoreOutcomeLocals] at run
          | exited => simp [armRun, Semantics.restoreOutcomeLocals] at run
          | outOfFuel => simp [armRun, Semantics.restoreOutcomeLocals] at run
        · have hne : (k == kv) = false := by simpa using hk
          simp only [beq_self_eq_true, Bool.true_and, hne, Bool.false_eq_true, ↓reduceIte] at run
          have found' : more[kv - (k + 1)]? = some fs := by
            rw [show kv - k = kv - (k + 1) + 1 by omega] at found
            simpa using found
          split at ok
          · have := (List.getElem?_eq_some_iff.mp found').1
            simp only [List.length_cons, List.length_nil] at len
            omega
          · split at ok
            · simp at ok
            rename_i o othersOk
            simp only [Option.some.injEq] at ok
            subst ok
            obtain ⟨fresh', keeps', locals', xs', flat', insens', exec'⟩ := ih othersOk (by simpa using len)
              (fun fs mem => clear fs (List.mem_cons_of_mem _ mem))
              (fun fs mem => room fs (List.mem_cons_of_mem _ mem)) (by omega) found' bound tag
              payload run
            have differ : BitVec.ofNat 64 kv ≠ BitVec.ofNat 64 k := ofNat_ne bound (by omega) (Ne.symm hk)
            exact ⟨fresh', keeps', locals', xs', flat', insens', fun d =>
              .ifFalse (by simp [Expr.eval, Word.holds, CmpOp.holdsU, tag, differ]) (exec' d)⟩

/-! ## Statements -/

/-! ## Heap bounds -/

theorem Exec.limit_normal {prog : Program} {d : Nat} {env : Env} {hp : Heap} {s : Stmt} {env' : Env}
    {hp' : Heap} (exec : Exec prog d env hp s (.normal env' hp')) : hp'.limit = hp.limit := exec.limit

/-- The cursor before a `let` body is within any bound the end is. -/
theorem tail_bound {sp : SrcProgram} {fuel : Nat} {st1 : State} {id : Nat} {v : Value} {body : SrcStmt}
    {c : Completion} {st' : State} (views : st1.i32ArrayViews = [])
    (run : Semantics.restoreOutcomeLocals st1 (execStmt fuel sp.toCore (st1.bindLocal id v) body.toCore) =
      .done c st') {L : Nat} (bound : st'.heap.nextAddress ≤ L) : st1.heap.nextAddress ≤ L :=
  Nat.le_trans ((let_grows (fun r => execStmt_grows (s := body) r) run) views).2 bound

/-- The cursor before a statement is within any bound the end is. -/
theorem stmt_bound {sp : SrcProgram} {fuel : Nat} {st1 : State} {s : SrcStmt} {c : Completion} {st' : State}
    (views : st1.i32ArrayViews = []) (run : execStmt fuel sp.toCore st1 s.toCore = .done c st') {L : Nat}
    (bound : st'.heap.nextAddress ≤ L) : st1.heap.nextAddress ≤ L :=
  Nat.le_trans ((execStmt_grows run) views).2 bound

section Statements

variable {sp : SrcProgram} {mp : Program} {fuel : Nat} {ret : SrcType} {scope : List Binding}
  {next : Nat} {stmt : Stmt} {frame : Nat → Nat} {base : Nat} {st : State} {env : Env}
  {c : Completion} {st' : State} {hp : Heap}

theorem stmt_nop (ok : SrcStmt.nop.lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fresh : st.Fresh)
    (hc : HeapCorr st.heap st.world hp) (run : execStmt (fuel + 1) sp.toCore st SrcStmt.nop.toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore, execStmt, Semantics.Outcome.done.injEq] at run
  obtain ⟨rfl, rfl⟩ := run
  exact ⟨fresh, Keeps.refl _ _, 0, _, .skip, .next corr hc⟩

theorem stmt_let (ih : StmtSound sp mp fuel) {id : Nat} {ty : SrcType} {value : SrcExpr}
    {body : SrcStmt} (ok : (SrcStmt.let id ty value body).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (hc : HeapCorr st.heap st.world hp) (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.let id ty value body).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerLet] at ok
  split at ok
  · simp at ok
  rename_i xs valueOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i v st1 valueRun
    refine Simulates.checked (lowerValue_guard corr (SrcProgram.target_toCore sp) valueOk valueRun) ?_
    obtain ⟨rfl, flat, shape⟩ := lowerValue_sound corr (SrcProgram.target_toCore sp) valueOk valueRun
    obtain ⟨fresh', keeps, d, out, exec, matched⟩ := let_tail ih (hp := hp) bodyOk corr fr fresh le
      (by rw [← flat.length]; exact shape.sized fr)
      (fr.agree fun j below => setFrom_outside xs next env j (.inl below))
      (flat.store (shape.insens_next fr)) hc run bound
    exact ⟨fresh', keeps, d, out, assignFrom_exec xs next exec, matched⟩
  all_goals simp at run

theorem stmt_letStruct (ih : StmtSound sp mp fuel) {id : Nat} {ty : SrcType} {fields : List SrcExpr}
    {body : SrcStmt}
    (ok : (SrcStmt.letStruct id ty fields body).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (hc : HeapCorr st.heap st.world hp) (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.letStruct id ty fields body).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerLet] at ok
  split at ok
  · simp at ok
  rename_i xs literalOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [Option.some.injEq] at ok
  subst ok
  cases ty with
  | i32 => simp [lowerLiteral] at literalOk
  | bool => simp [lowerLiteral] at literalOk
  | uint => simp [lowerLiteral] at literalOk
  | enum => simp [lowerLiteral] at literalOk
  | slice => simp [lowerLiteral] at literalOk
  | unit => simp [lowerLiteral] at literalOk
  | isize => simp [lowerLiteral] at literalOk
  | char => simp [lowerLiteral] at literalOk
  | sint => simp [lowerLiteral] at literalOk
  | ptr => simp [lowerLiteral] at literalOk
  | struct sid types =>
    simp only [lowerLiteral, lowerStructFields] at literalOk
    split at literalOk
    · simp at literalOk
    rename_i nonempty
    simp only [SrcStmt.toCore, execStmt] at run
    split at run
    · rename_i v st1 valueRun
      cases fuel with
      | zero => simp [evalExpr] at valueRun
      | succ k =>
        simp only [SrcType.typeId, evalExpr] at valueRun
        split at valueRun
        · rename_i vs st2 fieldsRun
          simp only [Semantics.Outcome.done.injEq] at valueRun
          obtain ⟨rfl, rfl⟩ := valueRun
          refine Simulates.checked (lowerArgs_guard corr (SrcProgram.target_toCore sp) literalOk fieldsRun) ?_
          obtain ⟨rfl, fieldsHold, len, shapes⟩ :=
            lowerArgs_sound corr (SrcProgram.target_toCore sp) literalOk fieldsRun
          have flat : FlatValue (.struct sid types) (.structure sid vs) env xs :=
            ⟨by simp [SrcType.size, len], .struct fieldsHold⟩
          have insens : Insens xs next := Insens.below fun x mem => by
            obtain ⟨ys, shape, inYs⟩ := shapes x mem
            exact shape.below fr.slots x inYs
          obtain ⟨fresh', keeps, d, out, exec, matched⟩ := let_tail ih (hp := hp) bodyOk corr fr fresh le
            (by simp only [SrcType.size]; omega)
            (fr.agree fun j below => setFrom_outside xs next env j (.inl below))
            (flat.store insens) hc run bound
          exact ⟨fresh', keeps, d, out, assignFrom_exec xs next exec, matched⟩
        all_goals simp at valueRun
    all_goals simp at run

theorem stmt_letCall (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    (ih : ∀ m ≤ fuel, StmtSound sp mp m) {id : Nat} {ty : SrcType} {callee : Nat}
    {args : List SrcExpr} {body : SrcStmt}
    (ok : (SrcStmt.letCall id ty callee args body).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (hc : HeapCorr st.heap st.world hp) (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.letCall id ty callee args body).toCore =
      .done c st') (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerLetCall] at ok
  split at ok
  · simp at ok
  rename_i es argsOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i v st1 callRun
    cases fuel with
    | zero => simp [evalExpr] at callRun
    | succ k =>
      refine Simulates.checked (lowerCall_guard corr argsOk callRun) ?_
      have views1 := (call_grows (grows sp (k + 1)) callRun fresh.2).1
      obtain ⟨fresh1, keeps1, locals1, sized, d1, rs, hp1, holds, len, hc1, callExec⟩ :=
        call_sound lowered (ih k (Nat.le_succ _)) corr fresh hc argsOk callRun (tail_bound views1 run bound)
      have corr1 := corr.keeps fresh keeps1 locals1
      obtain ⟨fresh', keeps', d2, out, exec, matched⟩ :=
        let_tail (ih (k + 1) (Nat.le_refl _)) bodyOk corr1 fr fresh1
          (Nat.le_trans le keeps1.next) sized (env' := env.setMany next rs)
          (fr.agree fun j below => by rw [setMany_eq, if_neg (by omega)])
          (setMany_holds holds len env next) hc1 run (by rw [(callExec next).limit_normal]; exact bound)
      exact ⟨fresh', (keeps1.lower le).trans keeps', max d1 d2, out,
        .seq ((callExec next).mono (Nat.le_max_left _ _)) (exec.mono (Nat.le_max_right _ _)), matched⟩
  all_goals simp at run

theorem stmt_letEnum (ih : StmtSound sp mp fuel) {id : Nat} {ty : SrcType} {variant : Nat}
    {payload : List SrcExpr} {body : SrcStmt}
    (ok : (SrcStmt.letEnum id ty variant payload body).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (hc : HeapCorr st.heap st.world hp) (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.letEnum id ty variant payload body).toCore =
      .done c st') (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerLet] at ok
  split at ok
  · simp at ok
  rename_i xs valueOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [Option.some.injEq] at ok
  subst ok
  cases ty with
  | i32 => simp [lowerEnumValue] at valueOk
  | bool => simp [lowerEnumValue] at valueOk
  | uint => simp [lowerEnumValue] at valueOk
  | struct => simp [lowerEnumValue] at valueOk
  | ptr => simp [lowerEnumValue] at valueOk
  | slice => simp [lowerEnumValue] at valueOk
  | unit => simp [lowerEnumValue] at valueOk
  | isize => simp [lowerEnumValue] at valueOk
  | char => simp [lowerEnumValue] at valueOk
  | sint => simp [lowerEnumValue] at valueOk
  | enum eid variants =>
    simp only [lowerEnumValue, lowerTagged] at valueOk
    split at valueOk
    case isFalse => simp at valueOk
    simp only [lowerVariant] at valueOk
    split at valueOk
    · simp at valueOk
    rename_i fs found
    simp only [lowerTag] at valueOk
    split at valueOk
    · simp at valueOk
    rename_i fxs fieldsOk
    simp only [Option.some.injEq] at valueOk
    subst valueOk
    simp only [SrcStmt.toCore, execStmt] at run
    split at run
    · rename_i v st1 valueRun
      cases fuel with
      | zero => simp [evalExpr] at valueRun
      | succ k =>
        simp only [SrcType.typeId, evalExpr] at valueRun
        split at valueRun
        · rename_i vs st2 fieldsRun
          simp only [Semantics.Outcome.done.injEq] at valueRun
          obtain ⟨rfl, rfl⟩ := valueRun
          refine Simulates.checked (lowerArgs_guard corr (SrcProgram.target_toCore sp) fieldsOk fieldsRun) ?_
          obtain ⟨rfl, fieldsHold, len, shapes⟩ :=
            lowerArgs_sound corr (SrcProgram.target_toCore sp) fieldsOk fieldsRun
          have insens : Insens (.lit (BitVec.ofNat 64 variant) :: fxs) next := Insens.below fun x mem => by
            simp only [List.mem_cons] at mem
            rcases mem with rfl | mem
            · trivial
            · obtain ⟨ys, shape, inYs⟩ := shapes x mem
              exact shape.below fr.slots x inYs
          have holds : (SrcType.enum eid variants).HoldsAt (.enumeration eid variant vs)
              (env.setFrom next (.lit (BitVec.ofNat 64 variant) :: fxs)) next := by
            refine .enum found ?_ (fieldsHold.congr fun i below => ?_)
            · simpa [Expr.eval] using setFrom_value _ next env insens 0 _ rfl
            · have : i < fxs.length := by rw [len]; exact below
              obtain ⟨x, xFound⟩ : ∃ x, fxs[i]? = some x := ⟨fxs[i], by simp [this]⟩
              rw [show next + 1 + i = next + (i + 1) by omega,
                setFrom_value _ next env insens (i + 1) x (by simpa using xFound), Nat.zero_add,
                entry_evalAll env fxs i x xFound]
          obtain ⟨fresh', keeps, d, out, exec, matched⟩ := let_tail ih (hp := hp) bodyOk corr fr fresh le
            (by simp only [SrcType.size]; omega)
            (fr.agree fun j below => setFrom_outside _ next env j (.inl below)) holds hc run bound
          exact ⟨fresh', keeps, d, out, assignFrom_exec _ next exec, matched⟩
        all_goals simp at valueRun
    all_goals simp at run

theorem stmt_letMatch (ih : StmtSound sp mp fuel) {id : Nat} {ty : SrcType} {scrutinee enumId : Nat}
    {arms : List SrcArm} {body : SrcStmt}
    (ok : (SrcStmt.letMatch id ty scrutinee enumId arms body).lower (sigs sp.funcs) sp.decls ret scope next =
      some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (hc : HeapCorr st.heap st.world hp) (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.letMatch id ty scrutinee enumId arms body).toCore =
      .done c st') (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerThen] at ok
  split at ok
  · simp at ok
  rename_i mstmt matchOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [lowerMatch] at matchOk
  split at matchOk
  · simp at matchOk
  rename_i b found
  simp only [lowerMatchOn] at matchOk
  split at matchOk
  · simp at matchOk
  · simp at matchOk
  · simp at matchOk
  · simp at matchOk
  case h_6 => simp at matchOk
  case h_7 => simp at matchOk
  case h_8 => simp at matchOk
  case h_9 => simp at matchOk
  case h_10 => simp at matchOk
  case h_11 => simp at matchOk
  rename_i eid variants hty
  simp only [lowerMatchArms] at matchOk
  split at matchOk
  case isFalse => simp at matchOk
  rename_i cond
  simp only [Bool.and_eq_true, decide_eq_true_eq] at cond
  obtain ⟨⟨⟨rfl, sized⟩, len⟩, few⟩ := cond
  have bmem := (lookup_mem found).1
  have room : ∀ fs ∈ variants, b.slot + 1 + sizes fs ≤ next := by
    intro fs mem
    have bound := sizes_le_maxSize_of_mem mem
    have := fr.slots b bmem
    rw [hty] at this
    simp only [SrcType.size] at this
    omega
  have clear : ∀ fs ∈ variants, ∀ b' ∈ scope, b'.slot < b.slot + 1 ∨ b.slot + 1 + sizes fs ≤ b'.slot := by
    intro fs mem b' mem'
    have bound := sizes_le_maxSize_of_mem mem
    by_cases same : b' = b
    · subst same
      omega
    · rcases fr.apart b' mem' b bmem same with h | h
      · have := fr.sized b' mem'
        omega
      · rw [hty] at h
        simp only [SrcType.size] at h
        omega
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i v st1 matchRun
    cases fuel with
    | zero => simp [evalExpr] at matchRun
    | succ k =>
      cases k with
      | zero => simp [evalExpr] at matchRun
      | succ k =>
        obtain ⟨w, localRun, holdsW⟩ := corr.local found k sp.toCore
        simp only [evalExpr] at matchRun
        simp only [evalExpr] at localRun
        rw [localRun] at matchRun
        rw [hty] at holdsW
        cases holdsW with
        | @enum _ _ kv fs vs _ _ fsFound tag payload =>
        have kvLt : kv < variants.length := (List.getElem?_eq_some_iff.mp fsFound).1
        have kvBound : kv < 2 ^ 64 := Nat.lt_trans kvLt (by omega)
        obtain ⟨fresh1, keeps1, locals1, xs, flat, insens, mexec⟩ :=
          lowerArms_sound (mp := mp) (SrcProgram.target_toCore sp) corr fresh fr.slots arms matchOk len
            clear room (Nat.zero_le _) (by simpa using fsFound) kvBound tag payload matchRun
        have corr1 := corr.keeps fresh keeps1 locals1
        have hc1 : HeapCorr st1.heap st1.world hp := by
          rw [(matchArms_same arms eid 0 matchRun).1, matchArms_world arms eid 0 matchRun]; exact hc
        obtain ⟨fresh', keeps', d, out, exec, matched⟩ :=
          let_tail ih (hp := hp) bodyOk corr1 fr fresh1 (Nat.le_trans le keeps1.next)
            sized (env' := env.setFrom next xs)
            (fr.agree fun j below => setFrom_outside xs next env j (.inl below))
            (flat.store insens) hc1 run bound
        exact ⟨fresh', (keeps1.lower le).trans keeps', d, out, .seq (mexec d) exec, matched⟩
  all_goals simp at run

theorem restore_heap (caller st : State) : (Semantics.restoreLocals caller st).heap = st.heap := rfl

theorem restore_world (caller st : State) : (Semantics.restoreLocals caller st).world = st.world := rfl

theorem restore_bindNil (st : State) : Semantics.restoreLocals st (st.bindLocals []) = st := rfl

/-- The tag test of a match arm statement binds nothing, and is true just
when the scrutinee is the variant and its payload fits the patterns. -/
theorem armTest_run {P : Core.Program} {st : State} {sc e kv variant : Nat} {vs : List Value}
    {pats : List Core.Pattern}
    (localRun : ∀ k, evalExpr (k + 1) P st (.local sc) = .done (.enumeration e kv vs) st)
    (noBinds : ∀ bs, Semantics.matchPatterns pats vs = some bs → bs = [])
    {fuel : Nat} {r : Value} {st1 : State}
    (run : evalExpr fuel P st (.matchValue (.local sc)
      [(.enumVariant e variant pats, .value (.boolean true)), (.wildcard, .value (.boolean false))]) =
      .done r st1) :
    st1 = st ∧ (r = .boolean true ↔ variant = kv ∧ (Semantics.matchPatterns pats vs).isSome = true) ∧
      (r = .boolean true ∨ r = .boolean false) := by
  rcases fuel with _ | _ | j
  · simp [evalExpr] at run
  · simp [evalExpr] at run
  · have lr := localRun j
    simp only [evalExpr] at lr run
    rw [lr] at run
    simp only [Semantics.evalMatchArms, Semantics.matchPattern, beq_self_eq_true, Bool.true_and] at run
    have otherwise : Semantics.evalMatchArms j P st (.enumeration e kv vs)
        [(.wildcard, .value (.boolean false))] = .done r st1 → st1 = st ∧ r = .boolean false := by
      intro arms
      rcases j with _ | _ | i
      · simp [Semantics.evalMatchArms] at arms
      · simp [Semantics.evalMatchArms, Semantics.matchPattern, evalExpr, Semantics.restoreOutcomeLocals] at arms
      · simp only [Semantics.evalMatchArms, Semantics.matchPattern, evalExpr, Semantics.restoreOutcomeLocals,
          Semantics.Outcome.done.injEq] at arms
        exact ⟨arms.2.symm.trans (restore_bindNil st), arms.1.symm⟩
    by_cases hk : variant = kv
    · subst hk
      simp only [beq_self_eq_true, ↓reduceIte] at run
      cases m : Semantics.matchPatterns pats vs with
      | none =>
        rw [m] at run
        obtain ⟨rfl, rfl⟩ := otherwise run
        simp
      | some bs =>
        rw [m] at run
        obtain rfl := noBinds bs m
        rcases j with _ | j
        · simp [evalExpr, Semantics.restoreOutcomeLocals] at run
        · simp only [evalExpr, Semantics.restoreOutcomeLocals, Semantics.Outcome.done.injEq] at run
          obtain ⟨rfl, rfl⟩ := run
          exact ⟨restore_bindNil st, by simp, .inl rfl⟩
    · have ne : (variant == kv) = false := by simpa using hk
      simp only [ne, Bool.false_eq_true, ↓reduceIte] at run
      obtain ⟨rfl, rfl⟩ := otherwise run
      simp [hk]

/-- The tag test of a match arm statement completes. -/
theorem armTest_done {P : Core.Program} {st : State} {sc e kv variant : Nat} {vs : List Value}
    {pats : List Core.Pattern}
    (localRun : ∀ k, evalExpr (k + 1) P st (.local sc) = .done (.enumeration e kv vs) st)
    (noBinds : ∀ bs, Semantics.matchPatterns pats vs = some bs → bs = []) (j : Nat) :
    ∃ r, evalExpr (j + 1 + 1 + 1 + 1) P st (.matchValue (.local sc)
      [(.enumVariant e variant pats, .value (.boolean true)), (.wildcard, .value (.boolean false))]) =
      .done r st := by
  have lr := localRun (j + 1 + 1)
  simp only [evalExpr] at lr ⊢
  simp only [lr]
  simp only [Semantics.evalMatchArms, Semantics.matchPattern, beq_self_eq_true, Bool.true_and]
  by_cases hk : variant = kv
  · subst hk
    simp only [beq_self_eq_true, ↓reduceIte]
    cases m : Semantics.matchPatterns pats vs with
    | none =>
      simp only [Semantics.evalMatchArms, Semantics.matchPattern, evalExpr, Semantics.restoreOutcomeLocals]
      exact ⟨_, rfl⟩
    | some bs =>
      obtain rfl := noBinds bs m
      simp only [evalExpr, Semantics.restoreOutcomeLocals]
      exact ⟨_, rfl⟩
  · have ne : (variant == kv) = false := by simpa using hk
    simp only [ne, Bool.false_eq_true, ↓reduceIte, Semantics.evalMatchArms, Semantics.matchPattern, evalExpr,
      Semantics.restoreOutcomeLocals]
    exact ⟨_, rfl⟩

/-- The copy of a match arm statement's payload, from the binder's value. -/
theorem armBind_run {P : Core.Program} {st : State} {sc e variant binder : Nat} {pv : Value}
    (localRun : ∀ k, evalExpr (k + 1) P st (.local sc) = .done (.enumeration e variant [pv]) st)
    {k : Nat} {v : Value} {st3 : State}
    (bindRun : evalExpr k P (st.bindLocals [(binder, pv)]) (.local binder) = .done v st3) :
    evalExpr (k + 1 + 1) P st (.matchValue (.local sc) [(.enumVariant e variant [.bind binder], .local binder)]) =
      .done v (Semantics.restoreLocals st st3) := by
  have lr := localRun k
  simp only [evalExpr] at lr ⊢
  simp only [lr]
  simp only [Semantics.evalMatchArms, Semantics.matchPattern, beq_self_eq_true, Bool.and_self, ↓reduceIte,
    Semantics.matchPatterns, List.append_nil, bindRun, Semantics.restoreOutcomeLocals]

theorem stmt_matchArm (below : ∀ m ≤ fuel, StmtSound sp mp m) {scrutinee enumId variant binder : Nat}
    {binds : Bool} {ty : SrcType} {body rest : SrcStmt}
    (ok : (SrcStmt.matchArm scrutinee enumId variant binds binder ty body rest).lower (sigs sp.funcs) sp.decls ret
      scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (hc : HeapCorr st.heap st.world hp) (run : execStmt (fuel + 1) sp.toCore st
      (SrcStmt.matchArm scrutinee enumId variant binds binder ty body rest).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  obtain ⟨b, variants, fields, vs, bstmt, rstmt, found, hty, fieldsFound, few, payloadOk, bodyOk, restOk, rfl⟩ :=
    matchArm_lower_inv ok
  have bmem := (lookup_mem found).1
  have variantLt : variant < variants.length := (List.getElem?_eq_some_iff.mp fieldsFound).1
  have fieldsMem : fields ∈ variants := List.mem_of_getElem? fieldsFound
  have room : b.slot + 1 + sizes fields ≤ next := by
    have bound := sizes_le_maxSize_of_mem fieldsMem
    have := fr.slots b bmem
    rw [hty] at this
    simp only [SrcType.size] at this
    omega
  have clear : ∀ b' ∈ scope, b'.slot < b.slot + 1 ∨ b.slot + 1 + sizes fields ≤ b'.slot := by
    intro b' mem'
    have bound := sizes_le_maxSize_of_mem fieldsMem
    by_cases same : b' = b
    · subst same
      omega
    · rcases fr.apart b' mem' b bmem same with h | h
      · have := fr.sized b' mem'
        omega
      · rw [hty] at h
        simp only [SrcType.size] at h
        omega
  have shape := armPayload_shape payloadOk
  obtain ⟨w, entry, holdsW⟩ := corr.values b bmem
  have localRun : ∀ k, evalExpr (k + 1) sp.toCore st (.local scrutinee) = .done w st := fun k => by
    simp only [evalExpr, corr.cellId, found, Option.map_some, entry]
  rw [hty] at holdsW
  cases holdsW with
  | @enum _ _ kv fs pvs _ _ fsFound tag payload =>
  have kvLt : kv < variants.length := (List.getElem?_eq_some_iff.mp fsFound).1
  -- When the tag is the variant, the payload fits the test's patterns.
  have fits : variant = kv → (Semantics.matchPatterns (if binds then [.wildcard] else []) pvs).isSome = true := by
    intro hk
    subst hk
    have same : fs = fields := by simpa [fsFound] using fieldsFound
    subst same
    rcases shape with ⟨u, rfl, _⟩ | ⟨u, _, s', scopeOk, _⟩
    · cases payload
      simp [u, Semantics.matchPatterns]
    · obtain ⟨_, _, _, _, blen⟩ := armScope_corr [binder] scopeOk payload clear corr fresh
      rcases pvs with _ | ⟨pv, _ | ⟨pv', more⟩⟩
      · simp at blen
      · simp [u, Semantics.matchPatterns, Semantics.matchPattern]
      · simp at blen
  simp only [SrcStmt.toCore] at run
  generalize hpats : (if binds then [Core.Pattern.wildcard] else []) = pats at run fits
  generalize hthen : (if binds then .letLocal binder ty.toCore (.matchValue (.local scrutinee) [(.enumVariant enumId variant [.bind binder], .local binder)]) body.toCore else body.toCore) = T at run
  have noBinds : ∀ bs, Semantics.matchPatterns pats pvs = some bs → bs = [] := by
    intro bs m
    rw [← hpats] at m
    split at m <;> rcases pvs with _ | ⟨v, _ | ⟨v', more⟩⟩ <;>
      simp [Semantics.matchPatterns, Semantics.matchPattern] at m <;> simp_all
  have differ : variant ≠ kv → BitVec.ofNat 64 kv ≠ BitVec.ofNat 64 variant := fun hk =>
    ofNat_ne (Nat.lt_trans kvLt (by omega)) (Nat.lt_trans variantLt (by omega)) (Ne.symm hk)
  simp only [execStmt] at run
  split at run
  · -- the variant: bind the payload and run the body
    rename_i st1 testRun
    obtain ⟨hst, picked, _⟩ := armTest_run localRun noBinds testRun
    subst st1
    obtain ⟨rfl, _⟩ := picked.mp rfl
    have same : fs = fields := by simpa [fsFound] using fieldsFound
    subst same
    have test : (Expr.compare Word.u64 CmpOp.eq (Expr.var b.slot) (Expr.lit (BitVec.ofNat 64 variant))).eval env ≠ 0 := by
      simp [Expr.eval, Word.holds, CmpOp.holdsU, tag]
    rcases shape with ⟨u, rfl, rfl⟩ | ⟨u, sized, s', scopeOk, valueOk⟩
    · simp only [u, Bool.false_eq_true, ↓reduceIte] at hthen
      subst hthen
      simp only [armBodyScope, u, Bool.not_false, ↓reduceIte] at bodyOk
      obtain ⟨fresh', keeps, d, out, exec, matched⟩ :=
        below fuel (Nat.le_refl _) (hp := hp) bodyOk corr (fr.mono (Nat.le_add_right _ _)) fresh le hc run bound
      exact ⟨fresh', keeps, d, out, .ifTrue test exec, matched⟩
    · simp only [u, ↓reduceIte] at hthen
      subst hthen
      simp only [armBodyScope, u, Bool.not_true, Bool.false_eq_true, ↓reduceIte] at bodyOk
      obtain ⟨frame', corr', fresh', keeps', blen⟩ := armScope_corr [binder] scopeOk payload clear corr fresh
      have mb : Semantics.matchPatterns [.bind binder] pvs = some ([binder].zip pvs) :=
        matchBinds [binder] pvs blen
      rcases fuel with _ | f1
      · simp [execStmt] at run
      simp only [execStmt] at run
      split at run
      · rename_i v st2 initRun
        rcases f1 with _ | _ | f3
        · simp [evalExpr] at initRun
        · simp [evalExpr] at initRun
        have lr := localRun f3
        simp only [evalExpr] at lr initRun
        rw [lr] at initRun
        simp only [Semantics.evalMatchArms, Semantics.matchPattern, beq_self_eq_true, Bool.and_self,
          ↓reduceIte, mb] at initRun
        cases armRun : evalExpr f3 sp.toCore (st.bindLocals ([binder].zip pvs)) (SrcExpr.local binder).toCore with
        | done v' st3 =>
          simp only [SrcExpr.toCore] at armRun
          simp only [armRun, Semantics.restoreOutcomeLocals, Semantics.Outcome.done.injEq] at initRun
          obtain ⟨rfl, rfl⟩ := initRun
          obtain ⟨rfl, flat, vshape⟩ := lowerValue_sound corr' (SrcProgram.target_toCore sp) valueOk armRun
          have slots' := armScope_slots [binder] scopeOk fr.slots room
          have insens : Insens vs next := Insens.below fun x mem => vshape.below slots' x mem
          have keeps1 := keeps'.trans (restore_keeps st.nextCell st _)
          have corr1 := corr.keeps fresh keeps1 rfl
          obtain ⟨fresh'', keeps'', d, out, exec, matched⟩ :=
            let_tail (below _ (Nat.le_succ _)) (hp := hp) bodyOk corr1 fr (restore_fresh fresh')
              (Nat.le_trans le keeps1.next) sized (env' := env.setFrom next vs)
              (fr.agree fun j below => setFrom_outside vs next env j (.inl below))
              (flat.store insens) (by rw [restore_heap, restore_world, (bindLocals_same _ st).1, bindLocals_world]; exact hc) run bound
          exact ⟨fresh'', (keeps1.lower le).trans keeps'', d, out,
            .ifTrue test (assignFrom_exec vs next exec), matched⟩
        | trapped =>
          simp only [SrcExpr.toCore] at armRun
          simp [armRun, Semantics.restoreOutcomeLocals] at initRun
        | exited =>
          simp only [SrcExpr.toCore] at armRun
          simp [armRun, Semantics.restoreOutcomeLocals] at initRun
        | outOfFuel =>
          simp only [SrcExpr.toCore] at armRun
          simp [armRun, Semantics.restoreOutcomeLocals] at initRun
      all_goals simp at run
  · -- another variant: run the rest
    rename_i st1 testRun
    obtain ⟨hst, picked, _⟩ := armTest_run localRun noBinds testRun
    subst st1
    have hk : variant ≠ kv := fun hk => by
      have := picked.mpr ⟨hk, fits hk⟩
      simp at this
    obtain ⟨fresh', keeps, d, out, exec, matched⟩ :=
      below fuel (Nat.le_refl _) (hp := hp) restOk corr fr fresh le hc run bound
    exact ⟨fresh', keeps, d, out, .ifFalse (by simp [Expr.eval, Word.holds, CmpOp.holdsU, tag, differ hk]) exec,
      matched⟩
  all_goals simp at run

theorem stmt_set {id : Nat} {value : SrcExpr}
    (ok : (SrcStmt.set id value).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (hc : HeapCorr st.heap st.world hp) (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.set id value).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerSet] at ok
  split at ok
  · simp at ok
  rename_i b found
  simp only [lowerSetValues] at ok
  split at ok
  · simp at ok
  rename_i xs valueOk
  simp only [Option.some.injEq] at ok
  subst ok
  have bmem := (lookup_mem found).1
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i u st3 assignRun
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    cases fuel with
    | zero => simp [evalExpr] at assignRun
    | succ k =>
      obtain ⟨rv, st2, valueRun, rfl⟩ := assign_step corr found assignRun fun valueRun => by
        obtain ⟨rfl, _⟩ := lowerValue_sound corr (SrcProgram.target_toCore sp) valueOk valueRun
        exact fresh.2
      refine Simulates.checked (lowerValue_guard corr (SrcProgram.target_toCore sp) valueOk valueRun) ?_
      obtain ⟨rfl, flat, shape⟩ := lowerValue_sound corr (SrcProgram.target_toCore sp) valueOk valueRun
      have stored := flat.store (shape.insens_self fr bmem flat.length)
      refine ⟨assigned_fresh fresh _ _, assigned_keeps (fr.above b bmem) _ _, 0, _,
        assignFrom_exec xs b.slot .skip, .next (corr.assign fr bmem (fun j away => ?_) stored) hc⟩
      exact setFrom_outside xs b.slot env j (by rw [flat.length]; exact away)
  all_goals simp at run

theorem stmt_setField {id index : Nat} {value : SrcExpr}
    (ok : (SrcStmt.setField id index value).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (hc : HeapCorr st.heap st.world hp) (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.setField id index value).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerSetField] at ok
  split at ok
  · simp at ok
  rename_i b found
  simp only [lowerSetFieldOf] at ok
  split at ok
  · simp at ok
  · simp at ok
  · simp at ok
  case h_5 => simp at ok
  case h_6 => simp at ok
  case h_7 => simp at ok
  case h_8 => simp at ok
  case h_9 => simp at ok
  case h_10 => simp at ok
  case h_11 => simp at ok
  rename_i sid types hty
  simp only [lowerSetFieldAt] at ok
  split at ok
  · simp at ok
  rename_i f fieldFound
  split at ok
  case isFalse => simp at ok
  rename_i scalar
  simp only [lowerSetValue] at ok
  split at ok
  · simp at ok
  rename_i x valueOk
  simp only [Option.some.injEq] at ok
  subst ok
  have bmem := (lookup_mem found).1
  obtain ⟨v0, entry, holds0⟩ := corr.values b bmem
  rw [hty] at holds0
  cases holds0 with
  | @struct _ _ vs _ _ fieldsHold =>
  obtain ⟨old, got, _⟩ := fieldsHold.get fieldFound
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i u st3 assignRun
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    cases fuel with
    | zero => simp [evalExpr] at assignRun
    | succ k =>
      obtain ⟨rv, valueRun, rfl⟩ := field_assign_step corr found entry got fresh.2 assignRun
        fun valueRun => (lowerAs_sound corr (SrcProgram.target_toCore sp) valueOk valueRun).1
      refine Simulates.checked (lowerAs_guard corr (SrcProgram.target_toCore sp) valueOk valueRun) ?_
      obtain ⟨_, holds⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) valueOk valueRun
      have inRange := fieldOffset_lt fieldFound
      have one := SrcType.size_scalar scalar
      refine ⟨assigned_fresh fresh _ _, assigned_keeps (fr.above b bmem) _ _, 0, _, .assign,
        .next (corr.assign fr bmem (fun j away => ?_) ?_) hc⟩
      · simp only [Env.set]
        rw [hty] at away
        simp only [SrcType.size] at away
        rw [if_neg (by omega)]
      · rw [hty]
        exact .struct (fieldsHold.set fieldFound scalar holds)
  all_goals simp at run

theorem stmt_setCall (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs)
    (ih : ∀ m ≤ fuel, StmtSound sp mp m) {id callee : Nat} {args : List SrcExpr}
    (ok : (SrcStmt.setCall id callee args).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (hc : HeapCorr st.heap st.world hp) (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.setCall id callee args).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerSetCall] at ok
  split at ok
  · simp at ok
  rename_i b found
  simp only [lowerSetCallArgs] at ok
  split at ok
  · simp at ok
  rename_i es argsOk
  simp only [Option.some.injEq] at ok
  subst ok
  have bmem := (lookup_mem found).1
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i u st3 assignRun
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    cases fuel with
    | zero => simp [evalExpr] at assignRun
    | succ k =>
      obtain ⟨rv, st2, callRun, rfl⟩ := assign_step corr found assignRun fun callRun =>
        (call_grows (grows sp k) callRun fresh.2).1
      cases k with
      | zero => simp [evalExpr] at callRun
      | succ j =>
      refine Simulates.checked (lowerCall_guard corr argsOk callRun) ?_
      obtain ⟨fresh2, keeps2, locals2, -, d, rs, hp2, holds, len, hc2, callExec⟩ :=
        call_sound lowered (ih j (by omega)) corr fresh hc argsOk callRun bound
      have corr2 := corr.keeps fresh keeps2 locals2
      refine ⟨assigned_fresh fresh2 _ _, (keeps2.lower le).trans (assigned_keeps (fr.above b bmem) _ _),
        d, _, callExec b.slot,
        .next (corr2.assign fr bmem (fun j away => ?_) (setMany_holds holds len env b.slot)) hc2⟩
      rw [setMany_eq, if_neg (by omega)]
  all_goals simp at run

theorem stmt_then (ih : StmtSound sp mp fuel) {first second : SrcStmt}
    (ok : (SrcStmt.then first second).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (hc : HeapCorr st.heap st.world hp) (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.then first second).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerThen] at ok
  split at ok
  · simp at ok
  rename_i a firstOk
  split at ok
  · simp at ok
  rename_i b secondOk
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i mid firstRun
    have views1 := (execStmt_grows firstRun fresh.2).1
    obtain ⟨fresh1, keeps1, d1, out1, exec1, matched1⟩ :=
      ih (hp := hp) firstOk corr fr fresh le hc firstRun (stmt_bound views1 run bound)
    cases matched1 with
    | next corr1 hc1 =>
      obtain ⟨fresh2, keeps2, d2, out2, exec2, matched2⟩ :=
        ih secondOk corr1 fr fresh1 (Nat.le_trans le keeps1.next) hc1 run
          (by rw [exec1.limit_normal]; exact bound)
      exact ⟨fresh2, keeps1.trans keeps2, max d1 d2, out2,
        .seq (exec1.mono (Nat.le_max_left _ _)) (exec2.mono (Nat.le_max_right _ _)), matched2⟩
  · rename_i completion mid notNext firstRun
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    obtain ⟨fresh1, keeps1, d1, out1, exec1, matched1⟩ := ih (hp := hp) firstOk corr fr fresh le hc firstRun bound
    cases matched1 with
    | next => exact absurd rfl notNext
    | returned holds len hc1 => exact ⟨fresh1, keeps1, d1, _, .seqReturned exec1, .returned holds len hc1⟩
    | broke corr1 hc1 => exact ⟨fresh1, keeps1, d1, _, .seqBroke exec1, .broke corr1 hc1⟩
    | continued corr1 hc1 => exact ⟨fresh1, keeps1, d1, _, .seqContinued exec1, .continued corr1 hc1⟩
  all_goals simp at run

theorem stmt_if (ih : StmtSound sp mp fuel) {condition : SrcExpr} {thenBranch elseBranch : SrcStmt}
    (ok : (SrcStmt.if condition thenBranch elseBranch).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (hc : HeapCorr st.heap st.world hp) (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.if condition thenBranch elseBranch).toCore =
      .done c st') (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerIf] at ok
  split at ok
  · simp at ok
  rename_i x condOk
  split at ok
  · simp at ok
  rename_i ts thenOk
  split at ok
  · simp at ok
  rename_i es elseOk
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i mid condRun
    obtain ⟨rfl, y, hy, bits⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) condOk condRun
    cases hy
    refine Simulates.checked (lowerAs_guard corr (SrcProgram.target_toCore sp) condOk condRun) ?_
    obtain ⟨fresh', keeps, d, out, exec, matched⟩ := ih (hp := hp) thenOk corr fr fresh le hc run bound
    exact ⟨fresh', keeps, d, out, .ifTrue (by rw [bits]; decide) exec, matched⟩
  · rename_i mid condRun
    obtain ⟨rfl, y, hy, bits⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) condOk condRun
    cases hy
    refine Simulates.checked (lowerAs_guard corr (SrcProgram.target_toCore sp) condOk condRun) ?_
    obtain ⟨fresh', keeps, d, out, exec, matched⟩ := ih (hp := hp) elseOk corr fr fresh le hc run bound
    exact ⟨fresh', keeps, d, out, .ifFalse (by rw [bits]; decide) exec, matched⟩
  · rename_i w mid notTrue notFalse condRun
    obtain ⟨rfl, y, rfl, _⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) condOk condRun
    cases y <;> simp_all
  all_goals simp at run

theorem stmt_while (ih : StmtSound sp mp fuel) {condition : SrcExpr} {body : SrcStmt}
    (ok : (SrcStmt.while condition body).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (hc : HeapCorr st.heap st.world hp) (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.while condition body).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  have whileOk := ok
  simp only [SrcStmt.lower, lowerWhile] at ok
  split at ok
  · simp at ok
  rename_i x condOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i mid condRun
    have one := lowerAs_guard corr (SrcProgram.target_toCore sp) condOk condRun
    obtain ⟨rfl, y, hy, bits⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) condOk condRun
    cases hy
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    exact ⟨fresh, Keeps.refl _ _, 0, _, Exec.whileLoop_done one (by rw [bits]; decide), .next corr hc⟩
  · rename_i mid condRun
    have one := lowerAs_guard corr (SrcProgram.target_toCore sp) condOk condRun
    obtain ⟨rfl, y, hy, bits⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) condOk condRun
    cases hy
    have condTrue : x.eval env ≠ 0 := by rw [bits]; decide
    split at run
    · rename_i completed bodyRun
      obtain ⟨fresh1, keeps1, d1, out1, exec1, matched1⟩ := ih (hp := hp) bodyOk corr fr fresh le hc bodyRun
        (stmt_bound (execStmt_grows bodyRun fresh.2).1 (s := .while condition body) run bound)
      cases matched1 with
      | next corr1 hc1 =>
        obtain ⟨fresh2, keeps2, d2, out2, exec2, matched2⟩ :=
          ih whileOk corr1 fr fresh1 (Nat.le_trans le keeps1.next) hc1 run
            (by rw [exec1.limit_normal]; exact bound)
        exact ⟨fresh2, keeps1.trans keeps2, max d1 d2, out2,
          Exec.whileLoop_next one condTrue (.inl (exec1.mono (Nat.le_max_left _ _))) (exec2.mono (Nat.le_max_right _ _)),
          matched2⟩
    · rename_i completed bodyRun
      obtain ⟨fresh1, keeps1, d1, out1, exec1, matched1⟩ := ih (hp := hp) bodyOk corr fr fresh le hc bodyRun
        (stmt_bound (execStmt_grows bodyRun fresh.2).1 (s := .while condition body) run bound)
      cases matched1 with
      | continued corr1 hc1 =>
        obtain ⟨fresh2, keeps2, d2, out2, exec2, matched2⟩ :=
          ih whileOk corr1 fr fresh1 (Nat.le_trans le keeps1.next) hc1 run
            (by have limit := exec1.limit; simp only [Outcome.heap] at limit; rw [limit]; exact bound)
        exact ⟨fresh2, keeps1.trans keeps2, max d1 d2, out2,
          Exec.whileLoop_next one condTrue (.inr (exec1.mono (Nat.le_max_left _ _))) (exec2.mono (Nat.le_max_right _ _)),
          matched2⟩
    · rename_i completed bodyRun
      simp only [Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, rfl⟩ := run
      obtain ⟨fresh1, keeps1, d1, out1, exec1, matched1⟩ := ih (hp := hp) bodyOk corr fr fresh le hc bodyRun bound
      cases matched1 with
      | broke corr1 hc1 => exact ⟨fresh1, keeps1, d1, _, Exec.whileLoop_broke one condTrue exec1, .next corr1 hc1⟩
    · rename_i value completed bodyRun
      simp only [Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, rfl⟩ := run
      obtain ⟨fresh1, keeps1, d1, out1, exec1, matched1⟩ := ih (hp := hp) bodyOk corr fr fresh le hc bodyRun bound
      cases matched1 with
      | returned holds len hc1 =>
        exact ⟨fresh1, keeps1, d1, _, Exec.whileLoop_returned one condTrue exec1, .returned holds len hc1⟩
    all_goals simp at run
  · rename_i w mid notFalse notTrue condRun
    obtain ⟨rfl, y, rfl, _⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) condOk condRun
    cases y <;> simp_all
  all_goals simp at run

theorem stmt_return {value : SrcExpr}
    (ok : (SrcStmt.return value).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fresh : st.Fresh)
    (hc : HeapCorr st.heap st.world hp) (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.return value).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerReturn] at ok
  split at ok
  · simp at ok
  rename_i xs valueOk
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i v mid valueRun
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    refine Simulates.checked (lowerValue_guard corr (SrcProgram.target_toCore sp) valueOk valueRun) ?_
    obtain ⟨rfl, flat, -⟩ := lowerValue_sound corr (SrcProgram.target_toCore sp) valueOk valueRun
    exact ⟨fresh, Keeps.refl _ _, 0, _, .ret, .returned flat.holds (by rw [evalAll_length, flat.length]) hc⟩
  all_goals simp at run

theorem stmt_letAlloc (ih : StmtSound sp mp fuel) {id shift : Nat} {size : SrcExpr} {body : SrcStmt}
    (ok : (SrcStmt.letAlloc id size shift body).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell) (hc : HeapCorr st.heap st.world hp)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.letAlloc id size shift body).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerAlloc] at ok
  split at ok
  case isFalse => simp at ok
  split at ok
  · simp at ok
  rename_i x sizeOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i v st1 valueRun
    cases fuel with
    | zero => simp [evalExpr] at valueRun
    | succ k =>
      simp only [evalExpr] at valueRun
      split at valueRun
      · rename_i n afterSize sizeRun
        refine Simulates.checked (lowerAs_guard corr (SrcProgram.target_toCore sp) sizeOk sizeRun) ?_
        obtain ⟨rfl, holdsN, -⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) sizeOk sizeRun
        split at valueRun
        · rename_i a afterAlign alignRun
          have := eval_value_state alignRun
          subst this
          have := eval_value alignRun
          simp only [Value.unsigned.injEq, true_and] at this
          subst this
          split at valueRun
          · rename_i p heap' allocated
            simp only [Semantics.Outcome.done.injEq] at valueRun
            obtain ⟨rfl, rfl⟩ := valueRun
            simp only [UintTy.toCore, Value.unsigned.injEq, true_and] at holdsN
            subst holdsN
            obtain ⟨rfl, grown, hc'⟩ := hc.allocate allocated
            have tail := tail_bound (st1 := { afterAlign with heap := heap' }) fresh.2 run bound
            simp only [grown] at tail
            have small := hc.small
            have room : alignUp hp.cursor shift + ((atLeastOne x).eval env).toNat ≤ hp.limit := by
              rw [atLeastOne_eval]; exact tail
            have step := Exec.alloc (prog := mp) (depth := 0) (env := env) (target := next) room
            obtain ⟨fresh', keeps, d, out, exec, matched⟩ := let_tail ih (ty := .ptr) (st := { afterAlign with heap := heap' })
              (v := .pointer (alignUp hp.cursor shift))
              (env' := env.set next (BitVec.ofNat 64 (alignUp hp.cursor shift)))
              (hp := { hp with cursor := alignUp hp.cursor shift + max (x.eval env).toNat 1 }) bodyOk
              (corr.cells_congr rfl fun _ _ => rfl) fr fresh le Nat.one_pos
              (fr.agree fun j below => by simp only [Env.set]; rw [if_neg (by omega)])
              (.ptr (by
                simp only [SrcType.Holds, Env.set, if_pos, Value.pointer.injEq, BitVec.toNat_ofNat]
                exact (Nat.mod_eq_of_lt (by omega)).symm))
              hc' run bound
            refine ⟨fresh', ⟨keeps.cells, keeps.next⟩, d, out, .seq ?_ exec, matched⟩
            have step := Exec.alloc (prog := mp) (depth := d) (env := env) (target := next) room
            rw [atLeastOne_eval] at step
            exact step
          · rename_i heap' exhausted
            exact (hc.allocated _ _ exhausted).elim
          · simp at valueRun
        all_goals simp at valueRun
      all_goals simp at valueRun
  all_goals simp at run

/-- A lowered pointer-plus-offset address of a Core load or store. -/
theorem address_sound {P : Core.Program} (target : P.target = .x86_64) {k : Nat}
    {pointer offset : SrcExpr} {rest : List Core.Expr} {xp xo : Expr} {pv ov : Nat} {more : List Value}
    {mid : State} (corr : Corr scope frame st env)
    (pOk : lowerAs scope pointer .ptr = some xp) (oOk : lowerAs scope offset (.uint .usize) = some xo)
    (run : evalExprs k P st (pointer.toCore :: offset.toCore :: rest) =
      .done (.pointer pv :: .unsigned .usize ov :: more) mid)
    (small : pv + ov < 2 ^ 64) :
    ∃ k' mid', evalExprs k' P st rest = .done more mid' ∧
      ((Expr.binary Word.u64 BinOp.add xp xo).eval env).toNat = pv + ov := by
  obtain ⟨k1, v1, vs1, mid1, pRun, rest1, eq1⟩ := evalExprs_cons run
  simp only [List.cons.injEq] at eq1
  obtain ⟨rfl, rfl⟩ := eq1
  obtain ⟨rfl, hpv⟩ := lowerAs_sound corr target pOk pRun
  obtain ⟨k2, v2, vs2, mid2, oRun, rest2, eq2⟩ := evalExprs_cons rest1
  simp only [List.cons.injEq] at eq2
  obtain ⟨rfl, rfl⟩ := eq2
  obtain ⟨rfl, hov, -⟩ := lowerAs_sound corr target oOk oRun
  simp only [SrcType.Holds, Value.pointer.injEq] at hpv
  simp only [UintTy.toCore, Value.unsigned.injEq, true_and] at hov
  refine ⟨k2, mid, rest2, ?_⟩
  simp only [Expr.eval, Word.apply, BinOp.apply, BitVec.toNat_add, ← hpv, ← hov]
  exact Nat.mod_eq_of_lt small

theorem stmt_letLoad (ih : StmtSound sp mp fuel) {id : Nat} {pointer offset : SrcExpr} {body : SrcStmt}
    (ok : (SrcStmt.letLoad id pointer offset body).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell) (hc : HeapCorr st.heap st.world hp)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.letLoad id pointer offset body).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  cases pOk : lowerAs scope pointer .ptr with
  | none => simp [pOk, lowerAddress, lowerLoad] at ok
  | some xp =>
  cases oOk : lowerAs scope offset (.uint .usize) with
  | none => simp [pOk, oOk, lowerAddress, lowerLoad] at ok
  | some xo =>
  cases bodyOk : body.lower (sigs sp.funcs) sp.decls ret (⟨id, next, .uint .uint8⟩ :: scope) (next + 1) with
  | none => simp [pOk, oOk, bodyOk, lowerAddress, lowerLoad] at ok
  | some bstmt =>
  simp only [pOk, oOk, bodyOk, lowerAddress, lowerLoad, Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i v st1 valueRun
    cases fuel with
    | zero => simp [evalExpr] at valueRun
    | succ k =>
      simp only [evalExpr] at valueRun
      split at valueRun
      · rename_i pv ov mid argsRun
        have gs := prefix_guards (es := [pointer, offset]) (rest := []) corr (SrcProgram.target_toCore sp)
          (by simpa using ⟨⟨_, _, pOk⟩, ⟨_, _, oOk⟩⟩) argsRun
        refine Simulates.checked (guardAnd_one (gs pointer (by simp)) (gs offset (by simp))) ?_
        have := evalExprs_state [pointer, offset] argsRun
        subst this
        simp only [sync_ok fresh.2] at valueRun
        split at valueRun
        · rename_i b loaded
          simp only [Semantics.Outcome.done.injEq] at valueRun
          obtain ⟨rfl, rfl⟩ := valueRun
          obtain ⟨byte, inside⟩ := hc.load loaded
          have tail := tail_bound fresh.2 run bound
          have small := hc.small
          obtain ⟨-, -, -, address⟩ := address_sound (SrcProgram.target_toCore sp) corr pOk oOk argsRun
            (by addr_omega)
          have room : ((Expr.binary Word.u64 BinOp.add xp xo).eval env).toNat < hp.limit := by
            rw [address]; addr_omega
          obtain ⟨fresh', keeps, d, out, exec, matched⟩ := let_tail ih (ty := .uint .uint8) (st := mid)
              (v := .unsigned .u8 b.toNat)
              (env' := env.set next (BitVec.ofNat 64 (hp.bytes
                ((Expr.binary Word.u64 BinOp.add xp xo).eval env).toNat).toNat))
              (hp := hp) bodyOk corr fr fresh le Nat.one_pos
              (fr.agree fun j below => by simp only [Env.set]; rw [if_neg (by omega)])
              (.uint (by
                simp only [SrcType.Holds, Env.set, if_pos, address, byte, BitVec.toNat_ofNat, UintTy.toCore,
                  UintTy.width]
                have := b.toNat_lt
                exact ⟨by rw [Nat.mod_eq_of_lt (by omega)], by rw [Nat.mod_eq_of_lt (by omega)]; exact this⟩))
              hc run bound
          exact ⟨fresh', keeps, d, out, .seq (.loadByte room) exec, matched⟩
        · simp at valueRun
      all_goals simp at valueRun
  all_goals simp at run

theorem stmt_setByte {pointer offset value : SrcExpr}
    (ok : (SrcStmt.setByte pointer offset value).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fresh : st.Fresh) (hc : HeapCorr st.heap st.world hp)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.setByte pointer offset value).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  cases pOk : lowerAs scope pointer .ptr with
  | none => simp [pOk, lowerAddress, lowerStore] at ok
  | some xp =>
  cases oOk : lowerAs scope offset (.uint .usize) with
  | none => simp [pOk, oOk, lowerAddress, lowerStore] at ok
  | some xo =>
  cases vOk : lowerAs scope value (.uint .uint8) with
  | none => simp [pOk, oOk, vOk, lowerAddress, lowerStore] at ok
  | some xv =>
  simp only [pOk, oOk, vOk, lowerAddress, lowerStore, Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i u st1 valueRun
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    cases fuel with
    | zero => simp [evalExpr] at valueRun
    | succ k =>
      simp only [evalExpr] at valueRun
      split at valueRun
      · rename_i pv ov bv mid argsRun
        have gs := prefix_guards (es := [pointer, offset, value]) (rest := []) corr (SrcProgram.target_toCore sp)
          (by simpa using ⟨⟨_, _, pOk⟩, ⟨_, _, oOk⟩, ⟨_, _, vOk⟩⟩) argsRun
        refine Simulates.checked (guardAnd_one (gs pointer (by simp))
          (guardAnd_one (gs offset (by simp)) (gs value (by simp)))) ?_
        have := evalExprs_state [pointer, offset, value] argsRun
        subst this
        simp only [sync_ok fresh.2] at valueRun
        split at valueRun
        · simp at valueRun
        · rename_i heap' stored
          simp only [syncFrom_ok (st := { mid with heap := heap' }) fresh.2, Semantics.Outcome.done.injEq]
            at valueRun
          obtain ⟨-, rfl⟩ := valueRun
          obtain ⟨inside, hc'⟩ := hc.store stored
          have small := hc.small
          have below : mid.heap.nextAddress ≤ hp.limit := by rw [← storeByte_next stored]; exact bound
          obtain ⟨k', mid', vRun, address⟩ := address_sound (SrcProgram.target_toCore sp) corr pOk oOk argsRun
            (by addr_omega)
          obtain ⟨k'', bv', vs', mid'', bRun, -, eq⟩ := evalExprs_cons vRun
          simp only [List.cons.injEq] at eq
          obtain ⟨rfl, -⟩ := eq
          obtain ⟨-, hbv, lt⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) vOk bRun
          simp only [UintTy.toCore, Value.unsigned.injEq, true_and, UintTy.width] at hbv lt
          have room : ((Expr.binary Word.u64 BinOp.add xp xo).eval env).toNat < hp.limit := by
            rw [address]; addr_omega
          have low : lowByte (xv.eval env) = UInt8.ofNat bv := by
            simp only [lowByte, BitVec.toNat_setWidth, hbv]
            rw [Nat.mod_eq_of_lt lt]
          refine ⟨fresh, ⟨fun _ _ => rfl, Nat.le_refl _⟩, 0, _, .storeByte room,
            .next (corr.cells_congr rfl fun _ _ => rfl) ?_⟩
          rw [address, low]
          exact hc'
      all_goals simp at valueRun
  all_goals simp at run

theorem stmt_free {pointer size : SrcExpr} {shift : Nat}
    (ok : (SrcStmt.free pointer size shift).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fresh : st.Fresh) (hc : HeapCorr st.heap st.world hp)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.free pointer size shift).toCore = .done c st') :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerFree] at ok
  split at ok
  case isFalse => simp at ok
  split at ok
  · simp at ok
  rename_i xp pOk
  split at ok
  · simp at ok
  rename_i xs sOk
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i u st1 valueRun
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    cases fuel with
    | zero => simp [evalExpr] at valueRun
    | succ k =>
      simp only [evalExpr] at valueRun
      split at valueRun
      · rename_i p s a mid argsRun
        have gs := prefix_guards (es := [pointer, size]) (rest := [.value (.unsigned .usize (2 ^ shift))]) corr
          (SrcProgram.target_toCore sp) (by simpa using ⟨⟨_, _, pOk⟩, ⟨_, _, sOk⟩⟩) argsRun
        refine Simulates.checked (guardAnd_one (gs pointer (by simp)) (gs size (by simp))) ?_
        have := evalExprs_pure _ (fun x mem => by
          simp only [List.mem_cons, List.not_mem_nil, or_false] at mem
          rcases mem with rfl | rfl | rfl
          · exact pointer.eval_state
          · exact size.eval_state
          · exact eval_value_state) argsRun
        subst this
        simp only [sync_ok fresh.2] at valueRun
        split at valueRun
        · rename_i heap' freed
          simp only [Semantics.Outcome.done.injEq] at valueRun
          obtain ⟨-, rfl⟩ := valueRun
          exact ⟨fresh, ⟨fun _ _ => rfl, Nat.le_refl _⟩, 0, _, .skip,
            .next (corr.cells_congr rfl fun _ _ => rfl) (hc.dealloc freed)⟩
        · simp at valueRun
      all_goals simp at valueRun
  all_goals simp at run

/-! ## Raw slices -/

/-- What Core's `slice_from_raw_parts` did: a descriptor for the pointer, and
the heap as it was. -/
theorem mapRawI32Slice_inv {st : State} {a : Nat} {n : Int} {v : Value} {st1 : State}
    (run : Semantics.mapRawI32Slice st a n = .done v st1) :
    ∃ len heap, v = .rawSlice (.scalar (.signed .i32)) a len ∧ st1 = { st with heap } ∧
      (∀ hp, HeapCorr st.heap st.world hp → HeapCorr heap st.world hp) ∧ len = n.toNat ∧ 0 ≤ n := by
  simp only [Semantics.mapRawI32Slice] at run
  split at run
  · simp at run
  · split at run
    · rename_i zero
      simp only [Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, rfl⟩ := run
      exact ⟨0, st.heap, rfl, rfl, fun _ h => h, by omega, by omega⟩
    · split at run
      · simp at run
      · simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨rfl, rfl⟩ := run
        exact ⟨_, st.heap, rfl, rfl, fun _ h => h, rfl, by omega⟩

theorem mapRawNominalSlice_inv {P : Core.Program} {st : State} {element : Core.Ty} {a : Nat} {n : Int}
    {v : Value} {st1 : State}
    (run : Semantics.mapRawNominalSlice P st element a n = .done v st1) :
    ∃ len heap, v = .rawSlice element a len ∧ st1 = { st with heap } ∧
      (∀ hp, HeapCorr st.heap st.world hp → HeapCorr heap st.world hp) ∧ len = n.toNat ∧ 0 ≤ n := by
  unfold Semantics.mapRawNominalSlice at run
  split at run
  · simp at run
  split at run
  all_goals try (simp at run; done)
  all_goals
    simp only [Bool.not_true, Bool.false_eq_true, if_false] at run
    split at run
    · simp at run
    try dsimp only at run
    split at run
    · simp at run
    split at run
    · simp only [Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, rfl⟩ := run
      exact ⟨0, st.heap, rfl, rfl, fun _ h => h, by simp only [beq_iff_eq] at *; omega, by omega⟩
    split at run
    · simp at run
    split at run
    · simp at run
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    exact ⟨_, st.heap, rfl, rfl, fun _ h => h, rfl, by omega⟩

/-- The element types the slice lowering accepts. -/
theorem slice_kind {ds : SrcDecls} {element : SrcType}
    (cond : (element.isI32 || wordElement ds element) = true) :
    element = .i32 ∨ (∃ sid fields, element = .struct sid fields) ∨ ∃ eid variants, element = .enum eid variants := by
  cases element with
  | i32 => exact .inl rfl
  | struct sid fields => exact .inr (.inl ⟨sid, fields, rfl⟩)
  | enum eid variants => exact .inr (.inr ⟨eid, variants, rfl⟩)
  | bool | uint | ptr | slice | unit | isize | char | sint => simp [SrcType.isI32, wordElement] at cond

/-- What Core's `slice_from_raw_parts` of an accepted element type did. -/
theorem sliceFrom_inv {P : Core.Program} {k : Nat} {st : State} {element : SrcType}
    (kind : element = .i32 ∨ (∃ sid fields, element = .struct sid fields) ∨
      ∃ eid variants, element = .enum eid variants) {p l : Core.Expr}
    {v : Value} {st1 : State} (run : evalExpr (k + 1) P st (element.sliceFrom p l) = .done v st1) :
    ∃ a afterPointer n afterLength len heap, evalExpr k P st p = .done (.pointer a) afterPointer ∧
      evalExpr k P afterPointer l = .done (.signed .i32 n) afterLength ∧
      v = .rawSlice element.toCore a len ∧ st1 = { afterLength with heap } ∧
      (∀ hp, HeapCorr afterLength.heap afterLength.world hp → HeapCorr heap afterLength.world hp) ∧ len = n.toNat ∧ 0 ≤ n := by
  rcases kind with rfl | ⟨sid, fields, rfl⟩ | ⟨eid, variants, rfl⟩
  all_goals
    simp only [SrcType.sliceFrom, evalExpr] at run
    split at run
    · rename_i a afterPointer pointerRun
      split at run
      · rename_i n afterLength lengthRun
        first
        | obtain ⟨len, heap, rfl, rfl, hcOf, lenEq, nonneg⟩ := mapRawI32Slice_inv run
          exact ⟨a, afterPointer, n, afterLength, len, heap, pointerRun, lengthRun, rfl, rfl, hcOf, lenEq, nonneg⟩
        | obtain ⟨len, heap, rfl, rfl, hcOf, lenEq, nonneg⟩ := mapRawNominalSlice_inv run
          exact ⟨a, afterPointer, n, afterLength, len, heap, pointerRun, lengthRun, rfl, rfl, hcOf, lenEq, nonneg⟩
      all_goals simp at run
    all_goals simp at run

theorem stmt_letSlice (ih : StmtSound sp mp fuel) {id : Nat} {element : SrcType}
    {pointer length : SrcExpr} {body : SrcStmt}
    (ok : (SrcStmt.letSlice id element pointer length body).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell) (hc : HeapCorr st.heap st.world hp)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.letSlice id element pointer length body).toCore =
      .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerLet] at ok
  split at ok
  · simp at ok
  rename_i xs sliceOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [lowerSlice] at sliceOk
  split at sliceOk
  case isFalse => simp at sliceOk
  rename_i cond
  have kind := slice_kind (by simp only [Bool.and_eq_true] at cond; exact cond.1)
  cases pOk : lowerAs scope pointer .ptr with
  | none => simp [pOk] at sliceOk
  | some xp =>
  cases lOk : lowerAs scope length .i32 with
  | none => simp [pOk, lOk] at sliceOk
  | some xl =>
  simp only [pOk, lOk, Option.some.injEq] at sliceOk
  subst sliceOk
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i v st1 valueRun
    cases fuel with
    | zero => simp [evalExpr] at valueRun
    | succ k =>
      obtain ⟨a, afterPointer, n, afterLength, len, heap, pointerRun, lengthRun, rfl, rfl, hcOf, lenEq, nonneg⟩ :=
        sliceFrom_inv kind valueRun
      obtain ⟨rfl, holdsP⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) pOk pointerRun
      simp only [SrcType.Holds, Value.pointer.injEq] at holdsP
      refine Simulates.checked (guardAnd_one (lowerAs_guard corr (SrcProgram.target_toCore sp) pOk pointerRun)
        (lowerAs_guard corr (SrcProgram.target_toCore sp) lOk lengthRun)) ?_
      obtain ⟨rfl, holdsL⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) lOk lengthRun
      obtain ⟨hn, bitsL⟩ := holdsL
      simp only [Value.signed.injEq, true_and] at hn
      subst hn
      have sized : (0 : Nat) < (SrcType.slice element).size := by simp [SrcType.size]
      have insens : Insens [xp, xl] next := Insens.below fun x mem => by
        simp only [List.mem_cons, List.not_mem_nil, or_false] at mem
        rcases mem with rfl | rfl
        · obtain ⟨t, lowered, -, rfl⟩ := lowerAs_some pOk
          exact (ValueShape.single lowered rfl).below fr.slots _ List.mem_cons_self
        · obtain ⟨t, lowered, -, rfl⟩ := lowerAs_some lOk
          exact (ValueShape.single lowered rfl).below fr.slots _ List.mem_cons_self
      obtain ⟨fresh', keeps, d, out, exec, matched⟩ := let_tail ih (ty := .slice element)
          (st := { afterLength with heap }) (v := .rawSlice element.toCore a len)
          (env' := env.setFrom next [xp, xl]) (hp := hp) (by simpa [SrcType.size] using bodyOk)
          (corr.cells_congr rfl fun _ _ => rfl) fr fresh le sized
          (fr.agree fun j below => setFrom_outside [xp, xl] next env j (.inl below))
          (by
            have first : a = (env.setFrom next [xp, xl] next).toNat := by
              have here := setFrom_value _ next env insens 0 xp rfl
              simp only [Nat.add_zero] at here
              rw [here]; exact holdsP
            have second : env.setFrom next [xp, xl] (next + 1) = xl.eval env := by
              simpa using setFrom_value _ next env insens 1 xl rfl
            rw [first]
            refine .slice ?_ ?_
            · have bits : (xl.eval env).toNat = (low (xl.eval env)).toNat := by
                conv => lhs; rw [bitsL]
                exact widen_toNat _
              rw [second, lenEq, bits, ← toNat_of_toInt _ nonneg, Int.toNat_natCast]
            · have := BitVec.toInt_lt (x := low (xl.eval env))
              omega)
          (hcOf hp hc) run bound
      exact ⟨fresh', ⟨keeps.cells, keeps.next⟩, d, out, assignFrom_exec [xp, xl] next exec, matched⟩
  all_goals simp at run

/-- A raw slice read that returns is in bounds. -/
theorem readRawSliceIndex_lt {P : Core.Program} {st : State} {element : Core.Ty} {address length pos : Nat}
    {v : Value} (read : Semantics.readRawSliceIndex P st element address length pos = .ok v) : pos < length := by
  simp only [Semantics.readRawSliceIndex] at read
  split at read
  · simp at read
  · omega

theorem boundsGuard_one {b : Binding} {x : Expr} {env : Env}
    (lt : (x.eval env).toNat < (env (b.slot + 1)).toNat) : (boundsGuard b x).eval env = 1 := by
  simp [boundsGuard, Expr.eval, Word.holds, CmpOp.holdsU, BitVec.ult, lt]

/-- The bounds check of `slice[index]` passes when the index is below the
length in the slice's second slot. -/
theorem indexGuard_one {scope : List Binding} {slice : Nat} {b : Binding} (found : lookup scope slice = some b)
    {index : SrcExpr} {x : Expr} (ok : lowerIndex scope index = some x) {env : Env}
    (lt : (x.eval env).toNat < (env (b.slot + 1)).toNat) : (indexGuard scope slice index).eval env = 1 := by
  simp [indexGuard, found, ok, boundsGuard, Expr.eval, Word.holds, CmpOp.holdsU, BitVec.ult, lt]

/-- An `i32` or `usize` index's slot holds the position Core indexes with. -/
theorem index_toNat {t : Typed} {iv : Value} {x : BitVec 64} {pos : Nat}
    (kind : (t.ty.isI32 || t.ty.isUint .usize) = true) (holds : t.ty.Holds iv x)
    (ok : Semantics.integerIndex iv = .ok pos) : x.toNat = pos := by
  cases hty : t.ty with
  | i32 =>
    rw [hty] at holds
    obtain ⟨rfl, bits⟩ := holds
    simp only [Semantics.integerIndex] at ok
    split at ok
    · simp at ok
    · rename_i nonneg
      simp only [Except.ok.injEq] at ok
      subst ok
      have hx : x.toNat = (low x).toNat :=
        calc x.toNat = (widen (low x)).toNat := by rw [← bits]
          _ = (low x).toNat := by
            show (BitVec.setWidth 64 (low x)).toNat = (low x).toNat
            rw [BitVec.toNat_setWidth]
            exact Nat.mod_eq_of_lt (Nat.lt_trans (low x).isLt (by decide))
      rw [hx]
      rw [BitVec.toInt_eq_toNat_cond] at nonneg ⊢
      have := (low x).isLt
      by_cases h : 2 * (low x).toNat < 2 ^ 32 <;> simp only [h, if_true, if_false] at nonneg ⊢ <;> omega
  | uint k =>
    rw [hty] at kind holds
    simp only [SrcType.isI32, SrcType.isUint, Bool.false_or, decide_eq_true_eq] at kind
    cases UintTy.eq_of_code kind
    obtain ⟨rfl, -⟩ := holds
    simp only [Semantics.integerIndex, Except.ok.injEq] at ok
    exact ok
  | bool | struct | enum | ptr | slice | unit | isize | char | sint => rw [hty] at kind; simp [SrcType.isI32, SrcType.isUint] at kind

/-- Core's read of `slice[idx]` from a raw slice local. -/
theorem eval_index_raw {P : Core.Program} {k : Nat} {st : State} {slice : Nat} {idx : Core.Expr}
    {element : Core.Ty} {address length : Nat} {v : Value} {st1 : State}
    (base : evalExpr (k + 1) P st (.local slice) = .done (.rawSlice element address length) st)
    (run : evalExpr (k + 2) P st (.index (.local slice) idx) = .done v st1) :
    ∃ iv pos, evalExpr (k + 1) P st idx = .done iv st1 ∧ Semantics.integerIndex iv = .ok pos ∧
      Semantics.readRawSliceIndex P st1 element address length pos = .ok v := by
  simp only [evalExpr] at run base
  rw [base] at run
  simp only at run
  split at run
  · rename_i iv afterIndex indexRun
    split at run
    · simp at run
    · rename_i pos posOk
      split at run
      · rename_i value read
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨rfl, rfl⟩ := run
        exact ⟨iv, pos, indexRun, posOk, read⟩
      · simp at run
  all_goals simp at run

theorem stmt_letIndex_i32 (ih : StmtSound sp mp fuel) {id : Nat} {ty : SrcType} {slice : Nat}
    {index : SrcExpr} {body : SrcStmt}
    (ok : lowerLoadWord next (lowerElement (lookup scope slice) ty (lowerIndex scope index))
      (body.lower (sigs sp.funcs) sp.decls ret (⟨id, next, ty⟩ :: scope) (next + ty.size)) = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell) (hc : HeapCorr st.heap st.world hp)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.letIndex id ty slice index body).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env
      (checkThen next (guardAnd (index.guard scope) (indexGuard scope slice index)) stmt) c st' := by
  simp only [lowerLoadWord] at ok
  split at ok
  · simp at ok
  rename_i a addressOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [lowerElement] at addressOk
  split at addressOk
  · simp at addressOk
  rename_i b found
  split at addressOk
  case isFalse => simp at addressOk
  rename_i same
  have bty := SrcType.same_eq same
  simp only [elementAddress, bty, elementOf] at addressOk
  split at addressOk
  · simp at addressOk
  rename_i i indexOk
  split at addressOk
  case isFalse => simp at addressOk
  rename_i isI32
  cases ty <;> simp [SrcType.isI32] at isI32
  simp only [Option.some.injEq] at addressOk
  subst addressOk
  simp only [lowerIndex] at indexOk
  split at indexOk
  · simp at indexOk
  rename_i t indexLowered
  simp only [indexOf] at indexOk
  split at indexOk
  case isFalse => simp at indexOk
  rename_i kind
  simp only [Option.some.injEq] at indexOk
  subst indexOk
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i v st1 valueRun
    cases fuel with
    | zero => simp [evalExpr] at valueRun
    | succ k =>
      cases k with
      | zero => simp [evalExpr] at valueRun
      | succ k =>
        obtain ⟨w, localRun, holdsW⟩ := corr.local found k sp.toCore
        rw [bty] at holdsW
        cases holdsW with
        | @slice _ len _ _ lenSlot _ =>
        obtain ⟨iv, pos, indexRun, posOk, read⟩ := eval_index_raw localRun valueRun
        have lt := readRawSliceIndex_lt read
        refine Simulates.checked (guardAnd_one (index.guard_sound corr (SrcProgram.target_toCore sp) indexLowered indexRun)
          (indexGuard_one found (x := t.expr) (by simp [lowerIndex, indexLowered, indexOf, kind])
            (by rw [lenSlot, index_toNat kind (index.lower_sound corr (SrcProgram.target_toCore sp) indexLowered indexRun).2 posOk]
                exact lt))) ?_
        obtain ⟨rfl, holdsI⟩ := index.lower_sound corr (SrcProgram.target_toCore sp) indexLowered indexRun
        have posEq := index_toNat kind holdsI posOk
        simp only [Semantics.readRawSliceIndex] at read
        split at read
        · simp at read
        simp only [Semantics.rawSliceElementAddress?, SrcType.toCore] at read
        obtain ⟨elt, eltOk, read⟩ := except_bind_ok read
        simp only [pure, Except.pure, Except.ok.injEq] at eltOk
        subst eltOk
        simp only [NativeLayout.maxDepth, Semantics.readNativeValue] at read
        obtain ⟨bits, loaded, wrapped⟩ := except_bind_ok read
        simp only [pure, Except.pure, Except.ok.injEq] at wrapped
        subst wrapped
        obtain ⟨rfl, inside⟩ := hc.loadNatLE loaded
        have inside := inside (by decide)
        have tail := tail_bound fresh.2 run bound
        have small := hc.small
        have address : ((Expr.binary Word.u64 BinOp.add (Expr.var b.slot)
            (Expr.binary Word.u64 BinOp.mul t.expr (Expr.lit 4))).eval env).toNat =
            (env b.slot).toNat + pos * 4 := by
          have four : (4 : BitVec 64).toNat = 4 := rfl
          simp only [Expr.eval, Word.apply, BinOp.apply, BitVec.toNat_add, BitVec.toNat_mul, posEq, four]
          rw [Nat.mod_eq_of_lt (a := pos * 4) (by addr_omega), Nat.mod_eq_of_lt (by addr_omega)]
        have room : ((Expr.binary Word.u64 BinOp.add (Expr.var b.slot)
            (Expr.binary Word.u64 BinOp.mul t.expr (Expr.lit 4))).eval env).toNat + MemWidth.m32.bytes ≤
            hp.limit := by
          rw [address]; simp only [MemWidth.bytes]; addr_omega
        have lt32 := hp.readLE_lt ((env b.slot).toNat + pos * 4) 4
        obtain ⟨fresh', keeps, d, out, exec, matched⟩ := let_tail ih (ty := .i32) (st := st1)
            (env' := env.set next (BitVec.ofNat 64 (hp.readLE ((Expr.binary Word.u64 BinOp.add
              (Expr.var b.slot) (Expr.binary Word.u64 BinOp.mul t.expr (Expr.lit 4))).eval env).toNat
              MemWidth.m32.bytes)))
            (hp := hp) (by simpa [SrcType.size] using bodyOk) corr fr fresh le (by simp [SrcType.size])
            (fr.agree fun j below => by simp only [Env.set]; rw [if_neg (by omega)])
            (.i32 (by
              simp only [Env.set, if_pos, address, MemWidth.bytes]
              exact i32_load_holds (by simpa using lt32)))
            hc run bound
        exact ⟨fresh', keeps, d, out, .seq (.loadWord room) exec, matched⟩
  all_goals simp at run

theorem Corr.readPlace {scope frame st env} (corr : Corr scope frame st env) {id : Nat} {b : Binding}
    (found : lookup scope id = some b) (fuel : Nat) (prog : Core.Program) :
    ∃ v, Semantics.evalPlace (fuel + 1) prog st .read (.local id) =
      .done { root := frame b.slot, projections := [], value := some v } st ∧ b.ty.HoldsAt v env b.slot := by
  obtain ⟨v, entry, holds⟩ := corr.values b (lookup_mem found).1
  refine ⟨v, ?_, holds⟩
  simp only [Semantics.evalPlace, corr.cellId, found, Option.map_some, entry]

/-- Core's `slice[idx] = value` on a raw slice local, with no array views and
pure operands. -/
theorem eval_setIndex_raw {P : Core.Program} {k : Nat} {st : State} {slice : Nat} {idx e : Core.Expr}
    {element : Core.Ty} {address length : Nat} {root : Nat} {u : Value} {st' : State}
    (views : st.i32ArrayViews = [])
    (idxPure : ∀ {f v s}, evalExpr f P st idx = .done v s → s = st)
    (ePure : ∀ {f v s}, evalExpr f P st e = .done v s → s = st)
    (base : Semantics.evalPlace (k + 1) P st .read (.local slice) =
      .done { root, projections := [], value := some (.rawSlice element address length) } st)
    (run : evalExpr (k + 3) P st (.assign .set (.index (.local slice) idx) e) = .done u st') :
    ∃ iv pos at_ right heap, evalExpr (k + 1) P st idx = .done iv st ∧
      Semantics.integerIndex iv = .ok pos ∧ pos < length ∧
      Semantics.rawSliceElementAddress? P element address pos = .ok at_ ∧
      evalExpr (k + 2) P st e = .done right st ∧
      Semantics.writeNativeValue NativeLayout.maxDepth P st st.heap element at_ right = .ok heap ∧
      st' = { st with heap } := by
  rw [evalExpr] at run
  rw [Semantics.evalPlace] at run
  rw [base] at run
  simp only at run
  split at run
  · rename_i resolved st1 placeRun
    split at placeRun
    · rename_i iv afterIndex indexRun
      have := idxPure indexRun
      subst this
      split at placeRun
      · simp at placeRun
      rename_i pos posOk
      split at placeRun
      case isFalse => simp at placeRun
      rename_i inside
      split at placeRun
      · simp at placeRun
      rename_i at_ located
      simp only [Semantics.Outcome.done.injEq] at placeRun
      obtain ⟨rfl, rfl⟩ := placeRun
      split at run
      · rename_i right st2 valueRun
        have := ePure valueRun
        subst this
        simp only [Semantics.evalAssignValue, Semantics.assignOpBinary?,
          Semantics.writeResolvedPlaceNative] at run
        split at run
        · rename_i assigned written
          obtain ⟨heap, stored, wrapped⟩ := except_bind_ok written
          simp only [pure, Except.pure, Except.ok.injEq] at wrapped
          subst wrapped
          simp only [Semantics.syncI32ViewsFromHeap, views, Semantics.syncI32ViewsFromHeapFrom, ite_self,
            Semantics.Outcome.done.injEq] at run
          obtain ⟨-, rfl⟩ := run
          exact ⟨iv, pos, at_, right, heap, indexRun, posOk, inside, located, valueRun, stored, by rw [views]⟩
        · simp at run
      all_goals simp at run
    all_goals simp at placeRun
  all_goals simp at run

/-- The mini 32-bit store of an `i32` slot writes Core's bytes. -/
theorem i32_store_bytes {x : BitVec 64} (bits : x = widen (low x)) :
    Semantics.encodeNatLE 4 x.toNat = Semantics.i32Bytes (low x).toInt := by
  rw [i32Bytes_eq]
  congr 1
  have hx : x.toNat = (low x).toNat :=
    calc x.toNat = (widen (low x)).toNat := by rw [← bits]
      _ = (low x).toNat := by
        show (BitVec.setWidth 64 (low x)).toNat = (low x).toNat
        rw [BitVec.toNat_setWidth]
        exact Nat.mod_eq_of_lt (Nat.lt_trans (low x).isLt (by decide))
  rw [hx, BitVec.toInt_eq_toNat_cond]
  have := (low x).isLt
  split <;> omega

theorem stmt_setIndex_i32 {slice : Nat} {index value : SrcExpr} {b : Binding} {element : SrcType}
    (found : lookup scope slice = some b) (hElt : elementOf b.ty = some element)
    (ok : (match elementAddress b (lowerIndex scope index) with
      | none => none
      | some a =>
        match lowerAs scope value element with
        | none => none
        | some v => some (Stmt.storeWord MemWidth.m32 a v)) = some stmt)
    (corr : Corr scope frame st env) (fresh : st.Fresh) (hc : HeapCorr st.heap st.world hp)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.setIndex slice index value).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env
      (checkThen next (guardAnd (guardAnd (index.guard scope) (indexGuard scope slice index)) (value.guard scope)) stmt)
      c st' := by
  split at ok
  · simp at ok
  rename_i a addrOk
  split at ok
  · simp at ok
  rename_i xv vOk
  simp only [Option.some.injEq] at ok
  subst ok
  have bty : b.ty = .slice element := by
    cases hty : b.ty <;> simp [elementOf, hty] at hElt
    rw [hElt]
  simp only [elementAddress, bty, elementOf] at addrOk
  split at addrOk
  · simp at addrOk
  rename_i i indexOk
  split at addrOk
  case isFalse => simp at addrOk
  rename_i isI32
  cases element <;> simp [SrcType.isI32] at isI32
  simp only [Option.some.injEq] at addrOk
  subst addrOk
  simp only [lowerIndex] at indexOk
  split at indexOk
  · simp at indexOk
  rename_i t indexLowered
  simp only [indexOf] at indexOk
  split at indexOk
  case isFalse => simp at indexOk
  rename_i kind
  simp only [Option.some.injEq] at indexOk
  subst indexOk
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i u st1 assignRun
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    cases fuel with
    | zero => simp [evalExpr] at assignRun
    | succ k =>
    cases k with
    | zero => simp [evalExpr, Semantics.evalPlace] at assignRun
    | succ k =>
    cases k with
    | zero => simp [evalExpr, Semantics.evalPlace] at assignRun
    | succ k =>
    obtain ⟨w, place, holdsW⟩ := corr.readPlace found k sp.toCore
    rw [bty] at holdsW
    cases holdsW with
    | @slice _ len _ _ lenSlot _ =>
    obtain ⟨iv, pos, at_, right, heap, indexRun, posOk, posLt, located, valueRun, stored, rfl⟩ :=
      eval_setIndex_raw fresh.2 index.eval_state value.eval_state place assignRun
    refine Simulates.checked (guardAnd_one (guardAnd_one (index.guard_sound corr (SrcProgram.target_toCore sp) indexLowered indexRun)
      (indexGuard_one found (x := t.expr) (by simp [lowerIndex, indexLowered, indexOf, kind])
        (by rw [lenSlot, index_toNat kind (index.lower_sound corr (SrcProgram.target_toCore sp) indexLowered indexRun).2 posOk]
            exact posLt)))
      (lowerAs_guard corr (SrcProgram.target_toCore sp) vOk valueRun)) ?_
    obtain ⟨-, holdsI⟩ := index.lower_sound corr (SrcProgram.target_toCore sp) indexLowered indexRun
    have posEq := index_toNat kind holdsI posOk
    obtain ⟨-, holdsV⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) vOk valueRun
    obtain ⟨rfl, bitsV⟩ := holdsV
    simp only [Semantics.rawSliceElementAddress?, SrcType.toCore, Except.ok.injEq] at located
    subst located
    simp only [NativeLayout.maxDepth, Semantics.writeNativeValue, SrcType.toCore] at stored
    obtain ⟨hc', inside⟩ := HeapCorr.storeBytesFrom _ 0 hc stored
    have inside := inside (by simp [Semantics.i32Bytes])
    have same := storeBytes_next stored
    have small := hc.small
    simp only [Semantics.i32Bytes, List.length_map, List.length_range, Nat.add_zero] at inside hc'
    have address : ((Expr.binary Word.u64 BinOp.add (Expr.var b.slot)
        (Expr.binary Word.u64 BinOp.mul t.expr (Expr.lit 4))).eval env).toNat =
        (env b.slot).toNat + pos * 4 := by
      have four : (4 : BitVec 64).toNat = 4 := rfl
      simp only [Expr.eval, Word.apply, BinOp.apply, BitVec.toNat_add, BitVec.toNat_mul, posEq, four]
      rw [Nat.mod_eq_of_lt (a := pos * 4) (by addr_omega), Nat.mod_eq_of_lt (by addr_omega)]
    have room : ((Expr.binary Word.u64 BinOp.add (Expr.var b.slot)
        (Expr.binary Word.u64 BinOp.mul t.expr (Expr.lit 4))).eval env).toNat + MemWidth.m32.bytes ≤
        hp.limit := by
      rw [address]; simp only [MemWidth.bytes]; addr_omega
    refine ⟨fresh, ⟨fun _ _ => rfl, Nat.le_refl _⟩, 0, _, .storeWord room,
      .next (corr.cells_congr rfl fun _ _ => rfl) ?_⟩
    rw [address]
    simp only [MemWidth.bytes]
    rw [writeLE_eq_writeBytes, i32_store_bytes bitsV]
    simpa [Semantics.i32Bytes] using hc'
  all_goals simp at run

/-! ## Struct and enum slices -/

theorem Expr.Below.mono {n m : Nat} (le : n ≤ m) : ∀ {x : Expr}, x.Below n → x.Below m
  | .lit _, _ => trivial
  | .var _, below => by simp only [Expr.Below] at below ⊢; omega
  | .neg e, below => Expr.Below.mono le (x := e) below
  | .binary _ _ l r, below => ⟨Expr.Below.mono le below.1, Expr.Below.mono le below.2⟩
  | .compare _ _ l r, below => ⟨Expr.Below.mono le below.1, Expr.Below.mono le below.2⟩

theorem Expr.Below.eval_agree {n : Nat} : ∀ {x : Expr}, x.Below n → ∀ {E E' : Env},
    (∀ i < n, E' i = E i) → x.eval E' = x.eval E
  | .lit _, _, _, _, _ => rfl
  | .var i, below, E, E', agree => by
    simp only [Expr.Below] at below
    simp only [Expr.eval]
    exact agree i below
  | .neg e, below, E, E', agree => by
    simp only [Expr.eval, Expr.Below.eval_agree (x := e) below agree]
  | .binary _ _ l r, below, E, E', agree => by
    simp only [Expr.eval, Expr.Below.eval_agree below.1 agree, Expr.Below.eval_agree below.2 agree]
  | .compare _ _ l r, below, E, E', agree => by
    simp only [Expr.eval, Expr.Below.eval_agree below.1 agree, Expr.Below.eval_agree below.2 agree]

theorem addressBelow_eval {env : Env} {base : Expr} {offset : Nat} (fits : offset ≤ (base.eval env).toNat) :
    ((addressBelow base offset).eval env).toNat = (base.eval env).toNat - offset := by
  simp only [addressBelow]
  exact fieldAddress_eval fits

/-- A word scalar's load from `base - offset` into `target`. -/
theorem exec_loadScalar {sp : SrcProgram} {mp : Program} {hp : Heap} {heap : Memory.Heap}
    (hc : HeapCorr heap world hp) (tail : heap.nextAddress ≤ hp.limit) {base : Expr}
    {t : SrcType} {w : MemWidth} (hw : wordWidth t = some w) {target offset : Nat} {env : Env} {v : Value}
    (fits : offset ≤ (base.eval env).toNat)
    (read : ∃ k, Semantics.readNativeValue k sp.toCore heap t.toCore ((base.eval env).toNat - offset) = .ok v) :
    ∃ env', (∀ i, (i < target ∨ target + t.size ≤ i) → env' i = env i) ∧ t.HoldsAt v env' target ∧
      ∀ {d : Nat} {body : Stmt} {out : Outcome}, Exec mp d env' hp body out →
        Exec mp d env hp (.seq (.loadWord w target (addressBelow base offset)) body) out := by
  obtain ⟨k, read⟩ := read
  cases k with
  | zero => exact (readNativeValue_zero read).elim
  | succ k =>
  obtain ⟨holds, inside⟩ := readWord_holds hc hw read
  have addr := addressBelow_eval (offset := offset) fits
  refine ⟨env.set target (BitVec.ofNat 64 (hp.readLE ((base.eval env).toNat - offset) w.bytes)),
    fun i out => ?_, ?_, fun {d} {body} {out} exec => ?_⟩
  · simp only [Env.set]
    rw [if_neg (by rw [wordWidth_size hw] at out; omega)]
  · exact (SrcType.holdsAt_scalar (wordWidth_scalar hw)).mpr (by simp only [Env.set, if_pos]; exact holds)
  · have step := Exec.loadWord (prog := mp) (depth := d) (env := env) (heap := hp) (width := w) (target := target)
      (address := addressBelow base offset) (by rw [addr]; addr_omega)
    rw [addr] at step
    exact .seq step exec

mutual
/-- Loading a value of a word type, which Core reads at `base - offset`,
into the slots from `target`: the slots from `target` hold it after. -/
theorem exec_loadType {sp : SrcProgram} {mp : Program} {hp : Heap} {heap : Memory.Heap}
    (hc : HeapCorr heap world hp) (tail : heap.nextAddress ≤ hp.limit) {base : Expr} :
    ∀ (t : SrcType), wordType sp.decls t = true → ∀ {target offset : Nat} {env : Env} {v : Value},
      base.Below target → offset ≤ (base.eval env).toNat →
      (∃ k, Semantics.readNativeValue k sp.toCore heap t.toCore ((base.eval env).toNat - offset) = .ok v) →
      ∃ env', (∀ i, (i < target ∨ target + t.size ≤ i) → env' i = env i) ∧ t.HoldsAt v env' target ∧
        ∀ {d : Nat} {body : Stmt} {out : Outcome}, Exec mp d env' hp body out →
          Exec mp d env hp (loadType t target base offset body) out
  | .i32, ok, _, _, _, _, _, fits, read => exec_loadScalar hc tail (wordType_scalar ok rfl) fits read
  | .bool, ok, _, _, _, _, _, fits, read => exec_loadScalar hc tail (wordType_scalar ok rfl) fits read
  | .uint _, ok, _, _, _, _, _, fits, read => exec_loadScalar hc tail (wordType_scalar ok rfl) fits read
  | .ptr, ok, _, _, _, _, _, fits, read => exec_loadScalar hc tail (wordType_scalar ok rfl) fits read
  | .isize, ok, _, _, _, _, _, fits, read => exec_loadScalar hc tail (wordType_scalar ok rfl) fits read
  | .sint _, ok, _, _, _, _, _, fits, read => exec_loadScalar hc tail (wordType_scalar ok rfl) fits read
  | .slice _, ok, _, _, _, _, _, _, _ => by simp [wordType] at ok
  | .unit, ok, _, _, _, _, _, _, _ => by simp [wordType] at ok
  | .struct sid fields, ok, target, offset, env, v, below, fits, ⟨k, read⟩ => by
    obtain ⟨decl, words, -⟩ := wordType_struct ok
    cases k with
    | zero => exact (readNativeValue_zero read).elim
    | succ k =>
    simp only [SrcType.toCore] at read
    obtain ⟨vals, rfl, reads⟩ := readNativeValue_struct_reads decl words read
    have reads := reads.rebase fits
    rw [Nat.add_zero] at reads
    obtain ⟨env', agree, holds, exec⟩ := exec_loadTypes hc tail fields words below reads
    exact ⟨env', fun i out => agree i (by simpa only [SrcType.size] using out), .struct holds,
      fun e => by simp only [loadType]; exact exec e⟩
  | .enum eid variants, ok, target, offset, env, v, below, fits, ⟨k, read⟩ => by
    obtain ⟨decl, words, -, small⟩ := wordType_enum ok
    cases k with
    | zero => exact (readNativeValue_zero read).elim
    | succ k =>
    simp only [SrcType.toCore] at read
    obtain ⟨variant, fs, payload, rfl, tagLoad, hfs, reads⟩ := readNativeValue_enum_reads decl words read
    obtain ⟨tagEq, tagInside⟩ := hc.loadNatLE tagLoad
    have tagInside := tagInside (by decide)
    have vlt : variant < variants.length := (List.getElem?_eq_some_iff.mp hfs).1
    have tagLt : variant < 2 ^ 32 := by rw [tagEq]; simpa using hp.readLE_lt _ 4
    have addr := addressBelow_eval (offset := offset) fits
    have fsLe := sizes_le_maxSize hfs
    let env1 := env.set target
      (BitVec.ofNat 64 (hp.readLE ((addressBelow base offset).eval env).toNat MemWidth.m32.bytes))
    have same1 : base.eval env1 = base.eval env := below.eval_set (Nat.le_refl target) env _
    have tag1 : env1 target = BitVec.ofNat 64 (0 + variant) := by
      simp only [env1, Env.set, if_pos, MemWidth.bytes, addr, Nat.zero_add]
      rw [← tagEq]
    have reads := reads.rebase fits
    rw [← same1] at reads
    obtain ⟨env2, agree2, holds2, exec2⟩ := exec_loadCases hc tail variants words (k := 0) hfs tag1
      (Nat.lt_of_lt_of_le (by simpa using tagLt) (by decide))
      below reads
    refine ⟨env2, fun i out => ?_, .enum hfs ?_ holds2, fun {d} {body} {out} exec => ?_⟩
    · simp only [SrcType.size] at out
      rw [agree2 i (by omega)]
      simp only [env1, Env.set]
      rw [if_neg (by omega)]
    · rw [agree2 target (by omega), tag1, Nat.zero_add]
    · simp only [loadType]
      have room : ((addressBelow base offset).eval env).toNat + MemWidth.m32.bytes ≤ hp.limit := by
        rw [addr]
        simp only [MemWidth.bytes]
        addr_omega
      exact .seq (.loadWord room) (.seq exec2 exec)

theorem exec_loadTypes {sp : SrcProgram} {mp : Program} {hp : Heap} {heap : Memory.Heap}
    (hc : HeapCorr heap world hp) (tail : heap.nextAddress ≤ hp.limit) {base : Expr} :
    ∀ (fs : List SrcType), wordTypes sp.decls fs = true →
      ∀ {target offset : Nat} {env : Env} {vals : List Value}, base.Below target →
        FieldReads sp.toCore heap (base.eval env).toNat fs vals offset →
        ∃ env', (∀ i, (i < target ∨ target + sizes fs ≤ i) → env' i = env i) ∧ FieldsHold fs vals env' target ∧
          ∀ {d : Nat} {body : Stmt} {out : Outcome}, Exec mp d env' hp body out →
            Exec mp d env hp (loadTypes fs target base offset body) out
  | [], _, target, offset, env, vals, below, reads => by
    cases reads
    exact ⟨env, fun _ _ => rfl, .nil, fun e => by simp only [loadTypes]; exact e⟩
  | f :: rest, ok, target, offset, env, vals, below, reads => by
    simp only [wordTypes, Bool.and_eq_true] at ok
    cases reads with
    | cons le read more =>
    obtain ⟨env1, agree1, holds1, exec1⟩ := exec_loadType hc tail f ok.1 below le read
    have same1 : base.eval env1 = base.eval env := below.eval_agree fun i lt => agree1 i (.inl lt)
    rw [← same1] at more
    obtain ⟨env2, agree2, holds2, exec2⟩ := exec_loadTypes hc tail rest ok.2 (below.mono (m := target + f.size) (by omega)) more
    refine ⟨env2, fun i out => ?_, .cons (holds1.congr fun i lt => ?_) holds2, fun e => ?_⟩
    · simp only [sizes] at out
      rw [agree2 i (by omega), agree1 i (by omega)]
    · exact agree2 (target + i) (by omega)
    · simp only [loadTypes]
      exact exec1 (exec2 e)

theorem exec_loadCases {sp : SrcProgram} {mp : Program} {hp : Heap} {heap : Memory.Heap}
    (hc : HeapCorr heap world hp) (tail : heap.nextAddress ≤ hp.limit) {base : Expr} :
    ∀ (vs : List (List SrcType)), wordVariants sp.decls vs = true →
      ∀ {k m target offset : Nat} {env : Env} {fs : List SrcType} {vals : List Value}, vs[m]? = some fs →
        env target = BitVec.ofNat 64 (k + m) → k + m < 2 ^ 64 → base.Below target →
        FieldReads sp.toCore heap (base.eval env).toNat fs vals (offset + 8) →
        ∃ env', (∀ i, (i < target + 1 ∨ target + 1 + sizes fs ≤ i) → env' i = env i) ∧
          FieldsHold fs vals env' (target + 1) ∧
          ∀ {d : Nat}, Exec mp d env hp (loadCases target base offset k vs) (.normal env' hp)
  | [], _, _, _, _, _, _, _, _, found, _, _, _, _ => by simp at found
  | fs0 :: rest, ok, k, m, target, offset, env, fs, vals, found, tag, bound, below, reads => by
    simp only [wordVariants, Bool.and_eq_true] at ok
    cases m with
    | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst found
      obtain ⟨env', agree, holds, exec⟩ := exec_loadTypes hc tail fs0 ok.1 (below.mono (m := target + 1) (by omega)) reads
      refine ⟨env', fun i out => agree i (by omega), holds, fun {d} => ?_⟩
      cases rest with
      | nil =>
        simp only [loadCases]
        exact exec .skip
      | cons more others =>
        simp only [loadCases]
        exact .ifTrue (by simp [Expr.eval, Word.holds, CmpOp.holdsU, tag]) (exec .skip)
    | succ m =>
      cases rest with
      | nil => simp at found
      | cons more others =>
        have differ : BitVec.ofNat 64 (k + (m + 1)) ≠ BitVec.ofNat 64 k := ofNat_ne bound (by omega) (by omega)
        obtain ⟨env', agree, holds, exec⟩ := exec_loadCases hc tail (more :: others) ok.2 (k := k + 1) (m := m)
          (by simpa using found) (by rw [tag, show k + (m + 1) = k + 1 + m by omega]) (by omega) below reads
        refine ⟨env', agree, holds, fun {d} => ?_⟩
        simp only [loadCases]
        exact .ifFalse (by simp [Expr.eval, Word.holds, CmpOp.holdsU, tag, differ]) exec
end

/-- Loading a struct or enum element of a raw slice from `target` on gives
the value Core reads. -/
theorem loadElement_sound {sp : SrcProgram} {mp : Program} {hp : Heap} {st : State}
    (hc : HeapCorr st.heap st.world hp) (tail : st.heap.nextAddress ≤ hp.limit)
    {element : SrcType} (hel : wordElement sp.decls element = true)
    {env : Env} {bslot target : Nat} {i : Expr} {len pos : Nat} {v : Value}
    (posEq : (i.eval env).toNat = pos) (below : (elementBase bslot element.size i).Below target)
    (read : Semantics.readRawSliceIndex sp.toCore st element.toCore (env bslot).toNat len pos = .ok v) :
    ∃ env', (∀ j, (j < target ∨ target + element.size ≤ j) → env' j = env j) ∧ element.HoldsAt v env' target ∧
      ∀ {d : Nat} {rest : Stmt} {out : Outcome}, Exec mp d env' hp rest out →
        Exec mp d env hp (loadType element target (elementBase bslot element.size i) 0 rest) out := by
  simp only [Semantics.readRawSliceIndex] at read
  split at read
  all_goals try (simp at read; done)
  obtain ⟨at_, located, read⟩ := except_bind_ok read
  obtain ⟨rfl, fits, small⟩ := rawSliceElementAddress_word hel located
  have baseEval : ((elementBase bslot element.size i).eval env).toNat =
      (env bslot).toNat - pos * (8 * element.size) :=
    elementBase_eval posEq small fits
  exact exec_loadType hc tail element (wordElement_wordType hel) below (Nat.zero_le _)
    ⟨_, by rw [baseEval, Nat.sub_zero]; exact read⟩

/-- Core writes an `isize` as the 8 bytes of its two's complement bits. -/
theorem isize_word_bits (bits : BitVec 64) : Int.toNat (bits.toInt % 2 ^ 64) = bits.toNat := by
  rw [BitVec.toInt_eq_toNat_cond]
  have lt := bits.isLt
  have a : (2 : Nat) ^ 64 = 18446744073709551616 := by rfl
  have c : (2 : Int) ^ 64 = 18446744073709551616 := by rfl
  simp only [a, c] at lt ⊢
  split <;> omega

/-- A word field's store: Core writes the bytes the mini `storeWord` does. -/
theorem writeWord_corr {P : Core.Program} {st : State} {heap heap' : Memory.Heap} {hp : Heap}
    (hc : HeapCorr heap world hp) {f : SrcType} {w : MemWidth} (hw : wordWidth f = some w) {k a : Nat}
    {x : Value} {bits : BitVec 64} (holds : f.Holds x bits)
    (h : Semantics.writeNativeValue (k + 1) P st heap f.toCore a x = .ok heap') :
    HeapCorr heap' world (hp.writeLE a bits.toNat w.bytes) ∧ a + w.bytes ≤ heap.nextAddress ∧
      heap'.nextAddress = heap.nextAddress := by
  rcases wordWidth_cases hw with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨kind, rfl, hk⟩ | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩ | ⟨kind, rfl, hk⟩
  · obtain ⟨rfl, bitsV⟩ := holds
    simp only [SrcType.toCore, Semantics.writeNativeValue] at h
    obtain ⟨hc', inside⟩ := HeapCorr.storeBytesFrom _ 0 hc h
    refine ⟨?_, ?_, storeBytes_next h⟩
    · simp only [MemWidth.bytes]
      rw [writeLE_eq_writeBytes, i32_store_bytes bitsV]
      simpa using hc'
    · have := inside (by simp [Semantics.i32Bytes])
      simpa [Semantics.i32Bytes, MemWidth.bytes] using this
  · obtain ⟨b, rfl, rfl⟩ := holds
    simp only [SrcType.toCore, Semantics.writeNativeValue] at h
    obtain ⟨hc', inside⟩ := HeapCorr.storeBytesFrom _ 0 hc h
    refine ⟨?_, ?_, storeBytes_next h⟩
    · simp only [MemWidth.bytes]
      rw [writeLE_eq_writeBytes]
      have : (boolBits b).toNat = if b then 1 else 0 := by cases b <;> rfl
      rw [this]
      simpa using hc'
    · have := inside (by simp [Semantics.encodeNatLE])
      simpa [Semantics.encodeNatLE, MemWidth.bytes] using this
  · obtain ⟨rfl, -⟩ := holds
    cases kind <;> simp only [usizeWidth, Option.some.injEq] at hk <;> subst hk <;>
      simp only [SrcType.toCore, UintTy.toCore, Semantics.writeNativeValue] at h <;>
      obtain ⟨hc', inside⟩ := HeapCorr.storeBytesFrom _ 0 hc h <;>
      refine ⟨?_, ?_, storeBytes_next h⟩
    all_goals first
      | (simp only [MemWidth.bytes]; rw [writeLE_eq_writeBytes]; simpa using hc')
      | (have := inside (by simp [Semantics.encodeNatLE])
         simpa [Semantics.encodeNatLE, MemWidth.bytes] using this)
  · subst holds
    simp only [SrcType.toCore, Semantics.writeNativeValue] at h
    obtain ⟨hc', inside⟩ := HeapCorr.storeBytesFrom _ 0 hc h
    refine ⟨?_, ?_, storeBytes_next h⟩
    · simp only [MemWidth.bytes]
      rw [writeLE_eq_writeBytes]
      simpa using hc'
    · have := inside (by simp [Semantics.encodeNatLE])
      simpa [Semantics.encodeNatLE, MemWidth.bytes] using this
  · subst holds
    simp only [SrcType.toCore, Semantics.writeNativeValue] at h
    rw [isize_word_bits] at h
    obtain ⟨hc', inside⟩ := HeapCorr.storeBytesFrom _ 0 hc h
    refine ⟨?_, ?_, storeBytes_next h⟩
    · simp only [MemWidth.bytes]
      rw [writeLE_eq_writeBytes]
      simpa using hc'
    · have := inside (by simp [Semantics.encodeNatLE])
      simpa [Semantics.encodeNatLE, MemWidth.bytes] using this
  · cases kind <;> simp only [usizeWidth, Option.some.injEq] at hk <;> subst hk
    case uint64 | usize =>
      simp only [SrcType.Holds, UintTy.SintHolds] at holds
      subst holds
      simp only [SrcType.toCore, UintTy.toSigned, Semantics.writeNativeValue] at h
      rw [isize_word_bits] at h
      obtain ⟨hc', inside⟩ := HeapCorr.storeBytesFrom _ 0 hc h
      refine ⟨?_, ?_, storeBytes_next h⟩
      · simp only [MemWidth.bytes]
        rw [writeLE_eq_writeBytes]
        simpa using hc'
      · have := inside (by simp [Semantics.encodeNatLE])
        simpa [Semantics.encodeNatLE, MemWidth.bytes] using this
    all_goals
      obtain ⟨rfl, bitsV, -⟩ := holds
      simp only [SrcType.toCore, UintTy.toSigned, Semantics.writeNativeValue] at h
      obtain ⟨hc', inside⟩ := HeapCorr.storeBytesFrom _ 0 hc h
      refine ⟨?_, ?_, storeBytes_next h⟩
      · simp only [MemWidth.bytes]
        rw [writeLE_eq_writeBytes, i32_store_bytes bitsV]
        simpa using hc'
      · have := inside (by simp [Semantics.i32Bytes])
        simpa [Semantics.i32Bytes, MemWidth.bytes] using this

theorem holdsAt_enum_inv {id : Nat} {variants : List (List SrcType)} {v : Value} {env : Env} {slot : Nat}
    (h : SrcType.HoldsAt (.enum id variants) v env slot) :
    ∃ kv fs vals, v = .enumeration id kv vals ∧ variants[kv]? = some fs ∧ env slot = BitVec.ofNat 64 kv ∧
      FieldsHold fs vals env (slot + 1) := by
  cases h with
  | enum found tag payload => exact ⟨_, _, _, rfl, found, tag, payload⟩

/-- A word scalar's store of the value in `values[first]` at `base - offset`. -/
theorem exec_storeScalar {sp : SrcProgram} {mp : Program} {st : State} {env : Env} {base : Expr}
    {values : List Expr} {t : SrcType} {w : MemWidth} (hw : wordWidth t = some w) {first offset : Nat} {s : Stmt}
    {v : Value} {heap heap' : Memory.Heap} {hp : Heap}
    (ok : storeOne w (addressBelow base offset) values[first]? = some s)
    (holds : t.HoldsAt v (Func.entry (Expr.evalAll env values)) first) (fits : offset ≤ (base.eval env).toNat)
    (wrote : ∃ k, Semantics.writeNativeValue k sp.toCore st heap t.toCore ((base.eval env).toNat - offset) v =
      .ok heap')
    (hc : HeapCorr heap world hp) (bound : heap.nextAddress ≤ hp.limit) :
    ∃ hp', (∀ {d : Nat}, Exec mp d env hp s (.normal env hp')) ∧ HeapCorr heap' world hp' ∧
      heap'.nextAddress = heap.nextAddress ∧ hp'.limit = hp.limit := by
  cases hv : values[first]? with
  | none => simp [storeOne, hv] at ok
  | some e =>
  simp only [storeOne, hv, Option.some.injEq] at ok
  subst ok
  obtain ⟨k, wrote⟩ := wrote
  cases k with
  | zero => exact (writeNativeValue_zero wrote).elim
  | succ k =>
  have holds := (SrcType.holdsAt_scalar (wordWidth_scalar hw)).mp holds
  rw [entry_evalAll env values first e hv] at holds
  obtain ⟨hc1, inside, next1⟩ := writeWord_corr hc hw holds wrote
  have addr := addressBelow_eval (offset := offset) fits
  have room : ((addressBelow base offset).eval env).toNat + w.bytes ≤ hp.limit := by rw [addr]; addr_omega
  refine ⟨_, fun {d} => ?_, hc1, next1, (Heap.writeLE_limit _ _ _ _).1⟩
  have step := Exec.storeWord (prog := mp) (depth := d) (env := env) (heap := hp) (value := e) room
  rw [addr] at step
  exact step

mutual
/-- Storing a value of a word type, its slots `values` from `first`, at
`base - offset`, as Core writes it there. -/
theorem exec_storeType {sp : SrcProgram} {mp : Program} {st : State} {env : Env} {base : Expr}
    {values : List Expr} :
    ∀ (t : SrcType), wordType sp.decls t = true →
      ∀ {first offset : Nat} {s : Stmt} {v : Value} {heap heap' : Memory.Heap} {hp : Heap},
        storeType t values first base offset = some s → t.HoldsAt v (Func.entry (Expr.evalAll env values)) first →
        offset ≤ (base.eval env).toNat →
        (∃ k, Semantics.writeNativeValue k sp.toCore st heap t.toCore ((base.eval env).toNat - offset) v =
          .ok heap') →
        HeapCorr heap world hp → heap.nextAddress ≤ hp.limit →
        ∃ hp', (∀ {d : Nat}, Exec mp d env hp s (.normal env hp')) ∧ HeapCorr heap' world hp' ∧
          heap'.nextAddress = heap.nextAddress ∧ hp'.limit = hp.limit
  | .i32, ok, _, _, _, _, _, _, _, sOk, holds, fits, wrote, hc, bound =>
    exec_storeScalar (wordType_scalar ok rfl) sOk holds fits wrote hc bound
  | .bool, ok, _, _, _, _, _, _, _, sOk, holds, fits, wrote, hc, bound =>
    exec_storeScalar (wordType_scalar ok rfl) sOk holds fits wrote hc bound
  | .uint _, ok, _, _, _, _, _, _, _, sOk, holds, fits, wrote, hc, bound =>
    exec_storeScalar (wordType_scalar ok rfl) sOk holds fits wrote hc bound
  | .ptr, ok, _, _, _, _, _, _, _, sOk, holds, fits, wrote, hc, bound =>
    exec_storeScalar (wordType_scalar ok rfl) sOk holds fits wrote hc bound
  | .isize, ok, _, _, _, _, _, _, _, sOk, holds, fits, wrote, hc, bound =>
    exec_storeScalar (wordType_scalar ok rfl) sOk holds fits wrote hc bound
  | .sint _, ok, _, _, _, _, _, _, _, sOk, holds, fits, wrote, hc, bound =>
    exec_storeScalar (wordType_scalar ok rfl) sOk holds fits wrote hc bound
  | .slice _, ok, _, _, _, _, _, _, _, _, _, _, _, _, _ => by simp [wordType] at ok
  | .unit, ok, _, _, _, _, _, _, _, _, _, _, _, _, _ => by simp [wordType] at ok
  | .struct sid fields, ok, first, offset, s, v, heap, heap', hp, sOk, holds, fits, ⟨k, wrote⟩, hc, bound => by
    obtain ⟨decl, words, -⟩ := wordType_struct ok
    obtain ⟨vals, rfl, fh⟩ := holdsAt_struct_inv holds
    cases k with
    | zero => exact (writeNativeValue_zero wrote).elim
    | succ k =>
    simp only [SrcType.toCore] at wrote
    have writes := (writeNativeValue_struct_writes decl words wrote).rebase fits
    rw [Nat.add_zero] at writes
    simp only [storeType] at sOk
    exact exec_storeTypes fields words sOk fh writes hc bound
  | .enum eid variants, ok, first, offset, s, v, heap, heap', hp, sOk, holds, fits, ⟨k, wrote⟩, hc, bound => by
    obtain ⟨decl, words, -, small⟩ := wordType_enum ok
    obtain ⟨kv, fs, vals, rfl, hfs, tagv, fh⟩ := holdsAt_enum_inv holds
    cases k with
    | zero => exact (writeNativeValue_zero wrote).elim
    | succ k =>
    simp only [SrcType.toCore] at wrote
    obtain ⟨tagged, tagStored, writes⟩ := writeNativeValue_enum_writes decl words hfs wrote
    have writes := writes.rebase fits
    simp only [storeType] at sOk
    cases ht : values[first]? with
    | none => simp [ht] at sOk
    | some tag =>
    simp only [ht, lowerThen] at sOk
    split at sOk
    all_goals try (simp at sOk; done)
    rename_i s2 s2ok
    simp only [Option.some.injEq] at sOk
    subst sOk
    have kvLt : kv < 2 ^ 32 := Nat.lt_trans (List.getElem?_eq_some_iff.mp hfs).1 small
    have tagEval : tag.eval env = BitVec.ofNat 64 kv := by
      rw [← entry_evalAll env values first tag ht]
      exact tagv
    have tagNat : (tag.eval env).toNat = kv := by
      rw [tagEval, BitVec.toNat_ofNat]
      exact Nat.mod_eq_of_lt (Nat.lt_trans kvLt (by decide))
    obtain ⟨hcT, insideT⟩ := HeapCorr.storeBytesFrom _ 0 hc tagStored
    have insideT := insideT (by simp [Semantics.encodeNatLE])
    have nextT := storeBytes_next tagStored
    simp only [Semantics.encodeNatLE, List.length_map, List.length_range, Nat.add_zero] at insideT
    have hcT' : HeapCorr tagged world
        (hp.writeLE ((base.eval env).toNat - offset) (tag.eval env).toNat MemWidth.m32.bytes) := by
      rw [writeLE_eq_writeBytes, tagNat]
      simpa [MemWidth.bytes] using hcT
    have lim := (Heap.writeLE_limit hp ((base.eval env).toNat - offset) (tag.eval env).toNat MemWidth.m32.bytes).1
    obtain ⟨hp', exec2, hc', next2, lim2⟩ := exec_storeCases variants words (k := 0) (m := kv) s2ok hfs
      (by rw [Nat.zero_add]; exact tagEval) (by omega) fh writes hcT' (by rw [lim, nextT]; exact bound)
    have addr := addressBelow_eval (offset := offset) fits
    have room : ((addressBelow base offset).eval env).toNat + MemWidth.m32.bytes ≤ hp.limit := by
      rw [addr]
      simp only [MemWidth.bytes]
      addr_omega
    refine ⟨hp', fun {d} => ?_, hc', by rw [next2, nextT], by rw [lim2, lim]⟩
    have first' := Exec.storeWord (prog := mp) (depth := d) (env := env) (heap := hp) (width := .m32)
      (value := tag) room
    rw [addr] at first'
    exact .seq first' exec2

theorem exec_storeTypes {sp : SrcProgram} {mp : Program} {st : State} {env : Env} {base : Expr}
    {values : List Expr} :
    ∀ (fs : List SrcType), wordTypes sp.decls fs = true →
      ∀ {first offset : Nat} {s : Stmt} {vals : List Value} {heap heap' : Memory.Heap} {hp : Heap},
        storeTypes fs values first base offset = some s →
        FieldsHold fs vals (Func.entry (Expr.evalAll env values)) first →
        FieldWrites sp.toCore st (base.eval env).toNat fs vals offset heap heap' →
        HeapCorr heap world hp → heap.nextAddress ≤ hp.limit →
        ∃ hp', (∀ {d : Nat}, Exec mp d env hp s (.normal env hp')) ∧ HeapCorr heap' world hp' ∧
          heap'.nextAddress = heap.nextAddress ∧ hp'.limit = hp.limit
  | [], _, first, offset, s, vals, heap, heap', hp, sOk, _, writes, hc, _ => by
    simp only [storeTypes, Option.some.injEq] at sOk
    subst sOk
    cases writes
    exact ⟨hp, fun {d} => .skip, hc, rfl, rfl⟩
  | f :: rest, ok, first, offset, s, vals, heap, heap', hp, sOk, fh, writes, hc, bound => by
    simp only [wordTypes, Bool.and_eq_true] at ok
    simp only [storeTypes, lowerThen] at sOk
    split at sOk
    all_goals try (simp at sOk; done)
    rename_i s1 s1ok
    split at sOk
    all_goals try (simp at sOk; done)
    rename_i s2 s2ok
    simp only [Option.some.injEq] at sOk
    subst sOk
    cases fh with
    | cons holds fhr =>
    cases writes with
    | cons le wrote more =>
    obtain ⟨hp1, exec1, hc1, next1, lim1⟩ := exec_storeType f ok.1 s1ok holds le wrote hc bound
    obtain ⟨hp2, exec2, hc2, next2, lim2⟩ := exec_storeTypes rest ok.2 s2ok fhr more hc1
      (by rw [next1, lim1]; exact bound)
    exact ⟨hp2, fun {d} => .seq exec1 exec2, hc2, by rw [next2, next1], by rw [lim2, lim1]⟩

theorem exec_storeCases {sp : SrcProgram} {mp : Program} {st : State} {env : Env} {base : Expr}
    {values : List Expr} :
    ∀ (vs : List (List SrcType)), wordVariants sp.decls vs = true →
      ∀ {tag : Expr} {k m first offset : Nat} {s : Stmt} {fs : List SrcType} {vals : List Value}
        {heap heap' : Memory.Heap} {hp : Heap},
        storeCases tag values first base offset k vs = some s → vs[m]? = some fs →
        tag.eval env = BitVec.ofNat 64 (k + m) → k + m < 2 ^ 64 →
        FieldsHold fs vals (Func.entry (Expr.evalAll env values)) first →
        FieldWrites sp.toCore st (base.eval env).toNat fs vals offset heap heap' →
        HeapCorr heap world hp → heap.nextAddress ≤ hp.limit →
        ∃ hp', (∀ {d : Nat}, Exec mp d env hp s (.normal env hp')) ∧ HeapCorr heap' world hp' ∧
          heap'.nextAddress = heap.nextAddress ∧ hp'.limit = hp.limit
  | [], _, _, _, _, _, _, _, _, _, _, _, _, _, found, _, _, _, _, _, _ => by simp at found
  | fs0 :: rest, ok, tag, k, m, first, offset, s, fs, vals, heap, heap', hp, sOk, found, tagv, bound, fh, writes,
      hc, lim => by
    simp only [wordVariants, Bool.and_eq_true] at ok
    cases rest with
    | nil =>
      cases m with
      | succ m => simp at found
      | zero =>
      simp only [List.getElem?_cons_zero, Option.some.injEq] at found
      subst found
      simp only [storeCases] at sOk
      exact exec_storeTypes fs0 ok.1 sOk fh writes hc lim
    | cons more others =>
      simp only [storeCases, iteThen] at sOk
      split at sOk
      all_goals try (simp at sOk; done)
      rename_i t tOk
      split at sOk
      all_goals try (simp at sOk; done)
      rename_i e eOk
      simp only [Option.some.injEq] at sOk
      subst sOk
      cases m with
      | zero =>
        simp only [List.getElem?_cons_zero, Option.some.injEq] at found
        subst found
        obtain ⟨hp', exec, hc', next', lim'⟩ := exec_storeTypes fs0 ok.1 tOk fh writes hc lim
        exact ⟨hp', fun {d} => .ifTrue (by simp [Expr.eval, Word.holds, CmpOp.holdsU, tagv]) exec, hc', next',
          lim'⟩
      | succ m =>
        have differ : BitVec.ofNat 64 (k + (m + 1)) ≠ BitVec.ofNat 64 k := ofNat_ne bound (by omega) (by omega)
        obtain ⟨hp', exec, hc', next', lim'⟩ := exec_storeCases (more :: others) ok.2 (k := k + 1) (m := m) eOk
          (by simpa using found) (by rw [tagv, show k + (m + 1) = k + 1 + m by omega]) (by omega) fh writes hc lim
        exact ⟨hp', fun {d} => .ifFalse (by simp [Expr.eval, Word.holds, CmpOp.holdsU, tagv, differ]) exec,
          hc', next', lim'⟩
end

/-- Storing a struct or enum element of a raw slice, its slots given by
`vs`, writes the bytes Core does. -/
theorem storeElement_sound {sp : SrcProgram} {mp : Program} {hp : Heap} {st : State}
    (hc : HeapCorr st.heap st.world hp) {element : SrcType} (hel : wordElement sp.decls element = true)
    {env : Env} {bslot : Nat} {i : Expr} {pos at_ : Nat} {right : Value} {vs : List Expr} {s : Stmt}
    {heap : Memory.Heap} (posEq : (i.eval env).toNat = pos)
    (located : Semantics.rawSliceElementAddress? sp.toCore element.toCore (env bslot).toNat pos = .ok at_)
    (stored : Semantics.writeNativeValue NativeLayout.maxDepth sp.toCore st st.heap element.toCore at_ right =
      .ok heap)
    (flat : FlatValue element right env vs) (ok : storeType element vs 0 (elementBase bslot element.size i) 0 = some s)
    (bound : heap.nextAddress ≤ hp.limit) :
    ∃ hp', Exec mp 0 env hp s (.normal env hp') ∧ HeapCorr heap st.world hp' := by
  obtain ⟨rfl, fits, small⟩ := rawSliceElementAddress_word hel located
  have baseEval : ((elementBase bslot element.size i).eval env).toNat =
      (env bslot).toNat - pos * (8 * element.size) :=
    elementBase_eval posEq small fits
  have pre : st.heap.nextAddress ≤ hp.limit := by rw [← writeNativeValue_next _ stored]; exact bound
  obtain ⟨hp', exec, hc', -, -⟩ := exec_storeType (mp := mp) (st := st) (env := env)
    (base := elementBase bslot element.size i) element (wordElement_wordType hel) ok flat.holds (Nat.zero_le _)
    ⟨_, by rw [baseEval, Nat.sub_zero]; exact stored⟩ hc pre
  exact ⟨hp', exec, hc'⟩

theorem stmt_letIndex_word (ih : StmtSound sp mp fuel) {id : Nat} {ty : SrcType} {slice : Nat}
    {index : SrcExpr} {body : SrcStmt}
    (ok : lowerLoadType sp.decls next (lookup scope slice) ty (lowerIndex scope index)
      (body.lower (sigs sp.funcs) sp.decls ret (⟨id, next, ty⟩ :: scope) (next + ty.size)) = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell) (hc : HeapCorr st.heap st.world hp)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.letIndex id ty slice index body).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env
      (checkThen next (guardAnd (index.guard scope) (indexGuard scope slice index)) stmt) c st' := by
  unfold lowerLoadType at ok
  split at ok
  · simp at ok
  rename_i b found
  split at ok
  · simp at ok
  rename_i i indexOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  split at ok
  case isFalse => simp at ok
  rename_i cond
  simp only [Bool.and_eq_true] at cond
  obtain ⟨hel, same⟩ := cond
  simp only [Option.some.injEq] at ok
  subst ok
  have bty := SrcType.same_eq same
  have tpos := wordElement_size hel
  simp only [lowerIndex] at indexOk
  split at indexOk
  · simp at indexOk
  rename_i t indexLowered
  simp only [indexOf] at indexOk
  split at indexOk
  case isFalse => simp at indexOk
  rename_i kind
  simp only [Option.some.injEq] at indexOk
  subst indexOk
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i v st1 valueRun
    cases fuel with
    | zero => simp [evalExpr] at valueRun
    | succ k =>
      cases k with
      | zero => simp [evalExpr] at valueRun
      | succ k =>
        obtain ⟨w, localRun, holdsW⟩ := corr.local found k sp.toCore
        rw [bty] at holdsW
        cases holdsW with
        | @slice _ len _ _ lenSlot _ =>
        obtain ⟨iv, pos', indexRun, posOk, read⟩ := eval_index_raw localRun valueRun
        have lt := readRawSliceIndex_lt read
        refine Simulates.checked (guardAnd_one (index.guard_sound corr (SrcProgram.target_toCore sp) indexLowered indexRun)
          (indexGuard_one found (x := t.expr) (by simp [lowerIndex, indexLowered, indexOf, kind])
            (by rw [lenSlot, index_toNat kind (index.lower_sound corr (SrcProgram.target_toCore sp) indexLowered indexRun).2 posOk]
                exact lt))) ?_
        obtain ⟨rfl, holdsI⟩ := index.lower_sound corr (SrcProgram.target_toCore sp) indexLowered indexRun
        have posEq := index_toNat kind holdsI posOk
        have tail := tail_bound fresh.2 run bound
        have bslot : b.slot < next := by
          have := fr.slots b (lookup_mem found).1
          rw [bty] at this
          simp only [SrcType.size] at this
          omega
        have below : (elementBase b.slot ty.size t.expr).Below next :=
          ⟨bslot, SrcExpr.lower_below fr.slots index indexLowered, trivial⟩
        obtain ⟨env2, agree, holds, load⟩ := loadElement_sound (mp := mp) hc tail hel posEq below read
        obtain ⟨fresh', keeps, d, out, exec, matched⟩ := let_tail ih (ty := ty) (st := st1)
            (env' := env2) (hp := hp) bodyOk corr fr fresh le tpos
            (fr.agree fun j lt => agree j (.inl lt)) holds hc run bound
        exact ⟨fresh', keeps, d, out, load exec, matched⟩
  all_goals simp at run

theorem stmt_setIndex_word {slice : Nat} {index value : SrcExpr} {b : Binding} {element : SrcType}
    (found : lookup scope slice = some b) (hElt : elementOf b.ty = some element)
    (hel : wordElement sp.decls element = true)
    (ok : storeWordElement b element (lowerIndex scope index) scope value = some stmt)
    (corr : Corr scope frame st env) (fresh : st.Fresh) (hc : HeapCorr st.heap st.world hp)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.setIndex slice index value).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env
      (checkThen next (guardAnd (guardAnd (index.guard scope) (indexGuard scope slice index)) (value.guard scope)) stmt)
      c st' := by
  unfold storeWordElement at ok
  split at ok
  · simp at ok
  rename_i i indexOk
  split at ok
  · simp at ok
  rename_i vs vOk
  have bty : b.ty = .slice element := by
    cases hty : b.ty <;> simp [elementOf, hty] at hElt
    rw [hElt]
  simp only [lowerIndex] at indexOk
  split at indexOk
  · simp at indexOk
  rename_i t indexLowered
  simp only [indexOf] at indexOk
  split at indexOk
  case isFalse => simp at indexOk
  rename_i kind
  simp only [Option.some.injEq] at indexOk
  subst indexOk
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i u st1 assignRun
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    cases fuel with
    | zero => simp [evalExpr] at assignRun
    | succ k =>
    cases k with
    | zero => simp [evalExpr, Semantics.evalPlace] at assignRun
    | succ k =>
    cases k with
    | zero => simp [evalExpr, Semantics.evalPlace] at assignRun
    | succ k =>
    obtain ⟨w, place, holdsW⟩ := corr.readPlace found k sp.toCore
    rw [bty] at holdsW
    cases holdsW with
    | @slice _ len _ _ lenSlot _ =>
    obtain ⟨iv, pos', at_, right, heap, indexRun, posOk, posLt, located, valueRun, stored, rfl⟩ :=
      eval_setIndex_raw fresh.2 index.eval_state value.eval_state place assignRun
    refine Simulates.checked (guardAnd_one (guardAnd_one (index.guard_sound corr (SrcProgram.target_toCore sp) indexLowered indexRun)
      (indexGuard_one found (x := t.expr) (by simp [lowerIndex, indexLowered, indexOf, kind])
        (by rw [lenSlot, index_toNat kind (index.lower_sound corr (SrcProgram.target_toCore sp) indexLowered indexRun).2 posOk]
            exact posLt)))
      (lowerValue_guard corr (SrcProgram.target_toCore sp) vOk valueRun)) ?_
    obtain ⟨-, holdsI⟩ := index.lower_sound corr (SrcProgram.target_toCore sp) indexLowered indexRun
    have posEq := index_toNat kind holdsI posOk
    obtain ⟨-, flat, -⟩ := lowerValue_sound corr (SrcProgram.target_toCore sp) vOk valueRun
    obtain ⟨hp', exec, hc'⟩ := storeElement_sound (mp := mp) hc hel posEq located stored flat ok bound
    exact ⟨fresh, ⟨fun _ _ => rfl, Nat.le_refl _⟩, 0, _, exec, .next (corr.cells_congr rfl fun _ _ => rfl) hc'⟩
  all_goals simp at run

theorem stmt_letIndex (ih : StmtSound sp mp fuel) {id : Nat} {ty : SrcType} {slice : Nat}
    {index : SrcExpr} {body : SrcStmt}
    (ok : (SrcStmt.letIndex id ty slice index body).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell) (hc : HeapCorr st.heap st.world hp)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.letIndex id ty slice index body).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerLetIndex] at ok
  split at ok
  · exact stmt_letIndex_i32 ih ok corr fr fresh le hc run bound
  · exact stmt_letIndex_word ih ok corr fr fresh le hc run bound

theorem stmt_setIndex {slice : Nat} {index value : SrcExpr}
    (ok : (SrcStmt.setIndex slice index value).lower (sigs sp.funcs) sp.decls ret scope next = some stmt)
    (corr : Corr scope frame st env) (fresh : st.Fresh) (hc : HeapCorr st.heap st.world hp)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.setIndex slice index value).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower] at ok
  replace ok := guarded_some ok
  obtain ⟨stmt, ok, rfl⟩ := ok
  simp only [lowerSetIndex] at ok
  split at ok
  · simp at ok
  rename_i b found
  simp only [lowerSetIndexOf] at ok
  split at ok
  · simp at ok
  rename_i element hElt
  simp only [storeAny] at ok
  split at ok
  · exact stmt_setIndex_i32 found hElt ok corr fresh hc run bound
  · split at ok
    · rename_i _ hel
      exact stmt_setIndex_word found hElt hel ok corr fresh hc run bound
    · simp at ok

end Statements

end Lanius.Mini
