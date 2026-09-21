import Lanius.Semantics.Assignment
import Lanius.Semantics.CallerFrame
import Lanius.Semantics.ReadOnlySlice

namespace Lanius.Extraction.CertificateEmitterFrame

open Lanius Lanius.Core Lanius.Extraction Lanius.Semantics

/-! Artifact-independent memory frames for certificate emitters. -/

def WriteFrame (before after : State) (root : CellId) (updated : Value) : Prop :=
  ∃ middle, CallerFrame before middle ∧
    after.cells = replaceCell middle.cells root updated ∧
    after.nextCell = middle.nextCell ∧
    after.locals = before.locals ∧
    after.heap = before.heap ∧
    after.world = before.world ∧
    after.i32ArrayViews = before.i32ArrayViews

private theorem replaceCell_unchanged_of_not_mem
    (cells : List Cell) (root : CellId) (value : Value)
    (notMember : ∀ cell ∈ cells, cell.id ≠ root) :
    replaceCell cells root value = cells := by
  induction cells with
  | nil => simp [replaceCell]
  | cons head tail ih =>
      have headNe : head.id ≠ root := notMember head (by simp)
      have tailNe : ∀ cell ∈ tail, cell.id ≠ root := by
        intro cell member
        exact notMember cell (by simp [member])
      simp [replaceCell, headNe, ih tailNe]

private theorem replaceCell_append_of_not_mem
    (cells extra : List Cell) (root : CellId) (value : Value)
    (notMember : ∀ cell ∈ extra, cell.id ≠ root) :
    replaceCell (cells ++ extra) root value =
      replaceCell cells root value ++ extra := by
  induction cells with
  | nil =>
      simpa [replaceCell] using
        replaceCell_unchanged_of_not_mem extra root value notMember
  | cons head tail ih =>
      have tailResult : replaceCell (tail ++ extra) root value =
          replaceCell tail root value ++ extra := ih
      by_cases same : head.id = root
      · simp [replaceCell, same, tailResult]
      · simp [replaceCell, same, tailResult]

private theorem replaceCell_twice
    (cells : List Cell) (root : CellId) (first second : Value) :
    replaceCell (replaceCell cells root first) root second =
      replaceCell cells root second := by
  induction cells with
  | nil => simp [replaceCell]
  | cons head tail ih =>
      by_cases same : head.id = root
      · simp [replaceCell, same, ih]
      · simp [replaceCell, same, ih]

private theorem replaceCell_commute
    (cells : List Cell) (left right : CellId) (leftValue rightValue : Value)
    (different : left ≠ right) :
    replaceCell (replaceCell cells left leftValue) right rightValue =
      replaceCell (replaceCell cells right rightValue) left leftValue := by
  induction cells with
  | nil => rfl
  | cons head tail ih =>
      by_cases leftHead : head.id = left
      · have rightHead : head.id ≠ right := by
          intro equal
          exact different (leftHead.symm.trans equal)
        simp [replaceCell, leftHead, ih, different]
      · by_cases rightHead : head.id = right
        · simp [replaceCell, rightHead, ih, Ne.symm different]
        · simp [replaceCell, leftHead, rightHead, ih]

