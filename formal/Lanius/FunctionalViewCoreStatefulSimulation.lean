import Lanius.FunctionalViewCoreStateful
import Lanius.FunctionalViewCoreEffectfulSimulation
import Lanius.FunctionalViewLoop

namespace Lanius.FunctionalView.Core.Stateful

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Properties
open Lanius.Separation
open Lanius.CallContracts
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Stateful

universe u

/-! # Separation-backed stateful simulation

`Representation` is the only place where FunctionalView knows that Core
locals are physical cells.  It owns every active local, owns every abstract
slice resource, and records their disjointness.  Command proofs manipulate
pure environments and worlds; these lemmas perform cell bookkeeping once.
-/

def localFootprint (cells : Fin arity → CellId) : CellSet :=
  fun cell => ∃ index, cells index = cell

def pushCells (cells : Fin arity → CellId) (fresh : CellId) :
    Fin (arity + 1) → CellId := fun index =>
  if before : index.val < arity then cells ⟨index.val, before⟩ else fresh

structure Representation (layout : Layout arity)
    (localCell : Fin arity → CellId) (world : ReadOnly.World)
    (environment : Env arity) (state : State) : Prop where
  worldOwned : (ReadOnly.World.owns world).holds state
  localOwned : ∀ index,
    (Assertion.localPointsTo (layout index) (localCell index)
      (some (environment index))).holds state
  localCellsInjective : Function.Injective localCell
  worldLocalsDisjoint : CellSet.Disjoint
    (ReadOnly.World.owns world).footprint (localFootprint localCell)

/-- Canonical two-slot layout used by small mutable loop bodies. -/
def pairLayout (first second : VarId) : Layout 2
  | ⟨0, _⟩ => first
  | ⟨1, _⟩ => second

/-- Canonical two-value FunctionalView environment. -/
def pairEnvironment (first second : Value) : Env 2
  | ⟨0, _⟩ => first
  | ⟨1, _⟩ => second

/-- Physical cells corresponding to `pairLayout`. -/
def pairCells (first second : CellId) : Fin 2 → CellId
  | ⟨0, _⟩ => first
  | ⟨1, _⟩ => second

@[simp] theorem pairLayout_first (first second : VarId) :
    pairLayout first second ⟨0, by omega⟩ = first := rfl

@[simp] theorem pairLayout_second (first second : VarId) :
    pairLayout first second ⟨1, by omega⟩ = second := rfl

@[simp] theorem pairEnvironment_first (first second : Value) :
    pairEnvironment first second ⟨0, by omega⟩ = first := rfl

@[simp] theorem pairEnvironment_second (first second : Value) :
    pairEnvironment first second ⟨1, by omega⟩ = second := rfl

@[simp] theorem pairCells_first (first second : CellId) :
    pairCells first second ⟨0, by omega⟩ = first := rfl

@[simp] theorem pairCells_second (first second : CellId) :
    pairCells first second ⟨1, by omega⟩ = second := rfl

@[simp] theorem pairLayout_one (first second : VarId) :
    pairLayout first second (1 : Fin 2) = second := rfl

@[simp] theorem pairEnvironment_one (first second : Value) :
    pairEnvironment first second (1 : Fin 2) = second := rfl

@[simp] theorem pairCells_one (first second : CellId) :
    pairCells first second (1 : Fin 2) = second := rfl

/-- Build the common parser/lexer representation consisting of one mutable
    `i32` slice and two initialized locals.  All finite-index case analysis is
    discharged here; clients provide only ordinary separation facts. -/
theorem Representation.pairSingleton
    {state : State} {sliceCell firstCell secondCell : CellId}
    {sliceValues : List Int} {firstId secondId : VarId}
    {firstValue secondValue : Value}
    (wellFormed : StateWellFormed state)
    (sliceBacking : state.cellEntry? sliceCell = some {
      id := sliceCell
      value := some (.array (signedI32Values sliceValues))
    })
    (firstOwned : (Assertion.localPointsTo firstId firstCell
      (some firstValue)).holds state)
    (secondOwned : (Assertion.localPointsTo secondId secondCell
      (some secondValue)).holds state)
    (firstSecond : firstCell ≠ secondCell)
    (firstSlice : firstCell ≠ sliceCell)
    (secondSlice : secondCell ≠ sliceCell) :
    Representation (pairLayout firstId secondId)
      (pairCells firstCell secondCell)
      (ReadOnly.World.singleton sliceCell sliceValues)
      (pairEnvironment firstValue secondValue) state := by
  refine {
    worldOwned := (ReadOnly.World.owns_iff_represents wellFormed).2
      (ReadOnly.World.singleton_represents wellFormed sliceBacking)
    localOwned := ?_
    localCellsInjective := ?_
    worldLocalsDisjoint := ?_
  }
  · rintro ⟨slot, slotBound⟩
    have cases : slot = 0 ∨ slot = 1 := by omega
    rcases cases with rfl | rfl
    · simpa [pairLayout, pairCells, pairEnvironment] using firstOwned
    · simpa [pairLayout, pairCells, pairEnvironment] using secondOwned
  · intro left right same
    apply Fin.ext
    have leftCases : left.val = 0 ∨ left.val = 1 := by omega
    have rightCases : right.val = 0 ∨ right.val = 1 := by omega
    rcases leftCases with leftZero | leftOne <;>
      rcases rightCases with rightZero | rightOne
    · exact leftZero.trans rightZero.symm
    · exfalso
      apply firstSecond
      have leftEq : left = ⟨0, by omega⟩ := Fin.ext leftZero
      have rightEq : right = ⟨1, by omega⟩ := Fin.ext rightOne
      rw [leftEq, rightEq] at same
      simpa [pairCells] using same
    · exfalso
      apply firstSecond
      symm
      have leftEq : left = ⟨1, by omega⟩ := Fin.ext leftOne
      have rightEq : right = ⟨0, by omega⟩ := Fin.ext rightZero
      rw [leftEq, rightEq] at same
      simpa [pairCells] using same
    · exact leftOne.trans rightOne.symm
  · intro cell worldMember localMember
    obtain ⟨contents, found⟩ := worldMember
    by_cases sameSlice : cell = sliceCell
    · subst cell
      obtain ⟨slot, localAtSlice⟩ := localMember
      have slotCases : slot.val = 0 ∨ slot.val = 1 := by omega
      rcases slotCases with slotZero | slotOne
      · have slotEq : slot = ⟨0, by omega⟩ := Fin.ext slotZero
        rw [slotEq] at localAtSlice
        exact firstSlice (by simpa [pairCells] using localAtSlice)
      · have slotEq : slot = ⟨1, by omega⟩ := Fin.ext slotOne
        rw [slotEq] at localAtSlice
        exact secondSlice (by simpa [pairCells] using localAtSlice)
    · simp [ReadOnly.World.singleton, sameSlice] at found

/-- A proof-ready view of one slice local paired with one scalar cursor.
    The slice-local cell is intentionally hidden: clients normally know the
    source local value, not its physical allocation identity. -/
structure SliceCursorRepresentation
    (sliceId cursorId : VarId) (sliceCell cursorCell : CellId)
    (sliceValues : List Int) (cursorValue : Value) (state : State) where
  sliceLocalCell : CellId
  represented : Representation (pairLayout sliceId cursorId)
    (pairCells sliceLocalCell cursorCell)
    (ReadOnly.World.singleton sliceCell sliceValues)
    (pairEnvironment
      (.slice (.scalar (.signed .i32)) sliceCell [] 0 sliceValues.length)
      cursorValue) state

/-- Recover the hidden local-cell ownership needed by FunctionalView from an
    ordinary local read and a separation frame. -/
noncomputable def SliceCursorRepresentation.ofState
    {sliceId cursorId : VarId} {sliceCell cursorCell : CellId}
    {sliceValues : List Int} {cursorValue : Value} {state : State}
    (wellFormed : StateWellFormed state)
    (sliceLocal : state.local? sliceId = some
      (.slice (.scalar (.signed .i32)) sliceCell [] 0 sliceValues.length))
    (sliceBacking : state.cellEntry? sliceCell = some {
      id := sliceCell
      value := some (.array (signedI32Values sliceValues))
    })
    (cursorOwned : (Assertion.localPointsTo cursorId cursorCell
      (some cursorValue)).holds state)
    (sliceLocalSeparate : CellSet.Disjoint
      (localCellFootprint state (fun id => id = sliceId))
      (CellSet.union (CellSet.singleton sliceCell)
        (CellSet.singleton cursorCell)))
    (cursorSlice : cursorCell ≠ sliceCell) :
    SliceCursorRepresentation sliceId cursorId sliceCell cursorCell
      sliceValues cursorValue state := by
  let witness := Assertion.exists_localPointsTo_of_local state sliceId
    (.slice (.scalar (.signed .i32)) sliceCell [] 0 sliceValues.length)
    sliceLocal
  let sliceLocalCell := Classical.choose witness
  have sliceLocalOwned := Classical.choose_spec witness
  have localMember : localCellFootprint state (fun id => id = sliceId)
      sliceLocalCell := ⟨sliceId, rfl, sliceLocalOwned.1⟩
  have localCursor : sliceLocalCell ≠ cursorCell := by
    intro same
    exact sliceLocalSeparate cursorCell (by simpa [same] using localMember)
      (Or.inr rfl)
  have localSlice : sliceLocalCell ≠ sliceCell := by
    intro same
    exact sliceLocalSeparate sliceCell (by simpa [same] using localMember)
      (Or.inl rfl)
  exact {
    sliceLocalCell := sliceLocalCell
    represented := Representation.pairSingleton wellFormed sliceBacking
      sliceLocalOwned cursorOwned localCursor localSlice cursorSlice
  }

/-- Extend a representation with an already-existing owned local.  This is
    the proof-facing counterpart of `Layout.push`: unlike `bindLocal`, it does
    not allocate or change the Core state. -/
theorem Representation.pushOwnedLocal
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId} {world : ReadOnly.World}
    {environment : Env arity} {state : State}
    {id : VarId} {cell : CellId} {value : Value}
    (represented : Representation layout localCell world environment state)
    (owned : (Assertion.localPointsTo id cell (some value)).holds state)
    (cellDistinct : ∀ index, localCell index ≠ cell)
    (worldDistinct : ¬(ReadOnly.World.owns world).footprint cell) :
    Representation (Layout.push layout id) (pushCells localCell cell) world
      (environment.push value) state := by
  refine {
    worldOwned := represented.worldOwned
    localOwned := ?_
    localCellsInjective := ?_
    worldLocalsDisjoint := ?_
  }
  · intro index
    simp only [pushCells, Layout.push, Env.push]
    split
    next before => exact represented.localOwned ⟨index.val, before⟩
    next _ => exact owned
  · intro left right same
    by_cases leftBefore : left.val < arity <;>
      by_cases rightBefore : right.val < arity
    · simp only [pushCells, dif_pos leftBefore, dif_pos rightBefore] at same
      have old : (⟨left.val, leftBefore⟩ : Fin arity) =
          ⟨right.val, rightBefore⟩ :=
        represented.localCellsInjective same
      apply Fin.ext
      exact congrArg (fun index : Fin arity => index.val) old
    · simp only [pushCells, dif_pos leftBefore, dif_neg rightBefore] at same
      exact False.elim (cellDistinct ⟨left.val, leftBefore⟩ same)
    · simp only [pushCells, dif_neg leftBefore, dif_pos rightBefore] at same
      exact False.elim (cellDistinct ⟨right.val, rightBefore⟩ same.symm)
    · exact Fin.ext (by omega)
  · intro candidate worldMember localMember
    obtain ⟨index, same⟩ := localMember
    simp only [pushCells] at same
    split at same
    next before =>
      exact represented.worldLocalsDisjoint candidate worldMember
        ⟨⟨index.val, before⟩, same⟩
    next _ =>
      subst candidate
      exact worldDistinct worldMember

/-- Proof-ready representation for the common bounded loop shape: a mutable
    slice, a mutable cursor, and one read-only scalar bound.  Both ordinary
    local-cell identities remain hidden from clients. -/
