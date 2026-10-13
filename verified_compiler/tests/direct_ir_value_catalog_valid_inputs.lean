import verified_compiler.tests.direct_ir_owned_inputs
import Lanius.Core.Bindings
import Lanius.Semantics.NativeSnapshotFrame
import Lanius.Semantics.PureProof
import Lanius.Semantics.CallProof

namespace IRValueCatalogValid

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyOwnedInputs

abbrev Scope := Extracted.«lowering::value_catalog».Types.«ValueBindingScope»
abbrev Target := Extracted.«lowering::value_catalog».Types.«ValueTarget»

def scopeValue : Scope → Value
  | .InvalidScope => source_value Extracted.«lowering::value_catalog».Types.«ValueBindingScope».«InvalidScope» []
  | .LocalBinding => source_value Extracted.«lowering::value_catalog».Types.«ValueBindingScope».«LocalBinding» []
  | .ImportedBinding => source_value Extracted.«lowering::value_catalog».Types.«ValueBindingScope».«ImportedBinding» []
def scopeLocal : Scope → Bool | .LocalBinding => true | _ => false
def scopeImported : Scope → Bool | .ImportedBinding => true | _ => false
def sameScope (left right : Scope) : Bool := match left, right with
  | .InvalidScope, .InvalidScope | .LocalBinding, .LocalBinding
  | .ImportedBinding, .ImportedBinding => true
  | _, _ => false
@[simp] theorem sameScope_local (scope : Scope) : sameScope scope .LocalBinding = scopeLocal scope := by
  cases scope <;> rfl
@[simp] theorem sameScope_imported (scope : Scope) : sameScope scope .ImportedBinding = scopeImported scope := by
  cases scope <;> rfl
def targetValue : Target → Value
  | .InvalidTarget => source_value Extracted.«lowering::value_catalog».Types.«ValueTarget».«InvalidTarget» []
  | .Callable id => source_value Extracted.«lowering::value_catalog».Types.«ValueTarget».«Callable» [.signed .i32 id.toInt]
  | .Variant (.mk id ordinal fields) =>
      source_value Extracted.«lowering::value_catalog».Types.«ValueTarget».«Variant»
        [source_value Extracted.«lowering::value_catalog».Types.«VariantTarget».mk
          [.signed .i32 id.toInt, .signed .i32 ordinal.toInt, .signed .i32 fields.toInt]]
def targetValid : Target → Bool
  | .InvalidTarget => false
  | .Callable id => decide (0 ≤ id.toInt)
  | .Variant (.mk id ordinal fields) =>
      (decide (0 ≤ id.toInt) && decide (0 ≤ ordinal.toInt)) && decide (0 ≤ fields.toInt)

structure Binding where
  token : Int32
  scope : Scope
  target : Target
def Binding.value (binding : Binding) : Value :=
  source_value Extracted.«lowering::value_catalog».Types.«ValueBinding».mk
    [.signed .i32 binding.token.toInt, scopeValue binding.scope, targetValue binding.target]
def bindingType : Ty := match source_value Extracted.«lowering::value_catalog».Types.«ValueBinding».mk [] with
  | .structure id _ => .structure id | _ => .unit

structure Values where
  address : Nat
  length : Nat
  count : Int32
  binding : Nat → Binding
def Values.value (values : Values) : Value :=
  source_value Extracted.«lowering::value_catalog».Types.«ValueTable».mk
    [.rawSlice bindingType values.address values.length, .signed .i32 values.count.toInt]

structure IndexEntry where
  declarationRow : Int32
  coreRow : Int32
def IndexEntry.value (entry : IndexEntry) : Value :=
  source_value Extracted.«lowering::allocation».Types.«IndexEntry».mk
    [.signed .i32 entry.declarationRow.toInt, .signed .i32 entry.coreRow.toInt]
def indexEntryType : Ty := match source_value Extracted.«lowering::allocation».Types.«IndexEntry».mk [] with
  | .structure id _ => .structure id | _ => .unit

/-- The runtime flag and native slot contents carry no builder-correctness or
    uniqueness claim. Enumeration storage is represented but never read here. -/
structure Index where
  table : AllocationTable
  address : Nat
  length : Nat
  enumerationAddress : Nat
  enumerationLength : Nat
  enumerationCount : Int32
  count : Int32
  valid : Bool
  entry : Nat → IndexEntry