theorem WriteFrame.trans
    {before middle after : State} {root : CellId}
    {firstValue secondValue : Value}
    (first : WriteFrame before middle root firstValue)
    (second : WriteFrame middle after root secondValue)
    (rootBound : root < before.nextCell) :
    WriteFrame before after root secondValue := by
  rcases first with ⟨firstMiddle, firstCaller, firstCells, firstNext,
    firstLocals, firstHeap, firstWorld, firstViews⟩
  rcases second with ⟨secondMiddle, secondCaller, secondCells, secondNext,
    secondLocals, secondHeap, secondWorld, secondViews⟩
  rcases firstCaller.cells with ⟨left, leftCells, leftFrontier, leftFresh⟩
  rcases secondCaller.cells with ⟨right, rightCells, rightFrontier, rightFresh⟩
  let joinedMiddle : State := { secondMiddle with
    cells := firstMiddle.cells ++ right }
  have rightNotRoot : ∀ cell ∈ right, cell.id ≠ root := by
    intro cell member
    have lower : middle.nextCell ≤ cell.id := rightFresh cell member |>.1
    have middleFrontier : before.nextCell ≤ middle.nextCell := by
      rw [firstNext]
      exact leftFrontier
    exact (Nat.ne_of_lt (Nat.lt_of_lt_of_le rootBound
      (Nat.le_trans middleFrontier lower))).symm
  have joinedCells : joinedMiddle.cells =
      before.cells ++ (left ++ right) := by
    dsimp [joinedMiddle]
    rw [← List.append_assoc, leftCells]
  have joinedNext : before.nextCell ≤ joinedMiddle.nextCell := by
    rw [show joinedMiddle.nextCell = secondMiddle.nextCell by rfl]
    exact Nat.le_trans leftFrontier
      (Nat.le_trans (by simp [firstNext])
        rightFrontier)
  have joinedFresh : ∀ cell ∈ left ++ right,
      before.nextCell ≤ cell.id ∧ cell.id < joinedMiddle.nextCell := by
    intro cell member
    rcases List.mem_append.mp member with member | member
    · exact ⟨leftFresh cell member |>.1,
        Nat.lt_of_lt_of_le (by simpa [firstNext] using leftFresh cell member |>.2)
          rightFrontier⟩
    · exact ⟨Nat.le_trans (by
          rw [firstNext]
          exact leftFrontier) (rightFresh cell member |>.1),
        rightFresh cell member |>.2⟩
  have joinedCaller : CallerFrame before joinedMiddle := by
    refine ⟨firstCaller.callerFormed, ⟨left ++ right, joinedCells,
      joinedNext, joinedFresh⟩, ?_, ?_, ?_⟩
    · exact secondCaller.heap.trans firstHeap
    · exact secondCaller.world.trans firstWorld
    · exact secondCaller.views.trans firstViews
  refine ⟨joinedMiddle, joinedCaller, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · calc
      after.cells = replaceCell secondMiddle.cells root secondValue := secondCells
      _ = replaceCell (middle.cells ++ right) root secondValue := by rw [rightCells]
      _ = replaceCell (replaceCell firstMiddle.cells root firstValue ++ right)
          root secondValue := by rw [firstCells]
      _ = replaceCell (replaceCell firstMiddle.cells root firstValue)
          root secondValue ++ right :=
        replaceCell_append_of_not_mem _ _ root secondValue rightNotRoot
      _ = replaceCell firstMiddle.cells root secondValue ++ right := by
        rw [replaceCell_twice]
      _ = replaceCell (firstMiddle.cells ++ right) root secondValue := by
        symm
        exact replaceCell_append_of_not_mem _ _ root secondValue rightNotRoot
      _ = replaceCell joinedMiddle.cells root secondValue := by rfl
  · exact secondNext
  · exact secondLocals.trans (firstLocals.trans rfl)
  · exact secondHeap.trans (firstHeap.trans rfl)
  · exact secondWorld.trans (firstWorld.trans rfl)
  · exact secondViews.trans (firstViews.trans rfl)

theorem WriteFrame.ofCallerFrame
    {before after : State} {root : CellId} {updated : Value}
    (frame : CallerFrame before after)
    (unchanged : replaceCell after.cells root updated = after.cells)
    (locals : after.locals = before.locals) :
    WriteFrame before after root updated := by
  exact ⟨after, frame, unchanged.symm, rfl, locals, frame.heap,
    frame.world, frame.views⟩

