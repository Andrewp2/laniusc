import Lanius.Extraction.Parser.Derivation.Initialize
import Lanius.Extraction.Parser.Derivation.Step

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

/-- Cell results of one child emission. Keeping this assertion independent
    of temporary local bindings lets it survive all three lexical exits. -/
structure ReaderRuntime.ChildCells (reader : ReaderRuntime) (state : EarleyState)
    (remaining : Nat) (runtime : State) : Prop where
  current : runtime.cellEntry? reader.currentCell = some {
    id := reader.currentCell, value := some (.signed .i32 (previousValue state.previous)) }
  remainingValue : runtime.cellEntry? reader.remainingCell = some {
    id := reader.remainingCell, value := some (.signed .i32 (Int.ofNat remaining)) }
  artifact : RecognizerWorkspaceArtifact reader.layout reader.workspace
    reader.workspaceValues reader.workspaceCell runtime
  output : runtime.cellEntry? reader.outputCell = some {
    id := reader.outputCell, value := some (.array (signedI32Values
      (((reader.outputValues.set (reader.offset + 4 + remaining * 3) (childTag state.child)).set
        (reader.offset + 4 + remaining * 3 + 1) (childPayload state.child)).set
        (reader.offset + 4 + remaining * 3 + 2) (childKind state.child)))) }

def ReaderRuntime.childBody (reader : ReaderRuntime) : Stmt :=
  let readField := fun selector => Expr.call extractedParserStateValueFunction.id
    [.local reader.stores.workspace, .local reader.stores.base, .local reader.stores.current,
      .constant selector]
  .letLocal reader.tail.previous parserI32Type (readField 33)
    (.letLocal reader.stores.tag parserI32Type (readField 34)
      (.letLocal reader.stores.payload parserI32Type (readField 35)
        (guardedStores reader.stores reader.tail reader.offsetId reader.tokenCountId)))

/-- All child-field reads, both guards, all output stores, cursor updates,
    and lexical exits execute from the reader frame. No execution premise
    remains for any part of this source section. -/
theorem ReaderRuntime.At.execute_child {reader : ReaderRuntime}
    (held : reader.At stateId (remaining + 1) before)
    (accessor : reader.stores.accessor = extractedParserStateValueFunction.id)
    (selector : reader.stores.selector = 36)
    (sound : WorkspaceBackpointersSound grammar tokens reader.workspace)
    (found : reader.workspace.state? stateId = some state) (nonempty : state.dot ≠ 0)
    (tokenCount : reader.tokenCount = tokens.length)
    (distinctBuffers : reader.outputCell ≠ reader.workspaceCell)
    (distinctCursors : reader.currentCell ≠ reader.remainingCell)
    (fits : reader.offset + 4 + count * 3 ≤ reader.outputValues.length)
    (capacityBound : reader.outputValues.length ≤ 2147483647)
    (remainingBound : remaining + 1 ≤ count)
    (freshSlot : ∀ localId ∈ [reader.stores.output, reader.stores.workspace, reader.stores.base,
      reader.stores.tag, reader.stores.payload, reader.stores.current, reader.tail.remaining,
      reader.tail.previous], reader.stores.slot ≠ localId)
    (previousFresh : reader.tail.previous ∉ reader.liveLocals)
    (tagFresh : reader.stores.tag ∉ reader.liveLocals)
    (payloadFresh : reader.stores.payload ∉ reader.liveLocals)
    (distinct : reader.tail.previous ≠ reader.stores.tag ∧
      reader.tail.previous ≠ reader.stores.payload ∧ reader.stores.tag ≠ reader.stores.payload) :
    ∃ after, Executes verifiedParserCore before reader.childBody .next after ∧
      reader.ChildCells state remaining after ∧
      CellEffect (CellSet.union (CellSet.singleton reader.outputCell)
        (CellSet.union (CellSet.singleton reader.currentCell) (CellSet.singleton reader.remainingCell)))
        before after := by
  obtain ⟨after, execution, result, effect⟩ := held.initialize_child
    (post := fun cells => reader.ChildCells state remaining { before with cells := cells })
    found previousFresh tagFresh payloadFresh distinct
    (guardedStores reader.stores reader.tail reader.offsetId reader.tokenCountId) (by
      intro runtime entered previousLocal tagLocal payloadLocal
      obtain ⟨completed, body, currentAfter, remainingAfter, artifactAfter, backingAfter, bodyEffect⟩ :=
        reader.stores.execute_guarded reader.tail accessor selector entered.artifact entered.wellFormed
          sound found nonempty distinctBuffers fits capacityBound remainingBound freshSlot
          entered.offsetLocal (by simpa only [tokenCount] using entered.tokenCountLocal)
          entered.outputLocal entered.workspaceLocal entered.baseLocal tagLocal payloadLocal
          entered.currentOwned entered.remainingOwned distinctCursors previousLocal entered.backing
      exact ⟨completed, body, ⟨currentAfter.2, remainingAfter.2,
        artifactAfter.transfer_cells rfl, backingAfter⟩, bodyEffect⟩)
  exact ⟨after, execution, ⟨result.current, result.remainingValue,
    result.artifact.transfer_cells rfl, result.output⟩, effect⟩

end Lanius.Extraction.ParserDerivation
