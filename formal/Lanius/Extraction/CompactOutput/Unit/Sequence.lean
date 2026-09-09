import Lanius.Extraction.CompactOutput.Unit.Inputs
import Lanius.Extraction.CompactOutput.Unit.Word

namespace Lanius.Extraction.CompactOutput.Unit

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

theorem Owned.combine {capacity : Nat} {first second : List Nat} {position : Int} {contents : List Int}
    (owned : Owned memory
      (appendAll capacity second (appendAll capacity first position contents).position
        (appendAll capacity first position contents).contents).position
      (appendAll capacity second (appendAll capacity first position contents).position
        (appendAll capacity first position contents).contents).contents state) :
    Owned memory (appendAll capacity (first ++ second) position contents).position
      (appendAll capacity (first ++ second) position contents).contents state := by
  rw [(following_chunk capacity first second position contents).1,
    (following_chunk capacity first second position contents).2]
  exact owned

/-- Execute every statement after the cursor declaration. All calls are
derived from the checked helper functions and ordinary input contracts. -/
theorem Inputs.execute_tail (inputs : Inputs memory.base memory.outputCell memory.initialContents.length)
    (owned : Owned memory position contents before)
    (word : Word.Checked program byte digit)
    (bytes : Bytes.Checked program byte digit hex)
    (tokens : Tokens.Checked program byte digit word)
    (semantic : Assignments.Checked program byte digit word)
    (nodes : Nodes.Checked program byte digit word tokenTag stateTag)
    (tokenConstant : ParserTreeSource.constantValue program.core tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program.core stateTag 2) :
    ∃ after, Executes program.core before
        (tail ⟨word.source.function.id, bytes.source.function.id, tokens.source.function.id,
          semantic.source.function.id, nodes.source.function.id⟩)
        (.returned (some (.signed .i32 (appendAll inputs.capacity inputs.tailEncoding position contents).position))) after ∧
      after.cellEntry? memory.outputCell = some {
        id := memory.outputCell, value := some (.array (signedI32Values
          (appendAll inputs.capacity inputs.tailEncoding position contents).contents)) } ∧
      CellEffect memory.writes before after := by
  have rawFit : inputs.raw.tokens.length ≤ 2147483647 := by
    have := inputs.raw.inputRoom
    have := inputs.raw.lengthFit
    omega
  have canonicalFit : inputs.canonical.tokens.length ≤ 2147483647 := by
    have := inputs.canonical.inputRoom
    have := inputs.canonical.lengthFit
    omega
  obtain ⟨s1, r1, o1, e1⟩ := owned.bytes bytes 0 1 inputs.path.values inputs.capacity
    (by decide) (by decide) inputs.path.input inputs.path.inputRead inputs.path.lengthRead
    inputs.path.distinct inputs.path.lengthFit inputs.path.byteBound
    inputs.outputRead inputs.capacityRead inputs.room inputs.capacityFit
  obtain ⟨s2, r2, o2, e2⟩ := o1.word word 3 inputs.capacity inputs.source.values.length
    (by decide) inputs.source.lengthRead inputs.outputRead inputs.capacityRead inputs.room inputs.capacityFit inputs.source.lengthFit
  have o2 := o2.combine
  obtain ⟨s3, r3, o3, e3⟩ := o2.bytes bytes 2 3 inputs.source.values inputs.capacity
    (by decide) (by decide) inputs.source.input inputs.source.inputRead inputs.source.lengthRead
    inputs.source.distinct inputs.source.lengthFit inputs.source.byteBound
    inputs.outputRead inputs.capacityRead inputs.room inputs.capacityFit
  have o3 := o3.combine
  obtain ⟨s4, r4, o4, e4⟩ := o3.word word 6 inputs.capacity inputs.raw.tokens.length
    (by decide) inputs.raw.countRead inputs.outputRead inputs.capacityRead inputs.room inputs.capacityFit rawFit
  have o4 := o4.combine
  obtain ⟨s5, r5, o5, e5⟩ := o4.tokens tokens 4 5 6 inputs.raw.tokens inputs.raw.inputLength
    inputs.source.values.length inputs.capacity (by decide) (by decide) (by decide)
    inputs.raw.input inputs.raw.inputRead inputs.raw.lengthRead inputs.raw.countRead inputs.source.lengthRead
    inputs.raw.distinct inputs.raw.inputRoom inputs.raw.lengthFit inputs.source.lengthFit inputs.raw.fields
    inputs.outputRead inputs.capacityRead inputs.room inputs.capacityFit
  have o5 := o5.combine
  obtain ⟨s6, r6, o6, e6⟩ := o5.word word 9 inputs.capacity inputs.canonical.tokens.length
    (by decide) inputs.canonical.countRead inputs.outputRead inputs.capacityRead inputs.room inputs.capacityFit canonicalFit
  have o6 := o6.combine
  obtain ⟨s7, r7, o7, e7⟩ := o6.tokens tokens 7 8 9 inputs.canonical.tokens inputs.canonical.inputLength
    inputs.source.values.length inputs.capacity (by decide) (by decide) (by decide)
    inputs.canonical.input inputs.canonical.inputRead inputs.canonical.lengthRead inputs.canonical.countRead inputs.source.lengthRead
    inputs.canonical.distinct inputs.canonical.inputRoom inputs.canonical.lengthFit inputs.source.lengthFit inputs.canonical.fields
    inputs.outputRead inputs.capacityRead inputs.room inputs.capacityFit
  have o7 := o7.combine
  obtain ⟨s8, r8, o8, e8⟩ := o7.semantic semantic inputs.semantic.assignments inputs.semantic.inputLength inputs.capacity
    inputs.semantic.input inputs.semantic.inputRead inputs.semantic.lengthRead
    (by simpa only [inputs.semantic.countEqual] using inputs.canonical.countRead)
    inputs.semantic.distinct inputs.semantic.inputRoom inputs.semantic.lengthFit inputs.semantic.fields
    inputs.outputRead inputs.capacityRead inputs.room inputs.capacityFit
  have o8 := o8.combine
  obtain ⟨s9, r9, o9, e9⟩ := o8.word word 15 inputs.capacity inputs.nodes.records.length
    (by decide) inputs.nodes.nodesRead inputs.outputRead inputs.capacityRead inputs.room inputs.capacityFit inputs.nodes.nodesFit
  have o9 := o9.combine
  obtain ⟨after, r10, backing, effect⟩ := o9.nodes nodes tokenConstant stateConstant inputs.nodes.records
    inputs.nodes.words inputs.nodes.inputLength inputs.canonical.tokens.length inputs.capacity
    inputs.nodes.input inputs.nodes.offsets inputs.nodes.inputRead inputs.nodes.lengthRead inputs.nodes.offsetRead
    inputs.nodes.nodesRead inputs.canonical.countRead inputs.nodes.distinctInput inputs.nodes.distinctOffsets
    inputs.nodes.inputRoom inputs.nodes.inputFit canonicalFit inputs.nodes.nodesFit inputs.nodes.stored inputs.nodes.fields
    inputs.nodes.linked inputs.nodes.tokenBound inputs.outputRead inputs.capacityRead inputs.room inputs.capacityFit
  have run := executesSequence (executesExpression r1)
    (executesSequence (executesExpression r2)
      (executesSequence (executesExpression r3)
        (executesSequence (executesExpression r4)
          (executesSequence (executesExpression r5)
            (executesSequence (executesExpression r6)
              (executesSequence (executesExpression r7)
                (executesSequence (executesExpression r8)
                  (executesSequence (executesExpression r9)
                    (executesSequenceReturned (second := .skip) (executesReturnValue r10))))))))))
  have combined := following_chunk inputs.capacity
    ((((((((Bytes.encoding inputs.path.values ++ hexDigits inputs.source.values.length 8) ++
      Bytes.encoding inputs.source.values) ++ hexDigits inputs.raw.tokens.length 8) ++
      Tokens.encodeAll inputs.raw.tokens) ++ hexDigits inputs.canonical.tokens.length 8) ++
      Tokens.encodeAll inputs.canonical.tokens) ++ Assignments.encodeAll inputs.semantic.assignments) ++
      hexDigits inputs.nodes.records.length 8)
    (Nodes.encodeAll inputs.nodes.records) position contents
  rw [← combined.1] at run
  rw [← combined.2] at backing
  refine ⟨after, ?_, ?_, e1.trans (e2.trans (e3.trans (e4.trans (e5.trans
    (e6.trans (e7.trans (e8.trans (e9.trans (effect.weaken (by intro cell found; exact Or.inl found))))))))))⟩
  · simpa only [tail, assignThen, bytesCall, wordCall, tokensCall, semanticCall, nodesCall,
      returned, Inputs.tailEncoding, List.append_assoc] using run
  · simpa only [Inputs.tailEncoding, List.append_assoc] using backing

end Lanius.Extraction.CompactOutput.Unit
