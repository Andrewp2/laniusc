import Lanius.Mini.CompileCorrect
import Lanius.Mini.LowerExpr

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
  | call found arity counted inner body _ => exact .call found arity counted (Nat.lt_of_lt_of_le inner le) body
  | ret => exact .ret
  | alloc room => exact .alloc room
  | loadByte inside => exact .loadByte inside
  | storeByte inside => exact .storeByte inside

/-! ## Programs -/

mutual
theorem SrcType.eq_of_same : ∀ (a : SrcType) {b : SrcType}, a.same b = true → a = b
  | .i32, b, same => by cases b <;> simp_all [SrcType.same, SrcType.isI32]
  | .bool, b, same => by cases b <;> simp_all [SrcType.same, SrcType.isBool]
  | .uint k, b, same => (SrcType.eq_of_isUint (by simpa [SrcType.same] using same)).symm
  | .struct id fs, b, same => by
    cases b with
    | struct id' gs =>
      simp only [SrcType.same, Bool.and_eq_true, decide_eq_true_eq] at same
      rw [same.1, typesSame_eq fs same.2]
    | i32 => simp [SrcType.same] at same
    | bool => simp [SrcType.same] at same
    | uint => simp [SrcType.same] at same
    | enum => simp [SrcType.same] at same
  | .enum id vs, b, same => by
    cases b with
    | enum id' ws =>
      simp only [SrcType.same, Bool.and_eq_true, decide_eq_true_eq] at same
      rw [same.1, variantsSame_eq vs same.2]
    | i32 => simp [SrcType.same] at same
    | bool => simp [SrcType.same] at same
    | uint => simp [SrcType.same] at same
    | struct => simp [SrcType.same] at same

theorem typesSame_eq : ∀ (fs : List SrcType) {gs : List SrcType}, typesSame fs gs = true → fs = gs
  | [], gs, same => by cases gs <;> simp_all [typesSame]
  | f :: fs, gs, same => by
    cases gs with
    | nil => simp [typesSame] at same
    | cons g gs =>
      simp only [typesSame, Bool.and_eq_true] at same
      rw [SrcType.eq_of_same f same.1, typesSame_eq fs same.2]

theorem variantsSame_eq : ∀ (vs : List (List SrcType)) {ws : List (List SrcType)},
    variantsSame vs ws = true → vs = ws
  | [], ws, same => by cases ws <;> simp_all [variantsSame]
  | v :: vs, ws, same => by
    cases ws with
    | nil => simp [variantsSame] at same
    | cons w ws =>
      simp only [variantsSame, Bool.and_eq_true] at same
      rw [typesSame_eq v same.1, variantsSame_eq vs same.2]
end

theorem SrcType.same_eq {a b : SrcType} (same : a.same b = true) : a = b := SrcType.eq_of_same a same

theorem SrcType.toCore_ne_unit (ty : SrcType) : ty.toCore ≠ .unit := by
  cases ty <;> simp [SrcType.toCore]

theorem find_coreFuncs (funcs : List SrcFunc) (off i : Nat) (le : off ≤ i) :
    (coreFuncs off funcs).find? (fun function => function.id == i) =
      (funcs[i - off]?).map (SrcFunc.toCore i) := by
  induction funcs generalizing off with
  | nil => simp [coreFuncs]
  | cons head rest ih =>
    simp only [coreFuncs]
    by_cases eq : off = i
    · subst eq
      rw [List.find?_cons_of_pos (by simp [SrcFunc.toCore])]
      simp
    · rw [List.find?_cons_of_neg (by simp [SrcFunc.toCore]; omega), ih (off + 1) (by omega)]
      have : i - off = (i - (off + 1)) + 1 := by omega
      rw [this]
      simp

theorem SrcProgram.function?_toCore (sp : SrcProgram) (i : Nat) :
    sp.toCore.function? i = (sp.funcs[i]?).map (SrcFunc.toCore i) := by
  simp only [Core.Program.function?, SrcProgram.toCore]
  rw [find_coreFuncs _ 0 i (Nat.zero_le _)]
  rfl

theorem sigs_get (funcs : List SrcFunc) (i : Nat) :
    (sigs funcs)[i]? = (funcs[i]?).map fun f => ({ params := paramTypes f.params, ret := f.ret } : Sig) := by
  induction funcs generalizing i with
  | nil => simp [sigs]
  | cons head rest ih => cases i <;> simp [sigs, ih]

theorem lowerFuncs_get {sg : List Sig} {funcs : List SrcFunc} {lowered : List Func}
    (ok : lowerFuncs sg funcs = some lowered) {i : Nat} {f : SrcFunc} (found : funcs[i]? = some f) :
    ∃ g, lowered[i]? = some g ∧ lowerFunc sg f = some g := by
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

