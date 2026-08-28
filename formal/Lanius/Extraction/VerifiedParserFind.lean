import Lanius.Extraction.VerifiedParserReads
import Lanius.Extraction.VerifiedParserSymbolic

namespace Lanius.Extraction.ParserFind

open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.Compiler.Parser

def stateSeedValue (seed : StateSeed) : Value :=
  .structure 1 [
    .signed .i32 (Int.ofNat seed.production),
    .signed .i32 (Int.ofNat seed.dot),
    .signed .i32 (Int.ofNat seed.origin),
    .signed .i32 (previousValue seed.previous),
    .signed .i32 (childTag seed.child),
    .signed .i32 (childPayload seed.child),
    .signed .i32 (childKind seed.child)]

def workspaceValue (values : List Int) (workspaceCell : CellId) : Value :=
  .slice parserI32Type workspaceCell [] 0 values.length

def FindStateCallerLocal (id : VarId) : Prop :=
  id ∈ verifiedParserFindStateCallerFrameIds

theorem FindStateCallerLocal_source_frame (id : VarId) :
    FindStateCallerLocal id ↔
      verifiedParserFindStateCallerBindings.ContainsCoreId id := by
  rfl

/-- Runtime invariant for one nonnegative `find_state` loop cursor.  Static
    parser facts and physical ownership are carried together so any read-only
    call can advance the runtime state without rebuilding the proof. -/
structure RuntimeInvariant
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed)
    (runtime : State) (current : Nat) (remaining : List Nat) where
  valuesLength : values.length = layout.workspaceLength
  encoded : EncodesWorkspace layout workspace (listWords values)
  positionBound : position ≤ finalPosition layout.tokenCount
  wellFormed : StateWellFormed runtime
  workspaceLocal : runtime.local? 0 = some (workspaceValue values workspaceCell)
  baseLocal : runtime.local? 1 = some
    (.signed .i32 (Int.ofNat (stateBase layout.tokenCount)))
  positionLocal : runtime.local? 2 = some (.signed .i32 (Int.ofNat position))
  seedLocal : runtime.local? 3 = some (stateSeedValue seed)
  currentLocal : runtime.local? 4 = some (.signed .i32 (Int.ofNat current))
  currentCell : CellId
  currentOwned : (Assertion.localPointsTo 4 currentCell
    (some (.signed .i32 (Int.ofNat current)))).holds runtime
  /-- Separation from the structurally derived live caller frame. -/
  callerFrameSeparate : CellSet.Disjoint
    (localBindingFrameFootprint runtime verifiedParserFindStateCallerBindings)
    (CellSet.singleton currentCell)
  currentNotBacking : currentCell ≠ workspaceCell
  backing : runtime.cellEntry? workspaceCell = some {
    id := workspaceCell
    value := some (.array (signedI32Values values))
  }
  search : SearchCursor workspace seed.key (workspace.chart position)
    current remaining

theorem RuntimeInvariant.currentSeparate
    (invariant : RuntimeInvariant layout workspace values workspaceCell
      position seed runtime current remaining)
    (id : VarId) (member : id ∈ verifiedParserFindStateCallerFrameIds) :
    runtime.cellId? id ≠ some invariant.currentCell :=
  invariant.callerFrameSeparate.localCell_ne_of_singleton
    ((FindStateCallerLocal_source_frame id).mp member)

structure EntryInvariant
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed) (runtime : State) where
  valuesLength : values.length = layout.workspaceLength
  encoded : EncodesWorkspace layout workspace (listWords values)
  positionBound : position ≤ finalPosition layout.tokenCount
  wellFormed : StateWellFormed runtime
  workspaceLocal : runtime.local? 0 = some (workspaceValue values workspaceCell)
  baseLocal : runtime.local? 1 = some
    (.signed .i32 (Int.ofNat (stateBase layout.tokenCount)))
  positionLocal : runtime.local? 2 = some (.signed .i32 (Int.ofNat position))
  seedLocal : runtime.local? 3 = some (stateSeedValue seed)
  backing : runtime.cellEntry? workspaceCell = some {
    id := workspaceCell
    value := some (.array (signedI32Values values))
  }

def EntryInvariant.after_empty_effect
    (invariant : EntryInvariant layout workspace values workspaceCell
      position seed before)
    (effect : ModifiesOnly CellSet.empty before after)
    (afterWellFormed : StateWellFormed after) :
    EntryInvariant layout workspace values workspaceCell position seed after := {
  valuesLength := invariant.valuesLength
  encoded := invariant.encoded
  positionBound := invariant.positionBound
  wellFormed := afterWellFormed
  workspaceLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.workspaceLocal
  baseLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.baseLocal
  positionLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.positionLocal
  seedLocal := effect.empty_preserves_local invariant.wellFormed
    invariant.seedLocal
  backing := effect.empty_preserves_entry invariant.wellFormed invariant.backing
}

structure ChartHeadRead
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed) (before : State)
    (beforeInvariant : EntryInvariant layout workspace values workspaceCell
      position seed before) where
  after : State
  evaluation : Evaluates verifiedParserCore before parserFindChartHeadExpr
    (.signed .i32 (chartHeadValue workspace position)) after
  effect : ModifiesOnly CellSet.empty before after
  invariant : EntryInvariant layout workspace values workspaceCell position
    seed after

noncomputable def EntryInvariant.read_chart_head
    (invariant : EntryInvariant layout workspace values workspaceCell
      position seed runtime) :
    ChartHeadRead layout workspace values workspaceCell position seed runtime
      invariant := by
  let after := parserChartWordCallState runtime (Int.ofNat position) 0
  have evaluation : Evaluates verifiedParserCore runtime parserFindChartHeadExpr
      (.signed .i32 (chartHeadValue workspace position)) after := by
    simpa [after, parserChartWordCallState] using
      parserFindChartHeadExpr_reads_encoded layout workspace values
        workspaceCell invariant.valuesLength invariant.encoded position
        invariant.positionBound runtime invariant.wellFormed
        invariant.workspaceLocal invariant.positionLocal invariant.backing
  have effect : ModifiesOnly CellSet.empty runtime after := by
    exact parserChartWordCallState_effect
  have afterWellFormed : StateWellFormed after :=
    parserChartWordCallState_well_formed invariant.wellFormed
  exact ⟨after, evaluation, effect,
    invariant.after_empty_effect effect afterWellFormed⟩

