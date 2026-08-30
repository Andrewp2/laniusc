import Lanius.ExecutionRules
import Lanius.Properties
import Lanius.SymbolicCore

namespace Lanius.Separation

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Fuel
open Lanius.SymbolicCore

abbrev CellSet := CellId → Prop

namespace CellSet

def empty : CellSet := fun _ => False
def singleton (owned : CellId) : CellSet := fun cell => cell = owned
def union (left right : CellSet) : CellSet := fun cell => left cell ∨ right cell
def Subset (left right : CellSet) : Prop := ∀ cell, left cell → right cell
def Disjoint (left right : CellSet) : Prop :=
  ∀ cell, left cell → right cell → False

theorem subset_union_left : Subset left (union left right) :=
  fun _ member => Or.inl member

theorem subset_union_right : Subset right (union left right) :=
  fun _ member => Or.inr member

theorem empty_subset : Subset empty cells :=
  fun _ member => False.elim member

theorem Disjoint.symm (disjoint : Disjoint left right) : Disjoint right left :=
  fun cell rightMember leftMember => disjoint cell leftMember rightMember

theorem Disjoint.mono_left
    (subset : Subset smaller larger)
    (disjoint : Disjoint larger right) : Disjoint smaller right :=
  fun cell member written => disjoint cell (subset cell member) written

theorem Disjoint.mono_right
    (subset : Subset smaller larger)
    (disjoint : Disjoint left larger) : Disjoint left smaller :=
  fun cell member written => disjoint cell member (subset cell written)

end CellSet

/-- The physical cells currently backing a logical set of local variables.
    This is the bridge between proof-facing local frames and the cell
    footprints used by separation logic. -/
def localCellFootprint (state : State) (locals : VarId → Prop) : CellSet :=
  fun cell => ∃ id, locals id ∧ state.cellId? id = some cell

/-- Physical cells backing a source-derived declaration frame.  Clients pass
    the checked bindings themselves; numeric local membership is an internal
    projection rather than a separately maintained proof predicate. -/
def localBindingFrameFootprint
    (state : State) (frame : LocalBindingFrame) : CellSet :=
  localCellFootprint state frame.ContainsCoreId

theorem localCellFootprint_mono
    (subset : ∀ id, smaller id → larger id) :
    CellSet.Subset (localCellFootprint state smaller)
      (localCellFootprint state larger) := by
  intro cell member
  obtain ⟨id, framed, cellId⟩ := member
  exact ⟨id, subset id framed, cellId⟩

theorem localBindingFrameFootprint_mono
    (subset : ∀ id, smaller.ContainsCoreId id →
      larger.ContainsCoreId id) :
    CellSet.Subset (localBindingFrameFootprint state smaller)
      (localBindingFrameFootprint state larger) :=
  localCellFootprint_mono subset

/-- A local frame is disjoint from one written cell when none of its locals
    is backed by that cell. -/
theorem localCellFootprint_disjoint_singleton
    {state : State} {locals : VarId → Prop} {written : CellId}
    (separate : ∀ id, locals id → state.cellId? id ≠ some written) :
    CellSet.Disjoint (localCellFootprint state locals)
      (CellSet.singleton written) := by
  intro cell member writtenCell
  obtain ⟨id, framed, cellId⟩ := member
  subst cell
  exact separate id framed cellId

theorem localBindingFrameFootprint_disjoint_singleton
    {state : State} {frame : LocalBindingFrame} {written : CellId}
    (separate : ∀ id, frame.ContainsCoreId id →
      state.cellId? id ≠ some written) :
    CellSet.Disjoint (localBindingFrameFootprint state frame)
      (CellSet.singleton written) :=
  localCellFootprint_disjoint_singleton separate

theorem CellSet.Disjoint.localCell_ne_of_singleton
    {state : State} {locals : VarId → Prop} {written : CellId} {id : VarId}
    (disjoint : CellSet.Disjoint (localCellFootprint state locals)
      (CellSet.singleton written))
    (member : locals id) : state.cellId? id ≠ some written := by
  intro found
  exact disjoint written ⟨id, member, found⟩ rfl

/-- Two states agree on the resources observed by an assertion. Allocation
outside the observed cells is intentionally invisible. -/
structure Agreement (cells : CellSet) (before after : State) : Prop where
  locals : after.locals = before.locals
  cell : ∀ id, cells id → after.cellEntry? id = before.cellEntry? id
  heap : after.heap = before.heap
  world : after.world = before.world
  views : after.i32ArrayViews = before.i32ArrayViews

theorem Agreement.refl (cells : CellSet) (state : State) :
    Agreement cells state state := by
  exact ⟨rfl, fun _ _ => rfl, rfl, rfl, rfl⟩

theorem Agreement.symm
    (agreement : Agreement cells before after) :
    Agreement cells after before := by
  exact ⟨agreement.locals.symm, fun id member =>
    (agreement.cell id member).symm, agreement.heap.symm,
    agreement.world.symm, agreement.views.symm⟩

theorem Agreement.trans
    (first : Agreement cells before middle)
    (second : Agreement cells middle after) :
    Agreement cells before after := by
  exact ⟨second.locals.trans first.locals, fun id member =>
    (second.cell id member).trans (first.cell id member),
    second.heap.trans first.heap, second.world.trans first.world,
    second.views.trans first.views⟩

theorem Agreement.mono
    (subset : CellSet.Subset smaller larger)
    (agreement : Agreement larger before after) :
    Agreement smaller before after := by
  exact ⟨agreement.locals, fun id member =>
    agreement.cell id (subset id member), agreement.heap, agreement.world,
    agreement.views⟩

/-- A separation assertion has a static cell footprint and may inspect only
that footprint plus the caller-local environment and non-cell state. The
stability field makes the locality contract enforceable rather than a naming
convention. -/
structure Assertion where
  footprint : CellSet
  holds : State → Prop
  stable : ∀ {before after}, Agreement footprint before after →
    holds before → holds after
  allocated : ∀ {state}, holds state → StateWellFormed state →
    ∀ id, footprint id → id < state.nextCell

namespace Assertion

def emp : Assertion where
  footprint := CellSet.empty
  holds := fun _ => True
  stable := by
    intro before after agreement held
    exact held
  allocated := by
    intro state held wellFormed id member
    exact False.elim member

def pure (proposition : Prop) : Assertion where
  footprint := CellSet.empty
  holds := fun _ => proposition
  stable := by
    intro before after agreement held
    exact held
  allocated := by
    intro state held wellFormed id member
    exact False.elim member

def pointsTo (cell : CellId) (value : Option Value) : Assertion where
  footprint := CellSet.singleton cell
  holds := fun state =>
    state.cellEntry? cell = some { id := cell, value := value }
  stable := by
    intro before after agreement found
    exact (agreement.cell cell rfl).trans found
  allocated := by
    intro state found wellFormed id member
    subst id
    have entryMember : { id := cell, value := value } ∈ state.cells :=
      List.mem_of_find?_eq_some found
    exact wellFormed.cellIdsBelowNext _ entryMember

/-- Ownership of a local includes both the lexical binding and its physical
cell. The physical cell identity is explicit, so rebinding the same variable
does not silently transfer ownership. -/
def localPointsTo
    (varId : VarId) (cell : CellId) (value : Option Value) : Assertion where
  footprint := CellSet.singleton cell
  holds := fun state =>
    state.cellId? varId = some cell ∧
    state.cellEntry? cell = some { id := cell, value := value }
  stable := by
    intro before after agreement held
    constructor
    · unfold State.cellId? at held ⊢
      rw [agreement.locals]
      exact held.1
    · exact (agreement.cell cell rfl).trans held.2
  allocated := by
    intro state held wellFormed id member
    subst id
    have entryMember : { id := cell, value := value } ∈ state.cells :=
      List.mem_of_find?_eq_some held.2
    exact wellFormed.cellIdsBelowNext _ entryMember

theorem localPointsTo_local
    (id : VarId) (cell : CellId) (value : Value) (state : State)
    (held : (Assertion.localPointsTo id cell (some value)).holds state) :
    state.local? id = some value := by
  rw [State.local?, held.1]
  simp only [Option.bind_some, State.cell?, held.2, Cell.value,
    Option.bind_some]

/-- Every successful local read exposes the physical cell that justifies it.
    This is the elimination rule paired with `localPointsTo_local`; callers
    can recover ownership only for the exact initialized cell the semantics
    actually followed. -/
theorem exists_localPointsTo_of_local
    (state : State) (id : VarId) (value : Value)
    (found : state.local? id = some value) :
    ∃ cell, (Assertion.localPointsTo id cell (some value)).holds state := by
  rw [State.local?, Option.bind_eq_some_iff] at found
  obtain ⟨cell, cellId, cellValue⟩ := found
  rw [State.cell?, Option.bind_eq_some_iff] at cellValue
  obtain ⟨entry, entryFound, initialized⟩ := cellValue
  have entryId : entry.id = cell := by
    simpa using List.find?_some entryFound
  cases entry with
  | mk entryId' entryValue =>
      simp only [Cell.id, Cell.value] at entryId initialized
      subst entryId'
      subst entryValue
      exact ⟨cell, cellId, entryFound⟩

def sep (left right : Assertion) : Assertion where
  footprint := CellSet.union left.footprint right.footprint
  holds := fun state =>
    CellSet.Disjoint left.footprint right.footprint ∧
    left.holds state ∧ right.holds state
  stable := by
    intro before after agreement held
    refine ⟨held.1, left.stable ?_ held.2.1, right.stable ?_ held.2.2⟩
    · exact agreement.mono CellSet.subset_union_left
    · exact agreement.mono CellSet.subset_union_right
  allocated := by
    intro state held wellFormed id member
    rcases member with leftMember | rightMember
    · exact left.allocated held.2.1 wellFormed id leftMember
    · exact right.allocated held.2.2 wellFormed id rightMember

infixr:55 " ⋆ " => Assertion.sep

def Entails (left right : Assertion) : Prop :=
  ∀ state, StateWellFormed state → left.holds state → right.holds state

infix:50 " ⊢ₛ " => Assertion.Entails

theorem sep_comm (left right : Assertion) :
    (left ⋆ right).holds state ↔ (right ⋆ left).holds state := by
  simp only [sep]
  constructor
  · rintro ⟨disjoint, leftHeld, rightHeld⟩
    exact ⟨CellSet.Disjoint.symm disjoint, rightHeld, leftHeld⟩
  · rintro ⟨disjoint, rightHeld, leftHeld⟩
    exact ⟨CellSet.Disjoint.symm disjoint, leftHeld, rightHeld⟩

theorem sep_assoc (first second third : Assertion) :
    ((first ⋆ second) ⋆ third).holds state ↔
      (first ⋆ (second ⋆ third)).holds state := by
  simp only [sep]
  constructor
  · rintro ⟨outer, ⟨inner, firstHeld, secondHeld⟩, thirdHeld⟩
    have firstSecond := inner
    have firstThird : CellSet.Disjoint first.footprint third.footprint :=
      fun id firstMember thirdMember => outer id (Or.inl firstMember) thirdMember
    have secondThird : CellSet.Disjoint second.footprint third.footprint :=
      fun id secondMember thirdMember => outer id (Or.inr secondMember) thirdMember
    have firstOuter : CellSet.Disjoint first.footprint
        (CellSet.union second.footprint third.footprint) := by
      intro id firstMember member
      exact member.elim (firstSecond id firstMember) (firstThird id firstMember)
    exact ⟨firstOuter, firstHeld,
      ⟨secondThird, secondHeld, thirdHeld⟩⟩
  · rintro ⟨outer, firstHeld, ⟨inner, secondHeld, thirdHeld⟩⟩
    have firstSecond : CellSet.Disjoint first.footprint second.footprint :=
      fun id firstMember secondMember =>
        outer id firstMember (Or.inl secondMember)
    have firstThird : CellSet.Disjoint first.footprint third.footprint :=
      fun id firstMember thirdMember =>
        outer id firstMember (Or.inr thirdMember)
    have unionThird : CellSet.Disjoint
        (CellSet.union first.footprint second.footprint) third.footprint := by
      intro id member thirdMember
      cases member with
      | inl firstMember => exact firstThird id firstMember thirdMember
      | inr secondMember => exact inner id secondMember thirdMember
    exact ⟨unionThird, ⟨firstSecond, firstHeld, secondHeld⟩,
      thirdHeld⟩

end Assertion

theorem StateWellFormed.cell_lt_next_of_entry
    (wellFormed : StateWellFormed state)
    (found : state.cellEntry? cell = some {
      id := cell
      value := value
    }) :
    cell < state.nextCell := by
  have member : { id := cell, value := value } ∈ state.cells :=
    List.mem_of_find?_eq_some found
  exact wellFormed.cellIdsBelowNext _ member

theorem StateWellFormed.cell_lt_next_of_local_binding
    (id : VarId) (cell : CellId)
    (wellFormed : StateWellFormed state)
    (found : state.cellId? id = some cell) :
    cell < state.nextCell := by
  unfold State.cellId? at found
  rw [Option.map_eq_some_iff] at found
  obtain ⟨binding, bindingFound, bindingCell⟩ := found
  have bindingMember : binding ∈ state.locals :=
    List.mem_of_find?_eq_some bindingFound
  obtain ⟨entry, entryMember, entryId⟩ :=
    wellFormed.localsReferenceCells binding bindingMember
  rw [← bindingCell, ← entryId]
  exact wellFormed.cellIdsBelowNext entry entryMember

