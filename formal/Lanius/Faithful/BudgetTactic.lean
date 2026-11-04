import Lanius.Faithful.BudgetCore
import Lanius.Faithful.Auto

/-! # `budget`: a budget certificate's proof

A budget certificate's proof (`Budget.lean`) unfolds the call in `h`, the run
of `progW` (`qcall spW ..`, with a cost `k`), and in the goal, the same run of
the self program (`qcall sp ..`) and the cost model:

    h : RUN_W = some (w, k)    hb : k < B    pre : PRE
    ⊢ RUN = some (w, k) ∧ COST = k

`budget` walks the two runs in step, the cost semantics run as far as their
calls (`qsimp`), `qthen` folded:

* a call of a function `ix_K` (`qthen (qcall spW .. n ix_K args) K`): its
  result `r` and cost `c₁` come off `h` (`qthen_peel`, so `k = c₁ + c₂`); the
  callee's budget certificate `b_K` (or `bih_K` in a recursive group) at the
  budget `B`, with the arguments' representations (`rep`), `c₁ < B` and the
  precondition's first conjunct `Pre_K ..`, says the self program's call is the
  same, at the cost `Cost_K ..`, and gives the result's representation. The
  goal's call is replaced by it (`run_step`); what is left of the
  precondition is at the budget `B - c₁`;
* a prim's call (`pp_K : prims.isPrim ix_K = true`): its argument, at the cost
  `bx_K` says (`qcall_prim`), once the fuel is a successor;
