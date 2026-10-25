import Lanius.Mini.FrontLex
import Std.Data.HashMap

/-! A compiled driver for the self-hosting checks (formal/tools/self_host.py):
the front end and `compileSource` on programs given as lexed files and
laniusc's parse trees, as native code rather than `#eval`'s interpreter.

    lake exe runAll MANIFEST

Each manifest line is `compile NAME BASE...`, `dump NAME BASE...`,
`diag NAME BASE...`, `validate NAME BASE...` or `time NAME BASE...`, where a
base names BASE.lani, BASE.prods and BASE.parents. `compile` prints NAME and
nolex, tree (the grammar rejects the tree), unread (the builder rejects it),
uncompiled (`compileSource` rejects it) or `image [entries] [bytes]`; `dump`
prints NAME and, for each file, its tokens (kind:start:text), prods and
parents, or nolex; `diag` says why `compileSource` rejects a program;
`validate` prints ok or tree for each file; `time` prints how long each stage
of the front end and `compileSource` takes; `names` prints each function
instance's position, module, spelling and type argument count (a native
image's entries are in this order). -/

open Lanius.Mini

namespace Lanius.Tools

def readNats (path : String) : IO (List Nat) := do
  let text ← IO.FS.readFile path
  return (text.splitOn " ").filterMap String.toNat?

def readSource (path : String) : IO (List Lanius.Compiler.Lexer.Byte) := do
  let bytes ← IO.FS.readBinFile path
  return bytes.toList.map (fun b => Fin.ofNat 256 b.toNat)

/-- The files read so far, by base: a stdlib file is shared by many programs. -/
initialize loaded : IO.Ref (Std.HashMap String (Option FileInput)) ← IO.mkRef {}

def loadFile (base : String) : IO (Option FileInput) := do
  if let some r := (← loaded.get)[base]? then return r
  let source ← readSource (base ++ ".lani")
  let prods ← readNats (base ++ ".prods")
  let parents ← readNats (base ++ ".parents")
  let r := (lexTokens source).map fun tokens => ({ tokens := tokens, prods := prods, parents := parents } : FileInput)
  loaded.modify (·.insert base r)
  return r

def showNats (xs : List Nat) (sep : String) : String := sep.intercalate (xs.map toString)

def compileLine (name : String) (bases : List String) : IO Unit := do
  let mut files : List FileInput := []
  let mut lexed := true
  for b in bases do
    match ← loadFile b with
    | none => lexed := false
    | some f => files := files ++ [f]
  if !lexed then
    IO.println s!"{name} nolex"
  else
    match frontEndFiles grammar files with
    | none =>
      match validateFiles grammar files with
      | none => IO.println s!"{name} tree"
      | some _ => IO.println s!"{name} unread"
    | some p =>
      match compileSource p with
      | none => IO.println s!"{name} uncompiled"
      | some b => IO.println s!"{name} image {b.entries} {b.image.map (·.toNat)}"

/-- Whether the grammar accepts each file's tree: NAME and ok or tree. -/
def validateLine (name : String) (bases : List String) : IO Unit := do
  for b in bases do
    match ← loadFile b with
    | none => IO.println s!"{name} nolex"
    | some f =>
      match validateFiles grammar [f] with
      | none => IO.println s!"{name} tree"
      | some _ => IO.println s!"{name} ok"

def dumpLine (name : String) (bases : List String) : IO Unit := do
  for b in bases do
    match ← loadFile b with
    | none => IO.println s!"{name} nolex"
    | some f =>
      let ts := " ".intercalate (f.tokens.map fun t => s!"{t.kind}:{t.start}:{showNats t.text "."}")
      IO.println s!"{name} file {ts}|{showNats f.prods " "}|{showNats f.parents " "}"

/-- Why `compileSource` rejects a program the front end reads: each
function without a return on every path, each function `lowerFunc` rejects
(its index and the start of its `repr`), or the stage that fails after. -/
def diagLine (name : String) (bases : List String) : IO Unit := do
  let mut files : List FileInput := []
  for b in bases do
    match ← loadFile b with
    | none => IO.println s!"{name} nolex {b}"
    | some f => files := files ++ [f]
  match frontEndFiles grammar files with
  | none => IO.println s!"{name} unread"
  | some p =>
    IO.println s!"{name} funcs {p.funcs.length}"
    let mut i := 0
    for f in p.funcs do
      if !(f.ret.isUnit || f.body.returns) then IO.println s!"{name} noreturn {i}"
      i := i + 1
    match declareProgram p with
    | none => IO.println s!"{name} declare fails"
    | some d =>
      let mut j := 0
      let mut failed := false
      for f in p.funcs do
        match lowerFunc (sigs p.funcs) d f with
        | none =>
          failed := true
          IO.println s!"{name} lower fails {j}: {((reprStr f).take 600).replace "\n" " "}"
        | some _ => pure ()
        j := j + 1
      if !failed then
        match lowerFuncs (sigs p.funcs) d p.funcs with
        | none => IO.println s!"{name} lowerFuncs fails"
        | some fs =>
          match compileOptimized ({ funcs := fs } : Program) with
          | none => IO.println s!"{name} compileOptimized fails ({fs.length} functions)"
          | some b => IO.println s!"{name} compiles: {b.image.length} bytes"

