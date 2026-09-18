import Lanius.Extraction.Entry.File.Handoff

namespace Lanius.Extraction.Entry.File
open Lanius.Core Lanius.Semantics Lanius.Properties
open Lanius.Extraction.Frontend Lanius.Extraction.CompactOutput

/-- Ordinary invocation resources for the repeated file body. The source is
the requested file, working arrays may contain earlier results, and output
already contains earlier units. This record includes no component execution,
successful parse, accepted output, or internal parser invariant. -/
structure Resources (pipeline : Load.Pipeline program) (syntaxStage : Syntax.Stage)
    (collectStage : Collect.Stage) (emitStage : Emit.Stage) (argument : VarId) (before : State) where
  input : Load.Input pipeline before
  data : SyntaxData
  buffers : Load.FrontendBuffers input data
  valid : data.Valid
  capacities : Syntax.Capacities data
  reads : syntaxStage.Reads data input.source.length before
  kindsFit : data.grammar.grammar.n_kinds ≤ 32768
  grammarIdentity : data.grammar.grammar = laniusGrammar
  semantic : SavedBuffer input
  output : SavedBuffer input
  semanticCapacity : semantic.contents.length = 131072
  outputCapacity : output.contents.length = 16777216
  semanticRead : before.local? collectStage.semantic = some (.slice i32 semantic.view.root [] 0 semantic.contents.length)
  outputRead : before.local? emitStage.output = some (.slice i32 output.view.root [] 0 output.contents.length)
  position : Int
  positionRead : before.local? emitStage.position = some (.signed .i32 position)
  semanticSeparate : ∀ cell ∈ data.bufferRoots, cell ≠ semantic.view.root
  outputSeparate : ∀ cell ∈ data.bufferRoots, cell ≠ output.view.root
  outputSemantic : output.view.root ≠ semantic.view.root
  differentCursors : before.cellId? argument ≠ before.cellId? emitStage.position
  indexBound : input.index + 1 ≤ 2147483647
  olderHandles : ∀ handle ∈ before.world.fileHandles, handle.id < (before.world.nextFileHandle : Int)

end Lanius.Extraction.Entry.File
