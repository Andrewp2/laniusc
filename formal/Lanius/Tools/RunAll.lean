import Lanius.Mini.FrontLex

/-! A compiled driver for the self-hosting checks (formal/tools/self_host.py):
the front end and `compileSource` on programs given as lexed files and
laniusc's parse trees, as native code rather than `#eval`'s interpreter.

    lake exe runAll MANIFEST

Each manifest line is `compile NAME BASE...`, `dump NAME BASE...`,
`diag NAME BASE...` or `validate NAME BASE...`, where a base names BASE.lani, BASE.prods and BASE.parents. `compile` prints NAME and
nolex, tree (the grammar rejects the tree), unread (the builder rejects it),
uncompiled (`compileSource` rejects it) or `image [entries] [bytes]`; `dump`
prints NAME and, for each file, its tokens (kind:start:text), prods and
parents, or nolex; `diag` says why `compileSource` rejects a program;
`validate` prints ok or tree for each file. -/

open Lanius.Mini

namespace Lanius.Tools

def readNats (path : String) : IO (List Nat) := do
  let text ← IO.FS.readFile path
  return (text.splitOn " ").filterMap String.toNat?

def readSource (path : String) : IO (List Lanius.Compiler.Lexer.Byte) := do
  let bytes ← IO.FS.readBinFile path
  return bytes.toList.map (fun b => Fin.ofNat 256 b.toNat)

def loadFile (base : String) : IO (Option FileInput) := do
  let source ← readSource (base ++ ".lani")
  let prods ← readNats (base ++ ".prods")
  let parents ← readNats (base ++ ".parents")
  return (lexTokens source).map fun tokens => ({ tokens := tokens, prods := prods, parents := parents } : FileInput)

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
    | _ => IO.eprintln s!"bad manifest line: {line}"; return 2
    (← IO.getStdout).flush
  return 0