def ChartHeadRead.bind_nonempty
    (read : ChartHeadRead layout workspace values workspaceCell position seed
      before beforeInvariant)
    (chart : workspace.chart position = current :: remaining) :
    RuntimeInvariant layout workspace values workspaceCell position seed
      (read.after.bindLocal 4 (.signed .i32 (Int.ofNat current)))
      current remaining := by
  let bound := read.after.bindLocal 4 (.signed .i32 (Int.ofNat current))
  have currentOwned : (Assertion.localPointsTo 4 read.after.nextCell
      (some (.signed .i32 (Int.ofNat current)))).holds bound := by
    constructor
    · simp [bound, State.bindLocal, State.bindCell, State.cellId?]
    · simpa [bound, State.bindLocal] using
        bindCell_finds_fresh_cell read.after 4
          (some (.signed .i32 (Int.ofNat current))) read.invariant.wellFormed
  have backingOld : workspaceCell < read.after.nextCell :=
    Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      read.invariant.wellFormed read.invariant.backing
  exact {
    valuesLength := read.invariant.valuesLength
    encoded := read.invariant.encoded
    positionBound := read.invariant.positionBound
    wellFormed := bindLocal_preserves_well_formed read.after 4
      (.signed .i32 (Int.ofNat current)) read.invariant.wellFormed
    workspaceLocal := by
      simpa [bound] using (bindLocal_preserves_other_local
        read.invariant.wellFormed (by decide : (4 : VarId) ≠ 0)).trans
          read.invariant.workspaceLocal
    baseLocal := by
      simpa [bound] using (bindLocal_preserves_other_local
        read.invariant.wellFormed (by decide : (4 : VarId) ≠ 1)).trans
          read.invariant.baseLocal
    positionLocal := by
      simpa [bound] using (bindLocal_preserves_other_local
        read.invariant.wellFormed (by decide : (4 : VarId) ≠ 2)).trans
          read.invariant.positionLocal
    seedLocal := by
      simpa [bound] using (bindLocal_preserves_other_local
        read.invariant.wellFormed (by decide : (4 : VarId) ≠ 3)).trans
          read.invariant.seedLocal
    currentLocal := Assertion.localPointsTo_local 4 read.after.nextCell
      (.signed .i32 (Int.ofNat current)) bound currentOwned
    currentCell := read.after.nextCell
    currentOwned := currentOwned
    callerFrameSeparate := localCellFootprint_disjoint_singleton (by
      intro id frameMember equal
      have frameMemberIds : FindStateCallerLocal id :=
        (FindStateCallerLocal_source_frame id).mpr frameMember
      have different : (4 : VarId) ≠ id := by
        unfold FindStateCallerLocal at frameMemberIds
        rw [verifiedParserFindState_caller_frame_ids] at frameMemberIds
        simp only [List.mem_cons, List.not_mem_nil,
          or_false] at frameMemberIds
        rcases frameMemberIds with equal | equal | equal | equal <;>
          subst id <;> decide
      have oldFound : read.after.cellId? id = some read.after.nextCell := by
        have cellIdPreserved : bound.cellId? id = read.after.cellId? id := by
          simp [bound, State.bindLocal, State.bindCell, State.cellId?, different]
        rw [cellIdPreserved] at equal
        exact equal
      have impossible :=
        Lanius.Separation.StateWellFormed.cell_lt_next_of_local_binding
          id read.after.nextCell read.invariant.wellFormed oldFound
      exact (Nat.lt_irrefl read.after.nextCell) impossible)
    currentNotBacking := Nat.ne_of_gt backingOld
    backing := by
      simpa [bound, State.bindLocal] using
        (bindCell_preserves_old_cell read.after 4
          (some (.signed .i32 (Int.ofNat current))) workspaceCell
          backingOld).trans read.invariant.backing
    search := by
      rw [chart]
      exact SearchCursor.atHead workspace seed.key current remaining
  }

theorem RuntimeInvariant.state_at_cursor
    (invariant : RuntimeInvariant layout workspace values workspaceCell
      position seed runtime current remaining) :
    ∃ state,
      workspace.state? current = some state ∧
      state.position = position :=
  invariant.encoded.state_at_chart_cursor invariant.search.cursor

def RuntimeInvariant.after_empty_effect
    (invariant : RuntimeInvariant layout workspace values workspaceCell
      position seed before current remaining)
    (effect : ModifiesOnly CellSet.empty before after)
    (afterWellFormed : StateWellFormed after) :
    RuntimeInvariant layout workspace values workspaceCell position seed
      after current remaining := by
  exact {
    valuesLength := invariant.valuesLength
    encoded := invariant.encoded
    positionBound := invariant.positionBound
    wellFormed := afterWellFormed
    workspaceLocal := effect.empty_preserves_local invariant.wellFormed
      invariant.workspaceLocal
    baseLocal := effect.empty_preserves_local invariant.wellFormed
      invariant.baseLocal
    positionLocal := effect.empty_preserves_local invariant.wellFormed
      invariant.positionLocal
    seedLocal := effect.empty_preserves_local invariant.wellFormed
      invariant.seedLocal
    currentLocal := effect.empty_preserves_local invariant.wellFormed
      invariant.currentLocal
    currentCell := invariant.currentCell
    currentOwned := effect.empty_preserves_assertion invariant.wellFormed
      (Assertion.localPointsTo 4 invariant.currentCell
        (some (.signed .i32 (Int.ofNat current)))) invariant.currentOwned
    callerFrameSeparate := by
      rw [effect.localBindingFrameFootprint_eq
        verifiedParserFindStateCallerBindings]
      exact invariant.callerFrameSeparate
    currentNotBacking := invariant.currentNotBacking
    backing := effect.empty_preserves_entry invariant.wellFormed invariant.backing
    search := invariant.search
  }

def RuntimeInvariant.after_current_assignment
    (invariant : RuntimeInvariant layout workspace values workspaceCell
      position seed before current remaining)
    (newCurrent : Nat) (newRemaining : List Nat)
    (after : State)
    (effect : ModifiesOnly (CellSet.singleton invariant.currentCell)
      before after)
    (afterWellFormed : StateWellFormed after)
    (afterOwned : (Assertion.localPointsTo 4 invariant.currentCell
      (some (.signed .i32 (Int.ofNat newCurrent)))).holds after)
    (search : SearchCursor workspace seed.key (workspace.chart position)
      newCurrent newRemaining) :
    RuntimeInvariant layout workspace values workspaceCell position seed
      after newCurrent newRemaining := by
  have preserveFramedLocal (id : VarId)
      (frameMember : id ∈ verifiedParserFindStateCallerFrameIds)
      (value : Value)
      (found : before.local? id = some value) :
      after.local? id = some value :=
    effect.preserves_local_of_disjoint invariant.wellFormed
      invariant.callerFrameSeparate
        ((FindStateCallerLocal_source_frame id).mp frameMember) found
  have workspaceOld : workspaceCell < before.nextCell :=
    Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      invariant.wellFormed invariant.backing
  exact {
    valuesLength := invariant.valuesLength
    encoded := invariant.encoded
    positionBound := invariant.positionBound
    wellFormed := afterWellFormed
    workspaceLocal := preserveFramedLocal 0
      (by simp [verifiedParserFindState_caller_frame_ids])
      (workspaceValue values workspaceCell) invariant.workspaceLocal
    baseLocal := preserveFramedLocal 1
      (by simp [verifiedParserFindState_caller_frame_ids])
      (.signed .i32 (Int.ofNat (stateBase layout.tokenCount)))
      invariant.baseLocal
    positionLocal := preserveFramedLocal 2
      (by simp [verifiedParserFindState_caller_frame_ids])
      (.signed .i32 (Int.ofNat position)) invariant.positionLocal
    seedLocal := preserveFramedLocal 3
      (by simp [verifiedParserFindState_caller_frame_ids])
      (stateSeedValue seed)
      invariant.seedLocal
    currentLocal := Assertion.localPointsTo_local 4 invariant.currentCell
      (.signed .i32 (Int.ofNat newCurrent)) after afterOwned
    currentCell := invariant.currentCell
    currentOwned := afterOwned
    callerFrameSeparate := by
      rw [effect.localBindingFrameFootprint_eq
        verifiedParserFindStateCallerBindings]
      exact invariant.callerFrameSeparate
    currentNotBacking := invariant.currentNotBacking
    backing := (effect.oldCells workspaceCell workspaceOld (by
      intro written
      change workspaceCell = invariant.currentCell at written
      exact invariant.currentNotBacking written.symm)).trans invariant.backing
    search := search
  }

/-- An extracted expression evaluation together with the same parser-search
    invariant transported to its final runtime state.  This lives in `Type`
    because the invariant contains the concrete chart cursor used to drive the
    termination proof. -/
structure PreservedEvaluation
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed)
    (before : State) (current : Nat) (remaining : List Nat)
    (expression : Expr) (value : Value) where
  after : State
  evaluation : Evaluates verifiedParserCore before expression value after
  effect : ModifiesOnly CellSet.empty before after
  invariant : RuntimeInvariant layout workspace values workspaceCell position
    seed after current remaining

