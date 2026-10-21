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

/-- Every cell id is below the next one to be allocated. -/
def _root_.Lanius.Semantics.State.Fresh (st : State) : Prop := ∀ c ∈ st.cells, c.id < st.nextCell

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
  exact fresh e mem

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
    have := fresh cell mem
    simp; cell_omega
  simp [this, List.find?]

theorem bindLocal_fresh {st : State} (fresh : st.Fresh) (id : Nat) (v : Value) :
    (st.bindLocal id v).Fresh := by
  intro cell mem
  simp only [State.bindLocal, State.bindCell, List.mem_append, List.mem_singleton] at mem ⊢
  rcases mem with old | rfl
  · exact Nat.lt_succ_of_lt (fresh cell old)
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
  intro cell mem
  obtain ⟨old, oldMem, eq⟩ := mem_replaceCell mem
  rw [← eq]
  exact fresh old oldMem

/-! ## Frames -/

def upd (frame : Nat → Nat) (slot cell : Nat) : Nat → Nat :=
  fun other => if other = slot then cell else frame other

/-- The scope's slots are below `next`, its cells are at or above `base`, and
no two bindings share a cell. -/
structure Layout (scope : List Binding) (frame : Nat → Nat) (base next : Nat) : Prop where
  slots : ∀ b ∈ scope, b.slot < next
  above : ∀ b ∈ scope, base ≤ frame b.slot
  inj : ∀ a ∈ scope, ∀ b ∈ scope, frame a.slot = frame b.slot → a = b

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
  simp only [upd]
  rw [if_neg (by omega)]

theorem Layout.push {scope frame base next} (fr : Layout scope frame base next) {cell : Nat}
    (below : ∀ b ∈ scope, frame b.slot < cell) (le : base ≤ cell) (id : Nat) (ty : SrcType) :
    Layout (⟨id, next, ty⟩ :: scope) (upd frame next cell) base (next + 1) := by
  have same := upd_scope fr cell
  have self : upd frame next cell next = cell := by simp [upd]
  refine ⟨?_, ?_, ?_⟩
  · intro b mem
    simp only [List.mem_cons] at mem
    rcases mem with rfl | mem
    · exact Nat.lt_succ_self _
    · exact Nat.lt_succ_of_lt (fr.slots b mem)
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

