import Lanius.Extraction.CompactOutput.Nodes.ChildSetup

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

def headerThen (wordId : FunctionId) (continuation : Stmt) : Stmt :=
  .sequence (.expression (headerWrite wordId (read 11)))
    (.sequence (.expression (headerWrite wordId (recordRead 1)))
      (.sequence (.expression (headerWrite wordId (recordRead 2)))
        (.sequence (.expression (headerWrite wordId (read 12)))
          (.sequence (.ifThenElse failureGuard (returned negativeOne) .skip) continuation))))

/-- This is precisely the suffix of the source-checked outer iteration. -/
theorem step_header (wordId : FunctionId) (tokenTag stateTag : Lanius.ConstantId) :
    step wordId tokenTag stateTag =
      .letLocal 10 i32 (.index (read 2) (read 9))
        (.sequence (.ifThenElse recordGuard (returned negativeOne) .skip)
          (.letLocal 11 i32 (.index (read 0) (read 10)) (.letLocal 12 i32 (recordRead 3)
            (.sequence (.ifThenElse childrenGuard (returned negativeOne) .skip)
              (headerThen wordId (.letLocal 13 i32 (number 0)
                (.sequence (childLoop wordId tokenTag stateTag)
                  (.sequence (.expression increment) .skip)))))))) := rfl

theorem header_failure (owned : HeaderOwned memory position contents before)
    (word : Word.Checked program byte digit)
    (full : appendAll memory.capacity (encodeHeader memory.record) position contents = .full retained)
    (continuation : Stmt) :
    ∃ after, Executes program.core before (headerThen word.source.function.id continuation)
        (.returned (some (.signed .i32 (-1)))) after ∧
      after.cellEntry? memory.outputCell = some {
        id := memory.outputCell, value := some (.array (signedI32Values retained)) } ∧
      CellEffect memory.writes before after := by
  obtain ⟨first, second, third, after, firstRun, secondRun, thirdRun, lastRun, held, effect⟩ := write_header owned word
  have nextRead := local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ held.cursor)
  have backing := held.backing
  rw [full] at nextRead backing
  have failed : Evaluates program.core after failureGuard (.boolean true) after := by
    apply evaluatesEagerBinary (by decide) (by decide) nextRead (negativeOne_evaluates program.core after)
    simp [evalBinaryValue, evalSignedBinary, AppendOutcome.position]
  exact ⟨after, executesSequence (executesExpression firstRun)
    (executesSequence (executesExpression secondRun)
      (executesSequence (executesExpression thirdRun)
        (executesSequence (executesExpression lastRun)
          (executesSequenceReturned (executesIfTrue failed
            (executesSequenceReturned (executesReturnValue (negativeOne_evaluates program.core after)))))))),
    backing, effect⟩

theorem header_success {memory : HeaderMemory} {refs : References memory}
    {result : Int} {updated : List Int}
    (owned : HeaderOwned memory position contents before)
    (refsOwned : ReferencesOwned refs before) (word : Word.Checked program byte digit)
    (done : appendAll memory.capacity (encodeHeader memory.record) position contents = .done result updated) :
    ∃ written, HeaderOwned memory result updated written ∧ ReferencesOwned refs written ∧
      CellEffect memory.writes before written ∧
      ∀ continuation completion after, Executes program.core written continuation completion after →
        Executes program.core before (headerThen word.source.function.id continuation) completion after := by
  obtain ⟨first, second, third, written, firstRun, secondRun, thirdRun, lastRun, held, effect⟩ := write_header owned word
  have nonnegative : 0 ≤ result := appendAll_done_nonnegative _ (by
    simp only [encodeHeader, hexDigits, List.cons_append, ne_eq, List.cons_ne_nil, not_false_eq_true]) done
  rw [done] at held
  have nextRead := local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ held.cursor)
  have passed : Evaluates program.core written failureGuard (.boolean false) written := by
    apply evaluatesEagerBinary (by decide) (by decide) nextRead (negativeOne_evaluates program.core written)
    simp only [evalBinaryValue, evalSignedBinary, AppendOutcome.position, beq_self_eq_true,
      if_true, Except.ok.injEq, Value.boolean.injEq]
    exact decide_eq_false (by omega)
  refine ⟨written, held, refsOwned.preserve owned effect, effect, ?_⟩
  intro continuation completion after tailRun
  exact executesSequence (executesExpression firstRun)
    (executesSequence (executesExpression secondRun)
      (executesSequence (executesExpression thirdRun)
        (executesSequence (executesExpression lastRun)
          (executesSequence (executesIfFalse passed (executesSkip _ _)) tailRun))))

end Lanius.Extraction.CompactOutput.Nodes