theorem PreservedEvaluation.currentCell_eq
    (result : PreservedEvaluation layout workspace values workspaceCell
      position seed before current remaining expression value)
    (beforeInvariant : RuntimeInvariant layout workspace values workspaceCell
      position seed before current remaining) :
    result.invariant.currentCell = beforeInvariant.currentCell := by
  have afterBinding := result.invariant.currentOwned.1
  have beforeBinding := beforeInvariant.currentOwned.1
  unfold State.cellId? at afterBinding beforeBinding
  rw [result.effect.locals] at afterBinding
  rw [beforeBinding] at afterBinding
  exact (Option.some.inj afterBinding).symm

structure CursorAdvance
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed)
    (before : State) (current : Nat) (remaining : List Nat)
    (next : Nat) (tail : List Nat)
    (beforeInvariant : RuntimeInvariant layout workspace values workspaceCell
      position seed before current remaining) where
  after : State
  execution : Executes verifiedParserCore before parserFindUpdateCurrent
    .next after
  effect : ModifiesOnly (CellSet.singleton beforeInvariant.currentCell)
    before after
  nextInvariant : RuntimeInvariant layout workspace values workspaceCell position
    seed after next tail

structure CursorExhaustion
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed)
    (before : State) (current : Nat)
    (beforeInvariant : RuntimeInvariant layout workspace values workspaceCell
      position seed before current []) where
  after : State
  execution : Executes verifiedParserCore before parserFindUpdateCurrent
    .next after
  effect : ModifiesOnly (CellSet.singleton beforeInvariant.currentCell)
    before after
  wellFormed : StateWellFormed after
  currentOwned : (Assertion.localPointsTo 4 beforeInvariant.currentCell
    (some (.signed .i32 (-1)))).holds after

theorem evaluatesParserFindLoopCondition_nonnegative
    (currentLocal : runtime.local? 4 =
      some (.signed .i32 (Int.ofNat current))) :
    Evaluates verifiedParserCore runtime
      (.binary .greaterEqual (.local 4) (.value (.signed .i32 0)))
      (.boolean true) runtime := by
  have leftResult : Evaluates verifiedParserCore runtime (.local 4)
      (.signed .i32 (Int.ofNat current)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 4
      (.signed .i32 (Int.ofNat current)) currentLocal⟩
  have rightResult : Evaluates verifiedParserCore runtime
      (.value (.signed .i32 0)) (.signed .i32 0) runtime := ⟨1, rfl⟩
  apply evaluatesEagerBinary (by decide) (by decide) leftResult rightResult
  simp [evalBinaryValue, evalSignedBinary]

theorem evaluatesParserFindLoopCondition_missing
    (currentLocal : runtime.local? 4 = some (.signed .i32 (-1))) :
    Evaluates verifiedParserCore runtime
      (.binary .greaterEqual (.local 4) (.value (.signed .i32 0)))
      (.boolean false) runtime := by
  have leftResult : Evaluates verifiedParserCore runtime (.local 4)
      (.signed .i32 (-1)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 4
      (.signed .i32 (-1)) currentLocal⟩
  have rightResult : Evaluates verifiedParserCore runtime
      (.value (.signed .i32 0)) (.signed .i32 0) runtime := ⟨1, rfl⟩
  apply evaluatesEagerBinary (by decide) (by decide) leftResult rightResult
  simp [evalBinaryValue, evalSignedBinary]

def parserFindLoopCompletion : Option Nat → Completion
  | some stateId => .returned (some (.signed .i32 (Int.ofNat stateId)))
  | none => .next

theorem executesParserFindReturnMissing (runtime : State) :
    Executes verifiedParserCore runtime parserFindReturnMissing
      (.returned (some (.signed .i32 (-1)))) runtime := by
  have one : Evaluates verifiedParserCore runtime
      (.value (.signed .i32 1)) (.signed .i32 1) runtime := ⟨1, rfl⟩
  have wrapped : wrapSigned verifiedParserCore.target .i32 (-1) = -1 := by
    generalize verifiedParserCore.target = target
    rcases target with ⟨width⟩
    cases width <;> native_decide
  have negateResult : evalUnaryValue verifiedParserCore.target .negate
      (.signed .i32 1) = .ok (.signed .i32 (-1)) := by
    simp [evalUnaryValue, wrapped]
  have negativeOne := evaluatesUnary one negateResult
  have returned := executesReturnValue negativeOne
  simpa [parserFindReturnMissing] using
    (executesSequenceReturned (second := Stmt.skip) returned)

structure FindLoopExecution
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed)
    (before : State) (current : Nat) (remaining : List Nat)
    (beforeInvariant : RuntimeInvariant layout workspace values workspaceCell
      position seed before current remaining) where
  after : State
  execution : Executes verifiedParserCore before parserFindLoop
    (parserFindLoopCompletion
      (findStateIn? workspace seed.key (current :: remaining))) after
  effect : ModifiesOnly (CellSet.singleton beforeInvariant.currentCell)
    before after
  wellFormed : StateWellFormed after
  missingCurrent :
    findStateIn? workspace seed.key (current :: remaining) = none →
      after.local? 4 = some (.signed .i32 (-1))

structure FindStateBodyExecution
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed) (before : State)
    (beforeInvariant : EntryInvariant layout workspace values workspaceCell
      position seed before) where
  after : State
  execution : Executes verifiedParserCore before parserFindStateBody
    (.returned (some (.signed .i32
      (encodeStateId (workspace.findStateId? position seed.key))))) after
  effect : ModifiesOnly CellSet.empty before after
  wellFormed : StateWellFormed after
  backing : after.cellEntry? workspaceCell = some {
    id := workspaceCell
    value := some (.array (signedI32Values values))
  }

noncomputable def RuntimeInvariant.read_state_field
    (invariant : RuntimeInvariant layout workspace values workspaceCell
      position seed runtime current remaining)
    (state : EarleyState)
    (found : workspace.state? current = some state)
    (field constantId : Nat)
    (fieldBound : field < stateWords)
    (constantFound : verifiedParserCore.constant? constantId = some {
      id := constantId
      type := parserI32Type
      value := .signed .i32 (Int.ofNat field)
    }) :
    PreservedEvaluation layout workspace values workspaceCell position seed
      runtime current remaining (parserFindStateValueExpr constantId)
      (.signed .i32 (stateFieldValue workspace current state field)) := by
  let value := workspaceValue values workspaceCell
  let after := parserStateValueCallState runtime value
    (Int.ofNat (stateBase layout.tokenCount)) (Int.ofNat current)
    (Int.ofNat field)
  have workspaceArgument : Evaluates verifiedParserCore runtime (.local 0)
      value runtime := by
    refine ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 0 value ?_⟩
    simpa [value] using invariant.workspaceLocal
  have baseArgument : Evaluates verifiedParserCore runtime (.local 1)
      (.signed .i32 (Int.ofNat (stateBase layout.tokenCount))) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 1
      (.signed .i32 (Int.ofNat (stateBase layout.tokenCount)))
      invariant.baseLocal⟩
  have currentArgument : Evaluates verifiedParserCore runtime (.local 4)
      (.signed .i32 (Int.ofNat current)) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 4
      (.signed .i32 (Int.ofNat current)) invariant.currentLocal⟩
  have fieldArgument : Evaluates verifiedParserCore runtime
      (.constant constantId) (.signed .i32 (Int.ofNat field)) runtime := by
    refine ⟨2, ?_⟩
    simp [evalExpr, constantFound]
  have arguments : ArgumentsEvaluateTo verifiedParserCore runtime
      [.local 0, .local 1, .local 4, .constant constantId]
      [value,
        .signed .i32 (Int.ofNat (stateBase layout.tokenCount)),
        .signed .i32 (Int.ofNat current),
        .signed .i32 (Int.ofNat field)] runtime :=
    ArgumentsEvaluateTo.cons workspaceArgument
      (ArgumentsEvaluateTo.cons baseArgument
        (ArgumentsEvaluateTo.cons currentArgument
          (ArgumentsEvaluateTo.singleton fieldArgument)))
  have execution := extractedParserStateValueCall_reads_encoded layout
    workspace values workspaceCell invariant.valuesLength invariant.encoded
    state current field found fieldBound runtime runtime
    [.local 0, .local 1, .local 4, .constant constantId]
    invariant.wellFormed arguments invariant.backing
  have executionAtAfter : Evaluates verifiedParserCore runtime
      (parserFindStateValueExpr constantId)
      (.signed .i32 (stateFieldValue workspace current state field)) after := by
    simpa [parserFindStateValueExpr, after, value, workspaceValue,
      parserStateValueCallState] using execution
  have afterWellFormed : StateWellFormed after := by
    exact parserStateValueCallState_well_formed invariant.wellFormed
  have effect : ModifiesOnly CellSet.empty runtime after := by
    exact parserStateValueCallState_effect
  exact ⟨after, executionAtAfter, effect,
    invariant.after_empty_effect effect afterWellFormed⟩

