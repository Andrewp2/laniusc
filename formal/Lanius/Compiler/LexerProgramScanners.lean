import Lanius.Compiler.LexerProgram
import Lanius.ExecutionRules
import Lanius.Fuel
import Lanius.FunctionalViewCoreStatefulSimulation
import Lanius.Properties

namespace Lanius.Compiler.Lexer.Program

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Fuel
open Lanius.Properties

structure FrameExtension (before after : State) : Prop where
  locals : after.locals = before.locals
  oldCells : ∀ cell, cell < before.nextCell →
    after.cellEntry? cell = before.cellEntry? cell
  nextCell : before.nextCell ≤ after.nextCell
  heap : after.heap = before.heap
  world : after.world = before.world
  views : after.i32ArrayViews = before.i32ArrayViews

structure StoreExtension (before after : State) : Prop where
  oldCells : ∀ cell, cell < before.nextCell →
    after.cellEntry? cell = before.cellEntry? cell
  nextCell : before.nextCell ≤ after.nextCell
  heap : after.heap = before.heap
  world : after.world = before.world
  views : after.i32ArrayViews = before.i32ArrayViews

/-- Store identities survive, while their contents may change. This is the
right contract for restoring caller locals after a callee mutates variables
that were already allocated in the caller's frame. -/
structure CellDomainExtension (before after : State) : Prop where
  cells : ∀ entry, entry ∈ before.cells →
    ∃ nextEntry, nextEntry ∈ after.cells ∧ nextEntry.id = entry.id

theorem CellDomainExtension.refl (state : State) :
    CellDomainExtension state state := by
  exact ⟨fun entry member => ⟨entry, member, rfl⟩⟩

theorem CellDomainExtension.trans
    (first : CellDomainExtension before middle)
    (second : CellDomainExtension middle after) :
    CellDomainExtension before after := by
  constructor
  intro entry member
  obtain ⟨middleEntry, middleMember, middleId⟩ := first.cells entry member
  obtain ⟨afterEntry, afterMember, afterId⟩ :=
    second.cells middleEntry middleMember
  exact ⟨afterEntry, afterMember, afterId.trans middleId⟩

theorem CellDomainExtension.restoreLocals
    (extension : CellDomainExtension before completed) :
    CellDomainExtension before (Lanius.Semantics.restoreLocals caller completed) := by
  constructor
  intro entry member
  simpa [Lanius.Semantics.restoreLocals] using extension.cells entry member

theorem bindLocal_domain_extends (state : State) (id : VarId) (value : Value) :
    CellDomainExtension state (state.bindLocal id value) := by
  constructor
  intro entry member
  exact ⟨entry, List.mem_append_left _ member, rfl⟩

theorem bindLocals_preserves_well_formed
    (state : State) (bindings : List (VarId × Value))
    (wellFormed : StateWellFormed state) :
    StateWellFormed (state.bindLocals bindings) := by
  induction bindings generalizing state with
  | nil => simpa [State.bindLocals]
  | cons binding rest inductionHypothesis =>
      simp only [State.bindLocals, List.foldl_cons]
      exact inductionHypothesis (state := state.bindLocal binding.1 binding.2)
        (bindLocal_preserves_well_formed state binding.1 binding.2 wellFormed)

theorem bindLocals_nextCell
    (state : State) (bindings : List (VarId × Value)) :
    (state.bindLocals bindings).nextCell = state.nextCell + bindings.length := by
  induction bindings generalizing state with
  | nil => simp [State.bindLocals]
  | cons binding rest inductionHypothesis =>
      simp only [State.bindLocals, List.foldl_cons]
      change ((state.bindLocal binding.1 binding.2).bindLocals rest).nextCell = _
      rw [inductionHypothesis]
      simp only [State.bindLocal, State.bindCell, List.length_cons]
      rw [Nat.add_assoc]
      exact congrArg (state.nextCell + ·) (Nat.add_comm 1 rest.length)

theorem bindLocals_preserves_old_cell
    (state : State) (bindings : List (VarId × Value)) (cell : CellId)
    (old : cell < state.nextCell) :
    (state.bindLocals bindings).cellEntry? cell = state.cellEntry? cell := by
  induction bindings generalizing state with
  | nil => simp [State.bindLocals]
  | cons binding rest inductionHypothesis =>
      simp only [State.bindLocals, List.foldl_cons]
      change ((state.bindLocal binding.1 binding.2).bindLocals rest).cellEntry?
        cell = _
      rw [inductionHypothesis (state := state.bindLocal binding.1 binding.2)
        (by simpa [State.bindLocal, State.bindCell] using Nat.lt_succ_of_lt old)]
      exact bindCell_preserves_old_cell state binding.1 (some binding.2) cell old

theorem bindLocals_append
    (state : State) (first second : List (VarId × Value)) :
    state.bindLocals (first ++ second) =
      (state.bindLocals first).bindLocals second := by
  simp [State.bindLocals, List.foldl_append]

theorem bindLocals_finds_cell_after_prefix
    (state : State) (preceding following : List (VarId × Value))
    (id : VarId) (value : Value) (wellFormed : StateWellFormed state) :
    (state.bindLocals (preceding ++ (id, value) :: following)).cellEntry?
        (state.nextCell + preceding.length) =
      some { id := state.nextCell + preceding.length, value := some value } := by
  let before := state.bindLocals preceding
  have beforeWellFormed := bindLocals_preserves_well_formed state preceding wellFormed
  have beforeNext : before.nextCell = state.nextCell + preceding.length := by
    exact bindLocals_nextCell state preceding
  have fresh := bindCell_finds_fresh_cell before id (some value) beforeWellFormed
  have old : before.nextCell < (before.bindLocal id value).nextCell := by
    simp [State.bindLocal, State.bindCell]
  have preserved := bindLocals_preserves_old_cell
    (before.bindLocal id value) following before.nextCell old
  rw [bindLocals_append]
  change ((before.bindLocal id value).bindLocals following).cellEntry?
      (state.nextCell + preceding.length) = _
  rw [← beforeNext]
  exact preserved.trans (by simpa [State.bindLocal] using fresh)

theorem assignCell_domain_extends
    (assigned : state.assignCell cell value = some next) :
    CellDomainExtension state next := by
  rw [assignCell_state assigned, replaceCell_eq_map]
  constructor
  intro entry member
  let updated :=
    if entry.id == cell then { entry with value := some value } else entry
  refine ⟨updated, List.mem_map.2 ⟨entry, member, rfl⟩, ?_⟩
  exact updatedCell_id entry cell value

theorem CellDomainExtension.restoreLocals_well_formed
    (extension : CellDomainExtension before completed)
    (beforeWellFormed : StateWellFormed before)
    (completedWellFormed : StateWellFormed completed) :
    StateWellFormed (Lanius.Semantics.restoreLocals before completed) := by
  constructor
  · exact completedWellFormed.heapWellFormed
  · exact completedWellFormed.cellIdsUnique
  · exact completedWellFormed.cellIdsBelowNext
  · intro binding member
    obtain ⟨entry, entryMember, entryId⟩ :=
      beforeWellFormed.localsReferenceCells binding member
    obtain ⟨completedEntry, completedMember, completedId⟩ :=
      extension.cells entry entryMember
    exact ⟨completedEntry, completedMember, completedId.trans entryId⟩

theorem FrameExtension.store
    (extension : FrameExtension before after) : StoreExtension before after :=
  ⟨extension.oldCells, extension.nextCell, extension.heap,
    extension.world, extension.views⟩

theorem StoreExtension.trans
    (first : StoreExtension before middle)
    (second : StoreExtension middle after) : StoreExtension before after := by
  constructor
  · intro cell old
    rw [second.oldCells cell (Nat.lt_of_lt_of_le old first.nextCell),
      first.oldCells cell old]
  · exact Nat.le_trans first.nextCell second.nextCell
  · exact second.heap.trans first.heap
  · exact second.world.trans first.world
  · exact second.views.trans first.views

theorem StoreExtension.restoreLocals
    (extension : StoreExtension before completed) :
    FrameExtension before (restoreLocals before completed) := by
  exact ⟨rfl, extension.oldCells, extension.nextCell, extension.heap,
    extension.world, extension.views⟩

theorem FrameExtension.refl (state : State) : FrameExtension state state := by
  exact ⟨rfl, fun _ _ => rfl, Nat.le_refl _, rfl, rfl, rfl⟩

theorem FrameExtension.trans
    (first : FrameExtension before middle)
    (second : FrameExtension middle after) :
    FrameExtension before after := by
  constructor
  · exact second.locals.trans first.locals
  · intro cell old
    rw [second.oldCells cell (Nat.lt_of_lt_of_le old first.nextCell),
      first.oldCells cell old]
  · exact Nat.le_trans first.nextCell second.nextCell
  · exact second.heap.trans first.heap
  · exact second.world.trans first.world
  · exact second.views.trans first.views

theorem FrameExtension.preserves_local
    {id : VarId} {value : Value}
    (extension : FrameExtension before after)
    (wellFormed : StateWellFormed before)
    (found : before.local? id = some value) :
    after.local? id = some value := by
  rw [State.local?, Option.bind_eq_some_iff] at found
  obtain ⟨cell, cellId, cellValue⟩ := found
  rw [State.cell?, Option.bind_eq_some_iff] at cellValue
  obtain ⟨entry, cellEntry, initialized⟩ := cellValue
  have member : entry ∈ before.cells := List.mem_of_find?_eq_some cellEntry
  have entryId : entry.id = cell := by
    simpa using List.find?_some cellEntry
  have old : cell < before.nextCell := by
    rw [← entryId]
    exact wellFormed.cellIdsBelowNext entry member
  have afterCellId : after.cellId? id = some cell := by
    unfold State.cellId?
    rw [extension.locals]
    exact cellId
  rw [State.local?, afterCellId]
  simp only [Option.bind_some, State.cell?]
  rw [extension.oldCells cell old, cellEntry]
  simp [initialized]

theorem findCell_of_unique
    (cells : List Cell)
    (unique : ∀ left, left ∈ cells → ∀ right, right ∈ cells →
      left.id = right.id → left = right)
    (member : entry ∈ cells) :
    cells.find? (fun cell => cell.id == entry.id) = some entry := by
  induction cells with
  | nil => simp at member
  | cons head tail inductionHypothesis =>
      by_cases sameId : head.id = entry.id
      · have sameEntry := unique head (by simp) entry member sameId
        subst head
        simp
      · have different : head ≠ entry := by
          intro sameEntry
          exact sameId (congrArg Cell.id sameEntry)
        have differentRev : entry ≠ head := Ne.symm different
        have tailMember : entry ∈ tail := by
          simpa [differentRev] using member
        have tailUnique : ∀ left, left ∈ tail → ∀ right, right ∈ tail →
            left.id = right.id → left = right := by
          intro left leftMember right rightMember
          exact unique left (by simp [leftMember]) right (by simp [rightMember])
        simp [sameId, inductionHypothesis tailUnique tailMember]

theorem stateWellFormed_cellEntry_of_mem
    (wellFormed : StateWellFormed state)
    (member : entry ∈ state.cells) :
    state.cellEntry? entry.id = some entry := by
  exact findCell_of_unique state.cells wellFormed.cellIdsUnique member

theorem StoreExtension.restoreLocals_well_formed
    (extension : StoreExtension before completed)
    (beforeWellFormed : StateWellFormed before)
    (completedWellFormed : StateWellFormed completed) :
    StateWellFormed (Lanius.Semantics.restoreLocals before completed) := by
  constructor
  · exact completedWellFormed.heapWellFormed
  · exact completedWellFormed.cellIdsUnique
  · exact completedWellFormed.cellIdsBelowNext
  · intro binding member
    obtain ⟨entry, entryMember, entryId⟩ :=
      beforeWellFormed.localsReferenceCells binding member
    have old : entry.id < before.nextCell :=
      beforeWellFormed.cellIdsBelowNext entry entryMember
    have beforeFound := stateWellFormed_cellEntry_of_mem
      beforeWellFormed entryMember
    have completedFound : completed.cellEntry? entry.id = some entry := by
      rw [extension.oldCells entry.id old, beforeFound]
    exact ⟨entry, List.mem_of_find?_eq_some completedFound, entryId⟩

def clearLocals (state : State) : State := { state with locals := [] }

theorem clearLocals_well_formed (state : State) (wellFormed : StateWellFormed state) :
    StateWellFormed (clearLocals state) := by
  refine ⟨wellFormed.heapWellFormed, wellFormed.cellIdsUnique,
    wellFormed.cellIdsBelowNext, ?_⟩
  simp [clearLocals, LocalsReferenceCells]

def singleArgumentCalleeState (state : State) (value : Value) : State :=
  (clearLocals state).bindLocal 0 value

def singleArgumentCallState (state : State) (value : Value) : State :=
  restoreLocals state (singleArgumentCalleeState state value)

theorem singleArgumentCalleeState_store_extends
    (state : State) (value : Value) :
    StoreExtension state (singleArgumentCalleeState state value) := by
  constructor
  · intro cell old
    simpa [singleArgumentCalleeState, clearLocals, State.bindLocal,
      State.cellEntry?] using
      bindCell_preserves_old_cell (clearLocals state) 0 (some value) cell old
  · simp [singleArgumentCalleeState, clearLocals, State.bindLocal,
      State.bindCell]
  · rfl
  · rfl
  · rfl

theorem singleArgumentCallState_extends
    (state : State) (value : Value) :
    FrameExtension state (singleArgumentCallState state value) :=
  (singleArgumentCalleeState_store_extends state value).restoreLocals

theorem singleArgumentCalleeState_well_formed
    (state : State) (wellFormed : StateWellFormed state) (value : Value) :
    StateWellFormed (singleArgumentCalleeState state value) :=
  bindLocal_preserves_well_formed (clearLocals state) 0 value
    (clearLocals_well_formed state wellFormed)

theorem singleArgumentCallState_well_formed
    (state : State) (wellFormed : StateWellFormed state) (value : Value) :
    StateWellFormed (singleArgumentCallState state value) :=
  (singleArgumentCalleeState_store_extends state value)
    |>.restoreLocals_well_formed wellFormed
      (singleArgumentCalleeState_well_formed state wellFormed value)

theorem singleArgumentCalleeState_local
    (state : State) (wellFormed : StateWellFormed state) (value : Value) :
    (singleArgumentCalleeState state value).local? 0 = some value := by
  let cleared := clearLocals state
  have clearedWellFormed := clearLocals_well_formed state wellFormed
  have fresh := bindCell_finds_fresh_cell cleared 0 (some value)
    clearedWellFormed
  simp only [singleArgumentCalleeState, State.bindLocal, State.local?,
    State.cellId?, State.bindCell, List.find?_cons, beq_self_eq_true]
  exact congrArg (fun entry => entry.bind Cell.value) fresh

theorem singleArgumentFunctionCall_executes
    (fuel : Nat) (positive : 0 < fuel)
    (function : Function) (parameterType : Ty)
    (body : Stmt) (state : State) (argument : Expr)
    (argumentValue resultValue : Value) (bodyFinal : State)
    (functionFound : lexerProgram.function? function.id = some function)
    (parameters : function.parameters = [(0, parameterType)])
    (functionBody : function.body = some body)
    (argumentResult : evalExpr fuel lexerProgram state argument =
      .done argumentValue state)
    (bodyResult : execStmt (fuel + 1) lexerProgram
      (singleArgumentCalleeState state argumentValue) body =
      .done (.returned (some resultValue)) bodyFinal) :
    evalExpr (fuel + 2) lexerProgram state (.call function.id [argument]) =
      .done resultValue (restoreLocals state bodyFinal) := by
  have arguments :
      evalExprs (fuel + 1) lexerProgram state [argument] =
        .done [argumentValue] state := by
    cases fuel with
    | zero => omega
    | succ remaining =>
        rw [Lanius.Semantics.evalExprs.eq_def]
        simp only
        rw [argumentResult]
        rfl
  have boundParameters :
      bindParameters function.parameters [argumentValue] =
        some [(0, argumentValue)] := by
    rw [parameters]
    rfl
  have callee :
      ({ state with locals := [] }).bindLocals [(0, argumentValue)] =
        singleArgumentCalleeState state argumentValue := by
    rfl
  cases fuel with
  | zero => omega
  | succ remaining =>
      rw [evalExpr, arguments]
      simp only
      rw [functionFound]
      simp only
      rw [boundParameters, functionBody]
      simp only
      rw [callee, bodyResult]

/-- Fuel-synchronized call rule for a unary function with an arbitrary
    statement body. Unlike the older proof-program helper, this rule is
    independent of any particular `Program` and therefore applies directly to
    source-extracted functions, including their unnormalized statement lists. -/
theorem unaryFunctionCallWithBody_executes
    (program : Program) (fuel : Nat) (positive : 0 < fuel)
    (function : Function) (parameterType : Ty) (body : Stmt)
    (state : State) (argument : Expr) (argumentValue resultValue : Value)
    (bodyFinal : State)
    (functionFound : program.function? function.id = some function)
    (parameters : function.parameters = [(0, parameterType)])
    (functionBody : function.body = some body)
    (argumentResult : evalExpr fuel program state argument =
      .done argumentValue state)
    (bodyResult : execStmt (fuel + 1) program
      (singleArgumentCalleeState state argumentValue) body =
      .done (.returned (some resultValue)) bodyFinal) :
    evalExpr (fuel + 2) program state (.call function.id [argument]) =
      .done resultValue (restoreLocals state bodyFinal) := by
  have arguments :
      evalExprs (fuel + 1) program state [argument] =
        .done [argumentValue] state := by
    cases fuel with
    | zero => omega
    | succ remaining =>
        rw [Lanius.Semantics.evalExprs.eq_def]
        simp only
        rw [argumentResult]
        rfl
  have boundParameters :
      bindParameters function.parameters [argumentValue] =
        some [(0, argumentValue)] := by
    rw [parameters]
    rfl
  have callee :
      ({ state with locals := [] }).bindLocals [(0, argumentValue)] =
        singleArgumentCalleeState state argumentValue := by
    rfl
  cases fuel with
  | zero => omega
  | succ remaining =>
      rw [evalExpr, arguments]
      simp only
      rw [functionFound]
      simp only
      rw [boundParameters, functionBody]
      simp only
      rw [callee, bodyResult]

def unaryCalleeState (state : State) (byte : Byte) : State :=
  (clearLocals state).bindLocal 0 (.signed .i32 byte.val)

theorem unaryCalleeState_store_extends (state : State) (byte : Byte) :
    StoreExtension state (unaryCalleeState state byte) := by
  constructor
  · intro cell old
    simpa [unaryCalleeState, clearLocals, State.bindLocal, State.cellEntry?]
      using bindCell_preserves_old_cell (clearLocals state) 0
        (some (.signed .i32 byte.val)) cell old
  · simp [unaryCalleeState, clearLocals, State.bindLocal, State.bindCell]
  · rfl
  · rfl
  · rfl

theorem unaryCalleeState_local
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    (unaryCalleeState state byte).local? 0 = some (.signed .i32 byte.val) := by
  let cleared := clearLocals state
  have clearedWellFormed : StateWellFormed cleared :=
    clearLocals_well_formed state wellFormed
  have fresh := bindCell_finds_fresh_cell cleared 0
    (some (.signed .i32 byte.val)) clearedWellFormed
  simp only [unaryCalleeState, State.bindLocal, State.local?, State.cellId?,
    State.bindCell, List.find?_cons, beq_self_eq_true]
  exact congrArg (fun entry => entry.bind Cell.value) fresh

theorem unaryCalleeState_cellId (state : State) (byte : Byte) :
    (unaryCalleeState state byte).cellId? 0 = some state.nextCell := by
  rfl

theorem unaryCalleeState_cellEntry
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    (unaryCalleeState state byte).cellEntry? state.nextCell =
      some { id := state.nextCell, value := some (.signed .i32 byte.val) } := by
  let cleared := clearLocals state
  have clearedWellFormed : StateWellFormed cleared :=
    clearLocals_well_formed state wellFormed
  simpa [unaryCalleeState, State.bindLocal, cleared, clearLocals] using
    bindCell_finds_fresh_cell cleared 0 (some (.signed .i32 byte.val))
      clearedWellFormed

theorem compareByteEqual_executes
    (program : Program)
    (state : State) (wellFormed : StateWellFormed state)
    (byte : Byte) (value : Int) :
    evalExpr 3 program (unaryCalleeState state byte)
      (compareByte .equal value) =
      .done (.boolean (Int.ofNat byte.val == value))
        (unaryCalleeState state byte) := by
  simp only [compareByte, byteLocal, i32Literal, evalExpr,
    unaryCalleeState_cellId state byte,
    unaryCalleeState_cellEntry state wellFormed byte,
    evalBinaryValue, scalarEqual, beq_self_eq_true, ↓reduceIte]
  rfl

theorem compareByteGreaterEqual_executes
    (program : Program)
    (state : State) (wellFormed : StateWellFormed state)
    (byte : Byte) (value : Int) :
    evalExpr 3 program (unaryCalleeState state byte)
      (compareByte .greaterEqual value) =
      .done (.boolean (decide (Int.ofNat byte.val ≥ value)))
        (unaryCalleeState state byte) := by
  simp only [compareByte, byteLocal, i32Literal, evalExpr,
    unaryCalleeState_cellId state byte,
    unaryCalleeState_cellEntry state wellFormed byte,
    evalBinaryValue, beq_self_eq_true, if_true, evalSignedBinary]
  rfl

theorem compareByteLessEqual_executes
    (program : Program)
    (state : State) (wellFormed : StateWellFormed state)
    (byte : Byte) (value : Int) :
    evalExpr 3 program (unaryCalleeState state byte)
      (compareByte .lessEqual value) =
      .done (.boolean (decide (Int.ofNat byte.val ≤ value)))
        (unaryCalleeState state byte) := by
  simp only [compareByte, byteLocal, i32Literal, evalExpr,
    unaryCalleeState_cellId state byte,
    unaryCalleeState_cellEntry state wellFormed byte,
    evalBinaryValue, beq_self_eq_true, if_true, evalSignedBinary]
  rfl

def unaryCallState (state : State) (byte : Byte) : State :=
  restoreLocals state (unaryCalleeState state byte)

theorem unaryCallState_extends
    (state : State) (byte : Byte) :
    FrameExtension state (unaryCallState state byte) := by
  constructor
  · rfl
  · intro cell old
    change (unaryCalleeState state byte).cellEntry? cell =
      state.cellEntry? cell
    simpa [unaryCalleeState, clearLocals, State.bindLocal, State.cellEntry?] using
      bindCell_preserves_old_cell (clearLocals state) 0
        (some (.signed .i32 byte.val)) cell old
  · simp [unaryCallState, restoreLocals, unaryCalleeState, clearLocals,
      State.bindLocal, State.bindCell]
  · rfl
  · rfl
  · rfl

theorem unaryCallState_well_formed
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    StateWellFormed (unaryCallState state byte) := by
  have calleeWellFormed : StateWellFormed (unaryCalleeState state byte) :=
    bindLocal_preserves_well_formed (clearLocals state) 0
      (.signed .i32 byte.val) (clearLocals_well_formed state wellFormed)
  constructor
  · exact calleeWellFormed.heapWellFormed
  · exact calleeWellFormed.cellIdsUnique
  · exact calleeWellFormed.cellIdsBelowNext
  · intro binding member
    obtain ⟨cell, cellMember, cellId⟩ :=
      wellFormed.localsReferenceCells binding member
    refine ⟨cell, ?_, cellId⟩
    exact List.mem_append_left _ cellMember

theorem compareByteEqual_executes_more
    (program : Program)
    (state : State) (wellFormed : StateWellFormed state)
    (byte : Byte) (value : Int) (extra : Nat) :
    evalExpr (extra + 3) program (unaryCalleeState state byte)
      (compareByte .equal value) =
      .done (.boolean (Int.ofNat byte.val == value))
        (unaryCalleeState state byte) := by
  have base := compareByteEqual_executes program state wellFormed byte value
  have terminal : Lanius.Fuel.Terminal
      (evalExpr 3 program (unaryCalleeState state byte)
        (compareByte .equal value)) := by
    rw [base]
    trivial
  exact (Lanius.Fuel.evalExpr_more_fuel (extra := extra) terminal).trans base

theorem orExpr_executes
    {program : Program} {fuel : Nat} {state : State}
    {left right : Expr} {leftValue rightValue : Bool}
    (leftResult : evalExpr fuel program state left =
      .done (.boolean leftValue) state)
    (rightResult : evalExpr fuel program state right =
      .done (.boolean rightValue) state) :
    evalExpr (fuel + 1) program state (orExpr left right) =
      .done (.boolean (leftValue || rightValue)) state := by
  cases leftValue <;> simp [orExpr, evalExpr, leftResult, rightResult]

theorem andExpr_executes
    {program : Program} {fuel : Nat} {state : State}
    {left right : Expr} {leftValue rightValue : Bool}
    (leftResult : evalExpr fuel program state left =
      .done (.boolean leftValue) state)
    (rightResult : evalExpr fuel program state right =
      .done (.boolean rightValue) state) :
    evalExpr (fuel + 1) program state (andExpr left right) =
      .done (.boolean (leftValue && rightValue)) state := by
  cases leftValue <;> simp [andExpr, evalExpr, leftResult, rightResult]

theorem andExpr_false_left
    {program : Program} {fuel : Nat} {state : State} {left right : Expr}
    (leftResult : evalExpr fuel program state left =
      .done (.boolean false) state) :
    evalExpr (fuel + 1) program state (andExpr left right) =
      .done (.boolean false) state := by
  simp [andExpr, evalExpr, leftResult]

theorem intOfNat_beq (left right : Nat) :
    (Int.ofNat left == Int.ofNat right) = (left == right) := by
  apply Bool.eq_iff_iff.mpr
  simp [Int.ofNat_inj]

theorem intOfNat_lt_decide (left right : Nat) :
    decide (Int.ofNat left < Int.ofNat right) = decide (left < right) := by
  apply Bool.eq_iff_iff.mpr
  simp [Int.ofNat_lt]

theorem intOfNat_le_decide (left right : Nat) :
    decide (Int.ofNat left ≤ Int.ofNat right) = decide (left ≤ right) := by
  apply Bool.eq_iff_iff.mpr
  simp [Int.ofNat_le]

theorem wrapSigned_i32_ofNat_at_target
    (target : Target) (value : Nat) (bounded : value ≤ 2147483647) :
    wrapSigned target .i32 (Int.ofNat value) = Int.ofNat value :=
  Lanius.Semantics.wrapSigned_i32_ofNat target value bounded

theorem wrapSigned_i32_ofNat
    (value : Nat) (bounded : value ≤ 2147483647) :
    wrapSigned lexerProgram.target .i32 (Int.ofNat value) = Int.ofNat value :=
  wrapSigned_i32_ofNat_at_target lexerProgram.target value bounded

theorem whitespaceExpr_executes
    (program : Program)
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    evalExpr 6 program (unaryCalleeState state byte) whitespaceExpr =
      .done (.boolean (isWhitespace byte)) (unaryCalleeState state byte) := by
  let callee := unaryCalleeState state byte
  have first := compareByteEqual_executes program state wellFormed byte 32
  have second := compareByteEqual_executes program state wellFormed byte 9
  have firstTwo := orExpr_executes (state := callee) first second
  have third := compareByteEqual_executes_more program state wellFormed byte 10 1
  have firstThree := orExpr_executes (state := callee) firstTwo third
  have fourth := compareByteEqual_executes_more program state wellFormed byte 13 2
  have allFour := orExpr_executes (state := callee) firstThree fourth
  have classification :
      ((Int.ofNat byte.val == (32 : Int)) ||
        (Int.ofNat byte.val == (9 : Int)) ||
        (Int.ofNat byte.val == (10 : Int)) ||
        (Int.ofNat byte.val == (13 : Int))) = isWhitespace byte := by
    unfold isWhitespace
    change
      ((Int.ofNat byte.val == Int.ofNat 32) ||
        (Int.ofNat byte.val == Int.ofNat 9) ||
        (Int.ofNat byte.val == Int.ofNat 10) ||
        (Int.ofNat byte.val == Int.ofNat 13)) =
      ((byte.val == 32) || (byte.val == 9) ||
        (byte.val == 10) || (byte.val == 13))
    simp only [intOfNat_beq]
  rw [classification] at allFour
  simpa [whitespaceExpr, byteEqualsAny, callee] using allFour