theorem bindLocal_preserves_other_local
    (wellFormed : StateWellFormed state)
    (different : boundId ≠ queriedId) :
    (state.bindLocal boundId value).local? queriedId =
      state.local? queriedId := by
  have cellIdPreserved :
      (state.bindLocal boundId value).cellId? queriedId =
        state.cellId? queriedId := by
    simp [State.bindLocal, State.bindCell, State.cellId?, different]
  unfold State.local?
  rw [cellIdPreserved]
  cases found : state.cellId? queriedId with
  | none => rfl
  | some cell =>
      simp only [Option.bind_some]
      unfold State.cell?
      simp only [State.bindLocal]
      rw [bindCell_preserves_old_cell state boundId (some value) cell
      (Lanius.Separation.StateWellFormed.cell_lt_next_of_local_binding
          queriedId cell wellFormed found)]

/-- A freshly bound temporary immediately reads back as the bound value.
    This is the local-variable introduction rule used by extracted `let`
    proofs; the allocated cell identity remains available separately when a
    proof must hide that temporary at scope exit. -/
theorem bindLocal_finds_local
    (state : State) (id : VarId) (value : Value)
    (wellFormed : StateWellFormed state) :
    (state.bindLocal id value).local? id = some value := by
  have owned : (Assertion.localPointsTo id state.nextCell
      (some value)).holds (state.bindLocal id value) := by
    constructor
    · simp [State.bindLocal, State.bindCell, State.cellId?]
    · simpa [State.bindLocal] using
        bindCell_finds_fresh_cell state id (some value) wellFormed
  exact Assertion.localPointsTo_local id state.nextCell value
    (state.bindLocal id value) owned

/-- Binding a local allocates and owns exactly the caller's next fresh cell.
    Exposing the ownership fact directly lets loop invariants name their
    induction-variable cell without reconstructing it from a value read. -/
theorem bindLocal_owns_fresh
    (state : State) (id : VarId) (value : Value)
    (wellFormed : StateWellFormed state) :
    (Assertion.localPointsTo id state.nextCell (some value)).holds
      (state.bindLocal id value) := by
  constructor
  · simp [State.bindLocal, State.bindCell, State.cellId?]
  · simpa [State.bindLocal] using
      bindCell_finds_fresh_cell state id (some value) wellFormed

/-- A freshly allocated local cell cannot alias any different local that was
    already live in the caller. -/
theorem bindLocal_other_cellId_ne_fresh
    (state : State) (boundId queriedId : VarId) (value : Value)
    (wellFormed : StateWellFormed state) (different : boundId ≠ queriedId) :
    (state.bindLocal boundId value).cellId? queriedId ≠
      some state.nextCell := by
  have preserved : (state.bindLocal boundId value).cellId? queriedId =
      state.cellId? queriedId := by
    simp [State.bindLocal, State.bindCell, State.cellId?, different]
  rw [preserved]
  intro found
  have below : state.nextCell < state.nextCell :=
    Lanius.Separation.StateWellFormed.cell_lt_next_of_local_binding queriedId
      state.nextCell wellFormed found
  exact (Nat.lt_irrefl state.nextCell) below

/-- Binding a local that is absent from a checked source frame allocates a
    cell disjoint from every local represented by that frame.  This packages
    the recurring bridge from declaration-level freshness to physical-cell
    separation. -/
theorem bindLocal_fresh_disjoint_from_frame
    (state : State) (boundId : VarId) (value : Value)
    (frame : LocalBindingFrame)
    (wellFormed : StateWellFormed state)
    (boundNotInFrame : ¬ frame.ContainsCoreId boundId) :
    CellSet.Disjoint
      (localBindingFrameFootprint (state.bindLocal boundId value) frame)
      (CellSet.singleton state.nextCell) := by
  apply localBindingFrameFootprint_disjoint_singleton
  intro queriedId member
  apply bindLocal_other_cellId_ne_fresh state boundId queriedId value wellFormed
  intro same
  exact boundNotInFrame (same ▸ member)

/-- Binding a different variable leaves an existing local-to-cell mapping
    unchanged.  This identity-level rule complements the value-level local
    preservation lemmas below. -/
theorem bindLocal_preserves_other_cellId
    (state : State) (boundId queriedId : VarId) (value : Value)
    (different : boundId ≠ queriedId) :
    (state.bindLocal boundId value).cellId? queriedId =
      state.cellId? queriedId := by
  simp [State.bindLocal, State.bindCell, State.cellId?, different]

/-- A fresh-cell identity is also distinct from every cell already present in
    the caller's physical store. -/
theorem StateWellFormed.nextCell_ne_of_entry
    (wellFormed : StateWellFormed state)
    (found : state.cellEntry? cell = some { id := cell, value := value }) :
    state.nextCell ≠ cell := by
  exact Nat.ne_of_gt
    (Lanius.Separation.StateWellFormed.cell_lt_next_of_entry wellFormed found)

/-- Binding a distinct temporary preserves ownership of an existing local.
    This is stronger than preserving the local's read value: subsequent
    proofs may still assign through the original local after introducing
    nested extracted `let` bindings. -/
theorem bindLocal_preserves_localPointsTo_of_ne
    (state : State) (boundId queriedId : VarId) (boundValue : Value)
    (cell : CellId) (value : Option Value)
    (wellFormed : StateWellFormed state)
    (different : boundId ≠ queriedId)
    (owned : (Assertion.localPointsTo queriedId cell value).holds state) :
    (Assertion.localPointsTo queriedId cell value).holds
      (state.bindLocal boundId boundValue) := by
  constructor
  · have preserved :
        (state.bindLocal boundId boundValue).cellId? queriedId =
          state.cellId? queriedId := by
      simp [State.bindLocal, State.bindCell, State.cellId?, different]
    exact preserved.trans owned.1
  · have old :=
      StateWellFormed.cell_lt_next_of_entry wellFormed owned.2
    exact (by
      simpa [State.bindLocal] using
        (bindCell_preserves_old_cell state boundId (some boundValue) cell old)
      : (state.bindLocal boundId boundValue).cellEntry? cell =
          state.cellEntry? cell) |>.trans owned.2

/-- Every physical cell that existed before an operation still has a cell
with the same identity afterwards. Its contents may have changed. This is the
minimum domain fact needed to restore a caller's lexical environment safely. -/
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
    CellDomainExtension before
      (Lanius.Semantics.restoreLocals caller completed) := by
  constructor
  intro entry member
  simpa [Lanius.Semantics.restoreLocals] using extension.cells entry member

theorem CellDomainExtension.restoreLocals_wellFormed
    (extension : CellDomainExtension before completed)
    (beforeWellFormed : StateWellFormed before)
    (completedWellFormed : StateWellFormed completed) :
    StateWellFormed
      (Lanius.Semantics.restoreLocals before completed) := by
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

theorem bindLocal_domainExtension (state : State) (id : VarId) (value : Value) :
    CellDomainExtension state (state.bindLocal id value) := by
  constructor
  intro entry member
  exact ⟨entry, List.mem_append_left _ member, rfl⟩

theorem bindUninitialized_domainExtension (state : State) (id : VarId) :
    CellDomainExtension state (state.bindUninitialized id) := by
  constructor
  intro entry member
  exact ⟨entry, List.mem_append_left _ member, rfl⟩

theorem assignCell_domainExtension
    (assigned : before.assignCell cell value = some after) :
    CellDomainExtension before after := by
  rw [assignCell_state assigned, replaceCell_eq_map]
  constructor
  intro entry member
  let updated :=
    if entry.id == cell then { entry with value := some value } else entry
  refine ⟨updated, List.mem_map.2 ⟨entry, member, rfl⟩, ?_⟩
  exact updatedCell_id entry cell value

/-- State change before lexical locals are restored. Only `writes` may change
among pre-existing cells; fresh cells may be appended. -/
structure StoreEffect (writes : CellSet) (before after : State) : Prop where
  oldCells : ∀ cell, cell < before.nextCell → ¬ writes cell →
    after.cellEntry? cell = before.cellEntry? cell
  nextCell : before.nextCell ≤ after.nextCell
  heap : after.heap = before.heap
  world : after.world = before.world
  views : after.i32ArrayViews = before.i32ArrayViews
  domain : CellDomainExtension before after

/-- A completed command effect additionally restores the caller's lexical
environment. This is the relation used by the frame rule. -/
structure ModifiesOnly (writes : CellSet) (before after : State) : Prop
    extends StoreEffect writes before after where
  locals : after.locals = before.locals

/-- A completed command effect never changes lexical local-to-cell mappings;
    its write footprint concerns cell contents only. -/
theorem ModifiesOnly.preserves_cellId
    (effect : ModifiesOnly writes before after) (id : VarId) :
    after.cellId? id = before.cellId? id := by
  unfold State.cellId?
  rw [effect.locals]

/-- Completed effects preserve the physical footprint of every logical local
    frame because they restore the caller's local-to-cell environment. -/
theorem ModifiesOnly.localCellFootprint_eq
    (effect : ModifiesOnly writes before after) (locals : VarId → Prop) :
    localCellFootprint after locals = localCellFootprint before locals := by
  funext cell
  apply propext
  constructor
  · rintro ⟨id, member, found⟩
    rw [effect.preserves_cellId id] at found
    exact ⟨id, member, found⟩
  · rintro ⟨id, member, found⟩
    refine ⟨id, member, ?_⟩
    rw [effect.preserves_cellId id]
    exact found

theorem ModifiesOnly.localBindingFrameFootprint_eq
    (effect : ModifiesOnly writes before after) (frame : LocalBindingFrame) :
    localBindingFrameFootprint after frame =
      localBindingFrameFootprint before frame := by
  exact effect.localCellFootprint_eq frame.ContainsCoreId

theorem ModifiesOnly.preserves_entry
    {before after : State} {cell : CellId} {value : Option Value}
    (effect : ModifiesOnly writes before after)
    (beforeWellFormed : StateWellFormed before)
    (found : before.cellEntry? cell = some {
      id := cell
      value := value
    })
    (notWritten : ¬ writes cell) :
    after.cellEntry? cell = some { id := cell, value := value } := by
  have old := Lanius.Separation.StateWellFormed.cell_lt_next_of_entry
    beforeWellFormed found
  exact (effect.oldCells cell old notWritten).trans found

theorem ModifiesOnly.empty_preserves_entry
    {before after : State} {cell : CellId} {value : Option Value}
    (effect : ModifiesOnly CellSet.empty before after)
    (beforeWellFormed : StateWellFormed before)
    (found : before.cellEntry? cell = some {
      id := cell
      value := value
    }) :
    after.cellEntry? cell = some { id := cell, value := value } := by
  exact effect.preserves_entry beforeWellFormed found (by simp [CellSet.empty])

theorem ModifiesOnly.preserves_local
    {before after : State} {id : VarId} {value : Value}
    (effect : ModifiesOnly writes before after)
    (beforeWellFormed : StateWellFormed before)
    (found : before.local? id = some value)
    (notWritten : ∀ cell, before.cellId? id = some cell → ¬ writes cell) :
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
    exact beforeWellFormed.cellIdsBelowNext entry member
  have afterCellId : after.cellId? id = some cell := by
    unfold State.cellId?
    rw [effect.locals]
    exact cellId
  rw [State.local?, afterCellId]
  simp only [Option.bind_some, State.cell?, Option.bind_eq_some_iff]
  refine ⟨entry, ?_, initialized⟩
  exact (effect.oldCells cell old (notWritten cell cellId)).trans cellEntry

/-- Every value in a logical local frame survives an effect whose write
    footprint is disjoint from the cells currently backing that frame. -/
theorem ModifiesOnly.preserves_local_of_disjoint
    {before after : State} {locals : VarId → Prop} {id : VarId} {value : Value}
    (effect : ModifiesOnly writes before after)
    (beforeWellFormed : StateWellFormed before)
    (disjoint : CellSet.Disjoint (localCellFootprint before locals) writes)
    (member : locals id)
    (found : before.local? id = some value) :
    after.local? id = some value := by
  apply effect.preserves_local beforeWellFormed found
  intro cell cellId written
  exact disjoint cell ⟨id, member, cellId⟩ written

/-- Ownership of a local survives an effect that cannot write its backing
    cell.  Unlike `preserves_local`, this retains the physical cell identity,
    so a caller can continue assigning through the local or use it as a
    separation witness after a nested loop completes. -/
theorem ModifiesOnly.preserves_localPointsTo
    {before after : State} {id : VarId} {cell : CellId}
    {value : Option Value}
    (effect : ModifiesOnly writes before after)
    (beforeWellFormed : StateWellFormed before)
    (owned : (Assertion.localPointsTo id cell value).holds before)
    (notWritten : ¬ writes cell) :
    (Assertion.localPointsTo id cell value).holds after := by
  constructor
  · change after.cellId? id = some cell
    unfold State.cellId?
    rw [effect.locals]
    exact owned.1
  · exact effect.preserves_entry beforeWellFormed owned.2 notWritten

/-- A write to one distinguished cell preserves a local whose value differs
    from the value stored in that cell.  This is the useful value-level form
    of separation for generated code: callers need not expose the allocation
    identity of every scalar or aggregate temporary merely to show that an
    unrelated array-backing write leaves it alone. -/
theorem ModifiesOnly.singleton_preserves_local_of_ne
    {before after : State} {written : CellId} {writtenValue localValue : Value}
    {id : VarId}
    (effect : ModifiesOnly (CellSet.singleton written) before after)
    (beforeWellFormed : StateWellFormed before)
    (found : before.local? id = some localValue)
    (backing : before.cellEntry? written = some {
      id := written
      value := some writtenValue
    })
    (different : localValue ≠ writtenValue) :
    after.local? id = some localValue := by
  apply effect.preserves_local beforeWellFormed found
  intro cell cellId writtenCell
  have sameCell : cell = written := writtenCell
  subst cell
  rw [State.local?, cellId] at found
  simp only [Option.bind_some, State.cell?, backing, Cell.value,
    Option.bind_some] at found
  exact different (Option.some.inj found).symm

