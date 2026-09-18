import Lanius.X86.Source.Constant

namespace Lanius.X86.Source.Lookup

open Lanius.Core Lanius.Extraction

def parameters : List (VarId × Ty) := [(0, .slice i32), (1, i32), (2, i32)]
def positive : Expr := .binary .greater (read 3) (number 0)
def field (header : ConstantId) : Expr :=
  .index (read 0) (.binary .add (.constant header) (read 3))
def sameKey (header : ConstantId) : Expr := .binary .equal (field header) (read 2)
def decrement : Stmt := .expression (.assign .subtract (.local 3) (number 1))
def step (header : ConstantId) : Stmt := .sequence decrement
  (.sequence (.ifThenElse (sameKey header) (returned (read 3)) .skip) .skip)
def loop (header : ConstantId) : Stmt := .whileLoop positive (step header)
def body (header : ConstantId) : Stmt :=
  .letLocal 3 i32 (read 1) (.sequence (loop header) (returned (.unary .negate (number 1))))

structure Checked (program : CoreSynthesis.Program.CheckedProgram artifacts) where
  header : IntegerConstant program.core
  value : header.value = 16
  internal : Extraction.Source.CheckedInternal program ["backend", "frame"] "lookup" parameters i32 (body header.id)

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts) : Option (Checked program) := do
  let source ← CoreSynthesis.Program.checkSourceFunction? program ["backend", "frame"] "lookup"
  let some (.letLocal _ _ _ (.sequence (.whileLoop _
    (.sequence _ (.sequence (.ifThenElse (.binary .equal
      (.index _ (.binary .add (.constant headerId) _)) _) _ _) _))) _)) := source.function.body | none
  let header ← integerConstant? program.core headerId
  if value : header.value = 16 then
    let internal ← Extraction.Source.checkInternal? program ["backend", "frame"] "lookup" parameters i32 (body header.id)
    pure ⟨header, value, internal⟩
  else none

end Lanius.X86.Source.Lookup
