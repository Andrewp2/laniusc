import Lanius.X86.Source.Register
import Lanius.X86.Source.Fixed

namespace Lanius.X86.Source.Indexed

open Lanius.Core Lanius.Extraction

def parameters : List (VarId × Ty) :=
  [(0, .slice i32), (1, i32), (2, i32), (3, i32), (4, i32), (5, i32), (6, i32), (7, i32)]

def guard (valid : FunctionId) (rsp : ConstantId) : Expr :=
  .binary .logicalOr
    (.binary .logicalOr
      (.binary .logicalOr
        (.binary .logicalOr
          (.binary .logicalOr (.unary .logicalNot (.call valid [read 3]))
            (.unary .logicalNot (.call valid [read 4])))
          (.unary .logicalNot (.call valid [read 5])))
        (.binary .equal (read 5) (.constant rsp)))
      (.binary .less (read 6) (number 0)))
    (.binary .greater (read 6) (number 3))

def extended : Expr := .binary .greaterEqual (read 5) (number 8)
def extendRex : Stmt := .ifThenElse extended
  (.sequence (.expression (.assign .add (.local 8) (number 2))) .skip) .skip
def rexArguments : List Expr := [number 64, read 3, read 4, .value (.boolean false)]
def modRM : Expr := .binary .add (number 132)
  (.binary .multiply (.binary .remainder (read 3) (number 8)) (number 8))
def sib : Expr := .binary .add
  (.binary .add (.binary .multiply (read 6) (number 64))
    (.binary .multiply (.binary .remainder (read 5) (number 8)) (number 8)))
  (.binary .remainder (read 4) (number 8))

def header : List Expr := [read 8, number 141, modRM, sib]

def stores (offset : Nat) (expressions : List Expr) (tail : Stmt) : Stmt :=
  match expressions with
  | [] => tail
  | expression :: rest => .sequence
      (.expression (.assign .set (.index (.local 0) (fixedIndex offset)) expression))
      (stores (offset + 1) rest tail)

def write (word : FunctionId) : Stmt := stores 0 header
  (returned (.call word [read 0, fixedIndex 4, read 7]))

def afterGuard (rex fits word : FunctionId) : Stmt :=
  .sequence (.ifThenElse (fixedGuard fits 8) (returned negativeOne) .skip)
    (.letLocal 8 i32 (.call rex rexArguments) (.sequence extendRex (write word)))

def body (valid rex fits word : FunctionId) (rsp : ConstantId) : Stmt :=
  .sequence (.ifThenElse (guard valid rsp) (returned negativeOne) .skip) (afterGuard rex fits word)

structure Checked (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (valid : CheckedValidation program .register) (rex : CheckedRex program)
    (fits : CheckedFits program) (word : CheckedWord program) where
  rsp : ConstantId
  declaration : Constant
  found : program.core.constant? rsp = some declaration
  value : declaration.value = .signed .i32 4
  internal : Extraction.Source.CheckedInternal program ["x86", "encode"] "indexed_address"
    parameters i32 (body valid.source.function.id rex.source.function.id fits.source.function.id word.source.function.id rsp)

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (valid : CheckedValidation program .register) (rex : CheckedRex program)
    (fits : CheckedFits program) (word : CheckedWord program) : Option (Checked program valid rex fits word) := do
  let source ← CoreSynthesis.Program.checkSourceFunction? program ["x86", "encode"] "indexed_address"
  let some (.sequence (.ifThenElse
    (.binary .logicalOr (.binary .logicalOr (.binary .logicalOr _ (.binary .equal _ (.constant rsp))) _) _)
    _ _) _) := source.function.body | none
  match found : program.core.constant? rsp with
  | none => none
  | some declaration =>
    match value : declaration.value with
    | .signed .i32 number =>
      if exactNumber : number = 4 then
        let internal ← Extraction.Source.checkInternal? program ["x86", "encode"] "indexed_address"
          parameters i32 (body valid.source.function.id rex.source.function.id fits.source.function.id word.source.function.id rsp)
        pure ⟨rsp, declaration, found, by simpa only [exactNumber] using value, internal⟩
      else none
    | _ => none

end Lanius.X86.Source.Indexed