structure SliceCursorBoundRepresentation
    (sliceId cursorId boundId : VarId) (sliceCell cursorCell : CellId)
    (sliceValues : List Int) (cursorValue boundValue : Value)
    (state : State) where
  sliceLocalCell : CellId
  boundLocalCell : CellId
  represented : Representation
    (Layout.push (pairLayout sliceId cursorId) boundId)
    (pushCells (pairCells sliceLocalCell cursorCell) boundLocalCell)
    (ReadOnly.World.singleton sliceCell sliceValues)
    ((pairEnvironment
      (.slice (.scalar (.signed .i32)) sliceCell [] 0 sliceValues.length)
      cursorValue).push boundValue) state

/-- Recover a bounded-loop representation from source-facing local reads and
    one separation fact for the two shared locals. -/
noncomputable def SliceCursorBoundRepresentation.ofState
    {sliceId cursorId boundId : VarId} {sliceCell cursorCell : CellId}
    {sliceValues : List Int} {cursorValue boundValue : Value} {state : State}
    (wellFormed : StateWellFormed state)
    (sliceLocal : state.local? sliceId = some
      (.slice (.scalar (.signed .i32)) sliceCell [] 0 sliceValues.length))
    (sliceBacking : state.cellEntry? sliceCell = some {
      id := sliceCell
      value := some (.array (signedI32Values sliceValues))
    })
    (cursorOwned : (Assertion.localPointsTo cursorId cursorCell
      (some cursorValue)).holds state)
    (boundLocal : state.local? boundId = some boundValue)
    (sharedSeparate : CellSet.Disjoint
      (localCellFootprint state (fun id => id = sliceId ∨ id = boundId))
      (CellSet.union (CellSet.singleton sliceCell)
        (CellSet.singleton cursorCell)))
    (cursorSlice : cursorCell ≠ sliceCell)
    (valueDistinct :
      (.slice (.scalar (.signed .i32)) sliceCell [] 0 sliceValues.length) ≠
        boundValue) :
    SliceCursorBoundRepresentation sliceId cursorId boundId sliceCell
      cursorCell sliceValues cursorValue boundValue state := by
  have sliceSeparate : CellSet.Disjoint
      (localCellFootprint state (fun id => id = sliceId))
      (CellSet.union (CellSet.singleton sliceCell)
        (CellSet.singleton cursorCell)) :=
    CellSet.Disjoint.mono_left (localCellFootprint_mono (by
      intro id same
      exact Or.inl same)) sharedSeparate
  let cursorView := SliceCursorRepresentation.ofState wellFormed sliceLocal
    sliceBacking cursorOwned sliceSeparate cursorSlice
  let witness := Assertion.exists_localPointsTo_of_local state boundId
    boundValue boundLocal
  let boundLocalCell := Classical.choose witness
  have boundOwned := Classical.choose_spec witness
  have boundEntry : state.cellEntry? boundLocalCell = some {
      id := boundLocalCell
      value := some boundValue
    } := by
    simpa [boundLocalCell] using boundOwned.2
  have boundMember : localCellFootprint state
      (fun id => id = sliceId ∨ id = boundId) boundLocalCell :=
    ⟨boundId, Or.inr rfl, boundOwned.1⟩
  have boundCursor : boundLocalCell ≠ cursorCell := by
    intro same
    exact sharedSeparate cursorCell (by simpa [same] using boundMember)
      (Or.inr rfl)
  have boundWorld :
      ¬(ReadOnly.World.owns
        (ReadOnly.World.singleton sliceCell sliceValues)).footprint
        boundLocalCell := by
    intro member
    obtain ⟨contents, found⟩ := member
    by_cases same : boundLocalCell = sliceCell
    · exact sharedSeparate boundLocalCell boundMember (Or.inl same)
    · simp [ReadOnly.World.singleton, same] at found
  have boundSliceLocal : cursorView.sliceLocalCell ≠ boundLocalCell := by
    intro same
    have sliceEntry : state.cellEntry? cursorView.sliceLocalCell = some {
        id := cursorView.sliceLocalCell
        value := some (.slice (.scalar (.signed .i32)) sliceCell [] 0
          sliceValues.length)
      } := by
      simpa [pairCells, pairEnvironment] using
        (cursorView.represented.localOwned ⟨0, by omega⟩).2
    rw [same] at sliceEntry
    have entriesEqual := sliceEntry.symm.trans boundEntry
    apply valueDistinct
    simpa using congrArg (fun entry => entry.bind Cell.value) entriesEqual
  exact {
    sliceLocalCell := cursorView.sliceLocalCell
    boundLocalCell := boundLocalCell
    represented := cursorView.represented.pushOwnedLocal boundOwned (by
      intro slot
      have cases : slot.val = 0 ∨ slot.val = 1 := by omega
      rcases cases with zero | one
      · have slotEq : slot = ⟨0, by omega⟩ := Fin.ext zero
        rw [slotEq]
        simpa [pairCells] using boundSliceLocal
      · have slotEq : slot = ⟨1, by omega⟩ := Fin.ext one
        rw [slotEq]
        simpa [pairCells] using boundCursor.symm) boundWorld
  }

theorem Representation.worldRepresents
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId} {world : ReadOnly.World}
    {environment : Env arity} {state : State}
    (represented : Representation layout localCell world environment state)
    (wellFormed : StateWellFormed state) :
    ReadOnly.World.Represents world state :=
  (ReadOnly.World.owns_iff_represents wellFormed).mp represented.worldOwned

theorem Representation.environmentMatches
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId} {world : ReadOnly.World}
    {environment : Env arity} {state : State}
    (represented : Representation layout localCell world environment state) :
    EnvironmentMatches layout environment state := by
  intro index
  exact Assertion.localPointsTo_local (layout index)
    (localCell index) (environment index) state
    (represented.localOwned index)

theorem Representation.worldCell_ne_localCell
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId} {world : ReadOnly.World}
    {environment : Env arity} {state : State}
    (represented : Representation layout localCell world environment state)
    (found : world.i32Slice? worldCell = some values) (index : Fin arity) :
    worldCell ≠ localCell index := by
  intro same
  exact represented.worldLocalsDisjoint worldCell ⟨values, found⟩
    ⟨index, same.symm⟩

theorem Representation.bindLocal
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId} {world : ReadOnly.World}
    {environment : Env arity} {state : State} {nextLocal : VarId}
    (represented : Representation layout localCell world environment state)
    (below : LayoutBelow layout nextLocal)
    (wellFormed : StateWellFormed state) (value : Value) :
    Representation (Layout.push layout nextLocal)
      (pushCells localCell state.nextCell) world
      (environment.push value) (state.bindLocal nextLocal value) := by
  let fresh := state.nextCell
  let cells : Fin (arity + 1) → CellId := pushCells localCell fresh
  have oldBelow (index : Fin arity) :
      localCell index < fresh :=
    StateWellFormed.cell_lt_next_of_entry wellFormed
      (represented.localOwned index).2
  refine {
    worldOwned := ?_
    localOwned := ?_
    localCellsInjective := ?_
    worldLocalsDisjoint := ?_
  }
  · intro cell values found
    obtain ⟨backing, old⟩ := represented.worldRepresents wellFormed cell values
      found
    exact (bindCell_preserves_old_cell state nextLocal (some value) cell old).trans
      backing
  · intro index
    simp only [cells, pushCells, Layout.push, Env.push]
    split
    next before =>
      exact ⟨by
        have different : nextLocal ≠ layout ⟨index.val, before⟩ :=
          (Nat.ne_of_lt (below _)).symm
        have preserved :
            (state.bindLocal nextLocal value).cellId?
                (layout ⟨index.val, before⟩) =
              state.cellId? (layout ⟨index.val, before⟩) := by
          simp [State.bindLocal, State.bindCell, State.cellId?, different]
        exact preserved.trans (represented.localOwned ⟨index.val, before⟩).1, by
        exact (bindCell_preserves_old_cell state nextLocal (some value)
          (localCell ⟨index.val, before⟩)
          (oldBelow ⟨index.val, before⟩)).trans
            (represented.localOwned ⟨index.val, before⟩).2⟩
    next notBefore =>
      exact bindLocal_owns_fresh state nextLocal value wellFormed
  · intro left right same
    by_cases leftBefore : left.val < arity <;>
      by_cases rightBefore : right.val < arity
    · simp only [cells, pushCells, dif_pos leftBefore, dif_pos rightBefore]
        at same
      have indices : (⟨left.val, leftBefore⟩ : Fin arity) =
          ⟨right.val, rightBefore⟩ :=
        represented.localCellsInjective same
      have valuesEqual : left.val = right.val :=
        congrArg (fun index : Fin arity => index.val) indices
      exact Fin.ext valuesEqual
    · simp only [cells, pushCells, dif_pos leftBefore, dif_neg rightBefore]
        at same
      exact False.elim (Nat.ne_of_lt (oldBelow ⟨left.val, leftBefore⟩) same)
    · simp only [cells, pushCells, dif_neg leftBefore, dif_pos rightBefore]
        at same
      exact False.elim (Nat.ne_of_lt (oldBelow ⟨right.val, rightBefore⟩)
        same.symm)
    · exact Fin.ext (by omega)
  · intro cell worldMember localMember
    obtain ⟨index, indexCell⟩ := localMember
    simp only [cells, pushCells] at indexCell
    split at indexCell
    next before =>
      exact represented.worldLocalsDisjoint cell worldMember
        ⟨⟨index.val, before⟩, indexCell⟩
    next notBefore =>
      have cellFresh : cell = fresh := indexCell.symm
      obtain ⟨values, found⟩ := worldMember
      have old := (represented.worldRepresents wellFormed cell values found).2
      exact (Nat.ne_of_lt old) cellFresh

/-- Local assignment updates one owned cell and reconstructs the complete
    representation.  Every abstract slice and every other local is framed. -/
theorem Representation.setLocalAfterTerm
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId}
    {beforeWorld afterWorld : ReadOnly.World}
    {environment : Env arity} {before afterRight : State}
    {program : Program} {value : Term Core.signature arity}
    {result : Value} {target : Fin arity} {rightWrites : CellSet}
    (beforeRepresented :
      Representation layout localCell beforeWorld environment before)
    (afterRightRepresented :
      Representation layout localCell afterWorld environment afterRight)
    (rightResult : Evaluates program before
      (Core.toCoreExpr layout value) result afterRight)
    (rightWellFormed : StateWellFormed afterRight)
    (rightEffect : ModifiesOnly rightWrites before afterRight) :
    ∃ after,
      Evaluates program before
        (.assign .set (.local (layout target)) (Core.toCoreExpr layout value))
        .unit after ∧
      StateWellFormed after ∧
      Representation layout localCell afterWorld
        (Env.set environment target result) after ∧
      ModifiesOnly (CellSet.union rightWrites
        (CellSet.singleton (localCell target))) before after := by
  obtain ⟨after, execution, afterWellFormed, targetOwned, effect,
      assignmentEffect⟩ :=
    evaluatesSetOwnedLocal (program := program) (layout target)
      (localCell target) (beforeRepresented.localOwned target)
      rightResult rightWellFormed (afterRightRepresented.localOwned target)
      rightEffect
  have worldOwned : (ReadOnly.World.owns afterWorld).holds after :=
    assignmentEffect.preserve rightWellFormed (ReadOnly.World.owns afterWorld)
      afterRightRepresented.worldOwned (by
        intro cell worldMember written
        obtain ⟨values, found⟩ := worldMember
        exact afterRightRepresented.worldCell_ne_localCell found target written)
  have localOwned : ∀ index,
      (Assertion.localPointsTo (layout index) (localCell index)
        (some (Env.set environment target result index))).holds after := by
    intro index
    by_cases same : index = target
    · subst index
      simpa using targetOwned
    · rw [Env.set_other environment target index result same]
      exact assignmentEffect.preserve rightWellFormed
        (Assertion.localPointsTo (layout index)
          (localCell index) (some (environment index)))
        (afterRightRepresented.localOwned index) (by
          intro cell member written
          exact same (afterRightRepresented.localCellsInjective
            (member.symm.trans written)))
  exact ⟨after, execution, afterWellFormed, {
    worldOwned := worldOwned
    localOwned := localOwned
    localCellsInjective := afterRightRepresented.localCellsInjective
    worldLocalsDisjoint := afterRightRepresented.worldLocalsDisjoint
  }, effect⟩

