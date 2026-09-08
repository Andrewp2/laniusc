import Lanius.Extraction.SemanticTokens.Collect.NodeStep

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

def nodeLoop (symbols : Symbols) : Stmt :=
  .whileLoop (binary .notEqual (read 13) (read 7)) (nodeBody symbols)

/-- The entire postorder record loop terminates and makes exactly the
selected tree's assignment writes. Record setup and every child execution
are derived inside the induction, not assumed successful. -/
theorem node_loop {memory : NodeMemory} (program : Program) (symbols : Symbols)
    (tokenTag : ParserTreeSource.constantValue program symbols.childToken 1)
    (stateTag : ParserTreeSource.constantValue program symbols.childState 2)
    (held : NodeOwned memory index before) (bound : index ≤ memory.data.collection.records.length) :
    ∃ after, Executes program before (nodeLoop symbols) .next after ∧
      NodeOwned memory memory.data.collection.records.length after ∧ CellEffect memory.writes before after := by
  have nodeRead := local_evaluates program (Assertion.localPointsTo_local _ _ _ _ held.node)
  have countRead := local_evaluates program held.nodeCount
  have condition : Evaluates program before (binary .notEqual (read 13) (read 7))
      (.boolean (!(Int.ofNat index == Int.ofNat memory.data.collection.records.length))) before := by
    apply evaluatesEagerBinary (by decide) (by decide) nodeRead countRead
    simp [evalBinaryValue, scalarEqual]
  by_cases done : index = memory.data.collection.records.length
  · subst index
    exact ⟨before, executesWhileFalse (by simpa using condition), held, CellEffect.refl held.wellFormed⟩
  · have active : index < memory.data.collection.records.length := by omega
    let record := memory.data.collection.records.get ⟨index, active⟩
    have found : memory.data.collection.records[index]? = some record := by simp [record]
    have conditionTrue : Evaluates program before (binary .notEqual (read 13) (read 7)) (.boolean true) before := by
      simpa only [show (Int.ofNat index == Int.ofNat memory.data.collection.records.length) = false from
        beq_eq_false_iff_ne.mpr (by intro same; exact done (Int.ofNat.inj same)), Bool.not_false] using condition
    obtain ⟨middle, stepRun, next, stepEffect⟩ := node_step program symbols tokenTag stateTag held found
    obtain ⟨after, restRun, final, restEffect⟩ := node_loop program symbols tokenTag stateTag next (by omega)
    exact ⟨after, executesWhileTrue conditionTrue stepRun restRun, final, stepEffect.trans restEffect⟩
termination_by memory.data.collection.records.length - index

theorem NodeOwned.finished {memory : NodeMemory}
    (held : NodeOwned memory memory.data.collection.records.length state) :
    state.cellEntry? memory.data.outputCell = some {
      id := memory.data.outputCell,
      value := some (.array (signedI32Values (written memory.data.original memory.data.tokens.length
        (memory.data.collection.records.flatMap RecordVisit.uses)))) } := by
  simpa only [priorUses, List.take_length] using held.backing

end Lanius.Extraction.SemanticTokens.Collect
