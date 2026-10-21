import verified_compiler.tests.direct_ir_owned_inputs_entry
import Lanius.Core.Bindings
import Lanius.Semantics.LocalEnvProof

namespace IRBodyOwnedProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyOwnedInputs
open IRBodyProductionInputs

def ownedSource := Extracted.«lowering::bodies».Functions.«lower_owned».core

def ownedCall (input workspace : Value) : Expr :=
  .call ownedSource.id ([input, workspace].map Expr.value)

def entrySuffix : Stmt := match ownedSource.bindingStatement 13 with
  | .letLocal _ _ _ body => body
  | _ => .skip

def argumentValues (raw : RawInputs) (workspace : RawWorkspace) : LocalValues :=
  (LocalValues.empty.set (ownedSource.argumentId 0) raw.value).set (ownedSource.argumentId 1) workspace.value

/-- Symbolic values after the actual field prelude. No cell identities or
    native heap facts are encoded in this lexical map. -/
def entryValues (raw : RawInputs) (workspace : RawWorkspace) : LocalValues :=
  ((((((((((((((argumentValues raw workspace).set (ownedSource.bindingId 0)
    (source_value Extracted.«lowering::body_context».Types.«WordRegion».mk
      [raw.source, .signed .i32 raw.sourceWords.toInt])).set (ownedSource.bindingId 1)
    (source_value Extracted.«verified::token».Types.«TokenTable».mk
      [raw.tokens, .signed .i32 raw.tokenCount.toInt, .pointer raw.tokenStorage])).set (ownedSource.bindingId 2)
    raw.allocationTable.value).set (ownedSource.bindingId 3) raw.resolutions).set (ownedSource.bindingId 4)
    raw.valuesValue).set (ownedSource.bindingId 5)
    (source_value Extracted.«verified::surface_expr».Types.«ExpressionArena».mk
      [workspace.expressionData, workspace.expressionCount, .signed .i32 workspace.expressionCapacity.toInt])).set
    (ownedSource.bindingId 6) (source_value Extracted.«verified::surface_type».Types.«TypeArena».mk
      [workspace.typeData, workspace.typeCount, .signed .i32 workspace.typeCapacity.toInt])).set
    (ownedSource.bindingId 7) (source_value Extracted.«lowering::types».Types.«Results».mk
      [workspace.typeOutput, .signed .i32 workspace.typeOutputCount.toInt])).set
    (ownedSource.bindingId 8) (.signed .i32 raw.owner.toInt)).set
    (ownedSource.bindingId 9) (.signed .i32 raw.sourceWords.toInt)).set
    (ownedSource.bindingId 10) (.signed .i32 raw.tokenCount.toInt)).set
    (ownedSource.bindingId 11) (.signed .i32 raw.nodeCount.toInt)).set
    (ownedSource.bindingId 12) (.signed .i32 workspace.expressionCapacity.toInt)).set
    (ownedSource.bindingId 13) (.signed .i32 workspace.typeOutputCount.toInt)

private def Finished (origin : State) (post : Int → Heap → World.State → List I32ArrayView → Prop)
    (completion : Completion) (after : State) : Prop :=
  ∃ result : Int, completion = .returned (some (.signed .i32 result)) ∧
    FreshCellFrame origin after ∧ post result after.heap after.world after.i32ArrayViews

/-- All fourteen actual local bindings are discharged by the shared
    proof-producing rule. The continuation sees only the symbolic environment
    and unchanged heap/world/view projections, never fresh numeric cell IDs. -/
theorem actualOwnedPrelude
    (raw : RawInputs) (workspace : RawWorkspace) (formed : origin.CellsWellFormed)
    (post : Int → Heap → World.State → List I32ArrayView → Prop)
    (continuation : ∀ state, LocalEnv origin state (entryValues raw workspace) →
      state.heap = origin.heap → state.world = origin.world → state.i32ArrayViews = origin.i32ArrayViews →
      StmtWP extractedProgram state entrySuffix (Finished origin post)) :
    ∃ result after, RunsExpr extractedProgram origin (ownedCall raw.value workspace.value)
      (.signed .i32 result) after ∧ FreshCellFrame origin after ∧ after.locals = origin.locals ∧
        post result after.heap after.world after.i32ArrayViews := by
  let callee := ({ origin with locals := [] }).bindLocals
    [(ownedSource.argumentId 0, raw.value), (ownedSource.argumentId 1, workspace.value)]
  have env : LocalEnv origin callee (argumentValues raw workspace) :=
    ((LocalEnv.clear formed).bind (ownedSource.argumentId 0) raw.value).bind
      (ownedSource.argumentId 1) workspace.value
  have body : StmtWP extractedProgram callee (ownedSource.body.getD .skip) (Finished origin post) := by
    core_facts [raw, workspace]
    core_env_lets env
    apply continuation <;> first | assumption | rfl
  obtain ⟨completion, completed, run, result, rfl, cells, observed⟩ := body
  exact ⟨result, restoreLocals origin completed,
    RunsExpr.call (by core_lookup) rfl (RunsExprs.values _) rfl run,
    cells.restoreLocals, rfl, observed⟩

#print axioms actualOwnedPrelude

end IRBodyOwnedProof