theorem lowerFunc_some {sg : List Sig} {f : SrcFunc} {g : Func} (ok : lowerFunc sg f = some g) :
    g.params = paramsSize f.params ∧ 0 < f.ret.size ∧ paramsValid f.params = true ∧
      f.body.lower sg f.ret (paramScope f.params 0 []) (paramsSize f.params) = some g.body := by
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
    exact ⟨rfl, checks.1, checks.2, bodyOk⟩
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
      simp at ok
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

/-! ## Calls -/

def paramBindings (params : List SrcParam) (values : List Value) : List (Nat × Value) :=
  ((params.map fun p => (p.id, p.ty.toCore)).zip values).map fun pair => (pair.1.1, pair.2)

theorem bindParameters_eq (params : List SrcParam) (values : List Value)
    (len : values.length = params.length) :
    Semantics.bindParameters (params.map fun p => (p.id, p.ty.toCore)) values =
      some (paramBindings params values) := by
  simp [Semantics.bindParameters, len, paramBindings]

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

/-- What a Core call that returned did. -/
theorem call_inv {sp : SrcProgram} {fuel : Nat} {st : State} {callee : Nat} {args : List Core.Expr}
    {v : Value} {st' : State}
    (run : evalExpr (fuel + 1) sp.toCore st (.call callee args) = .done v st') :
    ∃ f values afterArgs completed, evalExprs fuel sp.toCore st args = .done values afterArgs ∧
      sp.funcs[callee]? = some f ∧ values.length = f.params.length ∧
      execStmt fuel sp.toCore (({ afterArgs with locals := [] } : State).bindLocals
        (paramBindings f.params values)) f.body.toCore = .done (.returned (some v)) completed ∧
      st' = restoreLocals afterArgs completed := by
  simp only [evalExpr] at run
  split at run
  · rename_i values afterArgs argsRun
    rw [SrcProgram.function?_toCore] at run
    cases found : sp.funcs[callee]? with
    | none => simp [found] at run
    | some f =>
      simp only [found, Option.map_some, SrcFunc.toCore] at run
      by_cases len : values.length = f.params.length
      · rw [bindParameters_eq _ _ len] at run
        simp only at run
        split at run
        · rename_i value completed bodyRun
          simp only [Semantics.Outcome.done.injEq] at run
          obtain ⟨rfl, rfl⟩ := run
          exact ⟨f, values, afterArgs, completed, argsRun, rfl, len, bodyRun, rfl⟩
        all_goals simp_all [SrcType.toCore_ne_unit]
      · have : Semantics.bindParameters (f.params.map fun p => (p.id, p.ty.toCore)) values = none := by
          simp [Semantics.bindParameters]; omega
        simp [this] at run
  all_goals simp at run

/-! ## The simulation -/

/-- A Core completion and a mini outcome that agree: both fall through with
the scope still in correspondence, or both return represented values. -/
inductive Matches (ret : SrcType) (scope : List Binding) (frame : Nat → Nat) (st : State) (hp : Heap) :
    Completion → Outcome → Prop where
  | next {env : Env} : Corr scope frame st env → Matches ret scope frame st hp .next (.normal env hp)
  | returned {v : Value} {bits : List (BitVec 64)} :
      ret.HoldsAt v (Func.entry bits) 0 → bits.length = ret.size →
      Matches ret scope frame st hp (.returned (some v)) (.returned bits hp)

/-- Core went from `st` to `st'` with completion `c`; the mini statement has a
derivation from `env` with a matching outcome. -/
abbrev Simulates (mp : Program) (hp : Heap) (ret : SrcType) (scope : List Binding) (frame : Nat → Nat)
    (base : Nat) (st : State) (env : Env) (stmt : Stmt) (c : Completion) (st' : State) : Prop :=
  st'.Fresh ∧ Keeps base st st' ∧ ∃ d out, Exec mp d env hp stmt out ∧ Matches ret scope frame st' hp c out

/-- Every statement lowered for `sp` that Core runs to completion with `fuel`
has a mini derivation with a matching outcome. -/
def StmtSound (sp : SrcProgram) (mp : Program) (fuel : Nat) : Prop :=
  ∀ {hp : Heap} {s : SrcStmt} {ret : SrcType} {scope : List Binding} {next : Nat} {stmt : Stmt}
    {frame : Nat → Nat} {base : Nat} {st : State} {env : Env} {c : Completion} {st' : State},
    s.lower (sigs sp.funcs) ret scope next = some stmt →
    Corr scope frame st env → Layout scope frame base next → st.Fresh → base ≤ st.nextCell →
    execStmt fuel sp.toCore st s.toCore = .done c st' →
    Simulates mp hp ret scope frame base st env stmt c st'

theorem SrcProgram.target_toCore (sp : SrcProgram) : sp.toCore.target = .x86_64 := rfl

/-- A function body Core runs to a return is a mini `Returns`. -/
theorem body_sound {sp : SrcProgram} {mp : Program}
    (lowered : lowerFuncs (sigs sp.funcs) sp.funcs = some mp.funcs) {fuel : Nat}
    (ih : StmtSound sp mp fuel) {callee : Nat} {f : SrcFunc} (found : sp.funcs[callee]? = some f)
    {hp : Heap} {st : State} (fresh : st.Fresh) {values : List Value} {bits : List (BitVec 64)}
    (holds : FieldsHold (paramTypes f.params) values (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize f.params) {v : Value} {completed : State}
    (run : execStmt fuel sp.toCore (({ st with locals := [] } : State).bindLocals
      (paramBindings f.params values)) f.body.toCore = .done (.returned (some v)) completed) :
    completed.Fresh ∧ Keeps st.nextCell st completed ∧
      ∃ d rs, mp.Returns d callee bits hp rs hp ∧ f.ret.HoldsAt v (Func.entry rs) 0 ∧ rs.length = f.ret.size := by
  obtain ⟨g, gFound, gOk⟩ := lowerFuncs_get lowered found
  obtain ⟨gParams, _, valid, bodyOk⟩ := lowerFunc_some gOk
  obtain ⟨frame, corr, fr, fresh0, keeps0⟩ := entry_corr (Func.entry bits) st.nextCell f.params
    (k := 0) (scope := []) (frame := fun _ => 0) (st := { st with locals := [] }) holds valid
    (Nat.le_refl _) fresh ⟨rfl, fun _ mem => by simp at mem⟩
    ⟨fun _ mem => by simp at mem, fun _ mem => by simp at mem, fun _ mem => by simp at mem,
      fun _ mem => by simp at mem, fun _ mem => by simp at mem⟩
  rw [Nat.zero_add] at fr
  obtain ⟨freshDone, keepsDone, d, out, exec, agree⟩ :=
    ih (hp := hp) bodyOk corr fr fresh0 keeps0.next run
  cases agree with
  | returned holdsRet len =>
    exact ⟨freshDone, ⟨fun c below => (keepsDone.cells c below).trans (keeps0.cells c below),
      Nat.le_trans keeps0.next keepsDone.next⟩, d, _, ⟨g, gFound, by rw [gParams, bitsLen], exec⟩, holdsRet, len⟩

/-- A lowered call that Core completes: the caller's locals and cells are as
they were, and the mini call stores slots representing the result. -/
theorem call_sound {sp : SrcProgram} {mp : Program}
    (lowered : lowerFuncs (sigs sp.funcs) sp.funcs = some mp.funcs) {fuel : Nat}
    (ih : StmtSound sp mp fuel) {hp : Heap} {scope frame st env} (corr : Corr scope frame st env)
    (fresh : st.Fresh) {callee : Nat} {args : List SrcExpr} {ty : SrcType} {es : List Expr}
    (ok : lowerCall (sigs sp.funcs) scope callee args ty = some es) {v : Value} {st' : State}
    (run : evalExpr (fuel + 1) sp.toCore st (.call callee (args.map SrcExpr.toCore)) = .done v st') :
    st'.Fresh ∧ Keeps st.nextCell st st' ∧ st'.locals = st.locals ∧ 0 < ty.size ∧
      ∃ d rs, ty.HoldsAt v (Func.entry rs) 0 ∧ rs.length = ty.size ∧
        ∀ target, Exec mp d env hp (.call target ty.size callee es) (.normal (env.setMany target rs) hp) := by
  obtain ⟨f, values, afterArgs, completed, argsRun, found, _, bodyRun, rfl⟩ := call_inv run
  simp only [lowerCall, sigs_get, found, Option.map_some, lowerCallSig] at ok
  split at ok
  · rename_i same
    have tyEq := SrcType.same_eq same
    subst tyEq
    obtain ⟨rfl, holds, esLen, -⟩ := lowerArgs_sound corr (SrcProgram.target_toCore sp) ok argsRun
    obtain ⟨freshDone, keeps, d, rs, ⟨g, gFound, arity, exec⟩, holdsRet, len⟩ :=
      body_sound lowered ih found (hp := hp) fresh holds (by rw [evalAll_length, esLen, paramsSize_eq]) bodyRun
    obtain ⟨g', -, gOk⟩ := lowerFuncs_get lowered found
    refine ⟨restore_fresh freshDone, keeps.trans (restore_keeps _ _ _), rfl, (lowerFunc_some gOk).2.1, d + 1, rs,
      holdsRet, len, fun target => .call gFound ?_ len (Nat.lt_succ_self d) exec⟩
    rw [← arity, evalAll_length]
  · simp at ok

/-- The slots a call stores hold the value its callee returned. -/
theorem setMany_holds {ty : SrcType} {v : Value} {rs : List (BitVec 64)} (holds : ty.HoldsAt v (Func.entry rs) 0)
    (len : rs.length = ty.size) (env : Env) (slot : Nat) : ty.HoldsAt v (env.setMany slot rs) slot :=
  holds.congr fun i below => by
    rw [setMany_eq, if_pos (by omega), Nat.zero_add, Nat.add_sub_cancel_left]
    rfl

/-! ## Assignment and `let` -/

theorem sync_ok {st : State} (views : st.i32ArrayViews = []) : Semantics.syncI32ViewsToHeap st = .ok st := by
  simp [Semantics.syncI32ViewsToHeap, views, Semantics.syncI32ViewsToHeapFrom]

/-- Core's `id = e` on a local of the scope: it evaluates `e`, then replaces
the local's cell. -/
theorem assign_step {P : Core.Program} {scope frame st env} (corr : Corr scope frame st env)
    {id : Nat} {b : Binding} (found : lookup scope id = some b) {e : Core.Expr} {k : Nat}
    {u : Value} {st' : State}
    (run : evalExpr (k + 1) P st (.assign .set (.local id) e) = .done u st')
    (after : ∀ {rv st2}, evalExpr k P st e = .done rv st2 →
      (st2.cellEntry? (frame b.slot)).isSome ∧ st2.i32ArrayViews = []) :
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
      obtain ⟨present, views⟩ := after valueRun
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

theorem castTo_below {n : Nat} {ty : SrcType} {inner t : Typed} (h : castTo ty inner = some t)
    (below : inner.expr.Below n) : t.expr.Below n := by
  cases ty with
  | i32 =>
    simp only [castTo, castToI32] at h
    split at h <;> simp only [Option.some.injEq, reduceCtorEq] at h <;> subst h
    · exact below
    · exact below.wrap .uint32
  | uint kind =>
    simp only [castTo, castToUint] at h
    split at h <;> simp only [Option.some.injEq, reduceCtorEq] at h <;> subst h
    · simp only [fromI32]
      split
      · exact ⟨below, ⟨below, trivial⟩, trivial⟩
      · exact below.wrap kind
    · exact below.wrap kind
  | bool => simp [castTo] at h
  | struct => simp [castTo] at h
  | enum => simp [castTo] at h

theorem SrcExpr.lower_below {scope : List Binding} {next : Nat}
    (slots : ∀ b ∈ scope, b.slot + b.ty.size ≤ next) :
    ∀ (e : SrcExpr) {t : Typed}, e.lower scope = some t → t.expr.Below next := by
  intro e
  induction e with
  | int x => intro t lowered; simp only [SrcExpr.lower, Option.some.injEq] at lowered; subst lowered; trivial
  | boolean x => intro t lowered; simp only [SrcExpr.lower, Option.some.injEq] at lowered; subst lowered; trivial
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
    · simp at lowered
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
    case plus | minus | times | bitAnd | bitOr | bitXor =>
      simp only [SrcOp.lower, arith] at lowered
      split at lowered
      · simp only [Option.some.injEq] at lowered
        subst lowered
        exact ⟨bl, br⟩
      · obtain ⟨k, -, -, rfl⟩ := arithUint_some lowered
        exact Expr.Below.wrap (e := .binary .u64 _ _ _) ⟨bl, br⟩ k
    case less | lessEq | greater | greaterEq =>
      simp only [SrcOp.lower, order] at lowered
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
    (bodyOk : body.lower (sigs sp.funcs) ret (⟨id, next, ty⟩ :: scope) (next + ty.size) = some bstmt)
    {frame base st env} (corr : Corr scope frame st env) (fr : Layout scope frame base next)
    (fresh : st.Fresh) (le : base ≤ st.nextCell) (sized : 0 < ty.size) {v : Value} {env' : Env}
    (agree : ScopeAgree scope env env') (holds : ty.HoldsAt v env' next)
    {c : Completion} {st' : State}
    (run : Semantics.restoreOutcomeLocals st
      (execStmt fuel sp.toCore (st.bindLocal id v) body.toCore) = .done c st') :
    st'.Fresh ∧ Keeps base st st' ∧
      ∃ d out, Exec mp d env' hp bstmt out ∧ Matches ret scope frame st' hp c out := by
  cases bodyRun : execStmt fuel sp.toCore (st.bindLocal id v) body.toCore with
  | done c' st'' =>
    simp only [bodyRun, Semantics.restoreOutcomeLocals, Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    have pushed := corr.push fr fresh agree (id := id) holds
    have frPushed := fr.push (corr.below fresh) le id sized
    obtain ⟨fresh'', keeps'', d, out, exec, matched⟩ :=
      ih (hp := hp) bodyOk pushed frPushed (bindLocal_fresh fresh id v)
        (Nat.le_trans le (Nat.le_succ _)) bodyRun
    refine ⟨restore_fresh fresh'', (bindLocal_keeps le id v).trans
      (keeps''.trans (restore_keeps _ _ _)), d, out, exec, ?_⟩
    cases matched with
    | next corr'' => exact .next (corr''.pop fr corr.locals rfl)
    | returned holdsRet len => exact .returned holdsRet len
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
            obtain ⟨rfl, flat, shape⟩ := lowerValue_sound corr' target valueOk armRun
            have slots' := armScope_slots arm.binders scopeOk slots (room _ (List.mem_cons_self ..))
            refine ⟨restore_fresh fresh', keeps'.trans (restore_keeps _ _ _), rfl, xs, flat,
              Insens.below fun x mem => shape.below slots' x mem, fun d => ?_⟩
            split at ok
            · simp only [Option.some.injEq] at ok
              subst ok
              exact assignFrom_exec xs dst .skip
            · split at ok
              · simp at ok
              · simp only [Option.some.injEq] at ok
                subst ok
                exact .ifTrue (by simp [Expr.eval, Word.holds, CmpOp.holdsU, tag]) (assignFrom_exec xs dst .skip)
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

section Statements

variable {sp : SrcProgram} {mp : Program} {fuel : Nat} {ret : SrcType} {scope : List Binding}
  {next : Nat} {stmt : Stmt} {frame : Nat → Nat} {base : Nat} {st : State} {env : Env}
  {c : Completion} {st' : State} {hp : Heap}

theorem stmt_nop (ok : SrcStmt.nop.lower (sigs sp.funcs) ret scope next = some stmt)
    (corr : Corr scope frame st env) (fresh : st.Fresh)
    (run : execStmt (fuel + 1) sp.toCore st SrcStmt.nop.toCore = .done c st') :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore, execStmt, Semantics.Outcome.done.injEq] at run
  obtain ⟨rfl, rfl⟩ := run
  exact ⟨fresh, Keeps.refl _ _, 0, _, .skip, .next corr⟩

theorem stmt_let (ih : StmtSound sp mp fuel) {id : Nat} {ty : SrcType} {value : SrcExpr}
    {body : SrcStmt} (ok : (SrcStmt.let id ty value body).lower (sigs sp.funcs) ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.let id ty value body).toCore = .done c st') :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerLet] at ok
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
    obtain ⟨rfl, flat, shape⟩ := lowerValue_sound corr (SrcProgram.target_toCore sp) valueOk valueRun
    obtain ⟨fresh', keeps, d, out, exec, matched⟩ := let_tail ih (hp := hp) bodyOk corr fr fresh le
      (by rw [← flat.length]; exact shape.sized fr)
      (fr.agree fun j below => setFrom_outside xs next env j (.inl below))
      (flat.store (shape.insens_next fr)) run
    exact ⟨fresh', keeps, d, out, assignFrom_exec xs next exec, matched⟩
  all_goals simp at run

theorem stmt_letStruct (ih : StmtSound sp mp fuel) {id : Nat} {ty : SrcType} {fields : List SrcExpr}
    {body : SrcStmt}
    (ok : (SrcStmt.letStruct id ty fields body).lower (sigs sp.funcs) ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.letStruct id ty fields body).toCore = .done c st') :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerLet] at ok
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
            (flat.store insens) run
          exact ⟨fresh', keeps, d, out, assignFrom_exec xs next exec, matched⟩
        all_goals simp at valueRun
    all_goals simp at run

theorem stmt_letCall (lowered : lowerFuncs (sigs sp.funcs) sp.funcs = some mp.funcs)
    (ih : ∀ m ≤ fuel, StmtSound sp mp m) {id : Nat} {ty : SrcType} {callee : Nat}
    {args : List SrcExpr} {body : SrcStmt}
    (ok : (SrcStmt.letCall id ty callee args body).lower (sigs sp.funcs) ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.letCall id ty callee args body).toCore =
      .done c st') :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerLetCall] at ok
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
      obtain ⟨fresh1, keeps1, locals1, sized, d1, rs, holds, len, callExec⟩ :=
        call_sound lowered (ih k (Nat.le_succ _)) corr fresh argsOk callRun
      have corr1 := corr.keeps fresh keeps1 locals1
      obtain ⟨fresh', keeps', d2, out, exec, matched⟩ :=
        let_tail (ih (k + 1) (Nat.le_refl _)) bodyOk corr1 fr fresh1
          (Nat.le_trans le keeps1.next) sized (env' := env.setMany next rs)
          (fr.agree fun j below => by rw [setMany_eq, if_neg (by omega)])
          (setMany_holds holds len env next) run
      exact ⟨fresh', (keeps1.lower le).trans keeps', max d1 d2, out,
        .seq ((callExec next).mono (Nat.le_max_left _ _)) (exec.mono (Nat.le_max_right _ _)), matched⟩
  all_goals simp at run

theorem stmt_letEnum (ih : StmtSound sp mp fuel) {id : Nat} {ty : SrcType} {variant : Nat}
    {payload : List SrcExpr} {body : SrcStmt}
    (ok : (SrcStmt.letEnum id ty variant payload body).lower (sigs sp.funcs) ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.letEnum id ty variant payload body).toCore =
      .done c st') :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerLet] at ok
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
            (fr.agree fun j below => setFrom_outside _ next env j (.inl below)) holds run
          exact ⟨fresh', keeps, d, out, assignFrom_exec _ next exec, matched⟩
        all_goals simp at valueRun
    all_goals simp at run

theorem stmt_letMatch (ih : StmtSound sp mp fuel) {id : Nat} {ty : SrcType} {scrutinee enumId : Nat}
    {arms : List SrcArm} {body : SrcStmt}
    (ok : (SrcStmt.letMatch id ty scrutinee enumId arms body).lower (sigs sp.funcs) ret scope next =
      some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.letMatch id ty scrutinee enumId arms body).toCore =
      .done c st') :
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
        obtain ⟨fresh', keeps', d, out, exec, matched⟩ :=
          let_tail ih (hp := hp) bodyOk corr1 fr fresh1 (Nat.le_trans le keeps1.next)
            sized (env' := env.setFrom next xs)
            (fr.agree fun j below => setFrom_outside xs next env j (.inl below))
            (flat.store insens) run
        exact ⟨fresh', (keeps1.lower le).trans keeps', d, out, .seq (mexec d) exec, matched⟩
  all_goals simp at run

theorem stmt_set {id : Nat} {value : SrcExpr}
    (ok : (SrcStmt.set id value).lower (sigs sp.funcs) ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.set id value).toCore = .done c st') :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerSet] at ok
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
        obtain ⟨v0, entry, _⟩ := corr.values b bmem
        exact ⟨by simp [entry], fresh.2⟩
      obtain ⟨rfl, flat, shape⟩ := lowerValue_sound corr (SrcProgram.target_toCore sp) valueOk valueRun
      have stored := flat.store (shape.insens_self fr bmem flat.length)
      refine ⟨assigned_fresh fresh _ _, assigned_keeps (fr.above b bmem) _ _, 0, _,
        assignFrom_exec xs b.slot .skip, .next (corr.assign fr bmem (fun j away => ?_) stored)⟩
      exact setFrom_outside xs b.slot env j (by rw [flat.length]; exact away)
  all_goals simp at run

theorem stmt_setField {id index : Nat} {value : SrcExpr}
    (ok : (SrcStmt.setField id index value).lower (sigs sp.funcs) ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.setField id index value).toCore = .done c st') :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerSetField] at ok
  split at ok
  · simp at ok
  rename_i b found
  simp only [lowerSetFieldOf] at ok
  split at ok
  · simp at ok
  · simp at ok
  · simp at ok
  case h_5 => simp at ok
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
      obtain ⟨_, holds⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) valueOk valueRun
      have inRange := fieldOffset_lt fieldFound
      have one := SrcType.size_scalar scalar
      refine ⟨assigned_fresh fresh _ _, assigned_keeps (fr.above b bmem) _ _, 0, _, .assign,
        .next (corr.assign fr bmem (fun j away => ?_) ?_)⟩
      · simp only [Env.set]
        rw [hty] at away
        simp only [SrcType.size] at away
        rw [if_neg (by omega)]
      · rw [hty]
        exact .struct (fieldsHold.set fieldFound scalar holds)
  all_goals simp at run

theorem stmt_setCall (lowered : lowerFuncs (sigs sp.funcs) sp.funcs = some mp.funcs)
    (ih : ∀ m ≤ fuel, StmtSound sp mp m) {id callee : Nat} {args : List SrcExpr}
    (ok : (SrcStmt.setCall id callee args).lower (sigs sp.funcs) ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.setCall id callee args).toCore = .done c st') :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerSetCall] at ok
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
      have callFacts : ∀ {rv st2}, evalExpr k sp.toCore st
          (.call callee (args.map SrcExpr.toCore)) = .done rv st2 →
          st2.Fresh ∧ Keeps st.nextCell st st2 ∧ st2.locals = st.locals ∧
            ∃ d rs, b.ty.HoldsAt rv (Func.entry rs) 0 ∧ rs.length = b.ty.size ∧
              ∀ target, Exec mp d env hp (.call target b.ty.size callee es) (.normal (env.setMany target rs) hp) := by
        intro rv st2 callRun
        cases k with
        | zero => simp [evalExpr] at callRun
        | succ j =>
          obtain ⟨f1, f2, f3, _, rest⟩ := call_sound lowered (ih j (by omega)) corr fresh argsOk callRun
          exact ⟨f1, f2, f3, rest⟩
      obtain ⟨rv, st2, callRun, rfl⟩ := assign_step corr found assignRun fun callRun => by
        obtain ⟨fresh2, keeps, _, _⟩ := callFacts callRun
        obtain ⟨v0, entry, _⟩ := corr.values b bmem
        rw [keeps.cells _ (corr.below fresh b bmem)]
        exact ⟨by simp [entry], fresh2.2⟩
      obtain ⟨fresh2, keeps2, locals2, d, rs, holds, len, callExec⟩ := callFacts callRun
      have corr2 := corr.keeps fresh keeps2 locals2
      refine ⟨assigned_fresh fresh2 _ _, (keeps2.lower le).trans (assigned_keeps (fr.above b bmem) _ _),
        d, _, callExec b.slot, .next (corr2.assign fr bmem (fun j away => ?_) (setMany_holds holds len env b.slot))⟩
      rw [setMany_eq, if_neg (by omega)]
  all_goals simp at run

theorem stmt_then (ih : StmtSound sp mp fuel) {first second : SrcStmt}
    (ok : (SrcStmt.then first second).lower (sigs sp.funcs) ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.then first second).toCore = .done c st') :
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
    obtain ⟨fresh1, keeps1, d1, out1, exec1, matched1⟩ := ih (hp := hp) firstOk corr fr fresh le firstRun
    cases matched1 with
    | next corr1 =>
      obtain ⟨fresh2, keeps2, d2, out2, exec2, matched2⟩ :=
        ih (hp := hp) secondOk corr1 fr fresh1 (Nat.le_trans le keeps1.next) run
      exact ⟨fresh2, keeps1.trans keeps2, max d1 d2, out2,
        .seq (exec1.mono (Nat.le_max_left _ _)) (exec2.mono (Nat.le_max_right _ _)), matched2⟩
  · rename_i completion mid notNext firstRun
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    obtain ⟨fresh1, keeps1, d1, out1, exec1, matched1⟩ := ih (hp := hp) firstOk corr fr fresh le firstRun
    cases matched1 with
    | next => exact absurd rfl notNext
    | returned holds len => exact ⟨fresh1, keeps1, d1, _, .seqReturned exec1, .returned holds len⟩
  all_goals simp at run

theorem stmt_if (ih : StmtSound sp mp fuel) {condition : SrcExpr} {thenBranch elseBranch : SrcStmt}
    (ok : (SrcStmt.if condition thenBranch elseBranch).lower (sigs sp.funcs) ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.if condition thenBranch elseBranch).toCore =
      .done c st') :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerIf] at ok
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
    obtain ⟨fresh', keeps, d, out, exec, matched⟩ := ih (hp := hp) thenOk corr fr fresh le run
    exact ⟨fresh', keeps, d, out, .ifTrue (by rw [bits]; decide) exec, matched⟩
  · rename_i mid condRun
    obtain ⟨rfl, y, hy, bits⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) condOk condRun
    cases hy
    obtain ⟨fresh', keeps, d, out, exec, matched⟩ := ih (hp := hp) elseOk corr fr fresh le run
    exact ⟨fresh', keeps, d, out, .ifFalse (by rw [bits]; decide) exec, matched⟩
  · rename_i w mid notTrue notFalse condRun
    obtain ⟨rfl, y, rfl, _⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) condOk condRun
    cases y <;> simp_all
  all_goals simp at run

theorem stmt_while (ih : StmtSound sp mp fuel) {condition : SrcExpr} {body : SrcStmt}
    (ok : (SrcStmt.while condition body).lower (sigs sp.funcs) ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.while condition body).toCore = .done c st') :
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
    obtain ⟨rfl, y, hy, bits⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) condOk condRun
    cases hy
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    exact ⟨fresh, Keeps.refl _ _, 0, _, .loopDone (by rw [bits]; decide), .next corr⟩
  · rename_i mid condRun
    obtain ⟨rfl, y, hy, bits⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) condOk condRun
    cases hy
    have condTrue : x.eval env ≠ 0 := by rw [bits]; decide
    split at run
    · rename_i completed bodyRun
      obtain ⟨fresh1, keeps1, d1, out1, exec1, matched1⟩ := ih (hp := hp) bodyOk corr fr fresh le bodyRun
      cases matched1 with
      | next corr1 =>
        obtain ⟨fresh2, keeps2, d2, out2, exec2, matched2⟩ :=
          ih (hp := hp) whileOk corr1 fr fresh1 (Nat.le_trans le keeps1.next) run
        exact ⟨fresh2, keeps1.trans keeps2, max d1 d2, out2,
          .loopNext condTrue (exec1.mono (Nat.le_max_left _ _)) (exec2.mono (Nat.le_max_right _ _)),
          matched2⟩
    · rename_i completed bodyRun
      obtain ⟨_, _, _, _, _, matched1⟩ := ih (hp := hp) bodyOk corr fr fresh le bodyRun
      cases matched1
    · rename_i completed bodyRun
      obtain ⟨_, _, _, _, _, matched1⟩ := ih (hp := hp) bodyOk corr fr fresh le bodyRun
      cases matched1
    · rename_i value completed bodyRun
      simp only [Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, rfl⟩ := run
      obtain ⟨fresh1, keeps1, d1, out1, exec1, matched1⟩ := ih (hp := hp) bodyOk corr fr fresh le bodyRun
      cases matched1 with
      | returned holds len => exact ⟨fresh1, keeps1, d1, _, .loopReturned condTrue exec1, .returned holds len⟩
    all_goals simp at run
  · rename_i w mid notFalse notTrue condRun
    obtain ⟨rfl, y, rfl, _⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) condOk condRun
    cases y <;> simp_all
  all_goals simp at run

theorem stmt_return {value : SrcExpr}
    (ok : (SrcStmt.return value).lower (sigs sp.funcs) ret scope next = some stmt)
    (corr : Corr scope frame st env) (fresh : st.Fresh)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.return value).toCore = .done c st') :
    Simulates mp hp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerReturn] at ok
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
    obtain ⟨rfl, flat, -⟩ := lowerValue_sound corr (SrcProgram.target_toCore sp) valueOk valueRun
    exact ⟨fresh, Keeps.refl _ _, 0, _, .ret, .returned flat.holds (by rw [evalAll_length, flat.length])⟩
  all_goals simp at run

end Statements

/-- The simulation, by induction on Core's fuel. -/
theorem stmt_sound {sp : SrcProgram} {mp : Program}
    (lowered : lowerFuncs (sigs sp.funcs) sp.funcs = some mp.funcs) : ∀ fuel, StmtSound sp mp fuel := by
  intro fuel
  induction fuel using Nat.strongRecOn with
  | _ fuel ih =>
    intro hp s ret scope next stmt frame base st env c st' ok corr fr fresh le run
    cases fuel with
    | zero => simp [execStmt] at run
    | succ fuel =>
      have below : ∀ m ≤ fuel, StmtSound sp mp m := fun m h => ih m (Nat.lt_succ_of_le h)
      have here : StmtSound sp mp fuel := below fuel (Nat.le_refl _)
      cases s with
      | nop => exact stmt_nop ok corr fresh run
      | «let» => exact stmt_let here ok corr fr fresh le run
      | letStruct => exact stmt_letStruct here ok corr fr fresh le run
      | letCall => exact stmt_letCall lowered below ok corr fr fresh le run
      | letEnum => exact stmt_letEnum here ok corr fr fresh le run
      | letMatch => exact stmt_letMatch here ok corr fr fresh le run
      | set => exact stmt_set ok corr fr fresh run
      | setField => exact stmt_setField ok corr fr fresh run
      | setCall => exact stmt_setCall lowered below ok corr fr fresh le run
      | «then» => exact stmt_then here ok corr fr fresh le run
      | «if» => exact stmt_if here ok corr fr fresh le run
      | «while» => exact stmt_while here ok corr fr fresh le run
      | «return» => exact stmt_return ok corr fresh run

end Lanius.Mini
