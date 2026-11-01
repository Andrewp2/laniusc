import Lanius.Faithful.Pure

/-! # The pure semantics with a heap cost (review #5 step 3, piece (b))

Core's heap grows only at `boxed`, and nothing bounds it from outside:
`selfStart`'s heap has no budget (`HeapCorr.unbounded`), and past `2 ^ 64`
Core's 8-byte pointer stores wrap, so a forward simulation needs the heap a
run will take before it runs. `qcall` is `pcall` with a count beside each
value: the same evaluation, in the same order, adding `cost c` at each call
of a `boxed` prim `c` (its block's size and alignment, which the forward
simulation of `boxed` bounds) and nothing elsewhere. It has a value exactly
where `pcall` has one, the same value (`pcall_eq_qcall`). -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (evalBinaryValue matchPattern)

/-- Calls with their heap cost. -/
abbrev QCalls := Nat → List Value → Option (Value × Nat)

/-- A result and the cost before it. -/
def addC {α : Type} (h : Nat) : Option (α × Nat) → Option (α × Nat) :=
  Option.map fun p => (p.1, h + p.2)

/-- A result of a pure step, at no cost. -/
def qfree {α : Type} (o : Option α) : Option (α × Nat) := o.map (·, 0)

/-- A result after another, the costs added. -/
def qthen {α β : Type} (o : Option (α × Nat)) (k : α → Option (β × Nat)) : Option (β × Nat) :=
  o.bind fun p => addC p.2 (k p.1)

def qbinary (op : Core.BinaryOp) (left right : Option (Value × Nat)) : Option (Value × Nat) :=
  qthen left fun l => qthen right fun r => qfree (evalBinaryValue target op l r).toOption

/-- `applyOp` with costs: the right side counts only where it runs. -/
def qapplyOp (op : SrcOp) (left right : Option (Value × Nat)) : Option (Value × Nat) :=
  match op with
  | .logicalAnd => qthen left fun l => (asBool l).bind fun b => if b then right else some (.boolean false, 0)
  | .logicalOr => qthen left fun l => (asBool l).bind fun b => if b then some (.boolean true, 0) else right
  | .plus | .minus | .times | .bitAnd | .bitOr | .bitXor | .shiftLeft | .shiftRight | .less
  | .lessEq | .greater | .greaterEq | .equal | .notEqual => qbinary op.toCore left right

section
variable (call : QCalls)

mutual
def qeff (env : Env) : SrcEff → Option (Value × Nat)
  | .ePure e => qfree (pexpr env e)
  | .eCall callee args => qthen (qeffs env args) (call callee)
  | .eApply op left right => qapplyOp op (qeff env left) (qeff env right)
  | .eNeg operand => qthen (qeff env operand) fun v => qfree (unary .negate v)
  | .eNot operand => qthen (qeff env operand) fun v => qfree (unary .logicalNot v)
  | .eCast ty operand => qthen (qeff env operand) fun v => qfree (cast ty v)
  | .eIndex _ _ => none
  | .eStruct ty fields => qthen (qeffs env fields) fun vs => some (.structure ty.typeId vs, 0)
  | .eVariant ty variant payload =>
      qthen (qeffs env payload) fun vs => some (.enumeration ty.typeId variant vs, 0)
  | .eMatch scrutinee ety _ binders values =>
      qthen (qeff env scrutinee) fun v => qarms env v ety.typeId 0 binders values
  | .eDivide op left right => qbinary op.toCore (qeff env left) (qeff env right)
  | .eStride _ => none

def qeffs (env : Env) : List SrcEff → Option (List Value × Nat)
  | [] => some ([], 0)
  | e :: es => qthen (qeff env e) fun v => qthen (qeffs env es) fun vs => some (v :: vs, 0)

def qarms (env : Env) (v : Value) (id : Nat) : Nat → List (List Nat) → List SrcEff → Option (Value × Nat)
  | _, [], _ => none
  | _, _ :: _, [] => none
  | k, binders :: rest, value :: values =>
      match matchPattern (.enumVariant id k (binders.map .bind)) v with
      | none => qarms env v id (k + 1) rest values
      | some bindings => qeff (env.bindAll bindings) value
end

def Done.qthen (rest : Option (Done × Nat)) : Done → Option (Done × Nat)
  | .next => rest
  | .ret value => some (.ret value, 0)