theorem ModifiesOnly.empty_preserves_local
    {before after : State} {id : VarId} {value : Value}
    (effect : ModifiesOnly CellSet.empty before after)
    (beforeWellFormed : StateWellFormed before)
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
    exact beforeWellFormed.cellIdsBelowNext entry member
  have afterCellId : after.cellId? id = some cell := by
    unfold State.cellId?
    rw [effect.locals]
    exact cellId
  rw [State.local?, afterCellId]
  simp only [Option.bind_some, State.cell?, Option.bind_eq_some_iff]
  refine ⟨entry, ?_, initialized⟩
  exact (effect.oldCells cell old (by simp [CellSet.empty])).trans cellEntry

theorem StoreEffect.refl (state : State) :
    StoreEffect CellSet.empty state state := by
  exact ⟨fun _ _ _ => rfl, Nat.le_refl _, rfl, rfl, rfl,
    CellDomainExtension.refl state⟩

theorem ModifiesOnly.refl (state : State) :
    ModifiesOnly CellSet.empty state state := by
  exact ⟨StoreEffect.refl state, rfl⟩

theorem ModifiesOnly.reflAny (writes : CellSet) (state : State) :
    ModifiesOnly writes state state := by
  exact ⟨⟨fun _ _ _ => rfl, Nat.le_refl _, rfl, rfl, rfl,
    CellDomainExtension.refl state⟩, rfl⟩

theorem StoreEffect.trans
    (first : StoreEffect firstWrites before middle)
    (second : StoreEffect secondWrites middle after) :
    StoreEffect (CellSet.union firstWrites secondWrites) before after := by
  constructor
  · intro cell old notWritten
    have notFirst : ¬ firstWrites cell := by
      intro member
      exact notWritten (Or.inl member)
    have notSecond : ¬ secondWrites cell := by
      intro member
      exact notWritten (Or.inr member)
    rw [second.oldCells cell (Nat.lt_of_lt_of_le old first.nextCell) notSecond,
      first.oldCells cell old notFirst]
  · exact Nat.le_trans first.nextCell second.nextCell
  · exact second.heap.trans first.heap
  · exact second.world.trans first.world
  · exact second.views.trans first.views
  · exact first.domain.trans second.domain

theorem ModifiesOnly.trans
    (first : ModifiesOnly firstWrites before middle)
    (second : ModifiesOnly secondWrites middle after) :
    ModifiesOnly (CellSet.union firstWrites secondWrites) before after := by
  exact ⟨first.toStoreEffect.trans second.toStoreEffect,
    second.locals.trans first.locals⟩

theorem ModifiesOnly.trans_same
    (first : ModifiesOnly writes before middle)
    (second : ModifiesOnly writes middle after) :
    ModifiesOnly writes before after := by
  have combined := first.trans second
  constructor
  · constructor
    · intro cell old notWritten
      exact combined.oldCells cell old (by
        intro written
        exact written.elim notWritten notWritten)
    · exact combined.nextCell
    · exact combined.heap
    · exact combined.world
    · exact combined.views
    · exact combined.domain
  · exact combined.locals

theorem StoreEffect.trans_same
    (first : StoreEffect writes before middle)
    (second : StoreEffect writes middle after) :
    StoreEffect writes before after := by
  have combined := first.trans second
  constructor
  · intro cell old notWritten
    exact combined.oldCells cell old (by
      intro written
      exact written.elim notWritten notWritten)
  · exact combined.nextCell
  · exact combined.heap
  · exact combined.world
  · exact combined.views
  · exact combined.domain

theorem StoreEffect.weaken
    (effect : StoreEffect smaller before after)
    (subset : CellSet.Subset smaller larger) :
    StoreEffect larger before after := by
  constructor
  · intro cell old notWritten
    exact effect.oldCells cell old (fun written => notWritten (subset cell written))
  · exact effect.nextCell
  · exact effect.heap
  · exact effect.world
  · exact effect.views
  · exact effect.domain

theorem ModifiesOnly.weaken
    (effect : ModifiesOnly smaller before after)
    (subset : CellSet.Subset smaller larger) :
    ModifiesOnly larger before after :=
  ⟨effect.toStoreEffect.weaken subset, effect.locals⟩

/-- Writes confined to cells allocated at or after the operation's initial
    frontier are not mutations of caller-visible storage.  Reclassifying such
    writes as an empty effect is what lets temporary locals disappear at
    scope and call boundaries. -/
theorem StoreEffect.hideFreshWrites
    (effect : StoreEffect writes before after)
    (fresh : ∀ cell, writes cell → before.nextCell ≤ cell) :
    StoreEffect CellSet.empty before after := by
  constructor
  · intro cell old _
    apply effect.oldCells cell old
    intro written
    exact (Nat.not_lt_of_ge (fresh cell written)) old
  · exact effect.nextCell
  · exact effect.heap
  · exact effect.world
  · exact effect.views
  · exact effect.domain

theorem ModifiesOnly.hideFreshWrites
    (effect : ModifiesOnly writes before after)
    (fresh : ∀ cell, writes cell → before.nextCell ≤ cell) :
    ModifiesOnly CellSet.empty before after :=
  ⟨effect.toStoreEffect.hideFreshWrites fresh, effect.locals⟩

/-- Reclassify writes to cells allocated during an operation as invisible to
    its caller while retaining a chosen set of writes to pre-existing cells.
    This is the mixed-effect counterpart of `hideFreshWrites`: it is needed
    when a scoped loop mutates both its fresh induction variable and an owned
    cell from an enclosing scope. -/
theorem StoreEffect.hideFreshWritesExcept
    (effect : StoreEffect writes before after)
    (classify : ∀ cell, writes cell →
      retained cell ∨ before.nextCell ≤ cell) :
    StoreEffect retained before after := by
  constructor
  · intro cell old notRetained
    apply effect.oldCells cell old
    intro written
    exact (classify cell written).elim notRetained
      (fun fresh => (Nat.not_lt_of_ge fresh) old)
  · exact effect.nextCell
  · exact effect.heap
  · exact effect.world
  · exact effect.views
  · exact effect.domain

theorem ModifiesOnly.hideFreshWritesExcept
    (effect : ModifiesOnly writes before after)
    (classify : ∀ cell, writes cell →
      retained cell ∨ before.nextCell ≤ cell) :
    ModifiesOnly retained before after :=
  ⟨effect.toStoreEffect.hideFreshWritesExcept classify, effect.locals⟩

theorem StoreEffect.restoreLocals
    (effect : StoreEffect writes before completed) :
    ModifiesOnly writes before
      (Lanius.Semantics.restoreLocals before completed) := by
  exact ⟨⟨effect.oldCells, effect.nextCell, effect.heap, effect.world,
    effect.views, effect.domain.restoreLocals⟩, rfl⟩

theorem StoreEffect.restoreLocals_wellFormed
    (effect : StoreEffect writes before completed)
    (beforeWellFormed : StateWellFormed before)
    (completedWellFormed : StateWellFormed completed) :
    StateWellFormed
      (Lanius.Semantics.restoreLocals before completed) :=
  effect.domain.restoreLocals_wellFormed beforeWellFormed completedWellFormed

theorem bindLocal_effect (state : State) (id : VarId) (value : Value) :
    StoreEffect CellSet.empty state (state.bindLocal id value) := by
  constructor
  · intro cell old _
    exact bindCell_preserves_old_cell state id (some value) cell old
  · simp [State.bindLocal, State.bindCell]
  · rfl
  · rfl
  · rfl
  · exact bindLocal_domainExtension state id value

theorem bindUninitialized_effect (state : State) (id : VarId) :
    StoreEffect CellSet.empty state (state.bindUninitialized id) := by
  constructor
  · intro cell old _
    exact bindCell_preserves_old_cell state id none cell old
  · simp [State.bindUninitialized, State.bindCell]
  · rfl
  · rfl
  · rfl
  · exact bindUninitialized_domainExtension state id

theorem bindLocals_effect
    (state : State) (bindings : List (VarId × Value)) :
    StoreEffect CellSet.empty state (state.bindLocals bindings) := by
  induction bindings generalizing state with
  | nil => simpa [State.bindLocals] using StoreEffect.refl state
  | cons binding rest inductionHypothesis =>
      simp only [State.bindLocals, List.foldl_cons]
      have first := bindLocal_effect state binding.1 binding.2
      have remaining := inductionHypothesis (state.bindLocal binding.1 binding.2)
      exact first.trans_same remaining

theorem bindLocals_preserves_wellFormed
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

/-- Binding a list that never shadows a queried local preserves that local's
    physical cell identity. -/
theorem bindLocals_preserves_cellId
    (state : State) (bindings : List (VarId × Value)) (queriedId : VarId)
    (notRebound : ∀ binding, binding ∈ bindings →
      binding.1 ≠ queriedId) :
    (state.bindLocals bindings).cellId? queriedId = state.cellId? queriedId := by
  induction bindings generalizing state with
  | nil => rfl
  | cons binding rest inductionHypothesis =>
      simp only [State.bindLocals, List.foldl_cons]
      change ((state.bindLocal binding.1 binding.2).bindLocals rest).cellId?
        queriedId = state.cellId? queriedId
      rw [inductionHypothesis (state := state.bindLocal binding.1 binding.2)
        (fun later member =>
          notRebound later (List.mem_cons_of_mem binding member))]
      exact bindLocal_preserves_other_cellId state binding.1 queriedId
        binding.2 (notRebound binding (by simp))

/-- Binding a list that never shadows a queried local preserves its value. -/
theorem bindLocals_preserves_local
    (state : State) (bindings : List (VarId × Value)) (queriedId : VarId)
    (value : Value) (wellFormed : StateWellFormed state)
    (found : state.local? queriedId = some value)
    (notRebound : ∀ binding, binding ∈ bindings →
      binding.1 ≠ queriedId) :
    (state.bindLocals bindings).local? queriedId = some value := by
  induction bindings generalizing state with
  | nil => simpa [State.bindLocals] using found
  | cons binding rest inductionHypothesis =>
      simp only [State.bindLocals, List.foldl_cons]
      have different := notRebound binding (by simp)
      have nextFound :=
        (bindLocal_preserves_other_local (state := state)
          (boundId := binding.1) (queriedId := queriedId)
          (value := binding.2) wellFormed different).trans found
      exact inductionHypothesis (state := state.bindLocal binding.1 binding.2)
        (bindLocal_preserves_well_formed state binding.1 binding.2 wellFormed)
        nextFound (fun later member =>
          notRebound later (List.mem_cons_of_mem binding member))

theorem bindLocals_preserves_old_cell
    (state : State) (bindings : List (VarId × Value)) (cell : CellId)
    (old : cell < state.nextCell) :
    (state.bindLocals bindings).cellEntry? cell = state.cellEntry? cell := by
  exact (bindLocals_effect state bindings).oldCells cell old (by
    simp [CellSet.empty])

theorem bindLocals_append
    (state : State) (first second : List (VarId × Value)) :
    state.bindLocals (first ++ second) =
      (state.bindLocals first).bindLocals second := by
  simp [State.bindLocals, List.foldl_append]

/-- The cell allocated for a binding remains discoverable after later,
    distinct lexical bindings are allocated. This is the physical half of
    the generic call-parameter rule. -/
theorem bindLocals_finds_cell_after_prefix
    (state : State) (preceding following : List (VarId × Value))
    (id : VarId) (value : Value) (wellFormed : StateWellFormed state) :
    (state.bindLocals (preceding ++ (id, value) :: following)).cellEntry?
        (state.nextCell + preceding.length) =
      some { id := state.nextCell + preceding.length, value := some value } := by
  let before := state.bindLocals preceding
  have beforeWellFormed := bindLocals_preserves_wellFormed state preceding
    wellFormed
  have beforeNext : before.nextCell = state.nextCell + preceding.length :=
    bindLocals_nextCell state preceding
  have fresh := bindCell_finds_fresh_cell before id (some value)
    beforeWellFormed
  have old : before.nextCell < (before.bindLocal id value).nextCell := by
    simp [State.bindLocal, State.bindCell]
  have preserved := bindLocals_preserves_old_cell
    (before.bindLocal id value) following before.nextCell old
  rw [bindLocals_append]
  change ((before.bindLocal id value).bindLocals following).cellEntry?
      (state.nextCell + preceding.length) = _
  rw [← beforeNext]
  exact preserved.trans (by simpa [State.bindLocal] using fresh)

/-- A selected binding owns its fresh cell after any later, non-shadowing
    lexical bindings have been introduced. -/
theorem bindLocals_owns_binding
    (state : State) (preceding following : List (VarId × Value))
    (id : VarId) (value : Value) (wellFormed : StateWellFormed state)
    (notRebound : ∀ binding, binding ∈ following → binding.1 ≠ id) :
    (Assertion.localPointsTo id (state.nextCell + preceding.length)
      (some value)).holds
      (state.bindLocals (preceding ++ (id, value) :: following)) := by
  let before := state.bindLocals preceding
  have beforeNext : before.nextCell = state.nextCell + preceding.length :=
    bindLocals_nextCell state preceding
  have localCell :
      (state.bindLocals (preceding ++ (id, value) :: following)).cellId? id =
        some (state.nextCell + preceding.length) := by
    rw [bindLocals_append]
    change ((before.bindLocal id value).bindLocals following).cellId? id = _
    rw [bindLocals_preserves_cellId _ following id notRebound]
    simp [State.bindLocal, State.bindCell, State.cellId?, beforeNext]
  exact ⟨localCell, bindLocals_finds_cell_after_prefix state preceding following
    id value wellFormed⟩

