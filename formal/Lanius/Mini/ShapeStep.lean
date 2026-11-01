import Lanius.Mini.ShapeEval

/-! # No `typeMismatch` without raw memory (review finding 2, step 4b)

`Good P k`: each of Core's five evaluators, run with fuel `k` on a term of
the fragment typed by Core's rules, from a state typed by a store typing,
keeps its promise (`EOk`, `EsOk`, `PlOk`, `SOk`). `good`: for a `ProgOk`
program this holds for every fuel, by induction; the step from `k` to
`k + 1` is one lemma per syntactic form. `evalExpr_ne_typeMismatch` is the
consequence finding 2 asks for: such a run never traps with `typeMismatch`. -/

namespace Lanius.Mini.NoMismatch

open Lanius.Core (Value Ty Expr Place Stmt Pattern)
open Lanius.Semantics (State Cell Outcome Completion ResolvedPlace evalExpr evalExprs evalMatchArms evalPlace
  execStmt)
open Lanius.Typing

structure Good (P : Core.Program) (k : Nat) : Prop where
  expr : ∀ {S : CellTypes} {Γ : Context} {st : State} {e : Expr} {t : Ty}, ExprFrag e = true →
    ExprHasType P Γ e t → CellsOk P S st → LocalsOk S Γ st → EOk P S st t (evalExpr k P st e)
  exprs : ∀ {S : CellTypes} {Γ : Context} {st : State} {es : List Expr} {ts : List Ty}, ExprsFrag es = true →
    ExprsHaveTypes P Γ es ts → CellsOk P S st → LocalsOk S Γ st → EsOk P S st ts (evalExprs k P st es)
  arms : ∀ {S : CellTypes} {Γ : Context} {st : State} {v : Value} {arms : List (Pattern × Expr)} {ts tr : Ty},
    ArmsFrag arms = true → MatchArmsHaveType P Γ arms ts tr → Shape P v ts → CellsOk P S st →
      LocalsOk S Γ st → EOk P S st tr (evalMatchArms k P st v arms)
  place : ∀ {S : CellTypes} {Γ : Context} {st : State} {p : Place} {t : Ty} (acc : Lanius.Semantics.PlaceAccess),
    PlaceFrag p = true → PlaceHasType P Γ p t → CellsOk P S st → LocalsOk S Γ st →
      PlOk P S st t (evalPlace k P st acc p)
  stmt : ∀ {S : CellTypes} {Γ : Context} {st : State} {ret : Ty} {inLoop : Bool} {s : Stmt}, StmtFrag s = true →
    StmtHasType P ret Γ inLoop s → CellsOk P S st → LocalsOk S Γ st → SOk P S st ret inLoop (execStmt k P st s)

/-- Close an outcome the step passes on unchanged: an exit, no fuel, or a
trap `h` already says is not `typeMismatch`. -/
macro "pass " h:term : tactic => `(tactic| first | trivial | (show _ ≠ _; exact $h))

/-- A trap the step makes itself, never `typeMismatch`. -/
macro "own_trap" : tactic => `(tactic| (show _ ≠ _; first | decide | (intro h; cases h)))