def qstmt (env : Env) : SrcStmt → Option (Done × Nat)
  | .nop => some (.next, 0)
  | .let id _ value body => (pexpr env value).bind fun v => qstmt ((id, v) :: env) body
  | .letStruct id ty fields body =>
      (pexprs env fields).bind fun vs => qstmt ((id, .structure ty.typeId vs) :: env) body
  | .letCall id _ callee args body =>
      qthen ((pexprs env args).bind (call callee)) fun v => qstmt ((id, v) :: env) body
  | .letEnum id ty variant payload body =>
      (pexprs env payload).bind fun vs => qstmt ((id, .enumeration ty.typeId variant vs) :: env) body
  | .letMatch _ _ _ _ _ _ => none
  | .set _ _ => none
  | .setField _ _ _ => none
  | .setCall _ _ _ => none
  | .then first second => qthen (qstmt env first) (Done.qthen (qstmt env second))
  | .if condition thenBranch elseBranch =>
      ((pexpr env condition).bind asBool).bind fun b =>
        if b then qstmt env thenBranch else qstmt env elseBranch
  | .while _ _ => none
  | .return value => qfree ((pexpr env value).map fun v => .ret (some v))
  | .letAlloc _ _ _ _ => none
  | .letLoad _ _ _ _ => none
  | .setByte _ _ _ => none
  | .free _ _ _ => none
  | .letSlice _ _ _ _ _ => none
  | .letIndex _ _ _ _ _ => none
  | .setIndex _ _ _ => none
  | .letEval id _ value body => qthen (qeff call env value) fun v => qstmt ((id, v) :: env) body
  | .setEval _ _ => none
  | .ifEval condition thenBranch elseBranch =>
      qthen (qeff call env condition) fun c => (asBool c).bind fun b =>
        if b then qstmt env thenBranch else qstmt env elseBranch
  | .whileEval _ _ => none
  | .returnEval value => qthen (qeff call env value) fun v => some (.ret (some v), 0)
  | .discard value => qthen (qeff call env value) fun _ => some (.next, 0)
  | .setIndexEval _ _ _ => none
  | .setFieldEval _ _ _ => none
  | .returnUnit => some (.ret none, 0)
  | .break => none
  | .continue => none
  | .matchArm _ _ _ _ _ _ _ _ => none
  | .unreachable _ _ => none
  | .assert condition =>
      qthen (qeff call env condition) fun c => (asBool c).bind fun b => if b then some (.next, 0) else none

end

/-- `pcall` with each call's heap cost: `cost c` at a `boxed` prim `c`. -/
def qcall (sp : SrcProgram) (prims : Prims) (cost : Nat → Nat) : Nat → QCalls
  | 0, _, _ => none
  | fuel + 1, callee, values =>
    if prims.isPrim callee then
      (single values).map (·, if prims.boxed.contains callee then cost callee else 0)
    else
      match sp.funcs[callee]? with
      | none => none
      | some f =>
        if values.length = f.params.length then
          qthen (qstmt (qcall sp prims cost fuel) (paramEnv f.params values) f.body) fun d =>
            qfree (doneValue f.ret d)
        else none

/-- The heap cost of a call. -/
def ccall (sp : SrcProgram) (prims : Prims) (cost : Nat → Nat) (fuel c : Nat) (vs : List Value) : Option Nat :=
  (qcall sp prims cost fuel c vs).map Prod.snd

/-! ## The values are `pcall`'s -/

theorem fst_addC {α : Type} (h : Nat) (o : Option (α × Nat)) : (addC h o).map Prod.fst = o.map Prod.fst := by
  cases o <;> rfl

theorem fst_qthen {α β : Type} {o : Option (α × Nat)} {k : α → Option (β × Nat)} {a : Option α}
    {g : α → Option β} (ho : a = o.map Prod.fst) (hk : ∀ x, g x = (k x).map Prod.fst) :
    a.bind g = (qthen o k).map Prod.fst := by
  subst ho
  cases o with
  | none => rfl
  | some p => simp only [Option.map_some, Option.bind_some, qthen, fst_addC, hk]

theorem fst_qfree {α : Type} (o : Option α) : o = (qfree o).map Prod.fst := by
  cases o <;> rfl

theorem fst_qbinary {op : Core.BinaryOp} {l r : Option Value} {ql qr : Option (Value × Nat)}
    (hl : l = ql.map Prod.fst) (hr : r = qr.map Prod.fst) :
    binary op l r = (qbinary op ql qr).map Prod.fst :=
  fst_qthen hl fun _ => fst_qthen hr fun _ => fst_qfree _

