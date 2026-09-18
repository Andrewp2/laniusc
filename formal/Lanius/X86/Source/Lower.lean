import Lanius.X86.Source.Check
import Lanius.X86.Source.Table
import Lanius.X86.Lower.Return
import Lanius.FunctionalViewCoreStatefulReification
import Lanius.X86.Select.Syntax

namespace Lanius.X86.Source.Lower

open Lanius.Core Lanius.Extraction Lanius.Extraction.CoreSynthesis.Program
open Lanius.FunctionalView.Core

def argumentEntries : List (Int × Int) := [(0, 7), (1, 6), (2, 2), (3, 1), (4, 8), (5, 9)]

abbrev CheckedArgumentRegister (program : CheckedProgram artifacts) :=
  Table.Checked program ["backend", "parameter"] "argument_register" argumentEntries

def checkArgumentRegister? (program : CheckedProgram artifacts) : Option (CheckedArgumentRegister program) :=
  Table.check? program ["backend", "parameter"] "argument_register" argumentEntries

/-- The selector's exact source-derived stateful view, without an assumed
selection result. Its functional correctness is a separate obligation. -/
structure CheckedSelector (program : CheckedProgram artifacts) where
  source : CheckedSourceFunction program ["backend", "parameter"] "select"
  signature : source.function.parameters = [(0, .slice i32), (1, i32)] ∧
    source.function.returnType = i32 ∧ source.function.external = none
  body : Stmt
  bodyPresent : source.function.body = some body
  bodyExact : body = Select.Syntax.body
  view : Stateful.Reification.ReifiedCommand program.core source.function.returnType
    (Lanius.Typing.parameterContext source.function.parameters) false (identityLayout (arity := 2)) 2 body

def checkSelector? (program : CheckedProgram artifacts) : Option (CheckedSelector program) := do
  let source ← checkSourceFunction? program ["backend", "parameter"] "select"
  if signature : source.function.parameters = [(0, .slice i32), (1, i32)] ∧
      source.function.returnType = i32 ∧ source.function.external = none then
    match bodyPresent : source.function.body with
    | none => none
    | some body => do
      let exactBody ← Lanius.Core.Equality.statement? body Select.Syntax.body
      let view ← Stateful.Reification.reifyCommand? program.core source.function.returnType
        (Lanius.Typing.parameterContext source.function.parameters) false (identityLayout (arity := 2)) 2 body
      pure ⟨source, signature, body, bodyPresent, exactBody.equal, view⟩
  else none

def rejectNegative (id : VarId) : Stmt :=
  .ifThenElse (.binary .less (read id) (number 0)) (returned negativeOne) .skip

def returnTail (returnNear : FunctionId) : Stmt :=
  .sequence (rejectNegative 8) (returned (.call returnNear [read 2, read 3, read 8]))

def moveTail (move returnNear : FunctionId) (resultRegister : ConstantId) : Stmt :=
  .letLocal 8 i32 (.call move [read 2, read 3, read 4, number 32, .constant resultRegister, read 6])
    (returnTail returnNear)

def reserveTail (fits move returnNear : FunctionId) (resultRegister : ConstantId) : Stmt :=
  .sequence (.ifThenElse (.unary .logicalNot (.call fits [read 3, read 4, read 7]))
    (returned negativeOne) .skip) (moveTail move returnNear resultRegister)

def chooseSize : Stmt :=
  .ifThenElse (.binary .greaterEqual (read 5) (number 4))
    (.sequence (.expression (.assign .set (.local 7) (number 4))) .skip) .skip

def mappedTail (fits move returnNear : FunctionId) (resultRegister : ConstantId) : Stmt :=
  .letLocal 7 i32 (number 3) (.sequence chooseSize (reserveTail fits move returnNear resultRegister))

def selectedTail (mapping fits move returnNear : FunctionId) (resultRegister : ConstantId) : Stmt :=
  .sequence (rejectNegative 5)
    (.letLocal 6 i32 (.call mapping [read 5]) (mappedTail fits move returnNear resultRegister))

def compileBody (selector mapping fits move returnNear : FunctionId) (resultRegister : ConstantId) : Stmt :=
  .letLocal 5 i32 (.call selector [read 0, read 1]) (selectedTail mapping fits move returnNear resultRegister)

def compileParameters : List (VarId × Ty) :=
  [(0, .slice i32), (1, i32), (2, .slice i32), (3, i32), (4, i32)]

private def resultConstant? (move : FunctionId) : Stmt → Option ConstantId
  | .letLocal _ _ (.call callee [_, _, _, _, .constant id, _]) rest =>
      if callee = move then some id else resultConstant? move rest
  | .letLocal _ _ _ rest | .sequence _ rest => resultConstant? move rest
  | _ => none

structure CheckedCompile (emitters : CheckedBuffer encoded sources) where
  selector : CheckedSelector emitters.pack.program
  mapping : CheckedArgumentRegister emitters.pack.program
  resultRegister : IntegerConstant emitters.pack.program.core
  resultZero : resultRegister.value = 0
  internal : Extraction.Source.CheckedInternal emitters.pack.program ["backend", "parameter"] "compile"
    compileParameters i32 (compileBody selector.source.function.id mapping.internal.source.function.id
      emitters.fits.source.function.id (emitters.registerWrappers .move).source.function.id
      emitters.returnNear.source.function.id resultRegister.id)

def checkCompile? (emitters : CheckedBuffer encoded sources) : Option (CheckedCompile emitters) := do
  let selector ← checkSelector? emitters.pack.program
  let mapping ← checkArgumentRegister? emitters.pack.program
  let source ← checkSourceFunction? emitters.pack.program ["backend", "parameter"] "compile"
  let actual ← source.function.body
  let resultId ← resultConstant? (emitters.registerWrappers .move).source.function.id actual
  let resultRegister ← integerConstant? emitters.pack.program.core resultId
  if resultZero : resultRegister.value = 0 then
    let internal ← Extraction.Source.checkInternal? emitters.pack.program ["backend", "parameter"] "compile"
      compileParameters i32 (compileBody selector.source.function.id mapping.internal.source.function.id
        emitters.fits.source.function.id (emitters.registerWrappers .move).source.function.id
        emitters.returnNear.source.function.id resultRegister.id)
    pure ⟨selector, mapping, resultRegister, resultZero, internal⟩
  else none

end Lanius.X86.Source.Lower