theorem lexerProgram_finds_isWhitespaceFunction :
    lexerProgram.function? isWhitespaceFunction.id = some isWhitespaceFunction := by
  rfl

theorem unaryBooleanFunctionCall_executes
    (function : Function) (body : Expr) (result : Bool)
    (state : State) (byte : Byte)
    (functionFound : lexerProgram.function? function.id = some function)
    (parameters : function.parameters = [(0, i32Type)])
    (functionBody : function.body = some (returnBool body))
    (bodyResult : evalExpr 8 lexerProgram (unaryCalleeState state byte) body =
      .done (.boolean result) (unaryCalleeState state byte)) :
    evalExpr 10 lexerProgram state (.call function.id [i32Literal byte.val]) =
      .done (.boolean result) (unaryCallState state byte) := by
  have arguments :
      evalExprs 9 lexerProgram state [i32Literal byte.val] =
        .done [.signed .i32 byte.val] state := by
    rfl
  have boundParameters :
      bindParameters function.parameters [.signed .i32 byte.val] =
        some [(0, .signed .i32 byte.val)] := by
    rw [parameters]
    rfl
  have callee :
      ({ state with locals := [] }).bindLocals
        [(0, .signed .i32 byte.val)] = unaryCalleeState state byte := by
    rfl
  have bodyExec :
      execStmt 9 lexerProgram (unaryCalleeState state byte) (returnBool body) =
        .done (.returned (some (.boolean result)))
          (unaryCalleeState state byte) := by
    rw [Lanius.Semantics.execStmt.eq_def]
    simp only [returnBool]
    rw [bodyResult]
  rw [evalExpr, arguments]
  simp only
  rw [functionFound]
  simp only
  rw [boundParameters, functionBody]
  simp only
  rw [callee, bodyExec]
  rfl

theorem unaryBooleanFunctionCallAtFuel_executes
    (fuel : Nat) (positive : 0 < fuel)
    (function : Function) (body : Expr) (result : Bool)
    (state : State) (byte : Byte)
    (functionFound : lexerProgram.function? function.id = some function)
    (parameters : function.parameters = [(0, i32Type)])
    (functionBody : function.body = some (returnBool body))
    (bodyResult : evalExpr fuel lexerProgram (unaryCalleeState state byte) body =
      .done (.boolean result) (unaryCalleeState state byte)) :
    evalExpr (fuel + 2) lexerProgram state
      (.call function.id [i32Literal byte.val]) =
      .done (.boolean result) (unaryCallState state byte) := by
  have arguments :
      evalExprs (fuel + 1) lexerProgram state [i32Literal byte.val] =
        .done [.signed .i32 byte.val] state := by
    cases fuel with
    | zero => omega
    | succ remaining => rfl
  have boundParameters :
      bindParameters function.parameters [.signed .i32 byte.val] =
        some [(0, .signed .i32 byte.val)] := by
    rw [parameters]
    rfl
  have callee :
      ({ state with locals := [] }).bindLocals
        [(0, .signed .i32 byte.val)] = unaryCalleeState state byte := by
    rfl
  have bodyExec :
      execStmt (fuel + 1) lexerProgram (unaryCalleeState state byte)
        (returnBool body) =
        .done (.returned (some (.boolean result)))
          (unaryCalleeState state byte) := by
    rw [Lanius.Semantics.execStmt.eq_def]
    simp only [returnBool]
    rw [bodyResult]
  cases fuel with
  | zero => omega
  | succ remaining =>
      rw [evalExpr, arguments]
      simp only
      rw [functionFound]
      simp only
      rw [boundParameters, functionBody]
      simp only
      rw [callee, bodyExec]
      rfl

theorem isWhitespaceCall_executes
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    evalExpr 10 lexerProgram state
      (.call isWhitespaceFunction.id [i32Literal byte.val]) =
      .done (.boolean (isWhitespace byte)) (unaryCallState state byte) := by
  have bodyBase := whitespaceExpr_executes lexerProgram state wellFormed byte
  have bodyTerminal : Lanius.Fuel.Terminal
      (evalExpr 6 lexerProgram (unaryCalleeState state byte) whitespaceExpr) := by
    rw [bodyBase]
    trivial
  have body := (Lanius.Fuel.evalExpr_more_fuel
    (extra := 2) bodyTerminal).trans bodyBase
  exact unaryBooleanFunctionCall_executes isWhitespaceFunction whitespaceExpr
    (isWhitespace byte) state byte lexerProgram_finds_isWhitespaceFunction
    rfl rfl body

theorem isWhitespaceCall_extends
    (state : State) (byte : Byte) :
    FrameExtension state (unaryCallState state byte) :=
  unaryCallState_extends state byte

theorem isWhitespaceCall_preserves_well_formed
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    StateWellFormed (unaryCallState state byte) :=
  unaryCallState_well_formed state wellFormed byte

def byteEqualsAnyValue (byte : Byte) : List Int → Bool
  | [] => false
  | first :: rest =>
      rest.foldl
        (fun accepted value => accepted || (Int.ofNat byte.val == value))
        (Int.ofNat byte.val == first)

theorem byteEqualsAnyFold_executes
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte)
    (values : List Int) (accumulator : Expr) (accumulatorValue : Bool)
    (fuel : Nat) (enough : 3 ≤ fuel)
    (accumulatorResult :
      evalExpr fuel lexerProgram (unaryCalleeState state byte) accumulator =
        .done (.boolean accumulatorValue) (unaryCalleeState state byte)) :
    evalExpr (fuel + values.length) lexerProgram (unaryCalleeState state byte)
      (values.foldl
        (fun expression value => orExpr expression (compareByte .equal value))
        accumulator) =
      .done
        (.boolean (values.foldl
          (fun accepted value =>
            accepted || (Int.ofNat byte.val == value)) accumulatorValue))
        (unaryCalleeState state byte) := by
  induction values generalizing fuel accumulator accumulatorValue with
  | nil => simpa
  | cons value rest inductionHypothesis =>
      have comparisonBase := compareByteEqual_executes lexerProgram
        state wellFormed byte value
      have comparison := evalExpr_done_at_larger_fuel (program := lexerProgram)
        enough comparisonBase
      have combined := orExpr_executes accumulatorResult comparison
      have restResult := inductionHypothesis
        (orExpr accumulator (compareByte .equal value))
        (accumulatorValue || (Int.ofNat byte.val == value)) (fuel + 1)
        (by omega) combined
      simpa [Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using restResult

theorem byteEqualsAny_executes
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte)
    (values : List Int) :
    evalExpr (values.length + 2) lexerProgram (unaryCalleeState state byte)
      (byteEqualsAny values) =
      .done (.boolean (byteEqualsAnyValue byte values))
        (unaryCalleeState state byte) := by
  cases values with
  | nil => rfl
  | cons first rest =>
      have firstResult := compareByteEqual_executes lexerProgram state
        wellFormed byte first
      have result := byteEqualsAnyFold_executes state wellFormed byte rest
        (compareByte .equal first) (Int.ofNat byte.val == first) 3
        (by decide) firstResult
      simpa [byteEqualsAny, byteEqualsAnyValue, Nat.add_assoc,
        Nat.add_comm, Nat.add_left_comm] using result

def scanEndValue : ScanEnd → Value
  | .success endOffset =>
      .structure scanEndDeclaration.id
        [.boolean true, .signed .i32 endOffset, .signed .i32 0]
  | .failure errorOffset =>
      .structure scanEndDeclaration.id
        [.boolean false, .signed .i32 0, .signed .i32 errorOffset]

theorem successfulScanBody_executes
    (state : State) (wellFormed : StateWellFormed state) (offset : Nat) :
    execStmt 7 lexerProgram
      (singleArgumentCalleeState state (.signed .i32 offset))
      (.returnValue (some (.structValue scanEndDeclaration.id
        [.value (.boolean true), .local 0, i32Literal 0]))) =
      .done (.returned (some (scanEndValue (.success offset))))
        (singleArgumentCalleeState state (.signed .i32 offset)) := by
  let callee := singleArgumentCalleeState state (.signed .i32 offset)
  have localFound := singleArgumentCalleeState_local state wellFormed
    (.signed .i32 offset)
  have localResult := evalLocal_of_local 2 lexerProgram callee 0
    (.signed .i32 offset) localFound
  have firstResult : evalExpr 4 lexerProgram callee (.value (.boolean true)) =
      .done (.boolean true) callee := by rfl
  have fieldsResult :
      evalExprs 5 lexerProgram callee
        [.value (.boolean true), .local 0, i32Literal 0] =
      .done [.boolean true, .signed .i32 offset, .signed .i32 0] callee := by
    rw [Lanius.Semantics.evalExprs.eq_3, firstResult]
    simp only
    rw [Lanius.Semantics.evalExprs.eq_3, localResult]
    rfl
  rw [Lanius.Semantics.execStmt.eq_def]
  simp only
  rw [evalExpr]
  rw [fieldsResult]
  rfl

theorem failedScanBody_executes
    (state : State) (wellFormed : StateWellFormed state) (offset : Nat) :
    execStmt 7 lexerProgram
      (singleArgumentCalleeState state (.signed .i32 offset))
      (.returnValue (some (.structValue scanEndDeclaration.id
        [.value (.boolean false), i32Literal 0, .local 0]))) =
      .done (.returned (some (scanEndValue (.failure offset))))
        (singleArgumentCalleeState state (.signed .i32 offset)) := by
  let callee := singleArgumentCalleeState state (.signed .i32 offset)
  have localFound := singleArgumentCalleeState_local state wellFormed
    (.signed .i32 offset)
  have localResult := evalLocal_of_local 1 lexerProgram callee 0
    (.signed .i32 offset) localFound
  have firstResult : evalExpr 4 lexerProgram callee (.value (.boolean false)) =
      .done (.boolean false) callee := by rfl
  have secondResult : evalExpr 3 lexerProgram callee (i32Literal 0) =
      .done (.signed .i32 0) callee := by rfl
  have fieldsResult :
      evalExprs 5 lexerProgram callee
        [.value (.boolean false), i32Literal 0, .local 0] =
      .done [.boolean false, .signed .i32 0, .signed .i32 offset] callee := by
    rw [Lanius.Semantics.evalExprs.eq_3, firstResult]
    simp only
    rw [Lanius.Semantics.evalExprs.eq_3, secondResult]
    simp only
    rw [Lanius.Semantics.evalExprs.eq_3, localResult]
    simp only
    rw [Lanius.Semantics.evalExprs.eq_2]
  rw [Lanius.Semantics.execStmt.eq_def]
  simp only
  rw [evalExpr]
  rw [fieldsResult]
  rfl

theorem successfulScanCall_after_argument
    (state : State) (wellFormed : StateWellFormed state)
    (argument : Expr) (offset : Nat)
    (argumentResult : evalExpr 6 lexerProgram state argument =
      .done (.signed .i32 offset) state) :
    evalExpr 8 lexerProgram state
      (callScanConstructor successfulScanFunction argument) =
      .done (scanEndValue (.success offset))
        (singleArgumentCallState state (.signed .i32 offset)) := by
  simpa [singleArgumentCallState, callScanConstructor] using
    singleArgumentFunctionCall_executes 6 (by decide)
      successfulScanFunction i32Type
      (.returnValue (some (.structValue scanEndDeclaration.id
        [.value (.boolean true), .local 0, i32Literal 0])))
      state argument (.signed .i32 offset) (scanEndValue (.success offset))
      (singleArgumentCalleeState state (.signed .i32 offset))
      (by rfl) rfl rfl argumentResult
      (successfulScanBody_executes state wellFormed offset)

theorem failedScanCall_after_argument
    (state : State) (wellFormed : StateWellFormed state)
    (argument : Expr) (offset : Nat)
    (argumentResult : evalExpr 6 lexerProgram state argument =
      .done (.signed .i32 offset) state) :
    evalExpr 8 lexerProgram state
      (callScanConstructor failedScanFunction argument) =
      .done (scanEndValue (.failure offset))
        (singleArgumentCallState state (.signed .i32 offset)) := by
  simpa [singleArgumentCallState, callScanConstructor] using
    singleArgumentFunctionCall_executes 6 (by decide)
      failedScanFunction i32Type
      (.returnValue (some (.structValue scanEndDeclaration.id
        [.value (.boolean false), i32Literal 0, .local 0])))
      state argument (.signed .i32 offset) (scanEndValue (.failure offset))
      (singleArgumentCalleeState state (.signed .i32 offset))
      (by rfl) rfl rfl argumentResult
      (failedScanBody_executes state wellFormed offset)

theorem byteInClosedRangeExpr_executes
    (program : Program)
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte)
    (lower upper : Nat) :
    evalExpr 4 program (unaryCalleeState state byte)
      (byteInClosedRange lower upper) =
      .done
        (.boolean
          (decide (Int.ofNat byte.val ≥ Int.ofNat lower) &&
            decide (Int.ofNat byte.val ≤ Int.ofNat upper)))
        (unaryCalleeState state byte) := by
  have lowerResult := compareByteGreaterEqual_executes program
    state wellFormed byte (Int.ofNat lower)
  have upperResult := compareByteLessEqual_executes program
    state wellFormed byte (Int.ofNat upper)
  simpa [byteInClosedRange] using
    andExpr_executes (state := unaryCalleeState state byte)
      lowerResult upperResult

theorem decimalDigitExpr_executes
    (program : Program)
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    evalExpr 4 program (unaryCalleeState state byte) decimalDigitExpr =
      .done (.boolean (isDecimalDigit byte))
        (unaryCalleeState state byte) := by
  have result := byteInClosedRangeExpr_executes program state wellFormed byte
    48 57
  have classification :
      (decide (Int.ofNat byte.val ≥ Int.ofNat 48) &&
        decide (Int.ofNat byte.val ≤ Int.ofNat 57)) =
        isDecimalDigit byte := by
    unfold isDecimalDigit
    rw [intOfNat_le_decide 48 byte.val, intOfNat_le_decide byte.val 57]
  rw [classification] at result
  simpa [decimalDigitExpr] using result

theorem identifierStartExpr_executes
    (program : Program)
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    evalExpr 6 program (unaryCalleeState state byte) identifierStartExpr =
      .done (.boolean (isIdentifierStart byte))
        (unaryCalleeState state byte) := by
  let callee := unaryCalleeState state byte
  have lowercase := byteInClosedRangeExpr_executes program state wellFormed byte
    97 122
  have uppercase := byteInClosedRangeExpr_executes program state wellFormed byte
    65 90
  have letter := orExpr_executes (state := callee) lowercase uppercase
  have underscoreBase := compareByteEqual_executes program state
    wellFormed byte 95
  have underscore := evalExpr_done_at_larger_fuel (program := program)
    (state := callee) (expression := compareByte .equal 95)
    (value := .boolean (Int.ofNat byte.val == (95 : Int)))
    (finalState := callee) (by decide : 3 ≤ 5) underscoreBase
  have result := orExpr_executes (state := callee) letter underscore
  have lowercaseEq :
      (decide (Int.ofNat byte.val ≥ Int.ofNat 97) &&
        decide (Int.ofNat byte.val ≤ Int.ofNat 122)) =
      (97 ≤ byte.val && byte.val ≤ 122) := by
    rw [intOfNat_le_decide 97 byte.val,
      intOfNat_le_decide byte.val 122]
  have uppercaseEq :
      (decide (Int.ofNat byte.val ≥ Int.ofNat 65) &&
        decide (Int.ofNat byte.val ≤ Int.ofNat 90)) =
      (65 ≤ byte.val && byte.val ≤ 90) := by
    rw [intOfNat_le_decide 65 byte.val,
      intOfNat_le_decide byte.val 90]
  have underscoreEq :
      (Int.ofNat byte.val == (95 : Int)) = (byte.val == 95) := by
    change (Int.ofNat byte.val == Int.ofNat 95) = (byte.val == 95)
    exact intOfNat_beq byte.val 95
  rw [lowercaseEq, uppercaseEq, underscoreEq] at result
  simpa [identifierStartExpr, isIdentifierStart, callee] using result

theorem symbolStartValue_eq : ∀ byte : Byte,
    byteEqualsAnyValue byte
      [40, 41, 43, 42, 61, 45, 47, 33, 91, 93, 123, 125,
       60, 62, 38, 124, 37, 94, 126, 44, 59, 58, 63, 46] =
      isSymbolStart byte := by
  native_decide

theorem symbolStartExpr_executes
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    evalExpr 26 lexerProgram (unaryCalleeState state byte) symbolStartExpr =
      .done (.boolean (isSymbolStart byte))
        (unaryCalleeState state byte) := by
  have result := byteEqualsAny_executes state wellFormed byte
    [40, 41, 43, 42, 61, 45, 47, 33, 91, 93, 123, 125,
     60, 62, 38, 124, 37, 94, 126, 44, 59, 58, 63, 46]
  rw [symbolStartValue_eq byte] at result
  simpa [symbolStartExpr] using result

theorem lexerProgram_finds_isIdentifierStartFunction :
    lexerProgram.function? isIdentifierStartFunction.id =
      some isIdentifierStartFunction := by
  rfl

theorem lexerProgram_finds_isDecimalDigitFunction :
    lexerProgram.function? isDecimalDigitFunction.id =
      some isDecimalDigitFunction := by
  rfl

theorem lexerProgram_finds_isSymbolStartFunction :
    lexerProgram.function? isSymbolStartFunction.id =
      some isSymbolStartFunction := by
  rfl

theorem isSymbolStartCall_executes
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    evalExpr 28 lexerProgram state
      (.call isSymbolStartFunction.id [i32Literal byte.val]) =
      .done (.boolean (isSymbolStart byte)) (unaryCallState state byte) := by
  exact unaryBooleanFunctionCallAtFuel_executes 26 (by decide)
    isSymbolStartFunction symbolStartExpr (isSymbolStart byte) state byte
    lexerProgram_finds_isSymbolStartFunction rfl rfl
    (symbolStartExpr_executes state wellFormed byte)

theorem unaryBooleanFunctionCallAfterArgument_executes
    (function : Function) (body : Expr) (result : Bool)
    (state : State) (argument : Expr) (byte : Byte)
    (functionFound : lexerProgram.function? function.id = some function)
    (parameters : function.parameters = [(0, i32Type)])
    (functionBody : function.body = some (returnBool body))
    (argumentResult : evalExpr 10 lexerProgram state argument =
      .done (.signed .i32 byte.val) state)
    (bodyResult : evalExpr 10 lexerProgram (unaryCalleeState state byte) body =
      .done (.boolean result) (unaryCalleeState state byte)) :
    evalExpr 12 lexerProgram state (.call function.id [argument]) =
      .done (.boolean result) (unaryCallState state byte) := by
  have arguments :
      evalExprs 11 lexerProgram state [argument] =
        .done [.signed .i32 byte.val] state := by
    rw [Lanius.Semantics.evalExprs.eq_def]
    simp only
    rw [argumentResult]
    rfl
  have boundParameters :
      bindParameters function.parameters [.signed .i32 byte.val] =
        some [(0, .signed .i32 byte.val)] := by
    rw [parameters]
    rfl
  have callee :
      ({ state with locals := [] }).bindLocals
        [(0, .signed .i32 byte.val)] = unaryCalleeState state byte := by
    rfl
  have bodyExec :
      execStmt 11 lexerProgram (unaryCalleeState state byte)
        (returnBool body) =
        .done (.returned (some (.boolean result)))
          (unaryCalleeState state byte) := by
    rw [Lanius.Semantics.execStmt.eq_def]
    simp only [returnBool]
    rw [bodyResult]
  rw [evalExpr, arguments]
  simp only
  rw [functionFound]
  simp only
  rw [boundParameters, functionBody]
  simp only
  rw [callee, bodyExec]
  rfl

theorem isIdentifierStartCall_after_argument
    (state : State) (wellFormed : StateWellFormed state)
    (argument : Expr) (byte : Byte)
    (argumentResult : evalExpr 10 lexerProgram state argument =
      .done (.signed .i32 byte.val) state) :
    evalExpr 12 lexerProgram state
      (.call isIdentifierStartFunction.id [argument]) =
      .done (.boolean (isIdentifierStart byte)) (unaryCallState state byte) := by
  have bodyBase := identifierStartExpr_executes lexerProgram state wellFormed byte
  have body := evalExpr_done_at_larger_fuel (program := lexerProgram)
    (state := unaryCalleeState state byte) (expression := identifierStartExpr)
    (value := .boolean (isIdentifierStart byte))
    (finalState := unaryCalleeState state byte)
    (by decide : 6 ≤ 10) bodyBase
  exact unaryBooleanFunctionCallAfterArgument_executes
    isIdentifierStartFunction identifierStartExpr (isIdentifierStart byte)
    state argument byte lexerProgram_finds_isIdentifierStartFunction
    rfl rfl argumentResult body

theorem isDecimalDigitCall_after_argument
    (state : State) (wellFormed : StateWellFormed state)
    (argument : Expr) (byte : Byte)
    (argumentResult : evalExpr 10 lexerProgram state argument =
      .done (.signed .i32 byte.val) state) :
    evalExpr 12 lexerProgram state
      (.call isDecimalDigitFunction.id [argument]) =
      .done (.boolean (isDecimalDigit byte)) (unaryCallState state byte) := by
  have bodyBase := decimalDigitExpr_executes lexerProgram state wellFormed byte
  have body := evalExpr_done_at_larger_fuel (program := lexerProgram)
    (state := unaryCalleeState state byte) (expression := decimalDigitExpr)
    (value := .boolean (isDecimalDigit byte))
    (finalState := unaryCalleeState state byte)
    (by decide : 4 ≤ 10) bodyBase
  exact unaryBooleanFunctionCallAfterArgument_executes
    isDecimalDigitFunction decimalDigitExpr (isDecimalDigit byte)
    state argument byte lexerProgram_finds_isDecimalDigitFunction
    rfl rfl argumentResult body

def identifierContinueAfterStartState (state : State) (byte : Byte) : State :=
  unaryCallState (unaryCalleeState state byte) byte

def identifierContinueBodyState (state : State) (byte : Byte) : State :=
  let afterStart := identifierContinueAfterStartState state byte
  if isIdentifierStart byte then afterStart else unaryCallState afterStart byte

theorem identifierContinueExpr_executes
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    evalExpr 13 lexerProgram (unaryCalleeState state byte)
      identifierContinueExpr =
      .done (.boolean (isIdentifierContinue byte))
        (identifierContinueBodyState state byte) := by
  let outer := unaryCalleeState state byte
  have outerWellFormed := bindLocal_preserves_well_formed
    (clearLocals state) 0 (.signed .i32 byte.val)
    (clearLocals_well_formed state wellFormed)
  have outerLocal := unaryCalleeState_local state wellFormed byte
  have outerArgument := evalLocal_of_local 9 lexerProgram outer 0
    (.signed .i32 byte.val) outerLocal
  have firstCall := isIdentifierStartCall_after_argument outer outerWellFormed
    byteLocal byte outerArgument
  let afterStart := identifierContinueAfterStartState state byte
  have afterStartWellFormed : StateWellFormed afterStart := by
    exact unaryCallState_well_formed outer outerWellFormed byte
  have afterStartLocal : afterStart.local? 0 = some (.signed .i32 byte.val) := by
    exact (unaryCallState_extends outer byte).preserves_local
      outerWellFormed outerLocal
  have afterStartArgument := evalLocal_of_local 9 lexerProgram afterStart 0
    (.signed .i32 byte.val) afterStartLocal
  have secondCall := isDecimalDigitCall_after_argument afterStart
    afterStartWellFormed byteLocal byte afterStartArgument
  have secondCallExpanded :
      evalExpr 12 lexerProgram (unaryCallState outer byte)
        (.call isDecimalDigitFunction.id [byteLocal]) =
        .done (.boolean (isDecimalDigit byte))
          (unaryCallState (unaryCallState outer byte) byte) := by
    simpa [afterStart, identifierContinueAfterStartState, outer] using secondCall
  change evalExpr 13 lexerProgram outer
    (orExpr
      (.call isIdentifierStartFunction.id [byteLocal])
      (.call isDecimalDigitFunction.id [byteLocal])) = _
  simp only [orExpr]
  rw [evalExpr, firstCall]
  by_cases starts : isIdentifierStart byte = true
  · simp [starts, identifierContinueBodyState,
      identifierContinueAfterStartState, outer,
      isIdentifierContinue]
  · have doesNotStart : isIdentifierStart byte = false :=
      Bool.eq_false_iff.mpr starts
    simp only [doesNotStart]
    rw [secondCallExpanded]
    simp [doesNotStart, identifierContinueBodyState,
      identifierContinueAfterStartState, outer,
      isIdentifierContinue]

theorem identifierContinueBodyState_store_extends
    (state : State) (byte : Byte) :
    StoreExtension state (identifierContinueBodyState state byte) := by
  let outer := unaryCalleeState state byte
  let afterStart := identifierContinueAfterStartState state byte
  have throughOuter := unaryCalleeState_store_extends state byte
  have throughStart : StoreExtension state afterStart := by
    exact throughOuter.trans (unaryCallState_extends outer byte).store
  by_cases starts : isIdentifierStart byte = true
  · simpa [identifierContinueBodyState, starts, afterStart] using throughStart
  · have doesNotStart : isIdentifierStart byte = false :=
      Bool.eq_false_iff.mpr starts
    have throughDigit := throughStart.trans
      (unaryCallState_extends afterStart byte).store
    simpa [identifierContinueBodyState, doesNotStart, afterStart] using throughDigit

theorem identifierContinueBodyState_well_formed
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    StateWellFormed (identifierContinueBodyState state byte) := by
  let outer := unaryCalleeState state byte
  have outerWellFormed : StateWellFormed outer :=
    bindLocal_preserves_well_formed (clearLocals state) 0
      (.signed .i32 byte.val) (clearLocals_well_formed state wellFormed)
  let afterStart := identifierContinueAfterStartState state byte
  have afterStartWellFormed : StateWellFormed afterStart :=
    unaryCallState_well_formed outer outerWellFormed byte
  by_cases starts : isIdentifierStart byte = true
  · simpa [identifierContinueBodyState, starts, afterStart] using
      afterStartWellFormed
  · have doesNotStart : isIdentifierStart byte = false :=
      Bool.eq_false_iff.mpr starts
    have afterDigitWellFormed := unaryCallState_well_formed
      afterStart afterStartWellFormed byte
    simpa [identifierContinueBodyState, doesNotStart, afterStart] using
      afterDigitWellFormed

def identifierContinueCallState (state : State) (byte : Byte) : State :=
  restoreLocals state (identifierContinueBodyState state byte)

theorem identifierContinueCallState_extends
    (state : State) (byte : Byte) :
    FrameExtension state (identifierContinueCallState state byte) := by
  exact (identifierContinueBodyState_store_extends state byte).restoreLocals

theorem identifierContinueCallState_well_formed
    (state : State) (wellFormed : StateWellFormed state) (byte : Byte) :
    StateWellFormed (identifierContinueCallState state byte) := by
  exact (identifierContinueBodyState_store_extends state byte)
    |>.restoreLocals_well_formed wellFormed
      (identifierContinueBodyState_well_formed state wellFormed byte)