theorem Representation.setLocal
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId} {world : ReadOnly.World}
    {environment : Env arity} {state : State}
    {program : Program} {value : Term Core.signature arity}
    {result : Value} {target : Fin arity}
    (represented : Representation layout localCell world environment state)
    (wellFormed : StateWellFormed state)
    (valueResult : Term.evaluate (ReadOnly.machine program) world environment
      value = .ok (result, world)) :
    ∃ after,
      Evaluates program state
        (.assign .set (.local (layout target)) (Core.toCoreExpr layout value))
        .unit after ∧
      StateWellFormed after ∧
      Representation layout localCell world
        (Env.set environment target result) after ∧
      ModifiesOnly (CellSet.singleton (localCell target))
        state after := by
  have termSound := Core.term_evaluates (ReadOnly.bridge program)
    (represented.worldRepresents wellFormed)
    represented.environmentMatches valueResult
  obtain ⟨after, execution, afterWellFormed, targetOwned, effect⟩ :=
    evaluatesSetOwnedLocalFromEmpty (program := program) (layout target)
      (localCell target) wellFormed (represented.localOwned target)
      termSound.1 wellFormed (ModifiesOnly.refl state)
  have worldOwned : (ReadOnly.World.owns world).holds after :=
    effect.preserve wellFormed (ReadOnly.World.owns world)
      represented.worldOwned (by
        intro cell worldMember written
        obtain ⟨values, found⟩ := worldMember
        exact represented.worldCell_ne_localCell found target
          written)
  have localOwned : ∀ index,
      (Assertion.localPointsTo (layout index) (localCell index)
        (some (Env.set environment target result index))).holds after := by
    intro index
    by_cases same : index = target
    · subst index
      simpa using targetOwned
    · rw [Env.set_other environment target index result same]
      exact effect.preserve wellFormed
        (Assertion.localPointsTo (layout index)
          (localCell index) (some (environment index)))
        (represented.localOwned index) (by
          intro cell member written
          exact same (represented.localCellsInjective
            (member.symm.trans written)))
  exact ⟨after, execution, afterWellFormed, {
    worldOwned := worldOwned
    localOwned := localOwned
    localCellsInjective := represented.localCellsInjective
    worldLocalsDisjoint := represented.worldLocalsDisjoint
  }, effect⟩

/-- Compound local assignment has the same ownership rule as plain
    assignment; only the pure value transformer differs. -/
theorem Representation.updateLocalAfterTerm
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId}
    {beforeWorld afterWorld : ReadOnly.World}
    {environment : Env arity} {before afterRight : State}
    {program : Program} {value : Term Core.signature arity}
    {right result : Value} {target : Fin arity} {operation : AssignOp}
    {rightWrites : CellSet}
    (beforeRepresented :
      Representation layout localCell beforeWorld environment before)
    (afterRightRepresented :
      Representation layout localCell afterWorld environment afterRight)
    (rightResult : Evaluates program before
      (Core.toCoreExpr layout value) right afterRight)
    (rightWellFormed : StateWellFormed afterRight)
    (rightEffect : ModifiesOnly rightWrites before afterRight)
    (updated : evalAssignValue program.target operation
      (some (environment target)) right = .ok result) :
    ∃ after,
      Evaluates program before
        (.assign operation (.local (layout target))
          (Core.toCoreExpr layout value)) .unit after ∧
      StateWellFormed after ∧
      Representation layout localCell afterWorld
        (Env.set environment target result) after ∧
      ModifiesOnly (CellSet.union rightWrites
        (CellSet.singleton (localCell target))) before after := by
  obtain ⟨after, execution, afterWellFormed, targetOwned, effect,
      assignmentEffect⟩ :=
    evaluatesUpdateOwnedLocal (program := program) (layout target)
      (localCell target) operation (beforeRepresented.localOwned target)
      rightResult rightWellFormed (afterRightRepresented.localOwned target)
      rightEffect updated
  have worldOwned : (ReadOnly.World.owns afterWorld).holds after :=
    assignmentEffect.preserve rightWellFormed (ReadOnly.World.owns afterWorld)
      afterRightRepresented.worldOwned (by
        intro cell worldMember written
        obtain ⟨values, found⟩ := worldMember
        exact afterRightRepresented.worldCell_ne_localCell found target written)
  have localOwned : ∀ index,
      (Assertion.localPointsTo (layout index) (localCell index)
        (some (Env.set environment target result index))).holds after := by
    intro index
    by_cases same : index = target
    · subst index
      simpa using targetOwned
    · rw [Env.set_other environment target index result same]
      exact assignmentEffect.preserve rightWellFormed
        (Assertion.localPointsTo (layout index)
          (localCell index) (some (environment index)))
        (afterRightRepresented.localOwned index) (by
          intro cell member written
          exact same (afterRightRepresented.localCellsInjective
            (member.symm.trans written)))
  exact ⟨after, execution, afterWellFormed, {
    worldOwned := worldOwned
    localOwned := localOwned
    localCellsInjective := afterRightRepresented.localCellsInjective
    worldLocalsDisjoint := afterRightRepresented.worldLocalsDisjoint
  }, effect⟩

theorem Representation.updateLocal
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId} {world : ReadOnly.World}
    {environment : Env arity} {state : State}
    {program : Program} {value : Term Core.signature arity}
    {right result : Value} {target : Fin arity} {operation : AssignOp}
    (represented : Representation layout localCell world environment state)
    (wellFormed : StateWellFormed state)
    (valueResult : Term.evaluate (ReadOnly.machine program) world environment
      value = .ok (right, world))
    (updated : evalAssignValue program.target operation
      (some (environment target)) right = .ok result) :
    ∃ after,
      Evaluates program state
        (.assign operation (.local (layout target))
          (Core.toCoreExpr layout value)) .unit after ∧
      StateWellFormed after ∧
      Representation layout localCell world
        (Env.set environment target result) after ∧
      ModifiesOnly (CellSet.singleton (localCell target)) state after := by
  have termSound := Core.term_evaluates (ReadOnly.bridge program)
    (represented.worldRepresents wellFormed)
    represented.environmentMatches valueResult
  obtain ⟨after, execution, afterWellFormed, targetOwned, effect⟩ :=
    evaluatesUpdateOwnedLocalFromEmpty (program := program)
      (layout target) (localCell target) operation wellFormed
      (represented.localOwned target) termSound.1 wellFormed
      (ModifiesOnly.refl state) updated
  have worldOwned : (ReadOnly.World.owns world).holds after :=
    effect.preserve wellFormed (ReadOnly.World.owns world)
      represented.worldOwned (by
        intro cell worldMember written
        obtain ⟨values, found⟩ := worldMember
        exact represented.worldCell_ne_localCell found target written)
  have localOwned : ∀ index,
      (Assertion.localPointsTo (layout index) (localCell index)
        (some (Env.set environment target result index))).holds after := by
    intro index
    by_cases same : index = target
    · subst index
      simpa using targetOwned
    · rw [Env.set_other environment target index result same]
      exact effect.preserve wellFormed
        (Assertion.localPointsTo (layout index)
          (localCell index) (some (environment index)))
        (represented.localOwned index) (by
          intro cell member written
          exact same (represented.localCellsInjective
            (member.symm.trans written)))
  exact ⟨after, execution, afterWellFormed, {
    worldOwned := worldOwned
    localOwned := localOwned
    localCellsInjective := represented.localCellsInjective
    worldLocalsDisjoint := represented.worldLocalsDisjoint
  }, effect⟩

theorem ReadOnly.World.setI32Slice_footprint
    (found : world.i32Slice? cell = some values) :
    (ReadOnly.World.owns
      (ReadOnly.World.setI32Slice world cell replacement)).footprint =
      (ReadOnly.World.owns world).footprint := by
  funext candidate
  apply propext
  constructor
  · rintro ⟨contents, member⟩
    by_cases same : candidate = cell
    · subst candidate
      exact ⟨values, found⟩
    · exact ⟨contents, by
        simpa [ReadOnly.World.setI32Slice, same] using member⟩
  · rintro ⟨contents, member⟩
    by_cases same : candidate = cell
    · subst candidate
      exact ⟨replacement, by simp⟩
    · exact ⟨contents, by
        simpa [ReadOnly.World.setI32Slice, same] using member⟩

/-- Replace one owned abstract slice after a source operation has rewritten
    exactly its backing cell.  This is the call-level analogue of
    `setI32IndexCore`: clients supply the whole-slice postcondition, while
    FunctionalView discharges all local framing and footprint bookkeeping. -/
theorem Representation.replaceI32Slice
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId} {world : ReadOnly.World}
    {environment : Env arity} {before after : State}
    {cell : CellId} {beforeValues afterValues : List Int}
    (represented : Representation layout localCell world environment before)
    (beforeWellFormed : StateWellFormed before)
    (found : world.i32Slice? cell = some beforeValues)
    (effect : ModifiesOnly (CellSet.singleton cell) before after)
    (afterBacking : after.cellEntry? cell = some {
      id := cell
      value := some (.array (signedI32Values afterValues)) }) :
    Representation layout localCell
      (ReadOnly.World.setI32Slice world cell afterValues) environment after := by
  have afterWorldOwned : (ReadOnly.World.owns
      (ReadOnly.World.setI32Slice world cell afterValues)).holds after := by
    intro candidate contents candidateFound
    by_cases same : candidate = cell
    · subst candidate
      have contentsEq : contents = afterValues := by
        simpa using candidateFound.symm
      subst contents
      exact afterBacking
    · have oldFound : world.i32Slice? candidate = some contents := by
        simpa [ReadOnly.World.setI32Slice, same] using candidateFound
      exact effect.preserves_entry beforeWellFormed
        (represented.worldOwned candidate contents oldFound) (by
          simpa [CellSet.singleton] using same)
  have footprint := ReadOnly.World.setI32Slice_footprint
    (replacement := afterValues) found
  exact {
    worldOwned := afterWorldOwned
    localOwned := fun index =>
      effect.preserves_localPointsTo beforeWellFormed
        (represented.localOwned index) (by
          simpa [CellSet.singleton] using
            (represented.worldCell_ne_localCell found index).symm)
    localCellsInjective := represented.localCellsInjective
    worldLocalsDisjoint := by simpa [footprint] using
      represented.worldLocalsDisjoint
  }

/-- One indexed action updates the abstract world and preserves all owned
    locals by the separation frame. -/
theorem Representation.setI32IndexCore
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId} {world : ReadOnly.World}
    {environment : Env arity} {state : State} {program : Program}
    {base : Fin arity} {index value : Term Core.signature arity}
    {cell : CellId} {values : List Int} {position : Nat}
    {replacement : Int}
    (represented : Representation layout localCell world environment state)
    (wellFormed : StateWellFormed state)
    (baseLocal : state.local? (layout base) = some
      (.slice (.scalar (.signed .i32)) cell [] 0 values.length))
    (indexSound : Evaluates program state (Core.toCoreExpr layout index)
      (.signed .i32 (Int.ofNat position)) state)
    (valueSound : Evaluates program state (Core.toCoreExpr layout value)
      (.signed .i32 replacement) state)
    (found : world.i32Slice? cell = some values)
    (inBounds : position < values.length) :
    ∃ after,
      Executes program state
        (actionAdapter.toCoreStmt layout (.setI32Index base index value))
        .next after ∧
      StateWellFormed after ∧
      Representation layout localCell
        (ReadOnly.World.setI32Slice world cell
          (setI32Value values position replacement)) environment after ∧
      ModifiesOnly (CellSet.singleton cell) state after := by
  obtain ⟨after, execution, afterWellFormed, worldOwned, effect⟩ :=
    executes_setI32IndexCore wellFormed represented.worldOwned baseLocal
      indexSound valueSound found inBounds
  have localOwned : ∀ index,
      (Assertion.localPointsTo (layout index) (localCell index)
        (some (environment index))).holds after := by
    intro index
    exact effect.preserve wellFormed
      (Assertion.localPointsTo (layout index) (localCell index)
        (some (environment index))) (represented.localOwned index) (by
          intro queried member written
          exact represented.worldCell_ne_localCell found index
            (written.symm.trans member))
  have footprint := ReadOnly.World.setI32Slice_footprint
    (replacement := setI32Value values position replacement) found
  exact ⟨after, execution, afterWellFormed, {
    worldOwned := worldOwned
    localOwned := localOwned
    localCellsInjective := represented.localCellsInjective
    worldLocalsDisjoint := by simpa [footprint] using
      represented.worldLocalsDisjoint
  }, effect⟩

