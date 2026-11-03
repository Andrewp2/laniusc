import Lean
import Lanius.Faithful.SelfPre.HBAttr

/-! # `pre_auto` and `post_auto`: preconditions and heights by the potential (F14)

Every value a run of the self program holds is at most as high (`hb`) as a
potential `M` bounding its arguments plus the boxes allocated since, and the
budget left falls by those boxes: so `M + b` stays at most a bound `K` at the
budget `b`. A list is at most as long as it is high, so a `plus` on a list's
length or on a walker's index stays below `2 ^ 64`.

* `post_auto n, M` proves a height lemma
  `hb x ≤ M → .. → Cost_F (n + 1) xs < 2 ^ 64 → hb (F xs) ≤ M + Cost_F (n + 1) xs`
  (the cost model and the Lean function unfolded once): it splits their cases
  as the cost model splits them, and closes each case with the callees' height
  lemmas (`post_G` for `Cost_G n ys`, `HBPost.<f>.p<i>` for a Lean function the
  cost model does not see), each at `M` plus the boxes of the values its
  arguments come from, splitting the Lean function's remaining cases if needed.
* `upost_auto M` closes a case of `hb (f xs) ≤ M` for such a Lean function.
* `pre_auto n, M` proves `Pre_F (n + 1) xs b` from `hb x ≤ M` and `M + b ≤ K`:
  it takes the precondition apart (`∧`, the cost guards, `if`s and `match`es)
  and closes each callee's precondition by its lemma (`pre_G`) and each `plus`
  or `times` by arithmetic, with the same facts.

The arithmetic is linear over atoms (heights and cost-model calls); `omegaAtoms`
picks the few hypotheses a goal needs and runs `omega` over the atoms as
variables, since `omega` itself is slow on many hypotheses over big atoms. -/

namespace Lanius.Faithful.SelfPre.Tactic

open Lean Meta Elab Tactic

/-- Every subterm of `e` that `p` keeps (not inside binders' types). -/
partial def subterms (p : Expr → Bool) (e : Expr) : Array Expr :=
  go e #[]
where
  go (e : Expr) (acc : Array Expr) : Array Expr :=
    let acc := if p e then acc.push e else acc
    match e with
    | .app f a => go a (go f acc)
    | .lam _ t b _ => go b (go t acc)
    | .forallE _ t b _ => go b (go t acc)
    | .letE _ t v b _ => go b (go v (go t acc))
    | .mdata _ e => go e acc
    | .proj _ _ e => go e acc
    | _ => acc

/-- `hb e`'s argument. -/
def hbArg? (e : Expr) : Option Expr :=
  if e.isAppOfArity `Lanius.Faithful.SelfPre.HB.hb 3 then some e.appArg! else none

/-- `List.length l`'s list. -/
def lengthArg? (e : Expr) : Option Expr :=
  if e.isAppOfArity ``List.length 2 then some e.appArg! else none

/-- A cost model's call: its key (`Cost_<key>`) and the call. -/
def lastName (n : Name) : String :=
  match n with
  | .str _ s => s
  | _ => ""

def costKey? (e : Expr) : Option String :=
  match e.getAppFn with
  | .const n _ =>
    let s : String := lastName n
    if s.startsWith "Cost_" && e.getAppNumArgs ≥ 1 then some (s.drop 5).toString else none
  | _ => none

def hasLoose (e : Expr) : Bool := e.hasLooseBVars

/-- The constant `nm` with fresh universe metavariables. Unlike
`mkConstWithFreshMVarLevels` it reads only the signature (`getConstVal`), so it
does not wait for the proof of a theorem earlier in the same module, which the
asynchronous elaborator may still be checking: waiting serialized the modules. -/
def constFresh (nm : Name) : MetaM Expr := do
  let val ← getConstVal nm
  return mkConst nm (← val.levelParams.mapM fun _ => mkFreshLevelMVar)

/-- A local hypothesis or a constant called `nm`, as a term. -/
def lookup? (nm : Name) : TacticM (Option Expr) := do
  if let some d := (← getLCtx).findFromUserName? nm then return some d.toExpr
  let env ← getEnv
  if env.contains nm then return some (← constFresh nm)
  return none

/-- A generated lemma `s`: in the current namespace (a generated module's own,
e.g. the compile side's `SelfPre.Compile`, whose lemmas share names with
build_files'), else under `Lanius.Faithful.SelfPre`. -/
def genLookup? (s : Name) : TacticM (Option Expr) := do
  let ns ← getCurrNamespace
  if ns != `Lanius.Faithful.SelfPre then
    if let some e ← lookup? (ns ++ s) then return some e
  lookup? (`Lanius.Faithful.SelfPre ++ s)

/-- A product of two numbers below `2 ^ 32` does not wrap. -/
theorem mul_lt_two64 {x y : Nat} (hx : x < 4294967296) (hy : y < 4294967296) :
    x * y < 18446744073709551616 := by
  have := Nat.mul_le_mul (Nat.le_of_lt_succ hx) (Nat.le_of_lt_succ hy)
  omega

/-- `max` on the left of `≤` as a conjunction, so `omega` meets no `max`. -/
theorem max_le_iff' {a b c : Nat} : max a b ≤ c ↔ a ≤ c ∧ b ≤ c := by omega
theorem max_add_le_iff' {a b k c : Nat} : max a b + k ≤ c ↔ a + k ≤ c ∧ b + k ≤ c := by omega

/-- The conditions' normal form: `Bool` tests as propositions. -/
def normNames : Array Name := #[`decide_eq_true_eq, `decide_eq_false_iff_not, `Bool.and_eq_true, `Bool.or_eq_true,
  `Bool.not_eq_true', `Bool.not_eq_false', `not_and, `not_or, `true_and, `and_true, `false_and, `and_false,
  `true_or, `or_true, `false_or, `or_false, `Bool.false_eq_true, `Bool.true_eq_false, `Bool.false_and,
  `Bool.true_and, `Bool.and_false, `Bool.and_true, `Bool.false_or, `Bool.true_or, `Bool.or_false, `Bool.or_true,
  `Bool.not_true, `Bool.not_false, `if_true, `if_false, `ite_true, `ite_false, `dite_true, `dite_false, `not_true_eq_false, `not_false_eq_true, `eq_self_iff_true,
  `decide_true, `decide_false]

/-- A byte literal as the Lean functions write it (`72`), not as the cost models
do (`UInt8.ofNat 72`): the compile side's byte lists. -/
theorem uint8_ofNat_lit (n : Nat) : UInt8.ofNat (no_index (OfNat.ofNat n)) = (OfNat.ofNat n : UInt8) := rfl

/-- The heights' normal form: `hb` of a constructor by its parts, `max` on the
left of `≤` as a conjunction. -/
def hbNormNames : Array Name := #[``max_le_iff', ``max_add_le_iff', ``Nat.add_assoc, ``BitVec.ofNat_eq_ofNat,
  ``uint8_ofNat_lit]

/-- The nullary `Lanius.Mini` definitions and the `Inline` functions in the context
and the goal. -/
def inlineIds : TacticM (Array Name) := do
  let g ← getMainGoal
  g.withContext do
    let mut out : Array Name := #[]
    let mut ts := #[← instantiateMVars (← g.getType)]
    for d in ← getLCtx do
      unless d.isImplementationDetail do ts := ts.push (← instantiateMVars d.type)
    for t in ts do
      for c in subterms (fun e => e.isConst) t do
        let .const n _ := c | continue
        if out.contains n || !(`Lanius.Mini).isPrefixOf n then continue
        let some (.defnInfo info) := (← getEnv).find? n | continue
        if !info.type.isForall || (`Lanius.Mini.Inline).isPrefixOf n then out := out.push n
    return out

/-- The nullary `Lanius.Mini` definitions and the `Inline` functions in `e`. -/
def constIdsOf (e : Expr) : MetaM (Array Name) := do
  let mut out : Array Name := #[]
  for c in subterms (fun e => e.isConst) e do
    let .const n _ := c | continue
    if out.contains n || !(`Lanius.Mini).isPrefixOf n then continue
    let some (.defnInfo info) := (← getEnv).find? n | continue
    if !info.type.isForall || (`Lanius.Mini.Inline).isPrefixOf n then out := out.push n
  return out

/-- A name `hsplit<i>` not yet in the context: each case split's hypothesis gets
its own, so the facts can be simplified by all of them. -/
def freshSplitName : TacticM Name := withMainContext do
  let lctx ← getLCtx
  let mut i := 0
  while (lctx.findFromUserName? (Name.mkSimple s!"hsplit{i}")).isSome do i := i + 1
  return Name.mkSimple s!"hsplit{i}"

/-- Name the equations a `split` added (`d = C ..`) as case splits' hypotheses. -/
def nameSplitEqns (before : Array FVarId) : TacticM (Array Name) := do
  let mut g ← getMainGoal
  let mut names := #[]
  let ds ← g.withContext do return (← getLCtx).decls.toList.filterMap id
  for d in ds do
    if d.isImplementationDetail || before.contains d.fvarId then continue
    unless (← g.withContext do instantiateMVars d.type).isAppOfArity ``Eq 3 do continue
    let nm ← g.withContext do
      let lctx ← getLCtx
      let mut i := 0
      while (lctx.findFromUserName? (Name.mkSimple s!"hsplit{i}")).isSome do i := i + 1
      return Name.mkSimple s!"hsplit{i}"
    g ← g.rename d.fvarId nm
    names := names.push nm
  replaceMainGoal [g]
  return names

/-- The case splits' hypotheses in the context. -/
def splitNames : TacticM (Array Name) := withMainContext do
  let mut out := #[]
  for d in ← getLCtx do
    if d.isImplementationDetail then continue
    match d.userName with
    | .str .anonymous s => if s.startsWith "hsplit" then out := out.push d.userName
    | _ => pure ()
  return out

def simpArgs (extra : Array Name) : TacticM (Array (TSyntax `Lean.Parser.Tactic.simpLemma)) := do
  let mut args : Array (TSyntax `Lean.Parser.Tactic.simpLemma) := #[← `(Lean.Parser.Tactic.simpLemma| hb_simp)]
  for n in hbNormNames ++ normNames ++ extra do
    args := args.push (← `(Lean.Parser.Tactic.simpLemma| $(mkIdent n):ident))
  return args

/-- Normalize the heights in the goal and the hypotheses (and unfold the nullary
definitions, when `consts`). -/
def hbNorm (consts : Bool := true) : TacticM Unit := do
  let ids ← if consts then inlineIds else pure #[]
  let args ← simpArgs ids
  evalTactic (← `(tactic| try simp only [$args,*] at *))

