import Lanius.Extraction.Entry.Suffix.Source
import Lanius.Extraction.OutputPacking.Source

namespace Lanius.Extraction.Entry.Output
open Lanius.Core Lanius.Extraction.OutputPacking

/-- Authenticate the entire post-suffix tail, its live inputs, scratch locals,
workspace pointer, and modeled stdout service. These are source facts only. -/
structure Source (program : Program) (suffix : Suffix.Stage) where
  preparation : Preparation
  stdout : StdoutTail
  preparationSource : suffix.continuation = preparation.statement
  stdoutSource : preparation.continuation = stdout.statement
  input : preparation.packing.input = suffix.output
  length : preparation.packing.length = suffix.position
  stdoutLength : stdout.length = preparation.packing.length
  capacity : suffix.capacity = 16777216
  previousWorkspace : suffix.previous ≠ preparation.packing.workspace
  previousPointer : suffix.previous ≠ stdout.pointer
  wordDistinct : ∀ id ∈ [preparation.packing.workspace, preparation.packing.input, preparation.packing.length],
    preparation.wordCount ≠ id
  clearDistinct : ∀ id ∈ [preparation.packing.workspace, preparation.wordCount,
      preparation.packing.input, preparation.packing.length], preparation.clearCursor ≠ id
  packDistinct : ∀ id ∈ [preparation.packing.workspace, preparation.packing.input, preparation.packing.length],
    preparation.packing.cursor ≠ id
  pointerDistinct : preparation.wordCount ≠ stdout.pointer ∧ preparation.clearCursor ≠ stdout.pointer ∧
    preparation.packing.cursor ≠ stdout.pointer
  sizeLength : stdout.size ≠ stdout.length
  sizePointer : stdout.size ≠ stdout.pointer
  function : Function
  functionId : function.id = stdout.function
  functionFound : program.function? function.id = some function
  parameters : function.parameters.length = 2
  noBody : function.body = none
  host : function.external = some (.host .writeStdout)

def check? (program : Program) (suffix : Suffix.Stage) : Option (Source program suffix) := do
  let preparation ← checkPreparation? suffix.continuation
  let stdout ← checkStdoutTail? preparation.locals.continuation
  let packing := preparation.locals.packing
  if valid : packing.input = suffix.output ∧ packing.length = suffix.position ∧
      stdout.locals.length = packing.length ∧ suffix.capacity = 16777216 ∧
      suffix.previous ≠ packing.workspace ∧ suffix.previous ≠ stdout.locals.pointer ∧
      (∀ id ∈ [packing.workspace, packing.input, packing.length], preparation.locals.wordCount ≠ id) ∧
      (∀ id ∈ [packing.workspace, preparation.locals.wordCount, packing.input, packing.length], preparation.locals.clearCursor ≠ id) ∧
      (∀ id ∈ [packing.workspace, packing.input, packing.length], packing.cursor ≠ id) ∧
      (preparation.locals.wordCount ≠ stdout.locals.pointer ∧ preparation.locals.clearCursor ≠ stdout.locals.pointer ∧
        packing.cursor ≠ stdout.locals.pointer) ∧
      stdout.locals.size ≠ stdout.locals.length ∧ stdout.locals.size ≠ stdout.locals.pointer then
    let ⟨input, length, stdoutLength, capacity, previousWorkspace, previousPointer,
      wordDistinct, clearDistinct, packDistinct, pointerDistinct, sizeLength, sizePointer⟩ := valid
    match found : program.function? stdout.locals.function with
    | none => none
    | some function =>
      if service : function.id = stdout.locals.function ∧ function.parameters.length = 2 ∧
          function.body = none ∧ function.external = some (.host .writeStdout) then
        pure ⟨preparation.locals, stdout.locals, preparation.exactSource, stdout.exactSource,
          input, length, stdoutLength, capacity, previousWorkspace, previousPointer,
          wordDistinct, clearDistinct, packDistinct, pointerDistinct, sizeLength, sizePointer,
          function, service.1, by simpa only [service.1] using found, service.2.1, service.2.2.1, service.2.2.2⟩
      else none
  else none

end Lanius.Extraction.Entry.Output
