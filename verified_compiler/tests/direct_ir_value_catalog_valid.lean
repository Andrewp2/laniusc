import verified_compiler.tests.direct_ir_value_catalog_valid_inputs
import verified_compiler.tests.direct_ir_owned_queries_allocation
import verified_compiler.tests.direct_ir_owned_queries_fields
import verified_compiler.tests.direct_ir_owned_queries_rows
import Lanius.Semantics.LoopRun
import Lanius.Semantics.LocalPair.Scope

namespace IRValueCatalogValid

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyOwnedInputs

def source := Extracted.«lowering::value_catalog».Functions.«valid_slice».core
private def whole := Extracted.«lowering::value_catalog».Functions.«valid».core
private def loop := source.whileLoop 0
private def rowId := source.bindingId 0
private def finishId := source.bindingId 1
private def bindingId := source.bindingId 2
private def tokenId := source.bindingId 3
private def allocationId := source.bindingId 6
private def basicGuard : Stmt := match source.bindingStatement 3 with
  | .letLocal _ _ _ (.sequence statement _) => statement | _ => .skip
private def ordering : Stmt := match source.bindingStatement 3 with
  | .letLocal _ _ _ (.sequence _ (.sequence statement _)) => statement | _ => .skip
private def allocationInitializer := source.bindingInitializer 6
private def allocationGuard : Stmt := match source.bindingStatement 6 with
  | .letLocal _ _ _ (.sequence statement _) => statement | _ => .skip
private def advance : Stmt := match source.bindingStatement 6 with
  | .letLocal _ _ _ (.sequence _ rest) => rest | _ => .skip
private def descriptorGuard : Stmt := match source.body with
  | some (.sequence statement _) => statement | _ => .skip

/-- Original reached binding/index representation and independent slot safety.
    No allocation-table borrowing or successful validator run is required. -/
structure OriginalSlice (values : Values) (index : Index)
    (offset count tokenCount : Int) (heap : Heap) where
  bindings : guardValid values offset count tokenCount index = true →
    ∀ position, offset.toNat ≤ position → position < offset.toNat + count.toNat →
      NativeBinding values heap position
  entries : guardValid values offset count tokenCount index = true →
    ∀ position, offset.toNat ≤ position → position < offset.toNat + count.toNat →
      basicValid tokenCount (values.binding position) = true →
      (if offset.toNat < position then
        adjacentValid (values.binding (position - 1)) (values.binding position) else true) = true →
      index.lookupGuard (targetId (values.binding position).target) →
      NativeIndexEntry index heap (targetId (values.binding position).target).toNat
  safeRows : guardValid values offset count tokenCount index = true →
    ∀ position, offset.toNat ≤ position → position < offset.toNat + count.toNat →
    basicValid tokenCount (values.binding position) = true →
    (if offset.toNat < position then
      adjacentValid (values.binding (position - 1)) (values.binding position) else true) = true →
    0 ≤ index.targetRow (values.binding position).target →
      (index.targetRow (values.binding position).target).toNat < index.table.count.toInt.toNat

/-- Exactly the original binding spans represented at the guarded slice seam. -/
def OriginalSlice.bindingBytes (original : OriginalSlice values index offset count tokenCount heap)
    (address : Address) : Prop :=
  ∃ guarded position lower upper,
    (original.bindings guarded position lower upper).base ≤ address ∧
      address < (original.bindings guarded position lower upper).base + 48

/-- Index spans are included only where the source reaches a guarded lookup. -/
def OriginalSlice.indexBytes (original : OriginalSlice values index offset count tokenCount heap)
    (address : Address) : Prop :=
  ∃ guarded position lower upper basic ordered inside,
    (original.entries guarded position lower upper basic ordered inside).base ≤ address ∧
      address < (original.entries guarded position lower upper basic ordered inside).base + 16

def OriginalSlice.bytes (original : OriginalSlice values index offset count tokenCount heap)
    (address : Address) : Prop := original.bindingBytes address ∨ original.indexBytes address

theorem OriginalSlice.bindingSpan (original : OriginalSlice values index offset count tokenCount heap)
    (guarded) (position) (lower) (upper) (relative : Nat) (inside : relative < 48) :
    original.bytes ((original.bindings guarded position lower upper).base + relative) := by
  apply Or.inl
  exact ⟨guarded, position, lower, upper, Nat.le_add_right _ _, Nat.add_lt_add_left inside _⟩

theorem OriginalSlice.indexSpan (original : OriginalSlice values index offset count tokenCount heap)
    (guarded) (position) (lower) (upper) (basic) (ordered) (lookup)
    (relative : Nat) (inside : relative < 16) :
    original.bytes ((original.entries guarded position lower upper basic ordered lookup).base + relative) := by
  apply Or.inr
  exact ⟨guarded, position, lower, upper, basic, ordered, lookup,
    Nat.le_add_right _ _, Nat.add_lt_add_left inside _⟩

/-- Internal post-header seam: attach the SAME actually borrowed table view to
    the original represented bindings/index. Invalid semantic rows remain. -/
structure NativeSlice (values : Values) (index : Index) (rows : Nat → AllocationRow)
    (offset count tokenCount : Int) (heap : Heap) extends
    OriginalSlice values index offset count tokenCount heap where
  table : guardValid values offset count tokenCount index = true → BorrowedTable index.table heap
  locations : ∀ guarded, RowLocations (table guarded).toNormalTable
  rowIdentity : ∀ guarded position inside,
    ((table guarded).rows position inside).row = rows position

/-- Header borrowing preserves original bytes. Geometry and ownership come
    from the actual shared header effect, not an initially-borrowed premise. -/
def NativeSlice.ofReads (original : OriginalSlice values index offset count tokenCount origin)
    (reads : HeapReads origin heap)
    (table : guardValid values offset count tokenCount index = true → BorrowedTable index.table heap)
    (locations : ∀ guarded, RowLocations (table guarded).toNormalTable)
    (rowIdentity : ∀ guarded position inside, ((table guarded).rows position inside).row = rows position) :
    NativeSlice values index rows offset count tokenCount heap := {
  table, locations, rowIdentity
  bindings := fun guarded position lower upper =>
    let native := original.bindings guarded position lower upper
    { native with snapshot := native.snapshot.afterHeapReads reads }
  entries := fun guarded position lower upper basic ordered inside =>
    let native := original.entries guarded position lower upper basic ordered inside
    { native with snapshot := native.snapshot.afterHeapReads reads }
  safeRows := original.safeRows }