theorem unaryBooleanFunctionCallWithBodyState_executes
    (program : Program)
    (function : Function) (body : Expr) (result : Bool)
    (state : State) (argument : Expr) (byte : Byte) (bodyFinal : State)
    (functionFound : program.function? function.id = some function)
    (parameters : function.parameters = [(0, i32Type)])
    (functionBody : function.body = some (returnBool body))
    (argumentResult : evalExpr 13 program state argument =
      .done (.signed .i32 byte.val) state)
    (bodyResult : evalExpr 13 program (unaryCalleeState state byte) body =
      .done (.boolean result) bodyFinal) :
    evalExpr 15 program state (.call function.id [argument]) =
      .done (.boolean result) (restoreLocals state bodyFinal) := by
  have arguments :
      evalExprs 14 program state [argument] =
        .done [.signed .i32 byte.val] state := by
    rw [Lanius.Semantics.evalExprs.eq_def]
    simp only
    rw [argumentResult]
    rfl
  have boundParameters :
      bindParameters function.parameters [.signed .i32 byte.val] =
        some [(0, .signed .i32 byte.val)] := by
    rw [parameters]
    rfl
  have callee :
      ({ state with locals := [] }).bindLocals
        [(0, .signed .i32 byte.val)] = unaryCalleeState state byte := by
    rfl
  have bodyExec :
      execStmt 14 program (unaryCalleeState state byte)
        (returnBool body) =
        .done (.returned (some (.boolean result))) bodyFinal := by
    rw [Lanius.Semantics.execStmt.eq_def]
    simp only [returnBool]
    rw [bodyResult]
  rw [evalExpr, arguments]
  simp only
  rw [functionFound]
  simp only
  rw [boundParameters, functionBody]
  simp only
  rw [callee, bodyExec]

theorem lexerProgram_finds_isIdentifierContinueFunction :
    lexerProgram.function? isIdentifierContinueFunction.id =
      some isIdentifierContinueFunction := by
  rfl

theorem isIdentifierContinueCall_after_argument
    (state : State) (wellFormed : StateWellFormed state)
    (argument : Expr) (byte : Byte)
    (argumentResult : evalExpr 13 lexerProgram state argument =
      .done (.signed .i32 byte.val) state) :
    evalExpr 15 lexerProgram state
      (.call isIdentifierContinueFunction.id [argument]) =
      .done (.boolean (isIdentifierContinue byte))
        (identifierContinueCallState state byte) := by
  simpa [identifierContinueCallState] using
    unaryBooleanFunctionCallWithBodyState_executes
      lexerProgram isIdentifierContinueFunction identifierContinueExpr
      (isIdentifierContinue byte) state argument byte
      (identifierContinueBodyState state byte)
      lexerProgram_finds_isIdentifierContinueFunction rfl rfl argumentResult
      (identifierContinueExpr_executes state wellFormed byte)

theorem isWhitespaceCall_after_argument13
    (state : State) (wellFormed : StateWellFormed state)
    (argument : Expr) (byte : Byte)
    (argumentResult : evalExpr 13 lexerProgram state argument =
      .done (.signed .i32 byte.val) state) :
    evalExpr 15 lexerProgram state
      (.call isWhitespaceFunction.id [argument]) =
      .done (.boolean (isWhitespace byte)) (unaryCallState state byte) := by
  have bodyBase := whitespaceExpr_executes lexerProgram state wellFormed byte
  have body := evalExpr_done_at_larger_fuel (program := lexerProgram)
    (state := unaryCalleeState state byte) (expression := whitespaceExpr)
    (value := .boolean (isWhitespace byte))
    (finalState := unaryCalleeState state byte)
    (by decide : 6 ≤ 13) bodyBase
  simpa [unaryCallState] using
    unaryBooleanFunctionCallWithBodyState_executes
      lexerProgram isWhitespaceFunction whitespaceExpr (isWhitespace byte)
      state argument
      byte (unaryCalleeState state byte)
      lexerProgram_finds_isWhitespaceFunction rfl rfl argumentResult body

/-- Everything the generic scanner loop needs to know about a represented
byte predicate. The predicate chooses its own post-call state; the scanner
only relies on preserved caller locals and a well-formed extended store. -/
structure ScannerPredicateSemantics
    (program : Program) (predicate : Function) (accept : Byte → Bool) where
  callState : State → Byte → State
  call_executes : ∀ state, StateWellFormed state → ∀ argument byte,
    evalExpr 13 program state argument =
      .done (.signed .i32 byte.val) state →
    evalExpr 15 program state (.call predicate.id [argument]) =
      .done (.boolean (accept byte)) (callState state byte)
  call_extends : ∀ state byte, FrameExtension state (callState state byte)
  call_well_formed : ∀ state, StateWellFormed state → ∀ byte,
    StateWellFormed (callState state byte)

def whitespacePredicateSemantics :
    ScannerPredicateSemantics lexerProgram isWhitespaceFunction isWhitespace where
  callState := unaryCallState
  call_executes := isWhitespaceCall_after_argument13
  call_extends := unaryCallState_extends
  call_well_formed := unaryCallState_well_formed

def identifierPredicateSemantics :
    ScannerPredicateSemantics lexerProgram isIdentifierContinueFunction
      isIdentifierContinue where
  callState := identifierContinueCallState
  call_executes := isIdentifierContinueCall_after_argument
  call_extends := identifierContinueCallState_extends
  call_well_formed := identifierContinueCallState_well_formed

def sourceValues (source : List Byte) : List Value :=
  source.map fun byte => .signed .i32 byte.val

/-- Runtime backing storage for a source slice passed to a represented lexer
function. Cell zero is deliberately not a local: the slice retains it as its
stable root while calls create and later restore their parameter locals. -/
def sourceState (source : List Byte) : State := {
  cells := [{ id := 0, value := some (.array (sourceValues source)) }]
  nextCell := 1
}

theorem sourceState_well_formed (source : List Byte) :
    StateWellFormed (sourceState source) := by
  constructor
  · exact empty_heap_well_formed
  · simp [CellIdsUnique, sourceState]
  · simp [CellIdsBelowNext, sourceState]
  · simp [LocalsReferenceCells, sourceState]

theorem evalI32LocalAddNat
    (state : State) (id : VarId) (value amount : Nat)
    (found : state.local? id = some (.signed .i32 value))
    (bounded : value + amount ≤ 2147483647) :
    evalExpr 4 lexerProgram state
      (.binary .add (.local id) (i32Literal amount)) =
      .done (.signed .i32 (value + amount)) state := by
  have leftResult := evalLocal_of_local 2 lexerProgram state id
    (.signed .i32 value) found
  have rightResult :
      evalExpr 3 lexerProgram state (i32Literal amount) =
        .done (.signed .i32 amount) state := by rfl
  have wrapped :
      wrapSigned lexerProgram.target .i32
          (Int.ofNat value + Int.ofNat amount) =
        Int.ofNat (value + amount) := by
    simpa using wrapSigned_i32_ofNat (value + amount) bounded
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [leftResult]
  simp only
  rw [rightResult]
  simp only [evalBinaryValue, beq_self_eq_true, if_true, evalSignedBinary]
  have wrappedCoerced :
      wrapSigned lexerProgram.target .i32
          ((value : Int) + (amount : Int)) =
        (value : Int) + (amount : Int) := by simpa using wrapped
  rw [wrappedCoerced]

theorem evalSourceIndexAt
    {program : Program}
    (state : State) (source : List Byte) (cursor : Nat)
    (cursorId : VarId)
    (inBounds : cursor < source.length)
    (sourceLocal : state.local? 0 =
      some (.slice i32Type 0 [] 0 source.length))
    (cursorLocal : state.local? cursorId = some (.signed .i32 cursor))
    (backing : state.cellEntry? 0 =
      some { id := 0, value := some (.array (sourceValues source)) }) :
    evalExpr 10 program state (.index (.local 0) (.local cursorId)) =
      .done (.signed .i32 (source.get ⟨cursor, inBounds⟩).val) state := by
  have sourceResult := evalLocal_of_local 8 program state 0
    (.slice i32Type 0 [] 0 source.length) sourceLocal
  have cursorResult := evalLocal_of_local 8 program state cursorId
    (.signed .i32 cursor) cursorLocal
  have sourceResult9 :
      evalExpr 9 program state (.local 0) =
        .done (.slice i32Type 0 [] 0 source.length) state := by
    simpa using sourceResult
  have cursorResult9 :
      evalExpr 9 program state (.local cursorId) =
        .done (.signed .i32 cursor) state := by
    simpa using cursorResult
  rw [evalExpr, sourceResult9]
  simp only
  rw [cursorResult9]
  simp only
  have indexResult : integerIndex (.signed .i32 cursor) = .ok cursor := by
    simp [integerIndex]
  rw [indexResult]
  simp only
  rw [if_pos inBounds]
  have sliceResult :
      sliceValues state 0 [] 0 source.length = .ok (sourceValues source) := by
    simp [sliceValues, readCellProjection, projectedValue, backing, sourceValues]
    rw [show source.length = (sourceValues source).length by
      simp [sourceValues]]
    exact List.take_length
  rw [sliceResult]
  simp only
  have valueAt :
      (sourceValues source)[cursor]? =
        some (.signed .i32 (source.get ⟨cursor, inBounds⟩).val) := by
    simp [sourceValues, inBounds]
  rw [valueAt]

theorem evalSourceIndex
    (state : State) (source : List Byte) (cursor : Nat)
    (inBounds : cursor < source.length)
    (sourceLocal : state.local? 0 =
      some (.slice i32Type 0 [] 0 source.length))
    (cursorLocal : state.local? 3 = some (.signed .i32 cursor))
    (backing : state.cellEntry? 0 =
      some { id := 0, value := some (.array (sourceValues source)) }) :
    evalExpr 10 lexerProgram state (.index (.local 0) (.local 3)) =
      .done (.signed .i32 (source.get ⟨cursor, inBounds⟩).val) state := by
  exact evalSourceIndexAt state source cursor 3 inBounds sourceLocal
    cursorLocal backing

theorem evalSourceIndexNotNewline
    (state : State) (source : List Byte) (cursor : Nat)
    (inBounds : cursor < source.length)
    (sourceLocal : state.local? 0 =
      some (.slice i32Type 0 [] 0 source.length))
    (cursorLocal : state.local? 3 = some (.signed .i32 cursor))
    (backing : state.cellEntry? 0 =
      some { id := 0, value := some (.array (sourceValues source)) }) :
    evalExpr 11 lexerProgram state
      (.binary .notEqual (.index (.local 0) (.local 3)) (i32Literal 10)) =
      .done (.boolean ((source.get ⟨cursor, inBounds⟩).val != 10)) state := by
  have indexed := evalSourceIndex state source cursor inBounds sourceLocal
    cursorLocal backing
  let byte := source.get ⟨cursor, inBounds⟩
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [indexed]
  simp only
  have literal : evalExpr 10 lexerProgram state (i32Literal 10) =
      .done (.signed .i32 10) state := by rfl
  rw [literal]
  simp only [evalBinaryValue, scalarEqual, beq_self_eq_true, if_true]
  have equality : (Int.ofNat byte.val == (10 : Int)) = (byte.val == 10) := by
    change (Int.ofNat byte.val == Int.ofNat 10) = _
    exact intOfNat_beq byte.val 10
  have equalitySource :
      (Int.ofNat (source.get ⟨cursor, inBounds⟩).val == (10 : Int)) =
        ((source.get ⟨cursor, inBounds⟩).val == 10) := by
    simpa [byte] using equality
  exact congrArg
    (fun result => (Outcome.done (Value.boolean (!result)) state : Outcome Value))
    equalitySource

theorem evalSourceIndexEqualNatLiteral
    (state : State) (source : List Byte) (cursor literal : Nat)
    (inBounds : cursor < source.length)
    (sourceLocal : state.local? 0 =
      some (.slice i32Type 0 [] 0 source.length))
    (cursorLocal : state.local? 3 = some (.signed .i32 cursor))
    (backing : state.cellEntry? 0 =
      some { id := 0, value := some (.array (sourceValues source)) }) :
    evalExpr 11 lexerProgram state
      (.binary .equal (.index (.local 0) (.local 3)) (i32Literal literal)) =
      .done (.boolean ((source.get ⟨cursor, inBounds⟩).val == literal)) state := by
  have indexed := evalSourceIndex state source cursor inBounds sourceLocal
    cursorLocal backing
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [indexed]
  simp only
  have literalResult : evalExpr 10 lexerProgram state (i32Literal literal) =
      .done (.signed .i32 literal) state := by rfl
  rw [literalResult]
  simp only [evalBinaryValue, scalarEqual, beq_self_eq_true, if_true]
  exact congrArg
    (fun result => (Outcome.done (Value.boolean result) state : Outcome Value))
    (intOfNat_beq (source.get ⟨cursor, inBounds⟩).val literal)

theorem evalSourceNextIndex
    (state : State) (source : List Byte) (cursor : Nat)
    (nextInBounds : cursor + 1 < source.length)
    (sourceBound : source.length ≤ 2147483647)
    (sourceLocal : state.local? 0 =
      some (.slice i32Type 0 [] 0 source.length))
    (cursorLocal : state.local? 3 = some (.signed .i32 cursor))
    (backing : state.cellEntry? 0 =
      some { id := 0, value := some (.array (sourceValues source)) }) :
    evalExpr 10 lexerProgram state
      (.index (.local 0) (.binary .add (.local 3) (i32Literal 1))) =
      .done (.signed .i32
        (source.get ⟨cursor + 1, nextInBounds⟩).val) state := by
  have sourceResult := evalLocal_of_local 8 lexerProgram state 0
    (.slice i32Type 0 [] 0 source.length) sourceLocal
  have sourceResult9 : evalExpr 9 lexerProgram state (.local 0) =
      .done (.slice i32Type 0 [] 0 source.length) state := by
    simpa using sourceResult
  have nextBound : cursor + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.le_of_lt nextInBounds) sourceBound
  have nextBase := evalI32LocalAddNat state 3 cursor 1 cursorLocal nextBound
  have nextResult := evalExpr_done_at_larger_fuel (program := lexerProgram)
    (by decide : 4 ≤ 9) nextBase
  have nextResult' :
      evalExpr 9 lexerProgram state
        (.binary .add (.local 3) (i32Literal 1)) =
        .done (.signed .i32 (cursor + 1)) state := by
    simpa using nextResult
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [sourceResult9]
  simp only
  rw [nextResult']
  simp only
  have integerResult : integerIndex (.signed .i32 (cursor + 1)) =
      .ok (cursor + 1) := by
    simp [integerIndex]
    omega
  rw [integerResult]
  simp only
  rw [if_pos nextInBounds]
  have sliceResult :
      sliceValues state 0 [] 0 source.length = .ok (sourceValues source) := by
    simp [sliceValues, readCellProjection, projectedValue, backing, sourceValues]
    rw [show source.length = (sourceValues source).length by
      simp [sourceValues]]
    exact List.take_length
  rw [sliceResult]
  simp only
  simp [sourceValues, nextInBounds]

theorem evalSourceNextIndexEqualNatLiteral
    (state : State) (source : List Byte) (cursor literal : Nat)
    (nextInBounds : cursor + 1 < source.length)
    (sourceBound : source.length ≤ 2147483647)
    (sourceLocal : state.local? 0 =
      some (.slice i32Type 0 [] 0 source.length))
    (cursorLocal : state.local? 3 = some (.signed .i32 cursor))
    (backing : state.cellEntry? 0 =
      some { id := 0, value := some (.array (sourceValues source)) }) :
    evalExpr 11 lexerProgram state
      (.binary .equal
        (.index (.local 0) (.binary .add (.local 3) (i32Literal 1)))
        (i32Literal literal)) =
      .done (.boolean
        ((source.get ⟨cursor + 1, nextInBounds⟩).val == literal)) state := by
  have indexed := evalSourceNextIndex state source cursor nextInBounds
    sourceBound sourceLocal cursorLocal backing
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [indexed]
  simp only
  have literalResult : evalExpr 10 lexerProgram state (i32Literal literal) =
      .done (.signed .i32 literal) state := by rfl
  rw [literalResult]
  simp only [evalBinaryValue, scalarEqual, beq_self_eq_true, if_true]
  exact congrArg
    (fun result => (Outcome.done (Value.boolean result) state : Outcome Value))
    (intOfNat_beq (source.get ⟨cursor + 1, nextInBounds⟩).val literal)

theorem evalLocalLessLocal
    {program : Program}
    (state : State) (cursor limit : Nat)
    (cursorId limitId : VarId)
    (cursorLocal : state.local? cursorId = some (.signed .i32 cursor))
    (limitLocal : state.local? limitId = some (.signed .i32 limit)) :
    evalExpr 13 program state
      (.binary .less (.local cursorId) (.local limitId)) =
      .done (.boolean (cursor < limit)) state := by
  have cursorResult := evalLocal_of_local 11 program state cursorId
    (.signed .i32 cursor) cursorLocal
  have limitResult := evalLocal_of_local 11 program state limitId
    (.signed .i32 limit) limitLocal
  have cursorResult12 :
      evalExpr 12 program state (.local cursorId) =
        .done (.signed .i32 cursor) state := by
    simpa using cursorResult
  have limitResult12 :
      evalExpr 12 program state (.local limitId) =
        .done (.signed .i32 limit) state := by
    simpa using limitResult
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [cursorResult12]
  simp only
  rw [limitResult12]
  simp only
  have operationResult :
      evalBinaryValue program.target .less
        (.signed .i32 cursor) (.signed .i32 limit) =
        .ok (.boolean (decide (Int.ofNat cursor < Int.ofNat limit))) := by
    rfl
  rw [operationResult]
  rw [intOfNat_lt_decide]

theorem evalCursorLessLimit
    (state : State) (cursor limit : Nat)
    (cursorLocal : state.local? 3 = some (.signed .i32 cursor))
    (limitLocal : state.local? 1 = some (.signed .i32 limit)) :
    evalExpr 13 lexerProgram state
      (.binary .less (.local 3) (.local 1)) =
      .done (.boolean (cursor < limit)) state :=
  evalLocalLessLocal state cursor limit 3 1 cursorLocal limitLocal

theorem evalCursorPlusOneLessLimit
    (state : State) (cursor limit : Nat)
    (bounded : cursor + 1 ≤ 2147483647)
    (cursorLocal : state.local? 3 = some (.signed .i32 cursor))
    (limitLocal : state.local? 1 = some (.signed .i32 limit)) :
    evalExpr 13 lexerProgram state
      (.binary .less
        (.binary .add (.local 3) (i32Literal 1)) (.local 1)) =
      .done (.boolean (cursor + 1 < limit)) state := by
  have cursorBase := evalI32LocalAddNat state 3 cursor 1 cursorLocal bounded
  have cursorResult := evalExpr_done_at_larger_fuel (program := lexerProgram)
    (by decide : 4 ≤ 12) cursorBase
  have cursorResult' :
      evalExpr 12 lexerProgram state
        (.binary .add (.local 3) (i32Literal 1)) =
        .done (.signed .i32 (cursor + 1)) state := by
    simpa using cursorResult
  have limitResult := evalLocal_of_local 11 lexerProgram state 1
    (.signed .i32 limit) limitLocal
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [cursorResult']
  simp only
  rw [limitResult]
  simp only
  change Outcome.done (Value.boolean (decide
    (Int.ofNat (cursor + 1) < Int.ofNat limit))) state = _
  rw [intOfNat_lt_decide]

/-- Stable cells established by the represented scanner's three parameters
and its cursor local. Predicate calls may append unreachable cells, but these
five cells retain their identities throughout the loop. -/
structure ScannerState
    (state : State) (source : List Byte) (start cursor : Nat) : Prop where
  wellFormed : StateWellFormed state
  nextCell : 5 ≤ state.nextCell
  sourceCell : state.cellEntry? 0 =
    some { id := 0, value := some (.array (sourceValues source)) }
  sourceLocalId : state.cellId? 0 = some 1
  sourceLocalCell : state.cellEntry? 1 =
    some { id := 1, value := some (.slice i32Type 0 [] 0 source.length) }
  limitLocalId : state.cellId? 1 = some 2
  limitLocalCell : state.cellEntry? 2 =
    some { id := 2, value := some (.signed .i32 source.length) }
  startLocalId : state.cellId? 2 = some 3
  startLocalCell : state.cellEntry? 3 =
    some { id := 3, value := some (.signed .i32 start) }
  cursorLocalId : state.cellId? 3 = some 4
  cursorLocalCell : state.cellEntry? 4 =
    some { id := 4, value := some (.signed .i32 cursor) }

theorem ScannerState.sourceLocal
    (invariant : ScannerState state source start cursor) :
    state.local? 0 = some (.slice i32Type 0 [] 0 source.length) := by
  simp [State.local?, State.cell?, invariant.sourceLocalId,
    invariant.sourceLocalCell]

theorem ScannerState.limitLocal
    (invariant : ScannerState state source start cursor) :
    state.local? 1 = some (.signed .i32 source.length) := by
  simp [State.local?, State.cell?, invariant.limitLocalId,
    invariant.limitLocalCell]

theorem ScannerState.startLocal
    (invariant : ScannerState state source start cursor) :
    state.local? 2 = some (.signed .i32 start) := by
  simp [State.local?, State.cell?, invariant.startLocalId,
    invariant.startLocalCell]

theorem ScannerState.cursorLocal
    (invariant : ScannerState state source start cursor) :
    state.local? 3 = some (.signed .i32 cursor) := by
  simp [State.local?, State.cell?, invariant.cursorLocalId,
    invariant.cursorLocalCell]

theorem ScannerState.evalBlockCommentClose_notStar
    (invariant : ScannerState state source start cursor)
    (inBounds : cursor < source.length)
    (notStar : (source.get ⟨cursor, inBounds⟩).val ≠ 42) :
    evalExpr 15 lexerProgram state blockCommentCloseCondition =
      .done (.boolean false) state := by
  have firstBase := evalSourceIndexEqualNatLiteral state source cursor 42
    inBounds invariant.sourceLocal invariant.cursorLocal invariant.sourceCell
  have firstBoolean :
      ((source.get ⟨cursor, inBounds⟩).val == 42) = false := by
    apply Bool.eq_false_iff.mpr
    intro equal
    apply notStar
    simpa using equal
  rw [firstBoolean] at firstBase
  have first := evalExpr_done_at_larger_fuel (program := lexerProgram)
    (by decide : 11 ≤ 14) firstBase
  simpa [blockCommentCloseCondition] using
    (andExpr_false_left (fuel := 14) (right := andExpr
      (.binary .less
        (.binary .add (.local 3) (i32Literal 1)) (.local 1))
      (.binary .equal
        (.index (.local 0)
          (.binary .add (.local 3) (i32Literal 1)))
        (i32Literal 47))) first)

theorem ScannerState.evalBlockCommentClose_noNext
    (invariant : ScannerState state source start cursor)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : cursor < source.length)
    (isStar : (source.get ⟨cursor, inBounds⟩).val = 42)
    (nextOutOfBounds : ¬ cursor + 1 < source.length) :
    evalExpr 15 lexerProgram state blockCommentCloseCondition =
      .done (.boolean false) state := by
  have firstBase := evalSourceIndexEqualNatLiteral state source cursor 42
    inBounds invariant.sourceLocal invariant.cursorLocal invariant.sourceCell
  have firstBoolean :
      ((source.get ⟨cursor, inBounds⟩).val == 42) = true := by
    rw [isStar]
    rfl
  rw [firstBoolean] at firstBase
  have first := evalExpr_done_at_larger_fuel (program := lexerProgram)
    (by decide : 11 ≤ 14) firstBase
  have nextBound : cursor + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound
  have withinBase := evalCursorPlusOneLessLimit state cursor source.length
    nextBound invariant.cursorLocal invariant.limitLocal
  have withinBoolean : decide (cursor + 1 < source.length) = false := by
    simp [nextOutOfBounds]
  rw [withinBoolean] at withinBase
  have inner := andExpr_false_left
    (fuel := 13)
    (right := .binary .equal
      (.index (.local 0) (.binary .add (.local 3) (i32Literal 1)))
      (i32Literal 47)) withinBase
  have combined := andExpr_executes first inner
  simpa [blockCommentCloseCondition] using combined

theorem ScannerState.evalBlockCommentClose_withNext
    (invariant : ScannerState state source start cursor)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : cursor < source.length)
    (nextInBounds : cursor + 1 < source.length)
    (isStar : (source.get ⟨cursor, inBounds⟩).val = 42) :
    evalExpr 15 lexerProgram state blockCommentCloseCondition =
      .done (.boolean
        ((source.get ⟨cursor + 1, nextInBounds⟩).val == 47)) state := by
  have firstBase := evalSourceIndexEqualNatLiteral state source cursor 42
    inBounds invariant.sourceLocal invariant.cursorLocal invariant.sourceCell
  have firstBoolean :
      ((source.get ⟨cursor, inBounds⟩).val == 42) = true := by
    rw [isStar]
    rfl
  rw [firstBoolean] at firstBase
  have first := evalExpr_done_at_larger_fuel (program := lexerProgram)
    (by decide : 11 ≤ 14) firstBase
  have nextBound : cursor + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.le_of_lt nextInBounds) sourceBound
  have withinBase := evalCursorPlusOneLessLimit state cursor source.length
    nextBound invariant.cursorLocal invariant.limitLocal
  have withinBoolean : decide (cursor + 1 < source.length) = true := by
    simp [nextInBounds]
  rw [withinBoolean] at withinBase
  have slashBase := evalSourceNextIndexEqualNatLiteral state source cursor 47
    nextInBounds sourceBound invariant.sourceLocal invariant.cursorLocal
    invariant.sourceCell
  have slash := evalExpr_done_at_larger_fuel (program := lexerProgram)
    (by decide : 11 ≤ 13) slashBase
  have inner := andExpr_executes withinBase slash
  have combined := andExpr_executes first inner
  simpa [blockCommentCloseCondition] using combined

theorem ScannerState.afterPredicateCall
    (invariant : ScannerState state source start cursor)
    (extension : FrameExtension state after)
    (afterWellFormed : StateWellFormed after) :
    ScannerState after source start cursor := by
  have cell0Old : 0 < state.nextCell :=
    Nat.lt_of_lt_of_le (by decide) invariant.nextCell
  have cell1Old : 1 < state.nextCell :=
    Nat.lt_of_lt_of_le (by decide) invariant.nextCell
  have cell2Old : 2 < state.nextCell :=
    Nat.lt_of_lt_of_le (by decide) invariant.nextCell
  have cell3Old : 3 < state.nextCell :=
    Nat.lt_of_lt_of_le (by decide) invariant.nextCell
  have cell4Old : 4 < state.nextCell :=
    Nat.lt_of_lt_of_le (by decide) invariant.nextCell
  constructor
  · exact afterWellFormed
  · exact Nat.le_trans invariant.nextCell extension.nextCell
  · exact extension.oldCells 0 cell0Old |>.trans invariant.sourceCell
  · unfold State.cellId?
    rw [extension.locals]
    exact invariant.sourceLocalId
  · exact extension.oldCells 1 cell1Old |>.trans invariant.sourceLocalCell
  · unfold State.cellId?
    rw [extension.locals]
    exact invariant.limitLocalId
  · exact extension.oldCells 2 cell2Old |>.trans invariant.limitLocalCell
  · unfold State.cellId?
    rw [extension.locals]
    exact invariant.startLocalId
  · exact extension.oldCells 3 cell3Old |>.trans invariant.startLocalCell
  · unfold State.cellId?
    rw [extension.locals]
    exact invariant.cursorLocalId
  · exact extension.oldCells 4 cell4Old |>.trans invariant.cursorLocalCell

def incrementedCursorState (state : State) (cursor : Nat) : State :=
  { state with
    cells := replaceCell state.cells 4 (.signed .i32 (cursor + 1)) }

theorem ScannerState.assignCursor
    (invariant : ScannerState state source start cursor) :
    state.assignCell 4 (.signed .i32 (cursor + 1)) =
      some (incrementedCursorState state cursor) := by
  simp [State.assignCell, invariant.cursorLocalCell, incrementedCursorState]

