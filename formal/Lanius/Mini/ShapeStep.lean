import Lanius.Mini.ShapeEval

/-! # No `typeMismatch` without raw memory (review finding 2, step 4b)

`Good P k`: each of Core's five evaluators, run with fuel `k` on a term of
the fragment typed by Core's rules, from a state typed by a store typing,
keeps its promise (`EOk`, `EsOk`, `PlOk`, `SOk`). `good`: for a `ProgOk`
program this holds for every fuel, by induction; the step from `k` to
`k + 1` is one lemma per syntactic form. `evalExpr_ne_typeMismatch` is the
consequence finding 2 asks for: such a run never traps with `typeMismatch`. -/

namespace Lanius.Mini

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
macro "own_trap" : tactic => `(tactic| (show _ ≠ _; decide))

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

end Step

end Lanius.Mini