theorem WriteFrame.transCallerFrame
    {caller callee completed : State} {root : CellId} {updated : Value}
    (callerFrame : CallerFrame caller callee)
    (bodyFrame : WriteFrame callee completed root updated) :
    WriteFrame caller (restoreLocals caller completed) root updated := by
  rcases bodyFrame with ⟨middle, bodyCaller, cells, next, _, heap, world, views⟩
  refine ⟨middle, callerFrame.trans bodyCaller, ?_, next, rfl, ?_, ?_, ?_⟩
  · simpa [restoreLocals] using cells
  · exact heap.trans callerFrame.heap
  · exact world.trans callerFrame.world
  · exact views.trans callerFrame.views

/- Compose two mutable writes when the second call is made from a fresh
   `letLocal` binding. -/
theorem WriteFrame.trans_bindLocal
    {before firstAfter bound after : State} {root : CellId}
    {firstValue secondValue value : Value} (id : VarId)
    (first : WriteFrame before firstAfter root firstValue)
    (boundEq : bound = firstAfter.bindLocal id value)
    (second : WriteFrame bound after root secondValue)
    (rootBound : root < before.nextCell) :
    WriteFrame before (restoreLocals before after) root secondValue := by
  subst bound
  rcases first with ⟨firstMiddle, firstCaller, firstCells, firstNext,
    firstLocals, firstHeap, firstWorld, firstViews⟩
  rcases second with ⟨secondMiddle, secondCaller, secondCells, secondNext,
    secondLocals, secondHeap, secondWorld, secondViews⟩
  rcases firstCaller.cells with ⟨left, leftCells, leftFrontier, leftFresh⟩
  rcases secondCaller.cells with ⟨right, rightCells, rightFrontier, rightFresh⟩
  let binding : Cell := { id := firstAfter.nextCell, value := some value }
  let joinedMiddle : State := { secondMiddle with
    cells := firstMiddle.cells ++ (binding :: right) }
  have boundCells : (firstAfter.bindLocal id value).cells = firstAfter.cells ++ [binding] := by
    rfl
  have boundNext : (firstAfter.bindLocal id value).nextCell = firstAfter.nextCell + 1 := by
    rfl
  have rootBeforeBound : root < (firstAfter.bindLocal id value).nextCell := by
    rw [boundNext, firstNext]
    exact Nat.lt_succ_of_lt (Nat.lt_of_lt_of_le rootBound leftFrontier)
  have rightNotRoot : ∀ cell ∈ right, cell.id ≠ root := by
    intro cell member
    have lower : (firstAfter.bindLocal id value).nextCell ≤ cell.id :=
      rightFresh cell member |>.1
    exact (Nat.ne_of_lt (Nat.lt_of_lt_of_le rootBeforeBound lower)).symm
  have bindingNotRoot : binding.id ≠ root := by
    dsimp [binding]
    rw [firstNext]
    exact (Nat.ne_of_lt (Nat.lt_of_lt_of_le rootBound leftFrontier)).symm
  have joinedCells : joinedMiddle.cells = before.cells ++ (left ++ (binding :: right)) := by
    dsimp [joinedMiddle]
    rw [leftCells]
    simp [List.append_assoc]
  have joinedNext : before.nextCell ≤ joinedMiddle.nextCell := by
    rw [show joinedMiddle.nextCell = secondMiddle.nextCell by rfl]
    have firstToBound : firstMiddle.nextCell ≤
        (firstAfter.bindLocal id value).nextCell := by
      rw [boundNext, firstNext]
      exact Nat.le_succ _
    exact Nat.le_trans leftFrontier (Nat.le_trans firstToBound rightFrontier)
  have joinedFresh : ∀ cell ∈ left ++ (binding :: right),
      before.nextCell ≤ cell.id ∧ cell.id < joinedMiddle.nextCell := by
    intro cell member
    rcases List.mem_append.mp member with member | member
    · exact ⟨(leftFresh cell member).1,
        Nat.lt_of_lt_of_le (by simpa [firstNext] using leftFresh cell member |>.2)
          (Nat.le_trans (by
            rw [boundNext, firstNext]
            exact Nat.le_succ _) rightFrontier)⟩
    · rcases List.mem_cons.mp member with rfl | member
      · constructor
        · dsimp [binding]
          rw [firstNext]
          omega
        · dsimp [binding]
          exact Nat.lt_of_lt_of_le (by simp [boundNext, firstNext]) rightFrontier
      · exact ⟨Nat.le_trans (by
            rw [boundNext, firstNext]
            exact Nat.le_trans leftFrontier (Nat.le_succ _))
          (rightFresh cell member |>.1), rightFresh cell member |>.2⟩
  have joinedCaller : CallerFrame before joinedMiddle := by
    refine ⟨firstCaller.callerFormed, ⟨left ++ (binding :: right), joinedCells,
      joinedNext, joinedFresh⟩, ?_, ?_, ?_⟩
    · calc
        secondMiddle.heap = (firstAfter.bindLocal id value).heap := secondCaller.heap
        _ = firstAfter.heap := rfl
        _ = before.heap := firstHeap
    · calc
        secondMiddle.world = (firstAfter.bindLocal id value).world := secondCaller.world
        _ = firstAfter.world := rfl
        _ = before.world := firstWorld
    · calc
        secondMiddle.i32ArrayViews = (firstAfter.bindLocal id value).i32ArrayViews :=
          secondCaller.views
        _ = firstAfter.i32ArrayViews := rfl
        _ = before.i32ArrayViews := firstViews
  refine ⟨joinedMiddle, joinedCaller, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · calc
      (restoreLocals before after).cells = after.cells := rfl
      _ = replaceCell secondMiddle.cells root secondValue := secondCells
      _ = replaceCell ((firstAfter.bindLocal id value).cells ++ right)
          root secondValue := by rw [rightCells]
      _ = replaceCell ((replaceCell firstMiddle.cells root firstValue ++ [binding]) ++ right)
          root secondValue := by rw [boundCells, firstCells]
      _ = replaceCell (replaceCell firstMiddle.cells root firstValue ++ [binding])
          root secondValue ++ right :=
        replaceCell_append_of_not_mem _ _ root secondValue rightNotRoot
      _ = (replaceCell (replaceCell firstMiddle.cells root firstValue ++ [binding])
          root secondValue) ++ right := rfl
      _ = (replaceCell firstMiddle.cells root secondValue ++ [binding]) ++ right := by
        rw [replaceCell_append_of_not_mem _ _ root secondValue (by
          intro cell member
          simp only [List.mem_singleton] at member
          subst cell
          exact bindingNotRoot)]
        rw [replaceCell_twice]
      _ = replaceCell (firstMiddle.cells ++ (binding :: right)) root secondValue := by
        symm
        have h := replaceCell_append_of_not_mem firstMiddle.cells
          (binding :: right) root secondValue (by
          intro cell member
          rcases List.mem_cons.mp member with rfl | member
          · exact bindingNotRoot
          · exact rightNotRoot cell member)
        simpa [List.append_assoc] using h
      _ = replaceCell joinedMiddle.cells root secondValue := by rfl
  · simpa [restoreLocals, joinedMiddle] using secondNext
  · simp [restoreLocals]
  · simpa [restoreLocals, joinedMiddle] using
      (show after.heap = before.heap from by
        calc
          after.heap = (firstAfter.bindLocal id value).heap := secondHeap
          _ = firstAfter.heap := rfl
          _ = before.heap := firstHeap)
  · simpa [restoreLocals, joinedMiddle] using
      (show after.world = before.world from by
        calc
          after.world = (firstAfter.bindLocal id value).world := secondWorld
          _ = firstAfter.world := rfl
          _ = before.world := firstWorld)
  · simpa [restoreLocals, joinedMiddle] using
      (show after.i32ArrayViews = before.i32ArrayViews from by
        calc
          after.i32ArrayViews = (firstAfter.bindLocal id value).i32ArrayViews := secondViews
          _ = firstAfter.i32ArrayViews := rfl
          _ = before.i32ArrayViews := firstViews)