private def basicCondition : Expr := match basicGuard with
  | .ifThenElse condition _ _ => condition | _ => .value (.boolean false)
private def basicRejection (tokenCount : Int) (binding : Binding) : Bool :=
  ((decide (binding.token.toInt ≤ -1) || decide (tokenCount ≤ binding.token.toInt)) ||
    !targetValid binding.target) || (!scopeLocal binding.scope && !scopeImported binding.scope)

/-- The one actual basic-guard boundary, including all invalid binding cases.
    Its short-circuit calls may allocate fresh cells but cannot change input bytes. -/
private theorem actualBasicGuard (binding : Binding) (tokenCount : Int)
    (bindingFound : before.local? bindingId = some binding.value)
    (tokenFound : before.local? tokenId = some (.signed .i32 binding.token.toInt))
    (tokensFound : before.local? (source.argumentId 3) = some (.signed .i32 tokenCount))
    (formed : before.CellsWellFormed) :
    ∃ after, RunsStmt extractedProgram before basicGuard
      (if basicValid tokenCount binding then .next else .returned (some (.boolean false))) after ∧
      PureFrame before after := by
  have targetCheck {state : State} (formed : state.CellsWellFormed) := actualTargetValid binding.target formed
  have localScope {state : State} (formed : state.CellsWellFormed) := actualScope binding .LocalBinding formed
  have importedScope {state : State} (formed : state.CellsWellFormed) := actualScope binding .ImportedBinding formed
  simp only [sameScope_local, sameScope_imported] at localScope importedScope
  have negative : decide (binding.token.toInt ≤ -1) = !decide (0 ≤ binding.token.toInt) := by
    rw [← decide_not]
    congr 1
    apply propext
    omega
  have past : decide (tokenCount ≤ binding.token.toInt) = !decide (binding.token.toInt < tokenCount) := by
    rw [← decide_not]
    congr 1
    apply propext
    omega
  have rejection : basicRejection tokenCount binding = !basicValid tokenCount binding := by
    simp only [basicRejection, basicValid, negative, past, Bool.not_and, Bool.not_or]
  have condition : ∃ after, RunsExpr extractedProgram before basicCondition
      (.boolean (!basicValid tokenCount binding)) after ∧ PureFrame before after := by
    apply RunsExpr.booleanPure (actual := basicRejection tokenCount binding) _ rejection
    dsimp only [basicCondition, basicGuard, basicRejection]
    apply RunsExpr.logicalOrPure
      (a := (decide (binding.token.toInt ≤ -1) || decide (tokenCount ≤ binding.token.toInt)) ||
        !targetValid binding.target)
      (b := !scopeLocal binding.scope && !scopeImported binding.scope)
    · apply RunsExpr.logicalOrPure
        (a := decide (binding.token.toInt ≤ -1) || decide (tokenCount ≤ binding.token.toInt))
        (b := !targetValid binding.target)
      · apply RunsExpr.logicalOrPure (a := decide (binding.token.toInt ≤ -1))
          (b := decide (tokenCount ≤ binding.token.toInt))
        · core_pure_expr
        · intro middle frame
          core_pure_expr
      · intro middle frame
        core_pure_expr
    · intro middle frame
      apply RunsExpr.logicalAndPure (a := !scopeLocal binding.scope) (b := !scopeImported binding.scope)
      · core_pure_expr
      · intro final frame
        core_pure_expr
  dsimp only [basicGuard]
  apply RunsStmt.branchFramedPure (!basicValid tokenCount binding)
  · exact condition
  · intro middle frame
    cases valid : basicValid tokenCount binding <;> simp only [valid, Bool.not_false, Bool.not_true, ↓reduceIte] <;>
      core_pure

/-- The descriptor guard is scalar and state-identical. Its subtraction is
    evaluated only after the source's preceding nonnegative/in-range checks. -/
private theorem actualDescriptorGuard (values : Values) (index : Index)
    (offset count tokenCount : Int32)
    (valuesFound : before.local? (source.argumentId 0) = some values.value)
    (offsetFound : before.local? (source.argumentId 1) = some (.signed .i32 offset.toInt))
    (countFound : before.local? (source.argumentId 2) = some (.signed .i32 count.toInt))
    (tokensFound : before.local? (source.argumentId 3) = some (.signed .i32 tokenCount.toInt))
    (indexFound : before.local? (source.argumentId 4) = some index.value) :
    RunsStmt extractedProgram before descriptorGuard
      (if guardValid values offset.toInt count.toInt tokenCount.toInt index
        then .next else .returned (some (.boolean false))) before := by
  have difference (valuesNonnegative : 0 ≤ values.count.toInt) (offsetNonnegative : 0 ≤ offset.toInt)
      (within : offset.toInt ≤ values.count.toInt) :
      evalBinaryValue extractedProgram.target .subtract (.signed .i32 values.count.toInt)
        (.signed .i32 offset.toInt) = .ok (.signed .i32 (values.count.toInt - offset.toInt)) := by
    have valuesCast := Int.toNat_of_nonneg valuesNonnegative
    have offsetCast := Int.toNat_of_nonneg offsetNonnegative
    simpa only [Int.natCast_sub (show offset.toInt.toNat ≤ values.count.toInt.toNat by omega),
      valuesCast, offsetCast] using eval_i32_subNat extractedProgram.target
        values.count.toInt.toNat offset.toInt.toNat (by omega)
        (by have limit := values.count.toInt_lt; omega)
  by_cases guarded : guardValid values offset.toInt count.toInt tokenCount.toInt index = true
  · rcases guardValid_bounds guarded with
      ⟨valuesOkay, offsetOkay, countOkay, within, countFits, tokensOkay, flag⟩
    have subtraction := difference valuesOkay offsetOkay within
    simp only [guarded, ite_true]
    dsimp only [descriptorGuard]
    apply RunsStmt.ifThenElseFalse
    · core_run
    · exact RunsStmt.skip _ _
  · have rejected := Bool.eq_false_iff.mpr guarded
    simp only [rejected, Bool.false_eq_true, ite_false]
    dsimp only [descriptorGuard]
    apply RunsStmt.ifThenElseTrue
    · by_cases valuesOkay : 0 ≤ values.count.toInt
      · by_cases offsetOkay : 0 ≤ offset.toInt
        · by_cases countOkay : 0 ≤ count.toInt
          · by_cases within : offset.toInt ≤ values.count.toInt
            · have subtraction := difference valuesOkay offsetOkay within
              by_cases countFits : count.toInt ≤ values.count.toInt - offset.toInt
              · by_cases tokensOkay : 0 ≤ tokenCount.toInt
                · have flag : index.valid = false := by
                    apply Bool.eq_false_iff.mpr
                    intro accepted
                    apply guarded
                    simp only [guardValid, decide_eq_true valuesOkay, decide_eq_true offsetOkay,
                      decide_eq_true countOkay, decide_eq_true within, decide_eq_true countFits,
                      decide_eq_true tokensOkay, accepted, Bool.true_and]
                  core_run
                · core_run
              · core_run
            · core_run
          · core_run
        · core_run
      · core_run
    · exact RunsStmt.returnValue (RunsExpr.ofStable StableExpr.value rfl)

