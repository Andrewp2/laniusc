import Lanius.Extraction.Parser.Tree.Frame
import Lanius.Extraction.Parser.Tree.Reader
import Lanius.FunctionalViewCoreSimulation

namespace Lanius.Extraction.ParserTreeSource

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize Lanius.FunctionalView.Core
open Lanius.CallContracts Lanius.Extraction.ParserDerivation Lanius.Extraction.ParserTreeDerivation

private theorem local_read {id : Lanius.VarId} (found : before.local? id = some value) :
    Evaluates program before (.local id) value before :=
  ⟨1, evalLocal_of_local 0 program before id value found⟩

def TreeRuntime.visitValues (runtime : TreeRuntime) (workspaceValues : List Int)
    (workspaceCell : CellId) (tokenCount stateCount stateId depth : Nat) : List Value :=
  [.slice (.scalar (.signed .i32)) workspaceCell [] 0 workspaceValues.length,
   .signed .i32 (Int.ofNat workspaceValues.length), .signed .i32 (Int.ofNat tokenCount),
   .signed .i32 (Int.ofNat stateCount), .signed .i32 (Int.ofNat stateId),
   .slice (.scalar (.signed .i32)) runtime.recordsCell [] 0 runtime.records.length,
   .signed .i32 (Int.ofNat runtime.records.length),
   .slice (.scalar (.signed .i32)) runtime.offsetsCell [] 0 runtime.offsets.length,
   .signed .i32 (Int.ofNat runtime.offsets.length), .signed .i32 (Int.ofNat runtime.nodeBase),
   .signed .i32 (Int.ofNat runtime.wordBase), .signed .i32 (Int.ofNat depth)]

def TreeRuntime.visitBindings (runtime : TreeRuntime) (workspaceValues : List Int)
    (workspaceCell : CellId) (tokenCount stateCount stateId depth : Nat) : List (Lanius.VarId × Value) :=
  parameterBindings (fun index : Fin 12 =>
    (runtime.visitValues workspaceValues workspaceCell tokenCount stateCount stateId depth).get index)

def TreeRuntime.callee (runtime : TreeRuntime) (caller : State) (workspaceValues : List Int)
    (workspaceCell : CellId) (tokenCount stateCount stateId depth : Nat) : State :=
  enterCall caller (runtime.visitBindings workspaceValues workspaceCell tokenCount stateCount stateId depth)

/-- The public twelve-argument entry of the checked source function. No reader
    output, child cursor ownership, or successful nested execution is assumed. -/
structure TreeRuntime.CallEntry (runtime : TreeRuntime) (layout : WorkspaceLayout)
    (workspace : LogicalWorkspace) (workspaceValues : List Int) (workspaceCell : CellId)
    (stateId depth : Nat) (state : State) : Prop where
  frame : runtime.Frame layout workspace workspaceValues workspaceCell depth state
  stateLocal : state.local? 4 = some (.signed .i32 (Int.ofNat stateId))
  recordsLocal : state.local? 5 = some (.slice (.scalar (.signed .i32)) runtime.recordsCell [] 0 runtime.records.length)
  offsetsLocal : state.local? 7 = some (.slice (.scalar (.signed .i32)) runtime.offsetsCell [] 0 runtime.offsets.length)
  capacityLocal : state.local? 8 = some (.signed .i32 (Int.ofNat runtime.offsets.length))
  nodesLocal : state.local? 9 = some (.signed .i32 (Int.ofNat runtime.nodeBase))
  wordsLocal : state.local? 10 = some (.signed .i32 (Int.ofNat runtime.wordBase))
  recordsBacking : state.cellEntry? runtime.recordsCell = some {
    id := runtime.recordsCell, value := some (.array (signedI32Values runtime.records)) }
  offsetsBacking : state.cellEntry? runtime.offsetsCell = some {
    id := runtime.offsetsCell, value := some (.array (signedI32Values runtime.offsets)) }
  buffersDistinct : runtime.recordsCell ≠ runtime.offsetsCell

theorem TreeRuntime.parameters (runtime : TreeRuntime) (wellFormed : StateWellFormed caller) (index : Fin 12) :
    (runtime.callee caller workspaceValues workspaceCell tokenCount stateCount stateId depth).local? index.val =
      some ((runtime.visitValues workspaceValues workspaceCell tokenCount stateCount stateId depth).get index) :=
  enterCall_parameterBindings_matches wellFormed index

