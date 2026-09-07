import Lanius.Extraction.CanonicalTokens.Dispatch.Rule

namespace Lanius.Extraction.CanonicalTokens.Dispatch

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

def selected (program : Program) (source : List Int) (start width : Nat) : List Rule → Option Int
  | [] => none
  | rule :: rest =>
      if Ascii.matchesBytes source start (rule.spelling width) then some (tag program rule.kind)
      else selected program source start width rest

def selectedCompletion : Option Int → Completion
  | none => .next
  | some kind => .returned (some (.signed .i32 kind))

/-- A complete same-length choice list executes in source order. Mismatches
preserve the input for subsequent choices, and a successful rule returns
immediately. The proof is independent of the number or spelling of keywords. -/
theorem executes_choices (program : Program) (matcher : FunctionId)
    (before : State) (sourceCell : CellId) (source : List Int) (start width : Nat) (rules : List Rule)
    (found : program.function? matcher = some (Ascii.sourceFunction matcher))
    (valid : ∀ rule ∈ rules, ValidRule program width rule)
    (wellFormed : StateWellFormed before)
    (sourceLocal : before.local? 0 = some
      (.slice (.scalar (.signed .i32)) sourceCell [] 0 source.length))
    (sourceContents : before.cellEntry? sourceCell = some {
      id := sourceCell, value := some (.array (signedI32Values source)) })
    (startLocal : before.local? 1 = some (.signed .i32 start))
    (capacity : start + width ≤ source.length) (bounded : source.length ≤ 2147483647) :
    ∃ after, Executes program before (choices matcher width rules)
      (selectedCompletion (selected program source start width rules)) after ∧ CellEffect CellSet.empty before after := by
  induction rules generalizing before with
  | nil => exact ⟨before, executesSkip program before, CellEffect.refl wellFormed⟩
  | cons rule rest ih =>
      have headValid := valid rule (by simp)
      have tailValid : ∀ rule ∈ rest, ValidRule program width rule :=
        fun rule member => valid rule (List.mem_cons_of_mem _ member)
      obtain ⟨middle, tested, frame⟩ := evaluates_condition program matcher before sourceCell source
        start width rule found headValid wellFormed sourceLocal sourceContents startLocal capacity bounded
      cases matchesHead : Ascii.matchesBytes source start (rule.spelling width) with
      | false =>
          rw [matchesHead] at tested
          obtain ⟨after, run, tailFrame⟩ := ih middle tailValid frame.wellFormed
            (frame.empty_preserves_local wellFormed sourceLocal)
            (frame.empty_preserves_entry wellFormed sourceContents)
            (frame.empty_preserves_local wellFormed startLocal)
          refine ⟨after, ?_, frame.trans tailFrame⟩
          simpa only [choices, selected, matchesHead, Bool.false_eq_true, ↓reduceIte] using
            executesSequence (executesIfFalse tested (executesSkip program middle)) run
      | true =>
          rw [matchesHead] at tested
          refine ⟨middle, ?_, frame⟩
          simpa only [choices, selected, matchesHead, ↓reduceIte, selectedCompletion] using
            (executesSequenceReturned (second := choices matcher width rest)
              (executesIfTrue tested (executes_returned program middle rule headValid)))

end Lanius.Extraction.CanonicalTokens.Dispatch