theorem fst_qapplyOp {op : SrcOp} {l r : Option Value} {ql qr : Option (Value × Nat)}
    (hl : l = ql.map Prod.fst) (hr : r = qr.map Prod.fst) :
    applyOp op l r = (qapplyOp op ql qr).map Prod.fst := by
  cases op with
  | logicalAnd =>
    simp only [applyOp, qapplyOp]
    rw [Option.bind_assoc]
    refine fst_qthen hl fun x => ?_
    cases asBool x with
    | none => rfl
    | some b => cases b with
      | true => exact hr
      | false => rfl
  | logicalOr =>
    simp only [applyOp, qapplyOp]
    rw [Option.bind_assoc]
    refine fst_qthen hl fun x => ?_
    cases asBool x with
    | none => rfl
    | some b => cases b with
      | true => rfl
      | false => exact hr
  | plus | minus | times | bitAnd | bitOr | bitXor | shiftLeft | shiftRight | less | lessEq | greater
  | greaterEq | equal | notEqual => exact fst_qbinary hl hr

section
variable {call : Calls} {qc : QCalls}

mutual
theorem peff_eq (hc : ∀ c vs, call c vs = (qc c vs).map Prod.fst) : ∀ (env : Env) (e : SrcEff), peff call env e = (qeff qc env e).map Prod.fst
  | env, .ePure e => fst_qfree _
  | env, .eCall callee args => fst_qthen (peffs_eq hc env args) (hc callee)
  | env, .eApply op l r => fst_qapplyOp (peff_eq hc env l) (peff_eq hc env r)
  | env, .eNeg o => fst_qthen (peff_eq hc env o) fun _ => fst_qfree _
  | env, .eNot o => fst_qthen (peff_eq hc env o) fun _ => fst_qfree _
  | env, .eCast ty o => fst_qthen (peff_eq hc env o) fun _ => fst_qfree _
  | env, .eIndex _ _ => rfl
  | env, .eStruct ty fields => by
    rw [peff, qeff, Option.map_eq_bind]
    exact fst_qthen (peffs_eq hc env fields) fun _ => rfl
  | env, .eVariant ty k payload => by
    rw [peff, qeff, Option.map_eq_bind]
    exact fst_qthen (peffs_eq hc env payload) fun _ => rfl
  | env, .eMatch s ety _ binders values =>
    fst_qthen (peff_eq hc env s) fun v => parms_eq hc env v ety.typeId 0 binders values
  | env, .eDivide op l r => fst_qbinary (peff_eq hc env l) (peff_eq hc env r)
  | env, .eStride _ => rfl

theorem peffs_eq (hc : ∀ c vs, call c vs = (qc c vs).map Prod.fst) : ∀ (env : Env) (es : List SrcEff), peffs call env es = (qeffs qc env es).map Prod.fst
  | env, [] => rfl
  | env, e :: es => by
    rw [peffs, qeffs]
    refine fst_qthen (peff_eq hc env e) fun v => ?_
    rw [Option.map_eq_bind]
    exact fst_qthen (peffs_eq hc env es) fun _ => rfl

theorem parms_eq (hc : ∀ c vs, call c vs = (qc c vs).map Prod.fst) : ∀ (env : Env) (v : Value) (id k : Nat) (binders : List (List Nat)) (values : List SrcEff),
    parms call env v id k binders values = (qarms qc env v id k binders values).map Prod.fst
  | _, _, _, _, [], _ => by rw [parms, qarms]; rfl
  | _, _, _, _, _ :: _, [] => by rw [parms, qarms]; rfl
  | env, v, id, k, bs :: rest, value :: values => by
    rw [parms, qarms]
    cases matchPattern (.enumVariant id k (bs.map .bind)) v with
    | none => exact parms_eq hc env v id (k + 1) rest values
    | some bindings => exact peff_eq hc (env.bindAll bindings) value
end

