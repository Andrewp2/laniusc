import Lanius.Extraction.CompactOutput.Unit.Inputs

namespace Lanius.Extraction.CompactOutput.Unit

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- Reuse the same logical inputs after the initializer and fresh local.
Only storage/local preservation and unchanged output allocation are needed. -/
def Inputs.transport (inputs : Inputs before outputCell outputLength)
    (cellEqual : nextOutput = outputCell) (lengthEqual : nextLength = outputLength)
    (original : List Int)
    (keep : ∀ id value, id ≠ 19 → before.local? id = some value →
      value ≠ .array (signedI32Values original) → after.local? id = some value)
    (preserve : ∀ cell physicalCapacity values, I32Prefix before cell physicalCapacity values →
      outputCell ≠ cell → I32Prefix after cell physicalCapacity values) :
    Inputs after nextOutput nextLength where
  path := {
    values := inputs.path.values, cell := inputs.path.cell, capacity := inputs.path.capacity
    input := preserve _ _ _ inputs.path.input inputs.path.distinct
    inputRead := keep _ _ (by decide) inputs.path.inputRead (by intro same; cases same)
    lengthRead := keep _ _ (by decide) inputs.path.lengthRead (by intro same; cases same)
    distinct := cellEqual ▸ inputs.path.distinct
    lengthFit := inputs.path.lengthFit, byteBound := inputs.path.byteBound }
  source := {
    values := inputs.source.values, cell := inputs.source.cell, capacity := inputs.source.capacity
    input := preserve _ _ _ inputs.source.input inputs.source.distinct
    inputRead := keep _ _ (by decide) inputs.source.inputRead (by intro same; cases same)
    lengthRead := keep _ _ (by decide) inputs.source.lengthRead (by intro same; cases same)
    distinct := cellEqual ▸ inputs.source.distinct
    lengthFit := inputs.source.lengthFit, byteBound := inputs.source.byteBound }
  raw := {
    tokens := inputs.raw.tokens, cell := inputs.raw.cell, capacity := inputs.raw.capacity
    inputLength := inputs.raw.inputLength
    input := preserve _ _ _ inputs.raw.input inputs.raw.distinct
    inputRead := keep _ _ (by decide) inputs.raw.inputRead (by intro same; cases same)
    lengthRead := keep _ _ (by decide) inputs.raw.lengthRead (by intro same; cases same)
    countRead := keep _ _ (by decide) inputs.raw.countRead (by intro same; cases same)
    distinct := cellEqual ▸ inputs.raw.distinct
    inputRoom := inputs.raw.inputRoom, lengthFit := inputs.raw.lengthFit, fields := inputs.raw.fields }
  canonical := {
    tokens := inputs.canonical.tokens, cell := inputs.canonical.cell, capacity := inputs.canonical.capacity
    inputLength := inputs.canonical.inputLength
    input := preserve _ _ _ inputs.canonical.input inputs.canonical.distinct
    inputRead := keep _ _ (by decide) inputs.canonical.inputRead (by intro same; cases same)
    lengthRead := keep _ _ (by decide) inputs.canonical.lengthRead (by intro same; cases same)
    countRead := keep _ _ (by decide) inputs.canonical.countRead (by intro same; cases same)
    distinct := cellEqual ▸ inputs.canonical.distinct
    inputRoom := inputs.canonical.inputRoom, lengthFit := inputs.canonical.lengthFit, fields := inputs.canonical.fields }
  semantic := {
    assignments := inputs.semantic.assignments, cell := inputs.semantic.cell, capacity := inputs.semantic.capacity
    inputLength := inputs.semantic.inputLength
    input := preserve _ _ _ inputs.semantic.input inputs.semantic.distinct
    inputRead := keep _ _ (by decide) inputs.semantic.inputRead (by intro same; cases same)
    lengthRead := keep _ _ (by decide) inputs.semantic.lengthRead (by intro same; cases same)
    countEqual := inputs.semantic.countEqual
    distinct := cellEqual ▸ inputs.semantic.distinct
    inputRoom := inputs.semantic.inputRoom, lengthFit := inputs.semantic.lengthFit, fields := inputs.semantic.fields }
  nodes := {
    records := inputs.nodes.records, words := inputs.nodes.words, cell := inputs.nodes.cell
    capacity := inputs.nodes.capacity, offsetCell := inputs.nodes.offsetCell, offsetCapacity := inputs.nodes.offsetCapacity
    inputLength := inputs.nodes.inputLength
    input := preserve _ _ _ inputs.nodes.input inputs.nodes.distinctInput
    offsets := preserve _ _ _ inputs.nodes.offsets inputs.nodes.distinctOffsets
    inputRead := keep _ _ (by decide) inputs.nodes.inputRead (by intro same; cases same)
    lengthRead := keep _ _ (by decide) inputs.nodes.lengthRead (by intro same; cases same)
    offsetRead := keep _ _ (by decide) inputs.nodes.offsetRead (by intro same; cases same)
    nodesRead := keep _ _ (by decide) inputs.nodes.nodesRead (by intro same; cases same)
    distinctInput := cellEqual ▸ inputs.nodes.distinctInput
    distinctOffsets := cellEqual ▸ inputs.nodes.distinctOffsets
    inputRoom := inputs.nodes.inputRoom, inputFit := inputs.nodes.inputFit, nodesFit := inputs.nodes.nodesFit
    stored := inputs.nodes.stored, fields := inputs.nodes.fields, linked := inputs.nodes.linked
    tokenBound := inputs.nodes.tokenBound }
  capacity := inputs.capacity
  outputRead := by
    rw [cellEqual, lengthEqual]
    exact keep _ _ (by decide) inputs.outputRead (by intro same; cases same)
  capacityRead := keep _ _ (by decide) inputs.capacityRead (by intro same; cases same)
  room := lengthEqual ▸ inputs.room
  capacityFit := inputs.capacityFit

end Lanius.Extraction.CompactOutput.Unit
