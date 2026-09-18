import Lanius.Extraction.Entry.Files.Frontend.Separation
import Lanius.Extraction.Entry.Files.History

namespace Lanius.Extraction.Entry.Files
open Lanius.Core

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}

/-- Static allocation and binding checks for the first semantic/output
buffers and the cursor initialized by startup. -/
structure OutputSource (pipeline : File.Load.Pipeline program) (syntaxStage : File.Syntax.Stage)
    (collectStage : File.Collect.Stage) (emitStage : File.Emit.Stage) (header : Header.Stage)
    (buffers : List Allocation.Buffer) (aliases : List Pointers.Alias)
    (literal : Grammar.LiteralStage) (framing : Framing.Stage) where
  semantic : BufferSource buffers aliases literal framing pipeline.path.argument collectStage.semantic 131072
  output : BufferSource buffers aliases literal framing pipeline.path.argument emitStage.output 16777216
  outputBinding : emitStage.output = framing.output
  positionBinding : emitStage.position = header.position
  argumentPosition : pipeline.path.argument ≠ emitStage.position
  semanticOutput : collectStage.semantic ≠ emitStage.output
  semanticLoading : collectStage.semantic ≠ pipeline.unpack.locals.packed ∧
    collectStage.semantic ≠ pipeline.unpack.locals.output ∧ collectStage.semantic ≠ pipeline.read.output ∧
    collectStage.semantic ≠ pipeline.read.packed
  outputLoading : emitStage.output ≠ pipeline.unpack.locals.packed ∧
    emitStage.output ≠ pipeline.unpack.locals.output ∧ emitStage.output ≠ pipeline.read.output ∧
    emitStage.output ≠ pipeline.read.packed
  semanticFrontend : ∀ id ∈ syntaxStage.bufferLocals, id ≠ collectStage.semantic
  outputFrontend : ∀ id ∈ syntaxStage.bufferLocals, id ≠ emitStage.output
  capacity : framing.capacity = 16777216

def checkOutputSource? (pipeline : File.Load.Pipeline program) (syntaxStage : File.Syntax.Stage)
    (collectStage : File.Collect.Stage) (emitStage : File.Emit.Stage) (header : Header.Stage)
    (buffers : List Allocation.Buffer) (aliases : List Pointers.Alias)
    (literal : Grammar.LiteralStage) (framing : Framing.Stage) :
    Option (OutputSource pipeline syntaxStage collectStage emitStage header buffers aliases literal framing) := do
  let semantic ← checkBufferSource? buffers aliases literal framing pipeline.path.argument collectStage.semantic 131072
  let output ← checkBufferSource? buffers aliases literal framing pipeline.path.argument emitStage.output 16777216
  if valid : emitStage.output = framing.output ∧ emitStage.position = header.position ∧
      pipeline.path.argument ≠ emitStage.position ∧ collectStage.semantic ≠ emitStage.output ∧
      (collectStage.semantic ≠ pipeline.unpack.locals.packed ∧ collectStage.semantic ≠ pipeline.unpack.locals.output ∧
        collectStage.semantic ≠ pipeline.read.output ∧ collectStage.semantic ≠ pipeline.read.packed) ∧
      (emitStage.output ≠ pipeline.unpack.locals.packed ∧ emitStage.output ≠ pipeline.unpack.locals.output ∧
        emitStage.output ≠ pipeline.read.output ∧ emitStage.output ≠ pipeline.read.packed) ∧
      (∀ id ∈ syntaxStage.bufferLocals, id ≠ collectStage.semantic) ∧
      (∀ id ∈ syntaxStage.bufferLocals, id ≠ emitStage.output) then
    if capacity : framing.capacity = 16777216 then
      pure ⟨semantic, output, valid.1, valid.2.1, valid.2.2.1, valid.2.2.2.1,
        valid.2.2.2.2.1, valid.2.2.2.2.2.1, valid.2.2.2.2.2.2.1, valid.2.2.2.2.2.2.2, capacity⟩
    else none
  else none

end Lanius.Extraction.Entry.Files