/-- Binding parameters whose later identifiers are distinct preserves the
    value of the selected binding.  This is the lexical half of the generic
    call-parameter rule; `bindLocals_finds_cell_after_prefix` supplies its
    physical-cell half. -/
theorem bindLocals_local_of_binding
    (state : State) (preceding following : List (VarId × Value))
    (id : VarId) (value : Value) (wellFormed : StateWellFormed state)
    (notRebound : ∀ binding, binding ∈ following → binding.1 ≠ id) :
    (state.bindLocals (preceding ++ (id, value) :: following)).local? id =
      some value := by
  let before := state.bindLocals preceding
  have beforeWellFormed : StateWellFormed before :=
    bindLocals_preserves_wellFormed state preceding wellFormed
  let bound := before.bindLocal id value
  have owned : (Assertion.localPointsTo id before.nextCell
      (some value)).holds bound := by
    constructor
    · simp [bound, State.bindLocal, State.bindCell, State.cellId?]
    · simpa [bound, State.bindLocal] using
        bindCell_finds_fresh_cell before id (some value) beforeWellFormed
  have initiallyFound : bound.local? id = some value :=
    Assertion.localPointsTo_local id before.nextCell value bound owned
  rw [bindLocals_append]
  change (bound.bindLocals following).local? id = some value
  have preserveFollowing : ∀ (current : State)
      (bindings : List (VarId × Value)),
      StateWellFormed current →
      current.local? id = some value →
      (∀ binding, binding ∈ bindings → binding.1 ≠ id) →
      (current.bindLocals bindings).local? id = some value := by
    intro current bindings
    induction bindings generalizing current with
    | nil =>
        intro _ found _
        simpa [State.bindLocals] using found
    | cons binding rest inductionHypothesis =>
        intro currentWellFormed found distinct
        simp only [State.bindLocals, List.foldl_cons]
        have bindingDifferent : binding.1 ≠ id :=
          distinct binding (by simp)
        have afterBindingWellFormed := bindLocal_preserves_well_formed current
          binding.1 binding.2 currentWellFormed
        have afterBindingFound :
            (current.bindLocal binding.1 binding.2).local? id = some value :=
          (bindLocal_preserves_other_local currentWellFormed
            bindingDifferent).trans found
        exact inductionHypothesis
          (current.bindLocal binding.1 binding.2)
          afterBindingWellFormed afterBindingFound
          (fun later laterMember =>
            distinct later (List.mem_cons_of_mem binding laterMember))
  exact preserveFollowing bound following
    (bindLocal_preserves_well_formed before id value beforeWellFormed)
    initiallyFound notRebound

/-- The state used to execute a function body. Calls retain the physical cell
store but replace the caller's lexical environment with parameter bindings. -/
def enterCall (caller : State) (bindings : List (VarId × Value)) : State :=
  ({ caller with locals := [] }).bindLocals bindings

theorem clearLocals_effect (state : State) :
    StoreEffect CellSet.empty state { state with locals := [] } := by
  constructor
  · intro _ _ _
    rfl
  · exact Nat.le_refl _
  · rfl
  · rfl
  · rfl
  · exact ⟨fun entry member => ⟨entry, member, rfl⟩⟩

theorem clearLocals_preserves_wellFormed
    (wellFormed : StateWellFormed state) :
    StateWellFormed { state with locals := [] } := by
  refine ⟨wellFormed.heapWellFormed, wellFormed.cellIdsUnique,
    wellFormed.cellIdsBelowNext, ?_⟩
  simp [LocalsReferenceCells]

/-- A source-call parameter with no later rebinding reads as its argument in
    the callee frame. -/
theorem enterCall_local_of_binding
    (caller : State) (preceding following : List (VarId × Value))
    (id : VarId) (value : Value) (wellFormed : StateWellFormed caller)
    (notRebound : ∀ binding, binding ∈ following → binding.1 ≠ id) :
    (enterCall caller (preceding ++ (id, value) :: following)).local? id =
      some value := by
  exact bindLocals_local_of_binding { caller with locals := [] }
    preceding following id value (clearLocals_preserves_wellFormed wellFormed)
    notRebound

theorem enterCall_effect (caller : State)
    (bindings : List (VarId × Value)) :
    StoreEffect CellSet.empty caller (enterCall caller bindings) := by
  exact (clearLocals_effect caller).trans_same
    (bindLocals_effect { caller with locals := [] } bindings)

theorem enterCall_preserves_wellFormed
    (callerWellFormed : StateWellFormed caller) :
    StateWellFormed (enterCall caller bindings) := by
  exact bindLocals_preserves_wellFormed { caller with locals := [] } bindings
    (clearLocals_preserves_wellFormed callerWellFormed)

/-- Close a temporary-local scope. The temporary allocation is fresh and the
body may mutate only `writes`; restoration makes the whole scope frameable. -/
theorem temporaryLocal_effect
    (id : VarId) (value : Value)
    (body : StoreEffect writes (before.bindLocal id value) completed) :
    ModifiesOnly writes before
      (Lanius.Semantics.restoreLocals before completed) := by
  have entered : StoreEffect writes before (before.bindLocal id value) :=
    (bindLocal_effect before id value).weaken CellSet.empty_subset
  exact (entered.trans_same body).restoreLocals

/-- Function-call effect rule. The evaluator's call protocol clears caller
locals, binds parameters in fresh cells, executes the body, and restores the
caller environment. Only the body's declared writes escape the call. -/
theorem call_effect
    (body : StoreEffect writes (enterCall before bindings) completed) :
    ModifiesOnly writes before
      (Lanius.Semantics.restoreLocals before completed) := by
  have entered : StoreEffect writes before (enterCall before bindings) :=
    (enterCall_effect before bindings).weaken CellSet.empty_subset
  exact (entered.trans_same body).restoreLocals

theorem assignCell_effect
    (assigned : before.assignCell cell value = some after) :
    ModifiesOnly (CellSet.singleton cell) before after := by
  have stateEq := assignCell_state assigned
  constructor
  · constructor
    · intro queried _ notWritten
      have different : queried ≠ cell := notWritten
      exact assignCell_preserves_other assigned different
    · rw [stateEq]
      exact Nat.le_refl _
    · rw [stateEq]
    · rw [stateEq]
    · rw [stateEq]
    · exact assignCell_domainExtension assigned
  · rw [stateEq]

theorem assignCell_pointsTo
    {before after : State} {cell : CellId} {value : Value}
    (assigned : before.assignCell cell value = some after) :
    (Assertion.pointsTo cell (some value)).holds after :=
  assignCell_finds_assigned assigned

theorem assignCell_localPointsTo
    {before after : State} {id : VarId} {cell : CellId}
    {current : Option Value} {value : Value}
    (held : (Assertion.localPointsTo id cell current).holds before)
    (assigned : before.assignCell cell value = some after) :
    (Assertion.localPointsTo id cell (some value)).holds after := by
  constructor
  · rw [assignCell_state assigned]
    exact held.1
  · exact assignCell_finds_assigned assigned

theorem ModifiesOnly.agrees
    (effect : ModifiesOnly writes before after)
    (beforeWellFormed : StateWellFormed before)
    (assertion : Assertion)
    (held : assertion.holds before)
    (disjoint : CellSet.Disjoint assertion.footprint writes) :
    Agreement assertion.footprint before after := by
  constructor
  · exact effect.locals
  · intro cell member
    have old := assertion.allocated held beforeWellFormed cell member
    have notWritten : ¬ writes cell := by
      intro written
      exact disjoint cell member written
    exact effect.oldCells cell old notWritten
  · exact effect.heap
  · exact effect.world
  · exact effect.views

theorem ModifiesOnly.preserve
    (effect : ModifiesOnly writes before after)
    (beforeWellFormed : StateWellFormed before)
    (assertion : Assertion)
    (held : assertion.holds before)
    (disjoint : CellSet.Disjoint assertion.footprint writes) :
    assertion.holds after :=
  assertion.stable (effect.agrees beforeWellFormed assertion held disjoint) held

theorem ModifiesOnly.empty_preserves_assertion
    (effect : ModifiesOnly CellSet.empty before after)
    (beforeWellFormed : StateWellFormed before)
    (assertion : Assertion) (held : assertion.holds before) :
    assertion.holds after := by
  apply effect.preserve beforeWellFormed assertion held
  intro _ _ written
  exact written

theorem assignCell_preserves_pointsTo
    {before after : State} {written framed : CellId}
    {value : Value} {framedValue : Option Value}
    (wellFormed : StateWellFormed before)
    (assigned : before.assignCell written value = some after)
    (different : framed ≠ written)
    (held : (Assertion.pointsTo framed framedValue).holds before) :
    (Assertion.pointsTo framed framedValue).holds after := by
  apply (assignCell_effect assigned).preserve wellFormed
    (Assertion.pointsTo framed framedValue) held
  intro cell member writtenMember
  exact different (member.symm.trans writtenMember)

/-- An execution triple packages total execution, preservation of state
well-formedness, a postcondition, and the exact write footprint. -/
def EvalTriple
    (program : Program) (pre : Assertion) (expression : Expr)
    (value : Value) (post : Assertion) (writes : CellSet) : Prop :=
  ∀ before, StateWellFormed before → pre.holds before →
    ∃ after,
      Evaluates program before expression value after ∧
      StateWellFormed after ∧ post.holds after ∧
      ModifiesOnly writes before after

def ExecTriple
    (program : Program) (pre : Assertion) (statement : Stmt)
    (completion : Completion) (post : Assertion) (writes : CellSet) : Prop :=
  ∀ before, StateWellFormed before → pre.holds before →
    ∃ after,
      Executes program before statement completion after ∧
      StateWellFormed after ∧ post.holds after ∧
      ModifiesOnly writes before after

theorem EvalTriple.consequence
    (triple : EvalTriple program pre expression value post writes)
    (precondition : strongerPre ⊢ₛ pre)
    (postcondition : post ⊢ₛ weakerPost)
    (writeSubset : CellSet.Subset writes largerWrites) :
    EvalTriple program strongerPre expression value weakerPost largerWrites := by
  intro before beforeWellFormed held
  obtain ⟨after, execution, afterWellFormed, postHeld, effect⟩ :=
    triple before beforeWellFormed
      (precondition before beforeWellFormed held)
  exact ⟨after, execution, afterWellFormed,
    postcondition after afterWellFormed postHeld,
    effect.weaken writeSubset⟩

theorem ExecTriple.consequence
    (triple : ExecTriple program pre statement completion post writes)
    (precondition : strongerPre ⊢ₛ pre)
    (postcondition : post ⊢ₛ weakerPost)
    (writeSubset : CellSet.Subset writes largerWrites) :
    ExecTriple program strongerPre statement completion weakerPost
      largerWrites := by
  intro before beforeWellFormed held
  obtain ⟨after, execution, afterWellFormed, postHeld, effect⟩ :=
    triple before beforeWellFormed
      (precondition before beforeWellFormed held)
  exact ⟨after, execution, afterWellFormed,
    postcondition after afterWellFormed postHeld,
    effect.weaken writeSubset⟩

/-- Expression-level frame rule. Calls are expressions in Core, so this is
    also the frame rule used by source-function contracts. -/
theorem EvalTriple.frame
    (triple : EvalTriple program pre expression value post writes)
    (frame : Assertion)
    (postDisjoint : CellSet.Disjoint post.footprint frame.footprint)
    (writeDisjoint : CellSet.Disjoint frame.footprint writes) :
    EvalTriple program (pre ⋆ frame) expression value
      (post ⋆ frame) writes := by
  intro before beforeWellFormed held
  obtain ⟨after, execution, afterWellFormed, postHeld, effect⟩ :=
    triple before beforeWellFormed held.2.1
  have frameHeld := effect.preserve beforeWellFormed frame held.2.2
    writeDisjoint
  exact ⟨after, execution, afterWellFormed,
    ⟨postDisjoint, postHeld, frameHeld⟩, effect⟩

/-- The frame rule is independent of the statement syntax. Once a command's
write footprint is proved, every disjoint assertion is preserved without
repeating cell-by-cell bookkeeping. -/
theorem ExecTriple.frame
    (triple : ExecTriple program pre statement completion post writes)
    (frame : Assertion)
    (postDisjoint : CellSet.Disjoint post.footprint frame.footprint)
    (writeDisjoint : CellSet.Disjoint frame.footprint writes) :
    ExecTriple program (pre ⋆ frame) statement completion
      (post ⋆ frame) writes := by
  intro before beforeWellFormed held
  obtain ⟨after, execution, afterWellFormed, postHeld, effect⟩ :=
    triple before beforeWellFormed held.2.1
  have frameHeld := effect.preserve beforeWellFormed frame held.2.2
    writeDisjoint
  exact ⟨after, execution, afterWellFormed,
    ⟨postDisjoint, postHeld, frameHeld⟩, effect⟩

theorem ExecTriple.skip (pre : Assertion) :
    ExecTriple program pre .skip .next pre CellSet.empty := by
  intro before beforeWellFormed held
  exact ⟨before, executesSkip program before, beforeWellFormed, held,
    ModifiesOnly.refl before⟩