theorem ScannerState.afterCursorAssignment
    (invariant : ScannerState state source start cursor) :
    ScannerState (incrementedCursorState state cursor)
      source start (cursor + 1) := by
  let next := incrementedCursorState state cursor
  have assigned : state.assignCell 4 (.signed .i32 (cursor + 1)) = some next :=
    invariant.assignCursor
  constructor
  · exact assignCell_preserves_well_formed invariant.wellFormed assigned
  · simpa [incrementedCursorState] using invariant.nextCell
  · exact (assignCell_preserves_other assigned (by decide : 0 ≠ 4)).trans
      invariant.sourceCell
  · simpa [incrementedCursorState, State.cellId?] using
      invariant.sourceLocalId
  · exact (assignCell_preserves_other assigned (by decide : 1 ≠ 4)).trans
      invariant.sourceLocalCell
  · simpa [incrementedCursorState, State.cellId?] using
      invariant.limitLocalId
  · exact (assignCell_preserves_other assigned (by decide : 2 ≠ 4)).trans
      invariant.limitLocalCell
  · simpa [incrementedCursorState, State.cellId?] using
      invariant.startLocalId
  · exact (assignCell_preserves_other assigned (by decide : 3 ≠ 4)).trans
      invariant.startLocalCell
  · simpa [incrementedCursorState, State.cellId?] using
      invariant.cursorLocalId
  · exact assignCell_finds_assigned assigned

/-- Reconstruct the scanner invariant after a separation-framed command that
    may update only the cursor cell.  FunctionalView loop proofs use this once
    at loop exit instead of re-proving preservation of every scanner local on
    every iteration. -/
theorem ScannerState.afterCursorEffect
    (nextCursor : Nat)
    (invariant : ScannerState before source start cursor)
    (afterWellFormed : StateWellFormed after)
    (effect : Lanius.Separation.ModifiesOnly
      (Lanius.Separation.CellSet.singleton 4) before after)
    (cursorCell : after.cellEntry? 4 = some {
      id := 4, value := some (.signed .i32 (Int.ofNat nextCursor)) }) :
    ScannerState after source start nextCursor := by
  constructor
  · exact afterWellFormed
  · exact Nat.le_trans invariant.nextCell effect.nextCell
  · exact effect.preserves_entry invariant.wellFormed invariant.sourceCell
      (by simp [Lanius.Separation.CellSet.singleton])
  · exact (effect.preserves_cellId 0).trans invariant.sourceLocalId
  · exact effect.preserves_entry invariant.wellFormed invariant.sourceLocalCell
      (by simp [Lanius.Separation.CellSet.singleton])
  · exact (effect.preserves_cellId 1).trans invariant.limitLocalId
  · exact effect.preserves_entry invariant.wellFormed invariant.limitLocalCell
      (by simp [Lanius.Separation.CellSet.singleton])
  · exact (effect.preserves_cellId 2).trans invariant.startLocalId
  · exact effect.preserves_entry invariant.wellFormed invariant.startLocalCell
      (by simp [Lanius.Separation.CellSet.singleton])
  · exact (effect.preserves_cellId 3).trans invariant.cursorLocalId
  · exact cursorCell

theorem ScannerState.execCursorIncrement
    (invariant : ScannerState state source start cursor)
    (program : Program)
    (bounded : cursor + 1 ≤ 2147483647) :
    execStmt 11 program state
      (.expression (.assign .add (.local 3) (i32Literal 1))) =
      .done .next (incrementedCursorState state cursor) := by
  let next := incrementedCursorState state cursor
  have assigned : state.assignCell 4 (.signed .i32 (cursor + 1)) = some next :=
    invariant.assignCursor
  have placeResult :
      evalPlace 9 program state (.local 3) =
        .done { root := 4, projections := [], value := some (.signed .i32 cursor) }
          state := by
    rw [Lanius.Semantics.evalPlace.eq_def]
    simp only
    rw [invariant.cursorLocalId]
    simp only
    rw [invariant.cursorLocalCell]
  have rightResult :
      evalExpr 9 program state (i32Literal 1) =
        .done (.signed .i32 1) state := by
    rfl
  have wrapped :
      wrapSigned program.target .i32 (Int.ofNat cursor + 1) =
        Int.ofNat (cursor + 1) := by
    simpa using wrapSigned_i32_ofNat_at_target program.target (cursor + 1) bounded
  have arithmeticResult :
      evalAssignValue program.target .add
        (some (.signed .i32 cursor)) (.signed .i32 1) =
        .ok (.signed .i32 (cursor + 1)) := by
    simp only [evalAssignValue, assignOpBinary?, evalBinaryValue,
      beq_self_eq_true, if_true, evalSignedBinary]
    have wrappedCoerced :
        wrapSigned program.target .i32 ((cursor : Int) + 1) =
          (cursor : Int) + 1 := by
      simpa using wrapped
    exact congrArg
      (fun value => (Except.ok (.signed .i32 value) : Except Trap Value))
      wrappedCoerced
  have writeResult :
      writeResolvedPlace state
        { root := 4, projections := [], value := some (.signed .i32 cursor) }
        (.signed .i32 (cursor + 1)) = .ok next := by
    simp [writeResolvedPlace, assigned]
  have assignmentResult :
      evalExpr 10 program state
        (.assign .add (.local 3) (i32Literal 1)) =
        .done .unit next := by
    rw [Lanius.Semantics.evalExpr.eq_def]
    simp only
    rw [placeResult]
    simp only
    rw [rightResult]
    simp only
    rw [arithmeticResult]
    simp only
    rw [writeResult]
  rw [Lanius.Semantics.execStmt.eq_def]
  simp only
  rw [assignmentResult]

theorem ScannerState.execBlockCommentStep
    (invariant : ScannerState state source start cursor)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : cursor < source.length)
    (conditionResult : Evaluates lexerProgram state
      blockCommentCloseCondition (.boolean false) state) :
    ∃ next,
      Executes lexerProgram state blockCommentLoopBody .next next ∧
      ScannerState next source start (cursor + 1) := by
  have ifExec :
      Executes lexerProgram state
        (.ifThenElse blockCommentCloseCondition
          (.returnValue (some (callScanConstructor successfulScanFunction
            (.binary .add (.local 3) (i32Literal 2)))))
          .skip) .next state :=
    executesIfFalse conditionResult (executesSkip lexerProgram state)
  have incrementBound : cursor + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound
  let next := incrementedCursorState state cursor
  have incrementExec :
      Executes lexerProgram state (incrementLocal 3 1) .next next := by
    exact ⟨11, by simpa [incrementLocal] using
      invariant.execCursorIncrement lexerProgram incrementBound⟩
  exact ⟨next, by
    simpa [blockCommentLoopBody] using executesSequence ifExec incrementExec,
    invariant.afterCursorAssignment⟩

theorem ScannerState.execBlockCommentClose
    (invariant : ScannerState state source start cursor)
    (sourceBound : source.length ≤ 2147483647)
    (nextInBounds : cursor + 1 < source.length)
    (conditionResult : Evaluates lexerProgram state
      blockCommentCloseCondition (.boolean true) state) :
    ∃ finalState,
      Executes lexerProgram state blockCommentLoopBody
        (.returned (some (scanEndValue (.success (cursor + 2))))) finalState := by
  have resultBound : cursor + 2 ≤ 2147483647 :=
    Nat.le_trans (Nat.succ_le_of_lt nextInBounds) sourceBound
  have argumentBase := evalI32LocalAddNat state 3 cursor 2
    invariant.cursorLocal resultBound
  have argumentResult := evalExpr_done_at_larger_fuel (program := lexerProgram)
    (by decide : 4 ≤ 6) argumentBase
  let called := singleArgumentCallState state (.signed .i32 (cursor + 2))
  have callResult :
      Evaluates lexerProgram state
        (callScanConstructor successfulScanFunction
          (.binary .add (.local 3) (i32Literal 2)))
        (scanEndValue (.success (cursor + 2))) called := by
    exact ⟨8, successfulScanCall_after_argument state invariant.wellFormed
      (.binary .add (.local 3) (i32Literal 2)) (cursor + 2)
      (by simpa using argumentResult)⟩
  have returnExec := executesReturnValue callResult
  have ifExec :
      Executes lexerProgram state
        (.ifThenElse blockCommentCloseCondition
          (.returnValue (some (callScanConstructor successfulScanFunction
            (.binary .add (.local 3) (i32Literal 2)))))
          .skip)
        (.returned (some (scanEndValue (.success (cursor + 2))))) called :=
    executesIfTrue conditionResult returnExec
  exact ⟨called, by
    simpa [blockCommentLoopBody] using executesSequenceReturned ifExec⟩

def scanAcceptedFrom
    (accept : Byte → Bool) (source : List Byte) (cursor : Nat) : Nat :=
  cursor + (splitPrefix accept (source.drop cursor)).1.length

theorem scanAcceptedFrom_out_of_bounds
    (accept : Byte → Bool) (source : List Byte) (cursor : Nat)
    (outOfBounds : ¬ cursor < source.length) :
    scanAcceptedFrom accept source cursor = cursor := by
  have pastEnd : source.length ≤ cursor := Nat.le_of_not_gt outOfBounds
  simp [scanAcceptedFrom, List.drop_eq_nil_of_le pastEnd, splitPrefix]

theorem scanAcceptedFrom_rejected
    (accept : Byte → Bool) (source : List Byte) (cursor : Nat)
    (inBounds : cursor < source.length)
    (rejected : accept (source.get ⟨cursor, inBounds⟩) = false) :
    scanAcceptedFrom accept source cursor = cursor := by
  unfold scanAcceptedFrom
  rw [List.drop_eq_getElem_cons inBounds, splitPrefix]
  have rejectedAt : accept source[cursor] = false := by simpa using rejected
  rw [rejectedAt]
  rfl

theorem scanAcceptedFrom_accepted
    (accept : Byte → Bool) (source : List Byte) (cursor : Nat)
    (inBounds : cursor < source.length)
    (accepted : accept (source.get ⟨cursor, inBounds⟩) = true) :
    scanAcceptedFrom accept source cursor =
      scanAcceptedFrom accept source (cursor + 1) := by
  unfold scanAcceptedFrom
  rw [List.drop_eq_getElem_cons inBounds, splitPrefix]
  have acceptedAt : accept source[cursor] = true := by simpa using accepted
  rw [acceptedAt]
  simp only [if_true, List.length_cons]
  omega

def scannerLoopCondition (predicate : Function) : Expr :=
  scannerCondition predicate

def scannerLoopBody : Stmt :=
  .expression (.assign .add (.local 3) (i32Literal 1))

def scannerLoop (predicate : Function) : Stmt :=
  .whileLoop (scannerLoopCondition predicate) scannerLoopBody

theorem evalScannerCondition_in_bounds
    (semantics : ScannerPredicateSemantics program predicate accept)
    (state : State) (wellFormed : StateWellFormed state)
    (source : List Byte) (cursor : Nat)
    (inBounds : cursor < source.length)
    (sourceLocal : state.local? 0 =
      some (.slice i32Type 0 [] 0 source.length))
    (limitLocal : state.local? 1 =
      some (.signed .i32 source.length))
    (cursorLocal : state.local? 3 = some (.signed .i32 cursor))
    (backing : state.cellEntry? 0 =
      some { id := 0, value := some (.array (sourceValues source)) }) :
    evalExpr 16 program state (scannerCondition predicate) =
      .done (.boolean (accept (source.get ⟨cursor, inBounds⟩)))
        (semantics.callState state (source.get ⟨cursor, inBounds⟩)) := by
  let byte := source.get ⟨cursor, inBounds⟩
  have leftBase := evalLocalLessLocal (program := program)
    state cursor source.length 3 1 cursorLocal limitLocal
  have left := evalExpr_done_at_larger_fuel (program := program)
    (by decide : 13 ≤ 15) leftBase
  have argumentBase := evalSourceIndexAt (program := program) state source cursor 3
    inBounds sourceLocal cursorLocal backing
  have argument := evalExpr_done_at_larger_fuel (program := program)
    (by decide : 10 ≤ 13) argumentBase
  have right := semantics.call_executes state wellFormed
    (.index (.local 0) (.local 3)) byte argument
  change evalExpr 16 program state
    (andExpr (.binary .less (.local 3) (.local 1))
      (.call predicate.id [.index (.local 0) (.local 3)])) = _
  simp only [andExpr]
  rw [evalExpr, left]
  simp only [inBounds]
  simpa [byte] using right

theorem evalScannerCondition_out_of_bounds
    (program : Program) (predicate : Function) (state : State)
    (source : List Byte) (cursor : Nat)
    (outOfBounds : ¬ cursor < source.length)
    (cursorLocal : state.local? 3 = some (.signed .i32 cursor))
    (limitLocal : state.local? 1 =
      some (.signed .i32 source.length)) :
    evalExpr 16 program state (scannerCondition predicate) =
      .done (.boolean false) state := by
  have leftBase := evalLocalLessLocal (program := program)
    state cursor source.length 3 1 cursorLocal limitLocal
  have left := evalExpr_done_at_larger_fuel (program := program)
    (by decide : 13 ≤ 15) leftBase
  change evalExpr 16 program state
    (andExpr (.binary .less (.local 3) (.local 1))
      (.call predicate.id [.index (.local 0) (.local 3)])) = _
  simp only [andExpr]
  rw [evalExpr, left]
  simp [outOfBounds]

namespace LineCommentFunctional

open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.ReadOnly
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Stateful
open Lanius.FunctionalView.Stateful.Loop

private abbrev T := Term signature 3
private abbrev C := Command signature actions 3

private def sourceIntegers (source : List Byte) : List Int :=
  source.map fun byte => Int.ofNat byte.val

@[simp] private theorem sourceIntegers_length :
    (sourceIntegers source).length = source.length := by
  simp [sourceIntegers]

@[simp] private theorem sourceIntegers_values :
    signedI32Values (sourceIntegers source) = sourceValues source := by
  simp [sourceIntegers, sourceValues, signedI32Values]

private def layout : Layout 3 :=
  Layout.push (pairLayout 0 3) 1

private def sourceTerm : T := reference ⟨0, by omega⟩
private def cursorTerm : T := reference ⟨1, by omega⟩
private def boundTerm : T := reference ⟨2, by omega⟩
private def oneTerm : T := literal (.signed .i32 1)
private def newlineTerm : T := literal (.signed .i32 10)

private def beforeEnd : T :=
  apply (.binary .less i32Type i32Type (.scalar .bool))
    [cursorTerm, boundTerm]

private def currentByte : T :=
  apply (.index (.slice i32Type) i32Type i32Type)
    [sourceTerm, cursorTerm]

private def notNewline : T :=
  apply (.binary .notEqual i32Type i32Type (.scalar .bool))
    [currentByte, newlineTerm]

private def condition : T := logicalAnd beforeEnd notNewline

private def body : C :=
  .updateLocal .add ⟨1, by omega⟩ oneTerm

private def loop : C := .whileLoop condition body

private theorem loop_toCore :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter layout 4 loop =
      .whileLoop lineCommentCondition (incrementLocal 3 1) := by
  rfl

private def runtime (source : List Byte) (cursor : Nat) :
    Runtime (Lanius.FunctionalView.Core.ReadOnly.machine lexerProgram) 3 :=
  (World.singleton 0 (sourceIntegers source),
    (pairEnvironment
      (.slice i32Type 0 [] 0 source.length)
      (.signed .i32 (Int.ofNat cursor))).push
        (.signed .i32 (Int.ofNat source.length)))

private def accepts (source : List Byte) (cursor : Nat) : Bool :=
  (source[cursor]?.map fun byte => byte.val != 10).getD false

private theorem condition_in_bounds
    (cursor : Nat) (inBounds : cursor < source.length) :
    Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine lexerProgram)
      (runtime source cursor).world (runtime source cursor).environment
      condition = .ok (.boolean (accepts source cursor),
        (runtime source cursor).world) := by
  have evaluated : Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine lexerProgram)
      (runtime source cursor).world (runtime source cursor).environment
      condition = .ok (.boolean (decide (Int.ofNat
        (source.get ⟨cursor, inBounds⟩).val ≠ Int.ofNat 10)),
        (runtime source cursor).world) := by
    simp only [condition, Lanius.FunctionalView.Core.logicalAnd, beforeEnd,
      notNewline, currentByte, sourceTerm, cursorTerm, boundTerm, newlineTerm,
      Lanius.FunctionalView.Core.apply, Lanius.FunctionalView.Core.reference,
      Lanius.FunctionalView.Core.literal, runtime, Runtime.world,
      Runtime.environment]
    apply Term.evaluate_logicalAnd_true
      (afterLeft := World.singleton 0 (sourceIntegers source))
    · have left := Term.evaluate_i32_less (program := lexerProgram)
        (world := World.singleton 0 (sourceIntegers source))
        (environment := (pairEnvironment
          (.slice i32Type 0 [] 0 source.length)
          (.signed .i32 (Int.ofNat cursor))).push
            (.signed .i32 (Int.ofNat source.length)))
        (leftType := i32Type) (rightType := i32Type)
        (outputType := .scalar .bool)
        (left := .reference (.slot ⟨1, by omega⟩))
        (right := .reference (.slot ⟨2, by omega⟩))
        (leftValue := cursor) (rightValue := source.length)
        (by rfl) (by rfl)
      simpa [inBounds] using left
    · apply Term.evaluate_i32_notEqual_int
      · apply Term.evaluate_i32_index_as
          (cell := 0) (values := sourceIntegers source)
          (position := cursor)
          (expected := Int.ofNat
            (source.get ⟨cursor, inBounds⟩).val)
        · apply Term.evaluate_slot
          simp [Lanius.FunctionalView.Env.push, pairEnvironment, i32Type]
        · apply Term.evaluate_slot
          simp [Lanius.FunctionalView.Env.push, pairEnvironment]
        · exact World.singleton_finds
        · simp [sourceIntegers]
        · simpa [sourceIntegers] using inBounds
      · rfl
  rw [decide_intOfNat_notEqual] at evaluated
  simpa [accepts, List.getElem?_eq_getElem inBounds] using evaluated

private theorem condition_out_of_bounds
    (cursor : Nat) (outOfBounds : ¬ cursor < source.length) :
    Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine lexerProgram)
      (runtime source cursor).world (runtime source cursor).environment condition =
      .ok (.boolean false, (runtime source cursor).world) := by
  have leftResult : Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine lexerProgram)
      (runtime source cursor).world (runtime source cursor).environment beforeEnd =
      .ok (.boolean false, (runtime source cursor).world) := by
    have evaluated := Term.evaluate_i32_less (program := lexerProgram)
      (world := (runtime source cursor).world)
      (environment := (runtime source cursor).environment)
      (leftType := i32Type) (rightType := i32Type)
      (outputType := (.scalar .bool))
      (left := cursorTerm) (right := boundTerm)
      (leftValue := cursor) (rightValue := source.length)
      (by rfl) (by rfl)
    simpa [beforeEnd, Lanius.FunctionalView.Core.apply, runtime,
      outOfBounds] using evaluated
  exact Term.evaluate_logicalAnd_false leftResult

private theorem incrementResult
    (cursor : Nat) (sourceBound : source.length ≤ 2147483647)
    (inBounds : cursor < source.length) :
    evalAssignValue lexerProgram.target .add
      (some ((runtime source cursor).environment ⟨1, by omega⟩))
      (.signed .i32 1) =
      .ok (.signed .i32 (Int.ofNat (cursor + 1))) := by
  have cursorValue : (runtime source cursor).environment ⟨1, by omega⟩ =
      .signed .i32 (Int.ofNat cursor) := by
    change ((pairEnvironment
      (.slice i32Type 0 [] 0 source.length)
      (.signed .i32 (Int.ofNat cursor))).push
        (.signed .i32 (Int.ofNat source.length))) ⟨1, by omega⟩ = _
    simp [Lanius.FunctionalView.Env.push, pairEnvironment]
  have addition : Int.ofNat cursor + 1 = Int.ofNat (cursor + 1) := by
    simp
  have incrementBound : cursor + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound
  have wrapped := wrapSigned_i32_ofNat (cursor + 1) incrementBound
  rw [cursorValue]
  simp only [evalAssignValue, assignOpBinary?, evalBinaryValue,
    beq_self_eq_true, if_true, evalSignedBinary]
  rw [addition, wrapped]

private theorem body_evaluates
    (cursor : Nat) (sourceBound : source.length ≤ 2147483647)
    (inBounds : cursor < source.length) :
    Command.Evaluates
      (Lanius.FunctionalView.Core.ReadOnly.machine lexerProgram)
      (Lanius.FunctionalView.Core.Stateful.machine lexerProgram)
      (runtime source cursor).world (runtime source cursor).environment body .next
      (runtime source (cursor + 1)).world
      (runtime source (cursor + 1)).environment := by
  have oneResult : Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine lexerProgram)
      (runtime source cursor).world (runtime source cursor).environment oneTerm =
      .ok (.signed .i32 1, (runtime source cursor).world) := by
    rfl
  have advanceWorld : (runtime source (cursor + 1)).world =
      (runtime source cursor).world := by
    rfl
  have advanceEnvironment : (runtime source (cursor + 1)).environment =
      Lanius.FunctionalView.Stateful.Env.set (runtime source cursor).environment
        ⟨1, by omega⟩
        (.signed .i32 (Int.ofNat (cursor + 1))) := by
    funext index
    have cases : index.val = 0 ∨ index.val = 1 ∨ index.val = 2 := by
      omega
    rcases cases with zero | one | two
    · have indexEq : index = ⟨0, by omega⟩ := Fin.ext zero
      rw [indexEq]
      simp [runtime, Runtime.environment,
        Lanius.FunctionalView.Env.push, pairEnvironment,
        Lanius.FunctionalView.Stateful.Env.set]
    · have indexEq : index = ⟨1, by omega⟩ := Fin.ext one
      rw [indexEq]
      simp [runtime, Runtime.environment,
        Lanius.FunctionalView.Env.push,
        Lanius.FunctionalView.Stateful.Env.set]
    · have indexEq : index = ⟨2, by omega⟩ := Fin.ext two
      rw [indexEq]
      simp [runtime, Runtime.environment,
        Lanius.FunctionalView.Env.push,
        Lanius.FunctionalView.Stateful.Env.set]
  rw [advanceWorld, advanceEnvironment]
  exact Command.Evaluates.updateLocal oneResult (by
    simpa only [Lanius.FunctionalView.Core.Stateful.machine,
      Lanius.FunctionalView.Core.Stateful.machineWith] using
      incrementResult cursor sourceBound inBounds)

private theorem inBounds_of_condition_true
    (cursor : Nat)
    (conditionTrue : Term.evaluate
      (Lanius.FunctionalView.Core.ReadOnly.machine lexerProgram)
      (runtime source cursor).world (runtime source cursor).environment condition =
      .ok (.boolean true, (runtime source cursor).world)) :
    cursor < source.length := by
  by_cases inBounds : cursor < source.length
  · exact inBounds
  · have conditionFalse := condition_out_of_bounds (source := source) cursor inBounds
    have impossible := conditionFalse.symm.trans conditionTrue
    simp at impossible

private theorem scanRecurrence : CursorScan.Recurrence source.length
    (accepts source)
    (scanAcceptedFrom (fun byte => byte.val != 10) source) := by
  constructor
  · exact scanAcceptedFrom_out_of_bounds _ source
  · intro cursor inBounds rejected
    apply scanAcceptedFrom_rejected _ source cursor inBounds
    simpa [accepts, List.getElem?_eq_getElem inBounds] using rejected
  · intro cursor inBounds accepted
    apply scanAcceptedFrom_accepted _ source cursor inBounds
    simpa [accepts, List.getElem?_eq_getElem inBounds] using accepted

private theorem scanSpec
    (sourceBound : source.length ≤ 2147483647) : CursorScan.Spec
      (Lanius.FunctionalView.Core.ReadOnly.machine lexerProgram)
      (Lanius.FunctionalView.Core.Stateful.machine lexerProgram)
      condition LineCommentFunctional.body (runtime source) source.length
      (accepts source) := {
  conditionInBounds := condition_in_bounds
  conditionOutOfBounds := condition_out_of_bounds
  body := fun cursor inBounds _ => body_evaluates cursor sourceBound inBounds
}

private theorem bodySound
    (sourceBound : source.length ≤ 2147483647)
    (localCells : Fin 3 → CellId) :
    ConfigBodySoundWithin lexerProgram layout localCells condition
      LineCommentFunctional.body actionAdapter 4
      (Lanius.Separation.CellSet.singleton (localCells ⟨1, by omega⟩))
      Nat (runtime source) := by
  apply updateLocalConfigBodySoundWithin
    (right := fun _ => .signed .i32 1)
    (result := fun cursor => .signed .i32 (Int.ofNat (cursor + 1)))
  · intro _ _
    rfl
  · intro cursor conditionTrue
    have inBounds := inBounds_of_condition_true cursor conditionTrue
    exact incrementResult cursor sourceBound inBounds

private theorem executeLoop
    (invariant : ScannerState state source start cursor)
    (sourceBound : source.length ≤ 2147483647) :
    ∃ finalState,
      Executes lexerProgram state
        (.whileLoop lineCommentCondition (incrementLocal 3 1))
        .next finalState ∧
      ScannerState finalState source start
        (scanAcceptedFrom (fun byte => byte.val != 10) source cursor) := by
  have cursorOwned :
      (Lanius.Separation.Assertion.localPointsTo 3 4
        (some (.signed .i32 (Int.ofNat cursor)))).holds state :=
    ⟨invariant.cursorLocalId, invariant.cursorLocalCell⟩
  have sharedSeparate : Lanius.Separation.CellSet.Disjoint
      (Lanius.Separation.localCellFootprint state
        (fun id => id = 0 ∨ id = 1))
      (Lanius.Separation.CellSet.union
        (Lanius.Separation.CellSet.singleton 0)
        (Lanius.Separation.CellSet.singleton 4)) := by
    intro cell member written
    obtain ⟨id, localId, found⟩ := member
    rcases localId with rfl | rfl <;>
      rcases written with written | written <;>
      simp only [Lanius.Separation.CellSet.singleton] at written <;>
      subst cell <;>
      simp [invariant.sourceLocalId, invariant.limitLocalId] at found
  let boundedView := SliceCursorBoundRepresentation.ofState
    (sliceId := 0) (cursorId := 3) (boundId := 1)
    (sliceCell := 0) (cursorCell := 4)
    (sliceValues := sourceIntegers source)
    (cursorValue := .signed .i32 (Int.ofNat cursor))
    (boundValue := .signed .i32 (Int.ofNat source.length))
    (state := state)
    invariant.wellFormed
    (by simpa [i32Type, sourceIntegers_length] using invariant.sourceLocal)
    (by simpa [sourceIntegers_values] using invariant.sourceCell)
    cursorOwned (by simpa using invariant.limitLocal) sharedSeparate
    (by decide) (by simp)
  let localCells : Fin 3 → CellId :=
    pushCells (pairCells boundedView.sliceLocalCell 4)
      boundedView.boundLocalCell
  have represented : Representation layout localCells (runtime source cursor).world
      (runtime source cursor).environment state := by
    simpa [layout, localCells, runtime, sourceIntegers_length,
      i32Type, Runtime.world, Runtime.environment] using boundedView.represented
  let assembled := CursorScan.run (scanSpec sourceBound) scanRecurrence cursor
  rcases assembled with ⟨completion, abstractAfter, trace, result⟩
  cases result.completionEq
  let abstractSimulation := trace.simulatesWithin
    (bodySound sourceBound localCells) represented invariant.wellFormed
  have simulation : SimulatesWithin lexerProgram layout localCells
      (runtime source cursor).world (runtime source cursor).environment
      state loop .next (runtime source result.finalCursor).world
      (runtime source result.finalCursor).environment
      actionAdapter 4 (Lanius.Separation.CellSet.singleton 4) := by
    rw [← result.afterEq]
    simpa [loop, localCells, pushCells, pairCells] using abstractSimulation
  let finalState := Classical.choose simulation
  have simulationFacts := Classical.choose_spec simulation
  have loopExecution := simulationFacts.1
  have finalWellFormed := simulationFacts.2.1
  have finalRepresented := simulationFacts.2.2.1
  have effect := simulationFacts.2.2.2
  have finalCursorCell : finalState.cellEntry? 4 = some {
      id := 4,
      value := some (.signed .i32 (Int.ofNat result.finalCursor)) } := by
    have owned := finalRepresented.localOwned ⟨1, by omega⟩
    simpa [finalState, localCells, runtime, Runtime.environment,
      Lanius.FunctionalView.Env.push, pairEnvironment, pushCells, pairCells]
      using owned.2
  have finalInvariant : ScannerState finalState source start
      result.finalCursor :=
    invariant.afterCursorEffect result.finalCursor finalWellFormed effect
      finalCursorCell
  refine ⟨finalState, ?_, ?_⟩
  · simpa [finalState, loop_toCore,
      Lanius.FunctionalView.Core.Stateful.toCoreCompletion] using loopExecution
  · rw [result.finalEq] at finalInvariant
    exact finalInvariant

