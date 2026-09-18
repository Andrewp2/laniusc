import Lanius.Extraction.Frontend.Call
import Lanius.Semantics.Capacity.Call

namespace Lanius.Extraction.Frontend
open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.FunctionalView.Core Lanius.Extraction.RawLexer.LexInto
open Lanius.Extraction.CanonicalTokens.CanonicalizeModel

/-- Concrete caller-owned buffers, with physical source capacity independent
of the logical source length. -/
def SyntaxData.buffers (data : SyntaxData) (tail : List Int) : List (CellId × List Int) :=
  [(data.sourceCell, sourceIntegers data.request.source ++ tail), (data.rawCell, data.records),
    (data.canonicalCell, data.canonical), (data.kindsCell, data.kinds), (data.grammarCell, data.grammarWords),
    (data.workspaceCell, data.workspaceValues), (data.recordsCell, data.treeRecords), (data.offsetsCell, data.treeOffsets)]

def SyntaxData.bufferRoots (data : SyntaxData) : List CellId := (data.buffers []).map Prod.fst

def SyntaxData.PaddedOwns (data : SyntaxData) (tail : List Int) (before : State) : Prop :=
  ∀ buffer ∈ data.buffers tail, before.cellEntry? buffer.1 = some { id := buffer.1, value := some (.array (signedI32Values buffer.2)) }

def SyntaxData.PaddedOwns.input {data : SyntaxData} (owned : data.PaddedOwns tail before) : Semantics.Capacity.Input before where
  root := data.sourceCell
  roots := fun root => data.bufferRoots.contains root
  contents := signedI32Values (sourceIntegers data.request.source)
  tail := signedI32Values tail
  included := by simp [SyntaxData.bufferRoots, SyntaxData.buffers]
  source := by
    have found := owned (data.sourceCell, sourceIntegers data.request.source ++ tail) (by simp [SyntaxData.buffers])
    simpa only [signedI32Values, List.map_append] using found
  contentsPlain := Semantics.Capacity.signedValues_plain _
  buffersPlain := by
    intro root selected entry found
    have member : root ∈ (data.buffers tail).map Prod.fst := by
      simpa [SyntaxData.bufferRoots, SyntaxData.buffers] using List.contains_iff_mem.mp selected
    obtain ⟨buffer, member, same⟩ := List.mem_map.mp member
    have observed : before.cell? root = some (.array (signedI32Values buffer.2)) := by
      simp only [State.cell?, ← same, owned buffer member, Option.bind_some]
    have equal := Option.some.inj (found.symm.trans observed)
    subst entry
    exact Semantics.Capacity.signedValues_plain _

theorem SyntaxData.PaddedOwns.logical {data : SyntaxData} (owned : data.PaddedOwns tail before)
    (valid : data.Valid) (sourceGrammar : data.sourceCell ≠ data.grammarCell)
    (wellFormed : StateWellFormed before) : data.Owns owned.input.logical := by
  have other (root : CellId) (entries : List Int) (different : root ≠ data.sourceCell)
      (member : (root, entries) ∈ data.buffers tail) :
      owned.input.logical.cellEntry? root = some { id := root, value := some (.array (signedI32Values entries)) } :=
    (owned.input.logical_other different).trans (owned (root, entries) member)
  have raw := other data.rawCell data.records valid.sourceRaw.symm (by simp [SyntaxData.buffers])
  refine ⟨?_, other _ _ valid.sourceCanonical.symm (by simp [SyntaxData.buffers]),
    other _ _ valid.sourceKinds.symm (by simp [SyntaxData.buffers]),
    other _ _ sourceGrammar.symm (by simp [SyntaxData.buffers]),
    other _ _ valid.sourceWorkspace.symm (by simp [SyntaxData.buffers]),
    other _ _ (valid.outputSeparation data.sourceCell (by simp)).1.symm (by simp [SyntaxData.buffers]),
    other _ _ (valid.outputSeparation data.sourceCell (by simp)).2.symm (by simp [SyntaxData.buffers])⟩
  have logicalWF := owned.input.logical_wellFormed wellFormed
  exact (ReadOnly.World.owns_iff_represents logicalWF).mpr
    (ReadOnly.World.pair_represents logicalWF valid.sourceRaw.symm owned.input.logical_source raw)

theorem SyntaxData.PaddedOwns.values_closed {data : SyntaxData} (owned : data.PaddedOwns tail before) :
    Semantics.Capacity.closeds owned.input.config data.values = true := by
  simp [SyntaxData.values, Semantics.Capacity.closeds, Semantics.Capacity.closed,
    Semantics.Capacity.Config.reachable, Semantics.Capacity.Input.config, SyntaxData.PaddedOwns.input,
    SyntaxData.bufferRoots, SyntaxData.buffers]

def SyntaxData.paddedValues (data : SyntaxData) (capacityTail : Nat) : List Value :=
  .slice Structure.i32Type data.sourceCell [] 0 (data.request.source.length + capacityTail) :: data.values.tail

theorem SyntaxData.PaddedOwns.argument_values {data : SyntaxData} (owned : data.PaddedOwns tail before)
    (valid : data.Valid) (sourceGrammar : data.sourceCell ≠ data.grammarCell) :
    Semantics.Capacity.values owned.input.config data.values = data.paddedValues tail.length := by
  have sourceRecords := (valid.outputSeparation data.sourceCell (by simp)).1
  have sourceOffsets := (valid.outputSeparation data.sourceCell (by simp)).2
  simp [SyntaxData.values, SyntaxData.paddedValues, Semantics.Capacity.values, Semantics.Capacity.value,
    SyntaxData.PaddedOwns.input, Semantics.Capacity.Input.config, signedI32Values,
    valid.sourceRaw.symm, valid.sourceCanonical.symm, valid.sourceKinds.symm, valid.sourceWorkspace.symm,
    sourceGrammar.symm, sourceRecords.symm, sourceOffsets.symm]

end Lanius.Extraction.Frontend