@[core_pure_rule] private theorem actualTargetMatches (target : Target) (row : AllocationRow)
    (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::value_catalog».Functions.«target_matches_allocation».core.id
        [.value (targetValue target), .value row.value])
      (.boolean (targetMatches target row)) after ∧ PureFrame before after := by
  cases target with
  | InvalidTarget =>
      dsimp only [targetValue, targetMatches]
      core_call_pure Extracted.«lowering::value_catalog».Functions.«target_matches_allocation».core as callee
      core_pure
  | Callable id =>
      have rowId {state : State} (formed : state.CellsWellFormed) := actualRowCoreId row formed
      have functionKind {state : State} (formed : state.CellsWellFormed) :=
        actualRowHasKind row .Function formed
      have externalKind {state : State} (formed : state.CellsWellFormed) :=
        actualRowHasKind row .External formed
      have kinds : (kindSame row.source.kind .Function || kindSame row.source.kind .External) =
          callableKind row.source.kind := by cases row.source.kind <;> rfl
      dsimp only [targetValue, targetMatches]
      rw [← kinds]
      core_call_pure Extracted.«lowering::value_catalog».Functions.«target_matches_allocation».core as callee
      core_pure
  | Variant value =>
      cases value
      have rowId {state : State} (formed : state.CellsWellFormed) := actualRowDeclarationId row formed
      have enumKind {state : State} (formed : state.CellsWellFormed) :=
        actualRowHasKind row .Enumeration formed
      have kinds : kindSame row.source.kind .Enumeration = enumerationKind row.source.kind := by
        cases row.source.kind <;> rfl
      dsimp only [targetValue, targetMatches]
      rw [← kinds]
      core_call_pure Extracted.«lowering::value_catalog».Functions.«target_matches_allocation».core as callee
      core_pure

private theorem actualAllocationLookup (native : NativeSlice values index rows offset count tokenCount heap)
    (guarded : guardValid values offset count tokenCount index = true)
    (position : Nat) (lower : offset.toNat ≤ position) (upper : position < offset.toNat + count.toNat)
    (basic : basicValid tokenCount (values.binding position) = true)
    (ordered : (if offset.toNat < position then
      adjacentValid (values.binding (position - 1)) (values.binding position) else true) = true)
    (same : before.heap = heap) (formed : before.CellsWellFormed)
    (bindingFound : before.local? bindingId = some (values.binding position).value)
    (indexFound : before.local? (source.argumentId 4) = some index.value) :
    ∃ after, RunsExpr extractedProgram before allocationInitializer
      (.signed .i32 (index.targetRow (values.binding position).target)) after ∧ PureFrame before after := by
  cases target : (values.binding position).target with
  | InvalidTarget =>
      simp only [basicValid, target, targetValid, Bool.and_false, Bool.false_and] at basic
      cases basic
  | Callable id =>
      simp only [Binding.value, target] at bindingFound
      have query {state : State} (same : state.heap = heap) (formed : state.CellsWellFormed) :=
        actualCoreRow index id.toInt (fun inside => by
          simpa only [target, targetId] using native.entries guarded position lower upper basic ordered
            (by simpa only [target, targetId] using inside)) same formed
      dsimp only [Index.targetRow]
      core_pure_expr
  | Variant value =>
      cases value with
      | mk id ordinal fields =>
          simp only [Binding.value, target] at bindingFound
          have query {state : State} (same : state.heap = heap) (formed : state.CellsWellFormed) :=
            actualDeclarationRow index id.toInt (fun inside => by
              simpa only [target, targetId] using native.entries guarded position lower upper basic ordered
                (by simpa only [target, targetId] using inside)) same formed
          dsimp only [Index.targetRow]
          core_pure_expr

@[core_pure_rule] private theorem actualSelectedRow
    (native : NativeSlice values index rows offset count tokenCount heap)
    (guarded : guardValid values offset count tokenCount index = true)
    (position : Nat) (lower : offset.toNat ≤ position) (upper : position < offset.toNat + count.toNat)
    (basic : basicValid tokenCount (values.binding position) = true)
    (ordered : (if offset.toNat < position then
      adjacentValid (values.binding (position - 1)) (values.binding position) else true) = true)
    (nonnegative : 0 ≤ index.targetRow (values.binding position).target)
    (same : before.heap = heap) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::allocation».Functions.«table_row».core.id
        [.value index.table.value, .value (.signed .i32 (index.targetRow (values.binding position).target))])
      (rows (index.targetRow (values.binding position).target).toNat).value after ∧ PureFrame before after := by
  subst heap
  let slot := (index.targetRow (values.binding position).target).toNat
  have inside := native.safeRows guarded position lower upper basic ordered nonnegative
  have countEq : index.table.count.toInt.toNat = (native.table guarded).count := by
    rw [(native.table guarded).countEq]
    simp only [Int.toNat_natCast]
  rw [countEq] at inside
  have cast : (slot : Int) = index.targetRow (values.binding position).target := Int.toNat_of_nonneg nonnegative
  obtain ⟨after, run, frame⟩ := actualRow (native.table guarded) (native.locations guarded) inside formed
  dsimp only [slot] at cast
  rw [cast, native.rowIdentity guarded _ inside] at run
  exact ⟨after, run, frame⟩