end LineCommentFunctional

theorem executesScannerLoop
    (semantics : ScannerPredicateSemantics program predicate accept)
    (invariant : ScannerState state source start cursor)
    (sourceBound : source.length ≤ 2147483647) :
    ∃ finalState,
      Executes program state (scannerLoop predicate) .next finalState ∧
      ScannerState finalState source start
        (scanAcceptedFrom accept source cursor) := by
  by_cases inBounds : cursor < source.length
  · let byte := source.get ⟨cursor, inBounds⟩
    have conditionResult := evalScannerCondition_in_bounds semantics
      state invariant.wellFormed source cursor inBounds invariant.sourceLocal
      invariant.limitLocal invariant.cursorLocal invariant.sourceCell
    have calledInvariant := invariant.afterPredicateCall
      (semantics.call_extends state byte)
      (semantics.call_well_formed state invariant.wellFormed byte)
    by_cases accepted : accept byte = true
    · have acceptedSource :
          accept (source.get ⟨cursor, inBounds⟩) = true := by
        simpa [byte] using accepted
      rw [acceptedSource] at conditionResult
      have conditionExec :
          Evaluates program state (scannerLoopCondition predicate)
            (.boolean true) (semantics.callState state byte) := by
        refine ⟨16, ?_⟩
        simpa [scannerLoopCondition, byte] using conditionResult
      have incrementBound : cursor + 1 ≤ 2147483647 :=
        Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound
      have bodyExec : Executes program (semantics.callState state byte)
          scannerLoopBody .next
          (incrementedCursorState (semantics.callState state byte) cursor) := by
        refine ⟨11, ?_⟩
        simpa [scannerLoopBody] using
          calledInvariant.execCursorIncrement program incrementBound
      have nextInvariant := calledInvariant.afterCursorAssignment
      obtain ⟨finalState, restExec, finalInvariant⟩ :=
        executesScannerLoop semantics nextInvariant sourceBound
      refine ⟨finalState, ?_, ?_⟩
      · exact executesWhileTrue conditionExec bodyExec restExec
      · rw [scanAcceptedFrom_accepted accept source cursor inBounds
          (by simpa [byte] using accepted)]
        exact finalInvariant
    · have rejected : accept byte = false := Bool.eq_false_iff.mpr accepted
      have rejectedSource :
          accept (source.get ⟨cursor, inBounds⟩) = false := by
        simpa [byte] using rejected
      rw [rejectedSource] at conditionResult
      have conditionExec :
          Evaluates program state (scannerLoopCondition predicate)
            (.boolean false) (semantics.callState state byte) := by
        refine ⟨16, ?_⟩
        simpa [scannerLoopCondition, byte] using conditionResult
      refine ⟨semantics.callState state byte,
        executesWhileFalse conditionExec, ?_⟩
      rw [scanAcceptedFrom_rejected accept source cursor inBounds
        (by simpa [byte] using rejected)]
      exact calledInvariant
  · have conditionResult := evalScannerCondition_out_of_bounds
      program predicate state source cursor inBounds invariant.cursorLocal
      invariant.limitLocal
    have conditionExec :
        Evaluates program state (scannerLoopCondition predicate)
          (.boolean false) state := by
      exact ⟨16, by simpa [scannerLoopCondition] using conditionResult⟩
    refine ⟨state, executesWhileFalse conditionExec, ?_⟩
    rw [scanAcceptedFrom_out_of_bounds accept source cursor inBounds]
    exact invariant
termination_by source.length - cursor
decreasing_by omega

theorem executesLineCommentLoop
    (invariant : ScannerState state source start cursor)
    (sourceBound : source.length ≤ 2147483647) :
    ∃ finalState,
      Executes lexerProgram state
        (.whileLoop lineCommentCondition (incrementLocal 3 1))
        .next finalState ∧
      ScannerState finalState source start
        (scanAcceptedFrom (fun byte => byte.val != 10) source cursor) := by
  exact LineCommentFunctional.executeLoop invariant sourceBound

def scannerParameterState (source : List Byte) (start : Nat) : State :=
  (sourceState source).bindLocals
    [(0, .slice i32Type 0 [] 0 source.length),
      (1, .signed .i32 source.length),
      (2, .signed .i32 start)]

def scannerLoopInitialState (source : List Byte) (start : Nat) : State :=
  (scannerParameterState source start).bindLocal 3 (.signed .i32 (start + 1))

theorem scannerParameterState_well_formed
    (source : List Byte) (start : Nat) :
    StateWellFormed (scannerParameterState source start) := by
  unfold scannerParameterState State.bindLocals
  simp only [List.foldl]
  exact bindLocal_preserves_well_formed _ 2 (.signed .i32 start)
    (bindLocal_preserves_well_formed _ 1 (.signed .i32 source.length)
      (bindLocal_preserves_well_formed _ 0
        (.slice i32Type 0 [] 0 source.length)
        (sourceState_well_formed source)))

theorem scannerParameterState_startLocal
    (source : List Byte) (start : Nat) :
    (scannerParameterState source start).local? 2 =
      some (.signed .i32 start) := by
  rfl

theorem evalScannerCursorInitializer
    (program : Program)
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    evalExpr 8 program (scannerParameterState source start)
      (.binary .add (.local 2) (i32Literal 1)) =
      .done (.signed .i32 (start + 1))
        (scannerParameterState source start) := by
  have localResult := evalLocal_of_local 6 program
    (scannerParameterState source start) 2 (.signed .i32 start)
    (scannerParameterState_startLocal source start)
  have localResult7 :
      evalExpr 7 program (scannerParameterState source start) (.local 2) =
        .done (.signed .i32 start) (scannerParameterState source start) := by
    simpa using localResult
  have oneResult :
      evalExpr 7 program (scannerParameterState source start)
        (i32Literal 1) =
        .done (.signed .i32 1) (scannerParameterState source start) := by
    rfl
  have incrementBound : start + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.succ_le_of_lt startInBounds) sourceBound
  have wrapped :
      wrapSigned program.target .i32 ((start : Int) + 1) =
        (start : Int) + 1 := by
    simpa using wrapSigned_i32_ofNat_at_target program.target (start + 1)
      incrementBound
  have operationResult :
      evalBinaryValue program.target .add
        (.signed .i32 start) (.signed .i32 1) =
        .ok (.signed .i32 (start + 1)) := by
    simp only [evalBinaryValue, beq_self_eq_true, if_true, evalSignedBinary]
    exact congrArg
      (fun value => (Except.ok (.signed .i32 value) : Except Trap Value))
      wrapped
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [localResult7]
  simp only
  rw [oneResult]
  simp only
  rw [operationResult]

theorem scannerLoopInitialState_invariant
    (source : List Byte) (start : Nat) :
    ScannerState (scannerLoopInitialState source start)
      source start (start + 1) := by
  constructor
  · exact bindLocal_preserves_well_formed _ 3 (.signed .i32 (start + 1))
      (scannerParameterState_well_formed source start)
  · change 5 ≤ 5
    decide
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl

def lineCommentLoopInitialState (source : List Byte) (start : Nat) : State :=
  (scannerParameterState source start).bindLocal 3
    (.signed .i32 (start + 2))

theorem lineCommentLoopInitialState_invariant
    (source : List Byte) (start : Nat) :
    ScannerState (lineCommentLoopInitialState source start)
      source start (start + 2) := by
  constructor
  · exact bindLocal_preserves_well_formed _ 3 (.signed .i32 (start + 2))
      (scannerParameterState_well_formed source start)
  · change 5 ≤ 5
    decide
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl

theorem lineCommentBody_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length) :
    ∃ loopFinal,
      Executes lexerProgram (scannerParameterState source start)
        lineCommentBody
        (.returned (some (.signed .i32 (scanLineCommentEnd source start))))
        (restoreLocals (scannerParameterState source start) loopFinal) ∧
      ScannerState loopFinal source start (scanLineCommentEnd source start) := by
  have initialInvariant := lineCommentLoopInitialState_invariant source start
  obtain ⟨loopFinal, loopExec, finalInvariant⟩ :=
    executesLineCommentLoop initialInvariant sourceBound
  have scannedCursor :
      scanAcceptedFrom (fun byte => byte.val != 10) source (start + 2) =
        scanLineCommentEnd source start := by
    rfl
  rw [scannedCursor] at finalInvariant
  have returnValue :
      Evaluates lexerProgram loopFinal (.local 3)
        (.signed .i32 (scanLineCommentEnd source start)) loopFinal := by
    refine ⟨1, ?_⟩
    simpa using evalLocal_of_local 0 lexerProgram loopFinal 3
      (.signed .i32 (scanLineCommentEnd source start))
      finalInvariant.cursorLocal
  have returnExec := executesReturnValue returnValue
  have sequenceExec := executesSequence loopExec returnExec
  have initializerBound : start + 2 ≤ 2147483647 :=
    Nat.le_trans (by omega : start + 2 ≤ source.length) sourceBound
  have initializerExec :
      Evaluates lexerProgram (scannerParameterState source start)
        (.binary .add (.local 2) (i32Literal 2))
        (.signed .i32 (start + 2))
        (scannerParameterState source start) :=
    ⟨4, evalI32LocalAddNat (scannerParameterState source start) 2 start 2
      (scannerParameterState_startLocal source start) initializerBound⟩
  have letExec := executesLetLocal (type := i32Type)
    initializerExec (by
      simpa [lineCommentLoopInitialState] using sequenceExec)
  refine ⟨loopFinal, ?_, finalInvariant⟩
  simpa [lineCommentBody] using letExec

theorem scannerBody_executes
    (semantics : ScannerPredicateSemantics program predicate accept)
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ loopFinal,
      Executes program (scannerParameterState source start)
        (scannerBody predicate)
        (.returned (some (.signed .i32
          (scanAcceptedFrom accept source (start + 1)))))
        (restoreLocals (scannerParameterState source start) loopFinal) ∧
      ScannerState loopFinal source start
        (scanAcceptedFrom accept source (start + 1)) := by
  have initialInvariant := scannerLoopInitialState_invariant source start
  obtain ⟨loopFinal, loopExec, finalInvariant⟩ :=
    executesScannerLoop semantics initialInvariant sourceBound
  have returnValue :
      Evaluates program loopFinal (.local 3)
        (.signed .i32 (scanAcceptedFrom accept source (start + 1)))
        loopFinal := by
    refine ⟨1, ?_⟩
    simpa using evalLocal_of_local 0 program loopFinal 3
      (.signed .i32 (scanAcceptedFrom accept source (start + 1)))
      finalInvariant.cursorLocal
  have returnExec := executesReturnValue returnValue
  have sequenceExec := executesSequence loopExec returnExec
  have initializerExec :
      Evaluates program (scannerParameterState source start)
        (.binary .add (.local 2) (i32Literal 1))
        (.signed .i32 (start + 1))
        (scannerParameterState source start) :=
    ⟨8, evalScannerCursorInitializer program source start sourceBound
      startInBounds⟩
  have letExec := executesLetLocal (type := i32Type)
    initializerExec (by
      simpa [scannerLoopInitialState] using sequenceExec)
  refine ⟨loopFinal, ?_, finalInvariant⟩
  simpa [scannerBody, scannerLoop, scannerLoopCondition,
    scannerLoopBody] using letExec

theorem scanWhitespaceBody_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ loopFinal,
      Executes lexerProgram (scannerParameterState source start)
        (scannerBody isWhitespaceFunction)
        (.returned (some (.signed .i32 (scanWhitespaceEnd source start))))
        (restoreLocals (scannerParameterState source start) loopFinal) ∧
      ScannerState loopFinal source start
        (scanWhitespaceEnd source start) := by
  simpa [scanAcceptedFrom, scanWhitespaceEnd] using
    scannerBody_executes whitespacePredicateSemantics source start
      sourceBound startInBounds

theorem scanIdentifierBody_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ loopFinal,
      Executes lexerProgram (scannerParameterState source start)
        (scannerBody isIdentifierContinueFunction)
        (.returned (some (.signed .i32 (scanIdentifierEnd source start))))
        (restoreLocals (scannerParameterState source start) loopFinal) ∧
      ScannerState loopFinal source start
        (scanIdentifierEnd source start) := by
  simpa [scanAcceptedFrom, scanIdentifierEnd] using
    scannerBody_executes identifierPredicateSemantics source start
      sourceBound startInBounds

def sourceSlice (source : List Byte) : Expr :=
  .value (.slice i32Type 0 [] 0 source.length)

def scannerCall (function : Function) (source : List Byte) (start : Nat) : Expr :=
  .call function.id
    [sourceSlice source, i32Literal source.length, i32Literal start]

def quotedScannerCall
    (source : List Byte) (start : Nat) (delimiter : Byte) : Expr :=
  .call scanQuotedEndFunction.id
    [sourceSlice source, i32Literal source.length, i32Literal start,
      i32Literal delimiter.val]

theorem lexerProgram_finds_scanWhitespaceEndFunction :
    lexerProgram.function? scanWhitespaceEndFunction.id =
      some scanWhitespaceEndFunction := by
  rfl

theorem lexerProgram_finds_scanIdentifierEndFunction :
    lexerProgram.function? scanIdentifierEndFunction.id =
      some scanIdentifierEndFunction := by
  rfl

theorem lexerProgram_finds_scanQuotedEndFunction :
    lexerProgram.function? scanQuotedEndFunction.id =
      some scanQuotedEndFunction := by
  rfl

theorem lexerProgram_finds_scanStringEndFunction :
    lexerProgram.function? scanStringEndFunction.id =
      some scanStringEndFunction := by
  rfl

theorem lexerProgram_finds_scanCharacterEndFunction :
    lexerProgram.function? scanCharacterEndFunction.id =
      some scanCharacterEndFunction := by
  rfl

theorem lexerProgram_finds_scanLineCommentEndFunction :
    lexerProgram.function? scanLineCommentEndFunction.id =
      some scanLineCommentEndFunction := by
  rfl

theorem lexerProgram_finds_scanBlockCommentEndFunction :
    lexerProgram.function? scanBlockCommentEndFunction.id =
      some scanBlockCommentEndFunction := by
  rfl

theorem scannerCall_executesBody
    (program : Program)
    (function : Function) (functionBody : Stmt) (result : Value)
    (functionFound : program.function? function.id = some function)
    (parameters : function.parameters = scannerParameters)
    (body : function.body = some functionBody)
    (source : List Byte) (start : Nat)
    (bodyExec : ∃ bodyFinal,
      Executes program (scannerParameterState source start) functionBody
        (.returned (some result)) bodyFinal) :
    ∃ finalState,
      Evaluates program (sourceState source)
        (scannerCall function source start) result finalState := by
  obtain ⟨bodyFinal, bodyExec⟩ := bodyExec
  obtain ⟨bodyFuel, bodyResult⟩ := bodyExec
  have argumentsBase :
      evalExprs 4 program (sourceState source)
        [sourceSlice source, i32Literal source.length, i32Literal start] =
        .done
          [.slice i32Type 0 [] 0 source.length,
            .signed .i32 source.length, .signed .i32 start]
          (sourceState source) := by
    rfl
  let fuel := max 4 bodyFuel
  have argumentsAtFuel := evalExprs_done_at_larger_fuel
    (Nat.le_max_left 4 bodyFuel) argumentsBase
  have bodyAtFuel := execStmt_done_at_larger_fuel
    (Nat.le_max_right 4 bodyFuel) bodyResult
  have boundParameters :
      bindParameters function.parameters
        [.slice i32Type 0 [] 0 source.length,
          .signed .i32 source.length, .signed .i32 start] =
        some
          [(0, .slice i32Type 0 [] 0 source.length),
            (1, .signed .i32 source.length), (2, .signed .i32 start)] := by
    rw [parameters]
    rfl
  have callee :
      ({ sourceState source with locals := [] }).bindLocals
        [(0, .slice i32Type 0 [] 0 source.length),
          (1, .signed .i32 source.length), (2, .signed .i32 start)] =
        scannerParameterState source start := by
    rfl
  let finalState := restoreLocals (sourceState source) bodyFinal
  refine ⟨finalState, fuel + 1, ?_⟩
  unfold scannerCall
  rw [evalExpr, argumentsAtFuel]
  simp only
  rw [functionFound]
  simp only
  rw [boundParameters, body]
  simp only
  rw [callee, bodyAtFuel]

theorem scannerFunction_executes
    (function : Function)
    (semantics : ScannerPredicateSemantics program predicate accept)
    (functionFound : program.function? function.id = some function)
    (parameters : function.parameters = scannerParameters)
    (body : function.body = some (scannerBody predicate))
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Evaluates program (sourceState source)
        (scannerCall function source start)
        (.signed .i32 (scanAcceptedFrom accept source (start + 1)))
        finalState := by
  obtain ⟨loopFinal, bodyExec, _finalInvariant⟩ :=
    scannerBody_executes semantics source start sourceBound startInBounds
  exact scannerCall_executesBody program function (scannerBody predicate)
    (.signed .i32 (scanAcceptedFrom accept source (start + 1)))
    functionFound parameters body source start
    ⟨restoreLocals (scannerParameterState source start) loopFinal, bodyExec⟩

/-- Universal execution contract for the represented in-Lanius whitespace
scanner. The source-size and start-position hypotheses are exactly the domain
in which its `i32` ABI represents the slice length and initial cursor. -/
theorem scanWhitespaceEndFunction_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Evaluates lexerProgram (sourceState source)
        (scannerCall scanWhitespaceEndFunction source start)
        (.signed .i32 (scanWhitespaceEnd source start)) finalState := by
  simpa [scanAcceptedFrom, scanWhitespaceEnd] using
    scannerFunction_executes scanWhitespaceEndFunction
      whitespacePredicateSemantics lexerProgram_finds_scanWhitespaceEndFunction
      rfl rfl source start sourceBound startInBounds

/-- Universal execution contract for the represented in-Lanius identifier
scanner. It proves the actual scanner loop and the nested identifier predicate
calls, rather than evaluating an abstract replacement. -/
theorem scanIdentifierEndFunction_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Evaluates lexerProgram (sourceState source)
        (scannerCall scanIdentifierEndFunction source start)
        (.signed .i32 (scanIdentifierEnd source start)) finalState := by
  simpa [scanAcceptedFrom, scanIdentifierEnd] using
    scannerFunction_executes scanIdentifierEndFunction
      identifierPredicateSemantics lexerProgram_finds_scanIdentifierEndFunction
      rfl rfl source start sourceBound startInBounds

/-- The represented line-comment scanner starts after the two-byte `//`
delimiter, consumes the maximal non-newline prefix, and returns its exact end
offset. This executes the represented Lanius function rather than an abstract
replacement. -/
theorem scanLineCommentEndFunction_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length) :
    ∃ finalState,
      Evaluates lexerProgram (sourceState source)
        (scannerCall scanLineCommentEndFunction source start)
        (.signed .i32 (scanLineCommentEnd source start)) finalState := by
  obtain ⟨loopFinal, bodyExec, _finalInvariant⟩ :=
    lineCommentBody_executes source start sourceBound openingInBounds
  exact scannerCall_executesBody lexerProgram scanLineCommentEndFunction
    lineCommentBody
    (.signed .i32 (scanLineCommentEnd source start))
    lexerProgram_finds_scanLineCommentEndFunction rfl rfl source start
    ⟨restoreLocals (scannerParameterState source start) loopFinal, bodyExec⟩

theorem scanLineCommentEndFunction_executes_spec
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length) :
    ∃ finish : Nat, ∃ finalState : State,
      Evaluates lexerProgram (sourceState source)
        (scannerCall scanLineCommentEndFunction source start)
        (.signed .i32 (finish : Int)) finalState ∧
      LineCommentEndSpec source start finish := by
  obtain ⟨finalState, execution⟩ :=
    scanLineCommentEndFunction_executes source start sourceBound openingInBounds
  exact ⟨scanLineCommentEnd source start, finalState, execution,
    scanLineCommentEnd_spec source start⟩

theorem executesBlockCommentWhile
    (invariant : ScannerState state source start cursor)
    (sourceBound : source.length ≤ 2147483647)
    (cursorBound : cursor ≤ source.length) :
    (∃ finalState,
      scanBlockBody (source.drop cursor) cursor = .failure source.length ∧
      Executes lexerProgram state
        (.whileLoop (.binary .less (.local 3) (.local 1))
          blockCommentLoopBody) .next finalState ∧
      ScannerState finalState source start source.length) ∨
    (∃ finalState,
      Executes lexerProgram state
        (.whileLoop (.binary .less (.local 3) (.local 1))
          blockCommentLoopBody)
        (.returned (some
          (scanEndValue (scanBlockBody (source.drop cursor) cursor))))
        finalState) := by
  by_cases inBounds : cursor < source.length
  · have loopConditionBase := evalCursorLessLimit state cursor source.length
      invariant.cursorLocal invariant.limitLocal
    have loopCondition :
        Evaluates lexerProgram state
          (.binary .less (.local 3) (.local 1)) (.boolean true) state := by
      exact ⟨13, by simpa [inBounds] using loopConditionBase⟩
    let byte := source.get ⟨cursor, inBounds⟩
    have dropped := List.drop_eq_getElem_cons inBounds
    by_cases isStar : byte.val = 42
    · by_cases nextInBounds : cursor + 1 < source.length
      · let nextByte := source.get ⟨cursor + 1, nextInBounds⟩
        by_cases isSlash : nextByte.val = 47
        · have closeBase := invariant.evalBlockCommentClose_withNext
            sourceBound inBounds nextInBounds (by simpa [byte] using isStar)
          have slashBoolean :
              ((source.get ⟨cursor + 1, nextInBounds⟩).val == 47) =
                true := by
            rw [show (source.get ⟨cursor + 1, nextInBounds⟩).val = 47 by
              simpa [nextByte] using isSlash]
            rfl
          rw [slashBoolean] at closeBase
          have closeCondition :
              Evaluates lexerProgram state blockCommentCloseCondition
                (.boolean true) state := ⟨15, closeBase⟩
          obtain ⟨finalState, bodyExec⟩ := invariant.execBlockCommentClose
            sourceBound nextInBounds closeCondition
          have resultEq :
              scanBlockBody (source.drop cursor) cursor =
                .success (cursor + 2) := by
            rw [dropped, List.drop_eq_getElem_cons nextInBounds, scanBlockBody,
              if_pos]
            exact ⟨by simpa [byte] using isStar,
              by simpa [nextByte] using isSlash⟩
          right
          refine ⟨finalState, ?_⟩
          rw [resultEq]
          exact executesWhileReturned loopCondition bodyExec
        · have closeBase := invariant.evalBlockCommentClose_withNext
            sourceBound inBounds nextInBounds (by simpa [byte] using isStar)
          have slashBoolean :
              ((source.get ⟨cursor + 1, nextInBounds⟩).val == 47) =
                false := by
            apply Bool.eq_false_iff.mpr
            intro equal
            apply isSlash
            simpa [nextByte] using equal
          rw [slashBoolean] at closeBase
          have closeCondition :
              Evaluates lexerProgram state blockCommentCloseCondition
                (.boolean false) state := ⟨15, closeBase⟩
          obtain ⟨next, bodyExec, nextInvariant⟩ :=
            invariant.execBlockCommentStep sourceBound inBounds closeCondition
          have notClose :
              ¬(source[cursor].val = 42 ∧ source[cursor + 1].val = 47) := by
            intro closes
            apply isSlash
            simpa [nextByte] using closes.2
          have stepResult :
              scanBlockBody (source.drop cursor) cursor =
                scanBlockBody (source.drop (cursor + 1)) (cursor + 1) := by
            rw [dropped, List.drop_eq_getElem_cons nextInBounds,
              scanBlockBody, if_neg notClose]
          rcases executesBlockCommentWhile nextInvariant sourceBound
              (Nat.succ_le_of_lt inBounds) with
            ⟨finalState, resultEq, restExec, finalInvariant⟩ |
            ⟨finalState, restExec⟩
          · left
            exact ⟨finalState, stepResult.trans resultEq,
              executesWhileTrueThen loopCondition bodyExec restExec,
              finalInvariant⟩
          · right
            refine ⟨finalState, ?_⟩
            rw [stepResult]
            exact executesWhileTrueThen loopCondition bodyExec restExec
      · have closeBase := invariant.evalBlockCommentClose_noNext
          sourceBound inBounds (by simpa [byte] using isStar) nextInBounds
        have closeCondition :
            Evaluates lexerProgram state blockCommentCloseCondition
              (.boolean false) state := ⟨15, closeBase⟩
        obtain ⟨next, bodyExec, nextInvariant⟩ :=
          invariant.execBlockCommentStep sourceBound inBounds closeCondition
        have atEnd : cursor + 1 = source.length := by omega
        have droppedNext : source.drop (cursor + 1) = [] := by
          exact List.drop_eq_nil_of_le (Nat.le_of_not_gt nextInBounds)
        have stepResult :
            scanBlockBody (source.drop cursor) cursor =
              scanBlockBody (source.drop (cursor + 1)) (cursor + 1) := by
          rw [dropped, droppedNext]
          rfl
        rcases executesBlockCommentWhile nextInvariant sourceBound
            (Nat.succ_le_of_lt inBounds) with
          ⟨finalState, resultEq, restExec, finalInvariant⟩ |
          ⟨finalState, restExec⟩
        · left
          exact ⟨finalState, stepResult.trans resultEq,
            executesWhileTrueThen loopCondition bodyExec restExec,
            finalInvariant⟩
        · right
          refine ⟨finalState, ?_⟩
          rw [stepResult]
          exact executesWhileTrueThen loopCondition bodyExec restExec
    · have closeBase := invariant.evalBlockCommentClose_notStar inBounds
        (by simpa [byte] using isStar)
      have closeCondition :
          Evaluates lexerProgram state blockCommentCloseCondition
            (.boolean false) state := ⟨15, closeBase⟩
      obtain ⟨next, bodyExec, nextInvariant⟩ :=
        invariant.execBlockCommentStep sourceBound inBounds closeCondition
      have byteNotStar : source[cursor].val ≠ 42 := by
        simpa [byte] using isStar
      have stepResult :
          scanBlockBody (source.drop cursor) cursor =
            scanBlockBody (source.drop (cursor + 1)) (cursor + 1) := by
        rw [dropped]
        cases tail : source.drop (cursor + 1) with
        | nil => rfl
        | cons next rest =>
            rw [scanBlockBody, if_neg]
            intro closes
            exact byteNotStar closes.1
      rcases executesBlockCommentWhile nextInvariant sourceBound
          (Nat.succ_le_of_lt inBounds) with
        ⟨finalState, resultEq, restExec, finalInvariant⟩ |
        ⟨finalState, restExec⟩
      · left
        exact ⟨finalState, stepResult.trans resultEq,
          executesWhileTrueThen loopCondition bodyExec restExec,
          finalInvariant⟩
      · right
        refine ⟨finalState, ?_⟩
        rw [stepResult]
        exact executesWhileTrueThen loopCondition bodyExec restExec
  · have atEnd : cursor = source.length :=
      Nat.le_antisymm cursorBound (Nat.le_of_not_gt inBounds)
    have loopConditionBase := evalCursorLessLimit state cursor source.length
      invariant.cursorLocal invariant.limitLocal
    have loopCondition :
        Evaluates lexerProgram state
          (.binary .less (.local 3) (.local 1)) (.boolean false) state := by
      exact ⟨13, by simpa [inBounds] using loopConditionBase⟩
    left
    refine ⟨state, ?_, executesWhileFalse loopCondition, ?_⟩
    · simp [atEnd, scanBlockBody]
    · simpa [atEnd] using invariant