/-- How long each stage of `compileSource` takes on a program, in ms. -/
def timeLine (name : String) (bases : List String) : IO Unit := do
  let stage {α : Type} (label : String) (f : Unit → α) (size : α → Nat) : IO α := do
    let t0 ← IO.monoMsNow
    let x ← IO.lazyPure f
    let n := size x
    IO.println s!"{name} {label} {(← IO.monoMsNow) - t0} ms ({n})"
    (← IO.getStdout).flush
    return x
  let t0 ← IO.monoMsNow
  let mut files : List FileInput := []
  for b in bases do
    if let some f ← loadFile b then files := files ++ [f]
  IO.println s!"{name} lex {(← IO.monoMsNow) - t0} ms ({files.length} files)"
  (← IO.getStdout).flush
  let some _ ← stage "validate" (fun _ => validateFiles grammar files) (fun r => r.map List.length |>.getD 0)
    | IO.println s!"{name} tree"
  let some p ← stage "frontEnd" (fun _ => frontEndFiles grammar files) (fun r => r.map (·.funcs.length) |>.getD 0)
    | IO.println s!"{name} unread"
  let some d ← stage "declare" (fun _ => declareProgram p) (fun r => r.map (·.structs.length) |>.getD 0)
    | IO.println s!"{name} declare fails"
  let some fs ← stage "lower" (fun _ => lowerFuncs (sigs p.funcs) d p.funcs) (fun r => r.map List.length |>.getD 0)
    | IO.println s!"{name} lower fails"
  let prog : Program := { funcs := fs }
  let opt ← stage "optimize" (fun _ => optimizeProgram prog) (·.funcs.length)
  let _ ← stage "validate-opt" (fun _ => validate prog opt) (fun b => if b then 1 else 0)
  let some codes ← stage "compileFuncs" (fun _ => compileFuncs (arities opt.funcs) opt.funcs) (fun r => r.map List.length |>.getD 0)
    | IO.println s!"{name} compileFuncs fails"
  let entries ← stage "layout" (fun _ => layout 0 codes) List.length
  let _ ← stage "link" (fun _ => linkFrom entries 0 codes) List.length
  return ()

def spell (xs : List Nat) : String := String.ofList (xs.map Char.ofNat)

/-- Each function instance, in the order the image's entries are. -/
def namesLine (name : String) (bases : List String) : IO Unit := do
  let mut files : List FileInput := []
  for b in bases do
    if let some f ← loadFile b then files := files ++ [f]
  let some roots := validateFiles grammar files | IO.println s!"{name} tree"
  let fuel := filesFuel files
  let first :: rest := roots | IO.println s!"{name} unread"
  let some f := fileDecls fuel first | IO.println s!"{name} unread"
  let some c := collectFiles fuel rest { decls := f.decls, modules := [f.home] } | IO.println s!"{name} unread"
  let some m := monoLoop fuel fuel c.decls (rootInsts f.decls.fns 0) [] 0 | IO.println s!"{name} unread"
  let mut i := 0
  for inst in m.table do
    match c.decls.fns[inst.decl]? with
    | some d => IO.println s!"{name} fn {i} {"::".intercalate (d.home.map spell)}::{spell d.name} {inst.args.length}"
    | none => IO.println s!"{name} fn {i} projection {inst.decl} {inst.args.length}"
    i := i + 1

end Lanius.Tools

open Lanius.Tools in
def main (args : List String) : IO UInt32 := do
  let [manifest] := args | IO.eprintln "usage: runAll MANIFEST"; return 2
  let lines := ((← IO.FS.readFile manifest).splitOn "\n").filter (· ≠ "")
  for line in lines do
    match line.splitOn " " with
    | "compile" :: name :: bases => compileLine name bases
    | "dump" :: name :: bases => dumpLine name bases
    | "diag" :: name :: bases => diagLine name bases
    | "validate" :: name :: bases => validateLine name bases
    | "time" :: name :: bases => timeLine name bases
    | "names" :: name :: bases => namesLine name bases
    | _ => IO.eprintln s!"bad manifest line: {line}"; return 2
    (← IO.getStdout).flush
  return 0