/-- Source checks before lookup are read-only, including the previous-row
    query. This keeps the ordinary lexical scopes out of the loop argument. -/
private theorem actualOrdering (native : NativeSlice values index rows offset count tokenCount heap)
    (guarded : guardValid values offset count tokenCount index = true)
    (position : Nat) (lower : offset.toNat ≤ position) (upper : position < offset.toNat + count.toNat)
    (same : before.heap = heap) (formed : before.CellsWellFormed)
    (valuesFound : before.local? (source.argumentId 0) = some values.value)
    (offsetFound : before.local? (source.argumentId 1) = some (.signed .i32 offset))
    (rowFound : before.local? rowId = some (.signed .i32 position))
    (bindingFound : before.local? bindingId = some (values.binding position).value)
    (tokenFound : before.local? tokenId = some (.signed .i32 (values.binding position).token.toInt)) :
    ∃ after, RunsStmt extractedProgram before ordering
      (if offset.toNat < position ∧
        adjacentValid (values.binding (position - 1)) (values.binding position) = false
       then .returned (some (.boolean false)) else .next) after ∧ PureFrame before after := by
  have bounds := guardValid_bounds guarded
  have offsetCast : (offset.toNat : Int) = offset := Int.toNat_of_nonneg bounds.2.1
  have countCast : (count.toNat : Int) = count := Int.toNat_of_nonneg bounds.2.2.1
  have importedScope {state : State} (formed : state.CellsWellFormed) :=
    actualScope (values.binding position) .ImportedBinding formed
  have previousScope {state : State} (formed : state.CellsWellFormed) :=
    actualScope (values.binding (position - 1)) .LocalBinding formed
  have previousToken {state : State} (formed : state.CellsWellFormed) :=
    actualToken (values.binding (position - 1)) formed
  simp only [sameScope_local, sameScope_imported] at importedScope previousScope
  by_cases prior : offset.toNat < position
  · have previousLower : offset.toNat ≤ position - 1 := by omega
    have previousUpper : position - 1 < offset.toNat + count.toNat := by omega
    have predecessor := eval_i32_predecessor extractedProgram.target position
      (by have limit := values.count.toInt_lt; have := guardValid_bounds guarded; omega)
    have previous {state : State} (same : state.heap = heap) (formed : state.CellsWellFormed) :=
      actualReadBinding values (position - 1)
        (native.bindings guarded _ previousLower previousUpper) same formed
    have predecessorCast : (position : Int) - 1 = (position - 1 : Nat) := by omega
    rw [predecessorCast] at predecessor
    by_cases ordered : adjacentValid (values.binding (position - 1)) (values.binding position) = false
    · simp only [prior, ordered, and_self, ↓reduceIte]
      dsimp only [ordering, adjacentValid] at *
      core_pure
    · have good : adjacentValid (values.binding (position - 1)) (values.binding position) = true :=
        by cases value : adjacentValid (values.binding (position - 1)) (values.binding position) <;> simp_all
      simp only [prior, ordered, and_false, ↓reduceIte]
      dsimp only [ordering, adjacentValid] at *
      core_pure
  · simp only [prior, false_and, ↓reduceIte]
    dsimp only [ordering]
    core_pure