theorem pstmt_eq (hc : ∀ c vs, call c vs = (qc c vs).map Prod.fst) : ∀ (s : SrcStmt) (env : Env), pstmt call env s = (qstmt qc env s).map Prod.fst := by
  intro s
  induction s with
  | nop => intro env; rfl
  | «let» id _ value body ih =>
    intro env
    rw [pstmt, qstmt]
    cases pexpr env value with
    | none => rfl
    | some v => exact ih _
  | letStruct id ty fields body ih =>
    intro env
    rw [pstmt, qstmt]
    cases pexprs env fields with
    | none => rfl
    | some vs => exact ih _
  | letCall id _ callee args body ih =>
    intro env
    rw [pstmt, qstmt]
    refine fst_qthen ?_ fun v => ih _
    cases pexprs env args with
    | none => rfl
    | some vs => exact hc callee vs
  | letEnum id ty k payload body ih =>
    intro env
    rw [pstmt, qstmt]
    cases pexprs env payload with
    | none => rfl
    | some vs => exact ih _
  | «then» first second ih1 ih2 =>
    intro env
    rw [pstmt, qstmt]
    refine fst_qthen (ih1 env) fun d => ?_
    cases d with
    | next => exact ih2 env
    | ret _ => rfl
  | «if» condition a b iha ihb =>
    intro env
    rw [pstmt, qstmt]
    cases (pexpr env condition).bind asBool with
    | none => rfl
    | some bv => cases bv with
      | true => exact iha env
      | false => exact ihb env
  | «return» value => intro env; exact fst_qfree _
  | letEval id _ value body ih =>
    intro env
    rw [pstmt, qstmt]
    exact fst_qthen (peff_eq hc env value) fun v => ih _
  | ifEval condition a b iha ihb =>
    intro env
    rw [pstmt, qstmt, Option.bind_assoc]
    refine fst_qthen (peff_eq hc env condition) fun c => ?_
    cases asBool c with
    | none => rfl
    | some bv => cases bv with
      | true => exact iha env
      | false => exact ihb env
  | returnEval value =>
    intro env
    rw [pstmt, qstmt, Option.map_eq_bind]
    exact fst_qthen (peff_eq hc env value) fun _ => rfl
  | discard value =>
    intro env
    rw [pstmt, qstmt, Option.map_eq_bind]
    exact fst_qthen (peff_eq hc env value) fun _ => rfl
  | assert condition =>
    intro env
    rw [pstmt, qstmt, Option.bind_assoc]
    refine fst_qthen (peff_eq hc env condition) fun c => ?_
    cases asBool c with
    | none => rfl
    | some bv => cases bv with
      | true => rfl
      | false => rfl
  | returnUnit => intro env; rfl
  | letMatch _ _ _ _ _ _ | set _ _ | setField _ _ _ | setCall _ _ _ | «while» _ _ | letAlloc _ _ _ _
  | letLoad _ _ _ _ | setByte _ _ _ | free _ _ _ | letSlice _ _ _ _ _ | letIndex _ _ _ _ _
  | setIndex _ _ _ | setEval _ _ | whileEval _ _ | setIndexEval _ _ _ | setFieldEval _ _ _ | «break»
  | «continue» | matchArm _ _ _ _ _ _ _ _ | unreachable _ _ => intro env; rfl

end

/-- **`qcall`'s values are `pcall`'s.** -/
theorem pcall_eq_qcall (sp : SrcProgram) (prims : Prims) (cost : Nat → Nat) :
    ∀ (fuel c : Nat) (vs : List Value), pcall sp prims fuel c vs = (qcall sp prims cost fuel c vs).map Prod.fst
  | 0, _, _ => rfl
  | fuel + 1, c, vs => by
    rw [pcall, qcall]
    split
    · cases single vs <;> rfl
    · cases sp.funcs[c]? with
      | none => rfl
      | some f =>
        simp only
        split
        · exact fst_qthen (pstmt_eq (pcall_eq_qcall sp prims cost fuel) f.body _) fun d => fst_qfree _
        · rfl

/-- A pure call with a value has a heap cost. -/
theorem qcall_of_pcall {sp : SrcProgram} {prims : Prims} (cost : Nat → Nat) {fuel c : Nat} {vs : List Value}
    {w : Value} (h : pcall sp prims fuel c vs = some w) : ∃ n, qcall sp prims cost fuel c vs = some (w, n) := by
  rw [pcall_eq_qcall sp prims cost] at h
  cases hq : qcall sp prims cost fuel c vs with
  | none => rw [hq] at h; cases h
  | some p =>
    rw [hq] at h
    simp only [Option.map_some, Option.some.injEq] at h
    exact ⟨p.2, by rw [← h]⟩

end Lanius.Faithful