termination_by source.length - cursor
decreasing_by all_goals omega

theorem executesBlockCommentLoopAndFallback
    (invariant : ScannerState state source start cursor)
    (sourceBound : source.length ≤ 2147483647)
    (cursorBound : cursor ≤ source.length) :
    ∃ finalState,
      Executes lexerProgram state
        (.sequence
          (.whileLoop (.binary .less (.local 3) (.local 1))
            blockCommentLoopBody)
          (.returnValue (some
            (callScanConstructor failedScanFunction (.local 1)))))
        (.returned (some (scanEndValue
          (scanBlockBody (source.drop cursor) cursor)))) finalState := by
  rcases executesBlockCommentWhile invariant sourceBound cursorBound with
    ⟨afterLoop, resultEq, loopExec, finalInvariant⟩ |
    ⟨finalState, loopExec⟩
  · let called := singleArgumentCallState afterLoop
      (.signed .i32 source.length)
    have argumentResult :
        evalExpr 6 lexerProgram afterLoop (.local 1) =
          .done (.signed .i32 source.length) afterLoop :=
      evalLocal_of_local 5 lexerProgram afterLoop 1
        (.signed .i32 source.length) finalInvariant.limitLocal
    have callResult :
        Evaluates lexerProgram afterLoop
          (callScanConstructor failedScanFunction (.local 1))
          (scanEndValue (.failure source.length)) called := by
      exact ⟨8, failedScanCall_after_argument afterLoop
        finalInvariant.wellFormed (.local 1) source.length argumentResult⟩
    have returnExec := executesReturnValue callResult
    refine ⟨called, ?_⟩
    rw [resultEq]
    exact executesSequence loopExec returnExec
  · exact ⟨finalState, executesSequenceReturned loopExec⟩

theorem blockCommentBody_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length) :
    ∃ finalState,
      Executes lexerProgram (scannerParameterState source start)
        blockCommentBody
        (.returned (some (scanEndValue (scanBlockCommentEnd source start))))
        finalState := by
  have initialInvariant := lineCommentLoopInitialState_invariant source start
  have initialBound : start + 2 ≤ source.length := by omega
  obtain ⟨loopFinal, loopExec⟩ :=
    executesBlockCommentLoopAndFallback initialInvariant sourceBound initialBound
  have initializerBound : start + 2 ≤ 2147483647 :=
    Nat.le_trans initialBound sourceBound
  have initializerExec :
      Evaluates lexerProgram (scannerParameterState source start)
        (.binary .add (.local 2) (i32Literal 2))
        (.signed .i32 (start + 2))
        (scannerParameterState source start) :=
    ⟨4, evalI32LocalAddNat (scannerParameterState source start) 2 start 2
      (scannerParameterState_startLocal source start) initializerBound⟩
  let finalState := restoreLocals (scannerParameterState source start) loopFinal
  refine ⟨finalState, ?_⟩
  simpa [blockCommentBody, scanBlockCommentEnd, lineCommentLoopInitialState,
    finalState] using executesLetLocal (type := i32Type) initializerExec loopExec

theorem scanBlockCommentEndFunction_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length) :
    ∃ finalState,
      Evaluates lexerProgram (sourceState source)
        (scannerCall scanBlockCommentEndFunction source start)
        (scanEndValue (scanBlockCommentEnd source start)) finalState := by
  obtain ⟨bodyFinal, bodyExec⟩ :=
    blockCommentBody_executes source start sourceBound openingInBounds
  exact scannerCall_executesBody lexerProgram scanBlockCommentEndFunction
    blockCommentBody
    (scanEndValue (scanBlockCommentEnd source start))
    lexerProgram_finds_scanBlockCommentEndFunction rfl rfl source start
    ⟨bodyFinal, bodyExec⟩

theorem scanBlockCommentEndFunction_executes_spec
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (openingInBounds : start + 1 < source.length) :
    ∃ result finalState,
      Evaluates lexerProgram (sourceState source)
        (scannerCall scanBlockCommentEndFunction source start)
        (scanEndValue result) finalState ∧
      BlockBodyScan (source.drop (start + 2)) (start + 2) result := by
  obtain ⟨finalState, execution⟩ :=
    scanBlockCommentEndFunction_executes source start sourceBound openingInBounds
  exact ⟨scanBlockCommentEnd source start, finalState, execution,
    scanBlockBody_spec (source.drop (start + 2)) (start + 2)⟩

/-! ## Quoted string and character scanning -/

def quotedParameterState
    (source : List Byte) (start : Nat) (delimiter : Byte) : State :=
  (sourceState source).bindLocals
    [(0, .slice i32Type 0 [] 0 source.length),
      (1, .signed .i32 source.length),
      (2, .signed .i32 start),
      (3, .signed .i32 delimiter.val)]

def quotedOffsetState
    (source : List Byte) (start : Nat) (delimiter : Byte) : State :=
  (quotedParameterState source start delimiter).bindLocal 4
    (.signed .i32 (start + 1))

def quotedInitialState
    (source : List Byte) (start : Nat) (delimiter : Byte) : State :=
  (quotedOffsetState source start delimiter).bindLocal 5 (.boolean false)

def quotedParameterStateFrom
    (caller : State) (source : List Byte) (start : Nat) (delimiter : Byte) : State :=
  (clearLocals caller).bindLocals
    [(0, .slice i32Type 0 [] 0 source.length),
      (1, .signed .i32 source.length),
      (2, .signed .i32 start),
      (3, .signed .i32 delimiter.val)]

def quotedOffsetStateFrom
    (caller : State) (source : List Byte) (start : Nat) (delimiter : Byte) : State :=
  (quotedParameterStateFrom caller source start delimiter).bindLocal 4
    (.signed .i32 (start + 1))

def quotedInitialStateFrom
    (caller : State) (source : List Byte) (start : Nat) (delimiter : Byte) : State :=
  (quotedOffsetStateFrom caller source start delimiter).bindLocal 5 (.boolean false)

/-- Stable frame for the represented `scan_quoted_end` loop. Predicate-free
quoted scanning mutates the offset and escaping cells in place while temporary
`byte` locals and constructor-call parameters may append unreachable cells. -/
structure QuotedStateAt (base : Nat)
    (state : State) (source : List Byte) (start offset : Nat)
    (escaping : Bool) (delimiter : Byte) : Prop where
  wellFormed : StateWellFormed state
  nextCell : base + 6 ≤ state.nextCell
  offsetBound : offset ≤ source.length
  sourceCell : state.cellEntry? 0 =
    some { id := 0, value := some (.array (sourceValues source)) }
  sourceLocalId : state.cellId? 0 = some base
  sourceLocalCell : state.cellEntry? base =
    some { id := base, value := some (.slice i32Type 0 [] 0 source.length) }
  limitLocalId : state.cellId? 1 = some (base + 1)
  limitLocalCell : state.cellEntry? (base + 1) =
    some { id := base + 1, value := some (.signed .i32 source.length) }
  startLocalId : state.cellId? 2 = some (base + 2)
  startLocalCell : state.cellEntry? (base + 2) =
    some { id := base + 2, value := some (.signed .i32 start) }
  delimiterLocalId : state.cellId? 3 = some (base + 3)
  delimiterLocalCell : state.cellEntry? (base + 3) =
    some { id := base + 3, value := some (.signed .i32 delimiter.val) }
  offsetLocalId : state.cellId? 4 = some (base + 4)
  offsetLocalCell : state.cellEntry? (base + 4) =
    some { id := base + 4, value := some (.signed .i32 offset) }
  escapingLocalId : state.cellId? 5 = some (base + 5)
  escapingLocalCell : state.cellEntry? (base + 5) =
    some { id := base + 5, value := some (.boolean escaping) }

abbrev QuotedState := QuotedStateAt 1

theorem QuotedStateAt.sourceLocal
    (invariant : QuotedStateAt base state source start offset escaping delimiter) :
    state.local? 0 = some (.slice i32Type 0 [] 0 source.length) := by
  simp [State.local?, State.cell?, invariant.sourceLocalId,
    invariant.sourceLocalCell]

theorem QuotedStateAt.limitLocal
    (invariant : QuotedStateAt base state source start offset escaping delimiter) :
    state.local? 1 = some (.signed .i32 source.length) := by
  simp [State.local?, State.cell?, invariant.limitLocalId,
    invariant.limitLocalCell]

theorem QuotedStateAt.delimiterLocal
    (invariant : QuotedStateAt base state source start offset escaping delimiter) :
    state.local? 3 = some (.signed .i32 delimiter.val) := by
  simp [State.local?, State.cell?, invariant.delimiterLocalId,
    invariant.delimiterLocalCell]

theorem QuotedStateAt.offsetLocal
    (invariant : QuotedStateAt base state source start offset escaping delimiter) :
    state.local? 4 = some (.signed .i32 offset) := by
  simp [State.local?, State.cell?, invariant.offsetLocalId,
    invariant.offsetLocalCell]

theorem QuotedStateAt.escapingLocal
    (invariant : QuotedStateAt base state source start offset escaping delimiter) :
    state.local? 5 = some (.boolean escaping) := by
  simp [State.local?, State.cell?, invariant.escapingLocalId,
    invariant.escapingLocalCell]

theorem evalI32LocalEqualLiteral
    {program : Program}
    (state : State) (id : VarId) (value : Nat) (literal : Int)
    (found : state.local? id = some (.signed .i32 value)) :
    evalExpr 4 program state
      (.binary .equal (.local id) (i32Literal literal)) =
      .done (.boolean (Int.ofNat value == literal)) state := by
  have leftResult := evalLocal_of_local 2 program state id
    (.signed .i32 value) found
  have rightResult :
      evalExpr 3 program state (i32Literal literal) =
        .done (.signed .i32 literal) state := by rfl
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [leftResult]
  simp only
  rw [rightResult]
  simp only [evalBinaryValue, scalarEqual, beq_self_eq_true, if_true]
  rfl

theorem evalI32LocalEqualNatLiteral
    {program : Program}
    (state : State) (id : VarId) (value literal : Nat)
    (found : state.local? id = some (.signed .i32 value)) :
    evalExpr 4 program state
      (.binary .equal (.local id) (i32Literal literal)) =
      .done (.boolean (value == literal)) state := by
  have result := evalI32LocalEqualLiteral (program := program)
    state id value (Int.ofNat literal) found
  rw [intOfNat_beq] at result
  simpa using result

theorem evalI32LocalsEqual
    (state : State) (leftId rightId : VarId) (left right : Nat)
    (leftFound : state.local? leftId = some (.signed .i32 left))
    (rightFound : state.local? rightId = some (.signed .i32 right)) :
    evalExpr 4 lexerProgram state
      (.binary .equal (.local leftId) (.local rightId)) =
      .done (.boolean (left == right)) state := by
  have leftResult := evalLocal_of_local 2 lexerProgram state leftId
    (.signed .i32 left) leftFound
  have rightResult := evalLocal_of_local 2 lexerProgram state rightId
    (.signed .i32 right) rightFound
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [leftResult]
  simp only
  rw [rightResult]
  simp only [evalBinaryValue, scalarEqual, beq_self_eq_true, if_true]
  exact congrArg
    (fun result => (Outcome.done (Value.boolean result) state : Outcome Value))
    (intOfNat_beq left right)

theorem evalI32LocalAddOne
    {program : Program}
    (state : State) (id : VarId) (value : Nat)
    (found : state.local? id = some (.signed .i32 value))
    (bounded : value + 1 ≤ 2147483647)
    (sameTarget : program.target = lexerProgram.target) :
    evalExpr 4 program state
      (.binary .add (.local id) (i32Literal 1)) =
      .done (.signed .i32 (value + 1)) state := by
  have leftResult := evalLocal_of_local 2 program state id
    (.signed .i32 value) found
  have rightResult :
      evalExpr 3 program state (i32Literal 1) =
        .done (.signed .i32 1) state := by rfl
  have wrapped :
      wrapSigned program.target .i32 (Int.ofNat value + 1) =
        Int.ofNat (value + 1) := by
    rw [sameTarget]
    simpa using wrapSigned_i32_ofNat (value + 1) bounded
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [leftResult]
  simp only
  rw [rightResult]
  simp only [evalBinaryValue, beq_self_eq_true, if_true, evalSignedBinary]
  have wrappedCoerced :
      wrapSigned program.target .i32 ((value : Int) + 1) =
        (value : Int) + 1 := by simpa using wrapped
  rw [wrappedCoerced]

theorem QuotedStateAt.evalLoopCondition
    (invariant : QuotedStateAt base state source start offset escaping delimiter) :
    evalExpr 13 lexerProgram state
      (.binary .less (.local 4) (.local 1)) =
      .done (.boolean (offset < source.length)) state :=
  evalLocalLessLocal state offset source.length 4 1
    invariant.offsetLocal invariant.limitLocal

theorem QuotedStateAt.evalSourceByte
    (invariant : QuotedStateAt base state source start offset escaping delimiter)
    (inBounds : offset < source.length) :
    evalExpr 10 lexerProgram state (.index (.local 0) (.local 4)) =
      .done (.signed .i32 (source.get ⟨offset, inBounds⟩).val) state :=
  evalSourceIndexAt state source offset 4 inBounds invariant.sourceLocal
    invariant.offsetLocal invariant.sourceCell

theorem quotedParameterState_well_formed
    (source : List Byte) (start : Nat) (delimiter : Byte) :
    StateWellFormed (quotedParameterState source start delimiter) := by
  unfold quotedParameterState State.bindLocals
  simp only [List.foldl]
  exact bindLocal_preserves_well_formed _ 3 (.signed .i32 delimiter.val)
    (bindLocal_preserves_well_formed _ 2 (.signed .i32 start)
      (bindLocal_preserves_well_formed _ 1 (.signed .i32 source.length)
        (bindLocal_preserves_well_formed _ 0
          (.slice i32Type 0 [] 0 source.length)
          (sourceState_well_formed source))))

theorem quotedParameterState_startLocal
    (source : List Byte) (start : Nat) (delimiter : Byte) :
    (quotedParameterState source start delimiter).local? 2 =
      some (.signed .i32 start) := by
  rfl

theorem quotedParameterStateFrom_startLocal
    (caller : State) (source : List Byte) (start : Nat) (delimiter : Byte)
    (callerWellFormed : StateWellFormed caller) :
    (quotedParameterStateFrom caller source start delimiter).local? 2 =
      some (.signed .i32 start) := by
  let cleared := clearLocals caller
  have clearedWellFormed := clearLocals_well_formed caller callerWellFormed
  have found := bindLocals_finds_cell_after_prefix cleared
    [(0, .slice i32Type 0 [] 0 source.length),
      (1, .signed .i32 source.length)]
    [(3, .signed .i32 delimiter.val)] 2 (.signed .i32 start)
    clearedWellFormed
  have cellId :
      (quotedParameterStateFrom caller source start delimiter).cellId? 2 =
        some (caller.nextCell + 2) := by rfl
  rw [State.local?, cellId]
  simp only [Option.bind_some, State.cell?]
  have foundAtParameter :
      (quotedParameterStateFrom caller source start delimiter).cellEntry?
          (caller.nextCell + 2) =
        some { id := caller.nextCell + 2, value := some (.signed .i32 start) } := by
    simpa [quotedParameterStateFrom, cleared, clearLocals, Nat.add_assoc] using found
  rw [foundAtParameter]
  rfl

theorem quotedInitialState_invariant
    (source : List Byte) (start : Nat) (delimiter : Byte)
    (startInBounds : start < source.length) :
    QuotedState (quotedInitialState source start delimiter)
      source start (start + 1) false delimiter := by
  have offsetWellFormed := bindLocal_preserves_well_formed _ 4
    (.signed .i32 (start + 1))
    (quotedParameterState_well_formed source start delimiter)
  have escapingCell :
      (quotedInitialState source start delimiter).cellEntry? 6 =
        some { id := 6, value := some (.boolean false) } := by
    have fresh := bindCell_finds_fresh_cell
      (quotedOffsetState source start delimiter) 5
      (some (.boolean false)) offsetWellFormed
    have nextCell :
        (quotedOffsetState source start delimiter).nextCell = 6 := by rfl
    rw [nextCell] at fresh
    simpa [quotedInitialState, State.bindLocal] using fresh
  constructor
  · exact bindLocal_preserves_well_formed _ 5 (.boolean false)
      (bindLocal_preserves_well_formed _ 4 (.signed .i32 (start + 1))
        (quotedParameterState_well_formed source start delimiter))
  · change 7 ≤ 7
    decide
  · omega
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · exact escapingCell

theorem quotedInitialStateFrom_invariant
    (caller : State) (source : List Byte) (start : Nat) (delimiter : Byte)
    (callerWellFormed : StateWellFormed caller)
    (sourceCell : caller.cellEntry? 0 =
      some { id := 0, value := some (.array (sourceValues source)) })
    (startInBounds : start < source.length) :
    QuotedStateAt caller.nextCell
      (quotedInitialStateFrom caller source start delimiter)
      source start (start + 1) false delimiter := by
  let cleared := clearLocals caller
  let sourceValue : Value := .slice i32Type 0 [] 0 source.length
  let limitValue : Value := .signed .i32 source.length
  let startValue : Value := .signed .i32 start
  let delimiterValue : Value := .signed .i32 delimiter.val
  let offsetValue : Value := .signed .i32 (start + 1)
  let escapingValue : Value := .boolean false
  let bindings : List (VarId × Value) :=
    [(0, sourceValue), (1, limitValue), (2, startValue),
      (3, delimiterValue), (4, offsetValue), (5, escapingValue)]
  have clearedWellFormed : StateWellFormed cleared :=
    clearLocals_well_formed caller callerWellFormed
  have initialEq :
      quotedInitialStateFrom caller source start delimiter =
        cleared.bindLocals bindings := by
    rfl
  have sourceMember :
      { id := 0, value := some (.array (sourceValues source)) } ∈ caller.cells :=
    List.mem_of_find?_eq_some sourceCell
  have sourceOld : 0 < caller.nextCell :=
    callerWellFormed.cellIdsBelowNext _ sourceMember
  have sourcePreserved := bindLocals_preserves_old_cell cleared bindings 0
    (by simpa [cleared, clearLocals] using sourceOld)
  have sourceBound := bindLocals_finds_cell_after_prefix cleared []
    [(1, limitValue), (2, startValue), (3, delimiterValue),
      (4, offsetValue), (5, escapingValue)] 0 sourceValue clearedWellFormed
  have limitBound := bindLocals_finds_cell_after_prefix cleared
    [(0, sourceValue)]
    [(2, startValue), (3, delimiterValue), (4, offsetValue),
      (5, escapingValue)] 1 limitValue clearedWellFormed
  have startBound := bindLocals_finds_cell_after_prefix cleared
    [(0, sourceValue), (1, limitValue)]
    [(3, delimiterValue), (4, offsetValue), (5, escapingValue)]
    2 startValue clearedWellFormed
  have delimiterBound := bindLocals_finds_cell_after_prefix cleared
    [(0, sourceValue), (1, limitValue), (2, startValue)]
    [(4, offsetValue), (5, escapingValue)] 3 delimiterValue clearedWellFormed
  have offsetBound := bindLocals_finds_cell_after_prefix cleared
    [(0, sourceValue), (1, limitValue), (2, startValue),
      (3, delimiterValue)] [(5, escapingValue)] 4 offsetValue clearedWellFormed
  have escapingBound := bindLocals_finds_cell_after_prefix cleared
    [(0, sourceValue), (1, limitValue), (2, startValue),
      (3, delimiterValue), (4, offsetValue)] [] 5 escapingValue
      clearedWellFormed
  rw [initialEq]
  constructor
  · exact bindLocals_preserves_well_formed cleared bindings clearedWellFormed
  · rw [bindLocals_nextCell]
    simp [bindings, cleared, clearLocals]
  · omega
  · rw [sourcePreserved]
    change caller.cellEntry? 0 = _
    exact sourceCell
  · rfl
  · simpa [bindings, sourceValue, cleared, clearLocals, Nat.add_comm,
      Nat.add_left_comm, Nat.add_assoc] using sourceBound
  · rfl
  · simpa [bindings, limitValue, cleared, clearLocals, Nat.add_comm,
      Nat.add_left_comm, Nat.add_assoc] using limitBound
  · rfl
  · simpa [bindings, startValue, cleared, clearLocals, Nat.add_comm,
      Nat.add_left_comm, Nat.add_assoc] using startBound
  · rfl
  · simpa [bindings, delimiterValue, cleared, clearLocals, Nat.add_comm,
      Nat.add_left_comm, Nat.add_assoc] using delimiterBound
  · rfl
  · simpa [bindings, offsetValue, cleared, clearLocals, Nat.add_comm,
      Nat.add_left_comm, Nat.add_assoc] using offsetBound
  · rfl
  · simpa [bindings, escapingValue, cleared, clearLocals, Nat.add_comm,
      Nat.add_left_comm, Nat.add_assoc] using escapingBound

def quotedByteState (state : State) (byte : Byte) : State :=
  state.bindLocal 6 (.signed .i32 byte.val)

theorem QuotedStateAt.afterByteBinding
    (invariant : QuotedStateAt base state source start offset escaping delimiter)
    (byte : Byte) :
    QuotedStateAt base (quotedByteState state byte)
      source start offset escaping delimiter := by
  have old (cell : Nat) (bounded : cell < base + 6) : cell < state.nextCell :=
    Nat.lt_of_lt_of_le bounded invariant.nextCell
  constructor
  · exact bindLocal_preserves_well_formed state 6 (.signed .i32 byte.val)
      invariant.wellFormed
  · simpa [quotedByteState, State.bindLocal, State.bindCell] using
      Nat.le_trans invariant.nextCell (Nat.le_succ state.nextCell)
  · exact invariant.offsetBound
  · exact (bindCell_preserves_old_cell state 6
      (some (.signed .i32 byte.val)) 0 (old 0 (by omega))).trans
      invariant.sourceCell
  · simpa [quotedByteState, State.bindLocal, State.bindCell, State.cellId?]
      using invariant.sourceLocalId
  · exact (bindCell_preserves_old_cell state 6
      (some (.signed .i32 byte.val)) base (old base (by omega))).trans
      invariant.sourceLocalCell
  · simpa [quotedByteState, State.bindLocal, State.bindCell, State.cellId?]
      using invariant.limitLocalId
  · exact (bindCell_preserves_old_cell state 6
      (some (.signed .i32 byte.val)) (base + 1) (old (base + 1) (by omega))).trans
      invariant.limitLocalCell
  · simpa [quotedByteState, State.bindLocal, State.bindCell, State.cellId?]
      using invariant.startLocalId
  · exact (bindCell_preserves_old_cell state 6
      (some (.signed .i32 byte.val)) (base + 2) (old (base + 2) (by omega))).trans
      invariant.startLocalCell
  · simpa [quotedByteState, State.bindLocal, State.bindCell, State.cellId?]
      using invariant.delimiterLocalId
  · exact (bindCell_preserves_old_cell state 6
      (some (.signed .i32 byte.val)) (base + 3) (old (base + 3) (by omega))).trans
      invariant.delimiterLocalCell
  · simpa [quotedByteState, State.bindLocal, State.bindCell, State.cellId?]
      using invariant.offsetLocalId
  · exact (bindCell_preserves_old_cell state 6
      (some (.signed .i32 byte.val)) (base + 4) (old (base + 4) (by omega))).trans
      invariant.offsetLocalCell
  · simpa [quotedByteState, State.bindLocal, State.bindCell, State.cellId?]
      using invariant.escapingLocalId
  · exact (bindCell_preserves_old_cell state 6
      (some (.signed .i32 byte.val)) (base + 5) (old (base + 5) (by omega))).trans
      invariant.escapingLocalCell

theorem quotedByteState_local
    (invariant : QuotedStateAt base state source start offset escaping delimiter)
    (byte : Byte) :
    (quotedByteState state byte).local? 6 = some (.signed .i32 byte.val) := by
  have fresh := bindCell_finds_fresh_cell state 6
    (some (.signed .i32 byte.val)) invariant.wellFormed
  simp only [quotedByteState, State.bindLocal, State.local?, State.cellId?,
    State.bindCell, List.find?_cons, beq_self_eq_true]
  exact congrArg (fun entry => entry.bind Cell.value) fresh

def quotedEscapingState (base : Nat) (state : State) (escaping : Bool) : State :=
  { state with cells := replaceCell state.cells (base + 5) (.boolean escaping) }

def quotedOffsetAssignedState (base : Nat) (state : State) (offset : Nat) : State :=
  { state with cells := replaceCell state.cells (base + 4) (.signed .i32 offset) }

theorem QuotedStateAt.assignEscaping
    (invariant : QuotedStateAt base state source start offset oldEscaping delimiter)
    (escaping : Bool) :
    state.assignCell (base + 5) (.boolean escaping) =
      some (quotedEscapingState base state escaping) := by
  simp [State.assignCell, invariant.escapingLocalCell, quotedEscapingState]

theorem QuotedStateAt.afterEscapingAssignment
    (invariant : QuotedStateAt base state source start offset oldEscaping delimiter)
    (escaping : Bool) :
    QuotedStateAt base (quotedEscapingState base state escaping)
      source start offset escaping delimiter := by
  have assigned := invariant.assignEscaping escaping
  constructor
  · exact assignCell_preserves_well_formed invariant.wellFormed assigned
  · simpa [quotedEscapingState] using invariant.nextCell
  · exact invariant.offsetBound
  · exact (assignCell_preserves_other assigned (by omega : 0 ≠ base + 5)).trans
      invariant.sourceCell
  · simpa [quotedEscapingState, State.cellId?] using invariant.sourceLocalId
  · exact (assignCell_preserves_other assigned (by omega : base ≠ base + 5)).trans
      invariant.sourceLocalCell
  · simpa [quotedEscapingState, State.cellId?] using invariant.limitLocalId
  · exact (assignCell_preserves_other assigned (by omega : base + 1 ≠ base + 5)).trans
      invariant.limitLocalCell
  · simpa [quotedEscapingState, State.cellId?] using invariant.startLocalId
  · exact (assignCell_preserves_other assigned (by omega : base + 2 ≠ base + 5)).trans
      invariant.startLocalCell
  · simpa [quotedEscapingState, State.cellId?] using invariant.delimiterLocalId
  · exact (assignCell_preserves_other assigned (by omega : base + 3 ≠ base + 5)).trans
      invariant.delimiterLocalCell
  · simpa [quotedEscapingState, State.cellId?] using invariant.offsetLocalId
  · exact (assignCell_preserves_other assigned (by omega : base + 4 ≠ base + 5)).trans
      invariant.offsetLocalCell
  · simpa [quotedEscapingState, State.cellId?] using invariant.escapingLocalId
  · exact assignCell_finds_assigned assigned

theorem QuotedStateAt.assignOffset
    (invariant : QuotedStateAt base state source start oldOffset escaping delimiter)
    (offset : Nat) :
    state.assignCell (base + 4) (.signed .i32 offset) =
      some (quotedOffsetAssignedState base state offset) := by
  simp [State.assignCell, invariant.offsetLocalCell, quotedOffsetAssignedState]