private theorem actualIterationStep
    (native : NativeSlice values index rows offset count tokenCount heap)
    (guarded : guardValid values offset count tokenCount index = true)
    (position : Nat) (lower : offset.toNat ≤ position) (upper : position < offset.toNat + count.toNat)
    (good : rowValid values index rows offset.toNat tokenCount position = true)
    (frame : CallerFrame base before) (same : before.heap = heap)
    (pair : LocalPair base before rowId finishId (.signed .i32 position)
      (.signed .i32 (offset.toNat + count.toNat : Nat)))
    (valuesFound : before.local? (source.argumentId 0) = some values.value)
    (offsetFound : before.local? (source.argumentId 1) = some (.signed .i32 offset))
    (tokenCountFound : before.local? (source.argumentId 3) = some (.signed .i32 tokenCount))
    (indexFound : before.local? (source.argumentId 4) = some index.value) :
    ∃ after, RunsStmt extractedProgram before loop.2 .next after ∧ CallerFrame base after ∧
      LocalPair base after rowId finishId (.signed .i32 (position + 1 : Nat))
        (.signed .i32 (offset.toNat + count.toNat : Nat)) := by
  rcases (show basicValid tokenCount (values.binding position) = true ∧
      (if offset.toNat < position then adjacentValid (values.binding (position - 1)) (values.binding position)
        else true) = true ∧ 0 ≤ index.targetRow (values.binding position).target ∧
      targetMatches (values.binding position).target
        (rows (index.targetRow (values.binding position).target).toNat) = true from by
    simpa only [rowValid, Bool.and_eq_true, decide_eq_true_eq, and_assoc] using good) with
    ⟨basic, ordered, nonnegative, matching⟩
  have formed := frame.currentFormed
  have cell := pair.firstCell
  have rowFound := pair.first
  have bindingRead {state : State} (same : state.heap = heap) (formed : state.CellsWellFormed) :=
    actualReadBinding values position (native.bindings guarded position lower upper) same formed
  have tokenQuery {state : State} (formed : state.CellsWellFormed) :=
    actualToken (values.binding position) formed
  have allocationMatches {state : State} (formed : state.CellsWellFormed) :=
    actualTargetMatches (values.binding position).target
      (rows (index.targetRow (values.binding position).target).toNat) formed
  obtain ⟨readAfter, readRun, readFrame⟩ : ∃ after, RunsExpr extractedProgram before
      (source.bindingInitializer 2) (values.binding position).value after ∧ PureFrame before after := by
    core_pure_expr
  let bound := readAfter.bindLocal bindingId (values.binding position).value
  obtain ⟨tokenAfter, tokenRun, tokenFrame⟩ : ∃ after, RunsExpr extractedProgram bound
      (source.bindingInitializer 3) (.signed .i32 (values.binding position).token.toInt) after ∧
        PureFrame bound after := by core_pure_expr
  let tokened := tokenAfter.bindLocal tokenId (.signed .i32 (values.binding position).token.toInt)
  obtain ⟨checked, checkRun, checkFrame⟩ : ∃ after, RunsStmt extractedProgram tokened basicGuard .next after ∧
      PureFrame tokened after := by
    obtain ⟨after, run, frame⟩ := actualBasicGuard (values.binding position) tokenCount
      (before := tokened) (by core_local) (by core_local) (by core_local) (by core_formed)
    exact ⟨after, by simpa only [basic, ↓reduceIte] using run, frame⟩
  obtain ⟨orderedAfter, orderRun, orderFrame⟩ := actualOrdering native guarded position lower upper
    (before := checked) (by core_contract) (by core_formed)
    (by core_local) (by core_local) (by core_local) (by core_local) (by core_local)
  have notRejected : ¬(offset.toNat < position ∧
      adjacentValid (values.binding (position - 1)) (values.binding position) = false) := by
    intro bad
    simp only [if_pos bad.1, bad.2] at ordered
    cases ordered
  simp only [if_neg notRejected] at orderRun
  obtain ⟨lookupAfter, lookupRun, lookupFrame⟩ := actualAllocationLookup native guarded position lower upper basic ordered
    (before := orderedAfter) (by core_contract) (by core_formed) (by core_local) (by core_local)
  let allocated := lookupAfter.bindLocal allocationId
    (.signed .i32 (index.targetRow (values.binding position).target))
  have rowRead {state : State} (same : state.heap = heap) (formed : state.CellsWellFormed) :=
    actualSelectedRow native guarded position lower upper basic ordered nonnegative same formed
  obtain ⟨guardAfter, guardRun, guardFrame⟩ : ∃ after, RunsStmt extractedProgram allocated allocationGuard .next after ∧
      PureFrame allocated after := by
    dsimp only [allocationGuard]
    core_pure
  have scopedRead := ((CallerFrame.refl formed).transPure readFrame).bindLocal bindingId
    (values.binding position).value
  have scopedToken := (scopedRead.transPure tokenFrame).bindLocal tokenId
    (.signed .i32 (values.binding position).token.toInt)
  have scopedOrder := (scopedToken.transPure checkFrame).transPure orderFrame
  have scopedLookup := (scopedOrder.transPure lookupFrame).bindLocal allocationId
      (.signed .i32 (index.targetRow (values.binding position).target))
  have scopedFrame := scopedLookup.transPure guardFrame
  have prefixFrame := frame.trans scopedFrame
  have captured (retainedId : VarId) (bindingNe : retainedId ≠ bindingId)
      (tokenNe : retainedId ≠ tokenId) (allocationNe : retainedId ≠ allocationId) :
      guardAfter.cellId? retainedId = before.cellId? retainedId := by
    calc
      _ = allocated.cellId? retainedId := by simp only [State.cellId?, guardFrame.locals]
      _ = lookupAfter.cellId? retainedId :=
        State.bindLocal_cellId_of_ne lookupAfter retainedId allocationId (Ne.symm allocationNe) _
      _ = orderedAfter.cellId? retainedId := by simp only [State.cellId?, lookupFrame.locals]
      _ = checked.cellId? retainedId := by simp only [State.cellId?, orderFrame.locals]
      _ = tokened.cellId? retainedId := by simp only [State.cellId?, checkFrame.locals]
      _ = tokenAfter.cellId? retainedId :=
        State.bindLocal_cellId_of_ne tokenAfter retainedId tokenId (Ne.symm tokenNe) _
      _ = bound.cellId? retainedId := by simp only [State.cellId?, tokenFrame.locals]
      _ = readAfter.cellId? retainedId :=
        State.bindLocal_cellId_of_ne readAfter retainedId bindingId (Ne.symm bindingNe) _
      _ = before.cellId? retainedId := by simp only [State.cellId?, readFrame.locals]
  have rowCaptured := captured rowId (by decide) (by decide) (by decide)
  have finishCaptured := captured finishId (by decide) (by decide) (by decide)
  have cellGuard := rowCaptured.trans pair.firstCell
  have rowGuard : guardAfter.local? rowId = some (.signed .i32 position) := by core_local
  have fits : position + 1 < 2 ^ 31 := by
    have bounds := guardValid_bounds guarded
    have countCast : (count.toNat : Int) = count := Int.toNat_of_nonneg bounds.2.2.1
    have offsetCast : (offset.toNat : Int) = offset := Int.toNat_of_nonneg bounds.2.1
    have limit := values.count.toInt_lt
    omega
  obtain ⟨next, increment, assigned, effect⟩ := RunsExpr.assignI32 (program := extractedProgram)
    (op := .add) (operand := 1) (replacement := (position + 1 : Nat))
    cellGuard rowGuard (RunsExpr.ofStable StableExpr.value rfl)
    (by simpa only [evalAssignValue, assignOpBinary?, Int.natCast_one] using
      eval_i32_addNat extractedProgram.target position 1 fits)
  have nextFrame := prefixFrame.assignLocalFresh rowId base.nextCell _ cellGuard (Nat.le_refl _) assigned
  let completed := restoreLocals before next
  have bodyRun : RunsStmt extractedProgram before loop.2 .next
      (restoreLocals readAfter (restoreLocals tokenAfter (restoreLocals lookupAfter next))) := by
    dsimp only [loop]
    core_stmt_forward
  have run : RunsStmt extractedProgram before loop.2 .next completed := by
    simpa only [completed, restoreLocals, readFrame.locals, tokenFrame.locals, bound,
      State.bindLocal, lookupFrame.locals, orderFrame.locals, checkFrame.locals, tokened] using bodyRun
  have nextPair := pair.assignScoped frame.callerFormed scopedFrame.cells rowCaptured finishCaptured
    (Or.inl rfl) assigned
  refine ⟨completed, run, ⟨nextFrame.callerFormed, nextFrame.cells.restoreLocals,
    nextFrame.heap, nextFrame.world, nextFrame.views⟩, ?_⟩
  simpa only [completed, if_pos rfl, ite_true, if_neg pair.different] using nextPair