theorem stateSeedValue_key_field
    (seed : StateSeed) (field : Nat)
    (fieldBound : field < 3) :
    [(Value.signed .i32 (Int.ofNat seed.production)),
      (Value.signed .i32 (Int.ofNat seed.dot)),
      (Value.signed .i32 (Int.ofNat seed.origin)),
      (Value.signed .i32 (previousValue seed.previous)),
      (Value.signed .i32 (childTag seed.child)),
      (Value.signed .i32 (childPayload seed.child)),
      (Value.signed .i32 (childKind seed.child))][field]? =
        some (Value.signed .i32 (stateKeyFieldValue seed.key field)) := by
  have cases : field = 0 ∨ field = 1 ∨ field = 2 := by omega
  rcases cases with equal | equal | equal <;> subst field <;> rfl

noncomputable def RuntimeInvariant.read_seed_key_field
    (invariant : RuntimeInvariant layout workspace values workspaceCell
      position seed runtime current remaining)
    (field : Nat) (fieldBound : field < 3) :
    PreservedEvaluation layout workspace values workspaceCell position seed
      runtime current remaining (.field (.local 3) field)
      (.signed .i32 (stateKeyFieldValue seed.key field)) := by
  have localResult : Evaluates verifiedParserCore runtime (.local 3)
      (stateSeedValue seed) runtime :=
    ⟨1, evalLocal_of_local 1 verifiedParserCore runtime 3
      (stateSeedValue seed) invariant.seedLocal⟩
  have fieldResult : Evaluates verifiedParserCore runtime
      (.field (.local 3) field)
      (.signed .i32 (stateKeyFieldValue seed.key field)) runtime := by
    apply evaluatesStructureField localResult
    exact stateSeedValue_key_field seed field fieldBound
  exact ⟨runtime, fieldResult, ModifiesOnly.refl runtime, invariant⟩

noncomputable def RuntimeInvariant.read_field_match
    (invariant : RuntimeInvariant layout workspace values workspaceCell
      position seed runtime current remaining)
    (state : EarleyState)
    (found : workspace.state? current = some state)
    (field constantId : Nat)
    (fieldBound : field < 3)
    (constantFound : verifiedParserCore.constant? constantId = some {
      id := constantId
      type := parserI32Type
      value := .signed .i32 (Int.ofNat field)
    }) :
    PreservedEvaluation layout workspace values workspaceCell position seed
      runtime current remaining (parserFindFieldMatch constantId field)
      (.boolean
        (stateKeyFieldValue state.key field ==
          stateKeyFieldValue seed.key field)) := by
  let stateRead := invariant.read_state_field state found field constantId
    (Nat.lt_trans fieldBound (by decide : 3 < stateWords)) constantFound
  have stateEvaluation : Evaluates verifiedParserCore runtime
      (parserFindStateValueExpr constantId)
      (.signed .i32 (stateKeyFieldValue state.key field)) stateRead.after := by
    rw [← stateFieldValue_eq_keyFieldValue
      (workspace := workspace) (stateId := current) (state := state)
      fieldBound]
    exact stateRead.evaluation
  let seedRead := stateRead.invariant.read_seed_key_field field fieldBound
  have operationResult : evalBinaryValue verifiedParserCore.target .equal
      (.signed .i32 (stateKeyFieldValue state.key field))
      (.signed .i32 (stateKeyFieldValue seed.key field)) =
      .ok (.boolean
        (stateKeyFieldValue state.key field ==
          stateKeyFieldValue seed.key field)) := by
    simp [evalBinaryValue, scalarEqual]
  have comparison := evaluatesEagerBinary
    (program := verifiedParserCore) (op := BinaryOp.equal)
    (by decide) (by decide) stateEvaluation seedRead.evaluation
    operationResult
  exact ⟨seedRead.after, comparison,
    stateRead.effect.trans_same seedRead.effect, seedRead.invariant⟩

theorem stateKey_eq_of_fields (left right : StateKey)
    (production : left.production = right.production)
    (dot : left.dot = right.dot)
    (origin : left.origin = right.origin) : left = right := by
  cases left
  cases right
  simp_all

noncomputable def RuntimeInvariant.read_key_match_of_equal
    (invariant : RuntimeInvariant layout workspace values workspaceCell
      position seed runtime current remaining)
    (state : EarleyState)
    (found : workspace.state? current = some state)
    (same : state.key = seed.key) :
    PreservedEvaluation layout workspace values workspaceCell position seed
      runtime current remaining parserFindKeyMatchExpr (.boolean true) := by
  let productionRead := invariant.read_field_match state found 0 28
    (by decide) verifiedParser_find_constants.2.1
  have productionTrue : Evaluates verifiedParserCore runtime
      (parserFindFieldMatch 28 0) (.boolean true) productionRead.after := by
    simpa [same] using productionRead.evaluation
  let dotRead := productionRead.invariant.read_field_match state found 1 29
    (by decide) verifiedParser_find_constants.2.2.1
  have dotTrue : Evaluates verifiedParserCore productionRead.after
      (parserFindFieldMatch 29 1) (.boolean true) dotRead.after := by
    simpa [same] using dotRead.evaluation
  have firstTwo : Evaluates verifiedParserCore runtime
      (.binary .logicalAnd (parserFindFieldMatch 28 0)
        (parserFindFieldMatch 29 1)) (.boolean true) dotRead.after :=
    evaluatesLogicalAndTrue productionTrue dotTrue
  let originRead := dotRead.invariant.read_field_match state found 2 30
    (by decide) verifiedParser_find_constants.2.2.2.1
  have originTrue : Evaluates verifiedParserCore dotRead.after
      (parserFindFieldMatch 30 2) (.boolean true) originRead.after := by
    simpa [same] using originRead.evaluation
  have complete := evaluatesLogicalAndTrue firstTwo originTrue
  exact ⟨originRead.after, by
    simpa [parserFindKeyMatchExpr] using complete,
    (productionRead.effect.trans_same dotRead.effect).trans_same
      originRead.effect,
    originRead.invariant⟩

