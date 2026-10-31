import Lanius.Mini.FrontLex
import Std.Data.HashMap

/-! The front end's program of some files, for the extraction certificates:

    lake exe srcDump MANIFEST OUT NAMESPACE

The manifest's one line is `NAME BASE...` (as runAll's). OUT gets a Lean
file: for each function of the front end's `SrcProgram`, its instance (the
declaration's module, name and type arguments) as a comment, then the
function as a `SrcFunc` term. OUT.meta names the functions and types (`describe`). -/

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

def uintName : UintTy → String
  | .uint8 => "u8"
  | .uint32 => "u32"
  | .uint64 => "u64"
  | .usize => "usize"
  | .uint16 => "u16"

/-- The signed type as wide as an unsigned one. -/
def sintName : UintTy → String
  | .uint8 => "i8"
  | .uint32 => "i32"
  | .uint64 => "i64"
  | .usize => "isize"
  | .uint16 => "i16"

/-- A type as Lanius writes it, each named type with its module. -/
partial def tyName (decls : Decls) : Ty → String
  | .tyI32 => "i32"
  | .tyBool => "bool"
  | .tyUint k => uintName k
  | .tyPtr => "ptr"
  | .tyIsize => "isize"
  | .tyChar => "char"
  | .tySint k => sintName k
  | .tySlice e => s!"[{tyName decls e}]"
  | .tyNamed d args =>
    let name := match decls.types[d]? with
      | none => s!"?{d}"
      | some t => s!"{path t.home}::{text t.name}"
    if args.isEmpty then name else s!"{name}<{",".intercalate (args.map (tyName decls))}>"

partial def firstLeaf : CTree → Option String
  | .leaf t => some (text t.text)
  | .node _ kids => kids.findSome? firstLeaf

/-- A front-pass type: scalars by name, a struct or enum by its id. -/
def srcTyName : SrcType → String
  | .i32 => "i32"
  | .bool => "bool"
  | .uint k => uintName k
  | .ptr => "ptr"
  | .unit => "unit"
  | .isize => "isize"
  | .char => "char"
  | .float .f32 => "f32"
  | .float .f64 => "f64"
  | .slice _ => "slice"
  | .struct id _ => s!"#{id}"
  | .enum id _ => s!"#{id}"
  | .sint k => sintName k

mutual
partial def effCalls : SrcEff → List Nat
  | .ePure _ => []
  | .eCall c args => c :: args.flatMap effCalls
  | .eApply _ l r => effCalls l ++ effCalls r
  | .eNeg e => effCalls e
  | .eNot e => effCalls e
  | .eCast _ e => effCalls e
  | .eIndex _ i => effCalls i
  | .eStruct _ fs => fs.flatMap effCalls
  | .eVariant _ _ ps => ps.flatMap effCalls
  | .eMatch s _ _ _ vs => effCalls s ++ vs.flatMap effCalls
  | .eDivide _ l r => effCalls l ++ effCalls r
  | .eStride _ => []

partial def stmtCalls : SrcStmt → List Nat
  | .let _ _ _ b | .letStruct _ _ _ b | .letEnum _ _ _ _ b | .letMatch _ _ _ _ _ b => stmtCalls b
  | .letAlloc _ _ _ b | .letLoad _ _ _ b | .letSlice _ _ _ _ b | .letIndex _ _ _ _ b => stmtCalls b
  | .letCall _ _ c _ b => c :: stmtCalls b
  | .setCall _ c _ => [c]
  | .then a b => stmtCalls a ++ stmtCalls b
  | .if _ a b => stmtCalls a ++ stmtCalls b
  | .while _ b => stmtCalls b
  | .letEval _ _ v b => effCalls v ++ stmtCalls b
  | .setEval _ v | .returnEval v | .discard v | .setFieldEval _ _ v | .assert v => effCalls v
  | .ifEval c a b => effCalls c ++ stmtCalls a ++ stmtCalls b
  | .whileEval c b => effCalls c ++ stmtCalls b
  | .setIndexEval _ i v => effCalls i ++ effCalls v
  | .nop | .set _ _ | .setField _ _ _ | .return _ | .setByte _ _ _ | .free _ _ _ | .setIndex _ _ _
  | .returnUnit => []
end

/-- `sig ID PARAMS RET CALLEES` (comma lists, `-` when empty), and for a
struct or enum id `shape ID FIELDS` with one `|`-separated field list per
variant. -/
def sigLine (i : Nat) (f : SrcFunc) : String :=
  let list (xs : List String) := if xs.isEmpty then "-" else ",".intercalate xs
  s!"sig {i} {list (f.params.map (srcTyName ·.ty))} {srcTyName f.ret} {list ((stmtCalls f.body).eraseDups.map toString)}"