theorem EvalTriple.pureValue (pre : Assertion) (value : Value) :
    EvalTriple program pre (.value value) value pre CellSet.empty := by
  intro before beforeWellFormed held
  exact ⟨before, ⟨1, rfl⟩, beforeWellFormed, held,
    ModifiesOnly.refl before⟩

theorem EvalTriple.local
    (program : Program) (id : VarId) (cell : CellId) (value : Value) :
    EvalTriple program (Assertion.localPointsTo id cell (some value))
      (.local id) value
      (Assertion.localPointsTo id cell (some value)) CellSet.empty := by
  intro before beforeWellFormed held
  have execution : Evaluates program before (.local id) value before := by
    refine ⟨1, ?_⟩
    rw [Lanius.Semantics.evalExpr.eq_def]
    simp [held.1, held.2]
  exact ⟨before, execution, beforeWellFormed, held,
    ModifiesOnly.refl before⟩

theorem ExecTriple.sequence
    (firstTriple :
      ExecTriple program pre first .next middlePost firstWrites)
    (secondTriple :
      ExecTriple program middlePost second completion post secondWrites) :
    ExecTriple program pre (.sequence first second) completion post
      (CellSet.union firstWrites secondWrites) := by
  intro before beforeWellFormed held
  obtain ⟨middle, firstExecution, middleWellFormed, middleHeld,
      firstEffect⟩ := firstTriple before beforeWellFormed held
  obtain ⟨after, secondExecution, afterWellFormed, postHeld,
      secondEffect⟩ := secondTriple middle middleWellFormed middleHeld
  exact ⟨after, executesSequence firstExecution secondExecution,
    afterWellFormed, postHeld, firstEffect.trans secondEffect⟩

/-- Non-fallthrough completion bypasses the right side of a sequence and
therefore preserves the first command's postcondition and footprint. -/
theorem ExecTriple.sequenceNonNext
    (firstTriple : ExecTriple program pre first completion post writes)
    (notNext : completion ≠ .next) :
    ExecTriple program pre (.sequence first second) completion post writes := by
  intro before beforeWellFormed held
  obtain ⟨after, execution, afterWellFormed, postHeld, effect⟩ :=
    firstTriple before beforeWellFormed held
  exact ⟨after, executesSequenceNonNext execution notNext,
    afterWellFormed, postHeld, effect⟩

theorem EvalTriple.asStatement
    {expression : Expr} {value : Value}
    (triple : EvalTriple program pre expression value post writes) :
    ExecTriple program pre (.expression expression) .next post writes := by
  intro before beforeWellFormed held
  obtain ⟨after, execution, afterWellFormed, postHeld, effect⟩ :=
    triple before beforeWellFormed held
  exact ⟨after, executesExpression execution, afterWellFormed, postHeld,
    effect⟩

theorem EvalTriple.returnValue
    {expression : Expr} {value : Value}
    (triple : EvalTriple program pre expression value post writes) :
    ExecTriple program pre (.returnValue (some expression))
      (.returned (some value)) post writes := by
  intro before beforeWellFormed held
  obtain ⟨after, execution, afterWellFormed, postHeld, effect⟩ :=
    triple before beforeWellFormed held
  exact ⟨after, executesReturnValue execution, afterWellFormed, postHeld,
    effect⟩

theorem ExecTriple.returnNone (pre : Assertion) :
    ExecTriple program pre (.returnValue none) (.returned none) pre
      CellSet.empty := by
  intro before beforeWellFormed held
  exact ⟨before, executesReturnNone program before, beforeWellFormed, held,
    ModifiesOnly.refl before⟩

theorem ExecTriple.breakLoop (pre : Assertion) :
    ExecTriple program pre .breakLoop .breakLoop pre CellSet.empty := by
  intro before beforeWellFormed held
  exact ⟨before, executesBreak program before, beforeWellFormed, held,
    ModifiesOnly.refl before⟩

theorem ExecTriple.continueLoop (pre : Assertion) :
    ExecTriple program pre .continueLoop .continueLoop pre CellSet.empty := by
  intro before beforeWellFormed held
  exact ⟨before, executesContinue program before, beforeWellFormed, held,
    ModifiesOnly.refl before⟩

/-- Primitive mutation rule for assignment to an owned local cell. The rule
    applies equally to initialized and uninitialized locals because `.set`
    does not inspect the old value. -/
theorem EvalTriple.setLocal
    (program : Program) (id : VarId) (cell : CellId)
    (current : Option Value) (value : Value) :
    EvalTriple program (Assertion.localPointsTo id cell current)
      (.assign .set (.local id) (.value value)) .unit
      (Assertion.localPointsTo id cell (some value))
      (CellSet.singleton cell) := by
  intro before beforeWellFormed held
  let after : State :=
    { before with cells := replaceCell before.cells cell value }
  have assigned : before.assignCell cell value = some after := by
    simp [State.assignCell, held.2, after]
  have placeResult :
      evalPlace 1 program before (.local id) =
        .done { root := cell, projections := [], value := current } before := by
    rw [Lanius.Semantics.evalPlace.eq_def]
    simp [held.1, held.2]
  have valueResult : evalExpr 1 program before (.value value) =
      .done value before := by rfl
  have writeResult : writeResolvedPlace before
      { root := cell, projections := [], value := current } value =
      .ok after := by
    simp [writeResolvedPlace, assigned]
  have execution : Evaluates program before
      (.assign .set (.local id) (.value value)) .unit after := by
    refine ⟨2, ?_⟩
    rw [Lanius.Semantics.evalExpr.eq_def]
    simp only
    rw [placeResult]
    simp only
    rw [valueResult]
    simp only [evalAssignValue, assignOpBinary?]
    rw [writeResult]
  exact ⟨after, execution,
    assignCell_preserves_well_formed beforeWellFormed assigned,
    assignCell_localPointsTo held assigned,
    assignCell_effect assigned⟩

/-- General local assignment rule. The right-hand expression may itself have
effects, provided its postcondition retains ownership of the destination cell.
The final write is composed after those effects and updates only that cell. -/
theorem EvalTriple.setLocalFrom
    {id : VarId} {cell : CellId} {current : Option Value} {value : Value}
    (rightTriple :
      EvalTriple program (pre ⋆ Assertion.localPointsTo id cell current)
        right value (post ⋆ Assertion.localPointsTo id cell current)
        rightWrites) :
    EvalTriple program (pre ⋆ Assertion.localPointsTo id cell current)
      (.assign .set (.local id) right) .unit
      (post ⋆ Assertion.localPointsTo id cell (some value))
      (CellSet.union rightWrites (CellSet.singleton cell)) := by
  intro before beforeWellFormed held
  obtain ⟨afterRight, rightExecution, afterRightWellFormed, rightPostHeld,
      rightEffect⟩ := rightTriple before beforeWellFormed held
  let assignedState : State :=
    { afterRight with cells := replaceCell afterRight.cells cell value }
  have assigned : afterRight.assignCell cell value = some assignedState := by
    simp [State.assignCell, rightPostHeld.2.2.2, assignedState]
  have placeBase : evalPlace 1 program before (.local id) =
      .done { root := cell, projections := [], value := current } before := by
    rw [Lanius.Semantics.evalPlace.eq_def]
    simp [held.2.2.1, held.2.2.2]
  obtain ⟨rightFuel, rightAtFuel⟩ := rightExecution
  let fuel := max 1 rightFuel
  have placeAtFuel := evalPlace_done_at_larger_fuel
    (Nat.le_max_left 1 rightFuel) placeBase
  have rightAtCommonFuel := evalExpr_done_at_larger_fuel
    (Nat.le_max_right 1 rightFuel) rightAtFuel
  have writeResult : writeResolvedPlace afterRight
      { root := cell, projections := [], value := current } value =
      .ok assignedState := by
    simp [writeResolvedPlace, assigned]
  have execution : Evaluates program before
      (.assign .set (.local id) right) .unit assignedState := by
    refine ⟨fuel + 1, ?_⟩
    rw [Lanius.Semantics.evalExpr.eq_def]
    simp only
    rw [placeAtFuel]
    simp only
    rw [rightAtCommonFuel]
    simp only [evalAssignValue, assignOpBinary?]
    rw [writeResult]
  have assignmentEffect := assignCell_effect assigned
  have postHeld := assignmentEffect.preserve afterRightWellFormed post
    rightPostHeld.2.1 rightPostHeld.1
  have destinationHeld := assignCell_localPointsTo rightPostHeld.2.2 assigned
  exact ⟨assignedState, execution,
    assignCell_preserves_well_formed afterRightWellFormed assigned,
    ⟨rightPostHeld.1, postHeld, destinationHeld⟩,
    rightEffect.trans assignmentEffect⟩

/-- Pointwise form of `EvalTriple.setLocalFrom`.  The right-hand expression
    may modify an arbitrary framed footprint; retaining ownership of the
    destination local in its post-state is the only condition required before
    the final singleton assignment. -/
theorem evaluatesSetOwnedLocal
    (id : VarId) (cell : CellId)
    (ownedBefore : (Assertion.localPointsTo id cell (some current)).holds before)
    (rightResult : Evaluates program before right value afterRight)
    (rightWellFormed : StateWellFormed afterRight)
    (ownedAfter :
      (Assertion.localPointsTo id cell (some current)).holds afterRight)
    (rightEffect : ModifiesOnly rightWrites before afterRight) :
    ∃ after,
      Evaluates program before (.assign .set (.local id) right) .unit after ∧
      StateWellFormed after ∧
      (Assertion.localPointsTo id cell (some value)).holds after ∧
      ModifiesOnly (CellSet.union rightWrites (CellSet.singleton cell))
        before after ∧
      ModifiesOnly (CellSet.singleton cell) afterRight after := by
  let after : State :=
    { afterRight with cells := replaceCell afterRight.cells cell value }
  have assigned : afterRight.assignCell cell value = some after := by
    simp [State.assignCell, ownedAfter.2, after]
  have placeBase : evalPlace 1 program before (.local id) =
      .done { root := cell, projections := [], value := some current }
        before := by
    rw [Lanius.Semantics.evalPlace.eq_def]
    simp [ownedBefore.1, ownedBefore.2]
  obtain ⟨rightFuel, rightAtFuel⟩ := rightResult
  let fuel := max 1 rightFuel
  have placeAtFuel := evalPlace_done_at_larger_fuel
    (Nat.le_max_left 1 rightFuel) placeBase
  have rightAtCommonFuel := evalExpr_done_at_larger_fuel
    (Nat.le_max_right 1 rightFuel) rightAtFuel
  have writeResult : writeResolvedPlace afterRight
      { root := cell, projections := [], value := some current } value =
      .ok after := by
    simp [writeResolvedPlace, assigned]
  have execution : Evaluates program before
      (.assign .set (.local id) right) .unit after := by
    refine ⟨fuel + 1, ?_⟩
    rw [Lanius.Semantics.evalExpr.eq_def]
    simp only
    rw [placeAtFuel]
    simp only
    rw [rightAtCommonFuel]
    simp only [evalAssignValue, assignOpBinary?]
    rw [writeResult]
  have assignmentEffect := assignCell_effect assigned
  exact ⟨after, execution,
    assignCell_preserves_well_formed rightWellFormed assigned,
    assignCell_localPointsTo ownedAfter assigned,
    rightEffect.trans assignmentEffect, assignmentEffect⟩

/-- Execute an effectful right-hand side followed by assignment to an owned
    local when the right-hand side itself is store-pure.  This pointwise rule
    is useful inside loop simulations, where the surrounding invariant is
    indexed by the current iteration rather than packaged as one fixed
    assertion. -/
theorem evaluatesSetOwnedLocalFromEmpty
    (id : VarId) (cell : CellId)
    (beforeWellFormed : StateWellFormed before)
    (owned : (Assertion.localPointsTo id cell (some current)).holds before)
    (rightResult : Evaluates program before right value afterRight)
    (rightWellFormed : StateWellFormed afterRight)
    (rightEffect : ModifiesOnly CellSet.empty before afterRight) :
    ∃ after,
      Evaluates program before (.assign .set (.local id) right) .unit after ∧
      StateWellFormed after ∧
      (Assertion.localPointsTo id cell (some value)).holds after ∧
      ModifiesOnly (CellSet.singleton cell) before after := by
  have afterOwned := rightEffect.empty_preserves_assertion beforeWellFormed
    (Assertion.localPointsTo id cell (some current)) owned
  let after : State :=
    { afterRight with cells := replaceCell afterRight.cells cell value }
  have assigned : afterRight.assignCell cell value = some after := by
    simp [State.assignCell, afterOwned.2, after]
  have placeBase : evalPlace 1 program before (.local id) =
      .done { root := cell, projections := [], value := some current }
        before := by
    rw [Lanius.Semantics.evalPlace.eq_def]
    simp [owned.1, owned.2]
  obtain ⟨rightFuel, rightAtFuel⟩ := rightResult
  let fuel := max 1 rightFuel
  have placeAtFuel := evalPlace_done_at_larger_fuel
    (Nat.le_max_left 1 rightFuel) placeBase
  have rightAtCommonFuel := evalExpr_done_at_larger_fuel
    (Nat.le_max_right 1 rightFuel) rightAtFuel
  have writeResult : writeResolvedPlace afterRight
      { root := cell, projections := [], value := some current } value =
      .ok after := by
    simp [writeResolvedPlace, assigned]
  have execution : Evaluates program before
      (.assign .set (.local id) right) .unit after := by
    refine ⟨fuel + 1, ?_⟩
    rw [Lanius.Semantics.evalExpr.eq_def]
    simp only
    rw [placeAtFuel]
    simp only
    rw [rightAtCommonFuel]
    simp only [evalAssignValue, assignOpBinary?]
    rw [writeResult]
  have assignmentEffect := assignCell_effect assigned
  have completeEffect : ModifiesOnly (CellSet.singleton cell) before after := by
    have writesEqual :
        CellSet.union CellSet.empty (CellSet.singleton cell) =
          CellSet.singleton cell := by
      funext queried
      simp [CellSet.union, CellSet.empty]
    have combined := rightEffect.trans assignmentEffect
    rw [writesEqual] at combined
    exact combined
  exact ⟨after, execution,
    assignCell_preserves_well_formed rightWellFormed assigned,
    assignCell_localPointsTo afterOwned assigned, completeEffect⟩