* an `if`: both cases, in `h`, the goal and the precondition;
* a value the run waits on (a match's scrutinee, a condition): its
  representation, taken apart (`cases`, after generalizing a Lean side that
  is not a variable: a callee's result);

and at `some (v, d)` it closes the run, then the cost: `COST` unfolded once
(the `Cost_F` given, if any), with the callees' costs (`hcost`), the cases'
conditions (`hcond`) and results (`hx`), by `omega`. -/

namespace Lanius.Faithful.Budget

section
open Lanius.Mini Lanius.Faithful Lanius.Faithful.Termination

open Lean Meta Simp in
/-- A comparison of closed numbers (a shift by a cast literal, `(8 as u64)`,
tests `(BitVec.ofInt 64 (8#32).toInt).toNat < 64`): decided by evaluation,
the proof `of_decide_eq_true rfl` checked by the kernel. -/
simproc_decl closedNatLt ((_ : Nat) < _) := fun e => do
  unless e.isAppOfArity ``LT.lt 4 do return .continue
  if e.hasFVar || e.hasMVar then return .continue
  let d ← Meta.mkDecide e
  let r ← Meta.withTransparency .default <| Meta.whnf d
  if r.isConstOf ``true then
    let inst ← Meta.synthInstance (mkApp (mkConst ``Decidable) e)
    let pf := mkApp3 (mkConst ``of_decide_eq_true) e inst (← Meta.mkEqRefl (mkConst ``true))
    return .done { expr := mkConst ``True, proof? := some (← Meta.mkEqTrue pf) }
  if r.isConstOf ``false then
    let inst ← Meta.synthInstance (mkApp (mkConst ``Decidable) e)
    let pf := mkApp3 (mkConst ``of_decide_eq_false) e inst (← Meta.mkEqRefl (mkConst ``false))
    return .done { expr := mkConst ``False, proof? := some (← Meta.mkEqFalse pf) }
  return .continue

open Lean Meta Simp in
/-- An equation of small closed numbers (production numbers a condition names),
decided by evaluation. -/
simproc_decl closedNatEq ((_ : Nat) = _) := fun e => do
  unless e.isAppOfArity ``Eq 3 do return .continue
  if e.hasFVar || e.hasMVar || e.approxDepth > 40 then return .continue
  let d ← Meta.mkDecide e
  let r ← Meta.withTransparency .default <| Meta.whnf d
  if r.isConstOf ``true then
    let inst ← Meta.synthInstance (mkApp (mkConst ``Decidable) e)
    let pf := mkApp3 (mkConst ``of_decide_eq_true) e inst (← Meta.mkEqRefl (mkConst ``true))
    return .done { expr := mkConst ``True, proof? := some (← Meta.mkEqTrue pf) }
  if r.isConstOf ``false then
    let inst ← Meta.synthInstance (mkApp (mkConst ``Decidable) e)
    let pf := mkApp3 (mkConst ``of_decide_eq_false) e inst (← Meta.mkEqRefl (mkConst ``false))
    return .done { expr := mkConst ``False, proof? := some (← Meta.mkEqFalse pf) }
  return .continue

/-! `qsimp` simplifies a run's head only. What a run does after its first step
(`qthen`'s, `bind`'s and `Out.qthen`'s continuations, an `if`'s branches,
the goal's cost) is simplified when it becomes the head, so a step does not
pass over the rest of the body: `simp` over the whole run at every step made
`let_first`'s proof quadratic in its body (11-02). -/

theorem ite_head_congr.{u} {α : Sort u} {c c' : Prop} [inst : Decidable c] [inst' : Decidable c'] (a b : α)
    (h : c = c') : @ite α c inst a b = @ite α c' inst' a b := by
  subst h
  congr

open Lean Meta Simp in
/-- Simplify only the head of a run: the `j`-th argument of a node with a
continuation, then try the rules at the node itself. -/
partial def headPre (e : Lean.Expr) : SimpM (Option Simp.Step) := do
  let f := e.getAppFn
  let some name := f.constName? | return none
  let args := e.getAppArgs
  let focus (j : Nat) : SimpM (Option Simp.Step) := do
    let r ← Simp.simp args[j]!
    if r.proof?.isNone && r.expr == args[j]! then
      -- the head is as simple as it gets: the rules at the node, if any
      match ← (← getMethods).post e with
      | .done r2 | .visit r2 | .continue (some r2) =>
        if r2.expr == e then return some (.done { expr := e }) else return some (.visit r2)
      | .continue none => return some (.done { expr := e })
    let ty ← inferType args[j]!
    let fn := mkLambda `x .default ty (mkAppN f (args.set! j (.bvar 0)))
    let r1 ← Simp.mkCongrArg fn r
    let e' := r1.expr
    match ← (← getMethods).post e' with
    | .done r2 | .visit r2 | .continue (some r2) =>
      if r2.expr == e' then return some (.done r1) else return some (.visit (← r1.mkEqTrans r2))
    | .continue none => return some (.done r1)
  match name, args.size with
  | ``qthen, 4 => focus 2
  | ``Option.bind, 4 => focus 2
  | ``Out.qthen, 2 => focus 1
  | ``And, 2 => focus 0
  | ``ite, 5 =>
    let us := f.constLevels!
    let (α, c, inst, a, b) := (args[0]!, args[1]!, args[2]!, args[3]!, args[4]!)
    let r ← Simp.simp c
    if r.expr.isTrue then
      return some (.visit { expr := a, proof? := mkAppN (mkConst ``ite_cond_eq_true us) #[α, c, inst, a, b, ← r.getProof] })
    if r.expr.isFalse then
      return some (.visit { expr := b, proof? := mkAppN (mkConst ``ite_cond_eq_false us) #[α, c, inst, a, b, ← r.getProof] })
    if r.proof?.isNone then return some (.done { expr := e })
    let .some inst' ← trySynthInstance (mkApp (mkConst ``Decidable) r.expr) | return none
    let pf := mkAppN (mkConst ``ite_head_congr us) #[α, c, r.expr, inst, inst', a, b, ← r.getProof]
    return some (.done { expr := mkAppN f #[α, r.expr, inst', a, b], proof? := pf })
  | _, _ => return none

open Lean Meta in
/-- `qsimp`'s context, made once per module: building it (the equations of
`qstmt` and the rest) cost 16 ms a call, a sixth of `let_first`'s proof. -/
initialize qsimpCache : IO.Ref (Option (Name × Simp.Context × Simp.SimprocsArray)) ← IO.mkRef none

open Lean Elab Tactic Meta in
/-- `simp only` with the lemmas of `stx`, on the heads only (`headPre`), at
`h` or the goal. -/
def headSimp (stx : Syntax) (h? : Option Syntax) : TacticM Unit := do
  let mod := (← getEnv).mainModule
  let r ← match ← qsimpCache.get with
    | some (m, ctx, simprocs) =>
      if m == mod then pure { ctx, simprocs, dischargeWrapper := .default : MkSimpContextResult }
      else mkSimpContext stx (eraseLocal := false)
    | none => mkSimpContext stx (eraseLocal := false)
  qsimpCache.set (some (mod, r.ctx, r.simprocs))
  let base := Simp.mkDefaultMethodsCore r.simprocs
  let methods : Simp.Methods := { base with
    pre := fun e => do
      match ← headPre e with
      | some step => return step
      | none => base.pre e }
  let g ← getMainGoal
  g.withContext do
    match h? with
    | some h =>
      let fvarId ← getFVarId h
      let type ← instantiateMVars (← fvarId.getType)
      let (res, _) ← Simp.main type r.ctx (methods := methods)
      if res.expr == type then throwError "qsimp made no progress"
      match ← applySimpResultToLocalDecl g fvarId res (mayCloseGoal := true) with
      | none => replaceMainGoal []
      | some (_, g') => replaceMainGoal [g']
    | none =>
      let type ← instantiateMVars (← g.getType)
      let (res, _) ← Simp.main type r.ctx (methods := methods)
      if res.expr == type then throwError "qsimp made no progress"
      if res.expr.isTrue then
        g.assign (← mkOfEqTrue (← res.getProof))
        replaceMainGoal []
      else
        replaceMainGoal [← applySimpResultToTarget g type res]

/-- Run the cost semantics of a body as far as its calls, `qthen` folded. -/
syntax "qsimp" (" at " ident)? : tactic

open Lean Elab Tactic Meta in
elab_rules : tactic
  | `(tactic| qsimp $[at $h?]?) => do
    let stx ← `(tactic| simp (maxSteps := 10000000) only [budget_rule, pure_rule, reduceCtorEq, qstmt, qeff, qeffs, qapplyOp, qbinary, pexpr, pexprs, paramEnv,
      paramBindings, applyOp, binary, unary, Lanius.Faithful.cast, SrcOp.toCore, SrcDivOp.toCore, UintTy.toCore,
      SrcType.toScalar, Nat.reduceLT, Nat.reduceEqDiff, Nat.reduceAdd, Nat.reduceSub, Nat.reduceMul, Nat.reduceMod,
      Nat.reducePow, Nat.reduceBEq, Nat.reduceBNe, Nat.zero_add, Nat.add_zero,
      Except.toOption, closedNatLt, ↓reduceIte])
    headSimp stx h?

end

/-! `qpop` (a `let`'s scope ending) moved inside the run it ends, so that a
call in a `let`'s body is at the head of the run. -/

@[budget_rule] theorem qpop_qthen {α : Type} (o : Option (α × Nat)) (k : α → Option (Out × Nat)) :
    qpop (qthen o k) = qthen o fun x => qpop (k x) := by
  cases o with
  | none => rfl
  | some p =>
    simp only [qpop, qthen, Option.bind_some, addC, Option.map_map]
    rfl

@[budget_rule] theorem qpop_addC (c : Nat) (o : Option (Out × Nat)) : qpop (addC c o) = addC c (qpop o) := by
  cases o <;> rfl

@[budget_rule] theorem qpop_bind {α : Type} (o : Option α) (k : α → Option (Out × Nat)) :
    qpop (o.bind k) = o.bind fun x => qpop (k x) := by
  cases o <;> rfl

@[budget_rule] theorem qpop_ite (c : Prop) [Decidable c] (a b : Option (Out × Nat)) :
    qpop (if c then a else b) = if c then qpop a else qpop b := by
  split <;> rfl

/-- A shift by a literal tests the literal against the width. -/
@[budget_rule] theorem bv_ofNat_toNat_lt (w c n : Nat) : ((BitVec.ofNat w c).toNat < n) = (c % 2 ^ w < n) := by
  simp [BitVec.toNat_ofNat]

@[budget_rule] theorem bv_lit_toNat_lt (w c n : Nat) :
    ((no_index (OfNat.ofNat c : BitVec w)).toNat < n) = (c % 2 ^ w < n) := by
  show ((BitVec.ofNat w c).toNat < n) = _
  simp [BitVec.toNat_ofNat]

attribute [budget_cond] and_true true_and and_false false_and or_true true_or or_false false_or not_true_eq_false
  not_false_eq_true Bool.and_true Bool.true_and Bool.and_false Bool.false_and Bool.or_true Bool.true_or Bool.or_false
  Bool.false_or Bool.not_true Bool.not_false decide_eq_true_eq decide_eq_false_iff_not decide_true decide_false
  Bool.and_eq_true Bool.or_eq_true Bool.not_eq_true' ite_true ite_false Bool.false_eq_true Nat.add_zero Nat.zero_add
  Bool.true_eq_false eq_self_iff_true ite_self beq_iff_eq beq_eq_false_iff_ne bne_iff_ne

open Lean Elab Tactic Meta

-- The tactics built here name the proof's hypotheses (`h`, `pre`, `rfl`
-- patterns): no hygiene.
set_option hygiene false

/-- What the run `h` waits on. -/
inductive Wait where
  | done
  | fail
  | call (call : Expr)
  | addC
  | split (cond : Expr)
  | stuck (e : Expr)

/-- The head of a run: the first thing it waits on. -/
partial def waitOf (e : Expr) : MetaM Wait := do
  let e := (← instantiateMVars e).consumeMData.headBeta
  if e.isAppOfArity ``qthen 4 then
    let o := e.appFn!.appArg!.consumeMData.headBeta
    if o.isAppOfArity ``qcall 6 then return .call o
    return ← waitOf o
  if e.isAppOfArity ``Option.bind 4 then return ← waitOf e.appFn!.appArg!
  if e.isAppOfArity ``Option.map 4 then return ← waitOf e.appArg!
  if e.isAppOfArity ``qfree 2 then return ← waitOf e.appArg!
  if e.isAppOfArity ``qpop 1 then return ← waitOf e.appArg!
  if e.isAppOfArity ``addC 3 then return .addC
  if e.isAppOfArity ``Prod.mk 4 then return .done
  if e.isAppOfArity ``ite 5 then return .split e.appFn!.appFn!.appFn!.appArg!
  if e.isAppOfArity ``Option.some 2 then return .done
  if e.isAppOfArity ``Option.none 1 then return .fail
  return .stuck e

/-- The values a run waits on: a match's scrutinee (`qarms`), a struct
whose field is read, a condition, an operand. -/
def qblockedOn (e : Expr) : Array Expr :=
  let args := e.getAppArgs
  match e.getAppFn with
  | .const n _ =>
    if n == ``qarms && args.size ≥ 3 then #[args[2]!]
    else if n == ``fieldOf && args.size ≥ 1 then #[args[0]!]
    else if n == ``asBool && args.size ≥ 1 then #[args[0]!]
    else if n == ``Lanius.Semantics.matchPattern && args.size ≥ 2 then #[args[1]!]
    else if n == ``Lanius.Semantics.evalBinaryValue && args.size ≥ 4 then #[args[2]!, args[3]!]
    else if (n == ``Lanius.Semantics.evalUnaryValue || n == ``Lanius.Semantics.evalScalarCast) && args.size ≥ 3 then
      #[args[2]!]
    else #[]
  | _ => #[]

partial def qblocking (e : Expr) : Array Expr :=
  match e with
  | .app f a => qblockedOn e ++ qblocking f ++ qblocking a
  | .lam _ t b _ | .forallE _ t b _ => qblocking t ++ qblocking b
  | .letE _ t v b _ => qblocking t ++ qblocking v ++ qblocking b
  | .mdata _ b | .proj _ _ b => qblocking b
  | _ => #[]

/-- Run a tactic built here; an error it logs (a term elaborated with `sorry`) is
an error. -/
def tac (stx : TacticM (TSyntax `tactic)) : TacticM Unit := do
  let s ← stx
  let errors := fun (log : MessageLog) => log.toList.filter (·.severity == .error) |>.length
  let before := errors (← Core.getMessageLog)
  Term.withoutErrToSorry (evalTactic s)
  if errors (← Core.getMessageLog) > before then throwError "budget: {s} logged an error"

def tryT (stx : TacticM (TSyntax `tactic)) : TacticM Bool := do
  let saved ← saveState
  try
    tac stx
    return true
  catch _ =>
    saved.restore
    return false

def hyp? (name : Name) : TacticM (Option LocalDecl) := do
  let goal ← getMainGoal
  goal.withContext do return (← getLCtx).findFromUserName? name

def hypType? (name : Name) : TacticM (Option Expr) := do
  let goal ← getMainGoal
  goal.withContext do
    match (← getLCtx).findFromUserName? name with
    | some d => return some (← instantiateMVars d.type)
    | none => return none

def toStx (e : Expr) : TacticM Term := do
  let goal ← getMainGoal
  goal.withContext do Term.exprToSyntax e

/-- `h`'s run: the left side of `h : RUN = some (w, k)`. -/
def runOf : TacticM Expr := do
  let some t ← hypType? `h | throwError "budget: no run `h`"
  let some (_, lhs, _) := t.eq? | throwError "budget: `h` is not an equation{indentExpr t}"
  return lhs

/-- The budget `B` of `hb : k < B`. -/
def budgetOf? : TacticM (Option Expr) := do
  let some t ← hypType? `hb | return none
  let t := t.consumeMData
  if t.isAppOfArity ``LT.lt 4 then return some t.appArg!
  return none

/-- Take a representation apart: its Lean side generalized first when it is
not a variable and its relation has a constructor whose Lean side is not
one (a struct's or an enum's), with `hx<i>` the equation. -/
def casesRep (rep : FVarId) (i : Nat) : TacticM Unit := do
  let goal ← getMainGoal
  let goals ← goal.withContext do
    let d ← rep.getDecl
    let some (n, x, _) ← repOf? d.type | throwError "budget: not a representation"
    let scalar := [``Lanius.Faithful.RepNat, ``Lanius.Faithful.RepU64, ``Lanius.Faithful.RepU32,
      ``Lanius.Faithful.RepI32, ``Lanius.Faithful.RepU8, ``Lanius.Faithful.RepBool].contains n
    if x.isFVar || scalar then
      return (← goal.cases rep).map (·.mvarId)
    let tName := Name.mkSimple ("t" ++ toString i)
    let hName := Name.mkSimple ("hx" ++ toString i)
    let arg : GeneralizeArg := { expr := x, xName? := some tName, hName? := some hName }
    let (_, _, goal') ← goal.generalizeHyp #[arg] #[rep]
    goal'.withContext do
      let some d' := (← getLCtx).findFromUserName? d.userName | throwError "budget: lost {d.userName}"
      return (← goal'.cases d'.fvarId).map (·.mvarId)
  replaceMainGoal goals.toList

/-- Take apart the single-constructor representations (numbers, structs) of
the values `h` mentions. -/
partial def eagerCases (i : Nat) : TacticM Bool := do
  let goal ← getMainGoal
  let found ← goal.withContext do
    let some d ← hyp? `h | return none
    let t ← instantiateMVars d.type
    for r in ← getLCtx do
      if r.isImplementationDetail then continue
      let some (n, _, v) ← repOf? r.type | continue
      unless v.isFVar && t.containsFVar v.fvarId! do continue
      let some (.inductInfo info) := (← getEnv).find? n | continue
      if info.ctors.length == 1 then return some r.fvarId
    return none
  match found with
  | none => return false
  | some f =>
    casesRep f i
    return true

/-- The representation of a value the run waits on. -/
def stuckRep? (e : Expr) : TacticM (Option FVarId) := do
  let goal ← getMainGoal
  goal.withContext do
    let blocked := qblocking (← instantiateMVars e)
    for r in ← getLCtx do
      if r.isImplementationDetail then continue
      let some (_, _, v) ← repOf? r.type | continue
      unless v.isFVar do continue
      if blocked.any (· == v) then return some r.fvarId
    return none

/-- The names of the hypotheses whose name starts with one of `prefixes`. -/
def hypsNamed (prefixes : List String) : TacticM (Array Ident) := do
  let goal ← getMainGoal
  goal.withContext do
    let mut out := #[]
    for d in ← getLCtx do
      if d.isImplementationDetail then continue
      let s := d.userName.toString
      if prefixes.any (fun p => s.startsWith p && (s.drop p.length).all Char.isDigit && s.length > p.length) then
        out := out.push (mkIdent d.userName)
    return out

/-- What a callee's certificate takes: the hypothesis, whether it is
`Certified`, its number of premises, and whether its cost is `0`. -/
structure CertInfo where
  name : Name
  certified : Bool
  premises : Nat
  free : Bool

def certInfo? (k : String) : TacticM (Option CertInfo) := do
  for pre in ["bih_", "b_"] do
    let name := Name.mkSimple (pre ++ k)
    let some d ← hyp? name | continue
    let goal ← getMainGoal
    let info ← goal.withContext do
      let t ← whnfR (← instantiateMVars d.type)
      let certified := t.isAppOf ``Lanius.Faithful.Certified
      let t := if certified then t.appArg! else t
      forallTelescopeReducing t fun xs body => do
        let mut n := 0
        for x in xs do
          if (← x.fvarId!.getDecl).binderInfo == .default then n := n + 1
        -- `RUN = .. ∧ COST = k ∧ REP`: free when `COST` is `0`
        let body := body.consumeMData
        let free := body.isAppOfArity ``And 2 && body.appArg!.isAppOfArity ``And 2 &&
          (match body.appArg!.appFn!.appArg!.eq? with
           | some (_, l, _) => l.nat? == some 0
           | none => false)
        return { name, certified, premises := n, free }
    return some info
  return none

/-- The callee name `K` of `ix_K`. -/
def calleeKey? (c : Expr) : TacticM (Option String) := do
  let goal ← getMainGoal
  goal.withContext do
    let .fvar id := c.consumeMData | return none
    let name := (← id.getUserName).toString
    if name.startsWith "ix_" then return some (name.drop 3).toString
    return none

/-- The fuel of a call: a successor, or a variable to split. -/
def fuelVar? (fuel : Expr) : Option FVarId :=
  match fuel.consumeMData with
  | .fvar id => some id
  | _ => none

register_option budget.trace : Bool := { defValue := false, descr := "show budget's steps" }
register_option budget.time : Bool := { defValue := false, descr := "show budget's steps' times" }

def timing (m : MessageData) : TacticM Unit := do
  if budget.time.get (← getOptions) then logInfo m!"{(← IO.getNumHeartbeats) / 1000} {m}"

def trace (m : MessageData) : TacticM Unit := do
  if budget.trace.get (← getOptions) then logInfo m

/-- A value taken apart twice (`kid_token(fs, 0)` read twice): its parts made
one, from the two equations `hx_i : x = C a`, `hx_j : x = C b`. -/
def mergeCases : TacticM Unit := do
  let mut seen : Array (Expr × Ident) := #[]
  for h in ← hypsNamed ["hx"] do
    let some t ← hypType? h.getId | continue
    let some (_, lhs, _) := t.eq? | continue
    match seen.find? (·.1 == lhs) with
    | some (_, hi) =>
      let _ ← tryT `(tactic| cases ($h:ident).symm.trans $hi:ident)
    | none => seen := seen.push (lhs, h)

/-- Callees' costs `hcost_j : COST = c_j` with the same `COST` as an earlier
`hcost_i`: `c_j` is `c_i`. -/
def mergeCosts : TacticM Unit := do
  let mut seen : Array (Expr × Ident) := #[]
  for h in ← hypsNamed ["hcost"] do
    let some t ← hypType? h.getId | continue
    let some (_, lhs, rhs) := t.eq? | continue
    unless rhs.isFVar do continue
    match seen.find? (·.1 == lhs) with
    | some (_, hi) =>
      let _ ← tryT `(tactic| obtain rfl := ($h:ident).symm.trans $hi:ident)
    | none => seen := seen.push (lhs, h)

/-- `omega` on the goal alone, every hypothesis it does not mention cleared
first: in a certificate's context of a hundred hypotheses `omega` took minutes
on a sum it proves at once alone. Restores the state on failure. -/
def omegaAlone : TacticM Bool := do
  let saved ← saveState
  try
    let g ← getMainGoal
    let g' ← g.withContext do
      let ty ← instantiateMVars (← g.getType)
      let mut others := #[]
      for d in ← getLCtx do
        if d.isImplementationDetail then continue
        unless ty.containsFVar d.fvarId do others := others.push d.fvarId
      g.tryClearMany others
    replaceMainGoal [g']
    tac `(tactic| omega)
    return true
  catch _ =>
    saved.restore
    return false

/-- Close the cost: `COST = c` with the callees' costs, the cases' conditions
and the generalized results. -/
def closeCost (cost? : Option Ident) : TacticM Unit := do
  let t0 ← IO.monoMsNow
  trace m!"close {← getMainGoal}"
  match cost? with
  | none => tac `(tactic| omega)
  | some c =>
    -- a call made twice: one model, two names for its cost, made one
    mergeCosts
    -- the cases' equations as the model writes its scrutinees: conditions that
    -- equate two variables substituted, a taken-apart struct's fields projected
    for h in ← hypsNamed ["hcond"] do
      if let some t ← hypType? h.getId then
        if let some (_, a, b) := t.eq? then
          if a.isFVar && b.isFVar then
            let _ ← tryT `(tactic| subst $h:ident)
    for h in ← hypsNamed ["hx"] do
      let _ ← tryT `(tactic| dsimp only at $h:ident)
    mergeCases
    mergeCosts
    let hs ← hypsNamed ["hcost", "hcond", "hx"]
    let lemmas : Array (TSyntax `Lean.Parser.Tactic.simpLemma) ← hs.mapM fun h => `(Lean.Parser.Tactic.simpLemma| $h:ident)
    let eqDef := mkIdent (c.getId ++ `eq_def)
    tac `(tactic| rw [$eqDef:ident])
    let _ ← tryT `(tactic| simp (config := { decide := true }) only [$lemmas,*, budget_cond, pure_rule])
    timing m!"close simp {(← IO.monoMsNow) - t0} ms"
    if (← getGoals).isEmpty then return
    -- the models' equations are spent: `omega` would compare their sides as atoms
    -- by unfolding them
    for h in ← hypsNamed ["hcost", "hc", "hq", "hrep"] do
      let _ ← tryT `(tactic| clear $h:ident)
    let _ ← tryT `(tactic| clear $(mkIdent `pre):ident)
    let _ ← tryT `(tactic| clear $(mkIdent `h):ident)
    let t1 ← IO.monoMsNow
    let ok ← omegaAlone
    timing m!"close omega {(← IO.monoMsNow) - t1} ms"
    if ok then return
    -- a cost that still branches on a condition the hypotheses decide
    tac `(tactic| (repeat' split) <;> omega)

/-- The budget left after a cost `c`, `B - c`, as a new variable in `hb` and
`pre`: what follows needs only that budget, and a chain of differences would
leave `omega` a case split per subtraction. -/
def newBudget (bS : Term) (c : Term) (i : Nat) : TacticM Unit := do
  let nb := mkIdent (Name.mkSimple s!"bud{i}")
  let hb := mkIdent `hb
  let pre := mkIdent `pre
  unless ← tryT `(tactic| generalize $bS - $c = $nb:ident at $hb:ident $pre:ident) do
    tac `(tactic| generalize $bS - $c = $nb:ident at $hb:ident)

/-- The cost `C` of the precondition's next step, `∀ b1, C < B → ...`. -/
def preCost? : TacticM (Option Expr) := do
  let some t ← hypType? `pre | return none
  match t.consumeMData with
  | .forallE _ _ body _ =>
    match body.consumeMData with
    | .forallE _ lt _ _ =>
      let lt := lt.consumeMData
      if lt.isAppOfArity ``LT.lt 4 && !lt.appFn!.appArg!.hasLooseBVars then return some lt.appFn!.appArg!
      return none
    | _ => return none
  | _ => return none

/-- The case `hc` contradicts a condition taken before (`T` and `¬T`, as
written): closed. `contradiction` would compare every pair of hypotheses,
the runs among them, which took seconds a case on a long body. -/
def condContradicts (hc : Ident) : TacticM Bool := do
  let some t ← hypType? hc.getId | return false
  let t := t.consumeMData
  let notOf (e : Expr) : Option Expr := if e.isAppOfArity ``Not 1 then some e.appArg!.consumeMData else none
  for h in ← hypsNamed ["hcond"] do
    if h.getId == hc.getId then continue
    let some t' ← hypType? h.getId | continue
    let t' := t'.consumeMData
    if notOf t == some t' then
      tac `(tactic| exact absurd $h:ident $hc:ident)
      return true
    if notOf t' == some t then
      tac `(tactic| exact absurd $hc:ident $h:ident)
      return true
  return false

/-- One step on the main goal. -/
def step (cost? : Option Ident) (i : Nat) : TacticM Unit := do
  timing m!"begin"
  -- A run already at a call with its arguments evaluated is left as it is:
  -- `qsimp` normalized the rest before, and on a big body it costs a pass
  -- over all of it at every step.
  let ready ← do
    let some t ← hypType? `h | pure false
    let some (_, lhs, _) := t.eq? | pure false
    let e := (← instantiateMVars lhs).consumeMData.headBeta
    if e.isAppOfArity ``qthen 4 then
      let o := e.appFn!.appArg!.consumeMData.headBeta
      pure (o.isAppOfArity ``qcall 6 && (qblocking o).isEmpty)
    else pure false
  timing m!"ready"
  unless ready do
    let t0 ← IO.monoMsNow
    let _ ← tryT `(tactic| qsimp at $(mkIdent `h):ident)
    let t1 ← IO.monoMsNow
    if (← getGoals).isEmpty then return
    let _ ← tryT `(tactic| qsimp)
    timing m!"qsimp {t1 - t0} ms at h, {(← IO.monoMsNow) - t1} ms on the goal"
    if (← getGoals).isEmpty then return
  if ← eagerCases i then
    let goals ← getGoals
    let mut out := #[]
    for g in goals do
      setGoals [g]
      let hx := mkIdent (Name.mkSimple s!"hx{i}")
      if (← hyp? hx.getId).isSome then
        mergeCases
      if (← getGoals).isEmpty then continue
      if (← hyp? hx.getId).isSome then
        let _ ← tryT `(tactic| simp only [$hx:ident, budget_cond] at $(mkIdent `pre):ident)
      else
        let _ ← tryT `(tactic| simp only [budget_cond] at $(mkIdent `pre):ident)
      out := out ++ (← getGoals)
    setGoals out.toList
    return
  let run ← runOf
  trace m!"step {i} [{(← getMainGoal).name}] pre {← hypType? `pre}: {run}"
  let h := mkIdent `h
  let hb := mkIdent `hb
  let pre := mkIdent `pre
  let w ← waitOf run
  timing m!"step {i} {match w with | .done => "done" | .fail => "fail" | .call _ => "call" | .addC => "addC" | .split _ => "split" | .stuck _ => "stuck"}"
  match w with
  | .done =>
    trace m!"done {← getMainGoal}"
    unless ← tryT `(tactic| obtain ⟨rfl, rfl⟩ := Prod.mk.inj (Option.some.inj $h)) do
      unless ← tryT `(tactic| obtain ⟨rfl, rfl⟩ := Prod.mk.inj $h) do
        tac `(tactic| obtain ⟨rfl, rfl⟩ := $h:ident)
    let _ ← tryT `(tactic| refine ⟨rfl, ?_⟩)
    if (← getGoals).isEmpty then return
    closeCost cost?
  | .fail =>
    tac `(tactic| cases $h:ident)
  | .addC =>
    trace m!"addC"
    let k := mkIdent (Name.mkSimple s!"k{i}")
    let hx := mkIdent (Name.mkSimple s!"hrun{i}")
    let c ← toStx run.consumeMData.appFn!.appArg!
    let b? ← budgetOf?
    tac `(tactic| obtain ⟨$k, $hx, rfl⟩ := addC_peel $h)
    tac `(tactic| refine addC_step ?_)
    tac `(tactic| replace $h:ident := $hx:ident)
    let _ ← tryT `(tactic| clear $hx:ident)
    if let some b := b? then
      let bS ← toStx b
      match run.consumeMData.appFn!.appArg!.nat? with
      | some m =>
        if m > 1 then
          -- `m` boxed calls in a row (`addC_addC`): the precondition takes them one by one
          let mut cur := bS
          for j in [0:m] do
            let _ ← tryT `(tactic| replace $pre:ident := $pre:ident ($cur - 1) (by omega) (by omega))
            let left := Syntax.mkNumLit (toString (m - j - 1))
            tac `(tactic| replace $hb:ident : $left + $k < $cur - 1 := by omega)
            newBudget cur (← `(1)) (1000 * i + j)
            cur ← `($(mkIdent (Name.mkSimple s!"bud{1000 * i + j}")):ident)
          tac `(tactic| replace $hb:ident : $k < $cur := by omega)
        else
          let _ ← tryT `(tactic| replace $pre:ident := $pre:ident ($bS - $c) (by omega) (by omega))
          tac `(tactic| replace $hb:ident : $k < $bS - $c := by omega)
          newBudget bS c i
      | none =>
        let _ ← tryT `(tactic| replace $pre:ident := $pre:ident ($bS - $c) (by omega) (by omega))
        tac `(tactic| replace $hb:ident : $k < $bS - $c := by omega)
        newBudget bS c i
  | .split cond =>
    trace m!"split {cond}"
    let hc := mkIdent (Name.mkSimple s!"hcond{i}")
    let cS ← toStx cond
    tac `(tactic| by_cases $hc:ident : $cS)
    let goals ← getGoals
    let mut out := #[]
    for g in goals do
      setGoals [g]
      -- a condition decided before (a call made twice): one case contradicts it
      if ← condContradicts hc then continue
      timing m!"split: contradiction"
      let _ ← tryT `(tactic| simp only [$hc:ident, budget_cond] at $h:ident)
      timing m!"split: h"
      -- the run tests `a == b` where the models say `a = b`
      let _ ← tryT `(tactic| simp only [budget_cond] at $hc:ident)
      -- a case the conditions before rule out (`p = A` then `p = B`, constants)
      let before := (← hypsNamed ["hcond"]).filter (·.getId != hc.getId)
      let lemmas : Array (TSyntax `Lean.Parser.Tactic.simpLemma) ← before.mapM fun h =>
        `(Lean.Parser.Tactic.simpLemma| $h:ident)
      let probe := mkIdent `hprobe
      if ← tryT `(tactic| (have $probe:ident := $hc:ident; simp (config := { decide := true }) only [$lemmas,*, budget_cond] at $probe:ident; done)) then
        continue
      timing m!"split: probe"
      let _ ← tryT `(tactic| simp only [$hc:ident, budget_cond, pure_rule] at $pre:ident)
      timing m!"split: pre"
      let _ ← tryT `(tactic| simp only [$hc:ident, budget_cond])
      timing m!"split: goal"
      let now ← getGoals
      for g' in now do
        setGoals [g']
        trace m!"split into [{g'.name}] pre {← hypType? `pre}"
      out := out ++ now
    setGoals out.toList
  | .stuck e =>
    match ← stuckRep? e with
    | some r =>
      trace m!"cases {← (← getMainGoal).withContext r.getUserName}"
      casesRep r i
      let goals ← getGoals
      let mut out := #[]
      for g in goals do
        setGoals [g]
        let hx := mkIdent (Name.mkSimple s!"hx{i}")
        if (← hyp? hx.getId).isSome then
          mergeCases
        if (← getGoals).isEmpty then continue
        if (← hyp? hx.getId).isSome then
          let _ ← tryT `(tactic| simp only [$hx:ident, budget_cond] at $pre:ident)
        else
          let _ ← tryT `(tactic| simp only [budget_cond] at $pre:ident)
        out := out ++ (← getGoals)
      setGoals out.toList
    | none => throwError "budget: the run waits on{indentExpr e}"
  | .call call =>
    let args := call.getAppArgs
    let fuel := args[3]!
    let callee := args[4]!
    let some key ← calleeKey? callee | throwError "budget: a call of{indentExpr callee}"
    if (← hyp? (Name.mkSimple s!"pp_{key}")).isSome then
      trace m!"prim {key}"
      let pp := mkIdent (Name.mkSimple s!"pp_{key}")
      let bx := mkIdent (Name.mkSimple s!"bx_{key}")
      let isSucc := (fuel.consumeMData.isAppOfArity ``HAdd.hAdd 6) || fuel.consumeMData.isAppOfArity ``Nat.succ 1
      if !isSucc then
        let some v := fuelVar? fuel | throwError "budget: the fuel{indentExpr fuel}"
        let goal ← getMainGoal
        let name ← goal.withContext do v.getUserName
        let n := mkIdent name
        tac `(tactic| rcases $n:ident with _ | $n:ident)
        -- the first case: no fuel left, the run is `none`
        let goals ← getGoals
        match goals with
        | [g0, g1] =>
          setGoals [g0]
          tac `(tactic| qsimp at $h:ident)
          unless (← getGoals).isEmpty do throwError "budget: a run at no fuel"
          setGoals [g1]
        | _ => throwError "budget: rcases"
      tac `(tactic| rw [qcall_prim $pp:ident] at $h:ident)
      tac `(tactic| rw [qcall_prim $pp:ident])
      let _ ← tryT `(tactic| simp only [$bx:ident, uc, ite_true, ite_false, if_true, if_false, Bool.false_eq_true]
        at $h:ident ⊢)
      return
    let some info ← certInfo? key | throwError "budget: no certificate for {key}"
    trace m!"call {key}: pre {← hypType? `pre}"
    let nargs := match args[5]!.listLit? with
      | some (_, vs) => vs.length
      | none => 0
    let hasPre := info.premises > nargs + 1
    let r := mkIdent (Name.mkSimple s!"r{i}")
    let c1 := mkIdent (Name.mkSimple s!"c{i}")
    let c2 := mkIdent (Name.mkSimple s!"d{i}")
    let hc := mkIdent (Name.mkSimple s!"hc{i}")
    let he := mkIdent (Name.mkSimple s!"he{i}")
    let hq := mkIdent (Name.mkSimple s!"hq{i}")
    let hcost := mkIdent (Name.mkSimple s!"hcost{i}")
    let hrep := mkIdent (Name.mkSimple s!"hrep{i}")
    let b? ← budgetOf?
    tac `(tactic| obtain ⟨$r, $c1, $c2, $hc, $he, rfl⟩ := qthen_peel $h)
    timing m!"call: peel"
    let cert : Term ← if info.certified then `($(mkIdent info.name).out) else `($(mkIdent info.name):ident)
    let conds : Array (TSyntax `Lean.Parser.Tactic.simpLemma) ← (← hypsNamed ["hcond"]).mapM fun h =>
      `(Lean.Parser.Tactic.simpLemma| $h:ident)
    let mut more : Array Term := #[]
    for _ in [0:nargs] do
      -- an argument the run has as `e` where the precondition, simplified by a
      -- condition `e = true` taken before, has `true`
      more := more.push (← if conds.isEmpty then `(by rep) else `(by first | rep | (simp only [$conds,*]; rep)))
    let mut whole := false
    if hasPre then
      -- a precondition that tests constants the run has evaluated (production
      -- numbers): decided
      if let some pt ← hypType? `pre then
        if pt.consumeMData.isAppOfArity ``ite 5 then
          let _ ← tryT `(tactic| simp (config := { decide := true }) only [budget_cond, closedNatEq, closedNatLt] at $pre:ident)
      let some pt ← hypType? `pre | throwError "budget: no precondition for {key}"
      whole := !pt.consumeMData.isAppOfArity ``And 2
      more := more.push (← `(by omega))
      more := more.push (← if whole then `($pre:ident) else `(($pre).1))
    let app ← `($cert $hc:ident $more*)
    timing m!"call: pre"
    tac `(tactic| have $hq:ident := $app)
    timing m!"call: have"
    tac `(tactic| obtain ⟨$hq, $hcost, $hrep⟩ := $hq:ident)
    if hasPre then
      if whole then
        -- kept: `and_self` may have made two calls' preconditions this one
        pure ()
      else
        tac `(tactic| replace $pre:ident := ($pre).2)
    if info.free then
      tac `(tactic| subst $hcost:ident)
      if let some b := b? then
        let bS ← toStx b
        tac `(tactic| replace $hb:ident : $c2 < $bS := by omega)
    else
      if let some b := b? then
        let bS ← toStx b
        -- the precondition's cost of the call, as it writes it (a struct taken
        -- apart, say), is the callee's by definition: name it so for `omega`
        let hpc := mkIdent `hpc
        if let some C ← preCost? then
          let cS ← toStx C
          let _ ← tryT `(tactic| have $hpc:ident : $cS = $c1 := $hcost:ident)
        let _ ← tryT `(tactic| replace $pre:ident := $pre:ident ($bS - $c1) (by omega) (by omega))
        let _ ← tryT `(tactic| clear $hpc:ident)
        tac `(tactic| replace $hb:ident : $c2 < $bS - $c1 := by omega)
        newBudget bS c1 i
    timing m!"call: budget"
    tac `(tactic| refine run_step $hq ?_)
    tac `(tactic| replace $h:ident := $he:ident)
    -- the runs of the call are used: every later step would carry them
    let _ ← tryT `(tactic| clear $he:ident $hq:ident $hc:ident)
    timing m!"call: end"

/-- Prove the main goal by `k` on a fresh goal and assign its proof with its
metavariables instantiated. A case's proof is then instantiated on its own:
instantiating the metavariables of a whole certificate at once took 17 s of
`let_first`'s 70 s (11-02). (An auxiliary theorem per case did as well, but
its kernel checks cost more than the one check of the whole.) -/
def instantiateCase (k : TacticM Unit) : TacticM Unit := do
  let g ← getMainGoal
  let type ← instantiateMVars (← g.getType)
  if type.hasMVar then
    k
    return
  let g' ← g.withContext do mkFreshExprSyntheticOpaqueMVar type
  setGoals [g'.mvarId!]
  k
  unless (← getGoals).isEmpty do throwError "budget: a branch left goals"
  g.withContext do
    let pf ← instantiateMVars g'
    timing m!"aux inst"
    g.assign pf
  setGoals []

/-- `budget` on the main goal, until it is closed: depth first, each case of a
split instantiated on its own (`instantiateCase`). `ctr` numbers the steps, which
name their hypotheses. -/
partial def budgetLoop (cost? : Option Ident) (ctr : IO.Ref Nat) (fuel : Nat) : TacticM Unit := do
  if fuel = 0 then throwError "budget: out of steps"
  let i ← ctr.modifyGet fun n => (n, n + 1)
  step cost? i
  let goals ← (← getGoals).filterM fun g => return !(← g.isAssigned)
  match goals with
  | [] => setGoals []
  | [g] =>
    setGoals [g]
    budgetLoop cost? ctr (fuel - 1)
  | g :: gs =>
    for g in g :: gs do
      setGoals [g]
      instantiateCase (budgetLoop cost? ctr (fuel - 1))
    setGoals []

syntax "budget" (ppSpace colGt ident)? : tactic

elab_rules : tactic
  | `(tactic| budget $[$c]?) => do
    let ctr ← IO.mkRef 0
    let h0 ← IO.getNumHeartbeats
    budgetLoop c ctr 2000
    timing m!"budget: {((← IO.getNumHeartbeats) - h0) / 1000} kheartbeats"

end Lanius.Faithful.Budget
