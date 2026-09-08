import Lanius.Extraction.SemanticTokens.Collect.ChildStep

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Compiler.Parser

def childLoop (symbols : Symbols) : Stmt :=
  .whileLoop (binary .notEqual (read 17) (read 15)) (childBody symbols)

/-- Termination and exact assignment history for the complete child loop.
The remaining recognized path fixes the cursor at each iteration; uniqueness
derives every token branch's unused-slot check. No iteration is assumed to run. -/
theorem child_loop {memory : ChildMemory} {record : RecordVisit}
    (program : Program) (symbols : Symbols)
    (tokenTag : ParserTreeSource.constantValue program symbols.childToken 1)
    (stateTag : ParserTreeSource.constantValue program symbols.childState 2)
    (found : memory.data.collection.records[nodeIndex]? = some record)
    (held : ChildOwned memory record nodeIndex index position visited before)
    (bound : index ≤ record.children.length)
    (path : VisitPath memory.data.grammar.grammar (memory.data.tokens.map Token.kind)
      (record.children.drop index) position record.finish)
    (unique : ((visited ++ (record.children.drop index).flatMap ChildVisit.uses ++ remaining).map Use.slot).Nodup) :
    ∃ after, Executes program before (childLoop symbols) .next after ∧
      ChildOwned memory record nodeIndex record.children.length record.finish
        (visited ++ (record.children.drop index).flatMap ChildVisit.uses) after ∧
      CellEffect memory.writes before after := by
  have cursorRead := local_evaluates program (Assertion.localPointsTo_local _ _ _ _ held.child)
  have countRead := local_evaluates program held.childCount
  have condition : Evaluates program before (binary .notEqual (read 17) (read 15))
      (.boolean (!(Int.ofNat index == Int.ofNat record.children.length))) before := by
    apply evaluatesEagerBinary (by decide) (by decide) cursorRead countRead
    simp [evalBinaryValue, scalarEqual]
  by_cases done : index = record.children.length
  · subst index
    have finishEq : position = record.finish := by
      have nilPath : VisitPath memory.data.grammar.grammar (memory.data.tokens.map Token.kind) [] position record.finish :=
        by simpa only [List.drop_length] using path
      cases nilPath
      rfl
    subst position
    exact ⟨before, executesWhileFalse (by simpa using condition),
      by simpa only [List.drop_length, List.flatMap_nil, List.append_nil] using held,
      CellEffect.refl held.wellFormed⟩
  · have active : index < record.children.length := by omega
    let child := record.children.get ⟨index, active⟩
    have childFound : record.children[index]? = some child := by simp [child]
    have dropped : record.children.drop index = child :: record.children.drop (index + 1) :=
      List.drop_eq_getElem_cons active
    rw [dropped] at path
    cases path with
    | cons valid tail =>
      have conditionTrue : Evaluates program before (binary .notEqual (read 17) (read 15)) (.boolean true) before := by
        simpa only [show (Int.ofNat index == Int.ofNat record.children.length) = false from
          beq_eq_false_iff_ne.mpr (by intro same; exact done (Int.ofNat.inj same)), Bool.not_false] using condition
      have stepUnique : ((visited ++ child.uses ++
          ((record.children.drop (index + 1)).flatMap ChildVisit.uses ++ remaining)).map Use.slot).Nodup := by
        simpa only [dropped, List.flatMap_cons, List.append_assoc] using unique
      obtain ⟨middle, stepped, next, stepEffect⟩ := child_step program symbols tokenTag stateTag found childFound held stepUnique
      have restUnique : (((visited ++ child.uses) ++
          (record.children.drop (index + 1)).flatMap ChildVisit.uses ++ remaining).map Use.slot).Nodup := by
        simpa only [List.append_assoc] using stepUnique
      obtain ⟨after, finished, final, restEffect⟩ := child_loop program symbols tokenTag stateTag found next
        (by omega) tail restUnique
      refine ⟨after, executesWhileTrue conditionTrue stepped finished, ?_, stepEffect.trans restEffect⟩
      simpa only [dropped, List.flatMap_cons, List.append_assoc] using final
termination_by record.children.length - index

end Lanius.Extraction.SemanticTokens.Collect