/-- FunctionalView wrapper for the Core-level separation rule. -/
theorem Representation.setI32Index
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId} {world : ReadOnly.World}
    {environment : Env arity} {state : State} {program : Program}
    {base : Fin arity} {index value : Term Core.signature arity}
    {cell : CellId} {values : List Int} {position : Nat}
    {replacement : Int}
    (represented : Representation layout localCell world environment state)
    (wellFormed : StateWellFormed state)
    (baseValue : environment base =
      .slice (.scalar (.signed .i32)) cell [] 0 values.length)
    (indexResult : Term.evaluate (ReadOnly.machine program) world environment
      index = .ok (.signed .i32 (Int.ofNat position), world))
    (valueResult : Term.evaluate (ReadOnly.machine program) world environment
      value = .ok (.signed .i32 replacement, world))
    (found : world.i32Slice? cell = some values)
    (inBounds : position < values.length) :
    ∃ after,
      Executes program state
        (actionAdapter.toCoreStmt layout (.setI32Index base index value))
        .next after ∧
      StateWellFormed after ∧
      Representation layout localCell
        (ReadOnly.World.setI32Slice world cell
          (setI32Value values position replacement)) environment after ∧
      ModifiesOnly (CellSet.singleton cell) state after := by
  have representedWorld := represented.worldRepresents wellFormed
  have indexSound := Core.term_evaluates (ReadOnly.bridge program)
    representedWorld represented.environmentMatches indexResult
  have valueSound := Core.term_evaluates (ReadOnly.bridge program)
    representedWorld represented.environmentMatches valueResult
  have baseLocal : state.local? (layout base) = some
      (.slice (.scalar (.signed .i32)) cell [] 0 values.length) := by
    rw [represented.environmentMatches base, baseValue]
  exact represented.setI32IndexCore wellFormed baseLocal indexSound.1
    valueSound.1 found inBounds

/-- The common mutable-loop step: update one owned `i32` slice element and
    then advance an owned scalar local.  Keeping this rule at the FunctionalView
    boundary exposes the exact two-cell write footprint to clients; parser and
    lexer invariants therefore frame their unrelated resources without
    replaying Core's assignment semantics by hand. -/
theorem Representation.setI32IndexThenSetLocal
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId} {world : ReadOnly.World}
    {environment : Env arity} {state : State} {program : Program}
    {base target : Fin arity} {index replacement nextValue :
      Term Core.signature arity}
    {cell : CellId} {values : List Int} {position : Nat}
    {replacementValue : Int} {nextResult : Value}
    (represented : Representation layout localCell world environment state)
    (wellFormed : StateWellFormed state)
    (baseValue : environment base =
      .slice (.scalar (.signed .i32)) cell [] 0 values.length)
    (indexResult : Term.evaluate (ReadOnly.machine program) world environment
      index = .ok (.signed .i32 (Int.ofNat position), world))
    (replacementResult : Term.evaluate (ReadOnly.machine program) world
      environment replacement = .ok (.signed .i32 replacementValue, world))
    (found : world.i32Slice? cell = some values)
    (inBounds : position < values.length)
    (nextResultEval : Term.evaluate (ReadOnly.machine program)
      (ReadOnly.World.setI32Slice world cell
        (setI32Value values position replacementValue)) environment
      nextValue = .ok (nextResult,
        ReadOnly.World.setI32Slice world cell
          (setI32Value values position replacementValue))) :
    ∃ after,
      Executes program state
        (toCoreStmt actionAdapter layout nextLocal
          (.sequence
            (.action (.setI32Index base index replacement))
            (.setLocal target nextValue)))
        .next after ∧
      StateWellFormed after ∧
      Representation layout localCell
        (ReadOnly.World.setI32Slice world cell
          (setI32Value values position replacementValue))
        (Env.set environment target nextResult) after ∧
      ModifiesOnly
        (CellSet.union (CellSet.singleton cell)
          (CellSet.singleton (localCell target))) state after := by
  obtain ⟨written, writeExecution, writtenWellFormed,
      writtenRepresentation, writeEffect⟩ :=
    represented.setI32Index wellFormed baseValue indexResult
      replacementResult found inBounds
  obtain ⟨after, localExecution, afterWellFormed,
      afterRepresentation, localEffect⟩ :=
    writtenRepresentation.setLocal writtenWellFormed nextResultEval
  refine ⟨after, ?_, afterWellFormed, afterRepresentation, ?_⟩
  · simpa [toCoreStmt, localCapacity] using
      executesSequence writeExecution (executesExpression localExecution)
  · exact writeEffect.trans localEffect

/-- Compound-assignment variant of `setI32IndexThenSetLocal`.  This is the
    canonical shape of parser and lexer cursor loops (`buffer[i] = value;
    i += step`). -/
theorem Representation.setI32IndexThenUpdateLocal
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId} {world : ReadOnly.World}
    {environment : Env arity} {state : State} {program : Program}
    {base target : Fin arity} {index replacement right :
      Term Core.signature arity}
    {cell : CellId} {values : List Int} {position : Nat}
    {replacementValue : Int} {rightValue nextResult : Value}
    {operation : AssignOp}
    (represented : Representation layout localCell world environment state)
    (wellFormed : StateWellFormed state)
    (baseValue : environment base =
      .slice (.scalar (.signed .i32)) cell [] 0 values.length)
    (indexResult : Term.evaluate (ReadOnly.machine program) world environment
      index = .ok (.signed .i32 (Int.ofNat position), world))
    (replacementResult : Term.evaluate (ReadOnly.machine program) world
      environment replacement = .ok (.signed .i32 replacementValue, world))
    (found : world.i32Slice? cell = some values)
    (inBounds : position < values.length)
    (rightResult : Term.evaluate (ReadOnly.machine program)
      (ReadOnly.World.setI32Slice world cell
        (setI32Value values position replacementValue)) environment right =
      .ok (rightValue, ReadOnly.World.setI32Slice world cell
        (setI32Value values position replacementValue)))
    (updated : evalAssignValue program.target operation
      (some (environment target)) rightValue = .ok nextResult) :
    ∃ after,
      Executes program state
        (toCoreStmt actionAdapter layout nextLocal
          (.sequence
            (.action (.setI32Index base index replacement))
            (.updateLocal operation target right)))
        .next after ∧
      StateWellFormed after ∧
      Representation layout localCell
        (ReadOnly.World.setI32Slice world cell
          (setI32Value values position replacementValue))
        (Env.set environment target nextResult) after ∧
      ModifiesOnly
        (CellSet.union (CellSet.singleton cell)
          (CellSet.singleton (localCell target))) state after := by
  obtain ⟨written, writeExecution, writtenWellFormed,
      writtenRepresentation, writeEffect⟩ :=
    represented.setI32Index wellFormed baseValue indexResult
      replacementResult found inBounds
  obtain ⟨after, localExecution, afterWellFormed,
      afterRepresentation, localEffect⟩ :=
    writtenRepresentation.updateLocal writtenWellFormed rightResult updated
  refine ⟨after, ?_, afterWellFormed, afterRepresentation, ?_⟩
  · simpa [toCoreStmt, localCapacity] using
      executesSequence writeExecution (executesExpression localExecution)
  · exact writeEffect.trans localEffect

/-- Structural-Core normalization often retains a trailing `skip` after a
    compound assignment.  This companion rule keeps that administrative node
    out of client proofs while preserving an exact round trip to the extracted
    statement. -/
theorem Representation.setI32IndexThenUpdateLocalAndSkip
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId} {world : ReadOnly.World}
    {environment : Env arity} {state : State} {program : Program}
    {base target : Fin arity} {index replacement right :
      Term Core.signature arity}
    {cell : CellId} {values : List Int} {position : Nat}
    {replacementValue : Int} {rightValue nextResult : Value}
    {operation : AssignOp}
    (represented : Representation layout localCell world environment state)
    (wellFormed : StateWellFormed state)
    (baseValue : environment base =
      .slice (.scalar (.signed .i32)) cell [] 0 values.length)
    (indexResult : Term.evaluate (ReadOnly.machine program) world environment
      index = .ok (.signed .i32 (Int.ofNat position), world))
    (replacementResult : Term.evaluate (ReadOnly.machine program) world
      environment replacement = .ok (.signed .i32 replacementValue, world))
    (found : world.i32Slice? cell = some values)
    (inBounds : position < values.length)
    (rightResult : Term.evaluate (ReadOnly.machine program)
      (ReadOnly.World.setI32Slice world cell
        (setI32Value values position replacementValue)) environment right =
      .ok (rightValue, ReadOnly.World.setI32Slice world cell
        (setI32Value values position replacementValue)))
    (updated : evalAssignValue program.target operation
      (some (environment target)) rightValue = .ok nextResult) :
    ∃ after,
      Executes program state
        (toCoreStmt actionAdapter layout nextLocal
          (.sequence
            (.action (.setI32Index base index replacement))
            (.sequence (.updateLocal operation target right) .skip)))
        .next after ∧
      StateWellFormed after ∧
      Representation layout localCell
        (ReadOnly.World.setI32Slice world cell
          (setI32Value values position replacementValue))
        (Env.set environment target nextResult) after ∧
      ModifiesOnly
        (CellSet.union (CellSet.singleton cell)
          (CellSet.singleton (localCell target))) state after := by
  obtain ⟨written, writeExecution, writtenWellFormed,
      writtenRepresentation, writeEffect⟩ :=
    represented.setI32Index wellFormed baseValue indexResult
      replacementResult found inBounds
  obtain ⟨after, localExecution, afterWellFormed,
      afterRepresentation, localEffect⟩ :=
    writtenRepresentation.updateLocal writtenWellFormed rightResult updated
  refine ⟨after, ?_, afterWellFormed, afterRepresentation, ?_⟩
  · simpa [toCoreStmt, localCapacity] using
      executesSequence writeExecution
        (executesSequence (executesExpression localExecution)
          (executesSkip program after))
  · exact writeEffect.trans localEffect

/-- Specialization for the ubiquitous bounded cursor step
    `slice[cursor] = replacement; cursor += 1`.  The index read, literal-one
    evaluation, and wrapped `i32` addition are proved once here. -/
theorem Representation.setI32AtCursorThenIncrementAndSkip
    {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId} {world : ReadOnly.World}
    {environment : Env arity} {state : State} {program : Program}
    {base cursor : Fin arity} {replacement : Term Core.signature arity}
    {cell : CellId} {values : List Int} {position : Nat}
    {replacementValue : Int}
    (represented : Representation layout localCell world environment state)
    (wellFormed : StateWellFormed state)
    (baseValue : environment base =
      .slice (.scalar (.signed .i32)) cell [] 0 values.length)
    (cursorValue : environment cursor =
      .signed .i32 (Int.ofNat position))
    (replacementResult : Term.evaluate (ReadOnly.machine program) world
      environment replacement = .ok (.signed .i32 replacementValue, world))
    (found : world.i32Slice? cell = some values)
    (inBounds : position < values.length)
    (incrementBound : position + 1 ≤ 2147483647) :
    ∃ after,
      Executes program state
        (toCoreStmt actionAdapter layout nextLocal
          (.sequence
            (.action (.setI32Index base (.reference (.slot cursor))
              replacement))
            (.sequence
              (.updateLocal .add cursor
                (.reference (.literal (.signed .i32 1))))
              .skip)))
        .next after ∧
      StateWellFormed after ∧
      Representation layout localCell
        (ReadOnly.World.setI32Slice world cell
          (setI32Value values position replacementValue))
        (Env.set environment cursor
          (.signed .i32 (Int.ofNat (position + 1)))) after ∧
      ModifiesOnly
        (CellSet.union (CellSet.singleton cell)
          (CellSet.singleton (localCell cursor))) state after := by
  have indexResult : Term.evaluate (ReadOnly.machine program) world environment
      (.reference (.slot cursor)) =
      .ok (.signed .i32 (Int.ofNat position), world) := by
    simp [Term.evaluate, Ref.evaluate, cursorValue]
  have oneResult : Term.evaluate (ReadOnly.machine program)
      (ReadOnly.World.setI32Slice world cell
        (setI32Value values position replacementValue)) environment
      (.reference (.literal (.signed .i32 1))) =
      .ok (.signed .i32 1, ReadOnly.World.setI32Slice world cell
        (setI32Value values position replacementValue)) := by
    rfl
  have addition : Int.ofNat position + 1 = Int.ofNat (position + 1) := by
    simpa using (Int.natCast_add position 1).symm
  have wrapped := wrapSigned_i32_ofNat program.target (position + 1)
    incrementBound
  have updated : evalAssignValue program.target .add
      (some (.signed .i32 (Int.ofNat position))) (.signed .i32 1) =
      .ok (.signed .i32 (Int.ofNat (position + 1))) := by
    simp only [evalAssignValue, assignOpBinary?, evalBinaryValue,
      beq_self_eq_true, if_true, evalSignedBinary]
    rw [addition, wrapped]
  exact represented.setI32IndexThenUpdateLocalAndSkip wellFormed baseValue
    indexResult replacementResult found inBounds oneResult (by
      simpa [cursorValue] using updated)

