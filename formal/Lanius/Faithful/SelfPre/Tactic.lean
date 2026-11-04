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

/-! The normal forms' `↔` lemmas as equations, as `simp` would state them: `simp`
makes an auxiliary lemma of the current theorem for each `↔` it is given, so a
simp set made once and kept (`simpCtx`) must not contain one. -/
theorem max_le_eq' {a b c : Nat} : (max a b ≤ c) = (a ≤ c ∧ b ≤ c) := propext max_le_iff'
theorem max_add_le_eq' {a b k c : Nat} : (max a b + k ≤ c) = (a + k ≤ c ∧ b + k ≤ c) := propext max_add_le_iff'
theorem decide_eq_false_eq_not {p : Prop} {x : Decidable p} : (@decide p x = false) = ¬p :=
  propext decide_eq_false_iff_not
theorem not_and_eq {a b : Prop} : (¬(a ∧ b)) = (a → ¬b) := propext not_and
theorem not_or_eq {p q : Prop} : (¬(p ∨ q)) = (¬p ∧ ¬q) := propext not_or
theorem eq_self_eq_true {α : Sort u} (a : α) : (a = a) = True := propext (eq_self_iff_true a)

/-- The conditions' normal form: `Bool` tests as propositions. -/
def normNames : Array Name := #[`decide_eq_true_eq, ``decide_eq_false_eq_not, `Bool.and_eq_true, `Bool.or_eq_true,
  `Bool.not_eq_true', `Bool.not_eq_false', ``not_and_eq, ``not_or_eq, `true_and, `and_true, `false_and, `and_false,
  `true_or, `or_true, `false_or, `or_false, `Bool.false_eq_true, `Bool.true_eq_false, `Bool.false_and,
  `Bool.true_and, `Bool.and_false, `Bool.and_true, `Bool.false_or, `Bool.true_or, `Bool.or_false, `Bool.or_true,
  `Bool.not_true, `Bool.not_false, `if_true, `if_false, `ite_true, `ite_false, `dite_true, `dite_false, `not_true_eq_false, `not_false_eq_true, ``eq_self_eq_true,
  `decide_true, `decide_false]

theorem Bool.not_eq_eq_eq_not_eq {a b : Bool} : ((!a) = b) = (a = !b) := propext Bool.not_eq_eq_eq_not

/-- A precondition's test as a hypothesis: `hb_simp` also states numeric tests as
bounds (`flDigit_eq_true`, SelfPre/Values). Eq forms only (see `normNames`). -/
def ifNames : Array Name := #[`decide_eq_true_eq, ``decide_eq_false_eq_not, `Bool.and_eq_true,
  `Bool.or_eq_true, `Bool.not_eq_true', ``not_and_eq, ``not_or_eq, ``Bool.not_eq_eq_eq_not_eq, `Bool.not_true]

/-- A byte literal as the Lean functions write it (`72`), not as the cost models
do (`UInt8.ofNat 72`): the compile side's byte lists. -/
theorem uint8_ofNat_lit (n : Nat) : UInt8.ofNat (no_index (OfNat.ofNat n)) = (OfNat.ofNat n : UInt8) := rfl

/-- The heights' normal form: `hb` of a constructor by its parts, `max` on the
left of `≤` as a conjunction. -/
def hbNormNames : Array Name := #[``max_le_eq', ``max_add_le_eq', ``Nat.add_assoc, ``BitVec.ofNat_eq_ofNat,
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

register_option lanius.hb.run : Nat := {
  defValue := 0
  descr := "the current pre_auto/post_auto run, for its cache of proved premises (internal)"
}