private theorem actualIterationReject
    (native : NativeSlice values index rows offset count tokenCount heap)
    (guarded : guardValid values offset count tokenCount index = true)
    (position : Nat) (lower : offset.toNat ≤ position) (upper : position < offset.toNat + count.toNat)
    (bad : rowValid values index rows offset.toNat tokenCount position = false)
    (same : before.heap = heap) (formed : before.CellsWellFormed)
    (rowFound : before.local? rowId = some (.signed .i32 position))
    (valuesFound : before.local? (source.argumentId 0) = some values.value)
    (offsetFound : before.local? (source.argumentId 1) = some (.signed .i32 offset))
    (tokenCountFound : before.local? (source.argumentId 3) = some (.signed .i32 tokenCount))
    (indexFound : before.local? (source.argumentId 4) = some index.value) :
    ∃ after, RunsStmt extractedProgram before loop.2 (.returned (some (.boolean false))) after ∧
      PureFrame before after := by
  have bindingRead {state : State} (same : state.heap = heap) (formed : state.CellsWellFormed) :=
    actualReadBinding values position (native.bindings guarded position lower upper) same formed
  have tokenQuery {state : State} (formed : state.CellsWellFormed) :=
    actualToken (values.binding position) formed
  have allocationMatches {state : State} (formed : state.CellsWellFormed) :=
    actualTargetMatches (values.binding position).target
      (rows (index.targetRow (values.binding position).target).toNat) formed
  by_cases basic : basicValid tokenCount (values.binding position) = true
  · by_cases ordered : (if offset.toNat < position then
        adjacentValid (values.binding (position - 1)) (values.binding position) else true) = true
    · have query {state : State} (same : state.heap = heap) (formed : state.CellsWellFormed)
          (bindingFound : state.local? bindingId = some (values.binding position).value)
          (indexFound : state.local? (source.argumentId 4) = some index.value) :=
        actualAllocationLookup native guarded position lower upper basic ordered same formed bindingFound indexFound
      have selected {state : State} (nonnegative : 0 ≤ index.targetRow (values.binding position).target)
          (same : state.heap = heap) (formed : state.CellsWellFormed) :=
        actualSelectedRow native guarded position lower upper basic ordered nonnegative same formed
      dsimp only [loop]
      apply RunsStmt.letFramedPure
      · core_pure_expr
      · intro readAfter readFrame
        apply RunsStmt.letFramedPure
        · core_pure_expr
        · intro tokenAfter tokenFrame
          apply RunsStmt.sequenceFramedNext
          · change ∃ after, RunsStmt extractedProgram
                (tokenAfter.bindLocal tokenId (.signed .i32 (values.binding position).token.toInt))
                basicGuard .next after ∧ PureFrame _ after
            obtain ⟨after, run, frame⟩ := actualBasicGuard (values.binding position) tokenCount
              (before := tokenAfter.bindLocal tokenId (.signed .i32 (values.binding position).token.toInt))
              (by core_local) (by core_local) (by core_local) (by core_formed)
            simp only [basic, ite_true] at run
            exact ⟨after, run, frame⟩
          · intro checked checkFrame
            apply RunsStmt.sequenceFramedNext
            · obtain ⟨after, run, frame⟩ := actualOrdering native guarded position lower upper
                (before := checked) (by core_contract) (by core_formed)
                (by core_local) (by core_local) (by core_local) (by core_local) (by core_local)
              have notRejected : ¬(offset.toNat < position ∧
                  adjacentValid (values.binding (position - 1)) (values.binding position) = false) := by
                rintro ⟨prior, failed⟩
                simp only [if_pos prior, failed] at ordered
                cases ordered
              change ∃ completed, RunsStmt extractedProgram checked ordering .next completed ∧
                PureFrame checked completed
              exact ⟨after, by simpa only [if_neg notRejected] using run, frame⟩
            · intro orderedAfter orderFrame
              apply RunsStmt.letFramedPure
              · exact query (by core_contract) (by core_formed) (by core_local) (by core_local)
              · intro lookupAfter lookupFrame
                by_cases nonnegative : 0 ≤ index.targetRow (values.binding position).target
                · have mismatch : targetMatches (values.binding position).target
                      (rows (index.targetRow (values.binding position).target).toNat) = false := by
                    simpa only [rowValid, basic, ordered, decide_eq_true nonnegative,
                      Bool.true_and] using bad
                  try dsimp only [allocationGuard]
                  core_pure
                · try dsimp only [allocationGuard]
                  core_pure
    · have prior : offset.toNat < position := by
        by_cases prior : offset.toNat < position
        · exact prior
        · simp only [if_neg prior] at ordered
          exact False.elim (ordered (by trivial))
      have orderFailed : adjacentValid (values.binding (position - 1)) (values.binding position) = false := by
        apply Bool.eq_false_iff.mpr
        simpa only [if_pos prior] using ordered
      dsimp only [loop]
      apply RunsStmt.letFramedPure
      · core_pure_expr
      · intro readAfter readFrame
        apply RunsStmt.letFramedPure
        · core_pure_expr
        · intro tokenAfter tokenFrame
          apply RunsStmt.sequenceFramedNext
          · change ∃ after, RunsStmt extractedProgram
                (tokenAfter.bindLocal tokenId (.signed .i32 (values.binding position).token.toInt))
                basicGuard .next after ∧ PureFrame _ after
            obtain ⟨after, run, frame⟩ := actualBasicGuard (values.binding position) tokenCount
              (before := tokenAfter.bindLocal tokenId (.signed .i32 (values.binding position).token.toInt))
              (by core_local) (by core_local) (by core_local) (by core_formed)
            simp only [basic, ite_true] at run
            exact ⟨after, run, frame⟩
          · intro checked checkFrame
            obtain ⟨after, run, frame⟩ := actualOrdering native guarded position lower upper
              (before := checked) (by core_contract) (by core_formed)
              (by core_local) (by core_local) (by core_local) (by core_local) (by core_local)
            simp only [if_pos (And.intro prior orderFailed)] at run
            change ∃ completed, RunsStmt extractedProgram checked
              (.sequence ordering (source.bindingStatement 6))
              (.returned (some (.boolean false))) completed ∧ PureFrame checked completed
            exact ⟨after, RunsStmt.sequenceCompleted run (by intro impossible; cases impossible) _, frame⟩
  · have basicFailed : basicValid tokenCount (values.binding position) = false := Bool.eq_false_iff.mpr basic
    dsimp only [loop]
    apply RunsStmt.letFramedPure
    · core_pure_expr
    · intro readAfter readFrame
      apply RunsStmt.letFramedPure
      · core_pure_expr
      · intro tokenAfter tokenFrame
        apply RunsStmt.sequencePureCompleted (by intro impossible; cases impossible)
        change ∃ after, RunsStmt extractedProgram
            (tokenAfter.bindLocal tokenId (.signed .i32 (values.binding position).token.toInt))
            basicGuard (.returned (some (.boolean false))) after ∧ PureFrame _ after
        obtain ⟨after, run, frame⟩ := actualBasicGuard (values.binding position) tokenCount
          (before := tokenAfter.bindLocal tokenId (.signed .i32 (values.binding position).token.toInt))
          (by core_local) (by core_local) (by core_local) (by core_formed)
        simp only [basicFailed, Bool.false_eq_true, ite_false] at run
        exact ⟨after, run, frame⟩