/-! ## Fixed-footprint loop simulation

`FunctionalView.Stateful.Loop` proves termination and functional behavior
without mentioning physical cells.  The bridge below adds the separation
contract needed by compiler proofs: the body receives one declared write
footprint, and recursive loop assembly preserves that same permission instead
of exposing a growing union of per-iteration implementation details.
-/

/-- A FunctionalView command simulated by Core while staying inside one
    declared separation-logic write footprint. -/
def SimulatesWithin
    (program : Program) (layout : Layout arity)
    (localCell : Fin arity → CellId)
    (beforeWorld : ReadOnly.World) (beforeEnvironment : Env arity)
    (before : State) (command : Command Core.signature actions arity)
    (completion : Lanius.FunctionalView.Stateful.Completion)
    (afterWorld : ReadOnly.World) (afterEnvironment : Env arity)
    (adapter : ActionAdapter actions) (nextLocal : VarId)
    (writes : CellSet) : Prop :=
  ∃ after,
    Executes program before (toCoreStmt adapter layout nextLocal command)
      (Stateful.toCoreCompletion completion) after ∧
    StateWellFormed after ∧
    Representation layout localCell afterWorld afterEnvironment after ∧
    ModifiesOnly writes before after

/-- The reusable local obligation for a fixed-footprint loop.  It is stated
    against FunctionalView evaluation, so a compiler-specific proof only
    explains the mutation performed by one body execution. -/
def BodySoundWithin
    (program : Program) (layout : Layout arity)
    (localCell : Fin arity → CellId)
    (body : Command Core.signature actions arity)
    (adapter : ActionAdapter actions) (nextLocal : VarId)
    (writes : CellSet)
    (Valid : Lanius.FunctionalView.Stateful.Loop.Runtime
      (ReadOnly.machine program) arity → Prop) : Prop :=
  ∀ {beforeWorld afterWorld : ReadOnly.World}
    {beforeEnvironment afterEnvironment : Env arity}
    {before : State}
    {completion : Lanius.FunctionalView.Stateful.Completion},
    Valid ⟨beforeWorld, beforeEnvironment⟩ →
    Command.Evaluates (ReadOnly.machine program) (machine program)
      beforeWorld beforeEnvironment body completion afterWorld
      afterEnvironment →
    Representation layout localCell beforeWorld beforeEnvironment before →
    StateWellFormed before →
    SimulatesWithin program layout localCell beforeWorld beforeEnvironment
      before body completion afterWorld afterEnvironment adapter nextLocal
      writes

/-- Lift a total FunctionalView loop trace to structural Core.  Condition
    evaluation is read-only and therefore discharged generically; body
    mutation is supplied once through `BodySoundWithin`. -/
theorem Lanius.FunctionalView.Stateful.Loop.Trace.simulatesWithin
    {arity : Nat} {program : Program}
    {condition : Term Core.signature arity}
    {body : Command Core.signature actions arity}
    {before after : Lanius.FunctionalView.Stateful.Loop.Runtime
      (ReadOnly.machine program) arity}
    {completion : Lanius.FunctionalView.Stateful.Completion}
    {layout : Layout arity} {localCell : Fin arity → CellId}
    {state : State} {adapter : ActionAdapter actions}
    {nextLocal : VarId} {writes : CellSet}
    {Valid : Lanius.FunctionalView.Stateful.Loop.Runtime
      (ReadOnly.machine program) arity → Prop}
    (trace : Lanius.FunctionalView.Stateful.Loop.Trace
      (ReadOnly.machine program) (machine program) condition body before
      completion after)
    (bodySound : BodySoundWithin program layout localCell body adapter
      nextLocal writes Valid)
    (validBefore : Valid before)
    (validIteration : ∀ {iterationBefore iterationAfter},
      Lanius.FunctionalView.Stateful.Loop.Iteration
        (ReadOnly.machine program) (machine program) condition body
        iterationBefore iterationAfter →
      Valid iterationBefore → Valid iterationAfter)
    (represented : Representation layout localCell before.world
      before.environment state)
    (wellFormed : StateWellFormed state) :
    SimulatesWithin program layout localCell before.world before.environment
      state (.whileLoop condition body) completion after.world
      after.environment adapter nextLocal writes := by
  induction trace generalizing state with
  | exit edge =>
      cases edge with
      | conditionFalse conditionResult environmentEq =>
          have worldEq := ReadOnly.Term.evaluate_world_eq conditionResult
          have conditionSound := Core.term_evaluates (ReadOnly.bridge program)
            (represented.worldRepresents wellFormed)
            represented.environmentMatches conditionResult
          rw [worldEq, environmentEq]
          exact ⟨state, by
            simpa only [toCoreStmt, Stateful.toCoreCompletion] using
              executesWhileFalse conditionSound.1,
            wellFormed, represented, ModifiesOnly.reflAny writes state⟩
      | breakLoop conditionResult bodyResult =>
          have worldEq := ReadOnly.Term.evaluate_world_eq conditionResult
          have conditionSound := Core.term_evaluates (ReadOnly.bridge program)
            (represented.worldRepresents wellFormed)
            represented.environmentMatches conditionResult
          subst worldEq
          obtain ⟨final, bodyExecution, finalWellFormed, finalRepresented,
              bodyEffect⟩ :=
            bodySound validBefore bodyResult represented wellFormed
          exact ⟨final, by
            simpa only [toCoreStmt, Stateful.toCoreCompletion] using
              executesWhileBreak conditionSound.1 bodyExecution,
            finalWellFormed, finalRepresented, bodyEffect⟩
      | returned conditionResult bodyResult =>
          have worldEq := ReadOnly.Term.evaluate_world_eq conditionResult
          have conditionSound := Core.term_evaluates (ReadOnly.bridge program)
            (represented.worldRepresents wellFormed)
            represented.environmentMatches conditionResult
          subst worldEq
          obtain ⟨final, bodyExecution, finalWellFormed, finalRepresented,
              bodyEffect⟩ :=
            bodySound validBefore bodyResult represented wellFormed
          exact ⟨final, by
            simpa only [toCoreStmt, Stateful.toCoreCompletion] using
              executesWhileReturned conditionSound.1 bodyExecution,
            finalWellFormed, finalRepresented, bodyEffect⟩
  | step edge rest induction =>
      cases edge with
      | next conditionResult bodyResult =>
          have worldEq := ReadOnly.Term.evaluate_world_eq conditionResult
          have conditionSound := Core.term_evaluates (ReadOnly.bridge program)
            (represented.worldRepresents wellFormed)
            represented.environmentMatches conditionResult
          subst worldEq
          obtain ⟨middle, bodyExecution, middleWellFormed,
              middleRepresented, bodyEffect⟩ :=
            bodySound validBefore bodyResult represented wellFormed
          have validMiddle := validIteration
            (.next conditionResult bodyResult) validBefore
          obtain ⟨final, restExecution, finalWellFormed, finalRepresented,
              restEffect⟩ := induction validMiddle middleRepresented
            middleWellFormed
          exact ⟨final, by
            simpa only [toCoreStmt, Stateful.toCoreCompletion] using
              executesWhileTrueThen conditionSound.1 bodyExecution
                restExecution,
            finalWellFormed, finalRepresented,
            bodyEffect.trans_same restEffect⟩
      | continueLoop conditionResult bodyResult =>
          have worldEq := ReadOnly.Term.evaluate_world_eq conditionResult
          have conditionSound := Core.term_evaluates (ReadOnly.bridge program)
            (represented.worldRepresents wellFormed)
            represented.environmentMatches conditionResult
          subst worldEq
          obtain ⟨middle, bodyExecution, middleWellFormed,
              middleRepresented, bodyEffect⟩ :=
            bodySound validBefore bodyResult represented wellFormed
          have validMiddle := validIteration
            (.continueLoop conditionResult bodyResult) validBefore
          obtain ⟨final, restExecution, finalWellFormed, finalRepresented,
              restEffect⟩ := induction validMiddle middleRepresented
            middleWellFormed
          exact ⟨final, by
            simpa only [toCoreStmt, Stateful.toCoreCompletion] using
              executesWhileContinueThen conditionSound.1 bodyExecution
                restExecution,
            finalWellFormed, finalRepresented,
            bodyEffect.trans_same restEffect⟩

/-- Configuration-indexed body soundness.  Unlike `BodySoundWithin`, this
    exposes the algorithmic configuration for the current edge, so bounds and
    logical resource identities need not be reconstructed from raw values. -/
def ConfigBodySoundWithin
    (program : Program) (layout : Layout arity)
    (localCell : Fin arity → CellId)
    (condition : Term Core.signature arity)
    (body : Command Core.signature actions arity)
    (adapter : ActionAdapter actions) (nextLocal : VarId)
    (writes : CellSet) (Config : Type u)
    (runtime : Config → Lanius.FunctionalView.Stateful.Loop.Runtime
      (ReadOnly.machine program) arity) : Prop :=
  ∀ (config : Config) {afterWorld : ReadOnly.World}
    {afterEnvironment : Env arity} {before : State}
    {completion : Lanius.FunctionalView.Stateful.Completion},
    Term.evaluate (ReadOnly.machine program) (runtime config).world
      (runtime config).environment condition =
        .ok (.boolean true, (runtime config).world) →
    Command.Evaluates (ReadOnly.machine program) (machine program)
      (runtime config).world (runtime config).environment body completion
      afterWorld afterEnvironment →
    Representation layout localCell (runtime config).world
      (runtime config).environment before →
    StateWellFormed before →
    SimulatesWithin program layout localCell (runtime config).world
      (runtime config).environment before body completion afterWorld
      afterEnvironment adapter nextLocal writes

/-- A local update is a reusable fixed-footprint loop body.  Clients prove
    only the functional value and assignment equations for each algorithmic
    configuration; determinism and separation framing are discharged here. -/
theorem updateLocalConfigBodySoundWithin
    {arity : Nat} {program : Program}
    {layout : Layout arity} {localCell : Fin arity → CellId}
    {condition : Term Core.signature arity}
    {adapter : ActionAdapter actions} {nextLocal : VarId}
    {Config : Type u}
    {runtime : Config → Lanius.FunctionalView.Stateful.Loop.Runtime
      (ReadOnly.machine program) arity}
    {operation : AssignOp} {target : Fin arity}
    {value : Term Core.signature arity}
    (right : Config → Value) (result : Config → Value)
    (valueResult : ∀ config,
      Term.evaluate (ReadOnly.machine program) (runtime config).world
        (runtime config).environment condition =
          .ok (.boolean true, (runtime config).world) →
      Term.evaluate (ReadOnly.machine program) (runtime config).world
        (runtime config).environment value =
        .ok (right config, (runtime config).world))
    (updateResult : ∀ config,
      Term.evaluate (ReadOnly.machine program) (runtime config).world
        (runtime config).environment condition =
          .ok (.boolean true, (runtime config).world) →
      evalAssignValue program.target operation
        (some ((runtime config).environment target)) (right config) =
        .ok (result config)) :
    ConfigBodySoundWithin program layout localCell condition
      (.updateLocal operation target value) adapter nextLocal
      (CellSet.singleton (localCell target)) Config runtime := by
  intro config afterWorld afterEnvironment before completion conditionTrue evaluated
    represented wellFormed
  have canonical : Command.Evaluates (ReadOnly.machine program)
      (machine program) (runtime config).world (runtime config).environment
      (.updateLocal operation target value) .next (runtime config).world
      (Env.set (runtime config).environment target (result config)) :=
    .updateLocal (valueResult config conditionTrue) (by
      simpa [machine, machineWith] using updateResult config conditionTrue)
  obtain ⟨completionEq, worldEq, environmentEq⟩ :=
    canonical.deterministic evaluated
  cases completionEq
  cases worldEq
  cases environmentEq
  obtain ⟨after, execution, afterWellFormed, afterRepresented, effect⟩ :=
    represented.updateLocal wellFormed (valueResult config conditionTrue)
      (updateResult config conditionTrue)
  exact ⟨after, by
      simpa only [toCoreStmt, toCoreCompletion] using
        executesExpression execution,
    afterWellFormed, afterRepresented, effect⟩