/-! ## `omega` over atoms

The heights and the cost models' calls are big terms; `omega` compares its atoms
up to definitional equality, which is slow on them. `omegaAtoms` replaces every
atom (a `Nat` subterm that is not arithmetic) by a variable, syntactically, proves
the arithmetic statement over the variables by `omega`, and instantiates it. -/

def dbg (msg : String) : CoreM Unit := do
  if lanius.hb.debug.get (← getOptions) then IO.eprintln s!"[{← IO.monoMsNow}] {msg}"

/-- A `Nat` operation `omega` reads. -/
def arithHead (e : Expr) : Bool :=
  e.isAppOfArity ``HAdd.hAdd 6 || e.isAppOfArity ``HSub.hSub 6 || e.isAppOfArity ``HMul.hMul 6 ||
  e.isAppOfArity ``HDiv.hDiv 6 || e.isAppOfArity ``HMod.hMod 6 || e.isAppOfArity ``Max.max 4 ||
  e.isAppOfArity ``Min.min 4 || e.isAppOfArity ``Nat.succ 1

/-- The atoms of a `Nat` term, or `none` if it is not of `Nat`. -/
partial def termAtoms (e : Expr) (acc : Array Expr) : Array Expr :=
  if e.isRawNatLit || e.isAppOfArity ``OfNat.ofNat 3 then acc
  else if arithHead e then
    let n := e.getAppNumArgs
    if e.isAppOfArity ``Nat.succ 1 then termAtoms e.appArg! acc
    else termAtoms e.appArg! (termAtoms (e.getArg! (n - 2)) acc)
  else if acc.contains e then acc else acc.push e

def isNatTy (t : Expr) : Bool := t.isConstOf ``Nat

/-- The atoms of an arithmetic proposition (over `Nat`), or `none`. -/
partial def propAtoms (p : Expr) (acc : Array Expr) : Option (Array Expr) :=
  if p.isConstOf ``True || p.isConstOf ``False then some acc
  else if p.isAppOfArity ``And 2 || p.isAppOfArity ``Or 2 || p.isAppOfArity ``Iff 2 then
    propAtoms p.appFn!.appArg! acc >>= propAtoms p.appArg!
  else if p.isAppOfArity ``Not 1 then propAtoms p.appArg! acc
  else if (p.isAppOfArity ``LE.le 4 || p.isAppOfArity ``LT.lt 4) && isNatTy (p.getArg! 0) then
    some (termAtoms p.appArg! (termAtoms p.appFn!.appArg! acc))
  else if (p.isAppOfArity ``Eq 3 || p.isAppOfArity ``Ne 3) && isNatTy (p.getArg! 0) then
    some (termAtoms p.appArg! (termAtoms p.appFn!.appArg! acc))
  else match p with
    | .forallE _ a b _ => if b.hasLooseBVars then none else propAtoms a acc >>= propAtoms b
    | _ => none

/-! ### Choosing the hypotheses

`omega` slows down badly with many hypotheses over many atoms. The facts here are
almost all upper bounds, so a short search finds the few a goal needs: replace a
part of the left side by its bound, or weaken the left side to a hypothesis's;
`omega` then checks the goal from those alone. -/

/-- A linear form over the atoms: coefficients, then the constant last. -/
abbrev Lin := Array Int