noncomputable def RuntimeInvariant.read_key_match_of_not_equal
    (invariant : RuntimeInvariant layout workspace values workspaceCell
      position seed runtime current remaining)
    (state : EarleyState)
    (found : workspace.state? current = some state)
    (different : state.key ≠ seed.key) :
    PreservedEvaluation layout workspace values workspaceCell position seed
      runtime current remaining parserFindKeyMatchExpr (.boolean false) := by
  by_cases productionSame : state.production = seed.production
  · by_cases dotSame : state.dot = seed.dot
    · have originDifferent : state.origin ≠ seed.origin := by
        intro originSame
        exact different (stateKey_eq_of_fields state.key seed.key
          productionSame dotSame originSame)
      obtain ⟨productionAfter, productionEvaluation, productionEffect,
          productionInvariant⟩ :=
        invariant.read_field_match state found 0 28
          (by decide) verifiedParser_find_constants.2.1
      have productionTrue : Evaluates verifiedParserCore runtime
          (parserFindFieldMatch 28 0) (.boolean true)
          productionAfter := by
        simpa [stateKeyFieldValue, EarleyState.key, StateSeed.key,
          productionSame] using productionEvaluation
      obtain ⟨dotAfter, dotEvaluation, dotEffect, dotInvariant⟩ :=
        productionInvariant.read_field_match state found 1 29
          (by decide) verifiedParser_find_constants.2.2.1
      have dotTrue : Evaluates verifiedParserCore productionAfter
          (parserFindFieldMatch 29 1) (.boolean true) dotAfter := by
        simpa [stateKeyFieldValue, EarleyState.key, StateSeed.key, dotSame]
          using dotEvaluation
      have firstTwo : Evaluates verifiedParserCore runtime
          (.binary .logicalAnd (parserFindFieldMatch 28 0)
            (parserFindFieldMatch 29 1)) (.boolean true) dotAfter :=
        evaluatesLogicalAndTrue productionTrue dotTrue
      obtain ⟨originAfter, originEvaluation, originEffect,
          originInvariant⟩ :=
        dotInvariant.read_field_match state found 2 30
          (by decide) verifiedParser_find_constants.2.2.2.1
      have originComparison :
          (stateKeyFieldValue state.key 2 ==
            stateKeyFieldValue seed.key 2) = false := by
        simp [stateKeyFieldValue, EarleyState.key, StateSeed.key,
          Int.ofNat_inj, originDifferent]
      have originFalse : Evaluates verifiedParserCore dotAfter
          (parserFindFieldMatch 30 2) (.boolean false) originAfter := by
        simpa only [originComparison] using originEvaluation
      have complete := evaluatesLogicalAndTrue firstTwo originFalse
      exact ⟨originAfter, by
        simpa [parserFindKeyMatchExpr] using complete,
        (productionEffect.trans_same dotEffect).trans_same originEffect,
        originInvariant⟩
    · obtain ⟨productionAfter, productionEvaluation, productionEffect,
          productionInvariant⟩ := invariant.read_field_match state found 0 28
          (by decide) verifiedParser_find_constants.2.1
      have productionTrue : Evaluates verifiedParserCore runtime
          (parserFindFieldMatch 28 0) (.boolean true)
          productionAfter := by
        simpa [stateKeyFieldValue, EarleyState.key, StateSeed.key,
          productionSame] using productionEvaluation
      obtain ⟨dotAfter, dotEvaluation, dotEffect, dotInvariant⟩ :=
        productionInvariant.read_field_match state found 1 29
          (by decide) verifiedParser_find_constants.2.2.1
      have dotComparison :
          (stateKeyFieldValue state.key 1 ==
            stateKeyFieldValue seed.key 1) = false := by
        simp [stateKeyFieldValue, EarleyState.key, StateSeed.key,
          Int.ofNat_inj, dotSame]
      have dotFalse : Evaluates verifiedParserCore productionAfter
          (parserFindFieldMatch 29 1) (.boolean false) dotAfter := by
        simpa only [dotComparison] using dotEvaluation
      have firstTwo : Evaluates verifiedParserCore runtime
          (.binary .logicalAnd (parserFindFieldMatch 28 0)
            (parserFindFieldMatch 29 1)) (.boolean false) dotAfter :=
        evaluatesLogicalAndTrue productionTrue dotFalse
      have complete : Evaluates verifiedParserCore runtime
          parserFindKeyMatchExpr (.boolean false) dotAfter := by
        simpa [parserFindKeyMatchExpr] using
          (evaluatesLogicalAndFalse
            (right := parserFindFieldMatch 30 2) firstTwo)
      exact ⟨dotAfter, complete, productionEffect.trans_same dotEffect,
        dotInvariant⟩
  · obtain ⟨productionAfter, productionEvaluation, productionEffect,
        productionInvariant⟩ := invariant.read_field_match state found 0 28
        (by decide) verifiedParser_find_constants.2.1
    have productionComparison :
        (stateKeyFieldValue state.key 0 ==
          stateKeyFieldValue seed.key 0) = false := by
      simp [stateKeyFieldValue, EarleyState.key, StateSeed.key,
        Int.ofNat_inj, productionSame]
    have productionFalse : Evaluates verifiedParserCore runtime
        (parserFindFieldMatch 28 0) (.boolean false)
        productionAfter := by
      simpa only [productionComparison] using productionEvaluation
    have firstTwo : Evaluates verifiedParserCore runtime
        (.binary .logicalAnd (parserFindFieldMatch 28 0)
          (parserFindFieldMatch 29 1)) (.boolean false)
        productionAfter :=
      evaluatesLogicalAndFalse productionFalse
    have complete : Evaluates verifiedParserCore runtime
        parserFindKeyMatchExpr (.boolean false) productionAfter := by
      simpa [parserFindKeyMatchExpr] using
        (evaluatesLogicalAndFalse
          (right := parserFindFieldMatch 30 2) firstTwo)
    exact ⟨productionAfter, complete, productionEffect,
      productionInvariant⟩

noncomputable def RuntimeInvariant.advance_to_next
    (invariant : RuntimeInvariant layout workspace values workspaceCell
      position seed runtime current (next :: tail))
    (state : EarleyState)
    (found : workspace.state? current = some state)
    (statePosition : state.position = position)
    (different : state.key ≠ seed.key) :
    CursorAdvance layout workspace values workspaceCell position seed runtime
      current (next :: tail) next tail invariant := by
  obtain ⟨afterRead, readEvaluation, readEffect, readInvariant⟩ :=
    invariant.read_state_field state found 4 32 (by decide)
      verifiedParser_find_constants.2.2.2.2
  have nextValue : stateFieldValue workspace current state 4 =
      Int.ofNat next := by
    simp only [stateFieldValue, stateNextValue]
    rw [statePosition]
    rw [invariant.search.cursor.nextAfter]
    rfl
  have rightEvaluation : Evaluates verifiedParserCore runtime
      (parserFindStateValueExpr 32) (.signed .i32 (Int.ofNat next))
      afterRead := by
    simpa only [nextValue] using readEvaluation
  have assignmentResult := evaluatesSetOwnedLocalFromEmpty
    (program := verifiedParserCore) 4 invariant.currentCell
    invariant.wellFormed invariant.currentOwned rightEvaluation
    readInvariant.wellFormed readEffect
  let after := Classical.choose assignmentResult
  have assignmentFacts := Classical.choose_spec assignmentResult
  have assignmentEvaluation := assignmentFacts.1
  have afterWellFormed := assignmentFacts.2.1
  have afterOwned := assignmentFacts.2.2.1
  have assignmentEffect := assignmentFacts.2.2.2
  have updateExecution : Executes verifiedParserCore runtime
      parserFindUpdateCurrent .next after := by
    have expressionExecution := executesExpression assignmentEvaluation
    have sequenceExecution := executesSequence expressionExecution
      (executesSkip verifiedParserCore after)
    simpa [parserFindUpdateCurrent] using sequenceExecution
  have currentDifferent : ∀ candidate,
      workspace.state? current = some candidate → candidate.key ≠ seed.key := by
    intro candidate candidateFound
    rw [found] at candidateFound
    injection candidateFound with equal
    subst candidate
    exact different
  let nextSearch := invariant.search.next
    (invariant.encoded.wellFormed.chartIdsUnique position) currentDifferent
  let nextInvariant := invariant.after_current_assignment next tail after
    assignmentEffect afterWellFormed afterOwned nextSearch
  exact {
    after := after
    execution := updateExecution
    effect := assignmentEffect
    nextInvariant := nextInvariant
  }