/-- Configuration-preserving fixed-footprint bridge from a total
    FunctionalView loop to structural Core. -/
theorem Lanius.FunctionalView.Stateful.Loop.ConfigTrace.simulatesWithin
    {arity : Nat} {program : Program}
    {condition : Term Core.signature arity}
    {body : Command Core.signature actions arity}
    {Config : Type u}
    {runtime : Config → Lanius.FunctionalView.Stateful.Loop.Runtime
      (ReadOnly.machine program) arity}
    {config : Config}
    {after : Lanius.FunctionalView.Stateful.Loop.Runtime
      (ReadOnly.machine program) arity}
    {completion : Lanius.FunctionalView.Stateful.Completion}
    {layout : Layout arity} {localCell : Fin arity → CellId}
    {state : State} {adapter : ActionAdapter actions}
    {nextLocal : VarId} {writes : CellSet}
    (trace : Lanius.FunctionalView.Stateful.Loop.ConfigTrace
      (ReadOnly.machine program) (machine program) condition body Config
      runtime config completion after)
    (bodySound : ConfigBodySoundWithin program layout localCell condition body
      adapter nextLocal writes Config runtime)
    (represented : Representation layout localCell (runtime config).world
      (runtime config).environment state)
    (wellFormed : StateWellFormed state) :
    SimulatesWithin program layout localCell (runtime config).world
      (runtime config).environment state (.whileLoop condition body) completion
      after.world after.environment adapter nextLocal writes := by
  induction trace generalizing state with
  | exit edge =>
      cases edge with
      | conditionFalse conditionResult environmentEq =>
          have worldEq := ReadOnly.Term.evaluate_world_eq conditionResult
          have conditionSound := Core.term_evaluates (ReadOnly.bridge program)
            (represented.worldRepresents wellFormed)
            represented.environmentMatches conditionResult
          rw [worldEq, environmentEq]
          exact ⟨state, by
            simpa only [toCoreStmt, Stateful.toCoreCompletion] using
              executesWhileFalse conditionSound.1,
            wellFormed, represented, ModifiesOnly.reflAny writes state⟩
      | breakLoop conditionResult bodyResult =>
          have worldEq := ReadOnly.Term.evaluate_world_eq conditionResult
          have conditionSound := Core.term_evaluates (ReadOnly.bridge program)
            (represented.worldRepresents wellFormed)
            represented.environmentMatches conditionResult
          subst worldEq
          obtain ⟨final, bodyExecution, finalWellFormed, finalRepresented,
              bodyEffect⟩ :=
            bodySound _ conditionResult bodyResult represented wellFormed
          exact ⟨final, by
            simpa only [toCoreStmt, Stateful.toCoreCompletion] using
              executesWhileBreak conditionSound.1 bodyExecution,
            finalWellFormed, finalRepresented, bodyEffect⟩
      | returned conditionResult bodyResult =>
          have worldEq := ReadOnly.Term.evaluate_world_eq conditionResult
          have conditionSound := Core.term_evaluates (ReadOnly.bridge program)
            (represented.worldRepresents wellFormed)
            represented.environmentMatches conditionResult
          subst worldEq
          obtain ⟨final, bodyExecution, finalWellFormed, finalRepresented,
              bodyEffect⟩ :=
            bodySound _ conditionResult bodyResult represented wellFormed
          exact ⟨final, by
            simpa only [toCoreStmt, Stateful.toCoreCompletion] using
              executesWhileReturned conditionSound.1 bodyExecution,
            finalWellFormed, finalRepresented, bodyEffect⟩
  | step next edge rest induction =>
      cases edge with
      | next conditionResult bodyResult =>
          have worldEq := ReadOnly.Term.evaluate_world_eq conditionResult
          have conditionSound := Core.term_evaluates (ReadOnly.bridge program)
            (represented.worldRepresents wellFormed)
            represented.environmentMatches conditionResult
          subst worldEq
          obtain ⟨middle, bodyExecution, middleWellFormed,
              middleRepresented, bodyEffect⟩ :=
            bodySound _ conditionResult bodyResult represented wellFormed
          obtain ⟨final, restExecution, finalWellFormed, finalRepresented,
              restEffect⟩ := induction middleRepresented middleWellFormed
          exact ⟨final, by
            simpa only [toCoreStmt, Stateful.toCoreCompletion] using
              executesWhileTrueThen conditionSound.1 bodyExecution
                restExecution,
            finalWellFormed, finalRepresented,
            bodyEffect.trans_same restEffect⟩
      | continueLoop conditionResult bodyResult =>
          have worldEq := ReadOnly.Term.evaluate_world_eq conditionResult
          have conditionSound := Core.term_evaluates (ReadOnly.bridge program)
            (represented.worldRepresents wellFormed)
            represented.environmentMatches conditionResult
          subst worldEq
          obtain ⟨middle, bodyExecution, middleWellFormed,
              middleRepresented, bodyEffect⟩ :=
            bodySound _ conditionResult bodyResult represented wellFormed
          obtain ⟨final, restExecution, finalWellFormed, finalRepresented,
              restEffect⟩ := induction middleRepresented middleWellFormed
          exact ⟨final, by
            simpa only [toCoreStmt, Stateful.toCoreCompletion] using
              executesWhileContinueThen conditionSound.1 bodyExecution
                restExecution,
            finalWellFormed, finalRepresented,
            bodyEffect.trans_same restEffect⟩

/-! ## Whole-command simulation -/

def Simulates
    (program : Program) (layout : Layout arity)
    (localCell : Fin arity → CellId)
    (beforeWorld : ReadOnly.World) (beforeEnvironment : Env arity)
    (before : State) (command : Command Core.signature actions arity)
    (completion : Lanius.FunctionalView.Stateful.Completion)
    (afterWorld : ReadOnly.World) (afterEnvironment : Env arity)
    (adapter : ActionAdapter actions) (nextLocal : VarId) : Prop :=
  ∃ after writes,
    Executes program before (toCoreStmt adapter layout nextLocal command)
      (Stateful.toCoreCompletion completion) after ∧
    StateWellFormed after ∧
    Representation layout localCell afterWorld afterEnvironment after ∧
    ModifiesOnly writes before after

/-- The command simulator depends on expressions only through this framed
    transition.  Read-only terms leave the Core state unchanged; effectful
    call terms may move both the abstract world and Core state, but must
    preserve the complete slice/local representation. -/
structure ExpressionSoundness (program : Program)
    (evaluateOperation : OperationEvaluator) where
  term : ∀ {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId}
    {beforeWorld afterWorld : ReadOnly.World}
    {environment : Env arity} {before : State}
    {term : Term Core.signature arity} {value : Value},
    StateWellFormed before →
    Representation layout localCell beforeWorld environment before →
    Term.evaluate (termMachine evaluateOperation) beforeWorld environment
      term = .ok (value, afterWorld) →
    ∃ after writes,
      Evaluates program before (Core.toCoreExpr layout term) value after ∧
      StateWellFormed after ∧
      Representation layout localCell afterWorld environment after ∧
      ModifiesOnly writes before after

/-- Operation-level obligation from which framed expression soundness is
    derived.  A dialect supplies only primitive leaves (not term recursion or
    left-to-right argument composition). -/
structure OperationSoundness (program : Program)
    (evaluateOperation : OperationEvaluator) where
  operation : ∀ {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId}
    {argumentsWorld afterWorld : ReadOnly.World}
    {environment : Env arity} {before afterArguments : State}
    {operation : Operation} {arguments : List (Term Core.signature arity)}
    {values : List Value} {value : Value} {argumentWrites : CellSet},
    StateWellFormed afterArguments →
    Representation layout localCell argumentsWorld environment
      afterArguments →
    arguments.length = values.length →
    ArgumentsEvaluateTo program before (Core.toCoreExprs layout arguments)
      values afterArguments →
    ModifiesOnly argumentWrites before afterArguments →
    evaluateOperation argumentsWorld operation values =
      .ok (value, afterWorld) →
    ∃ after writes,
      Evaluates program before
        (Operation.toCoreExpr operation (Core.toCoreExprs layout arguments))
        value after ∧
      StateWellFormed after ∧
      Representation layout localCell afterWorld environment after ∧
      ModifiesOnly writes before after

mutual

  theorem termSoundnessOfOperations
      (operations : OperationSoundness program evaluateOperation)
      (wellFormed : StateWellFormed state)
      (represented : Representation layout localCell world environment state)
      (evaluated : Term.evaluate (termMachine evaluateOperation) world
        environment term = .ok (value, afterWorld)) :
      ∃ after writes,
        Evaluates program state (Core.toCoreExpr layout term) value after ∧
        StateWellFormed after ∧
        Representation layout localCell afterWorld environment after ∧
        ModifiesOnly writes state after := by
    cases term with
    | reference reference =>
        cases reference with
        | slot index =>
            simp only [Term.evaluate, Ref.evaluate, Core.toCoreExpr,
              Core.refToCoreExpr] at evaluated ⊢
            obtain ⟨rfl, rfl⟩ := evaluated
            exact ⟨state, CellSet.empty,
              ⟨1, evalLocal_of_local 0 program state _ _
                (represented.environmentMatches index)⟩,
              wellFormed, represented, ModifiesOnly.refl state⟩
        | literal literalValue =>
            simp only [Term.evaluate, Ref.evaluate, Core.toCoreExpr,
              Core.refToCoreExpr] at evaluated ⊢
            obtain ⟨rfl, rfl⟩ := evaluated
            exact ⟨state, CellSet.empty, ⟨1, rfl⟩, wellFormed,
              represented, ModifiesOnly.refl state⟩
    | apply operation arguments =>
        simp only [Term.evaluate] at evaluated
        cases argumentsResult : evaluateTerms (termMachine evaluateOperation)
            world environment arguments with
        | error reason =>
            rw [argumentsResult] at evaluated
            contradiction
        | ok result =>
            obtain ⟨values, argumentsWorld⟩ := result
            rw [argumentsResult] at evaluated
            change evaluateOperation argumentsWorld operation values =
              .ok (value, afterWorld) at evaluated
            obtain ⟨afterArguments, argumentWrites, argumentsExecution,
                argumentsWellFormed, argumentsRepresented, argumentsEffect⟩ :=
              termsSoundnessOfOperations operations wellFormed represented
                argumentsResult
            exact operations.operation argumentsWellFormed argumentsRepresented
              (Lanius.FunctionalView.Core.Effectful.evaluateTerms_length
                argumentsResult)
              argumentsExecution argumentsEffect evaluated
    | logicalAnd left right =>
        simp only [Term.evaluate] at evaluated
        cases leftResult : Term.evaluate (termMachine evaluateOperation) world
            environment left with
        | error reason =>
            simp only [leftResult, bind, Except.bind] at evaluated
            contradiction
        | ok result =>
            obtain ⟨leftValue, leftWorld⟩ := result
            simp only [leftResult, bind, Except.bind] at evaluated
            obtain ⟨afterLeft, leftWrites, leftExecution, leftWellFormed,
                leftRepresented, leftEffect⟩ :=
              termSoundnessOfOperations operations wellFormed represented
                leftResult
            cases leftValue with
            | boolean leftBoolean =>
                cases leftBoolean with
                | false =>
                    obtain ⟨rfl, rfl⟩ := evaluated
                    exact ⟨afterLeft, leftWrites,
                      evaluatesLogicalAndFalse leftExecution,
                      leftWellFormed, leftRepresented, leftEffect⟩
                | true =>
                    obtain ⟨after, rightWrites, rightExecution,
                        afterWellFormed, afterRepresented, rightEffect⟩ :=
                      termSoundnessOfOperations operations leftWellFormed
                        leftRepresented evaluated
                    exact ⟨after, CellSet.union leftWrites rightWrites,
                      evaluatesLogicalAndTrue leftExecution rightExecution,
                      afterWellFormed, afterRepresented,
                      leftEffect.trans rightEffect⟩
            | _ => contradiction
    | logicalOr left right =>
        simp only [Term.evaluate] at evaluated
        cases leftResult : Term.evaluate (termMachine evaluateOperation) world
            environment left with
        | error reason =>
            simp only [leftResult, bind, Except.bind] at evaluated
            contradiction
        | ok result =>
            obtain ⟨leftValue, leftWorld⟩ := result
            simp only [leftResult, bind, Except.bind] at evaluated
            obtain ⟨afterLeft, leftWrites, leftExecution, leftWellFormed,
                leftRepresented, leftEffect⟩ :=
              termSoundnessOfOperations operations wellFormed represented
                leftResult
            cases leftValue with
            | boolean leftBoolean =>
                cases leftBoolean with
                | false =>
                    obtain ⟨after, rightWrites, rightExecution,
                        afterWellFormed, afterRepresented, rightEffect⟩ :=
                      termSoundnessOfOperations operations leftWellFormed
                        leftRepresented evaluated
                    exact ⟨after, CellSet.union leftWrites rightWrites,
                      evaluatesLogicalOrFalse leftExecution rightExecution,
                      afterWellFormed, afterRepresented,
                      leftEffect.trans rightEffect⟩
                | true =>
                    obtain ⟨rfl, rfl⟩ := evaluated
                    exact ⟨afterLeft, leftWrites,
                      evaluatesLogicalOrTrue leftExecution,
                      leftWellFormed, leftRepresented, leftEffect⟩
            | _ => contradiction

  theorem termsSoundnessOfOperations
      (operations : OperationSoundness program evaluateOperation)
      (wellFormed : StateWellFormed state)
      (represented : Representation layout localCell world environment state)
      (evaluated : evaluateTerms (termMachine evaluateOperation) world
        environment terms = .ok (values, afterWorld)) :
      ∃ after writes,
        ArgumentsEvaluateTo program state (Core.toCoreExprs layout terms)
          values after ∧
        StateWellFormed after ∧
        Representation layout localCell afterWorld environment after ∧
        ModifiesOnly writes state after := by
    cases terms with
    | nil =>
        simp only [evaluateTerms, Core.toCoreExprs] at evaluated ⊢
        obtain ⟨rfl, rfl⟩ := evaluated
        exact ⟨state, CellSet.empty, ArgumentsEvaluateTo.nil program state,
          wellFormed, represented, ModifiesOnly.refl state⟩
    | cons head tail =>
        simp only [evaluateTerms] at evaluated
        cases headResult : Term.evaluate (termMachine evaluateOperation) world
            environment head with
        | error reason =>
            rw [headResult] at evaluated
            contradiction
        | ok result =>
            obtain ⟨headValue, headWorld⟩ := result
            rw [headResult] at evaluated
            simp only [bind, Except.bind] at evaluated
            cases tailResult : evaluateTerms (termMachine evaluateOperation)
                headWorld environment tail with
            | error reason =>
                rw [tailResult] at evaluated
                contradiction
            | ok result =>
                obtain ⟨tailValues, tailWorld⟩ := result
                rw [tailResult] at evaluated
                obtain ⟨rfl, rfl⟩ := evaluated
                obtain ⟨afterHead, headWrites, headExecution,
                    headWellFormed, headRepresented, headEffect⟩ :=
                  termSoundnessOfOperations operations wellFormed represented
                    headResult
                obtain ⟨after, tailWrites, tailExecution,
                    afterWellFormed, afterRepresented, tailEffect⟩ :=
                  termsSoundnessOfOperations operations headWellFormed
                    headRepresented tailResult
                exact ⟨after, CellSet.union headWrites tailWrites,
                  ArgumentsEvaluateTo.cons headExecution tailExecution,
                  afterWellFormed, afterRepresented,
                  headEffect.trans tailEffect⟩

