module

public import Lanius.Faithful.Scalar
public meta import Lean

public meta section

/-! # `faithful`: a certificate's proof

After the call is unfolded, `h` says the body's pure meaning returned `w`,
and the goal is that `w` represents the extracted Lean function at the
arguments. `faithful [F, ..]` repeats, until nothing changes:

* take apart each representation whose shape is known (one constructor, or
  a constructor on either side), which names the values' parts;
* run the pure meaning as far as it goes (`pure_simp` everywhere);
* apply the callees' certificates (`certs`), which say what the calls
  returned.

Then it closes the goal by unfolding `F, ..` and `rep`, or, if the body
still waits on a value, splits on it: the representation of a value that is
matched on, or an `if` condition, and goes on in each case. -/

namespace Lanius.Faithful

open Lean Elab Tactic Meta

/-- `Rep.. x v`: the relation, the Lean value and the pure value. -/
def repOf? (t : Expr) : MetaM (Option (Name × Expr × Expr)) := do
  let t := (← instantiateMVars t).cleanupAnnotations
  let .const n _ := t.getAppFn | return none
  let .str _ last := n | return none
  unless last.startsWith "Rep" do return none
  let some (.inductInfo _) := (← getEnv).find? n | return none
  let args := t.getAppArgs
  if args.size < 2 then return none
  return some (n, args[args.size - 2]!, args[args.size - 1]!)

def isCtorApp (e : Expr) : MetaM Bool := do
  let e ← instantiateMVars e
  match e.getAppFn with
  | .const n _ => return (← getEnv).isConstructor n || e.isRawNatLit
  | .lit _ => return true
  | _ => return false

/-- Take apart the representations whose shape is known. -/
partial def casesKnown : TacticM Bool := do
  let goal ← getMainGoal
  let found ← goal.withContext do
    -- The values a hypothesis being evaluated mentions: only those need their
    -- shape. (A list built of calls, a grammar table, has a representation per
    -- element; splitting them all only to rebuild them in the goal is
    -- quadratic in the context.)
    let mut used : Std.HashSet FVarId := {}
    for d in ← getLCtx do
      if d.isImplementationDetail then continue
      if (← repOf? d.type).isSome then continue
      if (← callOf? d.type).isSome then continue
      let t ← instantiateMVars d.type
      unless ← isProp t do continue
      for f in (collectFVars {} t).fvarIds do used := used.insert f
    -- And the goal's: a number or a structure there (one constructor) is
    -- compared with what the goal computes.
    let target ← instantiateMVars (← goal.getType)
    for d in ← getLCtx do
      if d.isImplementationDetail then continue
      let some (n, x, v) ← repOf? d.type | continue
      let some (.inductInfo info) := (← getEnv).find? n | continue
      if v.isFVar && !used.contains v.fvarId! &&
          !(info.ctors.length == 1 && target.containsFVar v.fvarId!) then continue
      if info.ctors.length == 1 || (← isCtorApp v) || (← isCtorApp x) then return some d.fvarId
    return none
  match found with
  | none => return false
  | some f =>
    let saved ← saveState
    try
      let subgoals ← goal.cases f
      replaceMainGoal (subgoals.map (·.mvarId)).toList
      return true
    catch _ =>
      saved.restore
      return false

/-- A fingerprint of the main goal, to see whether a round changed it: the
hashes of its hypotheses and target (pretty-printing it costs more than a
round in a big context). -/
def goalText : TacticM UInt64 := do
  let goal ← getMainGoal
  goal.withContext do
    let mut h : UInt64 := (← instantiateMVars (← goal.getType)).hash
    for d in ← getLCtx do
      unless d.isImplementationDetail do h := mixHash h (← instantiateMVars d.type).hash
    return h

def tryTac (tac : TacticM Unit) : TacticM Bool := do
  let saved ← saveState
  tryCatchRuntimeEx (do tac; return true) fun _ => do
    saved.restore
    return false

/-- Whether a tactic closes the main goal; if not, nothing happened. -/
register_option faithful.trace : Bool := { defValue := false, descr := "show why closing steps fail" }
register_option faithful.profile : Bool := { defValue := false, descr := "time faithful's phases" }

initialize phaseTimes : IO.Ref (Std.HashMap String Nat) ← IO.mkRef {}

/-- Time `x` under `name` when `faithful.profile` is set. -/
def phase {α : Type} (name : String) (x : TacticM α) : TacticM α := do
  unless faithful.profile.get (← getOptions) do return ← x
  let t0 ← IO.monoNanosNow
  try x finally
    let t1 ← IO.monoNanosNow
    if t1 - t0 > 1000000 then IO.eprintln s!"faithful phase {name}: {(t1 - t0) / 1000000} ms"