def Index.value (index : Index) : Value :=
  source_value Extracted.«lowering::allocation».Types.«Index».mk
    [index.table.value, .rawSlice indexEntryType index.address index.length,
      .rawSlice (.scalar (.signed .i32)) index.enumerationAddress index.enumerationLength,
      .signed .i32 index.enumerationCount.toInt, .signed .i32 index.count.toInt,
      .boolean index.valid]
def Index.lookupGuard (index : Index) (id : Int) : Prop :=
  index.valid = true ∧ 0 ≤ id ∧ id < index.count.toInt
instance (index : Index) (id : Int) : Decidable (index.lookupGuard id) := by
  unfold Index.lookupGuard
  infer_instance
def Index.declarationRow (index : Index) (id : Int) : Int :=
  if index.lookupGuard id then (index.entry id.toNat).declarationRow.toInt else -1
def Index.coreRow (index : Index) (id : Int) : Int :=
  if index.lookupGuard id then (index.entry id.toNat).coreRow.toInt else -1
def Index.targetRow (index : Index) : Target → Int
  | .InvalidTarget => -1
  | .Callable id => index.coreRow id.toInt
  | .Variant (.mk id _ _) => index.declarationRow id.toInt
def targetId : Target → Int
  | .InvalidTarget => -1
  | .Callable id => id.toInt
  | .Variant (.mk id _ _) => id.toInt

def callableKind : Extracted.«lowering::declarations».Types.«DeclarationKind» → Bool
  | .Function | .External => true | _ => false
def enumerationKind : Extracted.«lowering::declarations».Types.«DeclarationKind» → Bool
  | .Enumeration => true | _ => false
def targetMatches (target : Target) (row : AllocationRow) : Bool := match target with
  | .InvalidTarget => false
  | .Callable id => decide (row.coreId.toInt = id.toInt) && callableKind row.source.kind
  | .Variant (.mk id _ _) => decide (row.declarationId.toInt = id.toInt) && enumerationKind row.source.kind

def basicValid (tokenCount : Int) (binding : Binding) : Bool :=
  ((decide (0 ≤ binding.token.toInt) && decide (binding.token.toInt < tokenCount)) &&
    targetValid binding.target) && (scopeLocal binding.scope || scopeImported binding.scope)
def adjacentValid (previous current : Binding) : Bool :=
  decide (previous.token.toInt < current.token.toInt) ||
    (decide (previous.token.toInt = current.token.toInt) &&
      (scopeLocal previous.scope && scopeImported current.scope))
def guardValid (values : Values) (offset count tokenCount : Int) (index : Index) : Bool :=
  ((((((decide (0 ≤ values.count.toInt) && decide (0 ≤ offset)) && decide (0 ≤ count)) &&
    decide (offset ≤ values.count.toInt)) && decide (count ≤ values.count.toInt - offset)) &&
    decide (0 ≤ tokenCount)) && index.valid)
def rowValid (values : Values) (index : Index) (rows : Nat → AllocationRow)
    (offset : Nat) (tokenCount : Int) (position : Nat) : Bool :=
  let binding := values.binding position
  (basicValid tokenCount binding &&
    (if offset < position then adjacentValid (values.binding (position - 1)) binding else true)) &&
    (decide (0 ≤ index.targetRow binding.target) &&
      targetMatches binding.target (rows (index.targetRow binding.target).toNat))

/-- A finite semantic criterion over original represented fields, not a
    validator execution or an index-constructor theorem. Ordering is span-local. -/
def SemanticValidSlice (values : Values) (index : Index) (rows : Nat → AllocationRow)
    (offset count tokenCount : Int) : Prop :=
  guardValid values offset count tokenCount index = true ∧
    ∀ relative ∈ List.range count.toNat,
      rowValid values index rows offset.toNat tokenCount (offset.toNat + relative) = true
def sliceResult (values : Values) (index : Index) (rows : Nat → AllocationRow)
    (offset count tokenCount : Int) : Bool :=
  guardValid values offset count tokenCount index &&
    (List.range count.toNat).all
      (fun relative => rowValid values index rows offset.toNat tokenCount (offset.toNat + relative))
theorem sliceResult_iff : sliceResult values index rows offset count tokenCount = true ↔
    SemanticValidSlice values index rows offset count tokenCount := by
  simp only [sliceResult, SemanticValidSlice, Bool.and_eq_true, List.all_eq_true]

theorem guardValid_bounds (valid : guardValid values offset count tokenCount index = true) :
    0 ≤ values.count.toInt ∧ 0 ≤ offset ∧ 0 ≤ count ∧ offset ≤ values.count.toInt ∧
      count ≤ values.count.toInt - offset ∧ 0 ≤ tokenCount ∧ index.valid = true := by
  simpa only [guardValid, Bool.and_eq_true, decide_eq_true_eq, and_assoc] using valid