/-- The simp sets this process built, by their constants (`` `_hb `` first for the
`hb_simp` set): `mkSimpContext` elaborates every lemma, which was most of the
time of each of the normalizations (GenP: about 210 s of 370). -/
initialize simpBase : IO.Ref (Std.HashMap (Array Name) (Simp.Context × Simp.SimprocsArray)) ← IO.mkRef {}

/-- The context of `simp only [hb_simp (when `hb`), consts.., locals..]`: the constants'
part made once per process, the local equations `locals` added to it. -/
def simpCtx (hb : Bool) (consts : Array Name) (locals : Array FVarId := #[]) (fresh := false)
    (terms : Array Expr := #[]) : TacticM (Simp.Context × Simp.SimprocsArray) := do
  let key := (if hb then #[`_hb] else #[]) ++ consts
  let base ← simpBase.get
  let cached := if fresh then none else base[key]?
  let (ctx, sp) ← match cached with
    | some b =>
      -- a definition's equation lemmas, made by another theorem's `simp`: here too
      let env ← getEnv
      for c in consts do
        if (env.find? c).any (·.isDefinition) then
          let _ ← getEqnsFor? c
      pure b
    | none => do
      let mut args : Array (TSyntax `Lean.Parser.Tactic.simpLemma) := #[]
      if hb then args := args.push (← `(Lean.Parser.Tactic.simpLemma| hb_simp))
      for n in consts do
        args := args.push (← `(Lean.Parser.Tactic.simpLemma| $(mkIdent n):ident))
      let stx ← `(tactic| simp only [$args,*])
      let { ctx, simprocs, .. } ← withLCtx {} {} (mkSimpContext stx (eraseLocal := false))
      simpBase.modify (·.insert key (ctx, simprocs))
      pure (ctx, simprocs)
  if locals.isEmpty && terms.isEmpty then return (ctx, sp)
  let thms := ctx.simpTheorems
  let mut st := thms[0]!
  for f in locals do
    for t in ← mkSimpTheoremFromExpr (.fvar f) #[] (mkFVar f) (config := ctx.indexConfig) do
      st := st.addSimpTheorem t
  let mut i := 0
  for e in terms do
    for t in ← mkSimpTheoremFromExpr (.other (Name.mkSimple s!"term{i}")) #[] e (config := ctx.indexConfig) do
      st := st.addSimpTheorem t
    i := i + 1
  return (ctx.setSimpTheorems (thms.set! 0 st), sp)

/-- `simpGoal` with one cache for the hypotheses and the target (`simpGoal` starts
each afresh): a cost body is in the goal and in `Cost < 2 ^ 64` alike. No local
simp lemmas (`simpGoal` erases each hypothesis's own from its context). -/
def simpGoalShared (mvarId : MVarId) (ctx : Simp.Context) (simprocs : Simp.SimprocsArray)
    (simplifyTarget : Bool) (fvarIdsToSimp : Array FVarId) (cache : Simp.Cache := {}) :
    MetaM (Option MVarId × Simp.Cache) :=
  mvarId.withContext do
    mvarId.checkNotAssigned `simp
    let mut st : Simp.State := { cache }
    let mut mvarIdNew := mvarId
    let mut toAssert := #[]
    let mut replaced := #[]
    for fvarId in fvarIdsToSimp do
      let localDecl ← fvarId.getDecl
      let type ← instantiateMVars localDecl.type
      let (r, st') ← simpCore type ctx simprocs none st
      st := st'
      match r.proof? with
      | some _ => match (← applySimpResult mvarIdNew (mkFVar fvarId) type r) with
        | none => return (none, st.cache)
        | some (value, type) => toAssert := toAssert.push { userName := localDecl.userName, type := type, value := value }
      | none =>
        if r.expr.isFalse then
          mvarIdNew.assign (← mkFalseElim (← mvarIdNew.getType) (mkFVar fvarId))
          return (none, st.cache)
        mvarIdNew ← mvarIdNew.replaceLocalDeclDefEq fvarId r.expr
        replaced := replaced.push fvarId
    if simplifyTarget then
      let target ← instantiateMVars (← mvarIdNew.getType)
      let (r, st') ← simpCore target ctx simprocs none st
      st := st'
      if r.expr.isTrue then
        match r.proof? with
        | some proof => mvarIdNew.assign (← mkOfEqTrue proof)
        | none => mvarIdNew.assign (mkConst ``True.intro)
        return (none, st.cache)
      mvarIdNew ← applySimpResultToTarget mvarIdNew target r
    let (_, mvarIdNew') ← mvarIdNew.assertHypotheses toAssert
    mvarIdNew := mvarIdNew'
    let toClear := fvarIdsToSimp.filter fun fvarId => !replaced.contains fvarId
    mvarIdNew ← mvarIdNew.tryClearMany toClear
    return (some mvarIdNew, st.cache)

/-- By run (`lanius.hb.run`) and simp set (`simpCtx`'s key), `simp`'s cache: the
goals of a run share most of their hypotheses, normalized already. `simp only`
by these sets rewrites unconditionally (no hypothesis is in a result's proof),
so a result holds wherever its term is. -/
initialize simpCaches : IO.Ref (Std.HashMap Nat (IO.Ref (Std.HashMap (Array Name) Simp.Cache))) ←
  IO.mkRef {}

/-- `try simp only [..] at hs ⊢` (`hs` all the hypotheses when `none`) by `simpCtx`. -/
def simpAt (hb : Bool) (consts : Array Name) (locals : Array FVarId := #[])
    (hs : Option (Array FVarId) := none) (target := true) (terms : Array Expr := #[]) :
    TacticM Unit := withMainContext do
  let g ← getMainGoal
  let fvs ← match hs with
    | some hs => pure hs
    | none => g.getNondepPropHyps
  let run (fresh : Bool) : TacticM Unit := do
    let (ctx, sp) ← simpCtx hb consts locals fresh terms
    if locals.isEmpty && terms.isEmpty then
      let key := (if hb then #[`_hb] else #[]) ++ consts
      let ref? := (← simpCaches.get)[lanius.hb.run.get (← getOptions)]?
      let cache ← match ref? with
        | some r => pure (((← r.get)[key]?).getD {})
        | none => pure {}
      let (g'?, cache) ← simpGoalShared g ctx sp target fvs cache
      if let some r := ref? then r.modify (·.insert key cache)
      match g'? with
      | none => replaceMainGoal []
      | some g' => replaceMainGoal [g']
    else
      let (r, _) ← simpGoal g ctx sp (simplifyTarget := target) (fvarIdsToSimp := fvs)
      match r with
      | none => replaceMainGoal []
      | some (_, g') => replaceMainGoal [g']
  try run false
  catch e =>
    let msg ← e.toMessageData.toString
    if lanius.hb.debug.get (← getOptions) then IO.eprintln s!"simpAt: {msg}"
    -- a kept simp set naming another theorem's auxiliary lemma: made again here
    if (msg.splitOn "Unknown constant").length > 1 then
      try run true catch _ => pure ()

/-- Normalize the heights in the goal and the hypotheses (and unfold the nullary
definitions, when `consts`). -/
def hbNorm (consts : Bool := true) : TacticM Unit := do
  let ids ← if consts then inlineIds else pure #[]
  simpAt true (hbNormNames ++ normNames ++ ids)

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
  else if let some i := atoms.idxOf? e then some ((Lin.zero n).set! i 1)
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

/-- Prove arithmetic goals by linear certificates where the search finds them. -/
register_option lanius.hb.slots : Bool := {
  defValue := false
  descr := "also use the lowering's slot facts (`slots_<f>`, `slotsSome_<f>`, SelfPre/EvalSlots)"
}

register_option lanius.hb.cert : Bool := {
  defValue := true
  descr := "pre_auto and post_auto prove a goal the hypothesis search covers by SelfPre.LinCert.cert"
}

/-! ### Linear certificates

When the search finds the hypotheses, the goal follows from them by
`SelfPre.LinCert.cert`: a check of numerals the kernel evaluates, in place of an
`omega` proof. The terms are reflected as `LTm`s over the atoms, so each
hypothesis and the goal are used as they stand (`LTm.den` unfolds to them). -/

def lcName (s : String) : Name := (`Lanius.Faithful.SelfPre.LinCert).str s
def ltmC (s : String) : Expr := mkConst ((`Lanius.Faithful.SelfPre.LinCert.LTm).str s)

/-- The `LTm` of a `Nat` term `linOf` reads. -/
partial def ltmOf (atoms : Array Expr) (e : Expr) : Option Expr :=
  if let some k := natLit? e then some (mkApp (ltmC "lit") (mkRawNatLit k))
  else if let some i := atoms.idxOf? e then some (mkApp (ltmC "atom") (mkRawNatLit i))
  else if e.isAppOfArity ``HAdd.hAdd 6 then
    return mkApp2 (ltmC "add") (← ltmOf atoms (e.getArg! 4)) (← ltmOf atoms (e.getArg! 5))
  else if e.isAppOfArity ``HMul.hMul 6 then
    match natLit? (e.getArg! 4), natLit? (e.getArg! 5) with
    | some k, _ => return mkApp2 (ltmC "mulL") (mkRawNatLit k) (← ltmOf atoms (e.getArg! 5))
    | _, some k => return mkApp2 (ltmC "mulR") (← ltmOf atoms (e.getArg! 4)) (mkRawNatLit k)
    | none, none => none
  else if e.isAppOfArity ``Nat.succ 1 then
    return mkApp2 (ltmC "add") (← ltmOf atoms e.appArg!) (mkApp (ltmC "lit") (mkRawNatLit 1))
  else if arithHead e then none
  else match atoms.idxOf? e with
    | some i => some (mkApp (ltmC "atom") (mkRawNatLit i))
    | none => none

/-- A constraint `L ≤ R`: its linear forms, its `LTm`s, a proof (up to unfolding). -/
structure Con where
  l : Lin
  r : Lin
  lt : Expr
  rt : Expr
  pf : Expr
  ty : Expr
  deriving Inhabited

/-- The constraints a hypothesis `pf : p` gives, as `constraintsOf` reads them. -/
partial def consOf (atoms : Array Expr) (pf p : Expr) : Array Con :=
  let n := atoms.size
  let one := (Lin.zero n).set! n 1
  let lit1 := mkApp (ltmC "lit") (mkRawNatLit 1)
  if p.isAppOfArity ``And 2 then
    let a := p.appFn!.appArg!
    let b := p.appArg!
    consOf atoms (mkApp3 (mkConst ``And.left) a b pf) a ++ consOf atoms (mkApp3 (mkConst ``And.right) a b pf) b
  else if (p.isAppOfArity ``LE.le 4 || p.isAppOfArity ``LT.lt 4) && isNatTy (p.getArg! 0) then
    match linOf atoms (p.getArg! 2), linOf atoms (p.getArg! 3), ltmOf atoms (p.getArg! 2), ltmOf atoms (p.getArg! 3) with
    | some l, some r, some lt, some rt =>
      if p.isAppOfArity ``LE.le 4 then #[⟨l, r, lt, rt, pf, p⟩]
      else #[⟨l.add one, r, mkApp2 (ltmC "add") lt lit1, rt, pf, p⟩]
    | _, _, _, _ => #[]
  else if p.isAppOfArity ``Eq 3 && isNatTy (p.getArg! 0) then
    let a := p.getArg! 1
    let b := p.getArg! 2
    match linOf atoms a, linOf atoms b, ltmOf atoms a, ltmOf atoms b with
    | some l, some r, some lt, some rt =>
      let le := mkConst ``Nat.le_of_eq
      let leT (x y : Expr) := mkApp4 (mkConst ``LE.le [0]) (mkConst ``Nat) (mkConst ``instLENat) x y
      #[⟨l, r, lt, rt, mkApp3 le a b pf, leT a b⟩,
        ⟨r, l, rt, lt, mkApp3 le b a (mkApp4 (mkConst ``Eq.symm [1]) (mkConst ``Nat) a b pf), leT b a⟩]
    | _, _, _, _ => #[]
  else #[]