theorem WriteFrame.locals
    {before after : State} {root : CellId} {updated : Value}
    (frame : WriteFrame before after root updated) :
    after.locals = before.locals := by
  rcases frame with ⟨_, _, _, _, locals, _, _, _⟩
  exact locals

/- Generic stable assignment facts used by emitter call contracts.  They only
   mention the semantic assignment evaluator, so they remain independent of
   any quoted certificate artifact. -/
theorem StableExpr.assignSetLocal
    {rightFuel : Nat} (program : Program) (state : State)
    (id : VarId) (cell : CellId) (current : Value)
    (expression : Expr) (result : Value) (afterRight after : State)
    (cellFound : state.cellId? id = some cell)
    (localFound : state.local? id = some current)
    (right : StableExpr rightFuel program state expression result afterRight)
    (locals : afterRight.locals = state.locals)
    (assigned : afterRight.assignLocal id result = some after) :
    StableExpr (rightFuel + 2) program state
      (.assign .set (.local id) expression) .unit after := by
  intro fuel enough
  have place := evalPlace_local_of_local? (fuel - 2) program state id cell
    current cellFound localFound
  have rightEval := right (fuel - 2).succ (by omega)
  have afterCell : afterRight.cellId? id = some cell := by
    simpa [State.cellId?, locals] using cellFound
  have assignedCell := assignLocal_assignCell id cell result afterCell assigned
  have write :
      writeResolvedPlace afterRight
        { root := cell, projections := [], value := some current } result = .ok after := by
    unfold writeResolvedPlace
    rw [assignedCell]
  rw [← show (fuel - 2).succ.succ = fuel by omega, evalExpr.eq_def]
  simp only [place, rightEval]
  have operation :
      evalAssignValue program.target .set (some current) result = .ok result := by
    rfl
  simp only [operation, write]