/-- Derive all callee-local resources from ordinary caller arrays and argument
    values. Parameter cells are allocated by the source call protocol itself. -/
theorem TreeRuntime.enter (runtime : TreeRuntime) (wellFormed : StateWellFormed caller)
    (artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell caller)
    (records : caller.cellEntry? runtime.recordsCell = some {
      id := runtime.recordsCell, value := some (.array (signedI32Values runtime.records)) })
    (offsets : caller.cellEntry? runtime.offsetsCell = some {
      id := runtime.offsetsCell, value := some (.array (signedI32Values runtime.offsets)) })
    (recordsSeparate : workspaceCell ≠ runtime.recordsCell)
    (offsetsSeparate : workspaceCell ≠ runtime.offsetsCell)
    (buffersDistinct : runtime.recordsCell ≠ runtime.offsetsCell)
    (depthBound : depth ≤ 2147483647) :
    runtime.CallEntry layout workspace workspaceValues workspaceCell stateId depth
      (runtime.callee caller workspaceValues workspaceCell layout.tokenCount workspace.states.length stateId depth) := by
  have parameters := runtime.parameters (workspaceValues := workspaceValues) (workspaceCell := workspaceCell)
    (tokenCount := layout.tokenCount) (stateCount := workspace.states.length) (stateId := stateId) (depth := depth) wellFormed
  have preserve {cell : CellId} {value : Value}
      (found : caller.cellEntry? cell = some { id := cell, value := some value }) :
      (runtime.callee caller workspaceValues workspaceCell layout.tokenCount workspace.states.length stateId depth).cellEntry? cell =
        some { id := cell, value := some value } :=
    ((enterCall_effect caller _).oldCells cell (StateWellFormed.cell_lt_next_of_entry wellFormed found)
      (by simp [CellSet.empty])).trans found
  refine ⟨?_, parameters ⟨4, by decide⟩, parameters ⟨5, by decide⟩, parameters ⟨7, by decide⟩,
    parameters ⟨8, by decide⟩, parameters ⟨9, by decide⟩, parameters ⟨10, by decide⟩,
    preserve records, preserve offsets, buffersDistinct⟩
  exact ⟨enterCall_preserves_wellFormed wellFormed,
    ⟨artifact.workspaceLength, artifact.workspaceEncoded, preserve artifact.workspaceBacking⟩,
    recordsSeparate, offsetsSeparate, parameters ⟨0, by decide⟩, parameters ⟨1, by decide⟩,
    parameters ⟨2, by decide⟩, parameters ⟨3, by decide⟩, parameters ⟨6, by decide⟩,
    parameters ⟨11, by decide⟩, depthBound⟩

theorem CheckedVisit.bind_parameters (checked : CheckedVisit program) (runtime : TreeRuntime) :
    bindParameters checked.source.function.parameters
      (runtime.visitValues workspaceValues workspaceCell tokenCount stateCount stateId depth) =
      some (runtime.visitBindings workspaceValues workspaceCell tokenCount stateCount stateId depth) := by
  rw [checked.signature.1]
  rfl

/-- The same ordinary reader arguments are used on success and capacity failure. -/
theorem TreeRuntime.CallEntry.reader_arguments {runtime : TreeRuntime} (program : Program)
    (input : runtime.CallEntry layout workspace workspaceValues workspaceCell stateId depth before) :
    ArgumentsEvaluateTo program before
      [.local 0, .local 1, .local 2, .local 3, .local 4, .local 5, .local 6, .local 10]
      (readerValues workspaceValues runtime.records workspaceCell runtime.recordsCell layout.tokenCount
        workspace.states.length stateId runtime.wordBase) before := by
  refine .cons (local_read input.frame.workspaceLocal) ?_
  refine .cons (local_read input.frame.workspaceLengthLocal) ?_
  refine .cons (local_read input.frame.tokensLocal) ?_
  refine .cons (local_read input.frame.statesLocal) ?_
  refine .cons (local_read input.stateLocal) (.cons (local_read input.recordsLocal) ?_)
  exact .cons (local_read input.frame.capacityLocal) (.cons (local_read input.wordsLocal) (.nil _ _))

/-- Invoke the actual linked reader from the materializer's public call entry,
    then derive both post-reader resources in the real result-binding scope.
    The exact record, selected children, and decreasing child IDs are results
    of this call proof, not independent caller assumptions. -/