theorem EOk.of {P : Core.Program} {S S' : CellTypes} {st st' : State} {t : Ty} {v : Value} (le : S.Le S')
    (cells : CellsOk P S' st') (same : st'.locals = st.locals) (sh : Shape P v t) : EOk P S st t (.done v st') :=
  ⟨S', le, cells, same, sh⟩

theorem EsOk.of {P : Core.Program} {S S' : CellTypes} {st st' : State} {ts : List Ty} {vs : List Value}
    (le : S.Le S') (cells : CellsOk P S' st') (same : st'.locals = st.locals) (sh : Shapes P vs ts) :
    EsOk P S st ts (.done vs st') :=
  ⟨S', le, cells, same, sh⟩

theorem SOk.of {P : Core.Program} {S S' : CellTypes} {st st' : State} {ret : Ty} {inLoop : Bool} {c : Completion}
    (le : S.Le S') (cells : CellsOk P S' st') (same : st'.locals = st.locals) (comp : CompOk P ret inLoop c) :
    SOk P S st ret inLoop (.done c st') :=
  ⟨S', le, cells, same, comp⟩

theorem PlOk.of {P : Core.Program} {S : CellTypes} {st : State} {t T0 : Ty} {rp : ResolvedPlace}
    (raw : rp.raw = none) (root : S rp.root = some T0) (path : ProjTy P T0 rp.projections t)
    (value : ∀ v, rp.value = some v → Shape P v t) : PlOk P S st t (.done rp st) :=
  ⟨rfl, raw, ⟨T0, root, path⟩, value⟩

/-- The same cells, nextCell and views: another heap or world. -/
theorem CellsOk.same {P : Core.Program} {S : CellTypes} {st st' : State} (h : CellsOk P S st)
    (cells : st'.cells = st.cells) (next : st'.nextCell = st.nextCell) (views : st'.i32ArrayViews = st.i32ArrayViews) :
    CellsOk P S st' := by
  refine ⟨views.trans h.views, fun c t ty => ?_, fun cell mem => ?_⟩
  · simp only [State.cellEntry?, cells]; exact h.typed c t ty
  · rw [cells] at mem; rw [next]; exact h.below cell mem

theorem evalExpr_binary_general {k : Nat} {P : Core.Program} {st : State} {op : Core.BinaryOp} {l r : Expr}
    (h1 : op ≠ .logicalAnd) (h2 : op ≠ .logicalOr) :
    evalExpr (k + 1) P st (.binary op l r) =
      match evalExpr k P st l with
      | .done leftValue afterLeft =>
          match evalExpr k P afterLeft r with
          | .done rightValue afterRight =>
              match Lanius.Semantics.evalBinaryValue P.target op leftValue rightValue with
              | .ok result => .done result afterRight
              | .error reason => .trapped reason afterRight
          | .trapped reason next => .trapped reason next
          | .exited code exitedState => .exited code exitedState
          | .outOfFuel => .outOfFuel
      | .trapped reason next => .trapped reason next
      | .exited code exitedState => .exited code exitedState
      | .outOfFuel => .outOfFuel := by
  cases op <;> first | exact absurd rfl h1 | exact absurd rfl h2 | (simp only [evalExpr]; try rfl)

section Step

variable {P : Core.Program} {k : Nat} (ih : Good P k) {S : CellTypes} {Γ : Context} {st : State}

/-! ## Expressions -/

omit ih in
theorem step_local {id : Nat} {t : Ty} (found : Γ id = some t) (cells : CellsOk P S st) (locs : LocalsOk S Γ st) :
    EOk P S st t (evalExpr (k + 1) P st (.local id)) := by
  obtain ⟨c, hc, hS⟩ := locs _ _ found
  obtain ⟨cell, hcell, shaped⟩ := cells.typed _ _ hS
  obtain ⟨cid, value⟩ := cell
  cases value with
  | none => simp only [evalExpr, hc, hcell]; own_trap
  | some v => simp only [evalExpr, hc, hcell]; exact EOk.of (.refl S) cells rfl (shaped v rfl)

include ih in
theorem step_cast {ty s : Core.ScalarTy} {e : Expr} (fe : ExprFrag e = true)
    (operand : ExprHasType P Γ e (.scalar s)) (conversion : ScalarCast s ty) (cells : CellsOk P S st)
    (locs : LocalsOk S Γ st) : EOk P S st (.scalar ty) (evalExpr (k + 1) P st (.cast ty e)) := by
  simp only [evalExpr]
  have h := ih.expr fe operand cells locs
  cases hr : evalExpr k P st e with
  | done v next =>
    rw [hr] at h
    obtain ⟨S1, le1, cells1, same1, sh1⟩ := h
    have res := cast_ok (tgt := P.target) conversion sh1
    dsimp only
    cases hc : Lanius.Semantics.evalScalarCast P.target ty v with
    | ok r => rw [hc] at res; exact EOk.of le1 cells1 same1 res
    | error r => rw [hc] at res; pass res
  | _ => rw [hr] at h; pass h

include ih in
theorem step_unary {op : Core.UnaryOp} {e : Expr} {t t' : Ty} (fe : ExprFrag e = true)
    (operand : ExprHasType P Γ e t) (operation : UnaryOpHasType op t t') (cells : CellsOk P S st)
    (locs : LocalsOk S Γ st) : EOk P S st t' (evalExpr (k + 1) P st (.unary op e)) := by
  simp only [evalExpr]
  have h := ih.expr fe operand cells locs
  cases hr : evalExpr k P st e with
  | done v next =>
    rw [hr] at h
    obtain ⟨S1, le1, cells1, same1, sh1⟩ := h
    have res := unary_ok (tgt := P.target) operation sh1
    dsimp only
    cases hc : Lanius.Semantics.evalUnaryValue P.target op v with
    | ok r => rw [hc] at res; exact EOk.of le1 cells1 same1 res
    | error r => rw [hc] at res; pass res
  | _ => rw [hr] at h; pass h

include ih in
theorem step_binary {op : Core.BinaryOp} {l r : Expr} {lt rt t : Ty} (fl : ExprFrag l = true)
    (fr : ExprFrag r = true) (left : ExprHasType P Γ l lt) (right : ExprHasType P Γ r rt)
    (operation : BinaryOpHasType op lt rt t) (cells : CellsOk P S st) (locs : LocalsOk S Γ st) :
    EOk P S st t (evalExpr (k + 1) P st (.binary op l r)) := by
  have h := ih.expr fl left cells locs
  by_cases hand : op = .logicalAnd
  · subst hand
    cases operation
    simp only [evalExpr]
    cases hr : evalExpr k P st l with
    | done v next =>
      rw [hr] at h
      obtain ⟨S1, le1, cells1, same1, sh1⟩ := h
      obtain ⟨b, rfl⟩ := sh1.bool_inv
      cases b with
      | false => exact EOk.of le1 cells1 same1 (.boolean false)
      | true => exact (ih.expr fr right cells1 (locs.mono le1 same1)).weaken le1 same1
    | _ => rw [hr] at h; pass h
  by_cases hor : op = .logicalOr
  · subst hor
    cases operation
    simp only [evalExpr]
    cases hr : evalExpr k P st l with
    | done v next =>
      rw [hr] at h
      obtain ⟨S1, le1, cells1, same1, sh1⟩ := h
      obtain ⟨b, rfl⟩ := sh1.bool_inv
      cases b with
      | true => exact EOk.of le1 cells1 same1 (.boolean true)
      | false => exact (ih.expr fr right cells1 (locs.mono le1 same1)).weaken le1 same1
    | _ => rw [hr] at h; pass h
  rw [evalExpr_binary_general hand hor]
  cases hr : evalExpr k P st l with
  | done lv a =>
    rw [hr] at h
    obtain ⟨S1, le1, cells1, same1, sh1⟩ := h
    have h2 := ih.expr fr right cells1 (locs.mono le1 same1)
    dsimp only
    cases hr2 : evalExpr k P a r with
    | done rv b =>
      rw [hr2] at h2
      obtain ⟨S2, le2, cells2, same2, sh2⟩ := h2
      have res := binary_ok (tgt := P.target) operation sh1 sh2
      dsimp only
      cases hb : Lanius.Semantics.evalBinaryValue P.target op lv rv with
      | ok x => rw [hb] at res; exact EOk.of (le1.trans le2) cells2 (same2.trans same1) res
      | error e => rw [hb] at res; pass res
    | _ => rw [hr2] at h2; pass h2
  | _ => rw [hr] at h; pass h

include ih in
theorem step_array {ty : Ty} {es : List Expr} (fes : ExprsFrag es = true)
    (elements : ExprsHaveTypes P Γ es (List.replicate es.length ty)) (cells : CellsOk P S st)
    (locs : LocalsOk S Γ st) : EOk P S st (.array ty es.length) (evalExpr (k + 1) P st (.array ty es)) := by
  simp only [evalExpr]
  have h := ih.exprs fes elements cells locs
  cases hr : evalExprs k P st es with
  | done vs next =>
    rw [hr] at h
    obtain ⟨S1, le1, cells1, same1, sh⟩ := h
    obtain ⟨len, each⟩ := sh.replicate
    exact EOk.of le1 cells1 same1 (.array vs ty _ len each)
  | _ => rw [hr] at h; pass h

include ih in
theorem step_struct {id : Nat} {d : Core.StructDecl} {es : List Expr} (fes : ExprsFrag es = true)
    (found : P.structure? id = some d) (fields : ExprsHaveTypes P Γ es d.fields) (cells : CellsOk P S st)
    (locs : LocalsOk S Γ st) : EOk P S st (.structure id) (evalExpr (k + 1) P st (.structValue id es)) := by
  simp only [evalExpr]
  have h := ih.exprs fes fields cells locs
  cases hr : evalExprs k P st es with
  | done vs next =>
    rw [hr] at h
    obtain ⟨S1, le1, cells1, same1, sh⟩ := h
    exact EOk.of le1 cells1 same1 (Shape.mk_struct found sh)
  | _ => rw [hr] at h; pass h

include ih in
theorem step_enum {id variant : Nat} {d : Core.EnumDecl} {tys : List Ty} {es : List Expr}
    (fes : ExprsFrag es = true) (found : P.enumeration? id = some d) (variantFound : d.variants[variant]? = some tys)
    (payload : ExprsHaveTypes P Γ es tys) (cells : CellsOk P S st) (locs : LocalsOk S Γ st) :
    EOk P S st (.enumeration id) (evalExpr (k + 1) P st (.enumValue id variant es)) := by
  simp only [evalExpr]
  have h := ih.exprs fes payload cells locs
  cases hr : evalExprs k P st es with
  | done vs next =>
    rw [hr] at h
    obtain ⟨S1, le1, cells1, same1, sh⟩ := h
    exact EOk.of le1 cells1 same1 (Shape.mk_enum found variantFound sh)
  | _ => rw [hr] at h; pass h

include ih in
theorem step_field {b : Expr} {i id : Nat} {d : Core.StructDecl} {t : Ty} (fb : ExprFrag b = true)
    (base : ExprHasType P Γ b (.structure id)) (found : P.structure? id = some d) (fieldFound : d.fields[i]? = some t)
    (cells : CellsOk P S st) (locs : LocalsOk S Γ st) : EOk P S st t (evalExpr (k + 1) P st (.field b i)) := by
  simp only [evalExpr]
  have h := ih.expr fb base cells locs
  cases hr : evalExpr k P st b with
  | done v next =>
    rw [hr] at h
    obtain ⟨S1, le1, cells1, same1, sh⟩ := h
    obtain ⟨vs, rfl, fields⟩ := sh.struct_fields found
    obtain ⟨w, hw, shw⟩ := fields.get fieldFound
    simp only [hw]
    exact EOk.of le1 cells1 same1 shw
  | _ => rw [hr] at h; pass h

include ih in
theorem step_match {e : Expr} {arms : List (Pattern × Expr)} {ts t : Ty} (fe : ExprFrag e = true)
    (fa : ArmsFrag arms = true) (scrutinee : ExprHasType P Γ e ts) (typedArms : MatchArmsHaveType P Γ arms ts t)
    (cells : CellsOk P S st) (locs : LocalsOk S Γ st) : EOk P S st t (evalExpr (k + 1) P st (.matchValue e arms)) := by
  simp only [evalExpr]
  have h := ih.expr fe scrutinee cells locs
  cases hr : evalExpr k P st e with
  | done v next =>
    rw [hr] at h
    obtain ⟨S1, le1, cells1, same1, sh⟩ := h
    exact (ih.arms fa typedArms sh cells1 (locs.mono le1 same1)).weaken le1 same1
  | _ => rw [hr] at h; pass h

include ih in
theorem step_print {e : Expr} (fe : ExprFrag e = true) (argument : ExprHasType P Γ e (.scalar (.signed .i32)))
    (cells : CellsOk P S st) (locs : LocalsOk S Γ st) :
    EOk P S st .unit (evalExpr (k + 1) P st (.intrinsic .printI32 e)) := by
  simp only [evalExpr]
  have h := ih.expr fe argument cells locs
  cases hr : evalExpr k P st e with
  | done v next =>
    rw [hr] at h
    obtain ⟨S1, le1, cells1, same1, sh⟩ := h
    cases sh
    exact EOk.of le1 (cells1.same rfl rfl rfl) same1 .unit
  | _ => rw [hr] at h; pass h

include ih in
theorem step_assert {e : Expr} (fe : ExprFrag e = true) (argument : ExprHasType P Γ e (.scalar .bool))
    (cells : CellsOk P S st) (locs : LocalsOk S Γ st) :
    EOk P S st .unit (evalExpr (k + 1) P st (.intrinsic .assert e)) := by
  simp only [evalExpr]
  have h := ih.expr fe argument cells locs
  cases hr : evalExpr k P st e with
  | done v next =>
    rw [hr] at h
    obtain ⟨S1, le1, cells1, same1, sh⟩ := h
    obtain ⟨b, rfl⟩ := sh.bool_inv
    cases b with
    | true => exact EOk.of le1 cells1 same1 .unit
    | false => own_trap
  | _ => rw [hr] at h; pass h

include ih in
theorem step_assign {op : Core.AssignOp} {p : Place} {e : Expr} {t : Ty} (fp : PlaceFrag p = true)
    (fe : ExprFrag e = true) (target : PlaceHasType P Γ p t) (value : ExprHasType P Γ e t)
    (operation : AssignOpHasType op t) (cells : CellsOk P S st) (locs : LocalsOk S Γ st) :
    EOk P S st .unit (evalExpr (k + 1) P st (.assign op p e)) := by
  simp only [evalExpr]
  have hp : ∀ {acc o}, evalPlace k P st acc p = o → PlOk P S st t o := fun {acc _} he => by
    subst he; exact ih.place acc fp target cells locs
  split
  next rp ap heq =>
    obtain ⟨hst, raw, ⟨T0, root, path⟩, vsh⟩ := hp heq
    rw [hst]
    have h2 := ih.expr fe value cells locs
    cases hr : evalExpr k P st e with
    | done right av =>
      rw [hr] at h2
      obtain ⟨S1, le1, cells1, same1, sh⟩ := h2
      have res := assign_ok (tgt := P.target) operation vsh sh
      dsimp only
      cases hv : Lanius.Semantics.evalAssignValue P.target op rp.value right with
      | error r => rw [hv] at res; pass res
      | ok result =>
        rw [hv] at res
        dsimp only
        simp only [Lanius.Semantics.writeResolvedPlaceNative, raw]
        have w := write_ok cells1 (le1 _ _ root) path res
        cases hw : Lanius.Semantics.writeResolvedPlace av rp result with
        | error r => rw [hw] at w; pass w
        | ok assigned =>
          rw [hw] at w
          obtain ⟨cellsA, sameA⟩ := w
          simp only [syncTo_nil cellsA.views, ite_self]
          exact EOk.of le1 cellsA (sameA.trans same1) .unit
    | _ => rw [hr] at h2; pass h2
  all_goals (rename_i heq; pass (hp heq))

include ih in
/-- A call whose arguments evaluate as `EsOk` promises. -/
theorem step_call_of (prog : ProgOk P) {fid : Nat} {f : Core.Function} {es : List Expr}
    (found : P.function? fid = some f) (args : EsOk P S st (f.parameters.map Prod.snd) (evalExprs k P st es)) :
    EOk P S st f.returnType (evalExpr (k + 1) P st (.call fid es)) := by
  simp only [evalExpr]
  have h := args
  cases hr : evalExprs k P st es with
  | done vs after =>
    rw [hr] at h
    obtain ⟨S1, le1, cells1, same1, sh⟩ := h
    obtain ⟨bind, binds⟩ := bindParameters_binds sh
    have wt := prog.1.2 f (function?_mem found)
    dsimp only
    simp only [found, bind]
    rcases prog.2 f (function?_mem found) with ⟨body, hbody, fbody⟩ | ⟨hbody, s, hext, lowered⟩
    · simp only [hbody]
      simp only [FunctionWellTyped, hbody] at wt
      obtain ⟨-, typedBody, -⟩ := wt
      have cellsC : CellsOk P S1 { after with locals := [] } := cells1.same rfl rfl rfl
      have locsC : LocalsOk S1 Context.empty { after with locals := [] } := fun _ _ h => by cases h
      obtain ⟨S2, le2, cells2, locs2⟩ := bindLocals_ok binds cellsC locsC
      have hs := ih.stmt fbody typedBody cells2 locs2
      cases hx : execStmt k P (({ after with locals := [] }).bindLocals
          ((f.parameters.zip vs).map fun (pair : (Nat × Ty) × Value) => (pair.1.1, pair.2))) body with
      | done c completed =>
        rw [hx] at hs
        obtain ⟨S3, le3, cells3, -, comp⟩ := hs
        have le := le1.trans (le2.trans le3)
        cases c with
        | next =>
          dsimp only
          split
          · rename_i hu; rw [hu]; exact EOk.of le cells3.restore same1 .unit
          · own_trap
        | returned rv =>
          cases rv with
          | none =>
            dsimp only
            split
            · rename_i hu; rw [hu]; exact EOk.of le cells3.restore same1 .unit
            · own_trap
          | some v => exact EOk.of le cells3.restore same1 comp
        | breakLoop => exact absurd (show false = true from comp) (by decide)
        | continueLoop => exact absurd (show false = true from comp) (by decide)
      | _ => rw [hx] at hs; pass hs
    · simp only [hbody, hext]
      simp only [FunctionWellTyped, hbody, hext] at wt
      simp only [syncTo_nil cells1.views]
      have ho := host_ok (heap := after.heap) (world := after.world) lowered (wt.1 ▸ sh)
      have sf : ∀ (hp : Memory.Heap) (w : Lanius.World.State),
          Lanius.Semantics.syncI32ViewsFromHeap { after with heap := hp, world := w } =
            .ok { after with heap := hp, world := w } := fun _ _ => syncFrom_nil cells1.views
      cases hc : Lanius.World.call after.heap after.world s vs with
      | returned v hp w =>
        rw [hc] at ho
        simp only [Lanius.Semantics.worldCallOutcome, sf]
        exact EOk.of le1 (cells1.same rfl rfl rfl) same1 (by rw [wt.2]; exact ho)
      | exited c hp w => simp only [Lanius.Semantics.worldCallOutcome, sf]; trivial
      | unavailable _ hp w => simp only [Lanius.Semantics.worldCallOutcome]; own_trap
      | trapped r hp w => rw [hc] at ho; simp only [Lanius.Semantics.worldCallOutcome]; exact ho
      | typeMismatch hp w => rw [hc] at ho; exact ho.elim
  | _ => rw [hr] at h; pass h

include ih in
theorem step_call (prog : ProgOk P) {fid : Nat} {f : Core.Function} {es : List Expr} (fes : ExprsFrag es = true)
    (found : P.function? fid = some f) (arguments : ExprsHaveTypes P Γ es (f.parameters.map Prod.snd))
    (cells : CellsOk P S st) (locs : LocalsOk S Γ st) :
    EOk P S st f.returnType (evalExpr (k + 1) P st (.call fid es)) :=
  step_call_of ih prog found (ih.exprs fes arguments cells locs)

/-! ## Lists of expressions and match arms -/

omit ih in
theorem step_exprs_nil (cells : CellsOk P S st) : EsOk P S st [] (evalExprs (k + 1) P st []) := by
  simp only [evalExprs]; exact EsOk.of (.refl S) cells rfl (Shapes.nil P)

include ih in
theorem step_exprs_cons {e : Expr} {es : List Expr} {t : Ty} {ts : List Ty} (fe : ExprFrag e = true)
    (fes : ExprsFrag es = true) (head : ExprHasType P Γ e t) (tail : ExprsHaveTypes P Γ es ts)
    (cells : CellsOk P S st) (locs : LocalsOk S Γ st) : EsOk P S st (t :: ts) (evalExprs (k + 1) P st (e :: es)) := by
  simp only [evalExprs]
  have h := ih.expr fe head cells locs
  cases hr : evalExpr k P st e with
  | done v next =>
    rw [hr] at h
    obtain ⟨S1, le1, cells1, same1, sh⟩ := h
    have h2 := ih.exprs fes tail cells1 (locs.mono le1 same1)
    dsimp only
    cases hr2 : evalExprs k P next es with
    | done vs c =>
      rw [hr2] at h2
      obtain ⟨S2, le2, cells2, same2, shs⟩ := h2
      exact EsOk.of (le1.trans le2) cells2 (same2.trans same1) (Shapes.cons sh shs)
    | _ => rw [hr2] at h2; pass h2
  | _ => rw [hr] at h; pass h

omit ih in
theorem arms_nil {v : Value} {tr : Ty} : ∀ k, EOk P S st tr (evalMatchArms k P st v [])
  | 0 => by simp only [evalMatchArms]; trivial
  | _ + 1 => by simp only [evalMatchArms]; own_trap

include ih in
theorem step_arms_cons {v : Value} {pat : Pattern} {body : Expr} {arms : List (Pattern × Expr)} {ts tr : Ty}
    {bindings : List (Nat × Ty)} (fb : ExprFrag body = true) (pattern : PatternHasType P pat ts bindings)
    (typedBody : ExprHasType P (Γ.bindAll bindings) body tr) (rest : EOk P S st tr (evalMatchArms k P st v arms))
    (sh : Shape P v ts) (cells : CellsOk P S st) (locs : LocalsOk S Γ st) :
    EOk P S st tr (evalMatchArms (k + 1) P st v ((pat, body) :: arms)) := by
  simp only [evalMatchArms]
  cases hm : Lanius.Semantics.matchPattern pat v with
  | none => exact rest
  | some bs =>
    dsimp only
    obtain ⟨S1, le1, cells1, locs1⟩ := bindLocals_ok (pattern_binds pattern sh hm) cells locs
    exact EOk.restore le1 rfl (ih.expr fb typedBody cells1 locs1)

/-! ## Places -/

omit ih in
theorem step_place_local {id : Nat} {t : Ty} (acc : Lanius.Semantics.PlaceAccess) (found : Γ id = some t)
    (cells : CellsOk P S st) (locs : LocalsOk S Γ st) : PlOk P S st t (evalPlace (k + 1) P st acc (.local id)) := by
  obtain ⟨c, hc, hS⟩ := locs _ _ found
  obtain ⟨cell, hcell, shaped⟩ := cells.typed _ _ hS
  obtain ⟨cid, value⟩ := cell
  simp only [evalPlace, hc, hcell]
  cases acc <;> cases value <;>
    first
    | own_trap
    | exact PlOk.of rfl hS .nil shaped

include ih in
theorem step_place_field {b : Place} {i id : Nat} {d : Core.StructDecl} {t : Ty} (acc : Lanius.Semantics.PlaceAccess)
    (fb : PlaceFrag b = true) (base : PlaceHasType P Γ b (.structure id)) (found : P.structure? id = some d)
    (fieldFound : d.fields[i]? = some t) (cells : CellsOk P S st) (locs : LocalsOk S Γ st) :
    PlOk P S st t (evalPlace (k + 1) P st acc (.field b i)) := by
  simp only [evalPlace]
  have h := ih.place .address fb base cells locs
  cases hr : evalPlace k P st .address b with
  | done rp next =>
    rw [hr] at h
    obtain ⟨hst, raw, ⟨T0, root, path⟩, vsh⟩ := h
    subst hst
    dsimp only
    simp only [raw]
    cases hv : rp.value with
    | none => own_trap
    | some v =>
      obtain ⟨vs, rfl, fields⟩ := (vsh v hv).struct_fields found
      obtain ⟨w, hw, shw⟩ := fields.get fieldFound
      simp only [hw]
      exact PlOk.of rfl root (path.snoc found fieldFound) (fun u hu => by cases hu; exact shw)
  | _ => rw [hr] at h; pass h

/-! ## Statements -/

include ih in
theorem step_expression {e : Expr} {t ret : Ty} {inLoop : Bool} (fe : ExprFrag e = true) (typed : ExprHasType P Γ e t)
    (cells : CellsOk P S st) (locs : LocalsOk S Γ st) :
    SOk P S st ret inLoop (execStmt (k + 1) P st (.expression e)) := by
  simp only [execStmt]
  have h := ih.expr fe typed cells locs
  cases hr : evalExpr k P st e with
  | done v next =>
    rw [hr] at h
    obtain ⟨S1, le1, cells1, same1, -⟩ := h
    exact SOk.of le1 cells1 same1 trivial
  | _ => rw [hr] at h; pass h

include ih in
theorem step_sequence {a b : Stmt} {ret : Ty} {inLoop : Bool} (fa : StmtFrag a = true) (fb : StmtFrag b = true)
    (first : StmtHasType P ret Γ inLoop a) (second : StmtHasType P ret Γ inLoop b)
    (cells : CellsOk P S st) (locs : LocalsOk S Γ st) :
    SOk P S st ret inLoop (execStmt (k + 1) P st (.sequence a b)) := by
  simp only [execStmt]
  have h := ih.stmt fa first cells locs
  cases hr : execStmt k P st a with
  | done c next =>
    rw [hr] at h
    obtain ⟨S1, le1, cells1, same1, comp⟩ := h
    cases c with
    | next => exact (ih.stmt fb second cells1 (locs.mono le1 same1)).weaken le1 same1
    | _ => exact SOk.of le1 cells1 same1 comp
  | _ => rw [hr] at h; pass h

include ih in
theorem step_letLocal {id : Nat} {ty ret : Ty} {inLoop : Bool} {e : Expr} {body : Stmt} (fe : ExprFrag e = true)
    (fb : StmtFrag body = true) (initializer : ExprHasType P Γ e ty)
    (typedBody : StmtHasType P ret (Γ.bind id ty) inLoop body) (cells : CellsOk P S st) (locs : LocalsOk S Γ st) :
    SOk P S st ret inLoop (execStmt (k + 1) P st (.letLocal id ty e body)) := by
  simp only [execStmt]
  have h := ih.expr fe initializer cells locs
  cases hr : evalExpr k P st e with
  | done v next =>
    rw [hr] at h
    obtain ⟨S1, le1, cells1, same1, sh⟩ := h
    dsimp only
    obtain ⟨cells2, le2⟩ := cells1.bindCell id (value := some v) (t := ty) (fun w hw => by cases hw; exact sh)
    have locs2 := (locs.mono le1 same1).bindCell cells1 id (some v) ty
    exact SOk.restore (le1.trans le2) same1 (ih.stmt fb typedBody cells2 locs2)
  | _ => rw [hr] at h; pass h

include ih in
theorem step_letUninitialized {id : Nat} {ty ret : Ty} {inLoop : Bool} {body : Stmt} (fb : StmtFrag body = true)
    (typedBody : StmtHasType P ret (Γ.bind id ty) inLoop body) (cells : CellsOk P S st) (locs : LocalsOk S Γ st) :
    SOk P S st ret inLoop (execStmt (k + 1) P st (.letUninitialized id ty body)) := by
  simp only [execStmt]
  obtain ⟨cells2, le2⟩ := cells.bindCell id (value := none) (t := ty) (fun w hw => by cases hw)
  have locs2 := locs.bindCell cells id none ty
  exact SOk.restore le2 rfl (ih.stmt fb typedBody cells2 locs2)

include ih in
theorem step_if {c : Expr} {a b : Stmt} {ret : Ty} {inLoop : Bool} (fc : ExprFrag c = true) (fa : StmtFrag a = true)
    (fb : StmtFrag b = true) (condition : ExprHasType P Γ c (.scalar .bool)) (thenBranch : StmtHasType P ret Γ inLoop a)
    (elseBranch : StmtHasType P ret Γ inLoop b) (cells : CellsOk P S st) (locs : LocalsOk S Γ st) :
    SOk P S st ret inLoop (execStmt (k + 1) P st (.ifThenElse c a b)) := by
  simp only [execStmt]
  have h := ih.expr fc condition cells locs
  cases hr : evalExpr k P st c with
  | done v next =>
    rw [hr] at h
    obtain ⟨S1, le1, cells1, same1, sh⟩ := h
    obtain ⟨bv, rfl⟩ := sh.bool_inv
    cases bv with
    | true => exact (ih.stmt fa thenBranch cells1 (locs.mono le1 same1)).weaken le1 same1
    | false => exact (ih.stmt fb elseBranch cells1 (locs.mono le1 same1)).weaken le1 same1
  | _ => rw [hr] at h; pass h

include ih in
theorem step_while {c : Expr} {body : Stmt} {ret : Ty} {inLoop : Bool} (fc : ExprFrag c = true)
    (fb : StmtFrag body = true) (condition : ExprHasType P Γ c (.scalar .bool))
    (typedBody : StmtHasType P ret Γ true body) (cells : CellsOk P S st) (locs : LocalsOk S Γ st) :
    SOk P S st ret inLoop (execStmt (k + 1) P st (.whileLoop c body)) := by
  simp only [execStmt]
  have h := ih.expr fc condition cells locs
  have floop : StmtFrag (.whileLoop c body) = true := by simp [StmtFrag, fc, fb]
  cases hr : evalExpr k P st c with
  | done v next =>
    rw [hr] at h
    obtain ⟨S1, le1, cells1, same1, sh⟩ := h
    obtain ⟨bv, rfl⟩ := sh.bool_inv
    cases bv with
    | false => exact SOk.of le1 cells1 same1 trivial
    | true =>
      dsimp only
      have hb := ih.stmt fb typedBody cells1 (locs.mono le1 same1)
      cases hx : execStmt k P next body with
      | done comp completed =>
        rw [hx] at hb
        obtain ⟨S2, le2, cells2, same2, compOk⟩ := hb
        have le := le1.trans le2
        have same := same2.trans same1
        cases comp with
        | next =>
          exact (ih.stmt floop (.whileLoop condition typedBody) cells2 (locs.mono le same)).weaken le same
        | continueLoop =>
          exact (ih.stmt floop (.whileLoop condition typedBody) cells2 (locs.mono le same)).weaken le same
        | breakLoop => exact SOk.of le cells2 same trivial
        | returned rv =>
          cases rv with
          | none => exact SOk.of le cells2 same trivial
          | some w => exact SOk.of le cells2 same (show Shape P w ret from compOk)
      | _ => rw [hx] at hb; pass hb
  | _ => rw [hr] at h; pass h

include ih in
theorem step_return {e : Expr} {ret : Ty} {inLoop : Bool} (fe : ExprFrag e = true) (typed : ExprHasType P Γ e ret)
    (cells : CellsOk P S st) (locs : LocalsOk S Γ st) :
    SOk P S st ret inLoop (execStmt (k + 1) P st (.returnValue (some e))) := by
  simp only [execStmt]
  have h := ih.expr fe typed cells locs
  cases hr : evalExpr k P st e with
  | done v next =>
    rw [hr] at h
    obtain ⟨S1, le1, cells1, same1, sh⟩ := h
    exact SOk.of le1 cells1 same1 (show Shape P v ret from sh)
  | _ => rw [hr] at h; pass h

end Step

/-! ## The induction on fuel -/

theorem step {P : Core.Program} {k : Nat} (prog : ProgOk P) (ih : Good P k) : Good P (k + 1) where
  expr := by
    intro S Γ st e t frag typed cells locs
    cases typed with
    | value typed _ => simp only [evalExpr]; exact EOk.of (.refl S) cells rfl (ValueHasType.shape typed)
    | «local» found => exact step_local found cells locs
    | cast operand conversion =>
      simp only [ExprFrag] at frag; exact step_cast ih frag operand conversion cells locs
    | unary operand operation =>
      simp only [ExprFrag] at frag; exact step_unary ih frag operand operation cells locs
    | binary left right operation =>
      simp only [ExprFrag, Bool.and_eq_true] at frag
      exact step_binary ih frag.1 frag.2 left right operation cells locs
    | array elements => simp only [ExprFrag] at frag; exact step_array ih frag elements cells locs
    | structValue declaration found fields =>
      simp only [ExprFrag] at frag; exact step_struct ih frag found fields cells locs
    | field base declaration found fieldFound =>
      simp only [ExprFrag] at frag; exact step_field ih frag base found fieldFound cells locs
    | enumValue declaration found variantFound payload =>
      simp only [ExprFrag] at frag; exact step_enum ih frag found variantFound payload cells locs
    | matchValue scrutinee typedArms =>
      simp only [ExprFrag, Bool.and_eq_true] at frag
      exact step_match ih frag.1 frag.2 scrutinee typedArms cells locs
    | assign target value operation =>
      simp only [ExprFrag, Bool.and_eq_true] at frag
      exact step_assign ih frag.1 frag.2 target value operation cells locs
    | call function found arguments =>
      simp only [ExprFrag] at frag; exact step_call ih prog frag found arguments cells locs
    | printI32 argument =>
      simp only [ExprFrag, IntrinsicFrag, Bool.true_and] at frag; exact step_print ih frag argument cells locs
    | assert argument =>
      simp only [ExprFrag, IntrinsicFrag, Bool.true_and] at frag; exact step_assert ih frag argument cells locs
    | _ => simp [ExprFrag, IntrinsicFrag] at frag
  exprs := by
    intro S Γ st es ts frag typed cells locs
    cases typed with
    | nil => exact step_exprs_nil cells
    | cons head tail =>
      simp only [ExprsFrag, Bool.and_eq_true] at frag
      exact step_exprs_cons ih frag.1 frag.2 head tail cells locs
  arms := by
    intro S Γ st v arms ts tr frag typed sh cells locs
    cases typed with
    | one pattern body =>
      simp only [ArmsFrag, Bool.and_eq_true] at frag
      exact step_arms_cons ih frag.1 pattern body (arms_nil k) sh cells locs
    | cons pattern body tail =>
      simp only [ArmsFrag, Bool.and_eq_true] at frag
      exact step_arms_cons ih frag.1 pattern body (ih.arms frag.2 tail sh cells locs) sh cells locs
  place := by
    intro S Γ st p t acc frag typed cells locs
    cases typed with
    | «local» found => exact step_place_local acc found cells locs
    | field base declaration found fieldFound =>
      simp only [PlaceFrag] at frag; exact step_place_field ih acc frag base found fieldFound cells locs
    | _ => simp [PlaceFrag] at frag
  stmt := by
    intro S Γ st ret inLoop s frag typed cells locs
    cases typed with
    | skip => simp only [execStmt]; exact SOk.of (.refl S) cells rfl trivial
    | expression typed => simp only [StmtFrag] at frag; exact step_expression ih frag typed cells locs
    | sequence first second =>
      simp only [StmtFrag, Bool.and_eq_true] at frag
      exact step_sequence ih frag.1 frag.2 first second cells locs
    | letLocal initializer body =>
      simp only [StmtFrag, Bool.and_eq_true] at frag
      exact step_letLocal ih frag.1 frag.2 initializer body cells locs
    | letUninitialized body =>
      simp only [StmtFrag] at frag; exact step_letUninitialized ih frag body cells locs
    | ifThenElse condition thenBranch elseBranch =>
      simp only [StmtFrag, Bool.and_eq_true] at frag
      exact step_if ih frag.1.1 frag.1.2 frag.2 condition thenBranch elseBranch cells locs
    | whileLoop condition body =>
      simp only [StmtFrag, Bool.and_eq_true] at frag
      exact step_while ih frag.1 frag.2 condition body cells locs
    | returnUnit _ => simp only [execStmt]; exact SOk.of (.refl S) cells rfl trivial
    | returnValue value => simp only [StmtFrag] at frag; exact step_return ih frag value cells locs
    | breakLoop => simp only [execStmt]; exact SOk.of (.refl S) cells rfl rfl
    | continueLoop => simp only [execStmt]; exact SOk.of (.refl S) cells rfl rfl
    | _ => simp [StmtFrag] at frag

theorem good {P : Core.Program} (prog : ProgOk P) : ∀ k, Good P k
  | 0 => {
      expr := fun _ _ _ _ => by simp only [evalExpr]; trivial
      exprs := fun _ _ _ _ => by simp only [evalExprs]; trivial
      arms := fun _ _ _ _ _ => by simp only [evalMatchArms]; trivial
      place := fun _ _ _ _ _ => by simp only [evalPlace]; trivial
      stmt := fun _ _ _ _ => by simp only [execStmt]; trivial }
  | k + 1 => step prog (good prog k)

/-- Finding 2: a well-typed Core program of the fragment, from a typed
state, never traps with `typeMismatch`. -/
theorem evalExpr_ne_typeMismatch {P : Core.Program} (prog : ProgOk P) {k : Nat} {S : CellTypes} {Γ : Context}
    {st : State} {e : Expr} {t : Ty} (frag : ExprFrag e = true) (typed : ExprHasType P Γ e t)
    (cells : CellsOk P S st) (locs : LocalsOk S Γ st) (st' : State) :
    evalExpr k P st e ≠ .trapped .typeMismatch st' := by
  intro run
  have := (good prog k).expr frag typed cells locs
  rw [run] at this
  exact this rfl

theorem execStmt_ne_typeMismatch {P : Core.Program} (prog : ProgOk P) {k : Nat} {S : CellTypes} {Γ : Context}
    {st : State} {ret : Ty} {inLoop : Bool} {s : Stmt} (frag : StmtFrag s = true)
    (typed : StmtHasType P ret Γ inLoop s) (cells : CellsOk P S st) (locs : LocalsOk S Γ st) (st' : State) :
    execStmt k P st s ≠ .trapped .typeMismatch st' := by
  intro run
  have := (good prog k).stmt frag typed cells locs
  rw [run] at this
  exact this rfl

end Lanius.Mini.NoMismatch
