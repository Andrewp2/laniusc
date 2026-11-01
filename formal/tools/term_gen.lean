import Lanius.Faithful.Sim.TermSound
import Lanius.Faithful.Gen.SelfProg
import Std.Data.HashMap
import Std.Data.HashSet

/-! The termination annotations of the self program (`Sim/Term.lean`), and
the modules that check them.

    cd formal && lake env lean --run tools/term_gen.lean ROOT...

ROOTs are function names as the certificates spell them after `fn_`
(`Gen/SelfLookFn*.lean`). Every function they call, directly or not, gets an
annotation: its rank is its strongly connected component's height in the
call graph, and for a recursive component a search picks each function's
designated argument and subrank so that the check passes (the classes of the
arguments at each call are the check's own, `effCls` and `exprCls`). The
annotations are not trusted: `Gen/SelfTerm*.lean` has the kernel decide the
check for each function, and `pcall_complete` turns that into settling.

Writes `Lanius/Faithful/Gen/SelfTermInfo.lean`, `SelfTerm<k>.lean` (chunks of
the checks) and `SelfTerm.lean` (the link, and each root's settling). -/

open Lanius.Mini Lanius.Faithful Lanius.Faithful.Self Lanius.Faithful.Termination

/-! ## Call sites with the classes of their arguments, as the check sees them -/

section
variable (prims : Prims) (T : TermInfo)

mutual
partial def sitesEff (A : AEnv) : SrcEff → List (Nat × List SizeCls)
  | .ePure _ => []
  | .eCall c args => sitesEffs A args ++ [(c, effsCls prims T A args)]
  | .eApply _ l r | .eDivide _ l r => sitesEff A l ++ sitesEff A r
  | .eNeg a | .eNot a | .eCast _ a => sitesEff A a
  | .eIndex _ _ | .eStride _ => []
  | .eStruct _ fs | .eVariant _ _ fs => sitesEffs A fs
  | .eMatch s _ _ bs vs => sitesEff A s ++ sitesArms A (effCls prims T A s).part bs vs

partial def sitesEffs (A : AEnv) : List SrcEff → List (Nat × List SizeCls)
  | [] => []
  | e :: es => sitesEff A e ++ sitesEffs A es

partial def sitesArms (A : AEnv) (k : SizeCls) : List (List Nat) → List SrcEff → List (Nat × List SizeCls)
  | bs :: rest, v :: vs => sitesEff (A.bindAll (bs.map (·, k))) v ++ sitesArms A k rest vs
  | _, _ => []
end

partial def sitesStmt (A : AEnv) : SrcStmt → List (Nat × List SizeCls)
  | .let id _ value body => sitesStmt ((id, exprCls A value) :: A) body
  | .letStruct id _ _ body | .letEnum id _ _ _ body => sitesStmt ((id, .unk) :: A) body
  | .letCall id _ c args body =>
    (c, args.map (exprCls A)) :: sitesStmt ((id, callCls prims T c (args.map (exprCls A))) :: A) body
  | .then a b => sitesStmt A a ++ sitesStmt (A.after a) b
  | .if c a b => sitesStmt A a ++ sitesStmt (match guardVar c with | some x => A.refine x | none => A) b
  | .letEval id _ v body => sitesEff prims T A v ++ sitesStmt ((id, effCls prims T A v) :: A) body
  | .ifEval c a b => sitesEff prims T A c ++ sitesStmt A a ++ sitesStmt A b
  | .returnEval v | .discard v | .assert v => sitesEff prims T A v
  | _ => []

def sitesFn (pos : Nat) (f : SrcFunc) : List (Nat × List SizeCls) :=
  sitesStmt prims T (AEnv.bindAll [] ((paramIds f.params).zip (initCls pos f.params.length))) f.body
end

/-! ## The call graph -/

mutual
partial def effCalls : SrcEff → List Nat
  | .eCall c args => c :: args.flatMap effCalls
  | .eApply _ a b | .eDivide _ a b => effCalls a ++ effCalls b
  | .eNeg a | .eNot a | .eCast _ a | .eIndex _ a => effCalls a
  | .eStruct _ fs | .eVariant _ _ fs => fs.flatMap effCalls
  | .eMatch s _ _ _ vs => effCalls s ++ vs.flatMap effCalls
  | .ePure _ | .eStride _ => []
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

def usable (k : SizeCls) : Bool := k == .lt || k == .le || k == .nz

/-- Designated positions for a component, by backtracking: every call inside it
passes an argument of a usable class there, and the same-size calls have no
cycle. -/
partial def search (sites : Nat → Nat → List (Nat × List SizeCls)) (members : List Nat)
    (nparams : Nat → Nat) : List Nat → Std.HashMap Nat Nat →
      Option (Std.HashMap Nat Nat × Std.HashMap Nat Nat)
  | [], pos =>
    let edges := members.flatMap fun f => (sites f pos[f]!).filterMap fun (g, cs) =>
      if members.contains g && (cs.getD pos[g]! .unk) != .lt then some (f, g) else none
    (subranks members edges).map (pos, ·)
  | f :: rest, pos =>
    (List.range (nparams f)).firstM fun p => Id.run do
      let pos' := pos.insert f p
      let bad := pos'.toList.any fun (h, ph) => (sites h ph).any fun (g, cs) =>
        match pos'[g]? with
        | some pg => members.contains g && !usable (cs.getD pg .unk)
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
    List (Nat × TermAnn) × List (Nat × Nat × Nat) × List String := Id.run do
  let all := (reach sp prims roots {}).toList.mergeSort
  let decs := all.filterMap fun i => match sp.funcs[i]? with
    | some f => (decParams f).map fun (a, b) => (i, a, b)
    | none => none
  let T0 : TermInfo := { anns := [], decs := decs.map (·.1) }
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
      for f in scc do anns := (f, ⟨r, 0, 0⟩) :: anns
      continue
    let sites := fun (f p : Nat) => match sp.funcs[f]? with | some fn => sitesFn prims T0 p fn | none => []
    let nparams := fun (f : Nat) => match sp.funcs[f]? with | some fn => fn.params.length | none => 0
    match search sites scc nparams scc {} with
    | some (pos, sub) => for f in scc do anns := (f, ⟨r, pos[f]!, sub[f]!⟩) :: anns
    | none =>
      notes := s!"no annotation found for the component {scc}" :: notes
      for f in scc do anns := (f, ⟨r, 0, 0⟩) :: anns
  return (anns.reverse, decs, notes.reverse)

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

def main (args : List String) : IO Unit := do
  -- names from the lookup lemmas
  let mut names : Std.HashMap Nat String := {}
  let mut index : Std.HashMap String Nat := {}
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
          index := index.insert name i
  let roots := args.map fun r => index.getD r 0
  let (anns, decs, notes) := annotate prog SelfRep.prims roots
  for n in notes do IO.eprintln n
  let info : TermInfo := { anns := anns, decs := decs.map (·.1) }
  let mut failed := 0
  for (c, a) in anns do
    if let some f := prog.funcs[c]? then
      if !chkFn SelfRep.prims info a f then
        IO.eprintln s!"check fails: {names.getD c s!"#{c}"} ({c})"
        failed := failed + 1
  if failed > 0 then throw (IO.userError s!"{failed} functions fail the check")
  let parts := chunks 40 anns
  -- the annotations
  let mut text := header ["Lanius.Faithful.Sim.TermSound", "Lanius.Faithful.Gen.SelfProg"] false
  for k in [0:parts.length] do
    text := text ++ s!"def part{k} : List (Nat × TermAnn) := [\n" ++
      ",\n".intercalate (parts[k]!.map fun (c, a) => s!"  ({c}, {annText a})") ++ "]\n\n"
  let appended := (List.range parts.length).foldr (fun k acc =>
    if acc == "" then s!"part{k}" else s!"part{k} ++ ({acc})") ""
  text := text ++ s!"/-- The annotations of the functions {", ".intercalate args} reach. -/\n" ++
    s!"def info : TermInfo := \{ anns := {appended}, decs := {decs.map (·.1)} }\n\n" ++
    "end Lanius.Faithful.SelfTerm\n"
  IO.FS.writeFile s!"{gen}SelfTermInfo.lean" text
  -- the checks
  let looks := (List.range lookCount).map (s!"Lanius.Faithful.Gen.SelfLookFn{·}")
  for k in [0:parts.length] do
    let mut t := header (["Lanius.Faithful.Gen.SelfTermInfo"] ++ looks)
    for (c, a) in parts[k]! do
      let n := names.getD c s!"#{c}"
      t := t ++ s!"theorem ok_{n} : FnOk prog prims info ({c}, {annText a}) :=\n" ++
        s!"  fnOk_of fn_{n} (by decide +kernel)\n\n"
    t := t ++ s!"theorem chunk{k} : AllFns prog prims info part{k} :=\n  ⟨" ++
      ", ".intercalate (parts[k]!.map fun (c, _) => s!"ok_{names.getD c s!"#{c}"}") ++ ", trivial⟩\n\n" ++
      "end Lanius.Faithful.SelfTerm\n"
    IO.FS.writeFile s!"{gen}SelfTerm{k}.lean" t
  -- the link
  let mut t := header (["Lanius.Faithful.Gen.SelfTermInfo"] ++ looks ++
    (List.range parts.length).map (s!"Lanius.Faithful.Gen.SelfTerm{·}"))
  let chunked := (List.range parts.length).foldr (fun k acc =>
    if acc == "" then s!"chunk{k}" else s!"AllFns.append chunk{k} ({acc})") ""
  let decProofs := decs.map fun (c, a, b) =>
    let n := names.getD c s!"#{c}"
    s!"decOk_of {a} {b} np_{n} fn_{n} rfl (by decide) rfl"
  t := t ++ "theorem decs : AllDecs prog prims info.decs :=\n  ⟨" ++
    ", ".intercalate decProofs ++ ", trivial⟩\n\n" ++
    "/-- The check passes for every function the roots reach. -/\n" ++
    s!"theorem termOk : TermOk prog prims info :=\n  termOk_of decs ({chunked})\n\n"
  for (r, c) in args.zip roots do
    if let some a := info.ann c then
      t := t ++ s!"/-- Every pure call of `{r}` settles. -/\n" ++
        s!"theorem settles_{r} (vs : List Lanius.Core.Value) : Settles prog prims {c} vs :=\n" ++
        s!"  pcall_complete termOk {c} {annText a} rfl vs\n\n"
  t := t ++ String.join (args.map (s!"#print axioms settles_{·}\n")) ++ "\nend Lanius.Faithful.SelfTerm\n"
  IO.FS.writeFile s!"{gen}SelfTerm.lean" t
  IO.println s!"{anns.length} functions, {parts.length} chunks, decrements {decs.map (·.1)}"
