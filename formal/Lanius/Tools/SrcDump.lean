import Lanius.Mini.FrontLex
import Std.Data.HashMap

/-! The front end's program of some files, for the extraction certificates:

    lake exe srcDump MANIFEST OUT NAMESPACE

The manifest's one line is `NAME BASE...` (as runAll's). OUT gets a Lean
file: for each function of the front end's `SrcProgram`, its instance (the
declaration's module, name and type arguments) as a comment, then the
function as a `SrcFunc` term. -/

open Lanius.Mini

namespace Lanius.Tools.SrcDump

def readNats (path : String) : IO (List Nat) := do
  return ((← IO.FS.readFile path).splitOn " ").filterMap String.toNat?

def loadFile (base : String) : IO (Option FileInput) := do
  let bytes ← IO.FS.readBinFile (base ++ ".lani")
  let prods ← readNats (base ++ ".prods")
  let parents ← readNats (base ++ ".parents")
  return (lexTokens (bytes.toList.map (fun b => Fin.ofNat 256 b.toNat))).map fun tokens =>
    ({ tokens := tokens, prods := prods, parents := parents } : FileInput)

def text (bytes : List Nat) : String := String.ofList (bytes.map Char.ofNat)

def path (segments : List (List Nat)) : String := "::".intercalate (segments.map text)

/-- Each function instance's name: module::name<type arguments>. -/
def instNames (files : List FileInput) : Option (List String) := do
  let roots ← validateFiles grammar files
  let fuel := filesFuel files
  match roots with
  | [] => none
  | first :: rest =>
    let f ← fileDecls fuel first
    let c ← collectFiles fuel rest ({ decls := f.decls, modules := [f.home] } : Collected)
    let m ← monoLoop fuel fuel c.decls (rootInsts f.decls.fns 0) [] 0
    return m.table.map fun inst =>
      match c.decls.fns[inst.decl]? with
      | none => s!"?{inst.decl}"
      | some d =>
        let args := if inst.args.isEmpty then "" else s!"<{(reprStr inst.args).replace "\n" " "}>"
        s!"{path d.home}::{text d.name}{args}"

/-! Types are named once (`def tyK : SrcType`), bottom up, and each function
refers to them: a type written out in full at every use makes the dump of
the self-hosted compiler 147 MB. -/

structure Table where
  names : Std.HashMap String Nat := {}
  defs : Array String := #[]

def named (text : String) : StateM Table String := do
  let t ← get
  match t.names[text]? with
  | some k => pure s!"ty{k}"
  | none =>
    let k := t.defs.size
    set ({ names := t.names.insert text k, defs := t.defs.push s!"def ty{k} : SrcType := {text}" } : Table)
    pure s!"ty{k}"

def uintText : UintTy → String
  | .uint8 => ".uint8"
  | .uint32 => ".uint32"
  | .uint64 => ".uint64"
  | .usize => ".usize"

/-- A type's text: scalars as themselves, the rest by name. -/
partial def typeText : SrcType → StateM Table String
  | .i32 => pure ".i32"
  | .bool => pure ".bool"
  | .uint k => pure s!"(.uint {uintText k})"
  | .ptr => pure ".ptr"
  | .unit => pure ".unit"
  | .isize => pure ".isize"
  | .slice e => do named s!".slice {← typeText e}"
  | .struct id fs => do
    let ts ← fs.mapM typeText
    named s!".struct {id} [{", ".intercalate ts}]"
  | .enum id vs => do
    let ts ← vs.mapM fun v => do
      let ts ← v.mapM typeText
      pure s!"[{", ".intercalate ts}]"
    named s!".enum {id} [{", ".intercalate ts}]"

/-- The placeholder a named type prints as until `faithful_dump.py` writes
its name: `.struct (placeholder + k) []`. -/
def placeholder : Nat := 1000000000

def mark (ty : SrcType) : StateM Table SrcType := do
  let text ← typeText ty
  if text.startsWith "ty" then pure (.struct (placeholder + (text.drop 2).toString.toNat!) []) else pure ty

partial def markExpr : SrcExpr → StateM Table SrcExpr
  | .negate e => return .negate (← markExpr e)
  | .not e => return .not (← markExpr e)
  | .apply op l r => return .apply op (← markExpr l) (← markExpr r)
  | .cast ty e => return .cast (← mark ty) (← markExpr e)
  | e => pure e

partial def markEff : SrcEff → StateM Table SrcEff
  | .ePure e => return .ePure (← markExpr e)
  | .eCall c args => return .eCall c (← args.mapM markEff)
  | .eApply op l r => return .eApply op (← markEff l) (← markEff r)
  | .eNeg e => return .eNeg (← markEff e)
  | .eNot e => return .eNot (← markEff e)
  | .eCast ty e => return .eCast (← mark ty) (← markEff e)
  | .eIndex s i => return .eIndex s (← markEff i)
  | .eStruct ty fs => return .eStruct (← mark ty) (← fs.mapM markEff)
  | .eVariant ty k ps => return .eVariant (← mark ty) k (← ps.mapM markEff)
  | .eMatch s ety ty bs vs => return .eMatch (← markEff s) (← mark ety) (← mark ty) bs (← vs.mapM markEff)
  | .eDivide op l r => return .eDivide op (← markEff l) (← markEff r)
  | .eStride s => pure (.eStride s)