private theorem actualLoop
    (native : NativeSlice values index rows offset count tokenCount heap)
    (guarded : guardValid values offset count tokenCount index = true)
    (frame : CallerFrame base before) (same : base.heap = heap)
    (pair : LocalPair base before rowId finishId (.signed .i32 offset.toNat)
      (.signed .i32 (offset.toNat + count.toNat : Nat)))
    (valuesFound : base.local? (source.argumentId 0) = some values.value)
    (offsetFound : base.local? (source.argumentId 1) = some (.signed .i32 offset))
    (tokenCountFound : base.local? (source.argumentId 3) = some (.signed .i32 tokenCount))
    (indexFound : base.local? (source.argumentId 4) = some index.value) :
    ∃ completion after, RunsStmt extractedProgram before (.whileLoop loop.1 loop.2) completion after ∧
      CallerFrame base after ∧
      ((completion = .next ∧ sliceResult values index rows offset count tokenCount = true) ∨
       (completion = .returned (some (.boolean false)) ∧
         sliceResult values index rows offset count tokenCount = false)) := by
  let invariant : Nat → State → Prop := fun remaining state => ∃ position : Nat,
    offset.toNat ≤ position ∧ position + remaining = offset.toNat + count.toNat ∧
    CallerFrame base state ∧
    LocalPair base state rowId finishId (.signed .i32 position)
      (.signed .i32 (offset.toNat + count.toNat : Nat)) ∧
    ∀ previous, offset.toNat ≤ previous → previous < position →
      rowValid values index rows offset.toNat tokenCount previous = true
  let post : Completion → State → Prop := fun completion state => CallerFrame base state ∧
    ((completion = .next ∧ sliceResult values index rows offset count tokenCount = true) ∨
     (completion = .returned (some (.boolean false)) ∧
       sliceResult values index rows offset count tokenCount = false))
  have finished : ∀ state, invariant 0 state → ∃ after,
      RunsExpr extractedProgram state loop.1 (.boolean false) after ∧ post .next after := by
    intro state initial
    rcases initial with ⟨position, lower, atEnd, frame, pair, visited⟩
    have endPosition : position = offset.toNat + count.toNat := by omega
    have rowFound := pair.first
    have finishFound := pair.second
    have condition : RunsExpr extractedProgram state loop.1 (.boolean false) state := by
      dsimp only [loop]
      core_run
    refine ⟨state, condition, frame, Or.inl ⟨rfl, ?_⟩⟩
    apply sliceResult_iff.mpr
    refine ⟨guarded, ?_⟩
    intro relative member
    have inside := List.mem_range.mp member
    exact visited _ (by omega) (by omega)
  have step : ∀ remaining state, invariant (remaining + 1) state → ∃ middle,
      RunsExpr extractedProgram state loop.1 (.boolean true) middle ∧
      ((∃ after completion, RunsStmt extractedProgram middle loop.2 completion after ∧
        (completion = .next ∨ completion = .continueLoop) ∧ invariant remaining after) ∨
       (∃ after value, RunsStmt extractedProgram middle loop.2 (.returned value) after ∧
         post (.returned value) after)) := by
    intro remaining state initial
    rcases initial with ⟨position, lower, remainingEq, frame, pair, visited⟩
    have upper : position < offset.toNat + count.toNat := by omega
    have rowFound := pair.first
    have finishFound := pair.second
    have currentValues := pair.read (localId := source.argumentId 0) (by decide) (by decide) valuesFound
    have currentOffset := pair.read (localId := source.argumentId 1) (by decide) (by decide) offsetFound
    have currentTokens := pair.read (localId := source.argumentId 3) (by decide) (by decide) tokenCountFound
    have currentIndex := pair.read (localId := source.argumentId 4) (by decide) (by decide) indexFound
    have condition : RunsExpr extractedProgram state loop.1 (.boolean true) state := by
      dsimp only [loop]
      core_run
    refine ⟨state, condition, ?_⟩
    by_cases good : rowValid values index rows offset.toNat tokenCount position = true
    · obtain ⟨after, run, nextFrame, nextPair⟩ := actualIterationStep native guarded position lower upper good
        frame (frame.heap.trans same) pair
        currentValues currentOffset currentTokens currentIndex
      apply Or.inl
      refine ⟨after, .next, run, Or.inl rfl, position + 1, by omega, by omega,
        nextFrame, nextPair, ?_⟩
      intro previous previousLower previousUpper
      by_cases last : previous = position
      · simpa only [last] using good
      · exact visited _ previousLower (by omega)
    · have bad : rowValid values index rows offset.toNat tokenCount position = false :=
        Bool.eq_false_iff.mpr good
      obtain ⟨after, run, pure⟩ := actualIterationReject native guarded position lower upper bad
        (frame.heap.trans same) frame.currentFormed rowFound
        currentValues currentOffset currentTokens currentIndex
      apply Or.inr
      refine ⟨after, some (.boolean false), run, frame.transPure pure, Or.inr ⟨rfl, ?_⟩⟩
      apply Bool.eq_false_iff.mpr
      intro accepted
      have allRows := (sliceResult_iff.mp accepted).2
      have relative : position - offset.toNat ∈ List.range count.toNat := by
        apply List.mem_range.mpr
        omega
      have acceptedRow := allRows _ relative
      have address : offset.toNat + (position - offset.toNat) = position := by omega
      rw [address, bad] at acceptedRow
      contradiction
  have initial : invariant count.toNat before := by
    refine ⟨offset.toNat, Nat.le_refl _, rfl, frame, pair, ?_⟩
    intro previous lower upper
    omega
  exact RunsStmt.whileCountOrReturn invariant post finished step initial