/-- Effectful pointwise compound assignment.  It composes the complete RHS
    footprint with the destination-cell write while retaining the framed
    ownership supplied by the RHS post-state. -/
theorem evaluatesUpdateOwnedLocal
    (id : VarId) (cell : CellId) (operation : AssignOp)
    (ownedBefore : (Assertion.localPointsTo id cell (some current)).holds before)
    (rightResult : Evaluates program before right rightValue afterRight)
    (rightWellFormed : StateWellFormed afterRight)
    (ownedAfter :
      (Assertion.localPointsTo id cell (some current)).holds afterRight)
    (rightEffect : ModifiesOnly rightWrites before afterRight)
    (updated : evalAssignValue program.target operation (some current)
      rightValue = .ok result) :
    ∃ after,
      Evaluates program before (.assign operation (.local id) right) .unit after ∧
      StateWellFormed after ∧
      (Assertion.localPointsTo id cell (some result)).holds after ∧
      ModifiesOnly (CellSet.union rightWrites (CellSet.singleton cell))
        before after ∧
      ModifiesOnly (CellSet.singleton cell) afterRight after := by
  let after : State :=
    { afterRight with cells := replaceCell afterRight.cells cell result }
  have assigned : afterRight.assignCell cell result = some after := by
    simp [State.assignCell, ownedAfter.2, after]
  have placeBase : evalPlace 1 program before (.local id) =
      .done { root := cell, projections := [], value := some current }
        before := by
    rw [Lanius.Semantics.evalPlace.eq_def]
    simp [ownedBefore.1, ownedBefore.2]
  obtain ⟨rightFuel, rightAtFuel⟩ := rightResult
  let fuel := max 1 rightFuel
  have placeAtFuel := evalPlace_done_at_larger_fuel
    (Nat.le_max_left 1 rightFuel) placeBase
  have rightAtCommonFuel := evalExpr_done_at_larger_fuel
    (Nat.le_max_right 1 rightFuel) rightAtFuel
  have writeResult : writeResolvedPlace afterRight
      { root := cell, projections := [], value := some current } result =
      .ok after := by
    simp [writeResolvedPlace, assigned]
  have execution : Evaluates program before
      (.assign operation (.local id) right) .unit after := by
    refine ⟨fuel + 1, ?_⟩
    rw [Lanius.Semantics.evalExpr.eq_def]
    simp only
    rw [placeAtFuel]
    simp only
    rw [rightAtCommonFuel]
    simp only
    rw [updated]
    simp only
    rw [writeResult]
  have assignmentEffect := assignCell_effect assigned
  exact ⟨after, execution,
    assignCell_preserves_well_formed rightWellFormed assigned,
    assignCell_localPointsTo ownedAfter assigned,
    rightEffect.trans assignmentEffect, assignmentEffect⟩

/-- General compound-assignment rule for an owned initialized local.  The
    caller proves the pure value operation once; separation logic handles the
    physical local cell, framing, and exact singleton write footprint. -/
theorem evaluatesUpdateOwnedLocalFromEmpty
    (id : VarId) (cell : CellId) (operation : AssignOp)
    (beforeWellFormed : StateWellFormed before)
    (owned : (Assertion.localPointsTo id cell (some current)).holds before)
    (rightResult : Evaluates program before right rightValue afterRight)
    (rightWellFormed : StateWellFormed afterRight)
    (rightEffect : ModifiesOnly CellSet.empty before afterRight)
    (updated : evalAssignValue program.target operation (some current)
      rightValue = .ok result) :
    ∃ after,
      Evaluates program before (.assign operation (.local id) right) .unit after ∧
      StateWellFormed after ∧
      (Assertion.localPointsTo id cell (some result)).holds after ∧
      ModifiesOnly (CellSet.singleton cell) before after := by
  have afterOwned := rightEffect.empty_preserves_assertion beforeWellFormed
    (Assertion.localPointsTo id cell (some current)) owned
  let after : State :=
    { afterRight with cells := replaceCell afterRight.cells cell result }
  have assigned : afterRight.assignCell cell result = some after := by
    simp [State.assignCell, afterOwned.2, after]
  have placeBase : evalPlace 1 program before (.local id) =
      .done { root := cell, projections := [], value := some current }
        before := by
    rw [Lanius.Semantics.evalPlace.eq_def]
    simp [owned.1, owned.2]
  obtain ⟨rightFuel, rightAtFuel⟩ := rightResult
  let fuel := max 1 rightFuel
  have placeAtFuel := evalPlace_done_at_larger_fuel
    (Nat.le_max_left 1 rightFuel) placeBase
  have rightAtCommonFuel := evalExpr_done_at_larger_fuel
    (Nat.le_max_right 1 rightFuel) rightAtFuel
  have writeResult : writeResolvedPlace afterRight
      { root := cell, projections := [], value := some current } result =
      .ok after := by
    simp [writeResolvedPlace, assigned]
  have execution : Evaluates program before
      (.assign operation (.local id) right) .unit after := by
    refine ⟨fuel + 1, ?_⟩
    rw [Lanius.Semantics.evalExpr.eq_def]
    simp only
    rw [placeAtFuel]
    simp only
    rw [rightAtCommonFuel]
    simp only
    rw [updated]
    simp only
    rw [writeResult]
  have assignmentEffect := assignCell_effect assigned
  have completeEffect : ModifiesOnly (CellSet.singleton cell) before after := by
    have writesEqual :
        CellSet.union CellSet.empty (CellSet.singleton cell) =
          CellSet.singleton cell := by
      funext queried
      simp [CellSet.union, CellSet.empty]
    have combined := rightEffect.trans assignmentEffect
    rw [writesEqual] at combined
    exact combined
  exact ⟨after, execution,
    assignCell_preserves_well_formed rightWellFormed assigned,
    assignCell_localPointsTo afterOwned assigned, completeEffect⟩

/-- Increment an owned nonnegative `i32` local. This is the common mutation
    rule for extracted counting loops: it exposes the updated ownership and
    the singleton write footprint without making each algorithm unfold place
    evaluation, compound assignment, and signed wrapping again. -/
theorem evaluatesIncrementOwnedI32Local
    (program : Program) (before : State) (id : VarId) (cell : CellId)
    (current : Nat)
    (beforeWellFormed : StateWellFormed before)
    (owned : (Assertion.localPointsTo id cell
      (some (.signed .i32 (Int.ofNat current)))).holds before)
    (bounded : current + 1 ≤ 2147483647) :
    ∃ after,
      Evaluates program before
        (.assign .add (.local id) (.value (.signed .i32 1)))
        .unit after ∧
      StateWellFormed after ∧
      (Assertion.localPointsTo id cell
        (some (.signed .i32 (Int.ofNat (current + 1))))).holds after ∧
      ModifiesOnly (CellSet.singleton cell) before after := by
  let after : State :=
    { before with
      cells := replaceCell before.cells cell
        (.signed .i32 (Int.ofNat (current + 1))) }
  have assigned : before.assignCell cell
      (.signed .i32 (Int.ofNat (current + 1))) = some after := by
    simp [State.assignCell, owned.2, after]
  have placeResult : evalPlace 1 program before (.local id) =
      .done {
        root := cell
        projections := []
        value := some (.signed .i32 (Int.ofNat current))
      } before := by
    rw [Lanius.Semantics.evalPlace.eq_def]
    simp [owned.1, owned.2]
  have rightResult : evalExpr 1 program before
      (.value (.signed .i32 1)) = .done (.signed .i32 1) before := by
    rfl
  have wrapped := wrapSigned_i32_ofNat program.target
    (current + 1) bounded
  have addition : Int.ofNat current + 1 = Int.ofNat (current + 1) := by
    simpa using (Int.natCast_add current 1).symm
  have assignedCoerced : before.assignCell cell
      (.signed .i32 (Int.ofNat current + 1)) = some after := by
    rw [addition]
    exact assigned
  have arithmeticResult : evalAssignValue program.target .add
      (some (.signed .i32 (Int.ofNat current))) (.signed .i32 1) =
      .ok (.signed .i32 (Int.ofNat (current + 1))) := by
    simp only [evalAssignValue, assignOpBinary?, evalBinaryValue,
      beq_self_eq_true, if_true, evalSignedBinary]
    rw [addition, wrapped]
  have writeResult : writeResolvedPlace before {
      root := cell
      projections := []
      value := some (.signed .i32 (Int.ofNat current))
    } (.signed .i32 (Int.ofNat (current + 1))) = .ok after := by
    simp only [writeResolvedPlace]
    rw [← addition]
    rw [assignedCoerced]
  have evaluation : Evaluates program before
      (.assign .add (.local id) (.value (.signed .i32 1))) .unit after := by
    refine ⟨2, ?_⟩
    rw [Lanius.Semantics.evalExpr.eq_def]
    simp only
    rw [placeResult]
    simp only
    rw [rightResult]
    simp only
    rw [arithmeticResult]
    simpa only [writeResult]
  exact ⟨after, evaluation,
    assignCell_preserves_well_formed beforeWellFormed assigned,
    assignCell_localPointsTo owned assigned,
    assignCell_effect assigned⟩

/-- Statement-level companion to `evaluatesIncrementOwnedI32Local`, matching
    the normalized Core block generated for `local += 1`. -/
theorem executesIncrementOwnedI32Local
    (program : Program) (before : State) (id : VarId) (cell : CellId)
    (current : Nat)
    (beforeWellFormed : StateWellFormed before)
    (owned : (Assertion.localPointsTo id cell
      (some (.signed .i32 (Int.ofNat current)))).holds before)
    (bounded : current + 1 ≤ 2147483647) :
    ∃ after,
      Executes program before
        (.sequence
          (.expression
            (.assign .add (.local id) (.value (.signed .i32 1))))
          .skip)
        .next after ∧
      StateWellFormed after ∧
      (Assertion.localPointsTo id cell
        (some (.signed .i32 (Int.ofNat (current + 1))))).holds after ∧
      ModifiesOnly (CellSet.singleton cell) before after := by
  obtain ⟨after, evaluation, afterWellFormed, afterOwned, effect⟩ :=
    evaluatesIncrementOwnedI32Local program before id cell current
      beforeWellFormed owned bounded
  exact ⟨after,
    executesSequence (executesExpression evaluation)
      (executesSkip program after),
    afterWellFormed, afterOwned, effect⟩

/-- General indexed-slice assignment with effectful index and RHS terms.
    Both expression footprints are composed before the final backing-cell
    write; callers retain the assignment-only effect for framing the resulting
    abstract world and active locals. -/
theorem evaluatesSetSignedI32SliceIndex
    (program : Program) (before afterIndex afterRight : State)
    (indexValues rightValues : List Int)
    (sliceId : VarId) (indexExpression right : Expr)
    (cell : CellId) (index : Nat) (replacement : Int)
    (sameLength : indexValues.length = rightValues.length)
    (inBounds : index < rightValues.length)
    (sliceLocal : before.local? sliceId = some
      (.slice (.scalar (.signed .i32)) cell [] 0 rightValues.length))
    (indexResult : Evaluates program before indexExpression
      (.signed .i32 (Int.ofNat index)) afterIndex)
    (indexEffect : ModifiesOnly indexWrites before afterIndex)
    (rightResult : Evaluates program afterIndex right
      (.signed .i32 replacement) afterRight)
    (rightWellFormed : StateWellFormed afterRight)
    (rightEffect : ModifiesOnly rightWrites afterIndex afterRight)
    (backingAtIndex : afterIndex.cellEntry? cell = some {
      id := cell
      value := some (.array (signedI32Values indexValues))
    })
    (backingAtRight : afterRight.cellEntry? cell = some {
      id := cell
      value := some (.array (signedI32Values rightValues))
    }) :
    ∃ after,
      Evaluates program before
        (.assign .set (.index (.local sliceId) indexExpression) right)
        .unit after ∧
      StateWellFormed after ∧
      after.cellEntry? cell = some {
        id := cell
        value := some (.array
          (signedI32Values (setI32Value rightValues index replacement)))
      } ∧
      ModifiesOnly (CellSet.union indexWrites
        (CellSet.union rightWrites (CellSet.singleton cell))) before after ∧
      ModifiesOnly (CellSet.singleton cell) afterRight after := by
  have indexInBounds : index < indexValues.length := by
    omega
  obtain ⟨placeFuel, placeResult⟩ := evaluatesSignedI32SlicePlace program
    before afterIndex indexValues sliceId indexExpression cell index
    indexInBounds (by simpa [sameLength] using sliceLocal) indexResult
    backingAtIndex
  obtain ⟨rightFuel, rightAtFuel⟩ := rightResult
  let updated := setI32Value rightValues index replacement
  let after : State := { afterRight with
    cells := replaceCell afterRight.cells cell
      (.array (signedI32Values updated)) }
  have assigned : afterRight.assignCell cell
      (.array (signedI32Values updated)) = some after := by
    simp [State.assignCell, backingAtRight, after]
  have valueAt : (signedI32Values rightValues)[index]? =
      some (.signed .i32 (rightValues.get ⟨index, inBounds⟩)) := by
    simp [signedI32Values, inBounds]
  have written : writeResolvedPlace afterRight {
      root := cell
      projections := [.index index]
      value := some (.signed .i32 (indexValues.get ⟨index, indexInBounds⟩))
    } (.signed .i32 replacement) = .ok after := by
    simp [writeResolvedPlace, backingAtRight, replaceProjectedValue, valueAt,
      setValue_signedI32Values, updated, assigned]
  let fuel := max placeFuel rightFuel
  have placeAtFuel := evalPlace_done_at_larger_fuel
    (Nat.le_max_left placeFuel rightFuel) placeResult
  have rightAtCommonFuel := evalExpr_done_at_larger_fuel
    (Nat.le_max_right placeFuel rightFuel) rightAtFuel
  have execution : Evaluates program before
      (.assign .set (.index (.local sliceId) indexExpression) right)
      .unit after := by
    refine ⟨fuel + 1, ?_⟩
    rw [Lanius.Semantics.evalExpr.eq_def]
    simp only
    rw [placeAtFuel]
    simp only
    rw [rightAtCommonFuel]
    simp only [evalAssignValue, assignOpBinary?]
    rw [written]
  have afterBacking : after.cellEntry? cell = some {
      id := cell
      value := some (.array (signedI32Values updated))
    } := assignCell_finds_assigned assigned
  have assignmentEffect := assignCell_effect assigned
  have completeEffect : ModifiesOnly (CellSet.union indexWrites
      (CellSet.union rightWrites (CellSet.singleton cell))) before after :=
    indexEffect.trans (rightEffect.trans assignmentEffect)
  exact ⟨after, execution,
    assignCell_preserves_well_formed rightWellFormed assigned,
    by simpa [updated] using afterBacking, completeEffect, assignmentEffect⟩

