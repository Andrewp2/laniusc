import Lean

/-! Certificate spike exporter (target/claude-work/cert/FORMAT.md).

    a file that imports MODULE.. and runs `#eval CertSpike.exportTo OUT #[MODULE..]`

Walks the kernel proof terms of every theorem declared in MODULE.. and writes
one JSON line per `SelfPre.LinCert.cert` application (a linear arithmetic
obligation of pre_auto/post_auto, already reduced to `L ≤ R` from chosen
hypotheses `Lᵢ ≤ Rᵢ` over atoms 0..n-1), and one line per theorem with the
size of its proof (distinct `Expr` nodes, the size Lean's own certificate
has). Read only; it declares nothing. -/

open Lean

namespace CertSpike

def certName : Name := `Lanius.Faithful.SelfPre.LinCert.cert

partial def natOf (e : Expr) : Option Nat :=
  match e with
  | .lit (.natVal k) => some k
  | .mdata _ b => natOf b
  | _ =>
    if e.isAppOfArity ``OfNat.ofNat 3 then natOf (e.getArg! 1) else none

/-- An `LTm` as JSON: ["a",i] | ["k",n] | ["+",x,y] | ["*",k,x]. -/
partial def ltm (e : Expr) : Option Json := do
  let e := e.consumeMData
  let fn := e.getAppFn
  let .const c _ := fn | none
  let args := e.getAppArgs
  match c.componentsRev.head! with
  | `atom => return Json.arr #["a", toJson (← natOf args[0]!)]
  | `lit => return Json.arr #["k", toJson (← natOf args[0]!)]
  | `add => return Json.arr #["+", ← ltm args[0]!, ← ltm args[1]!]
  | `mulL => return Json.arr #["*", toJson (← natOf args[0]!), ← ltm args[1]!]
  | `mulR => return Json.arr #["*", toJson (← natOf args[1]!), ← ltm args[0]!]
  | _ => none

partial def listOf (e : Expr) : Option (Array Expr) := do
  let e := e.consumeMData
  if e.isAppOfArity ``List.nil 1 then return #[]
  if e.isAppOfArity ``List.cons 3 then
    return #[e.getArg! 1] ++ (← listOf (e.getArg! 2))
  none

def pairOf (e : Expr) : Option (Expr × Expr) :=
  let e := e.consumeMData
  if e.isAppOfArity ``Prod.mk 4 then some (e.getArg! 2, e.getArg! 3) else none

/-- One obligation: atoms, hypotheses, goal. -/
def obligation (e : Expr) : Option Json := do
  let args := e.getAppArgs
  let vs ← listOf args[0]!
  let hs ← listOf args[1]!
  let hyps ← hs.mapM fun p => do
    let (a, b) ← pairOf p
    return Json.arr #[← ltm a, ← ltm b]
  return Json.mkObj [("atoms", toJson vs.size), ("hyps", Json.arr hyps),
    ("goal", Json.arr #[← ltm args[2]!, ← ltm args[3]!])]

structure St where
  seen : Std.HashSet Expr := {}
  obls : Array Json := #[]
  bad : Nat := 0

partial def walk (e : Expr) : StateM St Unit := do
  if (← get).seen.contains e then return
  modify fun s => { s with seen := s.seen.insert e }
  if e.isAppOf certName && e.getAppNumArgs == 6 then
    match obligation e with
    | some j => modify fun s => { s with obls := s.obls.push j }
    | none => modify fun s => { s with bad := s.bad + 1 }
  match e with
  | .app f a => walk f; walk a
  | .lam _ t b _ => walk t; walk b
  | .forallE _ t b _ => walk t; walk b
  | .letE _ t v b _ => walk t; walk v; walk b
  | .mdata _ b => walk b
  | .proj _ _ b => walk b
  | .bvar _ => pure ()
  | .fvar _ => pure ()
  | .mvar _ => pure ()
  | .sort _ => pure ()
  | .const _ _ => pure ()
  | .lit _ => pure ()

end CertSpike

open CertSpike in
/-- Walk the theorems of `mods` (already imported by the including file). -/
def exportTo (out : String) (mods : Array Name) : CoreM Unit := do
  let env ← getEnv
  let t1 ← IO.monoMsNow
  let h ← IO.FS.Handle.mk out .write
  let mut nThm := 0
  let mut nObl := 0
  let mut nBad := 0
  for (n, ci) in env.constants.map₁.toList do
    let some idx := env.getModuleIdxFor? n | continue
    let m := env.header.moduleNames[idx.toNat]!
    unless mods.contains m do continue
    let .thmInfo ti := ci | continue
    nThm := nThm + 1
    let (_, st) := (walk ti.value).run {}
    nObl := nObl + st.obls.size
    nBad := nBad + st.bad
    h.putStrLn (Json.compress (Json.mkObj [("thm", toJson n.toString), ("module", toJson m.toString),
      ("nodes", toJson st.seen.size), ("type_nodes", toJson ((walk ti.type).run {}).2.seen.size),
      ("obls", toJson st.obls.size)]))
    for j in st.obls do
      h.putStrLn (Json.compress (Json.mkObj [("obl", j), ("thm", toJson n.toString)]))
  IO.eprintln s!"theorems {nThm}, obligations {nObl}, unparsed {nBad}, walked in {(← IO.monoMsNow) - t1} ms"