partial def markStmt : SrcStmt → StateM Table SrcStmt
  | .let id ty v b => return .let id (← mark ty) (← markExpr v) (← markStmt b)
  | .letStruct id ty fs b => return .letStruct id (← mark ty) (← fs.mapM markExpr) (← markStmt b)
  | .letCall id ty c args b => return .letCall id (← mark ty) c (← args.mapM markExpr) (← markStmt b)
  | .letEnum id ty k ps b => return .letEnum id (← mark ty) k (← ps.mapM markExpr) (← markStmt b)
  | .letMatch id ty s e arms b =>
    return .letMatch id (← mark ty) s e (← arms.mapM fun a => return { a with value := ← markExpr a.value }) (← markStmt b)
  | .set id v => return .set id (← markExpr v)
  | .setField id j v => return .setField id j (← markExpr v)
  | .setCall id c args => return .setCall id c (← args.mapM markExpr)
  | .then a b => return .then (← markStmt a) (← markStmt b)
  | .if c t e => return .if (← markExpr c) (← markStmt t) (← markStmt e)
  | .while c b => return .while (← markExpr c) (← markStmt b)
  | .return v => return .return (← markExpr v)
  | .letAlloc id sz sh b => return .letAlloc id (← markExpr sz) sh (← markStmt b)
  | .letLoad id p o b => return .letLoad id (← markExpr p) (← markExpr o) (← markStmt b)
  | .setByte p o v => return .setByte (← markExpr p) (← markExpr o) (← markExpr v)
  | .free p sz sh => return .free (← markExpr p) (← markExpr sz) sh
  | .letSlice id el p n b => return .letSlice id (← mark el) (← markExpr p) (← markExpr n) (← markStmt b)
  | .letIndex id ty s i b => return .letIndex id (← mark ty) s (← markExpr i) (← markStmt b)
  | .setIndex s i v => return .setIndex s (← markExpr i) (← markExpr v)
  | .letEval id ty v b => return .letEval id (← mark ty) (← markEff v) (← markStmt b)
  | .setEval id v => return .setEval id (← markEff v)
  | .ifEval c t e => return .ifEval (← markEff c) (← markStmt t) (← markStmt e)
  | .whileEval c b => return .whileEval (← markEff c) (← markStmt b)
  | .returnEval v => return .returnEval (← markEff v)
  | .discard v => return .discard (← markEff v)
  | .setIndexEval s i v => return .setIndexEval s (← markEff i) (← markEff v)
  | .setFieldEval id j v => return .setFieldEval id j (← markEff v)
  | .assert c => return .assert (← markEff c)
  | s => pure s

def markFunc (f : SrcFunc) : StateM Table SrcFunc := do
  return { params := ← f.params.mapM fun p => return { p with ty := ← mark p.ty },
           ret := ← mark f.ret, body := ← markStmt f.body }

end Lanius.Tools.SrcDump

open Lanius.Tools.SrcDump in
def main (args : List String) : IO UInt32 := do
  let [manifest, out, ns] := args | IO.eprintln "usage: srcDump MANIFEST OUT NAMESPACE"; return 2
  let line := ((← IO.FS.readFile manifest).splitOn "\n").headD ""
  let bases := (line.splitOn " ").drop 1
  let mut files : List FileInput := []
  for b in bases do
    match ← loadFile b with
    | none => IO.eprintln s!"{b} does not lex"; return 1
    | some f => files := files ++ [f]
  let some names := instNames files | IO.eprintln "the front end rejects the files"; return 1
  let some p := frontEndFiles grammar files | IO.eprintln "the front end rejects the files"; return 1
  let (funcs, table) := (p.funcs.mapM markFunc).run {}
  let h ← IO.FS.Handle.mk out .write
  h.putStrLn s!"import Lanius.Mini.Compiler\n\n/-! Generated by formal/tools/faithful_dump.py: the front end's program of\n{line}\n{p.funcs.length} functions, {table.defs.size} named types. -/\n\nnamespace {ns}\n\nopen Lanius.Mini\n"
  for d in table.defs do
    h.putStrLn d
  h.putStrLn ""
  let mut i := 0
  for f in funcs do
    h.putStrLn s!"/-- {names.getD i "?"} -/"
    h.putStrLn s!"def src{i} : SrcFunc := {(repr f).pretty 1000000000}"
    i := i + 1
  h.putStrLn s!"\ndef prog : SrcProgram := \{ funcs := [{", ".intercalate ((List.range p.funcs.length).map (s!"src{·}"))}] }\n\nend {ns}"
  return 0