theorem Layout.mono {scope frame base next} (fr : Layout scope frame base next) {next' : Nat}
    (le : next ≤ next') : Layout scope frame base next' :=
  ⟨fun b mem => Nat.lt_of_lt_of_le (fr.slots b mem) le, fr.above, fr.inj⟩

theorem Corr.env_congr {scope frame st env env'} (corr : Corr scope frame st env)
    (agree : ∀ b ∈ scope, env' b.slot = env b.slot) : Corr scope frame st env' :=
  ⟨corr.locals, fun b mem => by rw [agree b mem]; exact corr.values b mem⟩

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
    (agree : ∀ b ∈ scope, env' b.slot = env b.slot) {id : Nat} {ty : SrcType} {v : Value}
    (holds : ty.Holds v (env' next)) :
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
      refine ⟨w, ?_, by rw [agree b mem]; exact holdsb⟩
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

theorem Exec.mono {prog : Program} {d : Nat} {env : Env} {s : Stmt} {out : Outcome}
    (exec : Exec prog d env s out) {d' : Nat} (le : d ≤ d') : Exec prog d' env s out := by
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
  | call found arity inner body _ => exact .call found arity (Nat.lt_of_lt_of_le inner le) body
  | ret => exact .ret

/-! ## Programs -/

theorem SrcType.same_eq {a b : SrcType} (same : a.same b = true) : a = b := by
  cases a <;> cases b <;> simp_all [SrcType.same, SrcType.isI32, SrcType.isBool]

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
    g.params = f.params.length ∧
      f.body.lower sg f.ret (paramScope f.params 0 []) f.params.length = some g.body := by
  simp only [lowerFunc] at ok
  split at ok
  · simp at ok
  rename_i body bodyOk
  simp only [Option.some.injEq] at ok
  subst ok
  exact ⟨rfl, bodyOk⟩

theorem paramTypes_length (params : List SrcParam) : (paramTypes params).length = params.length := by
  induction params with
  | nil => rfl
  | cons head rest ih => simp [paramTypes, ih]

/-! ## Arguments -/

/-- Each argument value is represented by its bits at its parameter's type. -/
inductive ArgsHold : List SrcType → List Value → List (BitVec 32) → Prop where
  | nil : ArgsHold [] [] []
  | cons {ty : SrcType} {tys : List SrcType} {v : Value} {vs : List Value} {b : BitVec 32}
      {bs : List (BitVec 32)} :
      ty.Holds v b → ArgsHold tys vs bs → ArgsHold (ty :: tys) (v :: vs) (b :: bs)

theorem ArgsHold.length {tys vs bs} (holds : ArgsHold tys vs bs) :
    vs.length = tys.length ∧ bs.length = tys.length := by
  induction holds with
  | nil => exact ⟨rfl, rfl⟩
  | cons _ _ ih => exact ⟨by simp [ih.1], by simp [ih.2]⟩

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

theorem lowerArgs_sound {scope frame st env} {prog : Core.Program} (corr : Corr scope frame st env)
    (target : prog.target = .x86_64) :
    ∀ {args : List SrcExpr} {types : List SrcType} {es : List Expr} {fuel : Nat} {vs : List Value}
      {st' : State}, lowerArgs scope args types = some es →
      evalExprs fuel prog st (args.map SrcExpr.toCore) = .done vs st' →
      st' = st ∧ ArgsHold types vs (Expr.evalAll env es) ∧ es.length = types.length := by
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
        exact ⟨rfl, .nil, rfl⟩
  | cons arg rest ih =>
    intro types es fuel vs st' ok run
    cases fuel with
    | zero => simp [evalExprs] at run
    | succ fuel =>
      cases types with
      | nil => simp [lowerArgs] at ok
      | cons ty more =>
        simp only [lowerArgs, lowerCons] at ok
        split at ok
        · simp at ok
        rename_i x argOk
        split at ok
        · simp at ok
        rename_i xs restOk
        simp only [Option.some.injEq] at ok
        subst ok
        simp only [List.map_cons, evalExprs] at run
        split at run
        · rename_i v mid argRun
          obtain ⟨rfl, holds⟩ := lowerAs_sound corr target argOk argRun
          split at run
          · rename_i rvs fin restRun
            simp only [Semantics.Outcome.done.injEq] at run
            obtain ⟨rfl, rfl⟩ := run
            obtain ⟨rfl, restHolds, len⟩ := ih restOk restRun
            exact ⟨rfl, .cons holds restHolds, by simp [len]⟩
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

/-- Binding the parameters gives the callee's frame: slot `i` is cell `base + i`. -/
theorem entry_corr (env : Env) (base : Nat) :
    ∀ (params : List SrcParam) {values : List Value} {bits : List (BitVec 32)} {k : Nat}
      {scope : List Binding} {st : State},
      ArgsHold (paramTypes params) values bits →
      (∀ i (h : i < bits.length), env (k + i) = bits[i]) →
      st.nextCell = base + k → st.Fresh →
      Corr scope (fun i => base + i) st env → Layout scope (fun i => base + i) base k →
      Corr (paramScope params k scope) (fun i => base + i)
          (st.bindLocals (paramBindings params values)) env ∧
        Layout (paramScope params k scope) (fun i => base + i) base (k + params.length) ∧
        (st.bindLocals (paramBindings params values)).Fresh ∧
        Keeps base st (st.bindLocals (paramBindings params values)) := by
  intro params
  induction params with
  | nil =>
    intro values bits k scope st holds _ _ fresh corr fr
    cases holds
    simp only [paramScope, paramBindings, List.map_nil, List.zip_nil_left, State.bindLocals,
      List.foldl_nil, List.length_nil, Nat.add_zero]
    exact ⟨corr, fr, fresh, Keeps.refl _ _⟩
  | cons p ps ih =>
    intro values bits k scope st holds envAt nextEq fresh corr fr
    cases holds with
    | cons holdsHead holdsRest =>
    rename_i v vs b bs
    have bindEq : st.bindLocals (paramBindings (p :: ps) (v :: vs)) =
        (st.bindLocal p.id v).bindLocals (paramBindings ps vs) := by
      simp [paramBindings, State.bindLocals]
    rw [bindEq]
    simp only [paramScope]
    have hu : upd (fun i => base + i) k st.nextCell = fun i => base + i := by
      funext i
      simp only [upd]
      split <;> cell_omega
    have atK : env k = b := by
      have := envAt 0 (by simp)
      rw [Nat.add_zero] at this
      exact this
    have pushed := corr.push fr fresh (env' := env) (fun _ _ => rfl) (id := p.id) (ty := p.ty)
      (v := v) (by rw [atK]; exact holdsHead)
    rw [hu] at pushed
    have frPushed := fr.push (cell := st.nextCell)
      (fun b mem => by have := fr.slots b mem; cell_omega) (by cell_omega) p.id p.ty
    rw [hu] at frPushed
    obtain ⟨corr', fr', fresh', keeps'⟩ := ih holdsRest
      (fun i h => by
        have := envAt (i + 1) (by simp; cell_omega)
        rw [show k + 1 + i = k + (i + 1) by cell_omega, this]
        simp)
      (by simp [State.bindLocal, State.bindCell, nextEq]; cell_omega)
      (bindLocal_fresh fresh p.id v) pushed frPushed
    refine ⟨corr', ?_, fresh', (bindLocal_keeps (by cell_omega) p.id v).trans keeps'⟩
    simpa [Nat.add_assoc, Nat.add_comm 1] using fr'

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
inductive Matches (ret : SrcType) (scope : List Binding) (frame : Nat → Nat) (st : State) :
    Completion → Outcome → Prop where
  | next {env : Env} : Corr scope frame st env → Matches ret scope frame st .next (.normal env)
  | returned {v : Value} {b : BitVec 32} :
      ret.Holds v b → Matches ret scope frame st (.returned (some v)) (.returned b)

/-- Core went from `st` to `st'` with completion `c`; the mini statement has a
derivation from `env` with a matching outcome. -/
abbrev Simulates (mp : Program) (ret : SrcType) (scope : List Binding) (frame : Nat → Nat)
    (base : Nat) (st : State) (env : Env) (stmt : Stmt) (c : Completion) (st' : State) : Prop :=
  st'.Fresh ∧ Keeps base st st' ∧ ∃ d out, Exec mp d env stmt out ∧ Matches ret scope frame st' c out

/-- Every statement lowered for `sp` that Core runs to completion with `fuel`
has a mini derivation with a matching outcome. -/
def StmtSound (sp : SrcProgram) (mp : Program) (fuel : Nat) : Prop :=
  ∀ {s : SrcStmt} {ret : SrcType} {scope : List Binding} {next : Nat} {stmt : Stmt}
    {frame : Nat → Nat} {base : Nat} {st : State} {env : Env} {c : Completion} {st' : State},
    s.lower (sigs sp.funcs) ret scope next = some stmt →
    Corr scope frame st env → Layout scope frame base next → st.Fresh → base ≤ st.nextCell →
    execStmt fuel sp.toCore st s.toCore = .done c st' →
    Simulates mp ret scope frame base st env stmt c st'

theorem SrcProgram.target_toCore (sp : SrcProgram) : sp.toCore.target = .x86_64 := rfl

/-- A function body Core runs to a return is a mini `Returns`. -/
theorem body_sound {sp : SrcProgram} {mp : Program}
    (lowered : lowerFuncs (sigs sp.funcs) sp.funcs = some mp.funcs) {fuel : Nat}
    (ih : StmtSound sp mp fuel) {callee : Nat} {f : SrcFunc} (found : sp.funcs[callee]? = some f)
    {st : State} (fresh : st.Fresh) {values : List Value} {bits : List (BitVec 32)}
    (holds : ArgsHold (paramTypes f.params) values bits) {v : Value} {completed : State}
    (run : execStmt fuel sp.toCore (({ st with locals := [] } : State).bindLocals
      (paramBindings f.params values)) f.body.toCore = .done (.returned (some v)) completed) :
    completed.Fresh ∧ Keeps st.nextCell st completed ∧
      ∃ d b, mp.Returns d callee bits b ∧ f.ret.Holds v b := by
  obtain ⟨g, gFound, gOk⟩ := lowerFuncs_get lowered found
  obtain ⟨gParams, bodyOk⟩ := lowerFunc_some gOk
  have bitsLen : bits.length = f.params.length := by
    rw [holds.length.2, paramTypes_length]
  obtain ⟨corr, fr, fresh0, keeps0⟩ := entry_corr (Func.entry bits) st.nextCell f.params
    (k := 0) (scope := []) (st := { st with locals := [] }) holds
    (fun i h => by simp [Func.entry, h]) rfl fresh ⟨rfl, fun _ mem => by simp at mem⟩
    ⟨fun _ mem => by simp at mem, fun _ mem => by simp at mem, fun _ mem => by simp at mem⟩
  rw [Nat.zero_add] at fr
  obtain ⟨freshDone, keepsDone, d, out, exec, agree⟩ :=
    ih bodyOk corr fr fresh0 keeps0.next run
  cases agree with
  | returned holdsRet =>
    exact ⟨freshDone, ⟨fun c below => (keepsDone.cells c below).trans (keeps0.cells c below),
      Nat.le_trans keeps0.next keepsDone.next⟩, d, _, ⟨g, gFound, by rw [gParams, bitsLen], exec⟩, holdsRet⟩

/-- A lowered call that Core completes: the caller's locals and cells are as
they were, and the mini call stores a value representing the result. -/
theorem call_sound {sp : SrcProgram} {mp : Program}
    (lowered : lowerFuncs (sigs sp.funcs) sp.funcs = some mp.funcs) {fuel : Nat}
    (ih : StmtSound sp mp fuel) {scope frame st env} (corr : Corr scope frame st env)
    (fresh : st.Fresh) {callee : Nat} {args : List SrcExpr} {ty : SrcType} {es : List Expr}
    (ok : lowerCall (sigs sp.funcs) scope callee args ty = some es) {v : Value} {st' : State}
    (run : evalExpr (fuel + 1) sp.toCore st (.call callee (args.map SrcExpr.toCore)) = .done v st') :
    st'.Fresh ∧ Keeps st.nextCell st st' ∧ st'.locals = st.locals ∧
      ∃ d b, ty.Holds v b ∧ ∀ target, Exec mp d env (.call target callee es) (.normal (env.set target b)) := by
  obtain ⟨f, values, afterArgs, completed, argsRun, found, _, bodyRun, rfl⟩ := call_inv run
  simp only [lowerCall, sigs_get, found, Option.map_some, lowerCallSig] at ok
  split at ok
  · rename_i same
    have tyEq := SrcType.same_eq same
    subst tyEq
    obtain ⟨rfl, holds, esLen⟩ := lowerArgs_sound corr (SrcProgram.target_toCore sp) ok argsRun
    obtain ⟨freshDone, keeps, d, b, ⟨g, gFound, arity, exec⟩, holdsRet⟩ :=
      body_sound lowered ih found fresh holds bodyRun
    refine ⟨restore_fresh freshDone, keeps.trans (restore_keeps _ _ _), rfl, d + 1, b, holdsRet,
      fun target => .call gFound ?_ (Nat.lt_succ_self d) exec⟩
    rw [← arity, evalAll_length]
  · simp at ok

/-! ## Assignment and `let` -/

theorem SrcType.Holds.scalar {ty : SrcType} {v : Value} {x : BitVec 32} (holds : ty.Holds v x) :
    Semantics.valueMayContainI32ArrayView v = false := by
  cases ty with
  | i32 => simp only [SrcType.Holds] at holds; subst holds; rfl
  | bool => obtain ⟨_, rfl, _⟩ := holds; rfl

/-- Core's `id = e` on a local of the scope: it evaluates `e`, then replaces
the local's cell. -/
theorem assign_step {P : Core.Program} {scope frame st env} (corr : Corr scope frame st env)
    {id : Nat} {b : Binding} (found : lookup scope id = some b) {e : Core.Expr} {k : Nat}
    {u : Value} {st' : State}
    (run : evalExpr (k + 1) P st (.assign .set (.local id) e) = .done u st')
    (after : ∀ {rv st2}, evalExpr k P st e = .done rv st2 →
      (st2.cellEntry? (frame b.slot)).isSome ∧ Semantics.valueMayContainI32ArrayView rv = false) :
    ∃ rv st2, evalExpr k P st e = .done rv st2 ∧
      st' = { st2 with cells := Semantics.replaceCell st2.cells (frame b.slot) rv } := by
  cases k with
  | zero => simp [evalExpr, Semantics.evalPlace] at run
  | succ j =>
    obtain ⟨v0, entry, holds0⟩ := corr.values b (lookup_mem found).1
    have place : Semantics.evalPlace (j + 1) P st .address (.local id) =
        .done { root := frame b.slot, projections := [], value := some v0 } st := by
      simp [Semantics.evalPlace, corr.cellId, found, entry]
    simp only [evalExpr, place] at run
    split at run
    · rename_i rv st2 valueRun
      obtain ⟨present, safe⟩ := after valueRun
      obtain ⟨e2, entry2⟩ := Option.isSome_iff_exists.mp present
      simp only [Semantics.evalAssignValue, Semantics.assignOpBinary?,
        Semantics.writeResolvedPlaceNative, Semantics.writeResolvedPlace, assignCell_some entry2,
        Semantics.ResolvedPlace.viewFreeRootWrite, safe, holds0.scalar, Option.isNone_none,
        List.isEmpty_nil, Option.any_some, Bool.not_false, Bool.and_self,
        ↓reduceIte, Semantics.Outcome.done.injEq] at run
      exact ⟨rv, st2, valueRun, run.2.symm⟩
    all_goals simp at run

theorem Corr.assign {scope frame st env base next} (corr : Corr scope frame st env)
    (fr : Layout scope frame base next) {id : Nat} {b : Binding} (found : lookup scope id = some b)
    {rv : Value} {x : BitVec 32} (holds : b.ty.Holds rv x) :
    Corr scope frame { st with cells := Semantics.replaceCell st.cells (frame b.slot) rv }
      (env.set b.slot x) := by
  have bmem := (lookup_mem found).1
  refine ⟨corr.locals, fun a mem => ?_⟩
  rw [assigned_entry]
  by_cases same : frame a.slot = frame b.slot
  · have := fr.inj a mem b bmem same
    subst this
    obtain ⟨v0, entry, _⟩ := corr.values a mem
    rw [if_pos rfl, entry]
    exact ⟨rv, rfl, by simpa [Env.set] using holds⟩
  · rw [if_neg same]
    obtain ⟨v1, entry, holds1⟩ := corr.values a mem
    have : a.slot ≠ b.slot := fun eq => same (by rw [eq])
    exact ⟨v1, entry, by simpa [Env.set, this] using holds1⟩

theorem assigned_keeps {base cell : Nat} (above : base ≤ cell) (st : State) (rv : Value) :
    Keeps base st { st with cells := Semantics.replaceCell st.cells cell rv } :=
  ⟨fun c below => by rw [assigned_entry, if_neg (by cell_omega)], Nat.le_refl _⟩

/-- The body of a `let`, from the state after its initializer. -/
theorem let_tail {sp : SrcProgram} {mp : Program} {fuel : Nat} (ih : StmtSound sp mp fuel)
    {body : SrcStmt} {ret : SrcType} {scope : List Binding} {next : Nat} {bstmt : Stmt}
    {id : Nat} {ty : SrcType}
    (bodyOk : body.lower (sigs sp.funcs) ret (⟨id, next, ty⟩ :: scope) (next + 1) = some bstmt)
    {frame base st env} (corr : Corr scope frame st env) (fr : Layout scope frame base next)
    (fresh : st.Fresh) (le : base ≤ st.nextCell) {v : Value} {x : BitVec 32} (holds : ty.Holds v x)
    {c : Completion} {st' : State}
    (run : Semantics.restoreOutcomeLocals st
      (execStmt fuel sp.toCore (st.bindLocal id v) body.toCore) = .done c st') :
    st'.Fresh ∧ Keeps base st st' ∧
      ∃ d out, Exec mp d (env.set next x) bstmt out ∧ Matches ret scope frame st' c out := by
  cases bodyRun : execStmt fuel sp.toCore (st.bindLocal id v) body.toCore with
  | done c' st'' =>
    simp only [bodyRun, Semantics.restoreOutcomeLocals, Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    have agree : ∀ b ∈ scope, (env.set next x) b.slot = env b.slot := by
      intro b mem
      have := fr.slots b mem
      simp only [Env.set]
      rw [if_neg (by omega)]
    have pushed := corr.push fr fresh agree (id := id) (ty := ty) (v := v)
      (by simpa [Env.set] using holds)
    have frPushed := fr.push (corr.below fresh) le id ty
    obtain ⟨fresh'', keeps'', d, out, exec, matched⟩ :=
      ih bodyOk pushed frPushed (bindLocal_fresh fresh id v)
        (Nat.le_trans le (Nat.le_succ _)) bodyRun
    refine ⟨restore_fresh fresh'', (bindLocal_keeps le id v).trans
      (keeps''.trans (restore_keeps _ _ _)), d, out, exec, ?_⟩
    cases matched with
    | next corr'' => exact .next (corr''.pop fr corr.locals rfl)
    | returned holdsRet => exact .returned holdsRet
  | trapped => simp [bodyRun, Semantics.restoreOutcomeLocals] at run
  | exited => simp [bodyRun, Semantics.restoreOutcomeLocals] at run
  | outOfFuel => simp [bodyRun, Semantics.restoreOutcomeLocals] at run

/-! ## Statements -/

section Statements

variable {sp : SrcProgram} {mp : Program} {fuel : Nat} {ret : SrcType} {scope : List Binding}
  {next : Nat} {stmt : Stmt} {frame : Nat → Nat} {base : Nat} {st : State} {env : Env}
  {c : Completion} {st' : State}

theorem stmt_nop (ok : SrcStmt.nop.lower (sigs sp.funcs) ret scope next = some stmt)
    (corr : Corr scope frame st env) (fresh : st.Fresh)
    (run : execStmt (fuel + 1) sp.toCore st SrcStmt.nop.toCore = .done c st') :
    Simulates mp ret scope frame base st env stmt c st' := by
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
    Simulates mp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerLet] at ok
  split at ok
  · simp at ok
  rename_i x valueOk
  split at ok
  · simp at ok
  rename_i bstmt bodyOk
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i v st1 valueRun
    obtain ⟨rfl, holds⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) valueOk valueRun
    obtain ⟨fresh', keeps, d, out, exec, matched⟩ := let_tail ih bodyOk corr fr fresh le holds run
    exact ⟨fresh', keeps, d, out, .seq .assign exec, matched⟩
  all_goals simp at run

theorem stmt_letCall (lowered : lowerFuncs (sigs sp.funcs) sp.funcs = some mp.funcs)
    (ih : ∀ m ≤ fuel, StmtSound sp mp m) {id : Nat} {ty : SrcType} {callee : Nat}
    {args : List SrcExpr} {body : SrcStmt}
    (ok : (SrcStmt.letCall id ty callee args body).lower (sigs sp.funcs) ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.letCall id ty callee args body).toCore =
      .done c st') :
    Simulates mp ret scope frame base st env stmt c st' := by
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
      obtain ⟨fresh1, keeps1, locals1, d1, b, holds, callExec⟩ :=
        call_sound lowered (ih k (Nat.le_succ _)) corr fresh argsOk callRun
      have corr1 := corr.keeps fresh keeps1 locals1
      obtain ⟨fresh', keeps', d2, out, exec, matched⟩ :=
        let_tail (ih (k + 1) (Nat.le_refl _)) bodyOk corr1 fr fresh1
          (Nat.le_trans le keeps1.next) holds run
      exact ⟨fresh', (keeps1.lower le).trans keeps', max d1 d2, out,
        .seq ((callExec next).mono (Nat.le_max_left _ _)) (exec.mono (Nat.le_max_right _ _)), matched⟩
  all_goals simp at run

theorem stmt_set {id : Nat} {value : SrcExpr}
    (ok : (SrcStmt.set id value).lower (sigs sp.funcs) ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.set id value).toCore = .done c st') :
    Simulates mp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerSet] at ok
  split at ok
  · simp at ok
  rename_i b found
  simp only [lowerSetValue] at ok
  split at ok
  · simp at ok
  rename_i x valueOk
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
        obtain ⟨rfl, holds⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) valueOk valueRun
        obtain ⟨v0, entry, _⟩ := corr.values b bmem
        exact ⟨by simp [entry], holds.scalar⟩
      obtain ⟨rfl, holds⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) valueOk valueRun
      exact ⟨assigned_fresh fresh _ _, assigned_keeps (fr.above b bmem) _ _, 0, _, .assign,
        .next (corr.assign fr found holds)⟩
  all_goals simp at run

theorem stmt_setCall (lowered : lowerFuncs (sigs sp.funcs) sp.funcs = some mp.funcs)
    (ih : ∀ m ≤ fuel, StmtSound sp mp m) {id callee : Nat} {args : List SrcExpr}
    (ok : (SrcStmt.setCall id callee args).lower (sigs sp.funcs) ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.setCall id callee args).toCore = .done c st') :
    Simulates mp ret scope frame base st env stmt c st' := by
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
            ∃ d b', b.ty.Holds rv b' ∧
              ∀ target, Exec mp d env (.call target callee es) (.normal (env.set target b')) := by
        intro rv st2 callRun
        cases k with
        | zero => simp [evalExpr] at callRun
        | succ j => exact call_sound lowered (ih j (by omega)) corr fresh argsOk callRun
      obtain ⟨rv, st2, callRun, rfl⟩ := assign_step corr found assignRun fun callRun => by
        obtain ⟨_, keeps, _, _, _, holds, _⟩ := callFacts callRun
        obtain ⟨v0, entry, _⟩ := corr.values b bmem
        rw [keeps.cells _ (corr.below fresh b bmem)]
        exact ⟨by simp [entry], holds.scalar⟩
      obtain ⟨fresh2, keeps2, locals2, d, b', holds, callExec⟩ := callFacts callRun
      have corr2 := corr.keeps fresh keeps2 locals2
      exact ⟨assigned_fresh fresh2 _ _, (keeps2.lower le).trans (assigned_keeps (fr.above b bmem) _ _),
        d, _, callExec b.slot, .next (corr2.assign fr found holds)⟩
  all_goals simp at run

theorem stmt_then (ih : StmtSound sp mp fuel) {first second : SrcStmt}
    (ok : (SrcStmt.then first second).lower (sigs sp.funcs) ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.then first second).toCore = .done c st') :
    Simulates mp ret scope frame base st env stmt c st' := by
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
    obtain ⟨fresh1, keeps1, d1, out1, exec1, matched1⟩ := ih firstOk corr fr fresh le firstRun
    cases matched1 with
    | next corr1 =>
      obtain ⟨fresh2, keeps2, d2, out2, exec2, matched2⟩ :=
        ih secondOk corr1 fr fresh1 (Nat.le_trans le keeps1.next) run
      exact ⟨fresh2, keeps1.trans keeps2, max d1 d2, out2,
        .seq (exec1.mono (Nat.le_max_left _ _)) (exec2.mono (Nat.le_max_right _ _)), matched2⟩
  · rename_i completion mid notNext firstRun
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    obtain ⟨fresh1, keeps1, d1, out1, exec1, matched1⟩ := ih firstOk corr fr fresh le firstRun
    cases matched1 with
    | next => exact absurd rfl notNext
    | returned holds => exact ⟨fresh1, keeps1, d1, _, .seqReturned exec1, .returned holds⟩
  all_goals simp at run

theorem stmt_if (ih : StmtSound sp mp fuel) {condition : SrcExpr} {thenBranch elseBranch : SrcStmt}
    (ok : (SrcStmt.if condition thenBranch elseBranch).lower (sigs sp.funcs) ret scope next = some stmt)
    (corr : Corr scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.if condition thenBranch elseBranch).toCore =
      .done c st') :
    Simulates mp ret scope frame base st env stmt c st' := by
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
    obtain ⟨fresh', keeps, d, out, exec, matched⟩ := ih thenOk corr fr fresh le run
    exact ⟨fresh', keeps, d, out, .ifTrue (by rw [bits]; decide) exec, matched⟩
  · rename_i mid condRun
    obtain ⟨rfl, y, hy, bits⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) condOk condRun
    cases hy
    obtain ⟨fresh', keeps, d, out, exec, matched⟩ := ih elseOk corr fr fresh le run
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
    Simulates mp ret scope frame base st env stmt c st' := by
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
      obtain ⟨fresh1, keeps1, d1, out1, exec1, matched1⟩ := ih bodyOk corr fr fresh le bodyRun
      cases matched1 with
      | next corr1 =>
        obtain ⟨fresh2, keeps2, d2, out2, exec2, matched2⟩ :=
          ih whileOk corr1 fr fresh1 (Nat.le_trans le keeps1.next) run
        exact ⟨fresh2, keeps1.trans keeps2, max d1 d2, out2,
          .loopNext condTrue (exec1.mono (Nat.le_max_left _ _)) (exec2.mono (Nat.le_max_right _ _)),
          matched2⟩
    · rename_i completed bodyRun
      obtain ⟨_, _, _, _, _, matched1⟩ := ih bodyOk corr fr fresh le bodyRun
      cases matched1
    · rename_i completed bodyRun
      obtain ⟨_, _, _, _, _, matched1⟩ := ih bodyOk corr fr fresh le bodyRun
      cases matched1
    · rename_i value completed bodyRun
      simp only [Semantics.Outcome.done.injEq] at run
      obtain ⟨rfl, rfl⟩ := run
      obtain ⟨fresh1, keeps1, d1, out1, exec1, matched1⟩ := ih bodyOk corr fr fresh le bodyRun
      cases matched1 with
      | returned holds => exact ⟨fresh1, keeps1, d1, _, .loopReturned condTrue exec1, .returned holds⟩
    all_goals simp at run
  · rename_i w mid notFalse notTrue condRun
    obtain ⟨rfl, y, rfl, _⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) condOk condRun
    cases y <;> simp_all
  all_goals simp at run

theorem stmt_return {value : SrcExpr}
    (ok : (SrcStmt.return value).lower (sigs sp.funcs) ret scope next = some stmt)
    (corr : Corr scope frame st env) (fresh : st.Fresh)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.return value).toCore = .done c st') :
    Simulates mp ret scope frame base st env stmt c st' := by
  simp only [SrcStmt.lower, lowerReturn] at ok
  split at ok
  · simp at ok
  rename_i x valueOk
  simp only [Option.some.injEq] at ok
  subst ok
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i v mid valueRun
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    obtain ⟨rfl, holds⟩ := lowerAs_sound corr (SrcProgram.target_toCore sp) valueOk valueRun
    exact ⟨fresh, Keeps.refl _ _, 0, _, .ret, .returned holds⟩
  all_goals simp at run

end Statements

/-- The simulation, by induction on Core's fuel. -/
theorem stmt_sound {sp : SrcProgram} {mp : Program}
    (lowered : lowerFuncs (sigs sp.funcs) sp.funcs = some mp.funcs) : ∀ fuel, StmtSound sp mp fuel := by
  intro fuel
  induction fuel using Nat.strongRecOn with
  | _ fuel ih =>
    intro s ret scope next stmt frame base st env c st' ok corr fr fresh le run
    cases fuel with
    | zero => simp [execStmt] at run
    | succ fuel =>
      have below : ∀ m ≤ fuel, StmtSound sp mp m := fun m h => ih m (Nat.lt_succ_of_le h)
      have here : StmtSound sp mp fuel := below fuel (Nat.le_refl _)
      cases s with
      | nop => exact stmt_nop ok corr fresh run
      | «let» => exact stmt_let here ok corr fr fresh le run
      | letCall => exact stmt_letCall lowered below ok corr fr fresh le run
      | set => exact stmt_set ok corr fr fresh run
      | setCall => exact stmt_setCall lowered below ok corr fr fresh le run
      | «then» => exact stmt_then here ok corr fr fresh le run
      | «if» => exact stmt_if here ok corr fr fresh le run
      | «while» => exact stmt_while here ok corr fr fresh le run
      | «return» => exact stmt_return ok corr fresh run

end Lanius.Mini