register_option faithful.depth : Nat := { defValue := 100, descr := "nested splits before giving up" }
register_option faithful.rounds : Nat := { defValue := 40, descr := "rounds before closing" }
register_option faithful.admitClose : Bool := { defValue := false, descr := "admit instead of closing (to time the rounds)" }

register_option faithful.closeBudget : Nat := {
  defValue := 60000, descr := "heartbeats (in thousands) for one closing step" }

/-- Run `x` with its own heartbeat budget: a closing step that fails costs
at most that much. -/
def withBudget {α : Type} (x : TacticM α) : TacticM α := do
  let budget := faithful.closeBudget.get (← getOptions)
  withTheReader Core.Context (fun ctx => { ctx with maxHeartbeats := budget * 1000 }) (withCurrHeartbeats x)

def closes (tac : TSyntax `tactic) : TacticM Bool := phase s!"close {tac.raw.getKind}" do
  let saved ← saveState
  tryCatchRuntimeEx (withBudget do
    evalTactic (← `(tactic| ($tac; done)))
    if faithful.trace.get (← getOptions) then logInfo m!"closed by {tac}"
    if faithful.profile.get (← getOptions) then
      IO.eprintln s!"faithful closed {(toString tac.raw.prettyPrint).take 60 |>.replace "\n" " "}"
    return true) fun e => do
    let traces := (← getTraceState).traces
    saved.restore
    if faithful.trace.get (← getOptions) then
      logInfo m!"{tac}: {e.toMessageData}"
      for t in traces do logInfo t.msg
    return false

/-- The `Inline.f` the goal mentions: an inlined call the pure side ran,
whose body the extracted Lean function has in its place. -/
def inlineConsts : TacticM (Array Name) := do
  let goal ← getMainGoal
  goal.withContext do
    let mut out : Std.HashSet Name := {}
    let mut types := #[← instantiateMVars (← goal.getType)]
    for d in ← getLCtx do
      unless d.isImplementationDetail do types := types.push (← instantiateMVars d.type)
    for t in types do
      for c in t.getUsedConstants do
        if (`Lanius.Mini.Inline).isPrefixOf c then out := out.insert c
    return out.toArray

/-- The program's functions applied to a constructor in `e`: their
equations for that constructor make progress. -/
partial def ctorCalls (env : Environment) (e : Expr) (acc : Std.HashSet Name) : Std.HashSet Name :=
  match e with
  | .app .. =>
    let f := e.getAppFn
    let args := e.getAppArgs
    let acc := args.foldl (fun acc a => ctorCalls env a acc) (ctorCalls env f acc)
    match f with
    | .const n _ =>
      let isCtor (a : Expr) := match a.getAppFn with
        | .const c _ => env.isConstructor c
        | _ => false
      if (`Lanius.Mini).isPrefixOf n && !(`Lanius.Mini.Inline).isPrefixOf n && !env.isConstructor n &&
          args.any isCtor then acc.insert n else acc
    | _ => acc
  | .lam _ t b _ | .forallE _ t b _ => ctorCalls env b (ctorCalls env t acc)
  | .letE _ t v b _ => ctorCalls env b (ctorCalls env v (ctorCalls env t acc))
  | .mdata _ b | .proj _ _ b => ctorCalls env b acc
  | _ => acc

def ctorCallees : TacticM (Array Name) := do
  let goal ← getMainGoal
  goal.withContext do
    let env ← getEnv
    let mut acc := ctorCalls env (← instantiateMVars (← goal.getType)) {}
    for d in ← getLCtx do
      unless d.isImplementationDetail do acc := ctorCalls env (← instantiateMVars d.type) acc
    return acc.toArray

/-- Unfold them in the conditions (hypotheses `b = true`, not the
representations): an inlined call's result the pure side tested, which the
Lean function has as the call's body. Unfolding them in the representations
too would split the callers on every match of every inlined body. -/
def unfoldInlineConds : TacticM Bool := do
  let names ← inlineConsts
  if names.isEmpty then return false
  let goal ← getMainGoal
  let conds ← goal.withContext do
    let mut out := #[]
    for d in ← getLCtx do
      if d.isImplementationDetail then continue
      if (← repOf? d.type).isSome then continue
      let t ← instantiateMVars d.type
      if (← isProp t) && t.getUsedConstants.any (fun c => (`Lanius.Mini.Inline).isPrefixOf c) then
        out := out.push d.fvarId
    return out
  if conds.isEmpty then return false
  let stx ← `(tactic| simp only [$(← names.mapM fun n => `(Lean.Parser.Tactic.simpLemma| $(mkIdent n):ident)),*])
  goal.withContext do
    let { ctx, simprocs, .. } ← mkSimpContext stx (eraseLocal := false)
    let (result, _) ← simpGoal goal ctx simprocs (fvarIdsToSimp := conds) (simplifyTarget := false)
    match result with
    | none => replaceMainGoal []
    | some (_, g) => replaceMainGoal [g]
  return true