structure NativeBinding (values : Values) (heap : Heap) (position : Nat) where
  base : Nat
  inside : position < values.length
  location : rawSliceElementAddress? extractedProgram bindingType values.address position = .ok base
  snapshot : NativeSnapshot 64 extractedProgram heap bindingType base (values.binding position).value 48
theorem NativeBinding.read (native : NativeBinding values state.heap position) :
    readRawSliceIndex extractedProgram state bindingType values.address values.length position =
      .ok (values.binding position).value := by
  simp only [readRawSliceIndex, Nat.not_le_of_lt native.inside, ↓reduceIte, native.location]
  exact native.snapshot.read
structure NativeIndexEntry (index : Index) (heap : Heap) (id : Nat) where
  base : Nat
  inside : id < index.length
  location : rawSliceElementAddress? extractedProgram indexEntryType index.address id = .ok base
  snapshot : NativeSnapshot 64 extractedProgram heap indexEntryType base (index.entry id).value 16
theorem NativeIndexEntry.read {id : Nat} (native : NativeIndexEntry index state.heap id) :
    readRawSliceIndex extractedProgram state indexEntryType index.address index.length id =
      .ok (index.entry id).value := by
  simp only [readRawSliceIndex, Nat.not_le_of_lt native.inside, ↓reduceIte, native.location]
  exact native.snapshot.read

@[core_pure_rule] theorem actualReadBinding (values : Values) (position : Nat)
    (native : NativeBinding values heap position) (same : state.heap = heap)
    (formed : state.CellsWellFormed) : ∃ after, RunsExpr extractedProgram state
      (.call Extracted.«lowering::value_catalog».Functions.«read_binding».core.id
        [.value values.value, .value (.signed .i32 position)])
      (values.binding position).value after ∧ PureFrame state after := by
  subst heap
  have read := native.read (state := state)
  core_call_pure Extracted.«lowering::value_catalog».Functions.«read_binding».core as callee
  core_pure
@[core_pure_rule] theorem actualToken (binding : Binding) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call Extracted.«lowering::value_catalog».Functions.«binding_token».core.id [.value binding.value])
      (.signed .i32 binding.token.toInt) after ∧ PureFrame state after := by
  core_call_pure Extracted.«lowering::value_catalog».Functions.«binding_token».core as callee
  core_pure
@[core_pure_rule] theorem actualScope (binding : Binding) (expected : Scope)
    (formed : state.CellsWellFormed) : ∃ after, RunsExpr extractedProgram state
      (.call Extracted.«lowering::value_catalog».Functions.«binding_is_scope».core.id
        [.value binding.value, .value (scopeValue expected)])
      (.boolean (sameScope binding.scope expected)) after ∧ PureFrame state after := by
  cases scope : binding.scope <;> cases expected <;>
    simp only [Binding.value, scope, sameScope, scopeValue]
  all_goals (core_call_pure Extracted.«lowering::value_catalog».Functions.«binding_is_scope».core as callee; core_pure)
@[core_pure_rule] theorem actualTargetValid (target : Target) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call Extracted.«lowering::value_catalog».Functions.«valid_target».core.id [.value (targetValue target)])
      (.boolean (targetValid target)) after ∧ PureFrame state after := by
  cases target with
  | InvalidTarget =>
      dsimp only [targetValue, targetValid]
      core_call_pure Extracted.«lowering::value_catalog».Functions.«valid_target».core as callee
      core_pure
  | Callable id =>
      dsimp only [targetValue, targetValid]
      core_call_pure Extracted.«lowering::value_catalog».Functions.«valid_target».core as callee
      core_pure
  | Variant value =>
      cases value
      dsimp only [targetValue, targetValid]
      core_call_pure Extracted.«lowering::value_catalog».Functions.«valid_target».core as callee
      core_pure

