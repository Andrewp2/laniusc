import verified_compiler.tests.direct_ir_body_production_main_void
import Lanius.Semantics.EffectProof

namespace IRBodyProductionProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyProductionInputs
open IREventStoreProof

private def statementSource := Extracted.«lowering::body_statement».Functions.«statement».core
private def entrySource := Extracted.«lowering::body_statement».Functions.«lower_list_entry».core
private def listSource := Extracted.«lowering::body_statement».Functions.«statement_list».core
def terminalTag : Option Nat → Value
  | none => IRBodyProductionInputs.returnVoid
  | some root => IRBodyProductionInputs.returnValue root
def terminalLeaf (root : Option Nat) (context output : Value) (position : Int) (depth : Nat) : Expr :=
  match root with
  | none => voidCall context output position
  | some root => .call Extracted.«lowering::body_statement».Functions.«return_value».core.id
      [.value context, .value (.signed .i32 root), .value output,
        .value (.signed .i32 position), .value (.signed .i32 depth)]
def terminalStatement (context : Value) (node : Nat) (output : Value) (position : Int) (depth : Nat) : Expr :=
  .call statementSource.id [.value context, .value (.signed .i32 node), .value output,
    .value (.signed .i32 position), .value (.signed .i32 depth)]
def terminalListEntry (first rest : Nat) : Value :=
  source_value Extracted.«verified::surface_statement».Types.«ListEntry».mk
    [.signed .i32 first, .signed .i32 rest]
def terminalEntryCall (context : Value) (first rest : Nat) (output : Value) (position : Int) (depth : Nat) : Expr :=
  .call entrySource.id [.value context, .value (terminalListEntry first rest), .value output,
    .value (.signed .i32 position), .value (.signed .i32 depth)]
def terminalListCall (context : Value) (list : Nat) (output : Value) (position : Int) (depth : Nat) : Expr :=
  .call listSource.id [.value context, .value (.signed .i32 list), .value output,
    .value (.signed .i32 position), .value (.signed .i32 depth)]

/-- Source-selected pure queries and the one proved return phase compose
    through the actual statement, without per-binding state bookkeeping. -/
theorem actualTerminalStatement (input : Inputs) (workspace : Workspace) (locals : Value)
    (node depth : Nat) (positive : 0 < depth) (fits : depth < 2 ^ 31) (root : Option Nat)
    (query : ∀ {current : State}, current.heap = before.heap → current.CellsWellFormed → ∃ after,
      RunsExpr extractedProgram current (.call Extracted.«verified::surface_statement».Functions.«read».core.id
        [.value input.tree.value, .value (.signed .i32 node)]) (terminalTag root) after ∧ PureFrame current after)
    (writer : ∀ {current : State}, current.heap = before.heap → current.i32ArrayViews = before.i32ArrayViews →
      current.CellsWellFormed → ∃ after,
      RunsExpr extractedProgram current (terminalLeaf root (bodyContext input workspace locals) output position depth)
        result after ∧ MemoryEffect relation current after)
    (formed : before.CellsWellFormed) : ∃ after,
    RunsExpr extractedProgram before (terminalStatement (bodyContext input workspace locals) node output position depth)
      result after ∧ MemoryEffect relation before after := by
  cases root <;> core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) statementSource as callee
  all_goals core_effect (by assumption)

/-- Only the terminal ListEnd query is new here; the statement phase is reused. -/
theorem actualTerminalEntry (input : Inputs) (workspace : Workspace) (locals : Value)
    (first rest depth : Nat) (positive : 1 < depth) (fits : depth < 2 ^ 31) (root : Option Nat)
    (query : ∀ {current : State}, current.heap = before.heap → current.CellsWellFormed → ∃ after,
      RunsExpr extractedProgram current (.call Extracted.«verified::surface_statement».Functions.«read».core.id
        [.value input.tree.value, .value (.signed .i32 first)]) (terminalTag root) after ∧ PureFrame current after)
    (ending : ∀ {current : State}, current.heap = before.heap → current.CellsWellFormed → ∃ after,
      RunsExpr extractedProgram current (.call Extracted.«verified::surface_statement».Functions.«statement_list».core.id
        [.value input.tree.value, .value (.signed .i32 rest)]) listEnd after ∧ PureFrame current after)
    (writer : ∀ {current : State}, current.heap = before.heap → current.i32ArrayViews = before.i32ArrayViews →
      current.CellsWellFormed → ∃ after,
      RunsExpr extractedProgram current (terminalLeaf root (bodyContext input workspace locals) output position (depth - 1))
        result after ∧ MemoryEffect relation current after)
    (formed : before.CellsWellFormed) : ∃ after,
    RunsExpr extractedProgram before (terminalEntryCall (bodyContext input workspace locals) first rest output position depth)
      result after ∧ MemoryEffect relation before after := by
  have decrement := eval_i32_subNat extractedProgram.target depth 1 (by omega) fits
  have lower {current : State} (heap : current.heap = before.heap)
      (views : current.i32ArrayViews = before.i32ArrayViews) (formed : current.CellsWellFormed) :=
    actualTerminalStatement input workspace locals first (depth - 1) (by omega) (by omega) root
      (fun same formed => query (same.trans heap) formed)
      (fun same sameViews formed => writer (same.trans heap) (sameViews.trans views) formed) formed
  cases root <;> core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) entrySource as callee
  all_goals core_effect (by assumption)

