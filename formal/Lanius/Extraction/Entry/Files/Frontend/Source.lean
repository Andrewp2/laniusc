import Lanius.Extraction.Entry.Files.Input

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}

/-- Source-only selection of the eight frontend allocations and their
separation from the four loading buffers. -/
structure FrontendSource (pipeline : File.Load.Pipeline program) (stage : File.Syntax.Stage)
    (buffers : List Allocation.Buffer) (aliases : List Pointers.Alias)
    (literal : Grammar.LiteralStage) (framing : Framing.Stage) where
  source : BufferSource buffers aliases literal framing pipeline.path.argument stage.source 65536
  grammar : BufferSource buffers aliases literal framing pipeline.path.argument stage.grammar 2179
  raw : BufferSource buffers aliases literal framing pipeline.path.argument stage.raw 65536
  canonical : BufferSource buffers aliases literal framing pipeline.path.argument stage.canonical 65536
  kinds : BufferSource buffers aliases literal framing pipeline.path.argument stage.kinds 65536
  workspace : BufferSource buffers aliases literal framing pipeline.path.argument stage.workspace 4194304
  records : BufferSource buffers aliases literal framing pipeline.path.argument stage.records 1048576
  offsets : BufferSource buffers aliases literal framing pipeline.path.argument stage.offsets 65536
  sourceBinding : stage.source = pipeline.read.output
  grammarBinding : stage.grammar = literal.setup.cursor.locals.destination
  grammarCount : literal.setup.cursor.locals.count = 2179
  distinct : stage.bufferLocals.Nodup
  loadingApart : ∀ id ∈ stage.bufferLocals.tail,
    id ≠ pipeline.unpack.locals.packed ∧ id ≠ pipeline.unpack.locals.output ∧
    id ≠ pipeline.read.output ∧ id ≠ pipeline.read.packed

def checkFrontendSource? (pipeline : File.Load.Pipeline program) (stage : File.Syntax.Stage)
    (buffers : List Allocation.Buffer) (aliases : List Pointers.Alias)
    (literal : Grammar.LiteralStage) (framing : Framing.Stage) :
    Option (FrontendSource pipeline stage buffers aliases literal framing) := do
  let source ← checkBufferSource? buffers aliases literal framing pipeline.path.argument stage.source 65536
  let grammar ← checkBufferSource? buffers aliases literal framing pipeline.path.argument stage.grammar 2179
  let raw ← checkBufferSource? buffers aliases literal framing pipeline.path.argument stage.raw 65536
  let canonical ← checkBufferSource? buffers aliases literal framing pipeline.path.argument stage.canonical 65536
  let kinds ← checkBufferSource? buffers aliases literal framing pipeline.path.argument stage.kinds 65536
  let workspace ← checkBufferSource? buffers aliases literal framing pipeline.path.argument stage.workspace 4194304
  let records ← checkBufferSource? buffers aliases literal framing pipeline.path.argument stage.records 1048576
  let offsets ← checkBufferSource? buffers aliases literal framing pipeline.path.argument stage.offsets 65536
  if valid : stage.source = pipeline.read.output ∧ stage.grammar = literal.setup.cursor.locals.destination ∧
      literal.setup.cursor.locals.count = 2179 ∧ stage.bufferLocals.Nodup ∧
      ∀ id ∈ stage.bufferLocals.tail, id ≠ pipeline.unpack.locals.packed ∧ id ≠ pipeline.unpack.locals.output ∧
        id ≠ pipeline.read.output ∧ id ≠ pipeline.read.packed then
    pure ⟨source, grammar, raw, canonical, kinds, workspace, records, offsets,
      valid.1, valid.2.1, valid.2.2.1, valid.2.2.2.1, valid.2.2.2.2⟩
  else none

end Lanius.Extraction.Entry.Files