end

def expressionSoundnessOfOperations
    (operations : OperationSoundness program evaluateOperation) :
    ExpressionSoundness program evaluateOperation where
  term := fun wellFormed represented evaluated =>
    termSoundnessOfOperations operations wellFormed represented evaluated

def readOnlyExpressionSoundness (program : Program) :
    ExpressionSoundness program (ReadOnly.evaluateOperation program) where
  term := by
    intro arity layout localCell beforeWorld afterWorld environment before
      term value wellFormed represented evaluated
    have readOnlyEvaluated : Term.evaluate (ReadOnly.machine program)
        beforeWorld environment term = .ok (value, afterWorld) := by
      simpa [termMachine, ReadOnly.machine] using evaluated
    have worldEq := ReadOnly.Term.evaluate_world_eq readOnlyEvaluated
    subst afterWorld
    have execution := Core.term_evaluates (ReadOnly.bridge program)
      (represented.worldRepresents wellFormed)
      represented.environmentMatches readOnlyEvaluated
    exact ⟨before, CellSet.empty, execution.1, wellFormed, represented,
      ModifiesOnly.refl before⟩

/-- The only dialect-specific obligation in whole-command simulation.  An
    action proves one separation-preserving Core transition; sequencing,
    lexical scope, branching, and loops are generic. -/
structure ActionSoundness (program : Program)
    (evaluateOperation : OperationEvaluator) where
  action : ∀ {arity : Nat} {layout : Layout arity}
    {localCell : Fin arity → CellId} {world : ReadOnly.World}
    {environment : Env arity} {state : State} {operation : Action arity}
    {afterWorld : ReadOnly.World} {nextLocal : VarId},
    StateWellFormed state →
    Representation layout localCell world environment state →
    (machineWith program evaluateOperation).evalAction world environment
      operation = .ok afterWorld →
    Simulates program layout localCell world environment state
      (.action operation) .next afterWorld environment actionAdapter nextLocal

def actionSoundness (program : Program) :
    ActionSoundness program (ReadOnly.evaluateOperation program) where
  action := by
    intro arity layout localCell world environment state operation afterWorld
      nextLocal wellFormed represented actionResult
    cases operation with
    | setI32Index base index value =>
        change evaluateActionWith (ReadOnly.evaluateOperation program) world
          environment (.setI32Index base index value) = .ok afterWorld
          at actionResult
        cases indexResult : Term.evaluate
            (termMachine (ReadOnly.evaluateOperation program)) world
            environment index with
        | error reason =>
            simp [evaluateActionWith, indexResult, bind, Except.bind]
              at actionResult
        | ok result =>
            obtain ⟨indexValue, indexWorld⟩ := result
            have indexResultReadOnly :
                Term.evaluate (ReadOnly.machine program) world environment
                  index = .ok (indexValue, indexWorld) := by
              simpa [termMachine, ReadOnly.machine] using indexResult
            have indexSound := Core.term_evaluates (ReadOnly.bridge program)
              (represented.worldRepresents wellFormed)
              represented.environmentMatches indexResultReadOnly
            have indexExecution := indexSound.1
            have indexWorldEq :=
              ReadOnly.Term.evaluate_world_eq indexResultReadOnly
            subst indexWorld
            simp only [evaluateActionWith, indexResult, bind, Except.bind]
              at actionResult
            clear indexSound indexResult indexResultReadOnly
            cases valueResult : Term.evaluate
                (termMachine (ReadOnly.evaluateOperation program)) world
                environment value with
            | error reason =>
                simp [valueResult, bind, Except.bind]
                  at actionResult
            | ok result =>
                obtain ⟨replacementValue, valueWorld⟩ := result
                have valueResultReadOnly :
                    Term.evaluate (ReadOnly.machine program) world environment
                      value = .ok (replacementValue, valueWorld) := by
                  simpa [termMachine, ReadOnly.machine] using valueResult
                have valueSound := Core.term_evaluates (ReadOnly.bridge program)
                  (represented.worldRepresents wellFormed)
                  represented.environmentMatches valueResultReadOnly
                have valueExecution := valueSound.1
                have valueWorldEq :=
                  ReadOnly.Term.evaluate_world_eq valueResultReadOnly
                subst valueWorld
                simp only [valueResult, bind, Except.bind] at actionResult
                clear valueSound valueResult valueResultReadOnly
                obtain ⟨cell, values, position, replacement, baseValue,
                  indexValueEq, replacementValueEq, found, inBounds,
                  afterWorldEq⟩ := writeI32Slice_result actionResult
                subst indexValue
                subst replacementValue
                subst afterWorld
                have baseLocal : state.local? (layout base) = some
                    (.slice (.scalar (.signed .i32)) cell [] 0 values.length) := by
                  rw [represented.environmentMatches base, baseValue]
                obtain ⟨after, execution, afterWellFormed,
                  afterRepresented, effect⟩ :=
                  represented.setI32IndexCore wellFormed baseLocal
                    indexExecution valueExecution found inBounds
                exact ⟨after, CellSet.singleton cell, execution,
                  afterWellFormed, afterRepresented, effect⟩