theorem QuotedStateAt.afterOffsetAssignment
    (invariant : QuotedStateAt base state source start oldOffset escaping delimiter)
    (offset : Nat) (offsetBound : offset ≤ source.length) :
    QuotedStateAt base (quotedOffsetAssignedState base state offset)
      source start offset escaping delimiter := by
  have assigned := invariant.assignOffset offset
  constructor
  · exact assignCell_preserves_well_formed invariant.wellFormed assigned
  · simpa [quotedOffsetAssignedState] using invariant.nextCell
  · exact offsetBound
  · exact (assignCell_preserves_other assigned (by omega : 0 ≠ base + 4)).trans
      invariant.sourceCell
  · simpa [quotedOffsetAssignedState, State.cellId?] using invariant.sourceLocalId
  · exact (assignCell_preserves_other assigned (by omega : base ≠ base + 4)).trans
      invariant.sourceLocalCell
  · simpa [quotedOffsetAssignedState, State.cellId?] using invariant.limitLocalId
  · exact (assignCell_preserves_other assigned (by omega : base + 1 ≠ base + 4)).trans
      invariant.limitLocalCell
  · simpa [quotedOffsetAssignedState, State.cellId?] using invariant.startLocalId
  · exact (assignCell_preserves_other assigned (by omega : base + 2 ≠ base + 4)).trans
      invariant.startLocalCell
  · simpa [quotedOffsetAssignedState, State.cellId?] using invariant.delimiterLocalId
  · exact (assignCell_preserves_other assigned (by omega : base + 3 ≠ base + 4)).trans
      invariant.delimiterLocalCell
  · simpa [quotedOffsetAssignedState, State.cellId?] using invariant.offsetLocalId
  · exact assignCell_finds_assigned assigned
  · simpa [quotedOffsetAssignedState, State.cellId?] using invariant.escapingLocalId
  · exact (assignCell_preserves_other assigned (by omega : base + 5 ≠ base + 4)).trans
      invariant.escapingLocalCell

theorem QuotedStateAt.execEscapingSet
    (invariant : QuotedStateAt base state source start offset oldEscaping delimiter)
    (escaping : Bool) :
    execStmt 7 lexerProgram state
      (assignLocal 5 (.value (.boolean escaping))) =
      .done .next (quotedEscapingState base state escaping) := by
  let next := quotedEscapingState base state escaping
  have assigned : state.assignCell (base + 5) (.boolean escaping) = some next :=
    invariant.assignEscaping escaping
  have placeResult :
      evalPlace 5 lexerProgram state (.local 5) =
        .done { root := base + 5, projections := [], value := some (.boolean oldEscaping) }
          state := by
    rw [Lanius.Semantics.evalPlace.eq_def]
    simp only
    rw [invariant.escapingLocalId]
    simp only
    rw [invariant.escapingLocalCell]
  have rightResult :
      evalExpr 5 lexerProgram state (.value (.boolean escaping)) =
        .done (.boolean escaping) state := by rfl
  have writeResult :
      writeResolvedPlace state
        { root := base + 5, projections := [], value := some (.boolean oldEscaping) }
        (.boolean escaping) = .ok next := by
    simp [writeResolvedPlace, assigned]
  have assignmentResult :
      evalExpr 6 lexerProgram state
        (.assign .set (.local 5) (.value (.boolean escaping))) =
        .done .unit next := by
    rw [Lanius.Semantics.evalExpr.eq_def]
    simp only
    rw [placeResult]
    simp only
    rw [rightResult]
    simp only [evalAssignValue, assignOpBinary?]
    rw [writeResult]
  rw [Lanius.Semantics.execStmt.eq_def]
  simp only [assignLocal]
  rw [assignmentResult]

theorem QuotedStateAt.execOffsetIncrement
    (invariant : QuotedStateAt base state source start offset escaping delimiter)
    (bounded : offset + 1 ≤ 2147483647) :
    execStmt 11 lexerProgram state (incrementLocal 4 1) =
      .done .next (quotedOffsetAssignedState base state (offset + 1)) := by
  let next := quotedOffsetAssignedState base state (offset + 1)
  have assigned : state.assignCell (base + 4) (.signed .i32 (offset + 1)) = some next :=
    invariant.assignOffset (offset + 1)
  have placeResult :
      evalPlace 9 lexerProgram state (.local 4) =
        .done { root := base + 4, projections := [], value := some (.signed .i32 offset) }
          state := by
    rw [Lanius.Semantics.evalPlace.eq_def]
    simp only
    rw [invariant.offsetLocalId]
    simp only
    rw [invariant.offsetLocalCell]
  have rightResult :
      evalExpr 9 lexerProgram state (i32Literal 1) =
        .done (.signed .i32 1) state := by rfl
  have wrapped :
      wrapSigned lexerProgram.target .i32 (Int.ofNat offset + 1) =
        Int.ofNat (offset + 1) := by
    simpa using wrapSigned_i32_ofNat (offset + 1) bounded
  have arithmeticResult :
      evalAssignValue lexerProgram.target .add
        (some (.signed .i32 offset)) (.signed .i32 1) =
        .ok (.signed .i32 (offset + 1)) := by
    simp only [evalAssignValue, assignOpBinary?, evalBinaryValue,
      beq_self_eq_true, if_true, evalSignedBinary]
    have wrappedCoerced :
        wrapSigned lexerProgram.target .i32 ((offset : Int) + 1) =
          (offset : Int) + 1 := by simpa using wrapped
    exact congrArg
      (fun value => (Except.ok (.signed .i32 value) : Except Trap Value))
      wrappedCoerced
  have writeResult :
      writeResolvedPlace state
        { root := base + 4, projections := [], value := some (.signed .i32 offset) }
        (.signed .i32 (offset + 1)) = .ok next := by
    simp [writeResolvedPlace, assigned]
  have assignmentResult :
      evalExpr 10 lexerProgram state
        (.assign .add (.local 4) (i32Literal 1)) =
        .done .unit next := by
    rw [Lanius.Semantics.evalExpr.eq_def]
    simp only
    rw [placeResult]
    simp only
    rw [rightResult]
    simp only
    rw [arithmeticResult]
    simp only
    rw [writeResult]
  rw [Lanius.Semantics.execStmt.eq_def]
  simp only [incrementLocal]
  rw [assignmentResult]

theorem QuotedStateAt.restoreLocals
    (beforeInvariant :
      QuotedStateAt base before source start beforeOffset beforeEscaping delimiter)
    (completedInvariant :
      QuotedStateAt base completed source start offset escaping delimiter)
    (domain : CellDomainExtension before completed) :
    QuotedStateAt base (Lanius.Semantics.restoreLocals before completed)
      source start offset escaping delimiter := by
  constructor
  · exact domain.restoreLocals_well_formed beforeInvariant.wellFormed
      completedInvariant.wellFormed
  · exact completedInvariant.nextCell
  · exact completedInvariant.offsetBound
  · exact completedInvariant.sourceCell
  · exact beforeInvariant.sourceLocalId
  · exact completedInvariant.sourceLocalCell
  · exact beforeInvariant.limitLocalId
  · exact completedInvariant.limitLocalCell
  · exact beforeInvariant.startLocalId
  · exact completedInvariant.startLocalCell
  · exact beforeInvariant.delimiterLocalId
  · exact completedInvariant.delimiterLocalCell
  · exact beforeInvariant.offsetLocalId
  · exact completedInvariant.offsetLocalCell
  · exact beforeInvariant.escapingLocalId
  · exact completedInvariant.escapingLocalCell

theorem QuotedStateAt.execEscapedLoopBody
    (invariant : QuotedStateAt base state source start offset true delimiter)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : offset < source.length) :
    ∃ next,
      Executes lexerProgram state quotedLoopBody .next next ∧
      QuotedStateAt base next source start (offset + 1) false delimiter ∧
      CellDomainExtension state next := by
  let byte := source.get ⟨offset, inBounds⟩
  let withByte := quotedByteState state byte
  let withoutEscaping := quotedEscapingState base withByte false
  let completed := quotedOffsetAssignedState base withoutEscaping (offset + 1)
  let next := Lanius.Semantics.restoreLocals state completed
  have byteInvariant :
      QuotedStateAt base withByte source start offset true delimiter := by
    exact invariant.afterByteBinding byte
  have escapingResult :
      evalExpr 2 lexerProgram withByte (.local 5) =
        .done (.boolean true) withByte :=
    evalLocal_of_local 1 lexerProgram withByte 5 (.boolean true)
      byteInvariant.escapingLocal
  have escapingExec :
      Executes lexerProgram withByte
        (assignLocal 5 (.value (.boolean false))) .next withoutEscaping := by
    exact ⟨7, byteInvariant.execEscapingSet false⟩
  have withoutEscapingInvariant :
      QuotedStateAt base withoutEscaping source start offset false delimiter :=
    byteInvariant.afterEscapingAssignment false
  have incrementBound : offset + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound
  have incrementExec :
      Executes lexerProgram withoutEscaping (incrementLocal 4 1) .next completed := by
    exact ⟨11, withoutEscapingInvariant.execOffsetIncrement incrementBound⟩
  have completedInvariant :
      QuotedStateAt base completed source start (offset + 1) false delimiter :=
    withoutEscapingInvariant.afterOffsetAssignment (offset + 1)
      (Nat.succ_le_of_lt inBounds)
  have branchExec :
      Executes lexerProgram withByte
        (.sequence
          (assignLocal 5 (.value (.boolean false)))
          (incrementLocal 4 1)) .next completed :=
    executesSequence escapingExec incrementExec
  have ifExec :
      Executes lexerProgram withByte
        (.ifThenElse (.local 5)
          (.sequence
            (assignLocal 5 (.value (.boolean false)))
            (incrementLocal 4 1))
          quotedUnescapedBody) .next completed :=
    executesIfTrue ⟨2, escapingResult⟩ branchExec
  have initializerExec :
      Evaluates lexerProgram state (.index (.local 0) (.local 4))
        (.signed .i32 byte.val) state := by
    exact ⟨10, by simpa [byte] using invariant.evalSourceByte inBounds⟩
  have bodyExec : Executes lexerProgram state quotedLoopBody .next next := by
    simpa [quotedLoopBody, withByte, completed, next] using
      executesLetLocal (id := 6) (type := i32Type) initializerExec ifExec
  have byteDomain : CellDomainExtension state withByte := by
    exact bindLocal_domain_extends state 6 (.signed .i32 byte.val)
  have escapingAssigned :
      withByte.assignCell (base + 5) (.boolean false) = some withoutEscaping :=
    byteInvariant.assignEscaping false
  have escapingDomain : CellDomainExtension withByte withoutEscaping :=
    assignCell_domain_extends escapingAssigned
  have offsetAssigned :
      withoutEscaping.assignCell (base + 4) (.signed .i32 (offset + 1)) = some completed :=
    withoutEscapingInvariant.assignOffset (offset + 1)
  have offsetDomain : CellDomainExtension withoutEscaping completed :=
    assignCell_domain_extends offsetAssigned
  have completedDomain : CellDomainExtension state completed :=
    byteDomain.trans (escapingDomain.trans offsetDomain)
  have nextDomain : CellDomainExtension state next := by
    exact completedDomain.restoreLocals
  have nextInvariant :
      QuotedStateAt base next source start (offset + 1) false delimiter := by
    exact invariant.restoreLocals completedInvariant completedDomain
  exact ⟨next, bodyExec, nextInvariant, nextDomain⟩

theorem QuotedStateAt.execNewlineLoopBody
    (invariant : QuotedStateAt base state source start offset false delimiter)
    (inBounds : offset < source.length)
    (isNewline : (source.get ⟨offset, inBounds⟩).val = 10) :
    ∃ finalState,
      Executes lexerProgram state quotedLoopBody
        (.returned (some (scanEndValue (.failure offset)))) finalState := by
  let byte := source.get ⟨offset, inBounds⟩
  let withByte := quotedByteState state byte
  let called := singleArgumentCallState withByte (.signed .i32 offset)
  let finalState := Lanius.Semantics.restoreLocals state called
  have byteInvariant :
      QuotedStateAt base withByte source start offset false delimiter :=
    invariant.afterByteBinding byte
  have escapingResult :
      Evaluates lexerProgram withByte (.local 5) (.boolean false) withByte := by
    exact ⟨2, evalLocal_of_local 1 lexerProgram withByte 5 (.boolean false)
      byteInvariant.escapingLocal⟩
  have newlineBase := evalI32LocalEqualLiteral (program := lexerProgram)
    withByte 6 byte.val 10
    (quotedByteState_local invariant byte)
  have byteIsNewline : byte.val = 10 := by
    simpa [byte] using isNewline
  have newlineBoolean : (Int.ofNat byte.val == (10 : Int)) = true := by
    simp [byteIsNewline]
  have newlineResult :
      Evaluates lexerProgram withByte
        (.binary .equal (.local 6) (i32Literal 10)) (.boolean true) withByte := by
    refine ⟨4, ?_⟩
    rw [newlineBoolean] at newlineBase
    exact newlineBase
  have argumentResult :
      evalExpr 6 lexerProgram withByte (.local 4) =
        .done (.signed .i32 offset) withByte :=
    evalLocal_of_local 5 lexerProgram withByte 4 (.signed .i32 offset)
      byteInvariant.offsetLocal
  have callResult :
      Evaluates lexerProgram withByte
        (callScanConstructor failedScanFunction (.local 4))
        (scanEndValue (.failure offset)) called := by
    exact ⟨8, failedScanCall_after_argument withByte byteInvariant.wellFormed
      (.local 4) offset argumentResult⟩
  have returnExec :
      Executes lexerProgram withByte
        (.returnValue (some
          (callScanConstructor failedScanFunction (.local 4))))
        (.returned (some (scanEndValue (.failure offset)))) called :=
    executesReturnValue callResult
  have newlineIfExec :
      Executes lexerProgram withByte
        (.ifThenElse (.binary .equal (.local 6) (i32Literal 10))
          (.returnValue (some
            (callScanConstructor failedScanFunction (.local 4))))
          .skip)
        (.returned (some (scanEndValue (.failure offset)))) called :=
    executesIfTrue newlineResult returnExec
  have unescapedExec :
      Executes lexerProgram withByte quotedUnescapedBody
        (.returned (some (scanEndValue (.failure offset)))) called := by
    unfold quotedUnescapedBody
    exact executesSequenceReturned newlineIfExec
  have branchExec :
      Executes lexerProgram withByte
        (.ifThenElse (.local 5)
          (.sequence
            (assignLocal 5 (.value (.boolean false)))
            (incrementLocal 4 1))
          quotedUnescapedBody)
        (.returned (some (scanEndValue (.failure offset)))) called :=
    executesIfFalse escapingResult unescapedExec
  have initializerExec :
      Evaluates lexerProgram state (.index (.local 0) (.local 4))
        (.signed .i32 byte.val) state := by
    exact ⟨10, by simpa [byte] using invariant.evalSourceByte inBounds⟩
  have bodyExec :
      Executes lexerProgram state quotedLoopBody
        (.returned (some (scanEndValue (.failure offset)))) finalState := by
    simpa [quotedLoopBody, withByte, called, finalState] using
      executesLetLocal (id := 6) (type := i32Type) initializerExec branchExec
  exact ⟨finalState, bodyExec⟩

theorem QuotedStateAt.execDelimiterLoopBody
    (invariant : QuotedStateAt base state source start offset false delimiter)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : offset < source.length)
    (notNewline : (source.get ⟨offset, inBounds⟩).val ≠ 10)
    (isDelimiter : source.get ⟨offset, inBounds⟩ = delimiter) :
    ∃ finalState,
      Executes lexerProgram state quotedLoopBody
        (.returned (some (scanEndValue (.success (offset + 1))))) finalState := by
  let byte := source.get ⟨offset, inBounds⟩
  let withByte := quotedByteState state byte
  let called := singleArgumentCallState withByte (.signed .i32 (offset + 1))
  let finalState := Lanius.Semantics.restoreLocals state called
  have byteInvariant :
      QuotedStateAt base withByte source start offset false delimiter :=
    invariant.afterByteBinding byte
  have escapingResult :
      Evaluates lexerProgram withByte (.local 5) (.boolean false) withByte := by
    exact ⟨2, evalLocal_of_local 1 lexerProgram withByte 5 (.boolean false)
      byteInvariant.escapingLocal⟩
  have byteNotNewline : byte.val ≠ 10 := by
    simpa [byte] using notNewline
  have newlineBoolean : (Int.ofNat byte.val == (10 : Int)) = false := by
    apply Bool.eq_false_iff.mpr
    intro equal
    apply byteNotNewline
    have intEqual : Int.ofNat byte.val = (10 : Int) := by
      simpa using equal
    exact Int.ofNat.inj intEqual
  have newlineBase := evalI32LocalEqualLiteral (program := lexerProgram)
    withByte 6 byte.val 10
    (quotedByteState_local invariant byte)
  rw [newlineBoolean] at newlineBase
  have newlineResult :
      Evaluates lexerProgram withByte
        (.binary .equal (.local 6) (i32Literal 10)) (.boolean false) withByte :=
    ⟨4, newlineBase⟩
  have newlineIfExec :
      Executes lexerProgram withByte
        (.ifThenElse (.binary .equal (.local 6) (i32Literal 10))
          (.returnValue (some
            (callScanConstructor failedScanFunction (.local 4))))
          .skip) .next withByte :=
    executesIfFalse newlineResult (executesSkip lexerProgram withByte)
  have byteIsDelimiter : byte = delimiter := by
    simpa [byte] using isDelimiter
  have delimiterBoolean : (byte.val == delimiter.val) = true := by
    simp [byteIsDelimiter]
  have delimiterBase := evalI32LocalsEqual withByte 6 3 byte.val delimiter.val
    (quotedByteState_local invariant byte) byteInvariant.delimiterLocal
  rw [delimiterBoolean] at delimiterBase
  have delimiterResult :
      Evaluates lexerProgram withByte
        (.binary .equal (.local 6) (.local 3)) (.boolean true) withByte :=
    ⟨4, delimiterBase⟩
  have incrementBound : offset + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound
  have argumentResult := evalI32LocalAddOne (program := lexerProgram)
    withByte 4 offset
    byteInvariant.offsetLocal incrementBound rfl
  have callResult :
      Evaluates lexerProgram withByte
        (callScanConstructor successfulScanFunction
          (.binary .add (.local 4) (i32Literal 1)))
        (scanEndValue (.success (offset + 1))) called := by
    exact ⟨8, successfulScanCall_after_argument withByte byteInvariant.wellFormed
      (.binary .add (.local 4) (i32Literal 1)) (offset + 1)
      (evalExpr_done_at_larger_fuel (by decide : 4 ≤ 6) argumentResult)⟩
  have returnExec :
      Executes lexerProgram withByte
        (.returnValue (some (callScanConstructor successfulScanFunction
          (.binary .add (.local 4) (i32Literal 1)))))
        (.returned (some (scanEndValue (.success (offset + 1))))) called :=
    executesReturnValue callResult
  have delimiterIfExec :
      Executes lexerProgram withByte
        (.ifThenElse (.binary .equal (.local 6) (.local 3))
          (.returnValue (some (callScanConstructor successfulScanFunction
            (.binary .add (.local 4) (i32Literal 1)))))
          .skip)
        (.returned (some (scanEndValue (.success (offset + 1))))) called :=
    executesIfTrue delimiterResult returnExec
  have unescapedExec :
      Executes lexerProgram withByte quotedUnescapedBody
        (.returned (some (scanEndValue (.success (offset + 1))))) called := by
    unfold quotedUnescapedBody
    exact executesSequence newlineIfExec
      (executesSequenceReturned delimiterIfExec)
  have branchExec :
      Executes lexerProgram withByte
        (.ifThenElse (.local 5)
          (.sequence
            (assignLocal 5 (.value (.boolean false)))
            (incrementLocal 4 1))
          quotedUnescapedBody)
        (.returned (some (scanEndValue (.success (offset + 1))))) called :=
    executesIfFalse escapingResult unescapedExec
  have initializerExec :
      Evaluates lexerProgram state (.index (.local 0) (.local 4))
        (.signed .i32 byte.val) state := by
    exact ⟨10, by simpa [byte] using invariant.evalSourceByte inBounds⟩
  have bodyExec :
      Executes lexerProgram state quotedLoopBody
        (.returned (some (scanEndValue (.success (offset + 1))))) finalState := by
    simpa [quotedLoopBody, withByte, called, finalState] using
      executesLetLocal (id := 6) (type := i32Type) initializerExec branchExec
  exact ⟨finalState, bodyExec⟩

theorem QuotedStateAt.execBeginEscapeLoopBody
    (invariant : QuotedStateAt base state source start offset false delimiter)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : offset < source.length)
    (notNewline : (source.get ⟨offset, inBounds⟩).val ≠ 10)
    (notDelimiter : source.get ⟨offset, inBounds⟩ ≠ delimiter)
    (isEscape : (source.get ⟨offset, inBounds⟩).val = 92) :
    ∃ next,
      Executes lexerProgram state quotedLoopBody .next next ∧
      QuotedStateAt base next source start (offset + 1) true delimiter ∧
      CellDomainExtension state next := by
  let byte := source.get ⟨offset, inBounds⟩
  let withByte := quotedByteState state byte
  let withEscaping := quotedEscapingState base withByte true
  let completed := quotedOffsetAssignedState base withEscaping (offset + 1)
  let next := Lanius.Semantics.restoreLocals state completed
  have byteInvariant :
      QuotedStateAt base withByte source start offset false delimiter :=
    invariant.afterByteBinding byte
  have escapingResult :
      Evaluates lexerProgram withByte (.local 5) (.boolean false) withByte := by
    exact ⟨2, evalLocal_of_local 1 lexerProgram withByte 5 (.boolean false)
      byteInvariant.escapingLocal⟩
  have byteNotNewline : byte.val ≠ 10 := by simpa [byte] using notNewline
  have newlineBoolean : (Int.ofNat byte.val == (10 : Int)) = false := by
    apply Bool.eq_false_iff.mpr
    intro equal
    apply byteNotNewline
    have intEqual : Int.ofNat byte.val = (10 : Int) := by simpa using equal
    exact Int.ofNat.inj intEqual
  have newlineBase := evalI32LocalEqualLiteral (program := lexerProgram)
    withByte 6 byte.val 10
    (quotedByteState_local invariant byte)
  rw [newlineBoolean] at newlineBase
  have newlineIfExec :
      Executes lexerProgram withByte
        (.ifThenElse (.binary .equal (.local 6) (i32Literal 10))
          (.returnValue (some
            (callScanConstructor failedScanFunction (.local 4))))
          .skip) .next withByte :=
    executesIfFalse ⟨4, newlineBase⟩ (executesSkip lexerProgram withByte)
  have byteNotDelimiter : byte ≠ delimiter := by
    simpa [byte] using notDelimiter
  have byteValueNotDelimiter : byte.val ≠ delimiter.val := by
    intro equal
    exact byteNotDelimiter (Fin.ext equal)
  have delimiterBoolean : (byte.val == delimiter.val) = false := by
    exact Bool.eq_false_iff.mpr (by simpa using byteValueNotDelimiter)
  have delimiterBase := evalI32LocalsEqual withByte 6 3 byte.val delimiter.val
    (quotedByteState_local invariant byte) byteInvariant.delimiterLocal
  rw [delimiterBoolean] at delimiterBase
  have delimiterIfExec :
      Executes lexerProgram withByte
        (.ifThenElse (.binary .equal (.local 6) (.local 3))
          (.returnValue (some (callScanConstructor successfulScanFunction
            (.binary .add (.local 4) (i32Literal 1)))))
          .skip) .next withByte :=
    executesIfFalse ⟨4, delimiterBase⟩ (executesSkip lexerProgram withByte)
  have byteIsEscape : byte.val = 92 := by simpa [byte] using isEscape
  have escapeBoolean : (Int.ofNat byte.val == (92 : Int)) = true := by
    simp [byteIsEscape]
  have escapeBase := evalI32LocalEqualLiteral (program := lexerProgram)
    withByte 6 byte.val 92
    (quotedByteState_local invariant byte)
  rw [escapeBoolean] at escapeBase
  have escapingExec :
      Executes lexerProgram withByte
        (assignLocal 5 (.value (.boolean true))) .next withEscaping :=
    ⟨7, byteInvariant.execEscapingSet true⟩
  have escapeIfExec :
      Executes lexerProgram withByte
        (.ifThenElse (.binary .equal (.local 6) (i32Literal 92))
          (assignLocal 5 (.value (.boolean true))) .skip) .next withEscaping :=
    executesIfTrue ⟨4, escapeBase⟩ escapingExec
  have withEscapingInvariant :
      QuotedStateAt base withEscaping source start offset true delimiter :=
    byteInvariant.afterEscapingAssignment true
  have incrementBound : offset + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound
  have incrementExec :
      Executes lexerProgram withEscaping (incrementLocal 4 1) .next completed :=
    ⟨11, withEscapingInvariant.execOffsetIncrement incrementBound⟩
  have completedInvariant :
      QuotedStateAt base completed source start (offset + 1) true delimiter :=
    withEscapingInvariant.afterOffsetAssignment (offset + 1)
      (Nat.succ_le_of_lt inBounds)
  have unescapedExec :
      Executes lexerProgram withByte quotedUnescapedBody .next completed := by
    unfold quotedUnescapedBody
    exact executesSequence newlineIfExec
      (executesSequence delimiterIfExec
        (executesSequence escapeIfExec incrementExec))
  have branchExec :
      Executes lexerProgram withByte
        (.ifThenElse (.local 5)
          (.sequence
            (assignLocal 5 (.value (.boolean false)))
            (incrementLocal 4 1))
          quotedUnescapedBody) .next completed :=
    executesIfFalse escapingResult unescapedExec
  have initializerExec :
      Evaluates lexerProgram state (.index (.local 0) (.local 4))
        (.signed .i32 byte.val) state := by
    exact ⟨10, by simpa [byte] using invariant.evalSourceByte inBounds⟩
  have bodyExec : Executes lexerProgram state quotedLoopBody .next next := by
    simpa [quotedLoopBody, withByte, completed, next] using
      executesLetLocal (id := 6) (type := i32Type) initializerExec branchExec
  have byteDomain : CellDomainExtension state withByte :=
    bindLocal_domain_extends state 6 (.signed .i32 byte.val)
  have escapingAssigned :
      withByte.assignCell (base + 5) (.boolean true) = some withEscaping :=
    byteInvariant.assignEscaping true
  have escapingDomain : CellDomainExtension withByte withEscaping :=
    assignCell_domain_extends escapingAssigned
  have offsetAssigned :
      withEscaping.assignCell (base + 4) (.signed .i32 (offset + 1)) = some completed :=
    withEscapingInvariant.assignOffset (offset + 1)
  have offsetDomain : CellDomainExtension withEscaping completed :=
    assignCell_domain_extends offsetAssigned
  have completedDomain : CellDomainExtension state completed :=
    byteDomain.trans (escapingDomain.trans offsetDomain)
  have nextDomain : CellDomainExtension state next :=
    completedDomain.restoreLocals
  have nextInvariant :
      QuotedStateAt base next source start (offset + 1) true delimiter :=
    invariant.restoreLocals completedInvariant completedDomain
  exact ⟨next, bodyExec, nextInvariant, nextDomain⟩