def Lin.zero (n : Nat) : Lin := Array.replicate (n + 1) 0
def Lin.add (a b : Lin) : Lin := a.zipWith (· + ·) b
def Lin.sub (a b : Lin) : Lin := a.zipWith (· - ·) b
def Lin.scale (k : Int) (a : Lin) : Lin := a.map (k * ·)
/-- Every coefficient and the constant of `a` at least `0`. -/
def Lin.nonneg (a : Lin) : Bool := a.all (0 ≤ ·)

def natLit? (e : Expr) : Option Nat :=
  if let some n := e.rawNatLit? then some n
  else if e.isAppOfArity ``OfNat.ofNat 3 then (e.getArg! 1).rawNatLit?
  else none

/-- The linear form of a `Nat` term, or `none` for a truncated subtraction, a
division, a `max` or a `min`. -/
partial def linOf (atoms : Array Expr) (e : Expr) : Option Lin :=
  let n := atoms.size
  if let some k := natLit? e then some ((Lin.zero n).set! n k)
  else if e.isAppOfArity ``HAdd.hAdd 6 then
    return Lin.add (← linOf atoms (e.getArg! 4)) (← linOf atoms (e.getArg! 5))
  else if e.isAppOfArity ``HMul.hMul 6 then
    match natLit? (e.getArg! 4), natLit? (e.getArg! 5) with
    | some k, _ => return Lin.scale k (← linOf atoms (e.getArg! 5))
    | _, some k => return Lin.scale k (← linOf atoms (e.getArg! 4))
    | none, none => none
  else if e.isAppOfArity ``Nat.succ 1 then
    return Lin.add (← linOf atoms e.appArg!) ((Lin.zero n).set! n 1)
  else if arithHead e then none
  else match atoms.idxOf? e with
    | some i => some ((Lin.zero n).set! i 1)
    | none => none

/-- The constraints `L ≤ R` a proposition states (its conjuncts). -/
partial def constraintsOf (atoms : Array Expr) (p : Expr) : Array (Lin × Lin) :=
  let n := atoms.size
  let one := (Lin.zero n).set! n 1
  if p.isAppOfArity ``And 2 then
    constraintsOf atoms p.appFn!.appArg! ++ constraintsOf atoms p.appArg!
  else if p.isAppOfArity ``LE.le 4 && isNatTy (p.getArg! 0) then
    match linOf atoms (p.getArg! 2), linOf atoms (p.getArg! 3) with
    | some l, some r => #[(l, r)]
    | _, _ => #[]
  else if p.isAppOfArity ``LT.lt 4 && isNatTy (p.getArg! 0) then
    match linOf atoms (p.getArg! 2), linOf atoms (p.getArg! 3) with
    | some l, some r => #[(l.add one, r)]
    | _, _ => #[]
  else if p.isAppOfArity ``Eq 3 && isNatTy (p.getArg! 0) then
    match linOf atoms (p.getArg! 1), linOf atoms (p.getArg! 2) with
    | some l, some r => #[(l, r), (r, l)]
    | _, _ => #[]
  else #[]

