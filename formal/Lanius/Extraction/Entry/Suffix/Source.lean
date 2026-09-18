import Lanius.Extraction.Entry.Framing
import Lanius.Extraction.Entry.Scope
import Lanius.Separation.LocalCall

namespace Lanius.Extraction.Entry.Suffix
open Lanius.Core Lanius.Extraction.CompactOutput

def bytes : List UInt8 := Lanius.World.utf8Bytes ExtractorContract.moduleSuffix

theorem bytes_length : bytes.length = 677 := by decide +kernel

structure Stage where
  previous : VarId
  position : VarId
  output : VarId
  closing : VarId
  capacity : Nat
  continuation : Stmt

def Stage.call (stage : Stage) (function : FunctionId) : Expr :=
  .call function [read stage.output, number stage.capacity, read stage.position, read stage.closing, number bytes.length]

def Stage.statement (stage : Stage) (function : FunctionId) : Stmt :=
  .letLocal stage.previous i32 (read stage.position)
    (.sequence (.expression (.assign .set (.local stage.position) (stage.call function)))
      (.sequence (.ifThenElse (binary .notEqual (read stage.position)
        (binary .add (read stage.previous) (number bytes.length)))
        (returned (number 25)) .skip) stage.continuation))

def check? (function : FunctionId) (statement : Stmt) :
    Option (Source.CheckedStatement (fun stage : Stage => stage.statement function) statement) := do
  let .letLocal previous _ (.local position)
      (.sequence (.expression (.assign .set (.local _) (.call _
        [.local output, .value (.signed .i32 capacity), _, .local closing, _])))
        (.sequence _ continuation)) := statement | none
  let stage : Stage := ⟨previous, position, output, closing, capacity.toNat, continuation⟩
  let same ← Equality.statement? statement (stage.statement function)
  pure ⟨stage, same.equal⟩

structure Supported (stage : Stage) (framing : Framing.Stage) : Prop where
  previousOutput : stage.previous ≠ stage.output
  previousPosition : stage.previous ≠ stage.position
  previousClosing : stage.previous ≠ stage.closing
  output : stage.output = framing.output
  position : stage.position = framing.position
  closing : stage.closing = framing.closing
  capacity : stage.capacity = framing.capacity

def checkSupported? (stage : Stage) (framing : Framing.Stage) : Option (PLift (Supported stage framing)) :=
  if valid : stage.previous ≠ stage.output ∧ stage.previous ≠ stage.position ∧ stage.previous ≠ stage.closing ∧
      stage.output = framing.output ∧ stage.position = framing.position ∧ stage.closing = framing.closing ∧
      stage.capacity = framing.capacity then
    some ⟨⟨valid.1, valid.2.1, valid.2.2.1, valid.2.2.2.1, valid.2.2.2.2.1, valid.2.2.2.2.2.1, valid.2.2.2.2.2.2⟩⟩
  else none

end Lanius.Extraction.Entry.Suffix