theorem StableExpr.assignSubtractI32
    (program : Program) (state : State) (id : VarId) (cell : CellId)
    (current decrement : Int) (after : State)
    (cellFound : state.cellId? id = some cell)
    (localFound : state.local? id = some (.signed .i32 current))
    (assigned : state.assignLocal id
      (.signed .i32 (wrapSigned program.target .i32 (current - decrement))) =
      some after) :
    StableExpr 2 program state
      (.assign .subtract (.local id) (.value (.signed .i32 decrement)))
      .unit after := by
  intro fuel enough
  have place := evalPlace_local_of_local? (fuel - 2) program state id cell
    (.signed .i32 current) cellFound localFound
  have right := evalExpr_value (fuel - 2) program state
    (.signed .i32 decrement)
  let nextValue : Value :=
    .signed .i32 (wrapSigned program.target .i32 (current - decrement))
  have operation :
      evalAssignValue program.target .subtract
          (some (.signed .i32 current)) (.signed .i32 decrement) =
        .ok nextValue := by
    simp [nextValue, evalAssignValue, assignOpBinary?, evalBinaryValue, evalSignedBinary]
  have assignedCell : state.assignCell cell nextValue = some after := by
    simpa [State.assignLocal, cellFound, nextValue] using assigned
  have write :
      writeResolvedPlace state
          { root := cell, projections := [], value := some (.signed .i32 current) }
          nextValue = .ok after := by
    unfold writeResolvedPlace
    rw [assignedCell]
  rw [← show (fuel - 2).succ.succ = fuel by omega, evalExpr.eq_def]
  simp only [place, right, operation, write]

theorem WriteFrame.cellIdFound
    {before after : State} {root : CellId} {updated : Value}
    (frame : WriteFrame before after root updated) (id : VarId) (cell : CellId)
    (found : before.cellId? id = some cell) :
    after.cellId? id = some cell := by
  rcases frame with ⟨_, _, _, _, locals, _, _, _⟩
  simpa [State.cellId?, locals] using found