/-- Close the goal from a hypothesis `False` (a panic's certificate) or
`none = some _`. `contradiction` would also compare every pair of
hypotheses, which in a big context costs more than the rest of a round. -/
def falseHyp : TacticM Bool := do
  let goal ← getMainGoal
  goal.withContext do
    for d in ← getLCtx do
      if d.isImplementationDetail then continue
      let t ← instantiateMVars d.type
      if t.isConstOf ``False then
        goal.assign (← mkFalseElim (← goal.getType) d.toExpr)
        replaceMainGoal []
        return true
      if let some (_, a, b) := t.eq? then
        if a.isAppOf ``Option.none && b.isAppOf ``Option.some then
          let saved ← saveState
          try
            let gs ← goal.cases d.fvarId
            if gs.isEmpty then
              replaceMainGoal []
              return true
            saved.restore
          catch _ => saved.restore
    return false

/-- A number a closed term evaluates to: an inline constant (a token or
production kind) or a literal. -/
def closedNat? (e : Expr) : MetaM (Option Nat) := do
  if e.hasFVar || e.hasMVar then return none
  unless (← instantiateMVars (← inferType e)).isConstOf ``Nat do return none
  let e ← whnfD e
  return e.rawNatLit? <|> e.nat?

/-- `t = a` (or `a = t`) with `a` closed: `t`, `a`'s number, and a proof of `t = a`. -/
def pinned? (d : LocalDecl) : MetaM (Option (Expr × Nat × Expr)) := do
  let some (_, l, r) := (← instantiateMVars d.type).eq? | return none
  if let some k ← closedNat? r then
    unless l.hasFVar do return none
    return some (l, k, d.toExpr)
  if let some k ← closedNat? l then
    unless r.hasFVar do return none
    return some (r, k, ← mkEqSymm d.toExpr)
  return none

/-- Close a branch whose tests contradict each other: `t = a` and `t = b`
for different numbers, or `t = a` and `¬t = b` for the same one (one kind
tested against another after a split). -/
def pinnedClash : TacticM Bool := do
  let goal ← getMainGoal
  goal.withContext do
    let mut pins : Array (Expr × Nat × Expr) := #[]
    for d in ← getLCtx do
      if d.isImplementationDetail then continue
      if let some p ← pinned? d then pins := pins.push p
    if pins.isEmpty then return false
    let target ← goal.getType
    for d in ← getLCtx do
      if d.isImplementationDetail then continue
      let t ← instantiateMVars d.type
      -- `t = b` against `t = a`.
      if let some (t', b, hb) ← pinned? d then
        for (t, a, ha) in pins do
          if a != b && t == t' then
            -- a = b from the two, against `decide`.
            let hab ← mkEqTrans (← mkEqSymm ha) hb
            let aT := (← inferType' ha).appArg!
            let bT := (← inferType' hb).appArg!
            let ne ← mkDecideProof (mkNot (← mkEq aT bT))
            goal.assign (← mkAbsurd target hab ne)
            replaceMainGoal []
            return true
      -- `¬t = b` against `t = a`, `a` and `b` the same number.
      if t.isAppOfArity ``Not 1 then
        let inner := t.appArg!
        let some (_, l, r) := inner.eq? | continue
        for (t, a, ha) in pins do
          let lhsCase ← do
            if l == t then pure (some (r, false)) else if r == t then pure (some (l, true)) else pure none
          let some (b, flipped) := lhsCase | continue
          let some k ← closedNat? b | continue
          if k != a then continue
          let aTerm := (← inferType' ha).appArg!
          let hab ← mkDecideProof (← mkEq aTerm b)
          let htb ← mkEqTrans ha hab
          let hyp ← if flipped then mkEqSymm htb else pure htb
          goal.assign (← mkAbsurd target hyp d.toExpr)
          replaceMainGoal []
          return true
    -- A test `P t` that is false of the number `t` is pinned to (`isLevel`
    -- of a production known to be another one).
    for d in ← getLCtx do
      if d.isImplementationDetail then continue
      let t ← instantiateMVars d.type
      unless ← isProp t do continue
      if (← repOf? t).isSome || (← callOf? t).isSome then continue
      for (pt, _, ha) in pins do
        if t == (← inferType' ha) then continue
        let abst ← kabstract t pt
        unless abst.hasLooseBVars do continue
        let aTerm := (← inferType' ha).appArg!
        let pa := abst.instantiate1 aTerm
        if pa.hasFVar || pa.hasMVar then continue
        let saved ← saveState
        try
          let dec ← mkDecide pa
          let r ← withTransparency .default (whnf dec)
          unless r.isConstOf ``false do
            saved.restore
            continue
          let motive ← mkLambdaFVars #[] (.lam `x (← inferType pt) abst .default)
          let hpa ← mkEqNDRec motive d.toExpr ha
          let inst ← synthInstance (mkApp (mkConst ``Decidable) pa)
          let nota := mkApp3 (mkConst ``of_decide_eq_false) pa inst (← mkEqRefl (mkConst ``false))
          goal.assign (← mkAbsurd target hpa nota)
          replaceMainGoal []
          return true
        catch _ => saved.restore
    return false
where
  inferType' (h : Expr) : MetaM Expr := do return (← instantiateMVars (← inferType h))

/-- The applications of matchers in `e`, outermost first. -/
partial def matcherApps (env : Environment) (e : Expr) (acc : Array Expr) : Array Expr :=
  match e with
  | .app .. =>
    let acc := match e.getAppFn with
      | .const n _ => if Lean.Meta.isMatcherCore env n then acc.push e else acc
      | _ => acc
    e.getAppArgs.foldl (fun acc a => matcherApps env a acc) acc
  | .lam _ t b _ | .forallE _ t b _ => matcherApps env b (matcherApps env t acc)
  | .letE _ t v b _ => matcherApps env b (matcherApps env v (matcherApps env t acc))
  | .mdata _ b | .proj _ _ b => matcherApps env b acc
  | _ => acc

/-- Put the calls `Inline.f ..` that hypotheses state back into the goal:
after the extracted function is unfolded, the goal has an inlined call's
body (a `match`, through the function's own matcher) where a hypothesis
names the call. Each matcher application of the goal that is defeq to the
left side of such a hypothesis is replaced by it, so `simp [*]` uses it. -/
def foldInline : TacticM Bool := do
  let goal ← getMainGoal
  goal.withContext do
    let env ← getEnv
    let mut calls := #[]
    for d in ← getLCtx do
      if d.isImplementationDetail then continue
      let t ← instantiateMVars d.type
      if let some (_, lhs, _) := t.eq? then
        if let .const c _ := lhs.getAppFn then
          if (`Lanius.Mini.Inline).isPrefixOf c then calls := calls.push lhs
    if calls.isEmpty then return false
    let target ← instantiateMVars (← goal.getType)
    let found := matcherApps env target #[]
    let mut target' := target
    let mut changed := false
    for m in found do
      for c in calls do
        if ← withTransparency .default (withNewMCtxDepth (isDefEq m c)) then
          target' := target'.replace fun e => if e == m then some c else none
          changed := true
          break
    unless changed do return false
    replaceMainGoal [← goal.replaceTargetDefEq target']
    return true

/-- Clear hypotheses that repeat an earlier one. -/
def dedupe : TacticM Unit := do
  let goal ← getMainGoal
  let dups ← goal.withContext do
    let mut seen : Std.HashSet Expr := {}
    let mut dups := #[]
    for d in ← getLCtx do
      if d.isImplementationDetail then continue
      let t ← instantiateMVars d.type
      unless (← isProp t) do continue
      if seen.contains t then dups := dups.push d.fvarId else seen := seen.insert t
    return dups
  let mut goal := goal
  for f in dups.reverse do goal ← goal.tryClear f
  replaceMainGoal [goal]

/-- Whether the goal's pure value is still being computed: a local `w` that
a hypothesis other than a representation mentions. Closing steps cannot
succeed before a split. -/
def pending : TacticM Bool := do
  let goal ← getMainGoal
  goal.withContext do
    let some (_, _, v) ← repOf? (← goal.getType) | return false
    unless v.isFVar do return false
    for d in ← getLCtx do
      if d.isImplementationDetail then continue
      if (← repOf? d.type).isSome then continue
      if (← instantiateMVars d.type).containsFVar v.fvarId! then return true
    return false

/-- `pure_simp` on the hypotheses still being evaluated (not the
representations, bounds and call results, which it would leave as they
are, at a cost in a big context). -/
def pureSimpEval : TacticM Unit := do
  let goal ← getMainGoal
  let fvars ← goal.withContext do
    let mut out := #[]
    for d in ← getLCtx do
      if d.isImplementationDetail then continue
      if (← repOf? d.type).isSome then continue
      if (← callOf? d.type).isSome then continue
      let t ← instantiateMVars d.type
      unless (← isProp t) do continue
      if t.isAppOfArity ``LT.lt 4 then continue
      out := out.push d.fvarId
    return out
  let stx ← `(tactic| simp (maxSteps := 2000000) only [pure_rule, reduceCtorEq, pstmt, peff, peffs, pexpr, pexprs, paramEnv, Lanius.Mini.paramBindings,
    applyOp, binary, unary, cast, Lanius.Mini.SrcOp.toCore, Lanius.Mini.SrcDivOp.toCore, Lanius.Mini.UintTy.toCore,
    Lanius.Mini.SrcType.toScalar, Nat.reduceLT, Nat.reduceEqDiff,
    Nat.reduceAdd, Nat.reduceSub, Nat.reduceMul, Nat.reduceMod, Nat.reducePow, Nat.reduceBEq, Nat.reduceBNe])
  goal.withContext do
    let { ctx, simprocs, .. } ← mkSimpContext stx (eraseLocal := false)
    let (result, _) ← simpGoal goal ctx simprocs (fvarIdsToSimp := fvars) (simplifyTarget := true)
    match result with
    | none => replaceMainGoal []
    | some (_, g) => replaceMainGoal [g]

/-- One round on the main goal. -/
def round (ns : Name) : TacticM Unit := do
  while ← phase "cases" casesKnown do
    if (← getGoals).isEmpty then return
  if (← getGoals).isEmpty then return
  phase "dedupe" dedupe
  let _ ← phase "simp" (tryTac pureSimpEval)
  if (← getGoals).isEmpty then return
  let _ ← phase "destruct" (tryTac (evalTactic (← `(tactic| destruct))))
  let _ ← phase "peel" (tryTac (peelCalls 10000))
  let _ ← phase "subst" (tryTac (evalTactic (← `(tactic| subst_vars))))
  if (← getGoals).isEmpty then return
  phase "certs" (certsLoop ns)
  if (← getGoals).isEmpty then return
  let _ ← phase "contradiction" falseHyp
  if (← getGoals).isEmpty then return
  let _ ← phase "clash" (tryTac (do unless ← pinnedClash do throwError "none"))

/-- The pure values a hypothesis waits on: the scrutinee of a match
(`parms`), a struct whose field is read, a condition, an operand. -/
def blockedOn (e : Expr) : Array Expr :=
  let args := e.getAppArgs
  match e.getAppFn with
  | .const n _ =>
    if n == ``parms && args.size ≥ 4 then #[args[2]!]
    else if n == ``fieldOf && args.size ≥ 1 then #[args[0]!]
    else if n == ``asBool && args.size ≥ 1 then #[args[0]!]
    else if n == ``Lanius.Semantics.evalBinaryValue && args.size ≥ 4 then #[args[2]!, args[3]!]
    else if (n == ``Lanius.Semantics.evalUnaryValue || n == ``Lanius.Semantics.evalScalarCast) && args.size ≥ 3 then
      #[args[2]!]
    else #[]
  | _ => #[]

partial def blocking (e : Expr) : Array Expr :=
  match e with
  | .app f a => blockedOn e ++ blocking f ++ blocking a
  | .lam _ t b _ | .forallE _ t b _ => blocking t ++ blocking b
  | .letE _ t v b _ => blocking t ++ blocking v ++ blocking b
  | .mdata _ b | .proj _ _ b => blocking b
  | _ => #[]

/-- A pure value the body is stuck on: a local `v` with a representation
that a hypothesis's evaluation waits on. -/
def stuckRep? : TacticM (Option FVarId) := do
  let goal ← getMainGoal
  goal.withContext do
    let lctx ← getLCtx
    let mut reps : Array (FVarId × Expr) := #[]
    for d in lctx do
      if d.isImplementationDetail then continue
      if let some (_, _, v) ← repOf? d.type then
        if v.isFVar then reps := reps.push (d.fvarId, v)
    for d in lctx do
      if d.isImplementationDetail then continue
      if (← repOf? d.type).isSome then continue
      if (← callOf? d.type).isSome then continue
      let t ← instantiateMVars d.type
      for b in blocking t do
        for (r, v) in reps do
          if b == v then return some r
    return none

/-- The condition of an `if` in `e` outside any binder, the outermost first. -/
partial def closedIte? (e : Expr) : Option Expr :=
  if e.isAppOfArity ``ite 5 && !e.appFn!.appFn!.appFn!.appArg!.hasLooseBVars then
    some e.appFn!.appFn!.appFn!.appArg!
  else match e with
    | .app f a => closedIte? f <|> closedIte? a
    | .lam _ t b _ | .forallE _ t b _ => closedIte? t <|> closedIte? b
    | .letE _ t v b _ => closedIte? t <|> closedIte? v <|> closedIte? b
    | .mdata _ b | .proj _ _ b => closedIte? b
    | _ => none

/-- Split on the condition of an `if` in a hypothesis being evaluated, with a
rewrite: `split at` simplifies the whole hypothesis in a bounded number of
steps, which a long body (a chain of `||` tests) runs out of. -/
def iteSplit : TacticM Bool := do
  let goal ← getMainGoal
  let found ← goal.withContext do
    for d in ← getLCtx do
      if d.isImplementationDetail then continue
      if (← repOf? d.type).isSome then continue
      if (← callOf? d.type).isSome then continue
      unless ← isProp d.type do continue
      if let some c := closedIte? (← instantiateMVars d.type) then return some (d.userName, c)
    return none
  let some (h, c) := found | return false
  tryTac do
    let g ← getMainGoal
    let h ← g.withContext do
      let some d := (← getLCtx).findFromUserName? h | throwError "lost"
      pure d.fvarId
    let g ← g.rename h `hsplit
    replaceMainGoal [g]
    let cStx ← g.withContext (Term.exprToSyntax c)
    let hs := mkIdent `hsplit
    let hc := mkIdent `hc
    evalTactic (← `(tactic| by_cases $hc : $cStx))
    let [pos, neg] ← getGoals | throwError "by_cases"
    setGoals [pos]
    evalTactic (← `(tactic| rw [if_pos $hc:ident] at $hs:ident))
    let pos ← getGoals
    setGoals [neg]
    evalTactic (← `(tactic| rw [if_neg $hc:ident] at $hs:ident))
    setGoals (pos ++ (← getGoals))

/-- Split the main goal on what its body waits on. -/
def split : TacticM Bool := do
  if let some r ← stuckRep? then
    let goal ← getMainGoal
    let ok ← goal.withContext do
      let some (_, x, _) ← repOf? (← r.getType) | return false
      if x.isFVar then
        let subgoals ← goal.cases r
        replaceMainGoal (subgoals.map (·.mvarId)).toList
        return true
      -- A call's result: name the Lean value first.
      let saved ← saveState
      let rName := `hrep
      try
        replaceMainGoal [← goal.rename r rName]
        evalTactic (← `(tactic| generalize hx : $(← Term.exprToSyntax x) = y at $(mkIdent rName):ident))
        let goal ← getMainGoal
        let some d := (← goal.withContext getLCtx).findFromUserName? rName | throwError "lost"
        let subgoals ← goal.cases d.fvarId
        replaceMainGoal (subgoals.map (·.mvarId)).toList
        return true
      catch _ =>
        saved.restore
        return false
    if ok then return true
  if ← iteSplit then return true
  if ← tryTac (evalTactic (← `(tactic| split at *))) then return true
  -- An `if` or `match` in a hypothesis being evaluated, or in the goal.
  let goal ← getMainGoal
  let hyps ← goal.withContext do
    let mut out := #[]
    for d in ← getLCtx do
      if d.isImplementationDetail then continue
      if (← repOf? d.type).isSome then continue
      if (← callOf? d.type).isSome then continue
      if ← isProp d.type then out := out.push d.fvarId
    return out
  for h in hyps do
    let saved ← saveState
    try
      let g ← (← getMainGoal).rename h `hsplit
      replaceMainGoal [g]
      evalTactic (← `(tactic| split at $(mkIdent `hsplit):ident))
      return true
    catch _ => saved.restore
  tryTac (evalTactic (← `(tactic| split)))

/-- `t % 2 ^ 64` in the goal is `t` when `omega` shows `t < 2 ^ 64` from the
hypotheses (the prelude's overflow checks). -/
partial def dropMods : TacticM Unit := do
  let goal ← getMainGoal
  let target ← instantiateMVars (← goal.getType)
  let found := target.find? fun e =>
    e.isAppOfArity ``HMod.hMod 6 && (e.getArg! 5).nat? == some (2 ^ 64)
  let some e := found | return
  let t := e.getArg! 4
  let ok ← tryTac do
    -- `omega` as a tactic on its own goal: inside a term it would log its
    -- failure rather than throw it.
    let fits ← goal.withContext do
      let ty ← mkAppM ``LT.lt #[t, mkNatLit 18446744073709551616]
      let m ← mkFreshExprMVar ty
      let rest ← Term.TermElabM.run' (Tactic.run m.mvarId! (evalTactic (← `(tactic| omega))))
      unless rest.isEmpty do throwError "omega left goals"
      instantiateMVars m
    let fitsStx ← Term.exprToSyntax fits
    evalTactic (← `(tactic| rw [Nat.mod_eq_of_lt $fitsStx]))
  if ok then dropMods

partial def faithfulLoop (ns : Name) (heads : Array Ident) (fuel : Nat) : TacticM Unit := do
  if fuel = 0 then throwError m!"faithful: out of fuel{indentD (MessageData.ofGoal (← getMainGoal))}"
  let mut before : UInt64 := 0
  for _ in [0:faithful.rounds.get (← getOptions)] do
    if (← getGoals).isEmpty then return
    let now ← phase "fingerprint" goalText
    if now == before then break
    before := now
    round ns
  if (← getGoals).isEmpty then return
  if ← phase "pending" pending then
    if ← phase "split" split then
      let goals ← getGoals
      let mut done : List MVarId := []
      for g in goals do
        setGoals [g]
        faithfulLoop ns heads (fuel - 1)
        done := done ++ (← getGoals)
      setGoals done
      return
  if faithful.admitClose.get (← getOptions) then
    logInfo m!"{MessageData.ofGoal (← getMainGoal)}"
    evalTactic (← `(tactic| admit))
    return
  let lemmas : Array (TSyntax `Lean.Parser.Tactic.simpLemma) ← heads.mapM fun h => `(Lean.Parser.Tactic.simpLemma| $h:ident)
  if ← closes (← `(tactic| rep)) then return
  if ← tryTac (do dropMods; evalTactic (← `(tactic| rep)); done) then return
  if !heads.isEmpty then
    -- A recursive function: unfold it once (`simp` would not stop).
    if ← closes (← `(tactic| (unfold $heads*; simp only [*, ↓reduceIte, BitVec.ofNat_eq_ofNat]; rep))) then return
    -- Or only its call in the goal's Lean side (`unfold` would unfold its
    -- calls in the pure value too).
    if ← closes (← `(tactic| (rw [$(heads[0]!):ident]; simp only [*, ↓reduceIte, BitVec.ofNat_eq_ofNat]; rep))) then return
    if ← closes (← `(tactic| (simp only [$lemmas,*]; rep))) then return
    if ← closes (← `(tactic| (simp only [$lemmas,*, *]; rep))) then return
    if ← closes (← `(tactic| (simp only [$lemmas,*] at *; rep))) then return
    if ← closes (← `(tactic| (simp [$lemmas,*, *, Nat.max_def, Nat.min_def, List.getElem?_cons, List.getD_cons_succ,
        List.getD_cons_zero]; rep))) then return
    if ← closes (← `(tactic| (simp [$lemmas,*, *] at *; rep))) then return
    if ← tryTac (withBudget do
        evalTactic (← `(tactic| simp only [$lemmas,*]))
        unless ← foldInline do throwError "nothing to fold"
        evalTactic (← `(tactic| (simp [*]; rep)))
        done) then return
    if ← tryTac (withBudget do
        let _ ← unfoldInlineConds
        evalTactic (← `(tactic| (simp [$lemmas,*, *]; rep)))
        done) then return
    -- A recursive function's tests against inline constants: unfold those
    -- in the conditions, and the function once.
    if ← tryTac (withBudget do
        unless ← unfoldInlineConds do throwError "no inline constants"
        evalTactic (← `(tactic| (unfold $heads*; simp [*]; rep)))
        done) then return
    -- A recursive function whose inline part has a `match` of its own: its
    -- equation lemmas split that match, so `rw` with the function fails;
    -- its definition unfolded is the inline call a hypothesis states.
    if ← closes (← `(tactic| (rw [$(mkIdent (heads[0]!.getId ++ `eq_def)):ident]; assumption))) then return
  -- The functions applied to constructors, everywhere: the facts the
  -- hypotheses state about the parts, or a contradiction.
  let callees ← phase "ctorCallees" ctorCallees
  let names := (heads.map (·.getId)) ++ callees.filter fun c => !heads.any (·.getId == c)
  let all : Array (TSyntax `Lean.Parser.Tactic.simpLemma) ←
    names.mapM fun n => `(Lean.Parser.Tactic.simpLemma| $(mkIdent n):ident)
  if !all.isEmpty then
    if ← closes (← `(tactic| (simp [$all,*, *] at *; rep))) then return
    if ← closes (← `(tactic| (simp [$all,*] at *; simp [$all,*, *]; rep))) then return
  -- The same with the inline constants (token kinds and the like) unfolded
  -- everywhere at once, so the hypotheses about them match the goal's tests.
  let consts ← inlineConsts
  if !consts.isEmpty then
    let withConsts ← (names ++ consts).mapM fun n => `(Lean.Parser.Tactic.simpLemma| $(mkIdent n):ident)
    -- Two passes: `simp at *` rewrites the goal with the hypotheses as they
    -- were before the constants were unfolded.
    if ← closes (← `(tactic| (simp [$withConsts,*] at *; simp [$all,*, *]; rep))) then return
  -- An index into a list's tail: `¬i = 0` and the tail's representation.
  if ← closes (← `(tactic| (simp only [List.getD_eq_getElem?_getD, List.getElem?_cons, *, ↓reduceIte]; rep))) then
    return
  if ← phase "split" split then
    let goals ← getGoals
    let mut done : List MVarId := []
    for g in goals do
      setGoals [g]
      faithfulLoop ns heads (fuel - 1)
      done := done ++ (← getGoals)
    setGoals done
    return
  throwError m!"faithful: stuck{indentD (MessageData.ofGoal (← getMainGoal))}"

syntax "faithful" " [" ident,* "]" : tactic

elab_rules : tactic
  | `(tactic| faithful [$heads,*]) => do
    faithfulLoop (← getCurrNamespace) heads.getElems (faithful.depth.get (← getOptions))

/-- For working on the generator only: a proof `faithful` cannot finish is
reported as a warning and admitted, so one run shows every failure. No
committed file uses it (the certificates' axioms show it). -/
syntax "faithful_dev" " [" ident,* "]" : tactic

elab_rules : tactic
  | `(tactic| faithful_dev [$heads,*]) => do
    let saved ← saveState
    let ns ← getCurrNamespace
    phaseTimes.set {}
    tryCatchRuntimeEx (faithfulLoop ns heads.getElems (faithful.depth.get (← getOptions))) (fun e => do
      saved.restore
      logWarning m!"FAITHFUL FAILED: {e.toMessageData}"
      evalTactic (← `(tactic| admit)))
    if faithful.profile.get (← getOptions) then
      let times := (← phaseTimes.get).toArray.qsort (fun a b => a.2 > b.2)
      logInfo m!"{times.map fun (n, t) => s!"{n} {t / 1000000} ms"}"

end Lanius.Faithful

namespace Lanius.Faithful
open Lean Elab Tactic Meta

/-- For working on `faithful` only: one step of a round (0 cases, 1 simp,
2 destruct, 3 certificates, 4 inline, 5 contradiction). -/
elab "faithful_step " k:num : tactic => do
  let ns ← getCurrNamespace
  match k.getNat with
  | 0 => while ← casesKnown do if (← getGoals).isEmpty then return
  | 1 => pureSimpEval
  | 2 =>
    let _ ← tryTac (evalTactic (← `(tactic| destruct)))
    let _ ← tryTac (peelCalls 10000)
    let _ ← tryTac (evalTactic (← `(tactic| subst_vars)))
  | 3 => certsLoop ns
  | 4 => let _ ← unfoldInlineConds
  | 6 => evalTactic (← `(tactic| destruct))
  | 12 => pureSimpEval
  | 9 => peelCalls 10000
  | 11 => withMainContext do
    let mut g ← getMainGoal
    for d in ← getLCtx do
      if d.isImplementationDetail then continue
      let t ← instantiateMVars d.type
      let some (ty, lhs, rhs) := t.eq? | continue
      unless lhs.isAppOfArity ``Option.bind 4 && lhs.appFn!.appArg!.isAppOfArity ``Option.some 2 do continue
      let v := lhs.appFn!.appArg!.appArg!
      let f := lhs.appArg!
      g ← g.replaceLocalDeclDefEq d.fvarId (mkApp3 (mkConst ``Eq [← getLevel ty]) ty (mkApp f v).headBeta rhs)
    replaceMainGoal [g]
  | 10 => withMainContext do
    let mut hs := #[]
    for d in ← getLCtx do
      if !d.isImplementationDetail && (← instantiateMVars d.type).isEq then hs := hs.push d.fvarId
    let (_, g) ← (← getMainGoal).revert hs
    replaceMainGoal [g]
  | 7 => evalTactic (← `(tactic| subst_vars))
  | 8 => withMainContext do
    for d in ← getLCtx do
      unless d.isImplementationDetail do
        let t ← instantiateMVars d.type
        logInfo m!"{d.userName}: {t.sizeWithoutSharing} {t.approxDepth}"
  | _ => evalTactic (← `(tactic| contradiction))

end Lanius.Faithful
