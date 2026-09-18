import Lanius.X86.Source.Allocate
import Lanius.X86.Source.Index

namespace Lanius.X86.Source.Expression.Indexed

open Lanius.Core Lanius.Extraction

def parameters : List (VarId × Ty) :=
  [(0, .slice i32), (1, i32), (2, .slice i32), (3, .slice i32), (4, i32),
    (5, i32), (6, i32), (7, .slice i32), (8, i32)]
def recurseArguments : List Expr := (List.range 9).map read
def saveArguments (rax : ConstantId) : List Expr := [read 3, read 4, read 2, read 9, .constant rax]
def rejected : Expr := .binary .less (read 9) (number 0)
def preparation (allocate save : FunctionId) (rax : ConstantId) (rest : Stmt) : Stmt :=
  .letLocal 9 i32 (.call allocate [read 2, number 1])
    (.sequence (.ifThenElse rejected (returned (.value (.boolean false))) .skip)
      (.sequence (.expression (.call save (saveArguments rax))) rest))
def continuation (expression address : FunctionId) : Stmt :=
  .letLocal 10 i32 (.call expression recurseArguments)
    (returned (.binary .greaterEqual (.call address [read 3, read 4, read 2, read 9, read 10]) (number 0)))

/-- Authenticate the recursive caller and all nonrecursive callees against
one source pack. The expression callee's correctness is deliberately not
asserted here; it is the recursive simulation's induction obligation. -/
structure Checked (emitters : CheckedBuffer encoded sources) where
  allocate : Allocate.Checked emitters.pack.program
  index : Index.Checked emitters
  store : Memory.CheckedMove emitters.pack.program index.helpers.memory false
  save : Slot.Checked emitters.pack.program .save64 store index.helpers.offset
  expression : CoreSynthesis.Program.CheckedSourceFunction emitters.pack.program ["backend", "compile"] "expression"
  expressionSignature : expression.function.parameters = parameters ∧ expression.function.returnType = i32 ∧
    expression.function.external = none
  internal : Extraction.Source.CheckedInternal emitters.pack.program ["backend", "compile"] "indexed" parameters (.scalar .bool)
    (preparation allocate.internal.source.function.id save.internal.source.function.id index.constants.rax.id
      (continuation expression.function.id index.internal.source.function.id))

def check? (emitters : CheckedBuffer encoded sources) : Option (Checked emitters) := do
  let allocate ← Allocate.check? emitters.pack.program
  let index ← Index.check? emitters
  let store ← Memory.checkMove? emitters.pack.program index.helpers.memory false
  let save ← Slot.check? emitters.pack.program .save64 store index.helpers.offset
  let expression ← CoreSynthesis.Program.checkSourceFunction? emitters.pack.program ["backend", "compile"] "expression"
  if signature : expression.function.parameters = parameters ∧ expression.function.returnType = i32 ∧
      expression.function.external = none then
    let internal ← Extraction.Source.checkInternal? emitters.pack.program ["backend", "compile"] "indexed" parameters (.scalar .bool)
      (preparation allocate.internal.source.function.id save.internal.source.function.id index.constants.rax.id
        (continuation expression.function.id index.internal.source.function.id))
    pure ⟨allocate, index, store, save, expression, signature, internal⟩
  else none

end Lanius.X86.Source.Expression.Indexed