/-- The truncated subtractions of a proposition's arithmetic (not inside atoms). -/
partial def arithSubs (e : Expr) (acc : Array Expr) : Array Expr :=
  if e.isAppOfArity ``And 2 || e.isAppOfArity ``Or 2 || e.isAppOfArity ``Iff 2 then
    arithSubs e.appArg! (arithSubs e.appFn!.appArg! acc)
  else if e.isAppOfArity ``Not 1 then arithSubs e.appArg! acc
  else if e.isAppOfArity ``LE.le 4 || e.isAppOfArity ``LT.lt 4 then
    arithSubs (e.getArg! 3) (arithSubs (e.getArg! 2) acc)
  else if e.isAppOfArity ``Eq 3 then arithSubs (e.getArg! 2) (arithSubs (e.getArg! 1) acc)
  else if e.isAppOfArity ``HSub.hSub 6 && (e.getArg! 0).isConstOf ``Nat then
    let acc := if acc.contains e then acc else acc.push e
    arithSubs (e.getArg! 5) (arithSubs (e.getArg! 4) acc)
  else if arithHead e then
    if e.isAppOfArity ``Nat.succ 1 then arithSubs e.appArg! acc
    else arithSubs e.appArg! (arithSubs (e.getArg! (e.getAppNumArgs - 2)) acc)
  else acc


