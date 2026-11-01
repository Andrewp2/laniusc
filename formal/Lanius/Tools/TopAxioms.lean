import Lean

/-! The top theorems' axioms and statements, for formal/tools/trusted_check.py
(gate step `trusted`, roadmap F13):

    lake exe topAxioms [DEFS]       one line per top theorem:
                                    NAME HASH AXIOM,AXIOM,...
                                    then `definitions HASH COUNT`, and
                                    each definition's NAME HASH in DEFS
    lake exe topAxioms roots MOD..  the theorems of MOD.. that no constant
                                    of MOD.. uses, one `MODULE NAME` a line

HASH is the kernel's structural hash of the theorem's statement (its type
`Expr`, a 32-bit hash printed as 16 hex digits), so it changes when the
statement the kernel checked changes (but for a 1 in 2^32 collision). The
axioms are what `#print axioms` gives: the axioms reached through every
constant's type and body, walked as `Lean.collectAxioms` walks them but with
one memo for all the theorems (`collectAxioms` walked each proof afresh,
85 s for these 26).

A statement means what its definitions say, so `definitions` hashes them
too: every constant of the project (a `Lanius` module) that the top
theorems' statements reach through types, definition bodies and
constructors, stopping at the computations the theorems are about
(`cuts`: the compiler, the front end's code, the ELF writer and the self
program, which are not trusted), each with its type and body. It changes
whenever a trusted definition (Core's semantics, the x86 model, the reading,
the statements' own definitions) does, and not when a definition only moves
to another module (a private name's module prefix is dropped). Run from
`formal/`, after the modules are built. -/

open Lean

namespace Lanius.Tools.TopAxioms

/-- The top theorems (TRUSTED_BASE.md, "Top theorems"), with their modules. -/
def tops : Array (Name × Name) := #[
  (`Lanius.Mini.Process, `Lanius.Mini.process_exits),
  (`Lanius.Mini.Process, `Lanius.Mini.process_behaviour),
  (`Lanius.Mini.Process, `Lanius.Mini.textProcess_exits),
  (`Lanius.Mini.Process, `Lanius.Mini.textProcess_behaviour),
  (`Lanius.Mini.TextCorrect, `Lanius.Mini.compileText_correct),
  (`Lanius.Mini.TextCorrect, `Lanius.Mini.compileText_behaviour),
  (`Lanius.Mini.TextCorrect, `Lanius.Mini.textReading_unique),
  (`Lanius.Mini.SourceCorrect, `Lanius.Mini.compileSource_correct),
  (`Lanius.Mini.SourceCorrect, `Lanius.Mini.compileSource_correct_from),
  (`Lanius.Mini.SourceStops, `Lanius.Mini.compileSource_stops),
  (`Lanius.Mini.SourceStops, `Lanius.Mini.compileSource_behaviour),
  (`Lanius.Mini.Determinism, `Lanius.Mini.compileSource_deterministic),
  (`Lanius.Mini.Determinism, `Lanius.Mini.compileProgram_deterministic),
  (`Lanius.Mini.TypeSound, `Lanius.Mini.compileSource_wellTyped),
  (`Lanius.Mini.Correct, `Lanius.Mini.compileProgram_correct),
  (`Lanius.Mini.StopsCorrect, `Lanius.Mini.compileProgram_stops),
  (`Lanius.Mini.Validate, `Lanius.Mini.compileOptimized_correct),
  (`Lanius.Mini.Link, `Lanius.Mini.link_eq),
  (`Lanius.Mini.Link, `Lanius.Mini.linked_correct),
  (`Lanius.Mini.Link, `Lanius.Mini.linked_deterministic),
  (`Lanius.Faithful.SelfDriver, `Lanius.Faithful.SelfDriver.driver_faithful),
  (`Lanius.Faithful.SelfDriver, `Lanius.Faithful.SelfDriver.driver_files),
  (`Lanius.Faithful.SafeDriver, `Lanius.Faithful.SelfDriver.driver_safe),
  (`Lanius.Faithful.SelfCompiler, `Lanius.Faithful.SelfCompiler.selfCompiler_outcome),
  (`Lanius.Faithful.SelfHost, `Lanius.Faithful.SelfHost.selfHost_fixpoint),
  (`Lanius.Faithful.SelfHost, `Lanius.Faithful.SelfHost.selfHost_outcome)
]

/-- Constants the theorems are about rather than trusted: their bodies are
not part of what a statement means (TRUSTED_BASE.md, "Not trusted"). -/
def cuts : Array Name := #[
  `Lanius.Mini.compileSource, `Lanius.Mini.compileText, `Lanius.Mini.compileProgram,
  `Lanius.Mini.compileOptimized, `Lanius.Mini.compileModules, `Lanius.Mini.linkObjects,
  `Lanius.Mini.elfFile, `Lanius.Mini.sourceProgramFiles, `Lanius.Mini.compileWords,
  `Lanius.Mini.frontEndWords, `Lanius.Faithful.Self.prog
]

def hex16 (h : UInt64) : String :=
  let s := String.mk (Nat.toDigits 16 h.toNat)
  String.mk (List.replicate (16 - s.length) '0') ++ s

/-- The axioms `c` depends on (what `#print axioms` gives), with one memo for
every top theorem, so a proof shared by several is walked once. -/
partial def axiomsOf (env : Environment) (c : Name) : StateM (NameMap (Array Name)) (Array Name) := do
  if let some r := (← get).find? c then return r
  modify (·.insert c #[])
  let (own, used) : Array Name × Array Name := match env.find? c with
    | some (.axiomInfo v) => (#[c], v.type.getUsedConstants)
    | some (.defnInfo v) => (#[], v.type.getUsedConstants ++ v.value.getUsedConstants)
    | some (.thmInfo v) => (#[], v.type.getUsedConstants ++ v.value.getUsedConstants)
    | some (.opaqueInfo v) => (#[], v.type.getUsedConstants ++ v.value.getUsedConstants)
    | some (.ctorInfo v) => (#[], v.type.getUsedConstants)
    | some (.recInfo v) => (#[], v.type.getUsedConstants)
    | some (.inductInfo v) => (#[], v.type.getUsedConstants ++ v.ctors.toArray)
    | some (.quotInfo _) => (#[], #[])
    | none => (#[], #[])
  let mut acc : NameSet := own.foldl (·.insert ·) {}
  for d in used do
    for a in ← axiomsOf env d do
      acc := acc.insert a
  let r := acc.toArray.qsort Name.lt
  modify (·.insert c r)
  return r

def load (mods : Array Name) : IO Environment := do
  initSearchPath (← findSysroot) [System.FilePath.mk ".lake/build/lib/lean"]
  importModules (mods.map fun m => { module := m }) {} (trustLevel := 1024)

/-- A project constant: one declared in a `Lanius` module. -/
def project (env : Environment) (n : Name) : Bool :=
  match env.getModuleIdxFor? n with
  | some i => (`Lanius).isPrefixOf (env.header.moduleNames[i.toNat]!)
  | none => false

/-- A private name without its module (`_private.M.0.x` is `x`): which
module a definition sits in is not part of what it says, and the generated
modules move definitions between files. -/
def stable (n : Name) : Name := privateToUserName n

/-- `e`'s structural hash, with each constant's private prefix dropped. -/
def stableHash (e : Expr) : UInt64 :=
  (e.replace fun
    | .const n us => if isPrivateName n then some (.const (stable n) us) else none
    | _ => none).hash

/-- The project constants the statements reach, each with its hash. -/
def definitions (env : Environment) : Array (Name × UInt64) := Id.run do
  let env := env.setExporting false
  let cut : NameSet := cuts.foldl (·.insert ·) {}
  let mut seen : NameSet := {}
  let mut todo : Array Name := #[]
  for (_, n) in tops do
    if let some ci := env.find? n then
      todo := todo ++ ci.type.getUsedConstants
  let mut out : Array (Name × UInt64) := #[]
  while !todo.isEmpty do
    let n := todo.back!
    todo := todo.pop
    if seen.contains n || cut.contains n || !project env n then continue
    seen := seen.insert n
    let some ci := env.find? n | continue
    let mut digest := stableHash ci.type
    todo := todo ++ ci.type.getUsedConstants
    match ci with
    | .defnInfo v => digest := mixHash digest (stableHash v.value); todo := todo ++ v.value.getUsedConstants
    | .opaqueInfo v => digest := mixHash digest (stableHash v.value); todo := todo ++ v.value.getUsedConstants
    | .inductInfo v => todo := todo ++ v.ctors.toArray
    | .ctorInfo v => todo := todo.push v.induct
    | _ => pure ()
    out := out.push (stable n, digest)
  return out.qsort fun a b => Name.quickLt a.1 b.1 || (a.1 == b.1 && a.2 < b.2)

def check (defsFile : Option String) : IO UInt32 := do
  let env ← load (tops.map (·.1))
  let mut bad : UInt32 := 0
  for n in cuts do
    unless env.contains n do
      IO.println s!"{n} missing"
      bad := 1
  let mut memo : NameMap (Array Name) := {}
  let privateEnv := env.setExporting false
  for (_, n) in tops do
    match env.find? n with
    | some (.thmInfo info) =>
      let (axs, memo') := (axiomsOf privateEnv n).run memo
      memo := memo'
      IO.println s!"{n} {hex16 info.type.hash} {",".intercalate (axs.toList.map toString)}"
    | _ =>
      IO.println s!"{n} missing"
      bad := 1
  let defs := definitions env
  let total := defs.foldl (fun acc (n, h) => mixHash acc (mixHash (hash n) h)) 7
  IO.println s!"definitions {hex16 total} {defs.size}"
  if let some path := defsFile then
    IO.FS.writeFile path (String.join (defs.toList.map fun (n, h) => s!"{n} {hex16 h}\n"))
  return bad

/-- A name the elaborator made (equation lemmas, matchers, auxiliary proofs). -/
def generated (n : Name) : Bool :=
  n.isInternal || n.components.any fun c =>
    let s := c.toString
    s.startsWith "eq_" || s.startsWith "match_" || s == "eq_def" || s == "eq_unfold" ||
      s.startsWith "_" || s.endsWith "_def"

def roots (mods : Array Name) : IO UInt32 := do
  let env ← load mods
  let ours : NameSet := mods.foldl (·.insert ·) {}
  let mine (n : Name) : Bool :=
    match env.getModuleIdxFor? n with
    | some i => ours.contains (env.header.moduleNames[i.toNat]!)
    | none => false
  let mut used : NameSet := {}
  for (n, ci) in env.constants.map₁.toList do
    if mine n then
      for c in ci.type.getUsedConstants do used := used.insert c
      if let some v := ci.value? (allowOpaque := true) then
        for c in v.getUsedConstants do used := used.insert c
  for (n, ci) in env.constants.map₁.toList do
    if mine n && ci matches .thmInfo _ && !used.contains n && !generated n then
      let m := (env.getModuleIdxFor? n).map fun i => env.header.moduleNames[i.toNat]!
      IO.println s!"{m.getD .anonymous} {n}"
  return 0

end Lanius.Tools.TopAxioms

def main (args : List String) : IO UInt32 :=
  match args with
  | "roots" :: mods => Lanius.Tools.TopAxioms.roots (mods.toArray.map String.toName)
  | [path] => Lanius.Tools.TopAxioms.check (some path)
  | _ => Lanius.Tools.TopAxioms.check none
