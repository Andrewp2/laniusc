import Lanius.Faithful.Budget
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

/-- Run the cost semantics of a body as far as its calls, `qthen` folded. -/
syntax "qsimp" (" at " ident)? : tactic
macro_rules
  | `(tactic| qsimp at $h:ident) => `(tactic|
    simp (maxSteps := 10000000) only [budget_rule, pure_rule, reduceCtorEq, qstmt, qeff, qeffs, qapplyOp, qbinary, pexpr, pexprs, paramEnv,
      paramBindings, applyOp, binary, unary, Lanius.Faithful.cast, SrcOp.toCore, SrcDivOp.toCore, UintTy.toCore,
      SrcType.toScalar, Nat.reduceLT, Nat.reduceEqDiff, Nat.reduceAdd, Nat.reduceSub, Nat.reduceMul, Nat.reduceMod,
      Nat.reducePow, Nat.reduceBEq, Nat.reduceBNe, Nat.zero_add, Nat.add_zero, BitVec.reduceToNat, BitVec.reduceOfInt,
      BitVec.reduceToInt, Except.toOption, ↓reduceIte] at $h:ident)
  | `(tactic| qsimp) => `(tactic|
    simp (maxSteps := 10000000) only [budget_rule, pure_rule, reduceCtorEq, qstmt, qeff, qeffs, qapplyOp, qbinary, pexpr, pexprs, paramEnv,
      paramBindings, applyOp, binary, unary, Lanius.Faithful.cast, SrcOp.toCore, SrcDivOp.toCore, UintTy.toCore,
      SrcType.toScalar, Nat.reduceLT, Nat.reduceEqDiff, Nat.reduceAdd, Nat.reduceSub, Nat.reduceMul, Nat.reduceMod,
      Nat.reducePow, Nat.reduceBEq, Nat.reduceBNe, Nat.zero_add, Nat.add_zero, BitVec.reduceToNat, BitVec.reduceOfInt,
      BitVec.reduceToInt, Except.toOption, ↓reduceIte])

end

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

def trace (m : MessageData) : TacticM Unit := do
  if budget.trace.get (← getOptions) then logInfo m

/-- Close the cost: `COST = c` with the callees' costs, the cases' conditions
and the generalized results. -/
def closeCost (cost? : Option Ident) : TacticM Unit := do
  let hs ← hypsNamed ["hcost", "hcond", "hx"]
  let lemmas : Array (TSyntax `Lean.Parser.Tactic.simpLemma) ← hs.mapM fun h => `(Lean.Parser.Tactic.simpLemma| $h:ident)
  trace m!"close {← getMainGoal}"
  match cost? with
  | none => tac `(tactic| omega)
  | some c =>
    let eqDef := mkIdent (c.getId ++ `eq_def)
    tac `(tactic| rw [$eqDef:ident])
    let _ ← tryT `(tactic| simp (config := { decide := true }) only [$lemmas,*, budget_cond, pure_rule])
    if (← getGoals).isEmpty then return
    if ← tryT `(tactic| omega) then return
    -- a cost that still branches on a condition the hypotheses decide
    tac `(tactic| (repeat' split) <;> omega)

/-- One step on the main goal. -/
def step (cost? : Option Ident) (i : Nat) : TacticM Unit := do
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
  unless ready do
    let _ ← tryT `(tactic| qsimp at $(mkIdent `h):ident)
    if (← getGoals).isEmpty then return
    let _ ← tryT `(tactic| qsimp)
    if (← getGoals).isEmpty then return
  if ← eagerCases i then
    let goals ← getGoals
    let mut out := #[]
    for g in goals do
      setGoals [g]
      let hx := mkIdent (Name.mkSimple s!"hx{i}")
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
  match ← waitOf run with
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
      let _ ← tryT `(tactic| replace $pre:ident := $pre:ident ($bS - $c) (by omega) (by omega))
      tac `(tactic| replace $hb:ident : $k < $bS - $c := by omega)
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
      if ← tryT `(tactic| contradiction) then continue
      let _ ← tryT `(tactic| simp only [$hc:ident, budget_cond] at $h:ident)
      -- the run tests `a == b` where the models say `a = b`
      let _ ← tryT `(tactic| simp only [budget_cond] at $hc:ident)
      -- a case the conditions before rule out (`p = A` then `p = B`, constants)
      let before := (← hypsNamed ["hcond"]).filter (·.getId != hc.getId)
      let lemmas : Array (TSyntax `Lean.Parser.Tactic.simpLemma) ← before.mapM fun h =>
        `(Lean.Parser.Tactic.simpLemma| $h:ident)
      let probe := mkIdent `hprobe
      if ← tryT `(tactic| (have $probe:ident := $hc:ident; simp (config := { decide := true }) only [$lemmas,*, budget_cond] at $probe:ident; done)) then
        continue
      let _ ← tryT `(tactic| simp only [$hc:ident, budget_cond, pure_rule] at $pre:ident)
      let _ ← tryT `(tactic| simp only [$hc:ident, budget_cond])
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
    let cert : Term ← if info.certified then `($(mkIdent info.name).out) else `($(mkIdent info.name):ident)
    let mut more : Array Term := #[]
    for _ in [0:nargs] do
      more := more.push (← `(by rep))
    let mut whole := false
    if hasPre then
      let some pt ← hypType? `pre | throwError "budget: no precondition for {key}"
      whole := !pt.consumeMData.isAppOfArity ``And 2
      more := more.push (← `(by omega))
      more := more.push (← if whole then `($pre:ident) else `(($pre).1))
    let app ← `($cert $hc:ident $more*)
    tac `(tactic| have $hq:ident := $app)
    tac `(tactic| obtain ⟨$hq, $hcost, $hrep⟩ := $hq:ident)
    if hasPre then
      if whole then
        let _ ← tryT `(tactic| clear $pre:ident)
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
        let _ ← tryT `(tactic| replace $pre:ident := $pre:ident ($bS - $c1) (by omega) (by omega))
        tac `(tactic| replace $hb:ident : $c2 < $bS - $c1 := by omega)
    tac `(tactic| refine run_step $hq ?_)
    tac `(tactic| replace $h:ident := $he:ident)
    let _ ← tryT `(tactic| clear $he:ident)

/-- `budget` on every goal, until each is closed. -/
partial def budgetLoop (cost? : Option Ident) (i fuel : Nat) : TacticM Unit := do
  if fuel = 0 then throwError "budget: out of steps"
  let goals ← getGoals
  if goals.isEmpty then return
  let mut left := #[]
  let mut k := i
  for g in goals do
    if ← g.isAssigned then continue
    setGoals [g]
    step cost? k
    k := k + 1
    left := left ++ (← getGoals)
  setGoals left.toList
  budgetLoop cost? (k + 1) (fuel - 1)

syntax "budget" (ppSpace colGt ident)? : tactic

elab_rules : tactic
  | `(tactic| budget $[$c]?) => budgetLoop c 0 2000

end Lanius.Faithful.Budget