@[core_pure_rule] theorem actualCoreRow (index : Index) (id : Int)
    (native : index.lookupGuard id → NativeIndexEntry index heap id.toNat)
    (same : state.heap = heap) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call Extracted.«lowering::allocation».Functions.«core_row».core.id
        [.value index.value, .value (.signed .i32 id)])
      (.signed .i32 (index.coreRow id)) after ∧ PureFrame state after := by
  subst heap
  by_cases guarded : index.lookupGuard id
  · have cast : (id.toNat : Int) = id := Int.toNat_of_nonneg guarded.2.1
    have read := (native guarded).read (state := state)
    dsimp only [Index.coreRow]
    rw [if_pos guarded]
    rw [← cast]
    simp only [Int.toNat_natCast]
    dsimp only [Index.lookupGuard] at guarded
    core_call_pure Extracted.«lowering::allocation».Functions.«core_row».core as callee
    apply RunsStmt.guardPureFalse
    · core_run
    · apply RunsStmt.letPure
      · core_run
      · core_formed
      · core_state entriesState
        have heapSame : entriesState.heap = state.heap := rfl
        have currentRead : readRawSliceIndex extractedProgram entriesState indexEntryType
            index.address index.length id.toNat = .ok (index.entry id.toNat).value := by
          simpa only [readRawSliceIndex, heapSame] using read
        have entryRun : RunsExpr extractedProgram entriesState
            (.index (.local (Extracted.«lowering::allocation».Functions.«core_row».core.bindingId 0))
              (.local (Extracted.«lowering::allocation».Functions.«core_row».core.argumentId 1)))
            (index.entry id.toNat).value entriesState := by
          apply RunsExpr.ofStable
          · exact StableExpr.rawSliceRead (.local (by core_local)) (.local (by core_local)) currentRead
          · rfl
        exact ⟨entriesState, RunsStmt.returnValue (RunsExpr.field
          (fields := [.signed .i32 (index.entry id.toNat).declarationRow.toInt,
            .signed .i32 (index.entry id.toNat).coreRow.toInt]) entryRun (by rfl)),
          PureFrame.refl (by core_formed)⟩
  · dsimp only [Index.coreRow]
    rw [if_neg guarded]
    dsimp only [Index.lookupGuard] at guarded
    core_call_pure Extracted.«lowering::allocation».Functions.«core_row».core as callee
    core_pure

@[core_pure_rule] theorem actualDeclarationRow (index : Index) (id : Int)
    (native : index.lookupGuard id → NativeIndexEntry index heap id.toNat)
    (same : state.heap = heap) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call Extracted.«lowering::allocation».Functions.«declaration_row».core.id
        [.value index.value, .value (.signed .i32 id)])
      (.signed .i32 (index.declarationRow id)) after ∧ PureFrame state after := by
  subst heap
  by_cases guarded : index.lookupGuard id
  · have cast : (id.toNat : Int) = id := Int.toNat_of_nonneg guarded.2.1
    have read := (native guarded).read (state := state)
    dsimp only [Index.declarationRow]
    rw [if_pos guarded]
    rw [← cast]
    simp only [Int.toNat_natCast]
    dsimp only [Index.lookupGuard] at guarded
    core_call_pure Extracted.«lowering::allocation».Functions.«declaration_row».core as callee
    apply RunsStmt.guardPureFalse
    · core_run
    · apply RunsStmt.letPure
      · core_run
      · core_formed
      · core_state entriesState
        have heapSame : entriesState.heap = state.heap := rfl
        have currentRead : readRawSliceIndex extractedProgram entriesState indexEntryType
            index.address index.length id.toNat = .ok (index.entry id.toNat).value := by
          simpa only [readRawSliceIndex, heapSame] using read
        have entryRun : RunsExpr extractedProgram entriesState
            (.index (.local (Extracted.«lowering::allocation».Functions.«declaration_row».core.bindingId 0))
              (.local (Extracted.«lowering::allocation».Functions.«declaration_row».core.argumentId 1)))
            (index.entry id.toNat).value entriesState := by
          apply RunsExpr.ofStable
          · exact StableExpr.rawSliceRead (.local (by core_local)) (.local (by core_local)) currentRead
          · rfl
        exact ⟨entriesState, RunsStmt.returnValue (RunsExpr.field
          (fields := [.signed .i32 (index.entry id.toNat).declarationRow.toInt,
            .signed .i32 (index.entry id.toNat).coreRow.toInt]) entryRun (by rfl)),
          PureFrame.refl (by core_formed)⟩
  · dsimp only [Index.declarationRow]
    rw [if_neg guarded]
    dsimp only [Index.lookupGuard] at guarded
    core_call_pure Extracted.«lowering::allocation».Functions.«declaration_row».core as callee
    core_pure

#print axioms NativeBinding.read
#print axioms NativeIndexEntry.read
#print axioms actualReadBinding
#print axioms actualTargetValid
#print axioms actualCoreRow
#print axioms actualDeclarationRow

end IRValueCatalogValid