/-- A certificate proof of `goal` (`≤`, `<` and their conjunctions) from `hyps`, if
the search finds one for each conjunct. -/
partial def certProof? (atoms0 : Array Expr) (goal : Expr) (hyps : Array (Expr × Expr)) : Option Expr := do
  -- truncated subtractions as atoms, each with its facts
  let subs := (#[goal] ++ hyps.map (·.2)).foldl (fun acc t => arithSubs t acc) #[]
  let atoms := subs.foldl (fun acc s => if acc.contains s then acc else acc.push s) atoms0
  let leT (x y : Expr) := mkApp4 (mkConst ``LE.le [0]) (mkConst ``Nat) (mkConst ``instLENat) x y
  let addN (x y : Expr) := mkApp6 (mkConst ``HAdd.hAdd [0, 0, 0]) (mkConst ``Nat) (mkConst ``Nat) (mkConst ``Nat)
    (mkApp2 (mkConst ``instHAdd [0]) (mkConst ``Nat) (mkConst ``instAddNat)) x y
  let mut facts : Array (Expr × Expr) := #[]
  for sub in subs do
    let a := sub.getArg! 4
    let c := sub.getArg! 5
    facts := facts.push (mkApp2 (mkConst (lcName "sub_le'")) a c, leT sub a)
    facts := facts.push (mkApp2 (mkConst (lcName "le_sub_add'")) a c, leT a (addN sub c))
    for (pf, t) in hyps do
      if t.isAppOfArity ``LE.le 4 && t.getArg! 2 == c && t.getArg! 3 == a then
        facts := facts.push (mkApp3 (mkConst (lcName "sub_add_le_of_le")) a c pf, leT (addN sub c) a)
      else if t.isAppOfArity ``LT.lt 4 && t.getArg! 2 == c && t.getArg! 3 == a then
        facts := facts.push (mkApp3 (mkConst (lcName "sub_add_le_of_lt")) a c pf, leT (addN sub c) a)
  let cons := (hyps ++ facts).foldl (fun acc (pf, t) => acc ++ consOf atoms pf t) #[]
  let cs := cons.mapIdx fun i c => (c.l, c.r, i)
  let vs := atoms.foldr (fun a acc => mkApp3 (mkConst ``List.cons [0]) (mkConst ``Nat) a acc)
    (mkApp (mkConst ``List.nil [0]) (mkConst ``Nat))
  -- each subtraction atom's facts `s + c ≤ a` and `s ≤ a`, by constraint
  let factOf (nm : String) (a c : Expr) : Option Nat :=
    cons.findIdx? fun k => k.pf.isAppOf (lcName nm) && k.pf.getAppNumArgs ≥ 2 &&
      k.pf.getArg! 0 == a && k.pf.getArg! 1 == c
  let subInfo : Array (Nat × Option Nat × Option Nat) := subs.filterMap fun sub =>
    (atoms.idxOf? sub).map fun j =>
      let a := sub.getArg! 4
      let c := sub.getArg! 5
      (j, (factOf "sub_add_le_of_lt" a c).orElse fun _ => factOf "sub_add_le_of_le" a c, factOf "sub_le'" a c)
  -- a left side's subtractions `a - c` replaced by `a`: with its `c` where the left
  -- side has it (`a - c + c ≤ a`), else alone (`a - c ≤ a`)
  let rec unchain (l : Lin) (acc : Array Nat) : Nat → Lin × Array Nat
    | 0 => (l, acc)
    | fuel + 1 =>
      match subInfo.find? (fun (j, _, _) => l[j]! > 0) with
      | none => (l, acc)
      | some (_, add?, le?) =>
        let step (i : Nat) : Option Lin :=
          let l' := l.sub cons[i]!.l
          if l'.nonneg then some (l'.add cons[i]!.r) else none
        match add?.bind fun i => (step i).map (·, i) with
        | some (l', i) => unchain l' (acc.push i) fuel
        | none => match le?.bind fun i => (step i).map (·, i) with
          | some (l', i) => unchain l' (acc.push i) fuel
          | none => (l, acc)
  let ltmTy := mkConst (lcName "LTm")
  let pairTy := mkApp2 (mkConst ``Prod [0, 0]) ltmTy ltmTy
  let rec go (p : Expr) : Option Expr := do
    if p.isAppOfArity ``And 2 then
      let a := p.appFn!.appArg!
      let b := p.appArg!
      return mkApp4 (mkConst ``And.intro) a b (← go a) (← go b)
    unless (p.isAppOfArity ``LE.le 4 || p.isAppOfArity ``LT.lt 4) && isNatTy (p.getArg! 0) do none
    let gc ← (consOf atoms (mkConst ``True.intro) p)[0]?
    -- a budget chain takes two steps a level (`b₁ = b - c`, then `b - c + c ≤ b`):
    -- taken first, without search, then the search for the rest
    let (l1, u1) := unchain gc.l #[] 64
    let first : Option (Array Nat) := ((certify cs l1 gc.r 16 u1).run' 200 : Id _)
    let used ← first.orElse fun _ => ((certify cs gc.l gc.r 16 #[]).run' 200 : Id _)
    let sel := used.map (cons[·]!)
    -- the hypotheses' list and `AllLe vs` of it, from the last
    let (hs, hh) := sel.foldr (fun c (hs, hh) =>
      (mkApp3 (mkConst ``List.cons [0]) pairTy (mkApp4 (mkConst ``Prod.mk [0, 0]) ltmTy ltmTy c.lt c.rt) hs,
       mkApp4 (mkConst ``And.intro) c.ty (mkApp2 (mkConst (lcName "AllLe")) vs hs) c.pf hh))
      (mkApp (mkConst ``List.nil [0]) pairTy, mkConst ``True.intro)
    let hc := mkApp2 (mkConst ``Eq.refl [1]) (mkConst ``Bool) (mkConst ``Bool.true)
    return mkAppN (mkConst (lcName "cert")) #[vs, hs, gc.lt, gc.rt, hh, hc]
  go goal

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

/-- The arithmetic hypotheses of the current context and the atoms of `goal` and
them, or `none` when `goal` is not arithmetic. -/
def arithContext (goal : Expr) : MetaM (Option (Array Expr × Array (Expr × Expr))) := do
  let some atoms0 := propAtoms goal #[] | return none
  let mut atoms := atoms0
  let mut hyps : Array (Expr × Expr) := #[]
  for d in ← getLCtx do
    if d.isImplementationDetail then continue
    let t ← instantiateMVars d.type
    unless ← isProp t do continue
    if let some as := propAtoms t atoms then
      atoms := as
      hyps := hyps.push (d.toExpr, t)
  return some (atoms, hyps)

/-- A certificate proof of `goal` (`LinCert.cert`) from the hypotheses `hyps`, over
variables for the atoms and the hypotheses it uses, then applied to them: the
kernel then unfolds `LTm.den` against variables, never against an atom (it would
unfold a cost model's call first). -/
def certClosed? (atomsArr : Array Expr) (goal : Expr) (hyps : Array (Expr × Expr)) : MetaM (Option Expr) := do
  let some p := certProof? atomsArr goal hyps | return none
  let used := hyps.filter fun (h, _) => h.isFVar && p.containsFVar h.fvarId!
  let closed ← withLocalDeclsDND (atomsArr.mapIdx fun i _ => (Name.mkSimple s!"a{i}", mkConst ``Nat)) fun xs => do
    let abst (e : Expr) : Expr := e.replace fun s =>
      match atomsArr.idxOf? s with
      | some i => some xs[i]!
      | none => none
    withLocalDeclsDND (used.mapIdx fun i (_, t) => (Name.mkSimple s!"h{i}", abst t)) fun hs => do
      let p' := (abst p).replaceFVars (used.map (·.1)) hs
      mkLambdaFVars (xs ++ hs) p'
  return some (mkAppN (mkAppN closed atomsArr) (used.map (·.1)))

/-- Take apart the context's conjunctions that are not arithmetic as a whole (a split's
`(b = true ∧ 0 < x) ∧ x < k`), so that their arithmetic parts are hypotheses. -/
partial def splitMixed : TacticM Unit := do
  let g ← getMainGoal
  let some h ← g.withContext (do
      for d in ← getLCtx do
        if d.isImplementationDetail then continue
        let t ← instantiateMVars d.type
        if t.isAppOfArity ``And 2 && (propAtoms t #[]).isNone then return some d.fvarId
      return none) | return
  let gs ← g.cases h
  replaceMainGoal (gs.toList.map (·.mvarId))
  splitMixed

/-- Prove the main goal by `omega` over its and the hypotheses' atoms. -/
def omegaAtoms : TacticM Unit := do
  splitMixed
  withMainContext do
  let g ← getMainGoal
  let goal ← instantiateMVars (← g.getType)
  dbg "omegaAtoms"
  let some (atomsArr, hyps) ← arithContext goal |
    if lanius.hb.debug.get (← getOptions) then IO.eprintln s!"omegaAtoms: not arithmetic"
    evalTactic (← `(tactic| omega))
  dbg s!"atoms {atomsArr.size}"
  if lanius.hb.cert.get (← getOptions) then
    if let some p ← certClosed? atomsArr goal hyps then
      dbg "cert"
      g.assign p
      replaceMainGoal []
      return
  if lanius.hb.debug.get (← getOptions) then
    IO.eprintln s!"OMEGA {← ppExpr goal}"
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

/-- The premises one tactic run has proved, by run (`lanius.hb.run`): sibling goals
share most of their context and ask the same premises (let_first: 3,364 premises
asked again of 7,338). With each proof, the free variables it uses (in context
order), their types and whether they are hypotheses. -/
abbrev ArithCache := Std.HashMap Expr (Expr × Array (FVarId × Expr × Bool))
/-- By run, a reference of the run's own: the runs of a module's theorems go on
in parallel, and one shared map would make them wait on each other. -/
initialize arithCache : IO.Ref (Std.HashMap Nat (IO.Ref ArithCache)) ← IO.mkRef {}
initialize runCounter : IO.Ref Nat ← IO.mkRef 0

register_option lanius.hb.prof : Bool := {
  defValue := false
  descr := "pre_auto and post_auto print their time by phase at the end of each run"
}

/-- By run, the time (ns) spent in each phase, when `lanius.hb.prof`. -/
initialize profRefs : IO.Ref (Std.HashMap Nat (IO.Ref (Std.HashMap String Nat))) ← IO.mkRef {}

/-- `x`, its time added to phase `k` (nested phases count in both). -/
def timed {α : Type} (k : String) (x : TacticM α) : TacticM α := do
  unless lanius.hb.prof.get (← getOptions) do return ← x
  let t0 ← IO.monoNanosNow
  let h0 ← IO.getNumHeartbeats
  try x finally
    let t1 ← IO.monoNanosNow
    let h1 ← IO.getNumHeartbeats
    if let some r := (← profRefs.get)[lanius.hb.run.get (← getOptions)]? then
      -- the heartbeats too (`k@`): the times vary with the machine's load
      r.modify fun m => (m.insert k (m.getD k 0 + (t1 - t0))).insert (k ++ "@") (m.getD (k ++ "@") 0 + (h1 - h0))

/-- The lowering's slot facts of the terms of `e` (`lanius.hb.slots`, SelfPre/EvalSlots):
`slots_<f> xs` for each `f xs`, `slots_getElem_variants` for an index, and a split's
type's size (`SrcType.size x = SrcType.size (C ..)` for each `x = C ..` in `hyps`). -/
def slotFacts (es : Array Expr) (hyps : Array (Expr × Expr)) : MetaM (Array Expr) := do
  let env ← getEnv
  let mut facts : Array Expr := #[]
  let mut seen : Array Expr := #[]
  for t in es do
    for s in subterms (fun e => e.isApp && e.getAppFn.isConst && !e.hasLooseBVars) t do
      let .const fn _ := s.getAppFn | continue
      if seen.contains s then continue
      if (`Lanius.Mini).isPrefixOf fn || (`Lanius.Faithful.SelfPre).isPrefixOf fn then
        let nm := `Lanius.Faithful.SelfPre ++ Name.mkSimple s!"slots_{lastName fn}"
        if env.contains nm then
          seen := seen.push s
          -- (a function of another type with the same last name: not type-correct)
          let p := mkAppN (← constFresh nm) s.getAppArgs
          if ← (try (do return (← isTypeCorrect p) && (← isProp (← inferType p))) catch _ => pure false) then
            facts := facts.push p
      else if s.isAppOfArity ``GetElem?.getElem? 7 then
        seen := seen.push s
        let p ← try some <$> mkAppM `Lanius.Faithful.SelfPre.slots_getElem_variants #[s.getArg! 5, s.getArg! 6]
          catch _ => pure none
        if let some p := p then facts := facts.push p
  for (h, t) in hyps do
    let some (ty, _, r) := t.eq? | continue
    unless ty.isConstOf `Lanius.Mini.SrcType do continue
    let .const c _ := r.getAppFn | continue
    unless env.isConstructor c do continue
    let p ← try some <$> mkCongrArg (mkConst `Lanius.Mini.SrcType.size) h catch _ => pure none
    if let some p := p then facts := facts.push p
  return facts

/-- The slot facts (`slotFacts`) of the goal's terms and the context's type splits, as
hypotheses in their normal form. -/
def addSlotFacts : TacticM Unit := do
  -- two rounds: a fact's normal form can have terms of its own (`sizes [t]` is `t.size`)
  for round in [0, 1] do
    if (← getGoals).isEmpty then return
    let g ← getMainGoal
    let facts ← g.withContext do
      let mut eqs : Array (Expr × Expr) := #[]
      let mut mine : Array Expr := #[]
      for d in ← getLCtx do
        if d.isImplementationDetail then continue
        let t ← instantiateMVars d.type
        if d.userName == `hslot then mine := mine.push t
        if let some (sty, _, _) := t.eq? then
          if sty.isConstOf `Lanius.Mini.SrcType then eqs := eqs.push (d.toExpr, t)
      let gt ← instantiateMVars (← g.getType)
      let es := if round == 0 then #[gt] else mine
      let fs ← slotFacts es eqs
      -- (the second round's new facts only)
      let mut out := #[]
      for p in fs do
        let t ← inferType p
        unless mine.contains t do out := out.push p
      return out
    if facts.isEmpty then return
    let mut goal := g
    let mut hs : Array FVarId := #[]
    for p in facts do
      let (h, m') ← (← goal.withContext do goal.assert `hslot (← inferType p) p).intro1P
      goal := m'
      hs := hs.push h
    replaceMainGoal [goal]
    simpAt true (hbNormNames ++ normNames ++ #[``Nat.reducePow]) (hs := some hs) (target := false)

/-- Prove `ty` in the current context: heights normalized, then a certificate or `omega`. -/
def proveArith0? (ty : Expr) : TacticM (Option Expr) := do
  -- most premises are already linear over their atoms: a certificate, before `simp`
  if lanius.hb.cert.get (← getOptions) then
    let ty ← instantiateMVars ty
    let c? ← timed "ar.cert" do
      let some (atoms, hyps) ← arithContext ty | return none
      certClosed? atoms ty hyps
    if let some p := c? then
      dbg "cert0"
      return some p
  let g ← mkFreshExprMVar ty
  let saved ← saveState
  try
    let gs ← Tactic.run g.mvarId! (withoutRecover do
      timed "ar.simp" (simpAt true (hbNormNames ++ normNames ++ #[``Nat.reducePow]) (hs := some #[]))
      -- the slot facts of the premise's own terms, which the context's facts do not cover
      if lanius.hb.slots.get (← getOptions) then timed "ar.slots" addSlotFacts
      dbg "simped"
      for g in ← getGoals do
        setGoals [g]
        timed "ar.omega" omegaAtoms)
    let p ← instantiateMVars g
    if gs.isEmpty && !p.hasSorry && !p.hasSyntheticSorry then return some p
    saved.restore
    return none
  catch _ =>
    saved.restore
    return none

/-- A cached proof `p` in the current context: its free variables still there, or,
for a hypothesis gone (a sibling goal's facts are its own), one of the same type
(the same proposition, so `p` keeps its type). -/
def reuseProof? (p : Expr) (fvs : Array (FVarId × Expr × Bool)) : MetaM (Option Expr) := do
  let lctx ← getLCtx
  let mut olds : Array Expr := #[]
  let mut news : Array Expr := #[]
  let mut byType : Option (Std.HashMap Expr FVarId) := none
  for (f, t, isHyp) in fvs do
    if lctx.contains f then continue
    unless isHyp do return none
    if byType.isNone then
      let mut m : Std.HashMap Expr FVarId := {}
      for d in lctx do
        unless d.isImplementationDetail do
          m := m.insert (← instantiateMVars d.type) d.fvarId
      byType := some m
    let t' := t.replaceFVars olds news
    let some g := byType.bind (·[t']?) | return none
    olds := olds.push (mkFVar f)
    news := news.push (mkFVar g)
  return some (if olds.isEmpty then p else p.replaceFVars olds news)

/-- The `hb`-bounded values in `e`: the arguments of `hb`. -/
def hbTerms (e : Expr) : Array Expr :=
  (subterms (fun e => (hbArg? e).isSome) e).filterMap hbArg?

/-- An open statement (`Lanius.Open.*`, a `Prop` constant): the compile side's pre
lemmas assume some, which callers pass on from their own hypotheses. -/
def openProp (t : Expr) : Bool :=
  match t.getAppFn.constName? with
  | some n => (`Lanius.Open).isPrefixOf n
  | none => false

/-- `proveArith0?`, or the proof this run found for the same premise. -/
def proveArith? (ty : Expr) : TacticM (Option Expr) := do
  let run := lanius.hb.run.get (← getOptions)
  let key ← instantiateMVars ty
  -- a premise bounding closed values (`hb [115, ..] ≤ M`) that failed: it fails
  -- again (no case split bounds `M` from below), and a failure costs `omega` twice
  let closed := !key.hasMVar && !(hbTerms key).isEmpty && (hbTerms key).all (!·.hasFVar)
  let failKey := mkApp (mkConst `Lanius.Faithful.SelfPre.Tactic.failKey) key
  if run != 0 && !key.hasMVar then
    let cache ← (do match (← arithCache.get)[run]? with
        | some r => return some (← r.get)
        | none => return none)
    if closed && (cache.bind (·[failKey]?)).isSome then
      dbg "known failure"
      return none
    if let some (p, fvs) := cache.bind (·[key]?) then
      if let some p ← reuseProof? p fvs then
        dbg "hit"
        return some p
      dbg "stale"
  dbg "miss"
  let t0 ← IO.monoNanosNow
  let r ← timed "arith" (proveArith0? ty)
  if r.isNone then
    if closed && run != 0 then
      if let some c := (← arithCache.get)[run]? then c.modify (·.insert failKey (mkConst ``False, #[]))
    if let some pr := (← profRefs.get)[run]? then
      let t1 ← IO.monoNanosNow
      pr.modify fun m => (m.insert "arith.fail" (m.getD "arith.fail" 0 + (t1 - t0))).insert "n.fail" (m.getD "n.fail" 0 + 1000000)
      let s := toString (← ppExpr key)
      IO.eprintln s!"FAIL {(t1 - t0) / 1000000} {(s.replace "\n" " ").take 300}"
  if let some p := r then
    if run != 0 && !key.hasMVar && !p.hasMVar then
      let lctx ← getLCtx
      let ds := ((collectFVars {} p).fvarIds.filterMap lctx.find?).qsort (·.index < ·.index)
      let fvs ← ds.mapM fun d => do
        let t ← instantiateMVars d.type
        return (d.fvarId, t, ← isProp t)
      if let some r := (← arithCache.get)[run]? then r.modify (·.insert key (p, fvs))
  return r

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

/-- The equations of the context (`l = r`). -/
def contextEqs : MetaM (Array (Expr × Expr)) := do
  let mut eqs : Array (Expr × Expr) := #[]
  for d in ← getLCtx do
    if d.isImplementationDetail then continue
    let t ← instantiateMVars d.type
    if let some (_, l, r) := t.eq? then eqs := eqs.push (l, r)
  return eqs

/-- The values `scan` is computed from: `scan` and, through the equations `eqs`
the case splits left (`d = C .. y ..`), the `d` a variable of it was taken from. -/
def upstreamWith (eqs : Array (Expr × Expr)) (scan : Array Expr) : Array Expr := Id.run do
  let mut terms := scan
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

/-- `upstreamWith` the context's equations. -/
def upstream (scan : Array Expr) : MetaM (Array Expr) := do
  return upstreamWith (← contextEqs) scan

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
      -- an open statement the lemma assumes (`COMPILE_OVERRIDES`): the caller's own hypothesis
      if openProp t then
        if let some h ← findLocalDeclWithType? t then
          m.mvarId!.assign (mkFVar h)
          continue
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

/-- The facts' normal forms this run found: by the fact and the case splits'
equations in the context (sibling goals ask the same facts again), the normal
form, its equation, and the free variables that uses (as `arithCache`'s). -/
abbrev FactCache := Std.HashMap Expr (Expr × Option Expr × Array (FVarId × Expr × Bool))
initialize factCache : IO.Ref (Std.HashMap Nat (IO.Ref FactCache)) ← IO.mkRef {}

/-- A fact `t0`'s normal form (`simp only` by the heights' and the definitions'
lemmas and the split equations) and its equation (`none`: unchanged up to
`Eq.mp`'s need), or `none` when the result is `False` (the goal closes: left to
the tactic). -/
def normFact? (t0 : Expr) : TacticM (Option (Expr × Option Expr)) := withMainContext do
  let run := lanius.hb.run.get (← getOptions)
  let names ← splitNames
  let lctx ← getLCtx
  let mut eqTys : Array Expr := #[]
  for nm in names do
    if let some d := lctx.findFromUserName? nm then eqTys := eqTys.push (← instantiateMVars d.type)
  let key := mkAppN (mkConst `Lanius.Faithful.SelfPre.Tactic.factKey) (#[t0] ++ eqTys)
  if run != 0 && !key.hasMVar then
    if let some (t1, eq?, fvs) ← (do match (← factCache.get)[run]? with
        | some r => return (← r.get)[key]?
        | none => return none) then
      match eq? with
      | none => return some (t1, none)
      | some h =>
        if let some h ← reuseProof? h fvs then
          dbg "fhit"
          return some (t1, some h)
  dbg "fmiss"
  let ids ← constIdsOf t0
  let locals := names.filterMap fun nm => (lctx.findFromUserName? nm).map (·.fvarId)
  let simpIt (fresh : Bool) : TacticM Simp.Result := do
    let (ctx, simprocs) ← timed "nf.ctx" (simpCtx true (hbNormNames ++ normNames ++ ids) locals fresh)
    return (← timed "nf.simp" (Meta.simp t0 ctx simprocs)).1
  let r ← try simpIt false
    catch e =>
      -- a kept simp set naming another theorem's auxiliary lemma: made again here
      unless ((← e.toMessageData.toString).splitOn "Unknown constant").length > 1 do throw e
      simpIt true
  let t1 ← instantiateMVars r.expr
  timed (if t1 == t0 then "nf.same" else "nf.changed") (pure ())
  if t1.isConstOf ``False then return none
  let eq? ← r.proof?.mapM instantiateMVars
  if eq?.any (·.hasMVar) then return none
  if run != 0 && !key.hasMVar then
    let fvs ← match eq? with
      | none => pure #[]
      | some h => do
        let ds := ((collectFVars {} h).fvarIds.filterMap lctx.find?).qsort (·.index < ·.index)
        ds.mapM fun d => do
          let t ← instantiateMVars d.type
          return (d.fvarId, t, ← isProp t)
    if let some r := (← factCache.get)[run]? then r.modify (·.insert key (t1, eq?, fvs))
  return some (t1, eq?)

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
  -- the items an item's arguments are taken from (through the split equations):
  -- those first, or its premises fail for want of their bounds
  let eqs ← withMainContext contextEqs
  let deps : Array (Array Expr) := items.map fun (v, _, _) =>
    let up := upstreamWith eqs (if v.isApp then v.getAppArgs else #[])
    items.filterMap fun (v', _, _) => if v' != v && up.contains v' then some v' else none
  -- a value's bound may need another's through an equation: retry until none is
  -- new (then once with the items waiting on others too)
  let mut force := false
  let mut progress := true
  while progress do
   progress := false
   let mut waited := false
   for ((v, c?, lem), ds) in items.zip deps do
    if done.contains v then continue
    if !force && ds.any (fun d => !done.contains d) then
      waited := true
      continue
    dbg s!"item {v.getAppFn.constName?} {v.approxDepth} {c?.isSome}"
    let r ← timed "hf.inst" <| withMainContext do
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
    let t0 ← withMainContext do instantiateMVars (← inferType p)
    match ← timed "hf.normFact" (normFact? t0) with
    | some (t1, eq?) =>
      if t1 == t0 then
        addFact nm p
      else
        addFact raw p
        unless t1.isConstOf ``True do
          addFact nm (match eq? with
            | some h => mkApp4 (mkConst ``Eq.mp [0]) t0 t1 h p
            | none => p)
    | none =>
      addFact raw p
      addFact nm p
      let ids ← withMainContext do constIdsOf t0
      let args ← simpArgs (ids ++ (← splitNames))
      evalTactic (← `(tactic| try simp only [$args,*] at $(mkIdent nm):ident))
      let same ← withMainContext do
        match (← getLCtx).findFromUserName? nm with
        | some d => return (← instantiateMVars d.type) == t0
        | none => return false
      if same then evalTactic (← `(tactic| clear $(mkIdent raw):ident))
    k := k + 1
   if progress then force := false
   else if waited && !force then
     force := true
     progress := true
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

def normSimp0 : TacticM Unit := simpAt false normNames

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
  timed "ca.zeta" zetaLets
  timed "ca.eqns" eqnFacts
  dbg "eqns"
  timed "ca.norm1" hbNorm
  dbg "norm"
  if (← getGoals).isEmpty then return
  let before ← withMainContext do return (← getLCtx).getFVarIds
  let _ ← timed "ca.facts" (hbFacts fuel base)
  dbg "facts"
  -- the new facts only: the rest is as the `hbNorm` above left it (and the
  -- facts `hbFacts` normalized itself are so too)
  let fresh ← withMainContext do
    let mut out := #[]
    for d in ← getLCtx do
      if d.isImplementationDetail || before.contains d.fvarId then continue
      if ← isProp d.type then out := out.push d.fvarId
    return out
  unless fresh.isEmpty do
    let ids ← inlineIds
    timed "ca.norm2" (simpAt true (hbNormNames ++ normNames ++ ids) (hs := some fresh) (target := false))
  dbg "norm2"
  if (← getGoals).isEmpty then return
  let t ← withMainContext do instantiateMVars (← (← getMainGoal).getType)
  if depth < 8 && (← hasSplit t) then
    let saved ← saveState
    try
      timed "ca.omegaTry" omegaAtoms
      return
    catch _ => saved.restore
    match t.find? (·.isAppOfArity ``ite 5) with
    | some i =>
      let cs ← withMainContext (Term.exprToSyntax (i.getArg! 1))
      let h := mkIdent (← freshSplitName)
      timed "ca.bycases" (evalTactic (← `(tactic| by_cases $h:ident : $cs)))
      -- a condition whose constant `simp` unfolded in it but not in its `Decidable`
      -- instance (`Nat.decLe evalSlotLimit x`) is not type-correct at the instances'
      -- transparency, and `simp` would leave its `if`: unfold the constant everywhere
      let nullary ← withMainContext do
        let mut out : Array Name := #[]
        for c in subterms (fun e => e.isConst) i do
          let .const n _ := c | continue
          if out.contains n || !(`Lanius.Mini).isPrefixOf n then continue
          let some (.defnInfo info) := (← getEnv).find? n | continue
          unless info.type.isForall do out := out.push n
        return out
      for n in nullary do
        evalTactic (← `(tactic| all_goals try (delta $(mkIdent n):ident at *)))
      let gs ← getGoals
      let mut left := []
      for (g, pos) in gs.zip [true, false] do
        setGoals [g]
        timed "ca.ifsimp" do
          if pos then evalTactic (← `(tactic| try simp only [if_pos $h:ident] at *))
          else evalTactic (← `(tactic| try simp only [if_neg $h:ident] at *))

        timed "ca.norm0" normSimp0
        unless (← getGoals).isEmpty do closeArith fuel base (depth + 1)
        left := left ++ (← getGoals)
      setGoals left
    | none =>
      let before ← withMainContext do return (← getLCtx).getFVarIds
      timed "ca.split" (evalTactic (← `(tactic| split)))
      onGoals (← getGoals) do
        let names ← nameSplitEqns before
        let hs ← withMainContext do
          let lctx ← getLCtx
          return names.filterMap fun n => (lctx.findFromUserName? n).map (·.fvarId)
        timed "ca.eqsimp" (simpAt false normNames (locals := hs))
        unless (← getGoals).isEmpty do closeArith fuel base (depth + 1)
    return
  if lanius.hb.debug.get (← getOptions) then
    let g ← getMainGoal
    logInfo m!"hb: leaf{indentD g}"
  timed "ca.omegaLeaf" omegaAtoms

/-- Run a tactic of this file without recording info trees for its steps. Each
`evalTactic` inside would otherwise keep a tree with the goals before and after;
saving them is single-threaded at the end of the module and took most of a
GenP module's build time. -/
def quietly (x : TacticM Unit) : TacticM Unit := do
  let run ← runCounter.modifyGet fun n => (n + 1, n + 1)
  let ar ← IO.mkRef ({} : ArithCache)
  let fr ← IO.mkRef ({} : FactCache)
  arithCache.modify (·.insert run ar)
  factCache.modify (·.insert run fr)
  simpCaches.modify (·.insert run (← IO.mkRef {}))
  let prof := lanius.hb.prof.get (← getOptions)
  let pr ← IO.mkRef ({} : Std.HashMap String Nat)
  if prof then profRefs.modify (·.insert run pr)
  let t0 ← IO.monoNanosNow
  let h0 ← IO.getNumHeartbeats
  try
    withTheReader Core.Context (fun c => { c with options := lanius.hb.run.set c.options run })
      (withEnableInfoTree false x)
  finally
    arithCache.modify (·.erase run)
    factCache.modify (·.erase run)
    simpCaches.modify (·.erase run)
    if prof then
      let t1 ← IO.monoNanosNow
      let h1 ← IO.getNumHeartbeats
      pr.modify fun m => (m.insert "total" (t1 - t0)).insert "total@" (h1 - h0)
      profRefs.modify (·.erase run)
      let decl := (← Term.getDeclName?).getD .anonymous
      let parts := (← pr.get).toList.map fun (k, v) => s!" {k}={v / 1000}"
      IO.eprintln s!"PROFR {decl} {t0 / 1000000} {t1 / 1000000}{String.join parts}"

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
hypotheses, and `vals_F xs v h : ..` for each hypothesis `h : F xs = some v`; an open
statement (`openProp`) either lemma assumes next is the context's hypothesis of it. -/
def valueFacts : TacticM Unit := do
  if (← getGoals).isEmpty then return
  withMainContext do
    let env ← getEnv
    let slots := lanius.hb.slots.get (← getOptions)
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
        -- `val_<T>_<f>` for `T.f` (several types have a `number` or a `size`), else `val_<f>`
        let nmT := `Lanius.Faithful.SelfPre ++ Name.mkSimple s!"val_{lastName fn.getPrefix}_{lastName fn}"
        let nm := if env.contains nmT then nmT
          else `Lanius.Faithful.SelfPre ++ Name.mkSimple s!"val_{lastName fn}"
        -- and the slots' bound (`slots_<f>`, SelfPre/EvalSlots)
        let nmS := `Lanius.Faithful.SelfPre ++ Name.mkSimple s!"slots_{lastName fn}"
        for nm in (if slots then [nm, nmS] else [nm]) do
          unless env.contains nm do continue
          let mut p := mkAppN (← constFresh nm) s.getAppArgs
          -- an open statement the lemma assumes first: the context's hypothesis of it
          if ← (try isTypeCorrect p catch _ => pure false) then
            if let .forallE _ d _ _ ← whnfR (← inferType p) then
              if openProp d then
                if let some hd ← findLocalDeclWithType? d then p := mkApp p (mkFVar hd)
          if ← (try (do return (← isTypeCorrect p) && (← isProp (← inferType p))) catch _ => pure false) then
            facts := facts.push p
    -- a projection's type sizes are at most its structure's (`ts_le_<S>_<f>`, SelfPre/TS.lean)
    let mut seenP : Array Expr := #[]
    for t in ts do
      for s in subterms (fun e => e.isApp && e.getAppFn.isConst && !e.hasLooseBVars) t do
        let .const fn _ := s.getAppFn | continue
        let some info := env.getProjectionFnInfo? fn | continue
        unless s.getAppNumArgs == info.numParams + 1 do continue
        let nm := `Lanius.Faithful.SelfPre ++ Name.mkSimple s!"ts_le_{lastName fn.getPrefix}_{lastName fn}"
        unless env.contains nm do continue
        if seenP.contains s then continue
        seenP := seenP.push s
        facts := facts.push (mkApp (← constFresh nm) s.appArg!)
    -- an index into a list whose elements carry their own bounds (`val_getElem_<T>`, the compile side's)
    for t in ts do
      for s in subterms (fun e => e.isAppOfArity ``GetElem?.getElem? 7) t do
        if seen.contains s then continue
        seen := seen.push s
        for nm in [`Lanius.Faithful.SelfPre.val_getElem_sigs, `Lanius.Faithful.SelfPre.val_getElem_types,
            `Lanius.Faithful.SelfPre.val_getElem_variants] ++
            (if slots then [`Lanius.Faithful.SelfPre.slots_getElem_variants] else []) do
          unless env.contains nm do continue
          let p ← try some <$> mkAppM nm #[s.getArg! 5, s.getArg! 6] catch _ => pure none
          if let some p := p then facts := facts.push p
    -- a value matched against a constructor: its type sizes are the constructor's
    if env.contains `Lanius.Faithful.SelfPre.TS.ts then
      for (h, t) in hyps do
        let some (ty, _, r) := t.eq? | continue
        let .const c _ := r.getAppFn | continue
        unless env.isConstructor c && (`Lanius.Mini).isPrefixOf c do continue
        let p ← try
            let f ← mkAppOptM `Lanius.Faithful.SelfPre.TS.ts #[some ty, none]
            some <$> mkCongrArg f h
          catch _ => pure none
        if let some p := p then facts := facts.push p
    for (h, t) in hyps do
      let some (_, l, r) := t.eq? | continue
      -- an index that finds an element: `l[i]? = some v`
      if l.isAppOfArity ``GetElem?.getElem? 7 && r.isAppOfArity ``Option.some 2 then
        for nm in [`Lanius.Faithful.SelfPre.vals_getElem, `Lanius.Faithful.SelfPre.vals_getElem_sigs,
            `Lanius.Faithful.SelfPre.vals_getElem_types, `Lanius.Faithful.SelfPre.vals_getElem_variants] do
          if env.contains nm then
            let p ← try some <$> mkAppM nm #[l.getArg! 5, l.getArg! 6, r.appArg!, h] catch _ => pure none
            if let some p := p then facts := facts.push p
        continue
      let .const fn _ := l.getAppFn | continue
      unless (`Lanius.Mini).isPrefixOf fn && r.isAppOfArity ``Option.some 2 do continue
      let nmT := `Lanius.Faithful.SelfPre ++ Name.mkSimple s!"vals_{lastName fn.getPrefix}_{lastName fn}"
      let nm := if env.contains nmT then nmT
        else `Lanius.Faithful.SelfPre ++ Name.mkSimple s!"vals_{lastName fn}"
      let nmS := `Lanius.Faithful.SelfPre ++ Name.mkSimple s!"slotsSome_{lastName fn}"
      for nm in (if slots then [nm, nmS] else [nm]) do
        unless env.contains nm do continue
        let mut p := mkAppN (← constFresh nm) (l.getAppArgs ++ #[r.appArg!, h])
        -- an open statement the lemma assumes: the context's hypothesis of it
        if ← isTypeCorrect p then
          if let .forallE _ d _ _ ← whnfR (← inferType p) then
            if openProp d then
              if let some hd ← findLocalDeclWithType? d then p := mkApp p (mkFVar hd)
        if (← isTypeCorrect p) && (← isProp (← inferType p)) then facts := facts.push p
    if facts.isEmpty then return
    let mut have_ := hyps.map (·.2)
    let mut g := g
    let mut i := 0
    let mut tsFacts : Array FVarId := #[]
    for p in facts do
      let ty ← instantiateMVars (← inferType p)
      if have_.contains ty then continue
      have_ := have_.push ty
      let (h, g') ← (← g.assert (Name.mkSimple s!"hval{i}") ty p).intro1P
      g := g'
      i := i + 1
      if (ty.find? (·.isConstOf `Lanius.Faithful.SelfPre.TS.ts)).isSome then tsFacts := tsFacts.push h
    replaceMainGoal [g]
    -- the type sizes' facts in the form the goals' `hb_simp` gives them (`tySlots`)
    unless tsFacts.isEmpty do
      simpAt true hbNormNames (hs := some tsFacts) (target := false)

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
      timed "pg.ifsimp" do
        let hv ← withMainContext do return (← getLCtx).findFromUserName? h.getId |>.map (·.fvarId)
        simpAt true ifNames (hs := some hv.toArray) (target := false)
      preGoal nStx mStx
    return
  if (← matchMatcherApp? t).isSome then
    timed "pg.split" (evalTactic (← `(tactic| split)))
    onGoals (← getGoals) (preGoal nStx mStx)
    return
  if t.isAppOf `Lanius.Faithful.Budget.Pre_plus || t.isAppOf `Lanius.Faithful.Budget.Pre_times then
    let plus := mkIdent `Lanius.Faithful.Budget.Pre_plus
    let times := mkIdent `Lanius.Faithful.Budget.Pre_times
    evalTactic (← `(tactic| simp only [$plus:ident, $times:ident, Nat.reducePow]))
    timed "pg.values" valueFacts
    if (← getGoals).isEmpty then return
    let saved ← saveState
    let t ← withMainContext do instantiateMVars (← (← getMainGoal).getType)
    try
      timed "pg.arith" (closeArith (some fuel) base)
      unless (← getGoals).isEmpty do throwError "pre_auto: arithmetic left"
    catch e =>
      -- a product of two values: each below `2 ^ 32`
      unless t.isAppOfArity ``LT.lt 4 && (t.getArg! 2).isAppOfArity ``HMul.hMul 6 do throw e
      saved.restore
      let gs ← (← getMainGoal).apply (← mkConstWithFreshMVarLevels ``mul_lt_two64)
      onGoals gs (closeArith (some fuel) base)
    return
  if let some key := preKey? t then
    timed "pg.eqns" eqnFacts
    timed "pg.norm" hbNorm
    timed "pg.values" valueFacts
    if (← getGoals).isEmpty then return
    -- the call's arguments: their projections' facts
    let args ← withMainContext do
      return (← whnfR (← instantiateMVars (← (← getMainGoal).getType))).getAppArgs
    let reg ← timed "pg.facts" (hbFacts (some fuel) base args)
    if (← getGoals).isEmpty then return
    let r ← timed "pg.inst" <| withMainContext do
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

def normSimp : TacticM Unit := simpAt false normNames (hs := some #[])

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
    timed "po.bycases" (evalTactic (← `(tactic| by_cases $h:ident : $cs)))
    let gs ← getGoals
    let mut left := []
    for g in gs do
      setGoals [g]
      -- `simp only [if_pos h]`, `simp only [h]` and the normal form, by one
      -- `simp` (`h` rewrites the condition to `True` or `False`)
      timed "po.ifsimp" do
        let hv ← withMainContext do return (← getLCtx).findFromUserName? h.getId |>.map (·.fvarId)
        simpAt false normNames (locals := hv.toArray) (hs := some #[])
      if ← stillSplits c then throwError "post_auto: the split on{indentExpr c}\ndid not reduce"
      postGoal fuel base
      left := left ++ (← getGoals)
    setGoals left
  | some (false, d) =>
    timed "po.cases" do
      if d.isFVar then
        let ds ← Term.exprToSyntax d
        evalTactic (← `(tactic| cases $ds:term))
      else
        let ds ← Term.exprToSyntax d
        evalTactic (← `(tactic| generalize hdiscr : $ds = discr))
        evalTactic (← `(tactic| cases discr))
    onGoals (← getGoals) do
      -- `simp only []` (the matches on the case's constructor) and the normal form
      timed "po.norm" normSimp
      postGoal fuel base

syntax "post_auto" term "," term : tactic
elab_rules : tactic
  | `(tactic| post_auto $n, $m) => quietly do
    let g ← getMainGoal
    let (fuel, base) ← g.withContext do
      return (← Term.elabTerm n (some (mkConst ``Nat)), ← Term.elabTerm m (some (mkConst ``Nat)))
    dbg "post_auto"
    let ics ← g.withContext do inlineConsts (← instantiateMVars (← g.getType))
    timed "pa.consts" do
      for n in ics do
        evalTactic (← `(tactic| try rw [$(mkIdent n):ident]))
    dbg "consts"
    timed "pa.norm" (hbNorm (consts := false))
    dbg "norm"
    timed "pa.normSimp" normSimp
    dbg "normSimp"
    postGoal fuel base

end Lanius.Faithful.SelfPre.Tactic