noncomputable def RuntimeInvariant.advance_to_missing
    (invariant : RuntimeInvariant layout workspace values workspaceCell
      position seed runtime current [])
    (state : EarleyState)
    (found : workspace.state? current = some state)
    (statePosition : state.position = position) :
    CursorExhaustion layout workspace values workspaceCell position seed runtime
      current invariant := by
  obtain ⟨afterRead, readEvaluation, readEffect, readInvariant⟩ :=
    invariant.read_state_field state found 4 32 (by decide)
      verifiedParser_find_constants.2.2.2.2
  have missingValue : stateFieldValue workspace current state 4 = -1 := by
    simp only [stateFieldValue, stateNextValue]
    rw [statePosition]
    rw [invariant.search.cursor.nextAfter]
    rfl
  have rightEvaluation : Evaluates verifiedParserCore runtime
      (parserFindStateValueExpr 32) (.signed .i32 (-1)) afterRead := by
    simpa only [missingValue] using readEvaluation
  have assignmentResult := evaluatesSetOwnedLocalFromEmpty
    (program := verifiedParserCore) 4 invariant.currentCell
    invariant.wellFormed invariant.currentOwned rightEvaluation
    readInvariant.wellFormed readEffect
  let after := Classical.choose assignmentResult
  have assignmentFacts := Classical.choose_spec assignmentResult
  have assignmentEvaluation := assignmentFacts.1
  have afterWellFormed := assignmentFacts.2.1
  have afterOwned := assignmentFacts.2.2.1
  have assignmentEffect := assignmentFacts.2.2.2
  have updateExecution : Executes verifiedParserCore runtime
      parserFindUpdateCurrent .next after := by
    have expressionExecution := executesExpression assignmentEvaluation
    have sequenceExecution := executesSequence expressionExecution
      (executesSkip verifiedParserCore after)
    simpa [parserFindUpdateCurrent] using sequenceExecution
  exact {
    after := after
    execution := updateExecution
    effect := assignmentEffect
    wellFormed := afterWellFormed
    currentOwned := afterOwned
  }

noncomputable def RuntimeInvariant.execute_find_loop
    (invariant : RuntimeInvariant layout workspace values workspaceCell
      position seed runtime current remaining) :
    FindLoopExecution layout workspace values workspaceCell position seed
      runtime current remaining invariant := by
  have cursorState := invariant.state_at_cursor
  let state := Classical.choose cursorState
  have stateFacts := Classical.choose_spec cursorState
  have found : workspace.state? current = some state := stateFacts.1
  have statePosition : state.position = position := stateFacts.2
  have conditionTrue := evaluatesParserFindLoopCondition_nonnegative
    invariant.currentLocal
  by_cases same : state.key = seed.key
  · let keyRead := invariant.read_key_match_of_equal state found same
    have currentResult : Evaluates verifiedParserCore keyRead.after (.local 4)
        (.signed .i32 (Int.ofNat current)) keyRead.after :=
      ⟨1, evalLocal_of_local 1 verifiedParserCore keyRead.after 4
        (.signed .i32 (Int.ofNat current)) keyRead.invariant.currentLocal⟩
    have returnExecution : Executes verifiedParserCore keyRead.after
        parserFindReturnCurrent
        (.returned (some (.signed .i32 (Int.ofNat current))))
        keyRead.after := by
      have returned := executesReturnValue currentResult
      simpa [parserFindReturnCurrent] using
        (executesSequenceReturned (second := Stmt.skip) returned)
    have branchExecution : Executes verifiedParserCore runtime
        parserFindLoopBody
        (.returned (some (.signed .i32 (Int.ofNat current))))
        keyRead.after := by
      have selected := executesIfTrue (elseBranch := .skip)
        keyRead.evaluation returnExecution
      have propagated := executesSequenceReturned
        (second := parserFindUpdateCurrent) selected
      simpa [parserFindLoopBody] using propagated
    have loopExecution := executesWhileReturned conditionTrue branchExecution
    have expected : findStateIn? workspace seed.key (current :: remaining) =
        some current := by
      simp [findStateIn?, found, same]
    exact {
      after := keyRead.after
      execution := by
        rw [expected]
        simpa [parserFindLoop, parserFindLoopCompletion] using loopExecution
      effect := keyRead.effect.weaken CellSet.empty_subset
      wellFormed := keyRead.invariant.wellFormed
      missingCurrent := by
        intro missing
        rw [expected] at missing
        contradiction
    }
  · let keyRead := invariant.read_key_match_of_not_equal state found same
    have skipped : Executes verifiedParserCore keyRead.after Stmt.skip .next
        keyRead.after := executesSkip verifiedParserCore keyRead.after
    have selected : Executes verifiedParserCore runtime
        (.ifThenElse parserFindKeyMatchExpr parserFindReturnCurrent .skip)
        .next keyRead.after :=
      executesIfFalse keyRead.evaluation skipped
    cases remaining with
    | nil =>
        let exhausted := keyRead.invariant.advance_to_missing state found
          statePosition
        have bodyExecution : Executes verifiedParserCore runtime
            parserFindLoopBody .next exhausted.after := by
          simpa [parserFindLoopBody] using
            (executesSequence selected exhausted.execution)
        have missingLocal := Assertion.localPointsTo_local 4
          keyRead.invariant.currentCell (.signed .i32 (-1)) exhausted.after
          exhausted.currentOwned
        have conditionFalse :=
          evaluatesParserFindLoopCondition_missing missingLocal
        have restExecution := executesWhileFalse
          (body := parserFindLoopBody) conditionFalse
        have loopExecution := executesWhileTrue conditionTrue bodyExecution
          restExecution
        have expected :
            findStateIn? workspace seed.key [current] = none := by
          simp [findStateIn?, found, same]
        have completeEffect :=
          (keyRead.effect.weaken CellSet.empty_subset).trans_same
            exhausted.effect
        have keyCell := keyRead.currentCell_eq invariant
        rw [keyCell] at completeEffect
        exact {
          after := exhausted.after
          execution := by
            rw [expected]
            simpa [parserFindLoop, parserFindLoopCompletion] using loopExecution
          effect := completeEffect
          wellFormed := exhausted.wellFormed
          missingCurrent := by
            intro _
            exact missingLocal
        }
    | cons next tail =>
        let advanced := keyRead.invariant.advance_to_next state found
          statePosition same
        let rest := advanced.nextInvariant.execute_find_loop
        have bodyExecution : Executes verifiedParserCore runtime
            parserFindLoopBody .next advanced.after := by
          simpa [parserFindLoopBody] using
            (executesSequence selected advanced.execution)
        have loopExecution := executesWhileTrueThen conditionTrue bodyExecution
          rest.execution
        have expected :
            findStateIn? workspace seed.key (current :: next :: tail) =
              findStateIn? workspace seed.key (next :: tail) := by
          simp [findStateIn?, found, same]
        have prefixEffect :=
          (keyRead.effect.weaken CellSet.empty_subset).trans_same
            advanced.effect
        have completeEffect := prefixEffect.trans_same rest.effect
        have keyCell := keyRead.currentCell_eq invariant
        rw [keyCell] at completeEffect
        exact {
          after := rest.after
          execution := by
            rw [expected]
            exact loopExecution
          effect := completeEffect
          wellFormed := rest.wellFormed
          missingCurrent := by
            intro missing
            apply rest.missingCurrent
            rw [← expected]
            exact missing
        }
