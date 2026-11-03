import Lanius.Faithful.Sim.Term
import Lanius.Faithful.Gen.SelfProg
import Std.Data.HashMap
import Std.Data.HashSet

/-! The termination annotations of the self program (`Sim/Term.lean`), and
the modules that check them.

    cd formal && lake env lean --run tools/term_gen.lean [--out DIR] ROOT...

ROOTs are function names as the certificates spell them after `fn_`
(`Gen/SelfLookFn*.lean`). Every function they call, directly or not, gets an
annotation: its rank is its strongly connected component's height in the
call graph, and for a recursive component a search picks each function's
designated argument and subrank so that the check passes (the classes of the
arguments at each call are the check's own, `effCls` and `exprCls`). The
annotations are not trusted: `Gen/SelfTerm*.lean` has the kernel decide the
check for each function, and `pcall_complete` turns that into settling.

Writes `Lanius/Faithful/Gen/SelfTermInfo.lean`, `SelfTerm<k>.lean` (chunks of
the checks) and `SelfTerm.lean` (the link, and each root's settling), or
writes them to DIR (`faithful_current.py` compares them with Gen/'s). -/

open Lanius.Mini Lanius.Faithful Lanius.Faithful.Self Lanius.Faithful.Termination

/-! ## Call sites with the classes of their arguments, as the check sees them -/

section
variable (prims : Prims) (T : TermInfo)

mutual
partial def sitesEff (A : AEnv) (W : Wit) : SrcEff → List (Nat × List SizeCls)
  | .ePure _ => []
  | .eCall c args => sitesEffs A W args ++ [(c, (effsCls prims T A args).map (SizeCls.res W))]
  | .eApply _ l r | .eDivide _ l r => sitesEff A W l ++ sitesEff A W r
  | .eNeg a | .eNot a | .eCast _ a => sitesEff A W a
  | .eIndex _ _ | .eStride _ | .arraySlice _ _ => []
  | .eIf c _ a b => sitesEff A W c ++ sitesEff A W a ++ sitesEff A W b
  | .eLet id _ a _ b => sitesEff A W a ++ sitesEff ((id, effCls prims T A a) :: A) W b
  | .eLen _ | .eStr _ _ => []
  | .eStruct _ fs | .eVariant _ _ fs => sitesEffs A W fs
  | .eMatch s ety _ bs vs => sitesEff A W s ++ sitesArms A W (effCls prims T A s) ety.typeId 0 bs vs

partial def sitesEffs (A : AEnv) (W : Wit) : List SrcEff → List (Nat × List SizeCls)
  | [] => []
  | e :: es => sitesEff A W e ++ sitesEffs A W es

partial def sitesArms (A : AEnv) (W : Wit) (k : SizeCls) (id : Nat) :
    Nat → List (List Nat) → List SrcEff → List (Nat × List SizeCls)
  | i, bs :: rest, v :: vs =>
    sitesEff (A.bindAll (bs.map (·, k.part))) (if k.isLe && !bs.isEmpty then (id, i) :: W else W) v ++
      sitesArms A W k id (i + 1) rest vs
  | _, _, _ => []
end

partial def sitesStmt (A : AEnv) (W : Wit) : SrcStmt → List (Nat × List SizeCls)
  | .let id _ value body => sitesStmt ((id, exprCls A value) :: A) W body
  | .letStruct id _ _ body | .letEnum id _ _ _ body => sitesStmt ((id, .unk) :: A) W body
  | .letCall id _ c args body =>
    (c, (args.map (exprCls A)).map (SizeCls.res W)) ::
      sitesStmt ((id, callCls prims T c (args.map (exprCls A))) :: A) W body
  | .then a b => sitesStmt A W a ++ sitesStmt ((A.after a).forget a.writes) W b
  | .if c a b => sitesStmt A W a ++ sitesStmt (match guardVar c with | some (x, k) => A.refine x k | none => A) W b
  | .letEval id _ v body => sitesEff prims T A W v ++ sitesStmt ((id, effCls prims T A v) :: A) W body
  | .ifEval c a b => sitesEff prims T A W c ++ sitesStmt A W a ++ sitesStmt A W b
  | .returnEval v | .discard v | .assert v | .setEval _ v => sitesEff prims T A W v
  | _ => []

def sitesFn (pos : List Nat) (f : SrcFunc) : List (Nat × List SizeCls) :=
  sitesStmt prims T (AEnv.bindAll [] ((paramIds f.params).zip (initCls pos f.params.length))) [] f.body
end

/-! ## The call graph -/

mutual
partial def effCalls : SrcEff → List Nat
  | .eCall c args => c :: args.flatMap effCalls
  | .eApply _ a b | .eDivide _ a b => effCalls a ++ effCalls b
  | .eNeg a | .eNot a | .eCast _ a | .eIndex _ a => effCalls a
  | .eStruct _ fs | .eVariant _ _ fs => fs.flatMap effCalls
  | .eMatch s _ _ _ vs => effCalls s ++ vs.flatMap effCalls
  | .eIf c _ a b => effCalls c ++ effCalls a ++ effCalls b
  | .eLet _ _ a _ b => effCalls a ++ effCalls b
  | .eLen _ | .eStr _ _ => []
  | .ePure _ | .eStride _ | .arraySlice _ _ => []
end

partial def stmtCalls : SrcStmt → List Nat
  | .let _ _ _ b | .letStruct _ _ _ b | .letEnum _ _ _ _ b | .letMatch _ _ _ _ _ b => stmtCalls b
  | .letCall _ _ c _ b => c :: stmtCalls b
  | .setCall _ c _ => [c]
  | .then a b | .if _ a b | .matchArm _ _ _ _ _ _ a b => stmtCalls a ++ stmtCalls b
  | .while _ a => stmtCalls a
  | .letAlloc _ _ _ b | .letLoad _ _ _ b | .letSlice _ _ _ _ b | .letIndex _ _ _ _ b => stmtCalls b
  | .letEval _ _ e b => effCalls e ++ stmtCalls b
  | .setEval _ e | .returnEval e | .discard e | .assert e | .setFieldEval _ _ e => effCalls e
  | .ifEval e a b => effCalls e ++ stmtCalls a ++ stmtCalls b
  | .whileEval e a => effCalls e ++ stmtCalls a
  | .setIndexEval _ a b => effCalls a ++ effCalls b
  | _ => []

/-- A constant: `empty()`'s shape (`ConstOk`). -/
def constOf (f : SrcFunc) : Option (SrcType × Nat) :=
  match f.body with
  | .returnEval (.eVariant ty j []) => some (ty, j)
  | _ => none

def constTab (consts : List (Nat × SrcType × Nat)) : List (Nat × Nat × Nat) :=
  consts.map fun (c, ty, j) => (c, ty.typeId, j)

/-- A decrement: `minus(a, b)`'s shape (`DecOk`). -/
def decParams (f : SrcFunc) : Option (Nat × Nat) :=
  match f.params, f.body with
  | [p, q], .then (.if (.apply .greater (.local b) (.local a)) _ .nop)
      (.return (.apply .minus (.local a') (.local b'))) =>
    if p.id == a && q.id == b && a == a' && b == b' && a != b then some (a, b) else none
  | _, _ => none

structure Tarjan where
  index : Std.HashMap Nat Nat := {}
  low : Std.HashMap Nat Nat := {}
  onStack : Std.HashSet Nat := {}
  stack : List Nat := []
  counter : Nat := 0
  sccs : Array (List Nat) := #[]

partial def popTo (v : Nat) : List Nat → List Nat → List Nat × List Nat
  | acc, [] => (acc, [])
  | acc, w :: rest => if w == v then (w :: acc, rest) else popTo v (w :: acc) rest

/-- Tarjan's algorithm: components come out callees first. -/
partial def strong (succ : Nat → List Nat) (v : Nat) : StateM Tarjan Unit := do
  modify fun s =>
    { index := s.index.insert v s.counter
      low := s.low.insert v s.counter
      counter := s.counter + 1
      stack := v :: s.stack
      onStack := s.onStack.insert v
      sccs := s.sccs }
  for w in succ v do
    let s ← get
    if !s.index.contains w then
      strong succ w
      modify fun s => { s with low := s.low.insert v (min s.low[v]! s.low[w]!) }
    else if s.onStack.contains w then
      modify fun s => { s with low := s.low.insert v (min s.low[v]! s.index[w]!) }
  let s ← get
  if s.low[v]! == s.index[v]! then
    let (comp, rest) := popTo v [] s.stack
    set { s with stack := rest, onStack := comp.foldl (fun acc x => acc.erase x) s.onStack, sccs := s.sccs.push comp }

/-- Subranks from the same-size calls of a component: the longest such chain
below each function, if there is no cycle. -/
def subranks (members : List Nat) (edges : List (Nat × Nat)) : Option (Std.HashMap Nat Nat) := Id.run do
  let mut sub : Std.HashMap Nat Nat := members.foldl (fun m f => m.insert f 0) {}
  for _ in [0:members.length + 1] do
    let mut changed := false
    for (f, g) in edges do
      if sub[f]! ≤ sub[g]! then
        sub := sub.insert f (sub[g]! + 1)
        changed := true
    if !changed then return some sub
  return none

def at' (cs : List SizeCls) (pos : List Nat) : List SizeCls := pos.map fun p => cs.getD p .unk

/-- The candidate designated positions of a function of `n` parameters: one,
then two. -/
def candidates (n : Nat) : List (List Nat) :=
  (List.range n).map ([·]) ++ (List.range n).flatMap fun i => ((List.range n).filter (i < ·)).map ([i, ·])

/-- Designated positions for a component, by backtracking: every call inside it
passes arguments of usable classes there, and the same-size calls have no
cycle. -/
partial def search (sites : Nat → List Nat → List (Nat × List SizeCls)) (members : List Nat)
    (nparams : Nat → Nat) : List Nat → Std.HashMap Nat (List Nat) →
      Option (Std.HashMap Nat (List Nat) × Std.HashMap Nat Nat)
  | [], pos =>
    let edges := members.flatMap fun f => (sites f pos[f]!).filterMap fun (g, cs) =>
      let ks := at' cs pos[g]!
      if members.contains g && !(!ks.isEmpty && ks.all SizeCls.isLt) then some (f, g) else none
    (subranks members edges).map (pos, ·)
  | f :: rest, pos =>
    (candidates (nparams f)).firstM fun p => Id.run do
      let pos' := pos.insert f p
      let bad := pos'.toList.any fun (h, ph) => (sites h ph).any fun (g, cs) =>
        match pos'[g]? with
        | some pg => members.contains g && !(at' cs pg).all SizeCls.isLe
        | none => false
      if bad then none else search sites members nparams rest pos'

def callees (sp : SrcProgram) (prims : Prims) (i : Nat) : List Nat :=
  match sp.funcs[i]? with
  | some f => ((stmtCalls f.body).filter (!prims.isPrim ·)).eraseDups
  | none => []

partial def reach (sp : SrcProgram) (prims : Prims) : List Nat → Std.HashSet Nat → Std.HashSet Nat
  | [], seen => seen
  | i :: rest, seen =>
    if seen.contains i then reach sp prims rest seen
    else reach sp prims (callees sp prims i ++ rest) (seen.insert i)

/-- The annotations of the functions the roots reach, in components callees
first, and the decrements with their parameters. -/
def annotate (sp : SrcProgram) (prims : Prims) (roots : List Nat) :
    List (Nat × TermAnn) × List (Nat × Nat × Nat) × List (Nat × SrcType × Nat) × List String := Id.run do
  let all := (reach sp prims roots {}).toList.mergeSort
  let decs := all.filterMap fun i => match sp.funcs[i]? with
    | some f => (decParams f).map fun (a, b) => (i, a, b)
    | none => none
  let consts := all.filterMap fun i => match sp.funcs[i]? with
    | some f => if prims.isPrim i then none else (constOf f).map fun (ty, j) => (i, ty, j)
    | none => none
  let T0 : TermInfo := { tab := .leaf, decs := decs.map (·.1), consts := constTab consts }
  let succ := callees sp prims
  let act : StateM Tarjan Unit := all.forM fun v => do
    let s ← get
    if !s.index.contains v then strong succ v
  let (_, st) := act.run {}
  let mut comp : Std.HashMap Nat Nat := {}
  for k in [0:st.sccs.size] do
    for f in st.sccs[k]! do comp := comp.insert f k
  let mut rank : Std.HashMap Nat Nat := {}
  let mut anns : List (Nat × TermAnn) := []
  let mut notes : List String := []
  for scc in st.sccs do
    let r := scc.foldl (fun r f => (succ f).foldl (fun r g =>
      if comp[g]! != comp[f]! then max r (rank[g]! + 1) else r) r) 0
    for f in scc do rank := rank.insert f r
    let recursive := scc.length > 1 || scc.any fun f => (succ f).contains f
    if !recursive then
      for f in scc do anns := (f, ⟨r, [], 0⟩) :: anns
      continue
    let sites := fun (f : Nat) (p : List Nat) => match sp.funcs[f]? with | some fn => sitesFn prims T0 p fn | none => []
    let nparams := fun (f : Nat) => match sp.funcs[f]? with | some fn => fn.params.length | none => 0
    match search sites scc nparams scc {} with
    | some (pos, sub) => for f in scc do anns := (f, ⟨r, pos[f]!, sub[f]!⟩) :: anns
    | none =>
      notes := s!"no annotation found for the component {scc}" :: notes
      for f in scc do anns := (f, ⟨r, [], 0⟩) :: anns
  return (anns.reverse, decs, consts, notes.reverse)

/-- The functions that reach one of `bad` in the call graph. -/
def badReach (sp : SrcProgram) (prims : Prims) (bad : List Nat) (all : List Nat) : Std.HashSet Nat := Id.run do
  -- callers of each function, then a walk up from the bad ones
  let mut callers : Std.HashMap Nat (List Nat) := {}
  for f in all do
    for g in callees sp prims f do
      callers := callers.insert g (f :: callers.getD g [])
  let mut seen : Std.HashSet Nat := {}
  let mut todo := bad
  repeat
    match todo with
    | [] => break
    | f :: rest =>
      todo := rest
      if !seen.contains f then
        seen := seen.insert f
        todo := callers.getD f [] ++ todo
  return seen

/-! ## The modules -/

def gen := "Lanius/Faithful/Gen/"

def header (imports : List String) (looks : Bool := true) : String :=
  String.join (imports.map (s!"import {·}\n")) ++
    "\n/-! Generated by formal/tools/term_gen.lean. Do not edit. -/\n\n" ++
    "namespace Lanius.Faithful.SelfTerm\n\nopen Lanius.Mini\nopen Lanius.Faithful\nopen Lanius.Faithful.Self\n" ++
    "open Lanius.Faithful.SelfRep\nopen Lanius.Faithful.Termination\n" ++ (if looks then "open Lanius.Faithful.SelfCert\n\n" else "\n")

def annText (a : TermAnn) : String := s!"⟨{a.rank}, {a.pos}, {a.sub}⟩"

def chunks {α : Type} (n : Nat) (xs : List α) : List (List α) :=
  if n = 0 then [xs] else
  let rec go (xs : List α) (fuel : Nat) : List (List α) :=
    match fuel, xs with
    | 0, _ => []
    | _, [] => []
    | fuel + 1, xs => xs.take n :: go (xs.drop n) fuel
  go xs xs.length

instance : Inhabited ATree := ⟨.leaf⟩
instance : Inhabited TermAnn := ⟨⟨0, [], 0⟩⟩

/-- A balanced tree over the sorted annotations `xs[lo:hi]`. -/
partial def mkTree (xs : Array (Nat × TermAnn)) (lo hi : Nat) : ATree :=
  if hi ≤ lo then .leaf else
  let m := (lo + hi) / 2
  .node (mkTree xs lo m) xs[m]!.1 xs[m]!.2 (mkTree xs (m + 1) hi)

partial def treeText : ATree → String
  | .leaf => "ATree.leaf"
  | .node l k a r => s!"(ATree.node {treeText l} {k} {annText a} {treeText r})"

def infoOf (anns : List (Nat × TermAnn)) (decs : List Nat) (consts : List (Nat × Nat × Nat)) : TermInfo :=
  let xs := (anns.mergeSort fun a b => a.1 ≤ b.1).toArray
  { tab := mkTree xs 0 xs.size, decs := decs, consts := consts }

def main (args : List String) : IO Unit := do
  let (out, args) := match args with
    | "--out" :: dir :: rest => (dir ++ "/", rest)
    | _ => (gen, args)
  -- names from the lookup lemmas
  let mut names : Std.HashMap Nat String := {}
  let mut index : Std.HashMap String Nat := {}
  let mut fileOf : Std.HashMap Nat Nat := {}
  let lookCount := ((← System.FilePath.readDir gen).filter fun e =>
    e.fileName.startsWith "SelfLookFn" && e.fileName.endsWith ".lean").size
  for k in [0:lookCount] do
    let text ← IO.FS.readFile s!"{gen}SelfLookFn{k}.lean"
    for line in text.splitOn "\n" do
      if line.startsWith "theorem fn_" then
        let name := ((line.drop 11).takeWhile (· != ' ')).toString
        let rest := (line.splitOn "prog.funcs[")
        if rest.length ≥ 2 then
          let i := ((rest[1]!).takeWhile Char.isDigit).toString.toNat!
          names := names.insert i name
          fileOf := fileOf.insert i k
          index := index.insert name i
  let roots := args.map fun r => index.getD r 0
  let (anns, decs, consts, notes) := annotate prog SelfRep.prims roots
  let ctab := constTab consts
  for n in notes do IO.eprintln n
  -- drop the functions that fail the check and every function that reaches one
  let info0 := infoOf anns (decs.map (·.1)) ctab
  let fails0 := anns.filterMap fun (c, a) => match prog.funcs[c]? with
    | some f => if chkFn SelfRep.prims info0 a f then none else some c
    | none => none
  let bad := badReach prog SelfRep.prims fails0 (anns.map (·.1))
  let mut anns := anns.filter fun (c, _) => !bad.contains c
  let mut dropped : List Nat := (info0.anns.map (·.1)).filter bad.contains
  repeat
    let info := infoOf anns (decs.map (·.1)) ctab
    let fails := anns.filter fun (c, a) => match prog.funcs[c]? with
      | some f => !chkFn SelfRep.prims info a f
      | none => false
    if fails.isEmpty then break
    dropped := dropped ++ fails.map (·.1)
    anns := anns.filter fun (c, _) => !(fails.map (·.1)).contains c
  if !dropped.isEmpty then
    IO.eprintln s!"{dropped.length} functions fail the check or call one that does: {dropped.map fun c => names.getD c s!"#{c}"}"
  anns := anns.mergeSort fun a b => a.1 ≤ b.1
  let info := infoOf anns (decs.map (·.1)) ctab
  let parts := chunks 40 anns
  -- the annotations
  let mut text := header ["Lanius.Faithful.Sim.TermSound", "Lanius.Faithful.Gen.SelfProg"] false
  for k in [0:parts.length] do
    text := text ++ s!"def part{k} : List (Nat × TermAnn) := [\n" ++
      ",\n".intercalate (parts[k]!.map fun (c, a) => s!"  ({c}, {annText a})") ++ "]\n\n"
  let appended := (List.range parts.length).foldr (fun k acc =>
    if acc == "" then s!"part{k}" else s!"part{k} ++ ({acc})") ""
  text := text ++ s!"noncomputable def tab : ATree := {treeText info.tab}\n\n" ++
    s!"/-- The annotations of the functions {", ".intercalate args} reach. -/\n" ++
    s!"noncomputable def info : TermInfo := \{ tab := tab, decs := {decs.map (·.1)}, consts := {ctab} }\n\n" ++
    s!"theorem info_anns : info.anns = {appended} := by decide +kernel\n\n" ++
    "end Lanius.Faithful.SelfTerm\n"
  IO.FS.writeFile s!"{out}SelfTermInfo.lean" text
  -- the checks
  let looks := (List.range lookCount).map (s!"Lanius.Faithful.Gen.SelfLookFn{·}")
  for k in [0:parts.length] do
    let files := (parts[k]!.filterMap fun (c, _) => fileOf[c]?).eraseDups.mergeSort
    let mut t := header (["Lanius.Faithful.Gen.SelfTermInfo"] ++ files.map (s!"Lanius.Faithful.Gen.SelfLookFn{·}"))
    for (c, a) in parts[k]! do
      let n := names.getD c s!"#{c}"
      t := t ++ s!"theorem ok_{n} : FnOk prog prims info ({c}, {annText a}) :=\n" ++
        s!"  fnOk_of fn_{n} (by decide +kernel)\n\n"
    t := t ++ s!"theorem chunk{k} : AllFns prog prims info part{k} :=\n  ⟨" ++
      ", ".intercalate (parts[k]!.map fun (c, _) => s!"ok_{names.getD c s!"#{c}"}") ++ ", trivial⟩\n\n" ++
      "end Lanius.Faithful.SelfTerm\n"
    IO.FS.writeFile s!"{out}SelfTerm{k}.lean" t
  -- the link
  let mut t := header (["Lanius.Faithful.Gen.SelfTermInfo"] ++ looks ++
    (List.range parts.length).map (s!"Lanius.Faithful.Gen.SelfTerm{·}"))
  let chunked := (List.range parts.length).foldr (fun k acc =>
    if acc == "" then s!"chunk{k}" else s!"AllFns.append chunk{k} ({acc})") ""
  let decProofs := decs.map fun (c, a, b) =>
    let n := names.getD c s!"#{c}"
    s!"decOk_of {a} {b} np_{n} fn_{n} rfl (by decide) rfl"
  let constProofs := consts.map fun (c, _, j) =>
    let n := names.getD c s!"#{c}"
    s!"constOk_of {j} np_{n} fn_{n} rfl rfl"
  t := t ++ "theorem consts : AllConsts prog prims info.consts :=\n  ⟨" ++
    ", ".intercalate (constProofs ++ ["trivial"]) ++ "⟩\n\n"
  t := t ++ "theorem decs : AllDecs prog prims info.decs :=\n  ⟨" ++
    ", ".intercalate decProofs ++ ", trivial⟩\n\n" ++
    "/-- The check passes for every function the roots reach. -/\n" ++
    s!"theorem termOk : TermOk prog prims info :=\n  termOk_of decs consts info_anns ({chunked})\n\n"
  let kept := (args.zip roots).filter fun (_, c) => (info.ann c).isSome
  for (r, c) in kept do
    if let some a := info.ann c then
      t := t ++ s!"/-- Every pure call of `{r}` settles. -/\n" ++
        s!"theorem settles_{r} (vs : List Lanius.Core.Value) : Settles prog prims {c} vs :=\n" ++
        s!"  pcall_complete termOk {c} {annText a} rfl vs\n\n"
  t := t ++ String.join (kept.map fun (r, _) => s!"#print axioms settles_{r}\n") ++ "\nend Lanius.Faithful.SelfTerm\n"
  IO.FS.writeFile s!"{out}SelfTerm.lean" t
  IO.println s!"{anns.length} functions, {parts.length} chunks, decrements {decs.map (·.1)}, {consts.length} constants"
