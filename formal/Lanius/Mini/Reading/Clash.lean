module

public import Lanius.Mini.Reading.Prods
public meta import Lean

public meta section

/-! # `prods_clash`: two hypotheses that give a node two productions

A goal of the reading's determinism proofs is often closed by two hypotheses
that cannot both hold: `nodeProd c = pCast` and `nodeProd c = pNeg`, or
`nodeProd c ∈ levelProds`. `simp at *` and `omega` over the whole context
find that, at a cost that grows with the context. `prods_clash [f, ..]`
instead takes the hypotheses that test productions (or apply `f, ..`), states
them as a closed proposition (`∀ c .., h₁ → .. → hₙ → False`, over the locals
they mention), and proves that in an empty context: the constants of type `Nat` or `List Nat`
they mention (the productions, `levelProds`) and `f, ..` unfolded, then
`omega`. -/

namespace Lanius.Mini.Reading

open Lean Elab Tactic Meta

/-- The locals `e` mentions, with those their types mention, in context order. -/
def clashFVars (es : Array Expr) : MetaM (Array Expr) := do
  let mut set : Std.HashSet FVarId := {}
  let mut todo : Array FVarId := es.foldl (fun acc e => acc ++ ((collectFVars {} e).fvarIds)) #[]
  while h : todo.size > 0 do
    let f := todo[todo.size - 1]
    todo := todo.pop
    if set.contains f then continue
    set := set.insert f
    let t ← instantiateMVars (← f.getType)
    todo := todo ++ ((collectFVars {} t).fvarIds)
  let lctx ← getLCtx
  let mut out := #[]
  for d in lctx do
    if set.contains d.fvarId then out := out.push d.toExpr
  return out

/-- The constants of `e` that are numbers or lists of numbers, and those their
values mention (`levelProds`' productions). -/
def clashConsts (extra : Array String) (e : Expr) : MetaM (Array Name) := do
  let mut out : Array Name := #[]
  let mut seen : Array Name := #[]
  let mut todo := e.getUsedConstants
  while h : todo.size > 0 do
    let c := todo[todo.size - 1]
    todo := todo.pop
    if seen.contains c then continue
    seen := seen.push c
    let some info := (← getEnv).find? c | continue
    let some v := info.value? | continue
    let t := info.type
    -- `extra`'s bodies are unfolded too: the productions they test.
    if (match c with | .str _ s => extra.contains s | _ => false) then
      todo := todo ++ v.getUsedConstants
    else if t.isConstOf ``Nat || (t.isAppOfArity ``List 1 && t.appArg!.isConstOf ``Nat) then
      out := out.push c
      todo := todo ++ v.getUsedConstants
  return out

/-- Prove `stmt`, closed, in an empty context with `tac`. -/
def clashProve (stmt : Expr) (tac : TSyntax `tactic) : TacticM (Option Expr) := do
  let saved ← saveState
  try
    let m ← withLCtx {} {} (mkFreshExprMVar stmt)
    let rest ← withLCtx {} {} (Tactic.run m.mvarId! (evalTactic tac))
    unless rest.isEmpty do
      saved.restore
      return none
    return some (← instantiateMVars m)
  catch _ =>
    saved.restore
    return none

/-- The locals whose production `t` tests (`nodeProd (kid c 1)` tests `c`), or
that it applies one of the predicates `extra` to. -/
partial def clashKeys (extra : Array String) (t : Expr) : Array FVarId :=
  go t #[]
where
  go (e : Expr) (acc : Array FVarId) : Array FVarId :=
    let acc := match e.getAppFn with
      | .const n _ =>
        let hit := n == `Lanius.Mini.nodeProd || (match n with
          | .str _ s => extra.contains s
          | _ => false)
        if hit then e.getAppArgs.foldl (fun acc a => acc ++ (collectFVars {} a).fvarIds) acc else acc
      | _ => acc
    match e with
    | .app f a => go a (go f acc)
    | .lam _ t b _ | .forallE _ t b _ => go b (go t acc)
    | .letE _ t v b _ => go b (go v (go t acc))
    | .mdata _ b | .proj _ _ b => go b acc
    | _ => acc

syntax "prods_clash" (" [" ident,* "]")? : tactic

elab_rules : tactic
  | `(tactic| prods_clash $[[$extra,*]]?) => do
    let extra := match extra with
      | some xs => xs.getElems
      | none => #[]
    let goal ← getMainGoal
    goal.withContext do
      let mut hyps : Array (Expr × Expr) := #[]
      for d in ← getLCtx do
        if d.isImplementationDetail then continue
        let t ← instantiateMVars d.type
        unless ← isProp t do continue
        if t.hasMVar then continue
        let names := t.getUsedConstants
        unless names.any (· == `Lanius.Mini.nodeProd) || extra.any (fun x => names.any fun c => match c with
            | .str _ s => s == x.getId.eraseMacroScopes.toString
            | _ => false) do
          continue
        hyps := hyps.push (d.toExpr, t)
      let extraNames := extra.map (·.getId.eraseMacroScopes.toString)
      let keys := hyps.map fun (_, t) => clashKeys extraNames t
      let target ← goal.getType
      let attempt (hs : Array (Expr × Expr)) : TacticM Bool := do
        let fvs ← clashFVars (hs.map (·.2))
        let body ← hs.foldrM (fun (_, t) acc => mkArrow t acc) (mkConst ``False)
        let stmt ← mkForallFVars fvs body
        if stmt.hasFVar then return false
        let consts ← clashConsts extraNames stmt
        let lemmas ← (consts.map mkIdent ++ extra ++ #[mkIdent ``List.mem_cons, mkIdent ``List.not_mem_nil,
          mkIdent ``or_false]).mapM fun i => `(Lean.Parser.Tactic.simpLemma| $i:ident)
        let tac ← `(tactic| (intros; (try simp only [$lemmas,*] at *); omega))
        let some pf ← clashProve stmt tac | return false
        let falso := mkAppN pf (fvs ++ hs.map (·.1))
        goal.assign (← mkFalseElim target falso)
        replaceMainGoal []
        return true
      -- All of them at once: `omega` finds the ones that clash.
      let keyed := (List.range hyps.size).filterMap fun k => if keys[k]!.isEmpty then none else some hyps[k]!
      if ← attempt keyed.toArray then return
      throwError m!"prods_clash: no two hypotheses clash{indentD (MessageData.ofGoal goal)}"

end Lanius.Mini.Reading