/-- ListMore selects that same terminal entry, for both return tags. -/
theorem actualTerminalList (input : Inputs) (workspace : Workspace) (locals : Value)
    (list first rest depth : Nat) (positive : 1 < depth) (fits : depth < 2 ^ 31) (root : Option Nat)
    (query : ∀ {current : State}, current.heap = before.heap → current.CellsWellFormed → ∃ after,
      RunsExpr extractedProgram current (.call Extracted.«verified::surface_statement».Functions.«read».core.id
        [.value input.tree.value, .value (.signed .i32 first)]) (terminalTag root) after ∧ PureFrame current after)
    (ending : ∀ {current : State}, current.heap = before.heap → current.CellsWellFormed → ∃ after,
      RunsExpr extractedProgram current (.call Extracted.«verified::surface_statement».Functions.«statement_list».core.id
        [.value input.tree.value, .value (.signed .i32 rest)]) listEnd after ∧ PureFrame current after)
    (reading : ∀ {current : State}, current.heap = before.heap → current.CellsWellFormed → ∃ after,
      RunsExpr extractedProgram current (.call Extracted.«verified::surface_statement».Functions.«statement_list».core.id
        [.value input.tree.value, .value (.signed .i32 list)]) (listMore first rest) after ∧ PureFrame current after)
    (writer : ∀ {current : State}, current.heap = before.heap → current.i32ArrayViews = before.i32ArrayViews →
      current.CellsWellFormed → ∃ after,
      RunsExpr extractedProgram current (terminalLeaf root (bodyContext input workspace locals) output position (depth - 1))
        result after ∧ MemoryEffect relation current after)
    (formed : before.CellsWellFormed) : ∃ after,
    RunsExpr extractedProgram before (terminalListCall (bodyContext input workspace locals) list output position depth)
      result after ∧ MemoryEffect relation before after := by
  have lower {current : State} (heap : current.heap = before.heap)
      (views : current.i32ArrayViews = before.i32ArrayViews) (formed : current.CellsWellFormed) :=
    actualTerminalEntry input workspace locals first rest depth positive fits root
      (fun same formed => query (same.trans heap) formed)
      (fun same formed => ending (same.trans heap) formed)
      (fun same sameViews formed => writer (same.trans heap) (sameViews.trans views) formed) formed
  cases root <;> core_call_framed (RunsExpr.callEffect (MemoryEffect.scopeStable _)) listSource as callee
  all_goals core_effect (by assumption)

/-- The connected Void consumer discharges all query and writer premises from
    original native topology and the actual guarded writer. -/
theorem actualVoidTerminalList (input : Inputs) (workspace : Workspace) (locals : Value)
    (topology : TerminalTopology input before.heap declaration)
    (optional : topology.optionalNode.production = 91) (kind : input.signature.result = .Void)
    (depth : Nat) (positive : 1 < depth) (fits : depth < 2 ^ 31) (output : Context before)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) : ∃ after,
    RunsExpr extractedProgram before
      (terminalListCall (bodyContext input workspace locals) topology.list output.value output.position depth)
      (.signed .i32 (output.position + 1 : Nat)) after ∧ Appended output (returnEvent false) before after := by
  apply actualTerminalList input workspace locals topology.list topology.statement topology.rest depth positive fits none
  · intro current same formed
    exact actualReturnVoid topology.statementNode topology.statementProduction topology.statementBound
      topology.optionalChild topology.optionalKind topology.optionalNode topology.optionalIndex optional same formed
  · intro current same formed
    exact actualListEnd topology.restNode topology.restProduction same formed
  · intro current same formed
    have firstPositive : 0 ≤ topology.firstChild.payload := by rw [topology.firstIndex]; exact Int.natCast_nonneg _
    have restPositive : 0 ≤ topology.restChild.payload := by rw [topology.restIndex]; exact Int.natCast_nonneg _
    simpa only [topology.firstIndex, topology.restIndex] using
      actualListMore topology.listNode topology.listProduction topology.listBound
        topology.firstChild topology.restChild topology.firstKind topology.restKind firstPositive restPositive same formed
  · intro current same views formed
    exact actualVoid input workspace locals kind (output.reheap same) formed
      (by rw [same]; exact unique) (views.trans noViews)
  · exact formed

#print axioms actualTerminalStatement
#print axioms actualTerminalEntry
#print axioms actualTerminalList
#print axioms actualVoidTerminalList

end IRBodyProductionProof