termination_by remaining.length
decreasing_by simp_all

noncomputable def EntryInvariant.execute_find_body
    (invariant : EntryInvariant layout workspace values workspaceCell
      position seed runtime) :
    FindStateBodyExecution layout workspace values workspaceCell position seed
      runtime invariant := by
  let headRead := invariant.read_chart_head
  cases chart : workspace.chart position with
  | nil =>
      have headValue : chartHeadValue workspace position = -1 := by
        simp [chartHeadValue, chart, encodeStateId]
      have initializer : Evaluates verifiedParserCore runtime
          parserFindChartHeadExpr (.signed .i32 (-1)) headRead.after := by
        simpa only [headValue] using headRead.evaluation
      let bound := headRead.after.bindLocal 4 (.signed .i32 (-1))
      have boundWellFormed : StateWellFormed bound :=
        bindLocal_preserves_well_formed headRead.after 4 (.signed .i32 (-1))
          headRead.invariant.wellFormed
      have currentOwned : (Assertion.localPointsTo 4 headRead.after.nextCell
          (some (.signed .i32 (-1)))).holds bound := by
        constructor
        · simp [bound, State.bindLocal, State.bindCell, State.cellId?]
        · simpa [bound, State.bindLocal] using
            bindCell_finds_fresh_cell headRead.after 4
              (some (.signed .i32 (-1))) headRead.invariant.wellFormed
      have missingLocal := Assertion.localPointsTo_local 4
        headRead.after.nextCell (.signed .i32 (-1)) bound currentOwned
      have conditionFalse :=
        evaluatesParserFindLoopCondition_missing missingLocal
      have loopExecution : Executes verifiedParserCore bound parserFindLoop
          .next bound := by
        simpa [parserFindLoop] using
          (executesWhileFalse (body := parserFindLoopBody) conditionFalse)
      have bodyExecution : Executes verifiedParserCore bound
          (.sequence parserFindLoop parserFindReturnMissing)
          (.returned (some (.signed .i32 (-1)))) bound :=
        executesSequence loopExecution (executesParserFindReturnMissing bound)
      have scopedExecution := executesLetLocal (type := parserI32Type)
        initializer bodyExecution
      let after := restoreLocals headRead.after bound
      have expected : workspace.findStateId? position seed.key = none := by
        simp [LogicalWorkspace.findStateId?, chart, findStateIn?]
      have scopeEffect := bindLocal_effect headRead.after 4
        (.signed .i32 (-1))
      have afterWellFormed : StateWellFormed after := by
        exact scopeEffect.restoreLocals_wellFormed
          headRead.invariant.wellFormed boundWellFormed
      have closedEffect : ModifiesOnly CellSet.empty headRead.after after := by
        simpa [after] using scopeEffect.restoreLocals
      exact {
        after := after
        execution := by
            rw [expected]
            simpa [parserFindStateBody, after, encodeStateId] using scopedExecution
        effect := headRead.effect.trans_same closedEffect
        wellFormed := afterWellFormed
        backing := closedEffect.empty_preserves_entry
          headRead.invariant.wellFormed headRead.invariant.backing
      }
  | cons current remaining =>
      have headValue : chartHeadValue workspace position = Int.ofNat current := by
        simp [chartHeadValue, chart, encodeStateId]
      have initializer : Evaluates verifiedParserCore runtime
          parserFindChartHeadExpr (.signed .i32 (Int.ofNat current))
          headRead.after := by
        simpa only [headValue] using headRead.evaluation
      let searchInvariant := headRead.bind_nonempty chart
      let loop := searchInvariant.execute_find_loop
      let bound := headRead.after.bindLocal 4
        (.signed .i32 (Int.ofNat current))
      have expected : workspace.findStateId? position seed.key =
          findStateIn? workspace seed.key (current :: remaining) := by
        simp [LogicalWorkspace.findStateId?, chart]
      cases lookup : findStateIn? workspace seed.key (current :: remaining) with
      | none =>
          have loopNext : Executes verifiedParserCore bound parserFindLoop
              .next loop.after := by
            have execution := loop.execution
            rw [lookup] at execution
            simpa [parserFindLoopCompletion, bound, searchInvariant] using execution
          have bodyExecution : Executes verifiedParserCore bound
              (.sequence parserFindLoop parserFindReturnMissing)
              (.returned (some (.signed .i32 (-1)))) loop.after :=
            executesSequence loopNext
              (executesParserFindReturnMissing loop.after)
          have scopedExecution := executesLetLocal (type := parserI32Type)
            initializer bodyExecution
          let after := restoreLocals headRead.after loop.after
          have entered : StoreEffect
              (CellSet.singleton searchInvariant.currentCell)
              headRead.after bound :=
            (bindLocal_effect headRead.after 4
              (.signed .i32 (Int.ofNat current))).weaken
                CellSet.empty_subset
          have bodyEffect := entered.trans_same loop.effect.toStoreEffect
          have afterWellFormed : StateWellFormed after := by
            exact bodyEffect.restoreLocals_wellFormed
              headRead.invariant.wellFormed loop.wellFormed
          have closedEffect : ModifiesOnly
              (CellSet.singleton searchInvariant.currentCell)
              headRead.after after := by
            simpa [after] using bodyEffect.restoreLocals
          have hiddenEffect : ModifiesOnly CellSet.empty headRead.after after :=
            closedEffect.hideFreshWrites (by
              intro cell written
              change cell = searchInvariant.currentCell at written
              subst cell
              exact Nat.le_refl _)
          exact {
            after := after
            execution := by
              rw [expected, lookup]
              simpa [parserFindStateBody, after, encodeStateId] using
                scopedExecution
            effect := headRead.effect.trans_same hiddenEffect
            wellFormed := afterWellFormed
            backing := hiddenEffect.empty_preserves_entry
              headRead.invariant.wellFormed headRead.invariant.backing
          }
      | some foundId =>
          have loopReturned : Executes verifiedParserCore bound parserFindLoop
              (.returned (some (.signed .i32 (Int.ofNat foundId))))
              loop.after := by
            have execution := loop.execution
            rw [lookup] at execution
            simpa [parserFindLoopCompletion, bound, searchInvariant] using execution
          have bodyExecution : Executes verifiedParserCore bound
              (.sequence parserFindLoop parserFindReturnMissing)
              (.returned (some (.signed .i32 (Int.ofNat foundId))))
              loop.after := executesSequenceReturned loopReturned
          have scopedExecution := executesLetLocal (type := parserI32Type)
            initializer bodyExecution
          let after := restoreLocals headRead.after loop.after
          have entered : StoreEffect
              (CellSet.singleton searchInvariant.currentCell)
              headRead.after bound :=
            (bindLocal_effect headRead.after 4
              (.signed .i32 (Int.ofNat current))).weaken
                CellSet.empty_subset
          have bodyEffect := entered.trans_same loop.effect.toStoreEffect
          have afterWellFormed : StateWellFormed after := by
            exact bodyEffect.restoreLocals_wellFormed
              headRead.invariant.wellFormed loop.wellFormed
          have closedEffect : ModifiesOnly
              (CellSet.singleton searchInvariant.currentCell)
              headRead.after after := by
            simpa [after] using bodyEffect.restoreLocals
          have hiddenEffect : ModifiesOnly CellSet.empty headRead.after after :=
            closedEffect.hideFreshWrites (by
              intro cell written
              change cell = searchInvariant.currentCell at written
              subst cell
              exact Nat.le_refl _)
          exact {
            after := after
            execution := by
              rw [expected, lookup]
              simpa [parserFindStateBody, after, encodeStateId] using
                scopedExecution
            effect := headRead.effect.trans_same hiddenEffect
            wellFormed := afterWellFormed
            backing := hiddenEffect.empty_preserves_entry
              headRead.invariant.wellFormed headRead.invariant.backing
          }

