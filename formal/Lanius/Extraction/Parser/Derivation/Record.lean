import Lanius.Extraction.Parser.Derivation.Walk
import Lanius.Extraction.Parser.Derivation.Header

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

/-- Emit the full record from saved root metadata, including header writes,
    cursor setup, child traversal, seed checks, and return. The initial
    capacity/metadata guards and root-field initializers precede this region. -/
theorem ReaderRuntime.BeforeCursor.execute_record {reader : ReaderRuntime}
    (entry : reader.BeforeCursor before)
    (accessor : reader.stores.accessor = extractedParserStateValueFunction.id)
    (selector : reader.stores.selector = 36)
    (sound : WorkspaceBackpointersSound grammar tokens reader.workspace)
    (found : reader.workspace.state? stateId = some root)
    (stateLocal : before.local? stateIdLocal = some (.signed .i32 (Int.ofNat stateId)))
    (countLocal : before.local? countId = some (.signed .i32 (Int.ofNat root.dot)))
    (productionLocal : before.local? productionId = some (.signed .i32 (Int.ofNat root.production)))
    (originLocal : before.local? originId = some (.signed .i32 (Int.ofNat root.origin)))
    (tokenCount : reader.tokenCount = tokens.length)
    (distinctBuffers : reader.outputCell ≠ reader.workspaceCell)
    (capacityBound : reader.outputValues.length ≤ 2147483647)
    (different : reader.stores.current ≠ reader.tail.remaining)
    (currentFresh : reader.stores.current ∉ reader.readonlyLocals)
    (remainingFresh : reader.tail.remaining ∉ reader.readonlyLocals)
    (metadataFresh : ∀ localId ∈ [productionId, originId, countId],
      reader.stores.current ≠ localId ∧ reader.tail.remaining ≠ localId)
    (freshSlot : ∀ localId ∈ [reader.stores.output, reader.stores.workspace, reader.stores.base,
      reader.stores.tag, reader.stores.payload, reader.stores.current, reader.tail.remaining,
      reader.tail.previous], reader.stores.slot ≠ localId)
    (previousFresh : reader.tail.previous ∉ reader.liveLocals)
    (tagFresh : reader.stores.tag ∉ reader.liveLocals)
    (payloadFresh : reader.stores.payload ∉ reader.liveLocals)
    (distinct : reader.tail.previous ≠ reader.stores.tag ∧
      reader.tail.previous ≠ reader.stores.payload ∧ reader.stores.tag ≠ reader.stores.payload)
    (contents : reader.outputValues = leading ++ [oldProduction, oldOrigin, oldPosition, oldCount] ++ pending ++ trailing)
    (offset : leading.length = reader.offset) (pendingLength : pending.length = root.dot * 3) :
    ∃ children after, children.length = root.dot ∧
      derivationChildren? reader.workspace (stateId + 1) stateId = some children ∧
      Executes verifiedParserCore before
        (readerHeader reader.stores productionId originId reader.offsetId countId stateIdLocal 28
          (reader.walkBody stateIdLocal countId productionId originId))
        (.returned (some (.signed .i32 (Int.ofNat root.dot)))) after ∧
      after.cellEntry? reader.outputCell = some {
        id := reader.outputCell, value := some (.array (signedI32Values
          (leading ++ derivationRecordWords root children ++ trailing))) } ∧
      RecognizerWorkspaceArtifact reader.layout reader.workspace reader.workspaceValues reader.workspaceCell after ∧
      CellEffect (CellSet.singleton reader.outputCell) before after := by
  have size : reader.outputValues.length = reader.offset + 4 + root.dot * 3 + trailing.length := by
    simp only [contents, List.length_append, List.length_cons, List.length_nil, offset, pendingLength]
  obtain ⟨middle, headerExecution, backing, artifact, _, effect⟩ :=
    entry.artifact.store_header entry.wellFormed found distinctBuffers (by omega) (by omega)
      entry.outputLocal entry.workspaceLocal entry.baseLocal stateLocal entry.offsetLocal
      productionLocal originLocal countLocal entry.backing
  let header := leading ++ [Int.ofNat root.production, Int.ofNat root.origin,
    Int.ofNat root.position, Int.ofNat root.dot]
  let initialized := { reader with outputValues := header ++ pending ++ trailing }
  have updated : (((reader.outputValues.set reader.offset (Int.ofNat root.production)).set
      (reader.offset + 1) (Int.ofNat root.origin)).set (reader.offset + 2) (Int.ofNat root.position)).set
      (reader.offset + 3) (Int.ofNat root.dot) = initialized.outputValues := by
    have replaced := header_words_store leading (pending ++ trailing) oldProduction oldOrigin oldPosition oldCount root
    simpa only [initialized, header, ← offset, contents, List.append_assoc] using replaced
  rw [updated] at backing
  have sameLength : initialized.outputValues.length = reader.outputValues.length := by
    simp only [initialized, header, contents, List.length_append, List.length_cons, List.length_nil]
  have preserve {localId : VarId} {value : Value} (localValue : before.local? localId = some value)
      (notArray : value ≠ .array (signedI32Values reader.outputValues)) : middle.local? localId = some value :=
    effect.preserves_local_of_distinct_value entry.wellFormed localValue entry.backing notArray
  have prepared : initialized.BeforeCursor middle := ⟨effect.wellFormed, artifact,
    by simpa only [sameLength] using preserve entry.outputLocal (by simp),
    preserve entry.workspaceLocal (by simp), preserve entry.baseLocal (by simp),
    preserve entry.offsetLocal (by simp), preserve entry.tokenCountLocal (by simp), backing⟩
  obtain ⟨children, after, length, computed, walk, output, finalArtifact, walkEffect⟩ :=
    prepared.execute_walk accessor selector sound found (preserve stateLocal (by simp))
      (preserve countLocal (by simp)) (preserve productionLocal (by simp)) (preserve originLocal (by simp))
      tokenCount distinctBuffers (by change reader.offset + 4 + root.dot * 3 ≤ initialized.outputValues.length; rw [sameLength]; omega)
      (by rw [sameLength]; exact capacityBound) different currentFresh remainingFresh metadataFresh
      freshSlot previousFresh tagFresh payloadFresh distinct (header := header) (trailing := trailing) (by
        refine ⟨?_, pending, pendingLength, ?_⟩
        · simp [header, offset, initialized]
        · simp [initialized])
  obtain ⟨first, store0, rest⟩ := executesSequenceNext_inv headerExecution
  obtain ⟨second, store1, lastTwo⟩ := executesSequenceNext_inv rest
  refine ⟨children, after, length, computed, ?_, ?_, finalArtifact, effect.trans walkEffect⟩
  · simpa only [readerHeader, ReaderRuntime.walkBody, initialized, accessor] using
      executesSequence store0 (executesSequence store1 (executesSequence_continue lastTwo walk))
  · have record := header_children_record root children length
    simpa only [initialized, header, ← record, List.append_assoc] using output

end Lanius.Extraction.ParserDerivation
