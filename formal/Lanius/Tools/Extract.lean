import Lanius.Mini.FrontLex
import Lanius.Mini.Extract

/-! The extractor in Lanius (`formal/lani/mini/extract.lani`), run on a file:

    lake exe extract [--check] [--tree PATH=TREE].. SOURCE TREE NAME MODULE FORMAL OUTDIR

SOURCE is the `.lani` file, `TREE.prods` and `TREE.parents` laniusc's parse
tree of it, NAME its path from the repository root and MODULE the Lean module
of its extraction. The parts of the modules its external sections name are
read from FORMAL (as extract.py's external_names does), and each module
extracted is written as `OUTDIR/<module path>.lean`. Each external
section's file PATH (from the repository root) needs a `--tree PATH=TREE`:
its items must be the file's items of the same names, read from TREE as
the source is.
The front end's lexer and validator read the tree, so the extractor works on
the same parse as the front end.

As extract.py does, it also removes the module's parts it no longer writes,
and rewrites the `-- import all: MODULE` and `-- import parts: MODULE name..`
blocks of the Lean files under `FORMAL/Lanius` (written under OUTDIR). With
`--check` it writes nothing and fails if any of those files would change. -/

open Lanius.Mini

namespace Lanius.Tools.Extract

def readNats (path : String) : IO (List Nat) := do
  return ((← IO.FS.readFile path).splitOn " ").filterMap String.toNat?

def textOf (s : String) : List Nat := s.toUTF8.toList.map (·.toNat)

def bytesOf (text : List Nat) : ByteArray := ⟨(text.map (·.toUInt8)).toArray⟩

def stringOf (text : List Nat) : String := String.fromUTF8! (bytesOf text)

/-- The name `def NAME` (or `@[expose] def NAME`) at the start of a line defines. -/
def defName (line : String) : Option String :=
  let rest := if line.startsWith "@[expose] " then (line.drop 10).toString else line
  if rest.startsWith "def " then
    let name := (rest.drop 4).toString.takeWhile fun c => c.isAlphanum || c == '_' || c == '.'
    if name.isEmpty then none else some name.toString
  else none

/-- The definitions of the parts of `module` under `formal`, each with its part. -/
def knownOf (formal : System.FilePath) (module : String) : IO (List XKnown) := do
  let dir := (module.splitOn ".").foldl (· / ·) formal / "P"
  if !(← dir.isDir) then return []
  let files := ((← dir.readDir).map (·.fileName)).toList.filter (·.endsWith ".lean")
  let mut out := []
  for f in files.toArray.qsort (· < ·) do
    let part := module ++ ".P." ++ (f.dropEnd 5).toString
    for line in (← IO.FS.readFile (dir / f)).splitOn "\n" do
      if let some name := defName line then
        out := out ++ [{ modname := textOf module, name := textOf name, part := textOf part }]
  return out

/-- The `.lean` files under `dir`, as paths relative to `base`. -/
partial def leanFiles (base dir : System.FilePath) : IO (List String) := do
  if !(← dir.isDir) then return []
  let mut out := []
  for e in ← dir.readDir do
    if ← e.path.isDir then
      out := out ++ (← leanFiles base e.path)
    else if e.fileName.endsWith ".lean" then
      out := out ++ [((e.path.toString.drop (base.toString.length + 1)).toString)]
  return out

/-- The number of `/` in a path. -/
def slashes (path : String) : Nat := (path.toList.filter (· == '/')).length

/-- The text before the first `sep` and the text after it. -/
def splitOnce (text sep : String) : Option (String × String) :=
  match text.splitOn sep with
  | [] => none
  | [_] => none
  | head :: rest => some (head, sep.intercalate rest)

/-- The text with its `-- import all: module` block listing `parts` (`import
all`), and its `-- import parts: module names..` block listing the parts
`where` says define the names (`public import`). -/
def importBlocks (path text module : String) (parts : List String)
    (where_ : List (String × String)) : Except String String := do
  let mut new := text
  let begin := s!"-- import all: {module}\n"
  if let some (head, rest) := splitOnce new begin then
    if let some (_, tail) := splitOnce rest "-- end import all\n" then
      new := head ++ begin ++ String.join (parts.map (s!"import all {·}\n")) ++ "-- end import all\n" ++ tail
  let lead := s!"-- import parts: {module}"
  let lines := new.splitOn "\n"
  let hit := lines.find? fun l => l == lead || l.startsWith (lead ++ " ")
  if let some line := hit then
    if let some (head, rest) := splitOnce new (line ++ "\n") then
      if let some (_, tail) := splitOnce rest "-- end import parts\n" then
        let wanted := ((line.drop lead.length).toString.splitOn " ").filter (· ≠ "")
        let missing := wanted.filter fun w => (List.lookup w where_).isNone
        if !missing.isEmpty then
          throw s!"{path}: {module} defines no {missing}"
        let mods := (wanted.filterMap (List.lookup · where_)).eraseDups.toArray.qsort (fun a b => decide (a < b))
        new := head ++ line ++ "\n" ++ String.join (mods.toList.map (s!"public import {·}\n")) ++
          "-- end import parts\n" ++ tail
  return new

/-- A file's bytes and its tree, as the front end's lexer and validator check it. -/
def readTree (source tree : String) : IO (Except String (List Nat × CTree × Nat)) := do
  let bytes ← IO.FS.readBinFile source
  let prods ← readNats (tree ++ ".prods")
  let parents ← readNats (tree ++ ".parents")
  let some tokens := lexTokens (bytes.toList.map fun b => Fin.ofNat 256 b.toNat)
    | return .error s!"{source}: does not lex"
  let some root := validateTree grammar tokens prods parents
    | return .error s!"{source}: the tree does not validate"
  return .ok (bytes.toList.map (·.toNat), root, 4 * (prods.length + tokens.length) + 16)

/-- The `--tree PATH=TREE` arguments and the rest. -/
def treeArgs : List String → List (String × String) × List String
  | "--tree" :: pair :: rest =>
    let (trees, others) := treeArgs rest
    match pair.splitOn "=" with
    | [path, tree] => ((path, tree) :: trees, others)
    | _ => (trees, pair :: others)
  | a :: rest => let (trees, others) := treeArgs rest; (trees, a :: others)
  | [] => ([], [])

def main (args : List String) : IO UInt32 := do
  let check := args.contains "--check"
  let (trees, args) := treeArgs (args.filter (· ≠ "--check"))
  match args with
  | [source, tree, name, module, formal, outdir] =>
    let (src, root, fuel) ← match ← readTree source tree with
      | .ok r => pure r
      | .error e => IO.eprintln e; return 1
    let mut srcs := []
    let mut extFuel := fuel
    for p in exExternalPaths fuel src root do
      let path := stringOf p
      let some t := List.lookup path trees
        | IO.eprintln s!"{source}: no --tree for its external source {path}"; return 1
      match ← readTree path t with
      | .ok (bytes, r, f) =>
        srcs := srcs ++ [({ path := p, source := bytes, root := r } : XExtSrc)]
        extFuel := max extFuel f
      | .error e => IO.eprintln e; return 1
    let extErrs := exExternalErrs extFuel src root srcs
    if !extErrs.isEmpty then
      for e in extErrs do IO.eprintln s!"{source}: {stringOf e}"
      return 1
    let mut known := []
    for m in exExternalModules fuel src root do
      known := known ++ (← knownOf formal (stringOf m))
    let out := exExtract fuel src root (textOf name) (textOf module) known
    if !out.errs.isEmpty then
      for e in out.errs do IO.eprintln s!"{source}: {stringOf e}"
      return 1
    let relOf (m : String) := m.replace "." "/" ++ ".lean"
    let mut files : List (String × String) :=
      out.modules.map fun m => (relOf (stringOf m.name), stringOf m.text)
    let stem := (module.replace "." "/")
    let old := (← leanFiles outdir (System.FilePath.mk outdir / stem)).filter fun f =>
      slashes f == slashes stem + 1 || f.startsWith (stem ++ "/P/") && slashes f == slashes stem + 2
    let stale := old.filter fun f => (List.lookup f files).isNone
    let parts := (out.modules.map (stringOf ·.name)).filter (· ≠ module)
    let where_ := (out.modules.filter fun m => ((stringOf m.name).splitOn ".P.").length > 1).flatMap fun m =>
      ((stringOf m.text).splitOn "\n").filterMap fun l => (defName l).map (·, stringOf m.name)
    for f in ← leanFiles formal (System.FilePath.mk formal / "Lanius") do
      if (List.lookup f files).isSome then continue
      let text ← IO.FS.readFile (System.FilePath.mk formal / f)
      match importBlocks f text module parts where_ with
      | .error e => IO.eprintln e; return 1
      | .ok new => if new != text then files := files ++ [(f, new)]
    let mut changed := []
    for (f, t) in files do
      let path := System.FilePath.mk outdir / f
      if !(← path.pathExists) then
        changed := changed ++ [f]
      else if (← IO.FS.readFile path) != t then
        changed := changed ++ [f]
    if check then
      match changed ++ stale with
      | [] => return 0
      | f :: _ => IO.eprintln s!"{f} is stale; rerun the extractor"; return 1
    for f in stale do IO.FS.removeFile (System.FilePath.mk outdir / f)
    for (f, t) in files do
      if changed.contains f then
        let path := System.FilePath.mk outdir / f
        if let some dir := path.parent then IO.FS.createDirAll dir
        IO.FS.writeFile path t
    return 0
  | _ =>
    IO.eprintln "usage: lake exe extract [--check] [--tree PATH=TREE].. SOURCE TREE NAME MODULE FORMAL OUTDIR"
    return 2

end Lanius.Tools.Extract

def main (args : List String) : IO UInt32 := Lanius.Tools.Extract.main args