def parserFindStateBindings
    (values : List Int) (workspaceCell : CellId)
    (layout : WorkspaceLayout) (position : Nat) (seed : StateSeed) :
    List (VarId × Value) := [
  (0, workspaceValue values workspaceCell),
  (1, .signed .i32 (Int.ofNat (stateBase layout.tokenCount))),
  (2, .signed .i32 (Int.ofNat position)),
  (3, stateSeedValue seed)]

def parserFindStateCallee
    (caller : State) (values : List Int) (workspaceCell : CellId)
    (layout : WorkspaceLayout) (position : Nat) (seed : StateSeed) : State :=
  enterCall caller
    (parserFindStateBindings values workspaceCell layout position seed)

theorem parserFindStateCallee_entry
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed) (caller : State)
    (valuesLength : values.length = layout.workspaceLength)
    (encoded : EncodesWorkspace layout workspace (listWords values))
    (positionBound : position ≤ finalPosition layout.tokenCount)
    (wellFormed : StateWellFormed caller)
    (backing : caller.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values values))
    }) :
    EntryInvariant layout workspace values workspaceCell position seed
      (parserFindStateCallee caller values workspaceCell layout position seed) := by
  let value := workspaceValue values workspaceCell
  let base := Int.ofNat (stateBase layout.tokenCount)
  let sourcePosition := Int.ofNat position
  let seedValue := stateSeedValue seed
  let bindings : List (VarId × Value) := [
    (0, value), (1, .signed .i32 base),
    (2, .signed .i32 sourcePosition), (3, seedValue)]
  let callee := enterCall caller bindings
  have calleeWellFormed : StateWellFormed callee :=
    enterCall_preserves_wellFormed wellFormed
  have workspaceOld : workspaceCell < caller.nextCell :=
    Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
      wellFormed backing
  have calleeBacking : callee.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values values))
    } := by
    have preserved := (enterCall_effect caller bindings).oldCells
      workspaceCell workspaceOld (by simp [CellSet.empty])
    exact preserved.trans backing
  have local0 : callee.local? 0 = some value := by
    simpa [callee, bindings] using
      (enterCall_local_of_binding caller [] [
          (1, .signed .i32 base), (2, .signed .i32 sourcePosition),
          (3, seedValue)] 0 value wellFormed (by simp))
  have local1 : callee.local? 1 = some (.signed .i32 base) := by
    simpa [callee, bindings] using
      (enterCall_local_of_binding caller [(0, value)] [
          (2, .signed .i32 sourcePosition), (3, seedValue)]
        1 (.signed .i32 base) wellFormed (by simp))
  have local2 : callee.local? 2 =
      some (.signed .i32 sourcePosition) := by
    simpa [callee, bindings] using
      (enterCall_local_of_binding caller [
          (0, value), (1, .signed .i32 base)] [(3, seedValue)]
        2 (.signed .i32 sourcePosition) wellFormed (by simp))
  have local3 : callee.local? 3 = some seedValue := by
    simpa [callee, bindings] using
      (enterCall_local_of_binding caller [
          (0, value), (1, .signed .i32 base),
          (2, .signed .i32 sourcePosition)] []
        3 seedValue wellFormed (by simp))
  simpa [parserFindStateCallee, parserFindStateBindings, value, base,
      sourcePosition, seedValue, bindings, callee] using
    (show EntryInvariant layout workspace values workspaceCell position seed
        callee from {
      valuesLength := valuesLength
      encoded := encoded
      positionBound := positionBound
      wellFormed := calleeWellFormed
      workspaceLocal := local0
      baseLocal := local1
      positionLocal := local2
      seedLocal := local3
      backing := calleeBacking
    })

/-- Full source-call contract for the extracted `find_state`.  The theorem
    starts at ordinary caller expressions, validates the extracted parameter
    ABI and body, restores caller locals, and exposes a read-only effect on the
    encoded parser workspace. -/
theorem extractedParserFindStateCall_evaluates
    (layout : WorkspaceLayout) (workspace : LogicalWorkspace)
    (values : List Int) (workspaceCell : CellId)
    (position : Nat) (seed : StateSeed)
    (before afterArguments : State) (arguments : List Expr)
    (valuesLength : values.length = layout.workspaceLength)
    (encoded : EncodesWorkspace layout workspace (listWords values))
    (positionBound : position ≤ finalPosition layout.tokenCount)
    (afterArgumentsWellFormed : StateWellFormed afterArguments)
    (argumentsResult : ArgumentsEvaluateTo verifiedParserCore before arguments [
      workspaceValue values workspaceCell,
      .signed .i32 (Int.ofNat (stateBase layout.tokenCount)),
      .signed .i32 (Int.ofNat position),
      stateSeedValue seed] afterArguments)
    (backing : afterArguments.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values values))
    }) :
    ∃ after,
      Evaluates verifiedParserCore before
        (.call extractedParserFindStateFunction.id arguments)
        (.signed .i32
          (encodeStateId (workspace.findStateId? position seed.key))) after ∧
      ModifiesOnly CellSet.empty afterArguments after ∧
      StateWellFormed after ∧
      after.cellEntry? workspaceCell = some {
        id := workspaceCell
        value := some (.array (signedI32Values values))
      } := by
  let bindings := parserFindStateBindings values workspaceCell layout
    position seed
  let callee := parserFindStateCallee afterArguments values workspaceCell
    layout position seed
  have entry : EntryInvariant layout workspace values workspaceCell position
      seed callee := by
    simpa [callee] using parserFindStateCallee_entry layout workspace values
      workspaceCell position seed afterArguments valuesLength encoded
      positionBound afterArgumentsWellFormed backing
  let bodyResult := entry.execute_find_body
  let after := restoreLocals afterArguments bodyResult.after
  have evaluation : Evaluates verifiedParserCore before
      (.call extractedParserFindStateFunction.id arguments)
      (.signed .i32
        (encodeStateId (workspace.findStateId? position seed.key))) after := by
    apply evaluatesCallReturned (body := parserFindStateBody)
      argumentsResult verifiedParserCore_finds_findState
    · rw [extractedParserFindState_function_signature.2.1]
      rfl
    · rfl
    · simpa [after, callee, parserFindStateCallee, bindings,
        parserFindStateBindings] using bodyResult.execution
  have bodyStore : StoreEffect CellSet.empty callee bodyResult.after :=
    bodyResult.effect.toStoreEffect
  have callStore : StoreEffect CellSet.empty afterArguments bodyResult.after := by
    have entered := enterCall_effect afterArguments bindings
    simpa [callee, parserFindStateCallee] using entered.trans_same bodyStore
  have callEffect : ModifiesOnly CellSet.empty afterArguments after := by
    simpa [after] using callStore.restoreLocals
  have afterWellFormed : StateWellFormed after := by
    exact callStore.restoreLocals_wellFormed afterArgumentsWellFormed
      bodyResult.wellFormed
  have afterBacking : after.cellEntry? workspaceCell = some {
      id := workspaceCell
      value := some (.array (signedI32Values values))
    } := callEffect.empty_preserves_entry afterArgumentsWellFormed backing
  exact ⟨after, evaluation, callEffect, afterWellFormed, afterBacking⟩

end Lanius.Extraction.ParserFind