theorem TreeRuntime.CallEntry.read {runtime : TreeRuntime} {symbols : Core.Relocation.Symbols}
    (input : runtime.CallEntry layout workspace workspaceValues workspaceCell stateId depth before)
    (checked : CheckedVisit program) (linked : LinkedReader checked.reader allowed symbols)
    (inverseType : Lanius.TypeId → Lanius.TypeId)
    (inverse : Function.RightInverse inverseType symbols.typeId)
    (sound : WorkspaceBackpointersSound grammar tokens workspace)
    (found : workspace.state? stateId = some runtime.parent)
    (treeEnough : stateId < treeFuel)
    (materialized : materializeStatePrefix? grammar workspace treeFuel stateId = some trees)
    (layoutTokens : layout.tokenCount = tokens.length)
    (recordsBound : runtime.records.length ≤ 2147483647)
    (fits : runtime.wordBase + 4 + runtime.parent.dot * 3 ≤ runtime.records.length)
    (offsetsFit : runtime.nodeBase ≤ runtime.offsets.length)
    (offsetsBound : runtime.offsets.length ≤ 2147483647) :
    ∃ children afterRead, children.length = runtime.parent.dot ∧ trees.length = runtime.parent.dot ∧
      derivationChildren? workspace (stateId + 1) stateId = some children ∧
      ChildrenExpansion grammar workspace children trees ∧
      (∀ childId, .state childId ∈ children → childId < stateId) ∧
      Evaluates program.core before (.call checked.symbols.reader
        [.local 0, .local 1, .local 2, .local 3, .local 4, .local 5, .local 6, .local 10])
        (.signed .i32 (Int.ofNat runtime.parent.dot)) afterRead ∧
      runtime.Entry children (afterRead.bindLocal 12 (.signed .i32 (Int.ofNat runtime.parent.dot))) ∧
      runtime.Frame layout workspace workspaceValues workspaceCell depth
        (afterRead.bindLocal 12 (.signed .i32 (Int.ofNat runtime.parent.dot))) ∧
      CellEffect (CellSet.singleton runtime.recordsCell) before afterRead := by
  obtain ⟨children, afterRead, count, treeCount, read, matched, call, written, _, effect⟩ :=
    checked.read_children linked inverseType inverse sound found treeEnough materialized
      input.frame.wellFormed input.frame.artifact layoutTokens input.recordsBacking
      (Ne.symm input.frame.recordsSeparate) recordsBound fits (input.reader_arguments program.core)
  have afterFrame := input.frame.after_outputs input.recordsBacking input.offsetsBacking
    (effect.weaken CellSet.subset_union_left)
  let value := Value.signed .i32 (Int.ofNat runtime.parent.dot)
  have preserve {id : Lanius.VarId} {v : Value} (small : id < 12) (localValue : before.local? id = some v)
      (plain : v ≠ .array (signedI32Values runtime.records)) :
      (afterRead.bindLocal 12 value).local? id = some v :=
    (bindLocal_preserves_other_local (boundId := 12) (queriedId := id) effect.wellFormed
      (Ne.symm (Nat.ne_of_lt small))).trans
      (effect.preserves_local_of_distinct_value input.frame.wellFormed localValue input.recordsBacking plain)
  have backing {cell : CellId} {v : Value}
      (current : afterRead.cellEntry? cell = some { id := cell, value := some v }) :
      (afterRead.bindLocal 12 value).cellEntry? cell = some { id := cell, value := some v } :=
    ((bindLocal_effect afterRead 12 value).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry effect.wellFormed current) (by simp [CellSet.empty])).trans current
  refine ⟨children, afterRead, count, treeCount, read, matched, ?_, call, ?_,
    afterFrame.bind 12 (by decide) value, effect⟩
  · intro childId member
    exact (sound.derivationChildren_state_before found (Nat.lt_succ_self _) read member).1
  · exact ⟨bindLocal_preserves_well_formed _ _ _ effect.wellFormed, count, fits, offsetsFit,
      recordsBound, offsetsBound,
      preserve (by decide) input.wordsLocal (by intro impossible; cases impossible),
      preserve (by decide) input.nodesLocal (by intro impossible; cases impossible),
      bindLocal_finds_local _ _ _ effect.wellFormed,
      preserve (by decide) input.recordsLocal (by intro impossible; cases impossible),
      preserve (by decide) input.offsetsLocal (by intro impossible; cases impossible),
      preserve (by decide) input.capacityLocal (by intro impossible; cases impossible),
      backing written,
      backing (effect.preserves_entry input.frame.wellFormed input.offsetsBacking (Ne.symm input.buffersDistinct)),
      input.buffersDistinct⟩