def shapeLine (i : Nat) : Option SrcType → String
  | some (.struct _ fs) => s!"shape {i} {",".intercalate (fs.map srcTyName)}"
  | some (.enum _ vs) => s!"shape {i} {"|".intercalate (vs.map fun v => ",".intercalate (v.map srcTyName))}"
  | _ => s!"shape {i} ?"

/-- What the certificates need to name the program's parts in Lean, one
line each: `fn ID MODULE::NAME SELF ARGS` (SELF is an impl method's type,
or `-`; ARGS the type arguments, or `-`; an instance the front end made has
name `?`), and `type ID MODULE::NAME ARGS struct|enum NAMES` with the
fields' or variants' spellings, ID the SrcType id. -/
def describe (files : List FileInput) : Option (List String) := do
  let roots ← validateFiles grammar files
  let fuel := filesFuel files
  match roots with
  | [] => none
  | first :: rest =>
    let f ← fileDecls fuel first
    let c ← collectFiles fuel rest ({ decls := f.decls, modules := [f.home] } : Collected)
    let m ← monoLoop fuel fuel c.decls (rootInsts f.decls.fns 0) [] 0
    let seeds := seedInsts f.decls.types 0
    let types ← typeTable fuel c.decls seeds (seedTys seeds ++ funcsTys m.funcs)
    let args (ts : List Ty) := if ts.isEmpty then "-" else ",".intercalate (ts.map (tyName c.decls))
    let fns := (List.range m.table.length).zip m.table |>.map fun (i, inst) =>
      match c.decls.fns[inst.decl]? with
      | none => s!"fn {i} ? - {args inst.args}"
      | some d =>
        let self := if d.inImpl then (firstLeaf d.selfType).getD "?" else "-"
        s!"fn {i} {path d.home}::{text d.name} {self} {args inst.args}"
    let tys := (List.range types.length).zip types |>.map fun (i, inst) =>
      match c.decls.types[inst.decl]? with
      | none => s!"type {i} ? - struct"
      | some t =>
        let names := if t.isEnum then t.variants else t.fields
        s!"type {i} {path t.home}::{text t.name} {args inst.args} {if t.isEnum then "enum" else "struct"} {" ".intercalate (names.map text)}"
    let shapes := (List.range types.length).zip types |>.map fun (i, inst) =>
      shapeLine i (lowerNamed fuel c.decls types inst.decl inst.args)
    return fns ++ tys ++ shapes

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
  | .uint16 => ".uint16"

/-- A type's text: scalars as themselves, the rest by name. -/
partial def typeText : SrcType → StateM Table String
  | .i32 => pure ".i32"
  | .bool => pure ".bool"
  | .uint k => pure s!"(.uint {uintText k})"
  | .ptr => pure ".ptr"
  | .unit => pure ".unit"
  | .isize => pure ".isize"
  | .char => pure ".char"
  | .float .f32 => pure "(.float .f32)"
  | .float .f64 => pure "(.float .f64)"
  | .sint k => pure s!"(.sint {uintText k})"
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
  let some lines := describe files | IO.eprintln "the front end rejects the files"; return 1
  let names := (lines.filter (fun (l : String) => l.startsWith "fn ")).map fun (l : String) =>
    match l.splitOn " " with
    | [_, _, name, self, args] =>
      (if self == "-" then name else s!"{self}::{name}") ++ (if args == "-" then "" else s!"<{args}>")
    | _ => l
  let some p := frontEndFiles grammar files | IO.eprintln "the front end rejects the files"; return 1
  IO.FS.writeFile (out ++ ".meta") ("\n".intercalate (lines ++ ((List.range p.funcs.length).zip p.funcs).map (fun (i, f) => sigLine i f)) ++ "\n")
  let (funcs, table) := (p.funcs.mapM markFunc).run {}
  let h ← IO.FS.Handle.mk out .write
  h.putStrLn s!"import Lanius.Mini.Compiler\n\n/-! Generated by formal/tools/faithful_dump.py: the front end's program of\n{line}\n{p.funcs.length} functions, {table.defs.size} named types. -/\n\nnamespace {ns}\n\nopen Lanius.Mini\n\nnoncomputable section\n"
  for d in table.defs do
    h.putStrLn d
  h.putStrLn ""
  let mut i := 0
  for f in funcs do
    h.putStrLn s!"/-- {names.getD i "?"} -/"
    h.putStrLn s!"def src{i} : SrcFunc := {(repr f).pretty 1000000000}"
    i := i + 1
  h.putStrLn s!"\ndef prog : SrcProgram := \{ funcs := [{", ".intercalate ((List.range p.funcs.length).map (s!"src{·}"))}] }\n\nend\n\nend {ns}"
  return 0
