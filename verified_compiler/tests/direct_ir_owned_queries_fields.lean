import verified_compiler.tests.direct_ir_owned_queries_allocation

namespace IRBodyOwnedInputs

open Lanius Lanius.Core Lanius.Semantics

def kindCode : DeclarationKind → Nat
  | .Invalid => 0 | .Structure => 1 | .Enumeration => 2 | .Alias => 3 | .Constant => 4
  | .Function => 5 | .External => 6 | .Module => 7 | .Import => 8
def kindSame (left right : DeclarationKind) : Bool := kindCode left == kindCode right

theorem kindSame_iff (left right : DeclarationKind) : kindSame left right = true ↔ left = right := by
  cases left <;> cases right <;> simp [kindSame, kindCode]

@[core_pure_rule] private theorem actualDeclarationKind (row : DeclarationRow)
    (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::declarations».Functions.«row_kind».core.id [.value row.value])
      (kindValue row.kind) after ∧ PureFrame before after := by
  core_call_pure Extracted.«lowering::declarations».Functions.«row_kind».core as callee
  core_pure

@[core_pure_rule] private theorem actualSameKind (left right : DeclarationKind)
    (formed : before.CellsWellFormed) : ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::declarations».Functions.«same_kind».core.id
        [.value (kindValue left), .value (kindValue right)])
      (.boolean (kindSame left right)) after ∧ PureFrame before after := by
  have same : evalBinaryValue extractedProgram.target .equal (kindValue left) (kindValue right) =
      .ok (.boolean (kindSame left right)) := by
    cases left <;> cases right <;> rfl
  core_call_pure Extracted.«lowering::declarations».Functions.«same_kind».core as callee
  core_pure

@[core_pure_rule] theorem actualRowKind (row : AllocationRow) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::allocation».Functions.«row_kind».core.id [.value row.value])
      (kindValue row.source.kind) after ∧ PureFrame before after := by
  core_call_pure Extracted.«lowering::allocation».Functions.«row_kind».core as callee
  core_pure

@[core_pure_rule] theorem actualRowHasKind (row : AllocationRow) (expected : DeclarationKind)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::allocation».Functions.«row_has_kind».core.id
        [.value row.value, .value (kindValue expected)])
      (.boolean (kindSame row.source.kind expected)) after ∧ PureFrame before after := by
  core_call_pure Extracted.«lowering::allocation».Functions.«row_has_kind».core as callee
  core_pure

#print axioms kindSame_iff
#print axioms actualRowKind
#print axioms actualRowHasKind

end IRBodyOwnedInputs