/-- Total actual1570 result, including original represented rejection cases.
    The call is read-only after the independently established header borrow. -/
@[core_pure_rule] theorem actualValidSlice (values : Values) (index : Index)
    (rows : Nat → AllocationRow) (offset count tokenCount : Int32)
    (native : NativeSlice values index rows offset.toInt count.toInt tokenCount.toInt heap)
    (same : before.heap = heap) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call source.id
      [.value values.value, .value (.signed .i32 offset.toInt), .value (.signed .i32 count.toInt),
        .value (.signed .i32 tokenCount.toInt), .value index.value])
      (.boolean (sliceResult values index rows offset.toInt count.toInt tokenCount.toInt)) after ∧
      PureFrame before after := by
  by_cases guarded : guardValid values offset.toInt count.toInt tokenCount.toInt index = true
  · have bounds := guardValid_bounds guarded
    have offsetCast : (offset.toInt.toNat : Int) = offset.toInt := Int.toNat_of_nonneg bounds.2.1
    have countCast : (count.toInt.toNat : Int) = count.toInt := Int.toNat_of_nonneg bounds.2.2.1
    have finishFits : offset.toInt.toNat + count.toInt.toNat < 2 ^ 31 := by
      have limit := values.count.toInt_lt
      omega
    have addition := eval_i32_addNat extractedProgram.target offset.toInt.toNat count.toInt.toNat finishFits
    rw [offsetCast, countCast] at addition
    core_call_pure source as callee
    have calleeWellFormed : callee.CellsWellFormed := by core_formed
    let rowState := callee.bindLocal rowId (.signed .i32 offset.toInt.toNat)
    let seeded := rowState.bindLocal finishId (.signed .i32 (offset.toInt.toNat + count.toInt.toNat : Nat))
    have pair : LocalPair callee seeded rowId finishId (.signed .i32 offset.toInt.toNat)
        (.signed .i32 (offset.toInt.toNat + count.toInt.toNat : Nat)) :=
      LocalPair.start calleeWellFormed (by decide)
    have frame : CallerFrame callee seeded :=
      ((CallerFrame.refl calleeWellFormed).bindLocal rowId _).bindLocal finishId _
    obtain ⟨completion, loopAfter, loopRun, loopFrame, result⟩ := actualLoop native guarded frame
      (by core_contract) pair (by core_local) (by core_local) (by core_local) (by core_local)
    have guardRun : RunsStmt extractedProgram callee descriptorGuard .next callee := by
      have run := actualDescriptorGuard values index offset count tokenCount (before := callee)
        (by core_local) (by core_local) (by core_local) (by core_local) (by core_local)
      simpa only [guarded, ite_true] using run
    have rowInit : RunsExpr extractedProgram callee (source.bindingInitializer 0)
        (.signed .i32 offset.toInt.toNat) callee := by
      rw [offsetCast]
      core_run
    have finishInit : RunsExpr extractedProgram rowState (source.bindingInitializer 1)
        (.signed .i32 (offset.toInt.toNat + count.toInt.toNat : Nat)) rowState := by
      core_run
    let completed := restoreLocals callee (restoreLocals rowState loopAfter)
    have completedFrame : PureFrame callee completed :=
      ⟨loopFrame.callerFormed, loopFrame.cells.restoreLocals.restoreLocals,
        rfl, loopFrame.heap, loopFrame.world, loopFrame.views⟩
    rcases result with ⟨fallthrough, accepted⟩ | ⟨returned, rejected⟩
    · subst completion
      rw [accepted]
      refine ⟨completed, ?_, completedFrame⟩
      dsimp only [source]
      core_stmt_forward
    · subst completion
      rw [rejected]
      refine ⟨completed, ?_, completedFrame⟩
      dsimp only [source]
      core_stmt_forward
  · have rejected : guardValid values offset.toInt count.toInt tokenCount.toInt index = false :=
      Bool.eq_false_iff.mpr guarded
    simp only [sliceResult, rejected, Bool.false_and]
    core_call_pure source as callee
    have run := actualDescriptorGuard values index offset count tokenCount (before := callee)
      (by core_local) (by core_local) (by core_local) (by core_local) (by core_local)
    simp only [rejected, Bool.false_eq_true, ite_false] at run
    change ∃ completed, RunsStmt extractedProgram callee
      (.sequence descriptorGuard (source.bindingStatement 0))
      (.returned (some (.boolean false))) completed ∧ PureFrame callee completed
    exact ⟨callee, RunsStmt.sequenceCompleted run (by intro impossible; cases impossible) _,
      PureFrame.refl (by core_formed)⟩

/-- Actual1569 consumes the same original full-span criterion exactly once. -/
@[core_pure_rule] theorem actualValid (values : Values) (index : Index)
    (rows : Nat → AllocationRow) (tokenCount : Int32)
    (native : NativeSlice values index rows 0 values.count.toInt tokenCount.toInt heap)
    (same : before.heap = heap) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call whole.id
      [.value values.value, .value (.signed .i32 tokenCount.toInt), .value index.value])
      (.boolean (sliceResult values index rows 0 values.count.toInt tokenCount.toInt)) after ∧
      PureFrame before after := by
  have validator {state : State} (same : state.heap = heap) (formed : state.CellsWellFormed) :=
    actualValidSlice values index rows (0 : Int32) values.count tokenCount native same formed
  core_call_pure whole as callee
  core_pure

#print axioms actualTargetMatches
#print axioms actualBasicGuard
#print axioms actualDescriptorGuard
#print axioms actualSelectedRow
#print axioms actualLoop
#print axioms actualValidSlice
#print axioms actualValid
#print axioms OriginalSlice.bindingSpan
#print axioms OriginalSlice.indexSpan

end IRValueCatalogValid