theorem evaluatesSetSignedI32SliceIndexFromEmpty
    (program : Program) (before afterIndex afterRight : State)
    (values : List Int) (sliceId : VarId) (indexExpression right : Expr)
    (cell : CellId) (index : Nat) (replacement : Int)
    (inBounds : index < values.length)
    (sliceLocal : before.local? sliceId = some
      (.slice (.scalar (.signed .i32)) cell [] 0 values.length))
    (indexResult : Evaluates program before indexExpression
      (.signed .i32 (Int.ofNat index)) afterIndex)
    (indexWellFormed : StateWellFormed afterIndex)
    (indexEffect : ModifiesOnly CellSet.empty before afterIndex)
    (rightResult : Evaluates program afterIndex right
      (.signed .i32 replacement) afterRight)
    (rightWellFormed : StateWellFormed afterRight)
    (rightEffect : ModifiesOnly CellSet.empty afterIndex afterRight)
    (backingAtIndex : afterIndex.cellEntry? cell = some {
      id := cell
      value := some (.array (signedI32Values values))
    }) :
    ∃ after,
      Evaluates program before
        (.assign .set (.index (.local sliceId) indexExpression) right)
        .unit after ∧
      StateWellFormed after ∧
      after.cellEntry? cell = some {
        id := cell
        value := some (.array
          (signedI32Values (setI32Value values index replacement)))
      } ∧
      ModifiesOnly (CellSet.singleton cell) before after := by
  have backingAtWrite : afterRight.cellEntry? cell = some {
      id := cell
      value := some (.array (signedI32Values values))
    } := rightEffect.empty_preserves_entry indexWellFormed backingAtIndex
  obtain ⟨placeFuel, placeResult⟩ := evaluatesSignedI32SlicePlace program
    before afterIndex values sliceId indexExpression cell index inBounds
    sliceLocal indexResult backingAtIndex
  obtain ⟨rightFuel, rightAtFuel⟩ := rightResult
  let updated := setI32Value values index replacement
  let after : State := { afterRight with
    cells := replaceCell afterRight.cells cell
      (.array (signedI32Values updated)) }
  have assigned : afterRight.assignCell cell
      (.array (signedI32Values updated)) = some after := by
    simp [State.assignCell, backingAtWrite, after]
  have valueAt : (signedI32Values values)[index]? =
      some (.signed .i32 (values.get ⟨index, inBounds⟩)) := by
    simp [signedI32Values, inBounds]
  have written : writeResolvedPlace afterRight {
      root := cell
      projections := [.index index]
      value := some (.signed .i32 (values.get ⟨index, inBounds⟩))
    } (.signed .i32 replacement) = .ok after := by
    simp [writeResolvedPlace, backingAtWrite, replaceProjectedValue, valueAt,
      setValue_signedI32Values, updated, assigned]
  let fuel := max placeFuel rightFuel
  have placeAtFuel := evalPlace_done_at_larger_fuel
    (Nat.le_max_left placeFuel rightFuel) placeResult
  have rightAtCommonFuel := evalExpr_done_at_larger_fuel
    (Nat.le_max_right placeFuel rightFuel) rightAtFuel
  have execution : Evaluates program before
      (.assign .set (.index (.local sliceId) indexExpression) right)
      .unit after := by
    refine ⟨fuel + 1, ?_⟩
    rw [Lanius.Semantics.evalExpr.eq_def]
    simp only
    rw [placeAtFuel]
    simp only
    rw [rightAtCommonFuel]
    simp only [evalAssignValue, assignOpBinary?]
    rw [written]
  have afterBacking : after.cellEntry? cell = some {
      id := cell
      value := some (.array (signedI32Values updated))
    } := assignCell_finds_assigned assigned
  have prefixEffect : ModifiesOnly CellSet.empty before afterRight :=
    indexEffect.trans_same rightEffect
  have assignmentEffect := assignCell_effect assigned
  have combined := prefixEffect.trans assignmentEffect
  have completeEffect : ModifiesOnly (CellSet.singleton cell) before after := by
    have writesEqual :
        CellSet.union CellSet.empty (CellSet.singleton cell) =
          CellSet.singleton cell := by
      funext queried
      simp [CellSet.union, CellSet.empty]
    rw [writesEqual] at combined
    exact combined
  exact ⟨after, execution,
    assignCell_preserves_well_formed rightWellFormed assigned,
    by simpa [updated] using afterBacking, completeEffect⟩

theorem EvalTriple.ifTrue
    (conditionTriple :
      EvalTriple program pre condition (.boolean true) branchPre
        conditionWrites)
    (branchTriple :
      ExecTriple program branchPre thenBranch completion post branchWrites) :
    ExecTriple program pre (.ifThenElse condition thenBranch elseBranch)
      completion post (CellSet.union conditionWrites branchWrites) := by
  intro before beforeWellFormed held
  obtain ⟨afterCondition, conditionExecution, conditionWellFormed,
      branchHeld, conditionEffect⟩ :=
    conditionTriple before beforeWellFormed held
  obtain ⟨after, branchExecution, afterWellFormed, postHeld,
      branchEffect⟩ := branchTriple afterCondition conditionWellFormed branchHeld
  exact ⟨after, executesIfTrue conditionExecution branchExecution,
    afterWellFormed, postHeld, conditionEffect.trans branchEffect⟩

theorem EvalTriple.ifFalse
    (conditionTriple :
      EvalTriple program pre condition (.boolean false) branchPre
        conditionWrites)
    (branchTriple :
      ExecTriple program branchPre elseBranch completion post branchWrites) :
    ExecTriple program pre (.ifThenElse condition thenBranch elseBranch)
      completion post (CellSet.union conditionWrites branchWrites) := by
  intro before beforeWellFormed held
  obtain ⟨afterCondition, conditionExecution, conditionWellFormed,
      branchHeld, conditionEffect⟩ :=
    conditionTriple before beforeWellFormed held
  obtain ⟨after, branchExecution, afterWellFormed, postHeld,
      branchEffect⟩ := branchTriple afterCondition conditionWellFormed branchHeld
  exact ⟨after, executesIfFalse conditionExecution branchExecution,
    afterWellFormed, postHeld, conditionEffect.trans branchEffect⟩

/-- A scoped body starts after a fresh temporary local has been bound. Its
    postcondition is stated after restoring the enclosing local environment;
    its physical-cell effect remains available for framing. -/
def ScopedExecTriple
    (program : Program) (pre : Assertion) (id : VarId) (value : Value)
    (body : Stmt) (completion : Completion) (post : Assertion)
    (writes : CellSet) : Prop :=
  ∀ before, StateWellFormed before → pre.holds before →
    ∃ completed,
      Executes program (before.bindLocal id value) body completion completed ∧
      StateWellFormed completed ∧
      post.holds (restoreLocals before completed) ∧
      StoreEffect writes (before.bindLocal id value) completed

/-- Let-binding rule with an arbitrary effectful initializer. Fresh temporary
    cells are hidden when the scope closes; only initializer and body writes
    remain visible to the caller. -/
theorem EvalTriple.letLocal
    {id : VarId} {type : Ty} {value : Value}
    (initializerTriple :
      EvalTriple program pre initializer value initializedPost
        initializerWrites)
    (bodyTriple :
      ScopedExecTriple program initializedPost id value body completion post
        bodyWrites) :
    ExecTriple program pre (.letLocal id type initializer body) completion post
      (CellSet.union initializerWrites bodyWrites) := by
  intro before beforeWellFormed held
  obtain ⟨initialized, initializerExecution, initializedWellFormed,
      initializedHeld, initializerEffect⟩ :=
    initializerTriple before beforeWellFormed held
  obtain ⟨completed, bodyExecution, completedWellFormed, postHeld,
      bodyEffect⟩ :=
    bodyTriple initialized initializedWellFormed initializedHeld
  let after := restoreLocals initialized completed
  have entered : StoreEffect bodyWrites initialized
      (initialized.bindLocal id value) :=
    (bindLocal_effect initialized id value).weaken CellSet.empty_subset
  have scopeEffect : StoreEffect bodyWrites initialized completed :=
    entered.trans_same bodyEffect
  have afterWellFormed : StateWellFormed after :=
    scopeEffect.restoreLocals_wellFormed initializedWellFormed
      completedWellFormed
  have closedEffect : ModifiesOnly bodyWrites initialized after := by
    exact scopeEffect.restoreLocals
  exact ⟨after, by simpa [after] using
      executesLetLocal initializerExecution bodyExecution,
    afterWellFormed, by simpa [after] using postHeld,
    initializerEffect.trans closedEffect⟩

def ScopedUninitializedExecTriple
    (program : Program) (pre : Assertion) (id : VarId)
    (body : Stmt) (completion : Completion) (post : Assertion)
    (writes : CellSet) : Prop :=
  ∀ before, StateWellFormed before → pre.holds before →
    ∃ completed,
      Executes program (before.bindUninitialized id) body completion completed ∧
      StateWellFormed completed ∧
      post.holds (restoreLocals before completed) ∧
      StoreEffect writes (before.bindUninitialized id) completed

/-- Framing a scoped initialized local is sound at the enclosing scope. The
fresh local itself remains hidden; the framed resources are compared only
after the original local environment has been restored. -/
theorem ScopedExecTriple.frame
    {id : VarId}
    (triple : ScopedExecTriple program pre id value body completion post writes)
    (frame : Assertion)
    (postDisjoint : CellSet.Disjoint post.footprint frame.footprint)
    (writeDisjoint : CellSet.Disjoint frame.footprint writes) :
    ScopedExecTriple program (pre ⋆ frame) id value body completion
      (post ⋆ frame) writes := by
  intro before beforeWellFormed held
  obtain ⟨completed, execution, completedWellFormed, postHeld, bodyEffect⟩ :=
    triple before beforeWellFormed held.2.1
  have entered : StoreEffect writes before (before.bindLocal id value) :=
    (bindLocal_effect before id value).weaken CellSet.empty_subset
  have closedEffect : ModifiesOnly writes before
      (restoreLocals before completed) :=
    (entered.trans_same bodyEffect).restoreLocals
  have frameHeld := closedEffect.preserve beforeWellFormed frame held.2.2
    writeDisjoint
  exact ⟨completed, execution, completedWellFormed,
    ⟨postDisjoint, postHeld, frameHeld⟩, bodyEffect⟩

/-- Uninitialized temporary locals obey the same enclosing-scope frame rule. -/
theorem ScopedUninitializedExecTriple.frame
    {id : VarId}
    (triple : ScopedUninitializedExecTriple program pre id body completion
      post writes)
    (frame : Assertion)
    (postDisjoint : CellSet.Disjoint post.footprint frame.footprint)
    (writeDisjoint : CellSet.Disjoint frame.footprint writes) :
    ScopedUninitializedExecTriple program (pre ⋆ frame) id body completion
      (post ⋆ frame) writes := by
  intro before beforeWellFormed held
  obtain ⟨completed, execution, completedWellFormed, postHeld, bodyEffect⟩ :=
    triple before beforeWellFormed held.2.1
  have entered : StoreEffect writes before (before.bindUninitialized id) :=
    (bindUninitialized_effect before id).weaken CellSet.empty_subset
  have closedEffect : ModifiesOnly writes before
      (restoreLocals before completed) :=
    (entered.trans_same bodyEffect).restoreLocals
  have frameHeld := closedEffect.preserve beforeWellFormed frame held.2.2
    writeDisjoint
  exact ⟨completed, execution, completedWellFormed,
    ⟨postDisjoint, postHeld, frameHeld⟩, bodyEffect⟩