theorem QuotedStateAt.execOrdinaryLoopBody
    (invariant : QuotedStateAt base state source start offset false delimiter)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : offset < source.length)
    (notNewline : (source.get ⟨offset, inBounds⟩).val ≠ 10)
    (notDelimiter : source.get ⟨offset, inBounds⟩ ≠ delimiter)
    (notEscape : (source.get ⟨offset, inBounds⟩).val ≠ 92) :
    ∃ next,
      Executes lexerProgram state quotedLoopBody .next next ∧
      QuotedStateAt base next source start (offset + 1) false delimiter ∧
      CellDomainExtension state next := by
  let byte := source.get ⟨offset, inBounds⟩
  let withByte := quotedByteState state byte
  let completed := quotedOffsetAssignedState base withByte (offset + 1)
  let next := Lanius.Semantics.restoreLocals state completed
  have byteInvariant :
      QuotedStateAt base withByte source start offset false delimiter :=
    invariant.afterByteBinding byte
  have escapingResult :
      Evaluates lexerProgram withByte (.local 5) (.boolean false) withByte := by
    exact ⟨2, evalLocal_of_local 1 lexerProgram withByte 5 (.boolean false)
      byteInvariant.escapingLocal⟩
  have byteNotNewline : byte.val ≠ 10 := by simpa [byte] using notNewline
  have newlineBoolean : (byte.val == 10) = false :=
    Bool.eq_false_iff.mpr (by simpa using byteNotNewline)
  have newlineBase := evalI32LocalEqualNatLiteral (program := lexerProgram)
    withByte 6 byte.val 10
    (quotedByteState_local invariant byte)
  rw [newlineBoolean] at newlineBase
  have newlineIfExec :
      Executes lexerProgram withByte
        (.ifThenElse (.binary .equal (.local 6) (i32Literal 10))
          (.returnValue (some
            (callScanConstructor failedScanFunction (.local 4))))
          .skip) .next withByte :=
    executesIfFalse ⟨4, newlineBase⟩ (executesSkip lexerProgram withByte)
  have byteNotDelimiter : byte ≠ delimiter := by
    simpa [byte] using notDelimiter
  have byteValueNotDelimiter : byte.val ≠ delimiter.val := by
    intro equal
    exact byteNotDelimiter (Fin.ext equal)
  have delimiterBoolean : (byte.val == delimiter.val) = false :=
    Bool.eq_false_iff.mpr (by simpa using byteValueNotDelimiter)
  have delimiterBase := evalI32LocalsEqual withByte 6 3 byte.val delimiter.val
    (quotedByteState_local invariant byte) byteInvariant.delimiterLocal
  rw [delimiterBoolean] at delimiterBase
  have delimiterIfExec :
      Executes lexerProgram withByte
        (.ifThenElse (.binary .equal (.local 6) (.local 3))
          (.returnValue (some (callScanConstructor successfulScanFunction
            (.binary .add (.local 4) (i32Literal 1)))))
          .skip) .next withByte :=
    executesIfFalse ⟨4, delimiterBase⟩ (executesSkip lexerProgram withByte)
  have byteNotEscape : byte.val ≠ 92 := by simpa [byte] using notEscape
  have escapeBoolean : (byte.val == 92) = false :=
    Bool.eq_false_iff.mpr (by simpa using byteNotEscape)
  have escapeBase := evalI32LocalEqualNatLiteral (program := lexerProgram)
    withByte 6 byte.val 92
    (quotedByteState_local invariant byte)
  rw [escapeBoolean] at escapeBase
  have escapeIfExec :
      Executes lexerProgram withByte
        (.ifThenElse (.binary .equal (.local 6) (i32Literal 92))
          (assignLocal 5 (.value (.boolean true))) .skip) .next withByte :=
    executesIfFalse ⟨4, escapeBase⟩ (executesSkip lexerProgram withByte)
  have incrementBound : offset + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound
  have incrementExec :
      Executes lexerProgram withByte (incrementLocal 4 1) .next completed :=
    ⟨11, byteInvariant.execOffsetIncrement incrementBound⟩
  have completedInvariant :
      QuotedStateAt base completed source start (offset + 1) false delimiter :=
    byteInvariant.afterOffsetAssignment (offset + 1)
      (Nat.succ_le_of_lt inBounds)
  have unescapedExec :
      Executes lexerProgram withByte quotedUnescapedBody .next completed := by
    unfold quotedUnescapedBody
    exact executesSequence newlineIfExec
      (executesSequence delimiterIfExec
        (executesSequence escapeIfExec incrementExec))
  have branchExec :
      Executes lexerProgram withByte
        (.ifThenElse (.local 5)
          (.sequence
            (assignLocal 5 (.value (.boolean false)))
            (incrementLocal 4 1))
          quotedUnescapedBody) .next completed :=
    executesIfFalse escapingResult unescapedExec
  have initializerExec :
      Evaluates lexerProgram state (.index (.local 0) (.local 4))
        (.signed .i32 byte.val) state := by
    exact ⟨10, by simpa [byte] using invariant.evalSourceByte inBounds⟩
  have bodyExec : Executes lexerProgram state quotedLoopBody .next next := by
    simpa [quotedLoopBody, withByte, completed, next] using
      executesLetLocal (id := 6) (type := i32Type) initializerExec branchExec
  have byteDomain : CellDomainExtension state withByte :=
    bindLocal_domain_extends state 6 (.signed .i32 byte.val)
  have offsetAssigned :
      withByte.assignCell (base + 4) (.signed .i32 (offset + 1)) = some completed :=
    byteInvariant.assignOffset (offset + 1)
  have offsetDomain : CellDomainExtension withByte completed :=
    assignCell_domain_extends offsetAssigned
  have completedDomain : CellDomainExtension state completed :=
    byteDomain.trans offsetDomain
  have nextDomain : CellDomainExtension state next :=
    completedDomain.restoreLocals
  have nextInvariant :
      QuotedStateAt base next source start (offset + 1) false delimiter :=
    invariant.restoreLocals completedInvariant completedDomain
  exact ⟨next, bodyExec, nextInvariant, nextDomain⟩

theorem executesQuotedWhile
    (invariant : QuotedStateAt base state source start offset escaping delimiter)
    (sourceBound : source.length ≤ 2147483647) :
    (∃ finalState finalEscaping,
      scanQuotedBody delimiter escaping (source.drop offset) offset =
        .failure source.length ∧
      Executes lexerProgram state
        (.whileLoop (.binary .less (.local 4) (.local 1)) quotedLoopBody)
        .next finalState ∧
      QuotedStateAt base finalState source start source.length finalEscaping delimiter ∧
      CellDomainExtension state finalState) ∨
    (∃ finalState,
      Executes lexerProgram state
        (.whileLoop (.binary .less (.local 4) (.local 1)) quotedLoopBody)
        (.returned (some (scanEndValue
          (scanQuotedBody delimiter escaping (source.drop offset) offset))))
        finalState) := by
  by_cases inBounds : offset < source.length
  · have conditionBase := invariant.evalLoopCondition
    have conditionResult :
        Evaluates lexerProgram state
          (.binary .less (.local 4) (.local 1)) (.boolean true) state := by
      exact ⟨13, by simpa [inBounds] using conditionBase⟩
    have dropped := List.drop_eq_getElem_cons inBounds
    cases escaping with
    | true =>
        obtain ⟨next, bodyExec, nextInvariant, bodyDomain⟩ :=
          invariant.execEscapedLoopBody sourceBound inBounds
        have stepResult :
            scanQuotedBody delimiter true (source.drop offset) offset =
              scanQuotedBody delimiter false (source.drop (offset + 1))
                (offset + 1) := by
          rw [dropped, scanQuotedBody]
        rcases executesQuotedWhile nextInvariant sourceBound with
          ⟨finalState, finalEscaping, resultEq, restExec, finalInvariant,
            restDomain⟩ |
          ⟨finalState, restExec⟩
        · left
          exact ⟨finalState, finalEscaping, stepResult.trans resultEq,
            executesWhileTrueThen conditionResult bodyExec restExec,
            finalInvariant, bodyDomain.trans restDomain⟩
        · right
          refine ⟨finalState, ?_⟩
          rw [stepResult]
          exact executesWhileTrueThen conditionResult bodyExec restExec
    | false =>
        let byte := source.get ⟨offset, inBounds⟩
        by_cases newline : byte.val = 10
        · obtain ⟨finalState, bodyExec⟩ :=
            invariant.execNewlineLoopBody inBounds (by simpa [byte] using newline)
          have resultEq :
              scanQuotedBody delimiter false (source.drop offset) offset =
                .failure offset := by
            rw [dropped, scanQuotedBody, if_pos]
            simpa [byte] using newline
          right
          refine ⟨finalState, ?_⟩
          rw [resultEq]
          exact executesWhileReturned conditionResult bodyExec
        · by_cases closes : byte = delimiter
          · obtain ⟨finalState, bodyExec⟩ :=
              invariant.execDelimiterLoopBody sourceBound inBounds
                (by simpa [byte] using newline)
                (by simpa [byte] using closes)
            have resultEq :
                scanQuotedBody delimiter false (source.drop offset) offset =
                  .success (offset + 1) := by
              rw [dropped, scanQuotedBody, if_neg, if_pos]
              · simpa [byte] using closes
              · simpa [byte] using newline
            right
            refine ⟨finalState, ?_⟩
            rw [resultEq]
            exact executesWhileReturned conditionResult bodyExec
          · by_cases escape : byte.val = 92
            · obtain ⟨next, bodyExec, nextInvariant, bodyDomain⟩ :=
                invariant.execBeginEscapeLoopBody sourceBound inBounds
                  (by simpa [byte] using newline)
                  (by simpa [byte] using closes)
                  (by simpa [byte] using escape)
              have stepResult :
                  scanQuotedBody delimiter false (source.drop offset) offset =
                    scanQuotedBody delimiter true (source.drop (offset + 1))
                      (offset + 1) := by
                rw [dropped, scanQuotedBody, if_neg, if_neg, if_pos]
                · simpa [byte] using escape
                · simpa [byte] using closes
                · simpa [byte] using newline
              rcases executesQuotedWhile nextInvariant sourceBound with
                ⟨finalState, finalEscaping, resultEq, restExec, finalInvariant,
                  restDomain⟩ |
                ⟨finalState, restExec⟩
              · left
                exact ⟨finalState, finalEscaping, stepResult.trans resultEq,
                  executesWhileTrueThen conditionResult bodyExec restExec,
                  finalInvariant, bodyDomain.trans restDomain⟩
              · right
                refine ⟨finalState, ?_⟩
                rw [stepResult]
                exact executesWhileTrueThen conditionResult bodyExec restExec
            · obtain ⟨next, bodyExec, nextInvariant, bodyDomain⟩ :=
                invariant.execOrdinaryLoopBody sourceBound inBounds
                  (by simpa [byte] using newline)
                  (by simpa [byte] using closes)
                  (by simpa [byte] using escape)
              have stepResult :
                  scanQuotedBody delimiter false (source.drop offset) offset =
                    scanQuotedBody delimiter false (source.drop (offset + 1))
                      (offset + 1) := by
                rw [dropped, scanQuotedBody, if_neg, if_neg, if_neg]
                · simpa [byte] using escape
                · simpa [byte] using closes
                · simpa [byte] using newline
              rcases executesQuotedWhile nextInvariant sourceBound with
                ⟨finalState, finalEscaping, resultEq, restExec, finalInvariant,
                  restDomain⟩ |
                ⟨finalState, restExec⟩
              · left
                exact ⟨finalState, finalEscaping, stepResult.trans resultEq,
                  executesWhileTrueThen conditionResult bodyExec restExec,
                  finalInvariant, bodyDomain.trans restDomain⟩
              · right
                refine ⟨finalState, ?_⟩
                rw [stepResult]
                exact executesWhileTrueThen conditionResult bodyExec restExec
  · have atEnd : offset = source.length :=
      Nat.le_antisymm invariant.offsetBound (Nat.le_of_not_gt inBounds)
    have conditionBase := invariant.evalLoopCondition
    have conditionResult :
        Evaluates lexerProgram state
          (.binary .less (.local 4) (.local 1)) (.boolean false) state := by
      exact ⟨13, by simpa [inBounds] using conditionBase⟩
    left
    refine ⟨state, escaping, ?_, executesWhileFalse conditionResult, ?_,
      CellDomainExtension.refl state⟩
    · simp [atEnd, scanQuotedBody]
    · simpa [atEnd] using invariant
termination_by source.length - offset
decreasing_by all_goals omega

theorem executesQuotedLoopAndFallback
    (invariant : QuotedStateAt base state source start offset escaping delimiter)
    (sourceBound : source.length ≤ 2147483647) :
    ∃ finalState,
      Executes lexerProgram state
        (.sequence
          (.whileLoop (.binary .less (.local 4) (.local 1)) quotedLoopBody)
          (.returnValue (some
            (callScanConstructor failedScanFunction (.local 1)))))
        (.returned (some (scanEndValue
          (scanQuotedBody delimiter escaping (source.drop offset) offset))))
        finalState := by
  rcases executesQuotedWhile invariant sourceBound with
    ⟨afterLoop, finalEscaping, resultEq, loopExec, finalInvariant, _⟩ |
    ⟨finalState, loopExec⟩
  · let called := singleArgumentCallState afterLoop
      (.signed .i32 source.length)
    have argumentResult :
        evalExpr 6 lexerProgram afterLoop (.local 1) =
          .done (.signed .i32 source.length) afterLoop :=
      evalLocal_of_local 5 lexerProgram afterLoop 1
        (.signed .i32 source.length) finalInvariant.limitLocal
    have callResult :
        Evaluates lexerProgram afterLoop
          (callScanConstructor failedScanFunction (.local 1))
          (scanEndValue (.failure source.length)) called := by
      exact ⟨8, failedScanCall_after_argument afterLoop
        finalInvariant.wellFormed (.local 1) source.length argumentResult⟩
    have returnExec :
        Executes lexerProgram afterLoop
          (.returnValue (some
            (callScanConstructor failedScanFunction (.local 1))))
          (.returned (some (scanEndValue (.failure source.length)))) called :=
      executesReturnValue callResult
    refine ⟨called, ?_⟩
    rw [resultEq]
    exact executesSequence loopExec returnExec
  · exact ⟨finalState, executesSequenceReturned loopExec⟩

theorem quotedScannerBody_executesFrom
    (caller : State) (source : List Byte) (start : Nat) (delimiter : Byte)
    (callerWellFormed : StateWellFormed caller)
    (sourceCell : caller.cellEntry? 0 =
      some { id := 0, value := some (.array (sourceValues source)) })
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Executes lexerProgram
        (quotedParameterStateFrom caller source start delimiter)
        quotedScannerBody
        (.returned (some (scanEndValue (scanQuotedEnd source start delimiter))))
        finalState := by
  have incrementBound : start + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.succ_le_of_lt startInBounds) sourceBound
  have offsetInitializerBase := evalI32LocalAddOne (program := lexerProgram)
    (quotedParameterStateFrom caller source start delimiter) 2 start
    (quotedParameterStateFrom_startLocal caller source start delimiter
      callerWellFormed)
    incrementBound rfl
  have offsetInitializer :
      Evaluates lexerProgram
        (quotedParameterStateFrom caller source start delimiter)
        (.binary .add (.local 2) (i32Literal 1))
        (.signed .i32 (start + 1))
        (quotedParameterStateFrom caller source start delimiter) :=
    ⟨4, offsetInitializerBase⟩
  have escapingInitializer :
      Evaluates lexerProgram
        (quotedOffsetStateFrom caller source start delimiter)
        (.value (.boolean false)) (.boolean false)
        (quotedOffsetStateFrom caller source start delimiter) := ⟨1, rfl⟩
  have initialInvariant := quotedInitialStateFrom_invariant caller source start
    delimiter callerWellFormed sourceCell startInBounds
  obtain ⟨loopFinal, loopExec⟩ :=
    executesQuotedLoopAndFallback initialInvariant sourceBound
  have escapingLetExec := executesLetLocal
    (id := 5) (type := .scalar .bool) escapingInitializer loopExec
  have offsetLetExec := executesLetLocal
    (id := 4) (type := i32Type) offsetInitializer (by
      simpa [quotedOffsetStateFrom, quotedInitialStateFrom] using escapingLetExec)
  let finalState := Lanius.Semantics.restoreLocals
    (quotedParameterStateFrom caller source start delimiter)
    (Lanius.Semantics.restoreLocals
      (quotedOffsetStateFrom caller source start delimiter) loopFinal)
  refine ⟨finalState, ?_⟩
  simpa [quotedScannerBody, scanQuotedEnd, finalState,
    quotedOffsetStateFrom] using offsetLetExec

theorem quotedCallFromScannerParameters_executes
    (source : List Byte) (start : Nat) (delimiter : Byte)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Evaluates lexerProgram (scannerParameterState source start)
        (.call scanQuotedEndFunction.id
          [.local 0, .local 1, .local 2, i32Literal delimiter.val])
        (scanEndValue (scanQuotedEnd source start delimiter)) finalState := by
  let caller := scannerParameterState source start
  have callerWellFormed := scannerParameterState_well_formed source start
  have callerSourceCell : caller.cellEntry? 0 =
      some { id := 0, value := some (.array (sourceValues source)) } := by rfl
  obtain ⟨bodyFinal, bodyExec⟩ := quotedScannerBody_executesFrom
    caller source start delimiter callerWellFormed callerSourceCell sourceBound
    startInBounds
  obtain ⟨bodyFuel, bodyResult⟩ := bodyExec
  have argumentsBase :
      evalExprs 5 lexerProgram caller
        [.local 0, .local 1, .local 2, i32Literal delimiter.val] =
        .done
          [.slice i32Type 0 [] 0 source.length,
            .signed .i32 source.length, .signed .i32 start,
            .signed .i32 delimiter.val] caller := by
    rfl
  let fuel := max 5 bodyFuel
  have argumentsAtFuel := evalExprs_done_at_larger_fuel
    (Nat.le_max_left 5 bodyFuel) argumentsBase
  have bodyAtFuel := execStmt_done_at_larger_fuel
    (Nat.le_max_right 5 bodyFuel) bodyResult
  have boundParameters :
      bindParameters scanQuotedEndFunction.parameters
        [.slice i32Type 0 [] 0 source.length,
          .signed .i32 source.length, .signed .i32 start,
          .signed .i32 delimiter.val] =
        some
          [(0, .slice i32Type 0 [] 0 source.length),
            (1, .signed .i32 source.length), (2, .signed .i32 start),
            (3, .signed .i32 delimiter.val)] := by rfl
  have callee :
      ({ caller with locals := [] }).bindLocals
        [(0, .slice i32Type 0 [] 0 source.length),
          (1, .signed .i32 source.length), (2, .signed .i32 start),
          (3, .signed .i32 delimiter.val)] =
        quotedParameterStateFrom caller source start delimiter := by rfl
  let finalState := restoreLocals caller bodyFinal
  refine ⟨finalState, fuel + 1, ?_⟩
  rw [evalExpr, argumentsAtFuel]
  simp only
  rw [lexerProgram_finds_scanQuotedEndFunction]
  simp only
  rw [boundParameters]
  simp only [scanQuotedEndFunction]
  rw [callee, bodyAtFuel]

theorem quotedWrapperBody_executes
    (source : List Byte) (start : Nat) (delimiter : Byte)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Executes lexerProgram (scannerParameterState source start)
        (quotedWrapperBody delimiter.val)
        (.returned (some (scanEndValue (scanQuotedEnd source start delimiter))))
        finalState := by
  obtain ⟨finalState, callExec⟩ :=
    quotedCallFromScannerParameters_executes source start delimiter sourceBound
      startInBounds
  exact ⟨finalState, by
    simpa [quotedWrapperBody] using executesReturnValue callExec⟩

theorem quotedWrapperFunction_executes
    (function : Function) (delimiter : Byte)
    (functionFound : lexerProgram.function? function.id = some function)
    (parameters : function.parameters = scannerParameters)
    (body : function.body = some (quotedWrapperBody delimiter.val))
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Evaluates lexerProgram (sourceState source)
        (scannerCall function source start)
        (scanEndValue (scanQuotedEnd source start delimiter)) finalState := by
  obtain ⟨bodyFinal, bodyExec⟩ :=
    quotedWrapperBody_executes source start delimiter sourceBound startInBounds
  obtain ⟨bodyFuel, bodyResult⟩ := bodyExec
  have argumentsBase :
      evalExprs 4 lexerProgram (sourceState source)
        [sourceSlice source, i32Literal source.length, i32Literal start] =
        .done
          [.slice i32Type 0 [] 0 source.length,
            .signed .i32 source.length, .signed .i32 start]
          (sourceState source) := by rfl
  let fuel := max 4 bodyFuel
  have argumentsAtFuel := evalExprs_done_at_larger_fuel
    (Nat.le_max_left 4 bodyFuel) argumentsBase
  have bodyAtFuel := execStmt_done_at_larger_fuel
    (Nat.le_max_right 4 bodyFuel) bodyResult
  have boundParameters :
      bindParameters function.parameters
        [.slice i32Type 0 [] 0 source.length,
          .signed .i32 source.length, .signed .i32 start] =
        some
          [(0, .slice i32Type 0 [] 0 source.length),
            (1, .signed .i32 source.length), (2, .signed .i32 start)] := by
    rw [parameters]
    rfl
  have callee :
      ({ sourceState source with locals := [] }).bindLocals
        [(0, .slice i32Type 0 [] 0 source.length),
          (1, .signed .i32 source.length), (2, .signed .i32 start)] =
        scannerParameterState source start := by rfl
  let finalState := restoreLocals (sourceState source) bodyFinal
  refine ⟨finalState, fuel + 1, ?_⟩
  unfold scannerCall
  rw [evalExpr, argumentsAtFuel]
  simp only
  rw [functionFound]
  simp only
  rw [boundParameters, body]
  simp only
  rw [callee, bodyAtFuel]

def doubleQuoteByte : Byte := ⟨34, by decide⟩

def singleQuoteByte : Byte := ⟨39, by decide⟩

theorem scanStringEndFunction_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Evaluates lexerProgram (sourceState source)
        (scannerCall scanStringEndFunction source start)
        (scanEndValue (scanQuotedEnd source start doubleQuoteByte)) finalState := by
  exact quotedWrapperFunction_executes scanStringEndFunction doubleQuoteByte
    lexerProgram_finds_scanStringEndFunction rfl rfl source start sourceBound
    startInBounds

theorem scanCharacterEndFunction_executes
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Evaluates lexerProgram (sourceState source)
        (scannerCall scanCharacterEndFunction source start)
        (scanEndValue (scanQuotedEnd source start singleQuoteByte)) finalState := by
  exact quotedWrapperFunction_executes scanCharacterEndFunction singleQuoteByte
    lexerProgram_finds_scanCharacterEndFunction rfl rfl source start sourceBound
    startInBounds

theorem quotedScannerBody_executes
    (source : List Byte) (start : Nat) (delimiter : Byte)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Executes lexerProgram (quotedParameterState source start delimiter)
        quotedScannerBody
        (.returned (some (scanEndValue (scanQuotedEnd source start delimiter))))
        finalState := by
  have incrementBound : start + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.succ_le_of_lt startInBounds) sourceBound
  have offsetInitializerBase := evalI32LocalAddOne (program := lexerProgram)
    (quotedParameterState source start delimiter) 2 start
    (quotedParameterState_startLocal source start delimiter) incrementBound rfl
  have offsetInitializer :
      Evaluates lexerProgram (quotedParameterState source start delimiter)
        (.binary .add (.local 2) (i32Literal 1))
        (.signed .i32 (start + 1))
        (quotedParameterState source start delimiter) :=
    ⟨4, offsetInitializerBase⟩
  have escapingInitializer :
      Evaluates lexerProgram (quotedOffsetState source start delimiter)
        (.value (.boolean false)) (.boolean false)
        (quotedOffsetState source start delimiter) := ⟨1, rfl⟩
  have initialInvariant := quotedInitialState_invariant source start delimiter
    startInBounds
  obtain ⟨loopFinal, loopExec⟩ :=
    executesQuotedLoopAndFallback initialInvariant sourceBound
  have escapingLetExec := executesLetLocal
    (id := 5) (type := .scalar .bool) escapingInitializer loopExec
  have offsetLetExec := executesLetLocal
    (id := 4) (type := i32Type) offsetInitializer (by
      simpa [quotedOffsetState, quotedInitialState] using escapingLetExec)
  let finalState := Lanius.Semantics.restoreLocals
    (quotedParameterState source start delimiter)
    (Lanius.Semantics.restoreLocals
      (quotedOffsetState source start delimiter) loopFinal)
  refine ⟨finalState, ?_⟩
  simpa [quotedScannerBody, scanQuotedEnd, finalState, quotedOffsetState] using
    offsetLetExec

theorem scanQuotedEndFunction_executes
    (source : List Byte) (start : Nat) (delimiter : Byte)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    ∃ finalState,
      Evaluates lexerProgram (sourceState source)
        (quotedScannerCall source start delimiter)
        (scanEndValue (scanQuotedEnd source start delimiter)) finalState := by
  obtain ⟨bodyFinal, bodyExec⟩ :=
    quotedScannerBody_executes source start delimiter sourceBound startInBounds
  obtain ⟨bodyFuel, bodyResult⟩ := bodyExec
  have argumentsBase :
      evalExprs 5 lexerProgram (sourceState source)
        [sourceSlice source, i32Literal source.length, i32Literal start,
          i32Literal delimiter.val] =
        .done
          [.slice i32Type 0 [] 0 source.length,
            .signed .i32 source.length, .signed .i32 start,
            .signed .i32 delimiter.val]
          (sourceState source) := by rfl
  let fuel := max 5 bodyFuel
  have argumentsAtFuel := evalExprs_done_at_larger_fuel
    (Nat.le_max_left 5 bodyFuel) argumentsBase
  have bodyAtFuel := execStmt_done_at_larger_fuel
    (Nat.le_max_right 5 bodyFuel) bodyResult
  have boundParameters :
      bindParameters scanQuotedEndFunction.parameters
        [.slice i32Type 0 [] 0 source.length,
          .signed .i32 source.length, .signed .i32 start,
          .signed .i32 delimiter.val] =
        some
          [(0, .slice i32Type 0 [] 0 source.length),
            (1, .signed .i32 source.length), (2, .signed .i32 start),
            (3, .signed .i32 delimiter.val)] := by rfl
  have callee :
      ({ sourceState source with locals := [] }).bindLocals
        [(0, .slice i32Type 0 [] 0 source.length),
          (1, .signed .i32 source.length), (2, .signed .i32 start),
          (3, .signed .i32 delimiter.val)] =
        quotedParameterState source start delimiter := by rfl
  let finalState := restoreLocals (sourceState source) bodyFinal
  refine ⟨finalState, fuel + 1, ?_⟩
  unfold quotedScannerCall
  rw [evalExpr, argumentsAtFuel]
  simp only
  rw [lexerProgram_finds_scanQuotedEndFunction]
  simp only
  rw [boundParameters]
  simp only [scanQuotedEndFunction]
  rw [callee, bodyAtFuel]

/-- Relational form of the represented scanner contract. This is the bridge
from the independently stated first-error relation to execution of the actual
in-Lanius `scan_quoted_end` function. -/
theorem scanQuotedEndFunction_executes_spec
    (source : List Byte) (start : Nat) (delimiter : Byte) (result : ScanEnd)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length)
    (scan : QuotedBodyScan delimiter false (source.drop (start + 1))
      (start + 1) result) :
    ∃ finalState,
      Evaluates lexerProgram (sourceState source)
        (quotedScannerCall source start delimiter) (scanEndValue result)
        finalState := by
  have execution := scanQuotedEndFunction_executes source start delimiter
    sourceBound startInBounds
  have resultEq : scanQuotedEnd source start delimiter = result := by
    exact scan.executes
  simpa [resultEq] using execution

private def identifierProbe : List Byte :=
  [⟨97, by decide⟩, ⟨98, by decide⟩, ⟨95, by decide⟩,
   ⟨49, by decide⟩, ⟨43, by decide⟩]

example : outcomeI32? (evalExpr 64 lexerProgram (sourceState identifierProbe)
    (scannerCall scanIdentifierEndFunction identifierProbe 0)) = some 4 := by
  native_decide

private def whitespaceProbe : List Byte :=
  [⟨32, by decide⟩, ⟨9, by decide⟩, ⟨10, by decide⟩,
   ⟨13, by decide⟩, ⟨97, by decide⟩]

example : outcomeI32? (evalExpr 64 lexerProgram (sourceState whitespaceProbe)
    (scannerCall scanWhitespaceEndFunction whitespaceProbe 0)) = some 4 := by
  native_decide

theorem scanIdentifierEndFunction_empty :
    outcomeI32? (evalExpr 32 lexerProgram (sourceState [])
      (scannerCall scanIdentifierEndFunction [] 0)) = some 1 := by
  rfl

end Lanius.Compiler.Lexer.Program
