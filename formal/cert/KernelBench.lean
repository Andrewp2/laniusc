import Lanius.Faithful.SelfPre.LinCert
import Lean

/-! Lean's kernel on the existing certificates: each distinct obligation of
gen.py as a plain theorem `∀ a.., Lᵢ ≤ Rᵢ → .. → L ≤ R` whose proof is the term
pre_auto builds (`LinCert.cert` applied to the atoms, the hypotheses and
`Eq.refl true`), type-checked by the kernel alone (no elaboration), timed. -/

open Lean Meta

namespace CertSpike.Kernel

def ltm (n : String) : Expr := mkConst ((`Lanius.Faithful.SelfPre.LinCert.LTm).str n)

partial def ofJson (xs : Array Expr) (j : Json) : Except String (Expr × Expr) := do
  let a ← j.getArr?
  let tag ← a[0]!.getStr?
  match tag with
  | "a" => let i ← a[1]!.getNat?; return (mkApp (ltm "atom") (mkRawNatLit i), xs[i]!)
  | "k" => let k ← a[1]!.getNat?; return (mkApp (ltm "lit") (mkRawNatLit k), mkNatLit k)
  | "+" =>
    let (l1, p1) ← ofJson xs a[1]!
    let (l2, p2) ← ofJson xs a[2]!
    return (mkApp2 (ltm "add") l1 l2, mkNatAdd p1 p2)
  | _ =>
    let k ← a[1]!.getNat?
    let (l, p) ← ofJson xs a[2]!
    return (mkApp2 (ltm "mulL") (mkRawNatLit k) l, mkNatMul (mkNatLit k) p)

def ex {α} : Except String α → MetaM α
  | .ok a => pure a
  | .error e => throwError e

def lc (s : String) : Name := (`Lanius.Faithful.SelfPre.LinCert).str s

def decl (i : Nat) (o : Json) : MetaM Declaration := do
  let n ← ex (o.getObjValAs? Nat "atoms")
  let hyps ← ex ((o.getObjValD "hyps").getArr?)
  let goal ← ex ((o.getObjValD "goal").getArr?)
  withLocalDeclsDND ((Array.range n).map fun k => (Name.mkSimple s!"a{k}", mkConst ``Nat)) fun xs => do
    let hs ← hyps.mapM fun h => do
      let p ← ex (h.getArr?)
      let (la, pa) ← ex (ofJson xs p[0]!)
      let (lb, pb) ← ex (ofJson xs p[1]!)
      return (la, lb, mkNatLE pa pb)
    let (gl, gp) ← ex (ofJson xs goal[0]!)
    let (rl, rp) ← ex (ofJson xs goal[1]!)
    withLocalDeclsDND (hs.mapIdx fun j (_, _, t) => (Name.mkSimple s!"h{j}", t)) fun hvs => do
      let ltmTy := mkConst (lc "LTm")
      let pairTy := mkApp2 (mkConst ``Prod [0, 0]) ltmTy ltmTy
      let vs := xs.foldr (fun a acc => mkApp3 (mkConst ``List.cons [0]) (mkConst ``Nat) a acc)
        (mkApp (mkConst ``List.nil [0]) (mkConst ``Nat))
      let hl := hs.foldr (fun (a, b, _) acc => mkApp3 (mkConst ``List.cons [0]) pairTy
        (mkApp4 (mkConst ``Prod.mk [0, 0]) ltmTy ltmTy a b) acc) (mkApp (mkConst ``List.nil [0]) pairTy)
      -- AllLe vs hs, as And.intro over the plain hypotheses
      let rec allLe (j : Nat) : Expr × Expr :=
        if h : j < hs.size then
          let (ty, pf) := allLe (j + 1)
          (mkApp2 (mkConst ``And) hs[j].2.2 ty, mkApp4 (mkConst ``And.intro) hs[j].2.2 ty hvs[j]! pf)
        else (mkConst ``True, mkConst ``True.intro)
      termination_by hs.size - j
      let hh := (allLe 0).2
      let hc := mkApp2 (mkConst ``Eq.refl [1]) (mkConst ``Bool) (mkConst ``Bool.true)
      let pf := mkAppN (mkConst (lc "cert")) #[vs, hl, gl, rl, hh, hc]
      let ty ← mkForallFVars (xs ++ hvs) (mkNatLE gp rp)
      let val ← mkLambdaFVars (xs ++ hvs) pf
      return .thmDecl { name := Name.mkSimple s!"kobl{i}", levelParams := [], type := ty, value := val }

def run (path : String) (limit : Nat) : MetaM Unit := do
  let lines ← IO.FS.lines path
  let mut decls := #[]
  for (l, i) in lines.zipIdx do
    if i ≥ limit then break
    let j ← IO.ofExcept (Json.parse l)
    decls := decls.push (← decl i j)
  let kenv := (← getEnv).toKernelEnv
  let t0 ← IO.monoNanosNow
  let mut ok := 0
  let mut worst := 0
  for d in decls do
    let s ← IO.monoNanosNow
    match Lean.Kernel.Environment.addDeclCore kenv 0 100000 d none with
    | .ok _ => ok := ok + 1
    | .error _ => pure ()
    worst := max worst ((← IO.monoNanosNow) - s)
  let t1 ← IO.monoNanosNow
  IO.println s!"kernel: {ok}/{decls.size} accepted, {(t1 - t0) / 1000000} ms total, {(t1 - t0) / 1000 / decls.size} us each, worst {worst / 1000} us"

end CertSpike.Kernel

#eval CertSpike.Kernel.run "/home/andrew-peterson/code/laniusc/target/claude-work/cert/lean/distinct.jsonl" 100000