theorem ExecTriple.letUninitialized
    {id : VarId} {type : Ty}
    (bodyTriple : ScopedUninitializedExecTriple program pre id body completion
      post writes) :
    ExecTriple program pre (.letUninitialized id type body) completion post
      writes := by
  intro before beforeWellFormed held
  obtain ⟨completed, bodyExecution, completedWellFormed, postHeld,
      bodyEffect⟩ := bodyTriple before beforeWellFormed held
  let after := restoreLocals before completed
  have entered : StoreEffect writes before
      (before.bindUninitialized id) :=
    (bindUninitialized_effect before id).weaken CellSet.empty_subset
  have scopeEffect : StoreEffect writes before completed :=
    entered.trans_same bodyEffect
  exact ⟨after, by simpa [after] using
      executesLetUninitialized bodyExecution,
    scopeEffect.restoreLocals_wellFormed beforeWellFormed
      completedWellFormed,
    by simpa [after] using postHeld,
    scopeEffect.restoreLocals⟩

/-- A finite iteration relation used by loop proofs. It separates the
algorithm-specific progress argument from frame/effect composition. -/
inductive Iterates (step : State → State → Prop) : Nat → State → State → Prop
  | zero (state) : Iterates step 0 state state
  | succ (first : step before middle)
      (rest : Iterates step count middle after) :
      Iterates step (count + 1) before after

theorem Iterates.modifiesOnly
    (steps : Iterates step count before after)
    (stepEffect : ∀ {left right}, step left right →
      ModifiesOnly writes left right) :
    ModifiesOnly writes before after := by
  induction steps with
  | zero state => exact ModifiesOnly.reflAny writes state
  | succ first rest inductionHypothesis =>
      exact (stepEffect first).trans_same inductionHypothesis

theorem Iterates.invariant
    (invariant : State → Prop)
    (steps : Iterates step count before after)
    (initial : invariant before)
    (preserved : ∀ {left right}, invariant left → step left right →
      invariant right) :
    invariant after := by
  induction steps with
  | zero => exact initial
  | succ first rest inductionHypothesis =>
      exact inductionHypothesis (preserved initial first)

theorem Iterates.preserve
    (steps : Iterates step count before after)
    (stepEffect : ∀ {left right}, step left right →
      ModifiesOnly writes left right)
    (beforeWellFormed : StateWellFormed before)
    (assertion : Assertion)
    (held : assertion.holds before)
    (disjoint : CellSet.Disjoint assertion.footprint writes) :
    assertion.holds after :=
  (steps.modifiesOnly stepEffect).preserve beforeWellFormed assertion held
    disjoint

/-- One continuing `while` iteration. Both ordinary fallthrough and an
    explicit `continue` advance to the next condition check. -/
inductive WhileIteration
    (program : Program) (condition : Expr) (body : Stmt) :
    State → State → Prop
  | next
      (conditionResult :
        Evaluates program before condition (.boolean true) afterCondition)
      (bodyResult : Executes program afterCondition body .next after) :
      WhileIteration program condition body before after
  | continueLoop
      (conditionResult :
        Evaluates program before condition (.boolean true) afterCondition)
      (bodyResult : Executes program afterCondition body .continueLoop after) :
      WhileIteration program condition body before after

/-- A successful `while` exit. A false condition and `break` both produce
    normal fallthrough; a source return escapes the loop unchanged. -/
inductive WhileExit
    (program : Program) (condition : Expr) (body : Stmt) :
    Completion → State → State → Prop
  | conditionFalse
      (conditionResult :
        Evaluates program before condition (.boolean false) after) :
      WhileExit program condition body .next before after
  | breakLoop
      (conditionResult :
        Evaluates program before condition (.boolean true) afterCondition)
      (bodyResult : Executes program afterCondition body .breakLoop after) :
      WhileExit program condition body .next before after
  | returned
      (conditionResult :
        Evaluates program before condition (.boolean true) afterCondition)
      (bodyResult :
        Executes program afterCondition body (.returned value) after) :
      WhileExit program condition body (.returned value) before after

theorem WhileExit.executes
    (exit : WhileExit program condition body completion before after) :
    Executes program before (.whileLoop condition body) completion after := by
  cases exit with
  | conditionFalse conditionResult =>
      exact executesWhileFalse conditionResult
  | breakLoop conditionResult bodyResult =>
      exact executesWhileBreak conditionResult bodyResult
  | returned conditionResult bodyResult =>
      exact executesWhileReturned conditionResult bodyResult

theorem WhileIteration.executeThen
    (iteration : WhileIteration program condition body before middle)
    (rest : Executes program middle (.whileLoop condition body)
      completion after) :
    Executes program before (.whileLoop condition body) completion after := by
  cases iteration with
  | next conditionResult bodyResult =>
      exact executesWhileTrueThen conditionResult bodyResult rest
  | continueLoop conditionResult bodyResult =>
      exact executesWhileContinueThen conditionResult bodyResult rest

/-- Turn an algorithm-level finite iteration witness plus a semantic exit into
    execution of the actual Core `while` statement. This is the reusable bridge
    that numeric scanning previously rebuilt by recursive fuel proofs. -/
theorem Iterates.executesWhile
    (steps : Iterates (WhileIteration program condition body) count before middle)
    (exit : WhileExit program condition body completion middle after) :
    Executes program before (.whileLoop condition body) completion after := by
  induction steps with
  | zero => exact exit.executes
  | succ first rest inductionHypothesis =>
      exact first.executeThen (inductionHypothesis exit)

theorem Iterates.withExit_modifiesOnly
    (steps : Iterates step count before middle)
    (stepEffect : ∀ {left right}, step left right →
      ModifiesOnly writes left right)
    (exitEffect : ModifiesOnly writes middle after) :
    ModifiesOnly writes before after :=
  (steps.modifiesOnly stepEffect).trans_same exitEffect

/-- A loop-iteration contract is the reusable verification condition for one
successful back edge. It preserves both the logical invariant and state
well-formedness while exposing the iteration's write footprint. -/
def WhileIterationContract
    (program : Program) (condition : Expr) (body : Stmt)
    (invariant : Assertion) (writes : CellSet) : Prop :=
  ∀ {before after},
    StateWellFormed before → invariant.holds before →
    WhileIteration program condition body before after →
    StateWellFormed after ∧ invariant.holds after ∧
      ModifiesOnly writes before after

/-- The exit contract handles false conditions, `break`, and source returns
uniformly. Its completion is the completion of the enclosing while statement. -/
def WhileExitContract
    (program : Program) (condition : Expr) (body : Stmt)
    (completion : Completion) (invariant post : Assertion)
    (writes : CellSet) : Prop :=
  ∀ {before after},
    StateWellFormed before → invariant.holds before →
    WhileExit program condition body completion before after →
    StateWellFormed after ∧ post.holds after ∧
      ModifiesOnly writes before after

/-- Total correctness needs an algorithm-specific termination witness. The
generic separation layer consumes only a finite sequence of continuing
iterations followed by one semantic exit; it does not expose evaluator fuel. -/
def WhileTerminates
    (program : Program) (condition : Expr) (body : Stmt)
    (completion : Completion) (invariant : Assertion) : Prop :=
  ∀ before,
    StateWellFormed before → invariant.holds before →
    ∃ count middle after,
      Iterates (WhileIteration program condition body) count before middle ∧
      WhileExit program condition body completion middle after

/-- Fold a per-edge invariant/effect proof across a finite relation walk. -/
theorem Iterates.verified
    (invariant : Assertion) (writes : CellSet)
    (steps : Iterates step count before after)
    (initialWellFormed : StateWellFormed before)
    (initialInvariant : invariant.holds before)
    (stepContract : ∀ {left right},
      StateWellFormed left → invariant.holds left → step left right →
      StateWellFormed right ∧ invariant.holds right ∧
        ModifiesOnly writes left right) :
    StateWellFormed after ∧ invariant.holds after ∧
      ModifiesOnly writes before after := by
  induction steps with
  | zero state =>
      exact ⟨initialWellFormed, initialInvariant,
        ModifiesOnly.reflAny writes state⟩
  | succ first rest inductionHypothesis =>
      obtain ⟨middleWellFormed, middleInvariant, firstEffect⟩ :=
        stepContract initialWellFormed initialInvariant first
      obtain ⟨afterWellFormed, afterInvariant, restEffect⟩ :=
        inductionHypothesis middleWellFormed middleInvariant
      exact ⟨afterWellFormed, afterInvariant,
        firstEffect.trans_same restEffect⟩

/-- Total-correctness rule for Core while loops. Algorithm proofs supply a
finite termination witness and local iteration/exit contracts; this theorem
assembles semantic execution, invariant propagation, framing effects, and the
postcondition into one `ExecTriple`. -/
theorem ExecTriple.whileLoop
    (precondition : pre ⊢ₛ invariant)
    (termination : WhileTerminates program condition body completion invariant)
    (iterationContract :
      WhileIterationContract program condition body invariant writes)
    (exitContract :
      WhileExitContract program condition body completion invariant post writes) :
    ExecTriple program pre (.whileLoop condition body) completion post writes := by
  intro before beforeWellFormed preHeld
  have invariantHeld := precondition before beforeWellFormed preHeld
  obtain ⟨count, middle, after, steps, exit⟩ :=
    termination before beforeWellFormed invariantHeld
  obtain ⟨middleWellFormed, middleInvariant, stepsEffect⟩ :=
    Iterates.verified invariant writes steps beforeWellFormed invariantHeld
      iterationContract
  obtain ⟨afterWellFormed, postHeld, exitEffect⟩ :=
    exitContract middleWellFormed middleInvariant exit
  exact ⟨after, steps.executesWhile exit, afterWellFormed, postHeld,
    stepsEffect.trans_same exitEffect⟩

/-- A concrete execution bundled with the state-validity and write-footprint
    facts needed to compose it with surrounding scopes. -/
structure ExecutionWithEffect
    (program : Program) (before : State) (statement : Stmt)
    (completion : Completion) (writes : CellSet) where
  after : State
  execution : Executes program before statement completion after
  effect : ModifiesOnly writes before after
  wellFormed : StateWellFormed after

/-- Close a source `let` while retaining mutations to an explicit caller
    footprint.  Writes to the freshly allocated local cell are hidden at the
    lexical boundary; writes in `retained` remain visible and composable. -/
noncomputable def closesFreshLocalExcept
    {id : VarId} {type : Ty}
    (retained : CellSet)
    (beforeWellFormed : StateWellFormed before)
    (initializerResult : Evaluates program before initializer value before)
    (bodyResult : Executes program (before.bindLocal id value) body completion
      completed)
    (bodyEffect : ModifiesOnly
      (CellSet.union retained (CellSet.singleton before.nextCell))
      (before.bindLocal id value) completed)
    (completedWellFormed : StateWellFormed completed) :
    ExecutionWithEffect program before
      (.letLocal id type initializer body) completion retained := by
  let writes := CellSet.union retained (CellSet.singleton before.nextCell)
  let after := restoreLocals before completed
  have entered : StoreEffect writes before (before.bindLocal id value) :=
    (bindLocal_effect before id value).weaken CellSet.empty_subset
  have complete : StoreEffect writes before completed :=
    entered.trans_same (by simpa [writes] using bodyEffect.toStoreEffect)
  have closed : ModifiesOnly writes before after := complete.restoreLocals
  have visible : ModifiesOnly retained before after := by
    apply closed.hideFreshWritesExcept
    intro cell written
    rcases written with retainedWrite | freshWrite
    · exact Or.inl retainedWrite
    · right
      change cell = before.nextCell at freshWrite
      subst cell
      exact Nat.le_refl _
  have afterWellFormed : StateWellFormed after :=
    complete.restoreLocals_wellFormed beforeWellFormed completedWellFormed
  exact {
    after := after
    execution := by simpa [after] using
      executesLetLocal initializerResult bodyResult
    effect := visible
    wellFormed := afterWellFormed
  }

@[simp] theorem closesFreshLocalExcept_cells
    {id : VarId} {type : Ty}
    (retained : CellSet)
    (beforeWellFormed : StateWellFormed before)
    (initializerResult : Evaluates program before initializer value before)
    (bodyResult : Executes program (before.bindLocal id value) body completion
      completed)
    (bodyEffect : ModifiesOnly
      (CellSet.union retained (CellSet.singleton before.nextCell))
      (before.bindLocal id value) completed)
    (completedWellFormed : StateWellFormed completed) :
    (closesFreshLocalExcept (id := id) (type := type) retained
      beforeWellFormed initializerResult
      bodyResult bodyEffect completedWellFormed).after.cells =
        completed.cells := by
  simp [closesFreshLocalExcept, restoreLocals]

/-- Close a source `let` whose body can write only the freshly allocated local
    cell.  The write disappears at the lexical boundary, yielding an empty
    caller-visible effect.  This is the direct execution-level counterpart of
    `EvalTriple.letLocal`, useful when an algorithm proof already carries an
    exact body execution and footprint rather than an assertion triple. -/
noncomputable def closesFreshLocal
    {id : VarId} {type : Ty}
    (beforeWellFormed : StateWellFormed before)
    (initializerResult : Evaluates program before initializer value before)
    (bodyResult : Executes program (before.bindLocal id value) body completion
      completed)
    (bodyEffect : ModifiesOnly (CellSet.singleton before.nextCell)
      (before.bindLocal id value) completed)
    (completedWellFormed : StateWellFormed completed) :
    ExecutionWithEffect program before
      (.letLocal id type initializer body) completion CellSet.empty := by
  apply closesFreshLocalExcept CellSet.empty beforeWellFormed initializerResult
    bodyResult (completedWellFormed := completedWellFormed)
  exact bodyEffect.weaken CellSet.subset_union_right

end Lanius.Separation