/-- Close the complete source body around the proved reader and child-loop
    executions. All success guards execute here, and the reader-result local
    is restored at the actual scope boundary. The whole-call induction must
    supply `read` using `CallEntry.read` and `children` using `Entry.children`. -/
theorem TreeRuntime.CallEntry.body {runtime : TreeRuntime}
    (input : runtime.CallEntry layout workspace workspaceValues workspaceCell stateId depth before)
    (checked : CheckedVisit program) (positive : 0 < depth)
    (room : runtime.nodeBase < runtime.offsets.length)
    (read : Evaluates program.core before (.call checked.symbols.reader
      [.local 0, .local 1, .local 2, .local 3, .local 4, .local 5, .local 6, .local 10])
      (.signed .i32 (Int.ofNat runtime.parent.dot)) afterRead)
    (readEffect : CellEffect (CellSet.singleton runtime.recordsCell) before afterRead)
    (children : Executes program.core (afterRead.bindLocal 12 (.signed .i32 (Int.ofNat runtime.parent.dot)))
      (visitChildren checked.symbols) completion completed)
    (childEffect : CellEffect runtime.outputs
      (afterRead.bindLocal 12 (.signed .i32 (Int.ofNat runtime.parent.dot))) completed) :
    Executes program.core before (visitBody checked.symbols) completion (restoreLocals afterRead completed) ∧
      CellEffect runtime.outputs before (restoreLocals afterRead completed) := by
  have depthGuard : Evaluates program.core before
      (.binary .lessEqual (.local 11) (.value (.signed .i32 0))) (.boolean false) before :=
    evaluatesEagerBinary (by decide) (by decide) (local_read input.frame.depthLocal) ⟨1, rfl⟩
      (by simp [evalBinaryValue, evalSignedBinary, Nat.ne_of_gt positive])
  have capacityGuard : Evaluates program.core before
      (.binary .greaterEqual (.local 9) (.local 8)) (.boolean false) before :=
    evaluatesEagerBinary (by decide) (by decide) (local_read input.nodesLocal) (local_read input.capacityLocal)
      (by simp [evalBinaryValue, evalSignedBinary, room])
  let bound := afterRead.bindLocal 12 (.signed .i32 (Int.ofNat runtime.parent.dot))
  have countLocal : bound.local? 12 = some (.signed .i32 (Int.ofNat runtime.parent.dot)) :=
    bindLocal_finds_local _ _ _ readEffect.wellFormed
  have negativeTwo : Evaluates program.core bound (.unary .negate (.value (.signed .i32 2)))
      (.signed .i32 (-2)) bound := by
    apply evaluatesUnary (show
      Evaluates program.core bound (.value (.signed .i32 2)) (.signed .i32 2) bound from ⟨1, rfl⟩)
    simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]
  have countNotFull : Evaluates program.core bound
      (.binary .equal (.local 12) (.unary .negate (.value (.signed .i32 2)))) (.boolean false) bound :=
    evaluatesEagerBinary (by decide) (by decide) (local_read countLocal) negativeTwo
      (by simp [evalBinaryValue, scalarEqual])
  have countNotBad := nonnegative_check_false (program := program.core) countLocal (Int.natCast_nonneg _)
  refine ⟨?_, (readEffect.weaken CellSet.subset_union_left).trans
    (CellEffect.closeLocal afterRead 12 (.signed .i32 (Int.ofNat runtime.parent.dot)) readEffect.wellFormed childEffect)⟩
  apply executesSequence (middle := before)
  · exact executesIfFalse depthGuard (executesSkip _ _)
  · apply executesSequence (middle := before)
    · exact executesIfFalse capacityGuard (executesSkip _ _)
    · apply executesLetLocal (afterInitializer := afterRead) (completed := completed) read
      exact executesSequence (executesIfFalse countNotFull (executesSkip _ _))
        (executesSequence (executesIfFalse countNotBad (executesSkip _ _)) children)

end Lanius.Extraction.ParserTreeSource