/-- Hypotheses (by index) that give `L ≤ R`: replace a part `L'` of the left side
by `R'` (`L' ≤ R'`), or weaken the left side to such an `L'`, until the right side
covers it. The state bounds the nodes searched (a failing search over many
hypotheses is otherwise exponential). -/
partial def certify (cs : Array (Lin × Lin × Nat)) (l r : Lin) (fuel : Nat) (used : Array Nat) :
    StateM Nat (Option (Array Nat)) := do
  if (r.sub l).nonneg then return some used
  if fuel = 0 then return none
  let k ← get
  if k = 0 then return none
  set (k - 1)
  for (l', r', i) in cs do
    if used.contains i then continue
    -- a part of the left side
    if (l.sub l').nonneg then
      if let some u ← certify cs ((l.sub l').add r') r (fuel - 1) (used.push i) then return some u
  for (l', r', i) in cs do
    if used.contains i then continue
    -- the left side below a hypothesis's left side
    if (l'.sub l).nonneg then
      if let some u ← certify cs r' r (fuel - 1) (used.push i) then return some u
  return none

/-- The hypotheses (by index) a goal's conjuncts need, if the search finds them. -/
def selectHyps (atoms : Array Expr) (goal : Expr) (hyps : Array Expr) : Option (Array Nat) := Id.run do
  let gs := constraintsOf atoms goal
  if gs.isEmpty then return none
  let mut cs : Array (Lin × Lin × Nat) := #[]
  for h : i in [0:hyps.size] do
    for (l, r) in constraintsOf atoms hyps[i] do cs := cs.push (l, r, i)
  let mut out : Array Nat := #[]
  for (l, r) in gs do
    let some u := ((certify cs l r 6 #[]).run' 40 : Id _) | return none
    for i in u do
      unless out.contains i do out := out.push i
  return some out

/-- Run `x` within its own heartbeat budget (`k` thousands): `omega` over many
hypotheses can take exponential time; past the budget `x` fails (an ordinary
error, so callers try the next way). -/
def budgeted (k : Nat) (x : TacticM α) : TacticM α :=
  tryCatchRuntimeEx
    (withCurrHeartbeats <| withTheReader Core.Context (fun c => { c with maxHeartbeats := k * 1000 }) x)
    (fun e => throwError "budget exceeded: {e.toMessageData}")

/-- `Nat.add_assoc` reversed, stated once: `simp only [← Nat.add_assoc]` adds an
auxiliary theorem at every use (one per `omega` call), each checked by the kernel. -/
theorem add_nest_left (a b c : Nat) : a + (b + c) = a + b + c := (Nat.add_assoc a b c).symm

/-- Prove the main goal by `omega` over its and the hypotheses' atoms. -/
def omegaAtoms : TacticM Unit := withMainContext do
  let g ← getMainGoal
  let goal ← instantiateMVars (← g.getType)
  dbg "omegaAtoms"
  let some atoms0 := propAtoms goal #[] |
    if lanius.hb.debug.get (← getOptions) then IO.eprintln s!"omegaAtoms: not arithmetic"
    evalTactic (← `(tactic| omega))
  let mut atoms := atoms0
  let mut hyps : Array (Expr × Expr) := #[]
  for d in ← getLCtx do
    if d.isImplementationDetail then continue
    let t ← instantiateMVars d.type
    unless ← isProp t do continue
    if let some as := propAtoms t atoms then
      atoms := as
      hyps := hyps.push (d.toExpr, t)
  let atomsArr := atoms
  dbg s!"atoms {atoms.size}"
  match selectHyps atomsArr goal (hyps.map (·.2)) with
  | some sel =>
    let saved ← saveState
    try
      omegaOver atomsArr goal (sel.map (hyps[·]!))
      return
    catch _ => saved.restore
  | none => pure ()
  budgeted 40000 (omegaOver atomsArr goal hyps)
where
  /-- `omega` over the atoms, from the hypotheses `hyps`. -/
  omegaOver (atomsArr : Array Expr) (goal : Expr) (hyps : Array (Expr × Expr)) : TacticM Unit := do
  let g ← getMainGoal
  let stmt ← withLocalDeclsDND (atomsArr.mapIdx fun i _ => (Name.mkSimple s!"a{i}", mkConst ``Nat)) fun xs => do
    let abst (e : Expr) : Expr := e.replace fun s =>
      match atomsArr.idxOf? s with
      | some i => some xs[i]!
      | none => none
    let body := hyps.foldr (fun (_, t) acc => mkForall `h .default (abst t) acc) (abst goal)
    mkForallFVars xs body
  -- The statement is closed (its atoms are variables): prove it in an empty context,
  -- or `simp at *` and `omega` read all of the goal's (big) hypotheses too.
  let m ← if stmt.hasFVar || stmt.hasMVar then mkFreshExprMVar stmt
    else mkFreshExprMVarAt {} {} stmt
  let t0 ← IO.monoMsNow
  -- `omega` takes time exponential in the depth of a right-nested sum: nest them left
  let gs ← try Tactic.run m.mvarId! (withoutRecover (evalTactic (← `(tactic|
      intros; (try simp only [add_nest_left] at *); omega))))
    catch e =>
      if lanius.hb.debug.get (← getOptions) then
        IO.eprintln s!"omegaAtoms: failed, {atomsArr.size} atoms, {hyps.size} hyps, {(← IO.monoMsNow) - t0} ms"
      throw e
  if lanius.hb.debug.get (← getOptions) then
    IO.eprintln s!"omegaAtoms: {atomsArr.size} atoms, {hyps.size} hyps, {(← IO.monoMsNow) - t0} ms"
  unless gs.isEmpty do throwError "omegaAtoms: goals left"
  let p := mkAppN (mkAppN (← instantiateMVars m) atomsArr) (hyps.map (·.1))
  g.assign p
  replaceMainGoal []

/-- Prove `ty` in the current context: heights normalized, then `omega`. -/
def proveArith? (ty : Expr) : TacticM (Option Expr) := do
  let g ← mkFreshExprMVar ty
  let saved ← saveState
  try
    let args ← simpArgs #[``Nat.reducePow]
    let gs ← Tactic.run g.mvarId! (withoutRecover do
      evalTactic (← `(tactic| try simp only [$args,*]))
      dbg "simped"
      for g in ← getGoals do
        setGoals [g]
        omegaAtoms)
    let p ← instantiateMVars g
    if gs.isEmpty && !p.hasSorry && !p.hasSyntheticSorry then return some p
    saved.restore
    return none
  catch _ =>
    saved.restore
    return none

/-- Add `p : t` to the context as `name`. -/
def addFact (name : Name) (p : Expr) : TacticM Unit := withMainContext do
  let g ← getMainGoal
  let t ← instantiateMVars (← inferType p)
  let g' ← g.assert name t p
  let (_, g'') ← g'.intro1P
  replaceMainGoal [g'']

/-- The upper-bound lemmas for the Lean function `f` the cost model does not see:
`HBPost.<f>.p0`, `p1`, .. -/
def postsOf (f : Name) : TacticM (Array Expr) := do
  let mut out := #[]
  -- a local hypothesis concluding `hb (f ..) ≤ _`: an induction's hypothesis
  for d in ← getLCtx do
    if d.isImplementationDetail then continue
    let t ← instantiateMVars d.type
    unless t.isForall do continue
    let ok ← forallTelescopeReducing t fun _ c => do
      let some (_, lhs, _) := c.app4? ``LE.le |>.map (fun (a, _, l, r) => (a, l, r)) | return false
      let some a := hbArg? lhs | return false
      return a.getAppFn.isConstOf f
    if ok then out := out.push d.toExpr
  for i in [0:8] do
    match ← genLookup? (`HBPost ++ f ++ Name.mkSimple s!"p{i}") with
    | some c => out := out.push c
    | none => break
  return out

/-- The projection lemma `hb_le_S_f` for `S.f p`. -/
def projFact? (e : Expr) : TacticM (Option Expr) := do
  let .const fn _ := e.getAppFn | return none
  let env ← getEnv
  let some info := env.getProjectionFnInfo? fn | return none
  unless e.getAppNumArgs == info.numParams + 1 do return none
  let s := lastName fn.getPrefix
  let f := lastName fn
  let nm := `Lanius.Faithful.SelfPre ++ Name.mkSimple s!"hb_le_{s}_{f}"
  unless env.contains nm do return none
  return some (mkApp (← constFresh nm) e.appArg!)

/-- The values the context's heights stand for, with the boxes their computation
allocated (`0` for a value the cost model does not see). -/
abbrev Registry := Array (Expr × Expr)

def occursIn (t e : Expr) : Bool := (e.find? (· == t)).isSome

/-- The values `scan` is computed from: `scan` and, through the equations the
case splits left (`d = C .. y ..`), the `d` a variable of it was taken from. -/
def upstream (scan : Array Expr) : MetaM (Array Expr) := do
  let mut terms := scan
  let mut eqs : Array (Expr × Expr) := #[]
  for d in ← getLCtx do
    if d.isImplementationDetail then continue
    let t ← instantiateMVars d.type
    if let some (_, l, r) := t.eq? then eqs := eqs.push (l, r)
  let mut changed := true
  while changed do
    changed := false
    for (l, r) in eqs do
      if terms.contains l then continue
      let fs := (subterms Expr.isFVar r)
      if fs.any (fun f => terms.any (occursIn f)) then
        terms := terms.push l
        changed := true
  return terms

/-- `M` plus the boxes of the values bounded so far that `scan` is computed from
(`dense`: of every value bounded so far). Each is a distinct summand of the cost
(of the function's cost model, or of what the budget lost before a call), so a
callee's arguments are at most this and its value at most this plus its own
boxes. -/
def chooseM (reg : Registry) (base : Expr) (scan : Array Expr) (dense : Bool) : MetaM Expr := do
  let terms ← if dense then pure #[] else upstream scan
  let mut m := base
  let mut used : Array Expr := #[]
  for (t, c) in reg do
    if c.isAppOfArity ``OfNat.ofNat 3 || c.isRawNatLit || used.contains c then continue
    unless dense || terms.any (occursIn t) do continue
    used := used.push c
    m ← mkAppM ``HAdd.hAdd #[m, c]
  return m

def binderNames : Expr → Array Name → Array Name
  | .forallE n _ b _, acc => binderNames b (acc.push n)
  | _, acc => acc

/-- Instantiate `lem` (`∀ .. M .., premises → concl`): `unify` matches its
conclusion, `M` is `base` plus the boxes of the registered values in `scan`
(of the instantiated conclusion), or of all of them, the premises by
`proveArith?`. -/
def instM? (reg : Registry) (base : Expr) (lem : Expr) (unify : Expr → TacticM Bool)
    (scan : Expr → Array Expr) : TacticM (Option (Expr × Expr)) := do
  for dense in [false, true] do
    if let some r ← instM1? dense then return some r
  return none
where
  instM1? (dense : Bool) : TacticM (Option (Expr × Expr)) := do
  let saved ← saveState
  dbg s!"inst {dense}"
  let ty ← instantiateMVars (← inferType lem)
  let names := binderNames ty #[]
  let (ms, _, concl) ← forallMetaTelescopeReducing ty
  unless ← unify concl do
    saved.restore
    return none
  let concl ← instantiateMVars concl
  dbg "unified"
  for (m, n) in ms.zip names do
    if n == `M then
      unless ← m.mvarId!.isAssigned do
        m.mvarId!.assign (← chooseM reg base (scan concl) dense)
  dbg "chosen"
  for m in ms do
    unless ← m.mvarId!.isAssigned do
      let t ← instantiateMVars (← inferType m)
      if ← isProp t then
        let some p ← proveArith? t |
          if lanius.hb.debug.get (← getOptions) then
            IO.eprintln s!"premise failed: {← ppExpr t}\n{← ppGoal (← getMainGoal)}"
          saved.restore; return none
        m.mvarId!.assign p
      else if (← isClass? t).isSome then
        let some i ← (try some <$> synthInstance t catch _ => pure none) | saved.restore; return none
        unless ← isDefEq m i do saved.restore; return none
      else
        saved.restore
        return none
  return some (← instantiateMVars (mkAppN lem ms), ← instantiateMVars concl)

/-- The `hb`-bounded values in `e`: the arguments of `hb`. -/
def hbTerms (e : Expr) : Array Expr :=
  (subterms (fun e => (hbArg? e).isSome) e).filterMap hbArg?

/-- The local hypotheses' and the goal's types. -/
def contextTypes : TacticM (Array Expr) := do
  let g ← getMainGoal
  g.withContext do
    let mut ts := #[← instantiateMVars (← g.getType)]
    for d in ← getLCtx do
      unless d.isImplementationDetail do
        let t ← instantiateMVars d.type
        if ← isProp t then ts := ts.push t
    return ts

/-- A cost model call's lemma: a local `post_<key>` (the group's own, without
its fuel) or the constant. -/
def postLemma? (c : Expr) : TacticM (Option Expr) := do
  let some key := costKey? c | return none
  match ← lookup? (Name.mkSimple s!"post_{key}") with
  | some l => return some l
  | none => genLookup? (Name.mkSimple s!"post_{key}")

/-- Upper bounds for every value the context's heights and cost-model calls
stand for, at the potential `base`: each value at most `base` plus the boxes
allocated for it and for the values inside it. Returns the registry. -/
def hbFacts (fuel : Option Expr) (base : Expr) (extra : Array Expr := #[]) : TacticM Registry := do
  let mut reg : Registry := #[]
  let mut seen : Std.HashSet Expr := {}
  let mut k := 0
  -- the cost models' calls, their values found by their lemmas' conclusions
  let mut pending : Array (Expr × Expr × Expr) := #[]   -- (value, cost, lemma)
  let ts ← contextTypes
  if let some n := fuel then
    for t in ts do
      for c in subterms (fun e => (costKey? e).isSome) t do
        if hasLoose c || seen.contains c then continue
        seen := seen.insert c
        let ok ← withMainContext do
          unless (← whnfR (← inferType c)).isConstOf ``Nat do return false
          withReducible (isDefEq c.getAppArgs[0]! n)
        unless ok do continue
        let some lem ← withMainContext (postLemma? c) | continue
        let v? ← withMainContext do
          let saved ← saveState
          let (_, _, concl) ← forallMetaTelescopeReducing (← inferType lem)
          let some (_, lhs, rhs) := concl.app4? ``LE.le |>.map (fun (a, _, l, r) => (a, l, r))
            | saved.restore; return none
          let ok ← withReducible (isDefEq rhs.appArg! c)
          let v ← instantiateMVars lhs
          saved.restore
          if ok then return hbArg? v else return none
        let some v := v? | continue
        pending := pending.push (v, c, lem)
  dbg s!"pending {pending.size}"
  -- the values with no cost: the arguments of `hb` and the values above
  let mut todo : Array Expr := #[]
  for t in ts do todo := todo ++ hbTerms t
  todo := todo ++ extra
  -- a list's length is at most its height: the lists whose lengths occur
  let mut lens : Array Expr := #[]
  for t in ts do
    for s in subterms (fun e => (lengthArg? e).isSome) t do
      if hasLoose s then continue
      if let some l := lengthArg? s then
        unless lens.contains l do lens := lens.push l
  todo := todo ++ lens
  for (v, _, _) in pending do todo := todo.push v
  let mut free : Array (Expr × Expr) := #[]   -- (value, lemma)
  let mut projs : Array Expr := #[]
  let mut seenV : Std.HashSet Expr := {}
  for t in todo do
    for s in subterms (fun _ => true) t do
      if hasLoose s || seenV.contains s then continue
      seenV := seenV.insert s
      if let some p ← withMainContext (projFact? s) then
        projs := projs.push p
        continue
      if let .const f _ := s.getAppFn then
        if pending.any (fun (v, _, _) => v == s) then continue
        if (← withMainContext do return (← whnfR (← inferType s)).isForall) then continue
        for c in ← withMainContext (postsOf f) do
          free := free.push (s, c)
  dbg s!"free {free.size} projs {projs.size} seen {seenV.size}"
  for p in projs do
    addFact (Name.mkSimple s!"hbp{k}") p
    k := k + 1
  for l in lens do
    let some p ← withMainContext (try some <$> mkAppM `Lanius.Faithful.SelfPre.length_le_hb #[l] catch _ => pure none) | continue
    addFact (Name.mkSimple s!"hbp{k}") p
    k := k + 1
  -- inner values first
  let mut items : Array (Expr × Option Expr × Expr) :=
    pending.map (fun (v, c, l) => (v, some c, l)) ++ free.map (fun (v, l) => (v, none, l))
  items := items.qsort (fun a b => a.1.approxDepth.toNat < b.1.approxDepth.toNat)
  let mut done : Std.HashSet Expr := {}
  -- a value's bound may need another's through an equation: retry until none is new
  let mut progress := true
  while progress do
   progress := false
   for (v, c?, lem) in items do
    if done.contains v then continue
    dbg s!"item {v.getAppFn.constName?} {v.approxDepth} {c?.isSome}"
    let r ← withMainContext do
      let unify : Expr → TacticM Bool := fun concl => do
        let some (_, lhs, rhs) := concl.app4? ``LE.le |>.map (fun (a, _, l, r) => (a, l, r)) | return false
        match c? with
        | some c => withReducible (isDefEq rhs.appArg! c)
        | none =>
          let some a := hbArg? lhs | return false
          withReducible (isDefEq a v)
      let scan : Expr → Array Expr := fun _ => if v.isApp then v.getAppArgs else #[]
      instM? reg base lem unify scan
    let some (p, _) := r |
      if lanius.hb.debug.get (← getOptions) then logInfo m!"hb: no bound for{indentExpr v}"
      continue
    done := done.insert v
    progress := true
    reg := reg.push (v, c?.getD (mkNatLit 0))
    let nm := Name.mkSimple s!"hbf{k}"
    -- the split equations may rewrite the value's own arguments
    -- (`isTrueArm a = true`): the fact as stated stays too, for the goal's form
    let raw := Name.mkSimple s!"hbf{k}r"
    addFact raw p
    addFact nm p
    let t0 ← instantiateMVars (← inferType p)
    let ids ← withMainContext do constIdsOf t0
    let args ← simpArgs (ids ++ (← splitNames))
    evalTactic (← `(tactic| try simp only [$args,*] at $(mkIdent nm):ident))
    let same ← withMainContext do
      match (← getLCtx).findFromUserName? nm with
      | some d => return (← instantiateMVars d.type) == t0
      | none => return false
    if same then evalTactic (← `(tactic| clear $(mkIdent raw):ident))
    k := k + 1
  return reg

/-- Equations a split left, `d = C ..`: `hb (C ..) ≤ hb d`. -/
def eqnFacts : TacticM Unit := do
  let g ← getMainGoal
  let facts ← g.withContext do
    let mut out := #[]
    for d in ← getLCtx do
      if d.isImplementationDetail then continue
      let t ← instantiateMVars d.type
      let some (α, l, _) := t.eq? | continue
      unless l.getAppFn.isConst || l.isFVar do continue
      let ok ← try
          let _ ← synthInstance (← mkAppM `Lanius.Faithful.SelfPre.HB #[α])
          pure true
        catch _ => pure false
      if ok then
        let e ← mkAppM ``congrArg #[← mkAppOptM `Lanius.Faithful.SelfPre.HB.hb #[α, none], d.toExpr]
        out := out.push (← mkAppM ``Nat.le_of_eq #[← mkAppM ``Eq.symm #[e]])
    return out
  let mut k := 0
  for p in facts do
    addFact (Name.mkSimple s!"hbe{k}") p
    k := k + 1

def normSimp0 : TacticM Unit := do
  let mut args : Array (TSyntax `Lean.Parser.Tactic.simpLemma) := #[]
  for n in normNames do
    args := args.push (← `(Lean.Parser.Tactic.simpLemma| $(mkIdent n):ident))
  evalTactic (← `(tactic| try simp only [$args,*] at *))

/-- Replace the local definitions (`let`s a case split left) by their values. -/
def zetaLets : TacticM Unit := withMainContext do
  let g ← getMainGoal
  let lctx ← getLCtx
  let lets := lctx.foldl (fun acc d => if d.isLet && !d.isImplementationDetail then acc.push d.fvarId else acc) #[]
  if lets.isEmpty then return
  let t ← instantiateMVars (← g.getType)
  let t' ← zetaDeltaFVars t lets
  let mut g := g
  if t' != t then g ← g.replaceTargetDefEq t'
  for d in lctx do
    if d.isImplementationDetail || d.isLet then continue
    let ty ← instantiateMVars d.type
    unless ← isProp ty do continue
    let ty' ← zetaDeltaFVars ty lets
    if ty' != ty then g ← g.replaceLocalDeclDefEq d.fvarId ty'
  replaceMainGoal [g]

/-- Run `k` on each goal of `gs`, collecting what is left. -/
def onGoals (gs : List MVarId) (k : TacticM Unit) : TacticM Unit := do
  let mut left := []
  for g in gs do
    setGoals [g]
    k
    left := left ++ (← getGoals)
  setGoals left

/-- The goal has an `if` or a `match` left (the Lean function's, where the cost
model does not split). -/
def hasSplit (e : Expr) : MetaM Bool := do
  let env ← getEnv
  return (e.find? fun s =>
    s.isAppOf ``ite || s.isAppOf ``dite ||
      (match s.getAppFn with
       | .const n _ => isMatcherCore env n
       | _ => false)).isSome

/-- Close an arithmetic goal at the potential `base`: heights, then `omega`; if
that fails, split the Lean function's remaining cases (where the cost model does
not split) and try again in each. -/
partial def closeArith (fuel : Option Expr) (base : Expr) (depth : Nat := 0) : TacticM Unit := do
  dbg s!"closeArith {depth}"
  zetaLets
  eqnFacts
  dbg "eqns"
  hbNorm
  dbg "norm"
  if (← getGoals).isEmpty then return
  let _ ← hbFacts fuel base
  dbg "facts"
  hbNorm
  dbg "norm2"
  if (← getGoals).isEmpty then return
  let t ← withMainContext do instantiateMVars (← (← getMainGoal).getType)
  if depth < 8 && (← hasSplit t) then
    let saved ← saveState
    try
      omegaAtoms
      return
    catch _ => saved.restore
    match t.find? (·.isAppOfArity ``ite 5) with
    | some i =>
      let cs ← withMainContext (Term.exprToSyntax (i.getArg! 1))
      let h := mkIdent (← freshSplitName)
      evalTactic (← `(tactic| by_cases $h:ident : $cs))
      let gs ← getGoals
      let mut left := []
      for (g, pos) in gs.zip [true, false] do
        setGoals [g]
        if pos then evalTactic (← `(tactic| try simp only [if_pos $h:ident] at *))
        else evalTactic (← `(tactic| try simp only [if_neg $h:ident] at *))
        normSimp0
        unless (← getGoals).isEmpty do closeArith fuel base (depth + 1)
        left := left ++ (← getGoals)
      setGoals left
    | none =>
      let before ← withMainContext do return (← getLCtx).getFVarIds
      evalTactic (← `(tactic| split))
      onGoals (← getGoals) do
        let names ← nameSplitEqns before
        unless names.isEmpty do
          let args ← names.mapM fun n => `(Lean.Parser.Tactic.simpLemma| $(mkIdent n):ident)
          evalTactic (← `(tactic| try simp only [$args,*] at *))
        normSimp0
        unless (← getGoals).isEmpty do closeArith fuel base (depth + 1)
    return
  if lanius.hb.debug.get (← getOptions) then
    let g ← getMainGoal
    logInfo m!"hb: leaf{indentD g}"
  omegaAtoms

/-- Run a tactic of this file without recording info trees for its steps. Each
`evalTactic` inside would otherwise keep a tree with the goals before and after;
saving them is single-threaded at the end of the module and took most of a
GenP module's build time. -/
def quietly (x : TacticM Unit) : TacticM Unit := withEnableInfoTree false x

/-- Close `hb (f xs) ≤ M` for a function the cost model does not see, one case of
its functional induction. -/
syntax "upost_auto" term : tactic
elab_rules : tactic
  | `(tactic| upost_auto $m) => quietly do
    let g ← getMainGoal
    let base ← g.withContext (Term.elabTerm m (some (mkConst ``Nat)))
    normSimp0
    closeArith none base

/-- The pieces of `closeArith`, for looking at a goal. -/
syntax "hb_norm" : tactic
elab_rules : tactic
  | `(tactic| hb_norm) => quietly (hbNorm)
syntax "hb_norm0" : tactic
elab_rules : tactic
  | `(tactic| hb_norm0) => quietly (normSimp0)
syntax "hb_eqns" : tactic
elab_rules : tactic
  | `(tactic| hb_eqns) => quietly (eqnFacts)
/-- `omega` over the goal's and the hypotheses' atoms as variables: for the
compile side's hand proofs, whose cost atoms (`Cost_concat_of_u8 n <literal>
..`) `omega` itself compares by unfolding (a minute on `frameMemoryBytes`). -/
syntax "omega_atoms" : tactic
elab_rules : tactic
  | `(tactic| omega_atoms) => quietly (omegaAtoms)
syntax "hb_facts" term "," term : tactic
elab_rules : tactic
  | `(tactic| hb_facts $n, $m) => quietly do
    let g ← getMainGoal
    let (fuel, base) ← g.withContext do
      return (← Term.elabTerm n (some (mkConst ``Nat)), ← Term.elabTerm m (some (mkConst ``Nat)))
    let _ ← hbFacts (some fuel) base

syntax "hb_close" term "," term : tactic
elab_rules : tactic
  | `(tactic| hb_close $n, $m) => quietly do
    let g ← getMainGoal
    let (fuel, base) ← g.withContext do
      return (← Term.elabTerm n (some (mkConst ``Nat)), ← Term.elabTerm m (some (mkConst ``Nat)))
    closeArith (some fuel) base

theorem ite_intro {c : Prop} [Decidable c] {p q : Prop} (hp : c → p) (hq : ¬c → q) : if c then p else q := by
  by_cases h : c
  · rw [if_pos h]; exact hp h
  · rw [if_neg h]; exact hq h

/-- A precondition's lemma: a local hypothesis `pre_<key>` (the recursive group's
own, at the fuel below) or the constant. -/
def preLemma? (key : String) : TacticM (Option Expr) := do
  match ← lookup? (Name.mkSimple s!"pre_{key}") with
  | some l => return some l
  | none => genLookup? (Name.mkSimple s!"pre_{key}")

def preKey? (e : Expr) : Option String :=
  match e.getAppFn with
  | .const n _ =>
    let s : String := lastName n
    if s.startsWith "Pre_" then some (s.drop 4).toString else none
  | _ => none


/-- Facts on the numbers the Lean functions compute, which heights do not bound
(SelfPre/Values): `val_F xs : F xs ≤ ..` for each `F xs` in the goal or the
hypotheses, and `vals_F xs v h : ..` for each hypothesis `h : F xs = some v`. -/
def valueFacts : TacticM Unit := do
  if (← getGoals).isEmpty then return
  withMainContext do
    let env ← getEnv
    let g ← getMainGoal
    let mut ts := #[← instantiateMVars (← g.getType)]
    let mut hyps : Array (Expr × Expr) := #[]
    for d in ← getLCtx do
      if d.isImplementationDetail then continue
      let t ← instantiateMVars d.type
      ts := ts.push t
      hyps := hyps.push (d.toExpr, t)
    let mut facts : Array Expr := #[]
    let mut seen : Array Expr := #[]
    for t in ts do
      for s in subterms (fun e => e.isApp && e.getAppFn.isConst) t do
        let .const fn _ := s.getAppFn | continue
        unless (`Lanius.Mini).isPrefixOf fn do continue
        if seen.contains s then continue
        seen := seen.push s
        let nm := `Lanius.Faithful.SelfPre ++ Name.mkSimple s!"val_{lastName fn}"
        unless env.contains nm do continue
        let p := mkAppN (← constFresh nm) s.getAppArgs
        if (← isTypeCorrect p) && (← isProp (← inferType p)) then facts := facts.push p
    for (h, t) in hyps do
      let some (_, l, r) := t.eq? | continue
      -- an index that finds an element: `l[i]? = some v`
      if l.isAppOfArity ``GetElem?.getElem? 7 && r.isAppOfArity ``Option.some 2 then
        let nm := `Lanius.Faithful.SelfPre.vals_getElem
        if env.contains nm then
          let p ← try some <$> mkAppM nm #[l.getArg! 5, l.getArg! 6, r.appArg!, h] catch _ => pure none
          if let some p := p then facts := facts.push p
        continue
      let .const fn _ := l.getAppFn | continue
      unless (`Lanius.Mini).isPrefixOf fn && r.isAppOfArity ``Option.some 2 do continue
      let nm := `Lanius.Faithful.SelfPre ++ Name.mkSimple s!"vals_{lastName fn}"
      unless env.contains nm do continue
      let p := mkAppN (← constFresh nm) (l.getAppArgs ++ #[r.appArg!, h])
      if (← isTypeCorrect p) && (← isProp (← inferType p)) then facts := facts.push p
    if facts.isEmpty then return
    let mut have_ := hyps.map (·.2)
    let mut g := g
    let mut i := 0
    for p in facts do
      let ty ← instantiateMVars (← inferType p)
      if have_.contains ty then continue
      have_ := have_.push ty
      let (_, g') ← (← g.assert (Name.mkSimple s!"hval{i}") ty p).intro1P
      g := g'
      i := i + 1
    replaceMainGoal [g]

/-- Take a precondition apart and close its pieces. -/
partial def preGoal (nStx mStx : Term) : TacticM Unit := withMainContext do
  -- the fuel and the potential, read again in each goal (a split may reintroduce them)
  let fuel ← Term.elabTerm nStx (some (mkConst ``Nat))
  let base ← Term.elabTerm mStx (some (mkConst ``Nat))
  let g ← getMainGoal
  let t ← whnfR (← instantiateMVars (← g.getType))
  if t.isConstOf ``True then
    g.assign (mkConst ``True.intro)
    replaceMainGoal []
    return
  if t.isAppOfArity ``And 2 then
    let gs ← g.apply (mkConst ``And.intro)
    onGoals gs (preGoal nStx mStx)
    return
  if t.isLet then
    evalTactic (← `(tactic| intro _))
    evalTactic (← `(tactic| simp only [] at *))
    preGoal nStx mStx
    return
  if let .forallE _ ty _ _ := t then
    if ty.isConstOf ``Nat then
      evalTactic (← `(tactic| intro b' hc he))
      evalTactic (← `(tactic| subst b'))
      preGoal nStx mStx
      return
  if t.isAppOfArity ``ite 5 then
    let gs ← g.apply (← mkConstWithFreshMVarLevels ``ite_intro)
    onGoals gs do
      let h := mkIdent (← freshSplitName)
      evalTactic (← `(tactic| intro $h:ident))
      -- `hb_simp` also states numeric tests as bounds (`flDigit_eq_true`, SelfPre/Values)
      evalTactic (← `(tactic| try simp only [hb_simp, decide_eq_true_eq, decide_eq_false_iff_not, Bool.and_eq_true,
        Bool.or_eq_true, Bool.not_eq_true', not_and, not_or, Bool.not_eq_eq_eq_not, Bool.not_true] at $h:ident))
      preGoal nStx mStx
    return
  if (← matchMatcherApp? t).isSome then
    evalTactic (← `(tactic| split))
    onGoals (← getGoals) (preGoal nStx mStx)
    return
  if t.isAppOf `Lanius.Faithful.Budget.Pre_plus || t.isAppOf `Lanius.Faithful.Budget.Pre_times then
    let plus := mkIdent `Lanius.Faithful.Budget.Pre_plus
    let times := mkIdent `Lanius.Faithful.Budget.Pre_times
    evalTactic (← `(tactic| simp only [$plus:ident, $times:ident, Nat.reducePow]))
    valueFacts
    if (← getGoals).isEmpty then return
    let saved ← saveState
    let t ← withMainContext do instantiateMVars (← (← getMainGoal).getType)
    try
      closeArith (some fuel) base
      unless (← getGoals).isEmpty do throwError "pre_auto: arithmetic left"
    catch e =>
      -- a product of two values: each below `2 ^ 32`
      unless t.isAppOfArity ``LT.lt 4 && (t.getArg! 2).isAppOfArity ``HMul.hMul 6 do throw e
      saved.restore
      let gs ← (← getMainGoal).apply (← mkConstWithFreshMVarLevels ``mul_lt_two64)
      onGoals gs (closeArith (some fuel) base)
    return
  if let some key := preKey? t then
    eqnFacts
    hbNorm
    valueFacts
    if (← getGoals).isEmpty then return
    -- the call's arguments: their projections' facts
    let args ← withMainContext do
      return (← whnfR (← instantiateMVars (← (← getMainGoal).getType))).getAppArgs
    let reg ← hbFacts (some fuel) base args
    if (← getGoals).isEmpty then return
    let r ← withMainContext do
      -- looked up after the facts: `simp at *` may have replaced a local lemma
      let some lem ← preLemma? key | throwError "pre_auto: no lemma pre_{key}"
      let g ← getMainGoal
      let t ← instantiateMVars (← g.getType)
      let unify : Expr → TacticM Bool := fun concl => isDefEq concl t
      let scan : Expr → Array Expr := fun c =>
        let xs := c.getAppArgs
        if xs.size < 2 then #[] else xs.extract 1 (xs.size - 1)
      instM? reg base lem unify scan
    let some (p, _) := r | throwError "pre_auto: the premises of pre_{key} failed at{indentExpr t}"
    (← getMainGoal).assign p
    replaceMainGoal []
    return
  throwError "pre_auto: stuck at{indentExpr t}"

syntax "pre_auto" term "," term : tactic
elab_rules : tactic
  | `(tactic| pre_auto $n, $m) => quietly (preGoal n m)

/-- The first case split of a cost model's body, outermost first: an `if`'s
condition or a `match`'s scrutinee. -/
partial def firstSplit? (e : Expr) : MetaM (Option (Bool × Expr)) := do
  if e.isAppOfArity ``ite 5 then return some (true, e.getArg! 1)
  if let some m ← matchMatcherApp? e then
    if h : 0 < m.discrs.size then return some (false, m.discrs[0])
  match e with
  | .app f a =>
    match ← firstSplit? f with
    | some r => return some r
    | none => firstSplit? a
  | .mdata _ b => firstSplit? b
  | _ => return none

/-- The nullary `Inline` constants in `e` (a production's number). -/
def inlineConsts (e : Expr) : MetaM (Array Name) := do
  let mut out := #[]
  for c in subterms (fun e => e.isConst) e do
    let .const n _ := c | continue
    if (`Lanius.Mini.Inline).isPrefixOf n && !out.contains n then
      let info ← getConstInfo n
      if info.type.isConstOf ``Nat then out := out.push n
  return out

def normSimp : TacticM Unit := do
  let mut args : Array (TSyntax `Lean.Parser.Tactic.simpLemma) := #[]
  for n in normNames do
    args := args.push (← `(Lean.Parser.Tactic.simpLemma| $(mkIdent n):ident))
  evalTactic (← `(tactic| try simp only [$args,*]))

/-- The goal still splits on `c` first. -/
def stillSplits (c : Expr) : TacticM Bool := withMainContext do
  let gs ← getGoals
  if gs.isEmpty then return false
  let t ← instantiateMVars (← (← getMainGoal).getType)
  let .forallE _ prem _ _ := t | return false
  match ← firstSplit? prem with
  | some (true, c') => return c' == c
  | _ => return false

/-- Split a height lemma's cases as its cost model splits them, the Lean
function's alike, and close each. -/
partial def postGoal (fuel base : Expr) : TacticM Unit := withMainContext do
  dbg "postGoal"
  let g ← getMainGoal
  let t ← instantiateMVars (← g.getType)
  let .forallE _ prem _ _ := t | throwError "post_auto: not `cost < 2 ^ 64 → _`{indentExpr t}"
  match ← firstSplit? prem with
  | none =>
    evalTactic (← `(tactic| intro hpost))
    closeArith (some fuel) base
  | some (true, c) =>
    let cs ← Term.exprToSyntax c
    let h := mkIdent (← freshSplitName)
    evalTactic (← `(tactic| by_cases $h:ident : $cs))
    let gs ← getGoals
    let mut left := []
    for (g, pos) in gs.zip [true, false] do
      setGoals [g]
      if pos then
        evalTactic (← `(tactic| simp only [if_pos $h:ident]))
      else
        evalTactic (← `(tactic| simp only [if_neg $h:ident]))
      normSimp
      evalTactic (← `(tactic| try simp only [$h:ident]))
      normSimp
      if ← stillSplits c then throwError "post_auto: the split on{indentExpr c}\ndid not reduce"
      postGoal fuel base
      left := left ++ (← getGoals)
    setGoals left
  | some (false, d) =>
    if d.isFVar then
      let ds ← Term.exprToSyntax d
      evalTactic (← `(tactic| cases $ds:term))
    else
      let ds ← Term.exprToSyntax d
      evalTactic (← `(tactic| generalize hdiscr : $ds = discr))
      evalTactic (← `(tactic| cases discr))
    onGoals (← getGoals) do
      evalTactic (← `(tactic| try simp only []))
      normSimp
      postGoal fuel base

syntax "post_auto" term "," term : tactic
elab_rules : tactic
  | `(tactic| post_auto $n, $m) => quietly do
    let g ← getMainGoal
    let (fuel, base) ← g.withContext do
      return (← Term.elabTerm n (some (mkConst ``Nat)), ← Term.elabTerm m (some (mkConst ``Nat)))
    dbg "post_auto"
    let ics ← g.withContext do inlineConsts (← instantiateMVars (← g.getType))
    for n in ics do
      evalTactic (← `(tactic| try rw [$(mkIdent n):ident]))
    dbg "consts"
    hbNorm (consts := false)
    dbg "norm"
    normSimp
    dbg "normSimp"
    postGoal fuel base

end Lanius.Faithful.SelfPre.Tactic