theorem WriteFrame.assignCellFresh
    {before after : State} {root : CellId} {updated : Value}
    (frame : WriteFrame before after root updated)
    (rootBound : root < before.nextCell) (cell : CellId) (replacement : Value)
    (fresh : before.nextCell ≤ cell)
    (assigned : after.assignCell cell replacement = some final) :
    WriteFrame before final root updated := by
  rcases frame with ⟨middle, callerFrame, afterCells, afterNext,
    afterLocals, afterHeap, afterWorld, afterViews⟩
  have cellNe : cell ≠ root := by
    intro equal
    exact (Nat.not_lt_of_ge fresh) (equal ▸ rootBound)
  have entrySome : ∃ entry, after.cellEntry? cell = some entry := by
    have present : (after.cellEntry? cell).isSome := by
      unfold State.assignCell at assigned
      split at assigned
      · exact ‹(after.cellEntry? cell).isSome›
      · contradiction
    cases h : after.cellEntry? cell with
    | none => simp [h] at present
    | some entry => exact ⟨entry, rfl⟩
  obtain ⟨entry, entryFound⟩ := entrySome
  have middleEntry : middle.cellEntry? cell = some entry := by
    unfold State.cellEntry? at entryFound ⊢
    rw [afterCells, replaceCell_find_other middle.cells root cell updated cellNe] at entryFound
    exact entryFound
  let middleAfter : State := { middle with
    cells := replaceCell middle.cells cell replacement }
  have middleAssigned : middle.assignCell cell replacement = some middleAfter := by
    unfold State.assignCell
    rw [middleEntry]
    rfl
  have middleFrame : CallerFrame before middleAfter :=
    callerFrame.assignCellFresh cell replacement fresh middleAssigned
  have finalState : final = { after with
      cells := replaceCell after.cells cell replacement } := assignCell_state assigned
  refine ⟨middleAfter, middleFrame, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · rw [finalState, afterCells]
    change replaceCell (replaceCell middle.cells root updated) cell replacement =
      replaceCell (replaceCell middle.cells cell replacement) root updated
    rw [replaceCell_commute middle.cells root cell updated replacement (Ne.symm cellNe)]
  · simpa [finalState, middleAfter] using afterNext
  · simpa [finalState] using afterLocals
  · simpa [finalState] using afterHeap
  · simpa [finalState] using afterWorld
  · simpa [finalState] using afterViews

theorem WriteFrame.localFound_of_ne
    {before after : State} {root : CellId} {updated : Value}
    (frame : WriteFrame before after root updated) (id : VarId) (value : Value)
    (found : before.local? id = some value)
    (different : before.cellId? id ≠ some root) :
    after.local? id = some value := by
  rcases frame with ⟨middle, callFrame, cells, _, locals, _, _, _⟩
  have found' := found
  unfold State.local? at found'
  cases h : before.cellId? id with
  | none => simp [h] at found'
  | some cell =>
    have cellFound : before.cellId? id = some cell := h
    let entry : Cell := { id := cell, value := some value }
    have entryFound : before.cellEntry? cell = some entry := by
      simpa [entry] using cellEntry_of_local before id cell value cellFound found
    have middleEntry := callFrame.cells.cellEntryFound entryFound
    have cellNe : cell ≠ root := by
      intro equal
      apply different
      simpa [equal] using cellFound
    have afterEntry : after.cellEntry? cell = some entry := by
      unfold State.cellEntry? at middleEntry ⊢
      rw [cells, replaceCell_find_other middle.cells root cell updated cellNe]
      exact middleEntry
    have afterCell : after.cellId? id = some cell := by
      unfold State.cellId? at cellFound ⊢
      rw [show after.locals = before.locals from locals]
      exact cellFound
    unfold State.local?
    rw [afterCell]
    simp [State.cell?, afterEntry, entry]

end Lanius.Extraction.CertificateEmitterFrame