theorem command_executes
    {arity : Nat} {program : Program}
    {evaluateOperation : OperationEvaluator}
    {world afterWorld : ReadOnly.World}
    {environment afterEnvironment : Env arity}
    {command : Command Core.signature actions arity}
    {completion : Lanius.FunctionalView.Stateful.Completion}
    (expressionSoundness : ExpressionSoundness program evaluateOperation)
    (soundness : ActionSoundness program evaluateOperation)
    (evaluated : Command.Evaluates (termMachine evaluateOperation)
      (machineWith program evaluateOperation) world environment command
      completion afterWorld afterEnvironment) :
    ∀ {layout : Layout arity} {state : State}
      {localCell : Fin arity → CellId}
      {nextLocal : VarId},
      Representation layout localCell world environment state →
      LayoutBelow layout nextLocal →
      StateWellFormed state →
      Simulates program layout localCell world environment state command
        completion afterWorld afterEnvironment actionAdapter nextLocal := by
  let motive : {arity : Nat} →
      (world : ReadOnly.World) → (environment : Env arity) →
      (command : Command Core.signature actions arity) →
      (completion : Lanius.FunctionalView.Stateful.Completion) →
      (afterWorld : ReadOnly.World) → (afterEnvironment : Env arity) →
      Command.Evaluates (termMachine evaluateOperation)
        (machineWith program evaluateOperation) world environment command
        completion afterWorld afterEnvironment → Prop :=
    fun {arity} (world : ReadOnly.World)
      (environment : Env arity)
      (command : Command Core.signature actions arity)
      (completion : Lanius.FunctionalView.Stateful.Completion)
      (afterWorld : ReadOnly.World) (afterEnvironment : Env arity) _ =>
        ∀ {layout : Layout arity} {state : State}
          {localCell : Fin arity → CellId} {nextLocal : VarId},
          Representation layout localCell world environment state →
          LayoutBelow layout nextLocal →
          StateWellFormed state →
          Simulates program layout localCell world environment state command
            completion afterWorld afterEnvironment actionAdapter nextLocal
  change motive world environment command completion afterWorld
    afterEnvironment evaluated
  apply @Command.Evaluates.rec Core.signature actions
    (termMachine evaluateOperation) (machineWith program evaluateOperation)
    motive
  case skip =>
      intro _world _arity _environment layout state localCell nextLocal represented
        below wellFormed
      exact ⟨state, CellSet.empty, executesSkip program state, wellFormed,
        represented, ModifiesOnly.refl state⟩
  case sequenceNext =>
      intro _beforeWorld _arity _beforeEnvironment firstCommand _middleWorld
        _middleEnvironment _secondCommand _completion _afterWorld
        _afterEnvironment _firstResult _secondResult firstInduction
        secondInduction layout state localCell nextLocal represented below wellFormed
      obtain ⟨middle, firstWrites, firstExecution, middleWellFormed,
        middleRepresented, firstEffect⟩ :=
        firstInduction represented below wellFormed
      have secondBelow := below.mono
        (Nat.le_add_right nextLocal (localCapacity actionAdapter firstCommand))
      obtain ⟨after, secondWrites, secondExecution, afterWellFormed,
        afterRepresented, secondEffect⟩ :=
        secondInduction middleRepresented secondBelow middleWellFormed
      exact ⟨after, CellSet.union firstWrites secondWrites,
        executesSequence firstExecution secondExecution, afterWellFormed,
        afterRepresented, firstEffect.trans secondEffect⟩
  case sequenceStop =>
      intro _beforeWorld _arity _beforeEnvironment _firstCommand completion
        _afterWorld _afterEnvironment _secondCommand _firstResult stops
        firstInduction layout state localCell nextLocal represented below wellFormed
      obtain ⟨after, writes, execution, afterWellFormed, afterRepresented,
        effect⟩ := firstInduction represented below wellFormed
      exact ⟨after, writes, executesSequenceNonNext execution (by
        intro same
        apply stops
        cases completion <;> simp_all [Stateful.toCoreCompletion]),
        afterWellFormed, afterRepresented, effect⟩
  case letValue =>
      intro beforeWorld branchArity beforeEnvironment _initializer value
        initializedWorld _body _completion afterWorld extendedEnvironment
        _type initializerResult _bodyResult induction layout state localCell nextLocal
        represented below wellFormed
      obtain ⟨initialized, initializerWrites, initializerExecution,
          initializedWellFormed, initializedRepresented, initializerEffect⟩ :=
        expressionSoundness.term wellFormed represented initializerResult
      let bound := initialized.bindLocal nextLocal value
      let boundCells := pushCells localCell initialized.nextCell
      have boundWellFormed := bindLocal_preserves_well_formed initialized
        nextLocal value initializedWellFormed
      have boundRepresented : Representation (Layout.push layout nextLocal)
          boundCells initializedWorld (beforeEnvironment.push value) bound := by
        simpa [bound, boundCells] using
          initializedRepresented.bindLocal below initializedWellFormed value
      obtain ⟨completed, bodyWrites, bodyExecution, completedWellFormed,
        completedRepresented, bodyEffect⟩ :=
        induction boundRepresented below.push boundWellFormed
      let after := restoreLocals initialized completed
      have scopeEffect : ModifiesOnly bodyWrites initialized after := by
        exact temporaryLocal_effect nextLocal value bodyEffect.toStoreEffect
      have afterWellFormed : StateWellFormed after := by
        have entered : StoreEffect bodyWrites initialized bound :=
          (bindLocal_effect initialized nextLocal value).weaken
            CellSet.empty_subset
        simpa [after] using
          (entered.trans_same bodyEffect.toStoreEffect).restoreLocals_wellFormed
            initializedWellFormed completedWellFormed
      have afterRepresented : Representation layout localCell afterWorld
          (Env.pop extendedEnvironment) after := by
        refine {
          worldOwned := ?_
          localOwned := ?_
          localCellsInjective := initializedRepresented.localCellsInjective
          worldLocalsDisjoint := ?_
        }
        · intro cell values found
          simpa [after, restoreLocals, State.cellEntry?] using
            completedRepresented.worldOwned cell values found
        · intro index
          let lifted : Fin (branchArity + 1) :=
            ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩
          have owned := completedRepresented.localOwned lifted
          constructor
          · simpa [after, restoreLocals, State.cellId?] using
              (initializedRepresented.localOwned index).1
          · simpa [after, restoreLocals, State.cellEntry?, boundCells,
              pushCells, lifted, Env.pop] using owned.2
        · intro cell worldMember localMember
          exact completedRepresented.worldLocalsDisjoint cell worldMember (by
            obtain ⟨index, same⟩ := localMember
            let lifted : Fin (branchArity + 1) :=
              ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩
            exact ⟨lifted, by simpa [boundCells, pushCells, lifted] using same⟩)
      exact ⟨after, CellSet.union initializerWrites bodyWrites,
        executesLetLocal initializerExecution bodyExecution, afterWellFormed,
        afterRepresented, initializerEffect.trans scopeEffect⟩
  case setLocal =>
      intro _beforeWorld _arity _beforeEnvironment _value _result _afterWorld
        target valueResult layout state localCell nextLocal represented below wellFormed
      obtain ⟨afterRight, rightWrites, rightExecution, rightWellFormed,
          rightRepresented, rightEffect⟩ :=
        expressionSoundness.term wellFormed represented valueResult
      obtain ⟨after, execution, afterWellFormed, afterRepresented, effect⟩ :=
        represented.setLocalAfterTerm rightRepresented rightExecution
          rightWellFormed rightEffect
      exact ⟨after,
        CellSet.union rightWrites (CellSet.singleton (localCell target)),
        executesExpression execution, afterWellFormed, afterRepresented, effect⟩
  case updateLocal =>
      intro _beforeWorld _arity _beforeEnvironment _value _right _afterWorld
        operation target _result valueResult updateResult layout state localCell
        nextLocal represented below wellFormed
      obtain ⟨afterRight, rightWrites, rightExecution, rightWellFormed,
          rightRepresented, rightEffect⟩ :=
        expressionSoundness.term wellFormed represented valueResult
      obtain ⟨after, execution, afterWellFormed, afterRepresented, effect⟩ :=
        represented.updateLocalAfterTerm rightRepresented rightExecution
          rightWellFormed rightEffect updateResult
      exact ⟨after,
        CellSet.union rightWrites (CellSet.singleton (localCell target)),
        executesExpression execution, afterWellFormed, afterRepresented, effect⟩
  case action =>
      intro _beforeWorld _arity _beforeEnvironment _operation _afterWorld
        actionResult layout state localCell nextLocal represented below wellFormed
      exact soundness.action wellFormed represented actionResult
  case ifTrue =>
      intro _beforeWorld _arity _beforeEnvironment _condition _conditionWorld
        _thenBranch _completion _afterWorld _afterEnvironment _elseBranch
        conditionResult _branchResult induction layout state localCell nextLocal
        represented below wellFormed
      obtain ⟨conditionState, conditionWrites, conditionExecution,
          conditionWellFormed, conditionRepresented, conditionEffect⟩ :=
        expressionSoundness.term wellFormed represented conditionResult
      obtain ⟨after, branchWrites, branchExecution, afterWellFormed,
          afterRepresented, branchEffect⟩ :=
        induction conditionRepresented below conditionWellFormed
      exact ⟨after, CellSet.union conditionWrites branchWrites,
        executesIfTrue conditionExecution branchExecution,
        afterWellFormed, afterRepresented,
        conditionEffect.trans branchEffect⟩
  case ifFalse =>
      intro _beforeWorld _arity _beforeEnvironment _condition _conditionWorld
        _elseBranch _completion _afterWorld _afterEnvironment _thenBranch
        conditionResult _branchResult induction layout state localCell nextLocal
        represented below wellFormed
      obtain ⟨conditionState, conditionWrites, conditionExecution,
          conditionWellFormed, conditionRepresented, conditionEffect⟩ :=
        expressionSoundness.term wellFormed represented conditionResult
      obtain ⟨after, branchWrites, branchExecution, afterWellFormed,
          afterRepresented, branchEffect⟩ :=
        induction conditionRepresented below conditionWellFormed
      exact ⟨after, CellSet.union conditionWrites branchWrites,
        executesIfFalse conditionExecution branchExecution,
        afterWellFormed, afterRepresented,
        conditionEffect.trans branchEffect⟩
  case whileFalse =>
      intro _beforeWorld _arity _beforeEnvironment _condition _afterWorld _body
        conditionResult layout state localCell nextLocal represented below wellFormed
      obtain ⟨after, writes, conditionExecution, afterWellFormed,
          afterRepresented, effect⟩ :=
        expressionSoundness.term wellFormed represented conditionResult
      exact ⟨after, writes, executesWhileFalse conditionExecution,
        afterWellFormed, afterRepresented, effect⟩
  case whileNext =>
      intro _beforeWorld _arity _beforeEnvironment _condition _conditionWorld
        _body _bodyWorld _bodyEnvironment _completion _afterWorld
        _afterEnvironment conditionResult _bodyResult _restResult bodyInduction
        restInduction layout state localCell nextLocal represented below wellFormed
      obtain ⟨conditionState, conditionWrites, conditionExecution,
          conditionWellFormed, conditionRepresented, conditionEffect⟩ :=
        expressionSoundness.term wellFormed represented conditionResult
      obtain ⟨middle, bodyWrites, bodyExecution, middleWellFormed,
          middleRepresented, bodyEffect⟩ :=
        bodyInduction conditionRepresented below conditionWellFormed
      obtain ⟨after, restWrites, restExecution, afterWellFormed,
        afterRepresented, restEffect⟩ :=
        restInduction middleRepresented below middleWellFormed
      exact ⟨after, CellSet.union conditionWrites
          (CellSet.union bodyWrites restWrites),
        executesWhileTrueThen conditionExecution bodyExecution restExecution,
        afterWellFormed, afterRepresented,
        conditionEffect.trans (bodyEffect.trans restEffect)⟩
  case whileContinue =>
      intro _beforeWorld _arity _beforeEnvironment _condition _conditionWorld
        _body _bodyWorld _bodyEnvironment _completion _afterWorld
        _afterEnvironment conditionResult _bodyResult _restResult bodyInduction
        restInduction layout state localCell nextLocal represented below wellFormed
      obtain ⟨conditionState, conditionWrites, conditionExecution,
          conditionWellFormed, conditionRepresented, conditionEffect⟩ :=
        expressionSoundness.term wellFormed represented conditionResult
      obtain ⟨middle, bodyWrites, bodyExecution, middleWellFormed,
          middleRepresented, bodyEffect⟩ :=
        bodyInduction conditionRepresented below conditionWellFormed
      obtain ⟨after, restWrites, restExecution, afterWellFormed,
        afterRepresented, restEffect⟩ :=
        restInduction middleRepresented below middleWellFormed
      exact ⟨after, CellSet.union conditionWrites
          (CellSet.union bodyWrites restWrites),
        executesWhileContinueThen conditionExecution bodyExecution restExecution,
        afterWellFormed, afterRepresented,
        conditionEffect.trans (bodyEffect.trans restEffect)⟩
  case whileBreak =>
      intro _beforeWorld _arity _beforeEnvironment _condition _conditionWorld
        _body _afterWorld _afterEnvironment conditionResult _bodyResult induction
        layout state localCell nextLocal represented below wellFormed
      obtain ⟨conditionState, conditionWrites, conditionExecution,
          conditionWellFormed, conditionRepresented, conditionEffect⟩ :=
        expressionSoundness.term wellFormed represented conditionResult
      obtain ⟨after, bodyWrites, bodyExecution, afterWellFormed,
          afterRepresented, bodyEffect⟩ :=
        induction conditionRepresented below conditionWellFormed
      exact ⟨after, CellSet.union conditionWrites bodyWrites,
        executesWhileBreak conditionExecution bodyExecution,
        afterWellFormed, afterRepresented,
        conditionEffect.trans bodyEffect⟩
  case whileReturn =>
      intro _beforeWorld _arity _beforeEnvironment _condition _conditionWorld
        _body _value _afterWorld _afterEnvironment conditionResult _bodyResult
        induction layout state localCell nextLocal represented below wellFormed
      obtain ⟨conditionState, conditionWrites, conditionExecution,
          conditionWellFormed, conditionRepresented, conditionEffect⟩ :=
        expressionSoundness.term wellFormed represented conditionResult
      obtain ⟨after, bodyWrites, bodyExecution, afterWellFormed,
          afterRepresented, bodyEffect⟩ :=
        induction conditionRepresented below conditionWellFormed
      exact ⟨after, CellSet.union conditionWrites bodyWrites,
        executesWhileReturned conditionExecution bodyExecution,
        afterWellFormed, afterRepresented,
        conditionEffect.trans bodyEffect⟩
  case returnNone =>
      intro _world _arity _environment layout state localCell nextLocal represented
        below wellFormed
      exact ⟨state, CellSet.empty, executesReturnNone program state,
        wellFormed, represented, ModifiesOnly.refl state⟩
  case returnSome =>
      intro _beforeWorld _arity _beforeEnvironment _value _result _afterWorld
        valueResult layout state localCell nextLocal represented below wellFormed
      obtain ⟨after, writes, valueExecution, afterWellFormed,
          afterRepresented, effect⟩ :=
        expressionSoundness.term wellFormed represented valueResult
      exact ⟨after, writes, executesReturnValue valueExecution,
        afterWellFormed, afterRepresented, effect⟩
  case breakLoop =>
      intro _world _arity _environment layout state localCell nextLocal represented
        below wellFormed
      exact ⟨state, CellSet.empty, executesBreak program state, wellFormed,
        represented, ModifiesOnly.refl state⟩
  case continueLoop =>
      intro _world _arity _environment layout state localCell nextLocal represented
        below wellFormed
      exact ⟨state, CellSet.empty, executesContinue program state, wellFormed,
        represented, ModifiesOnly.refl state⟩
  case t =>
      exact evaluated

end Lanius.FunctionalView.Core.Stateful
