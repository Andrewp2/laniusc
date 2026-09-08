import Lanius.Extraction.Parser.Derivation.Advance

namespace Lanius.Extraction.ParserDerivation

open Lanius.Compiler.Parser

/-- Physical output partition during the backwards walk. Unfinished slots
    are unconstrained; finished slots encode the accumulated child suffix. -/
def ReaderRuntime.OutputLayout (reader : ReaderRuntime) (header trailing : List Int)
    (remaining : Nat) (suffix : List Child) : Prop :=
  header.length = reader.offset + 4 ∧ ∃ pending : List Int,
    pending.length = remaining * 3 ∧
    reader.outputValues = header ++ pending ++ suffix.flatMap derivationChildWords ++ trailing

private theorem split_three (pending : List Int) (length : pending.length = (remaining + 1) * 3) :
    ∃ leading tag payload kind, pending = leading ++ [tag, payload, kind] ∧
      leading.length = remaining * 3 := by
  have reversedLength : pending.reverse.length = (remaining + 1) * 3 := by simpa using length
  cases reversed : pending.reverse with
  | nil => simp [reversed] at reversedLength
  | cons kind rest =>
    cases rest with
    | nil => simp [reversed] at reversedLength; omega
    | cons payload rest =>
      cases rest with
      | nil => simp [reversed] at reversedLength; omega
      | cons tag leading =>
        refine ⟨leading.reverse, tag, payload, kind, ?_, ?_⟩
        · have equality := congrArg List.reverse reversed
          simpa [List.reverse_cons, List.append_assoc] using equality
        · simp only [reversed, List.length_cons, List.length_reverse] at reversedLength ⊢
          omega

/-- One checked three-word store consumes the final unfinished slot and
    prepends its child to the encoded suffix, preserving the other regions. -/
theorem ReaderRuntime.OutputLayout.advance {reader : ReaderRuntime}
    (layout : reader.OutputLayout header trailing (remaining + 1) suffix) (child : Child) :
    (reader.writeChild child remaining).OutputLayout header trailing remaining (child :: suffix) := by
  obtain ⟨headerLength, pending, pendingLength, contents⟩ := layout
  obtain ⟨leading, tag, payload, kind, split, leadingLength⟩ := split_three pending pendingLength
  refine ⟨headerLength, leading, leadingLength, ?_⟩
  have before : reader.outputValues = (header ++ leading) ++ [tag, payload, kind] ++
      suffix.flatMap derivationChildWords ++ trailing := by
    simpa only [split, List.append_assoc] using contents
  have written := reader.writeChild_suffix (remaining := remaining) before
    (by simp only [List.length_append, headerLength, leadingLength]) child
  simpa only [List.append_assoc] using written

/-- At zero remaining slots, no unconstrained words remain in the record. -/
theorem ReaderRuntime.OutputLayout.finish {reader : ReaderRuntime}
    (layout : reader.OutputLayout header trailing 0 children) :
    reader.outputValues = header ++ children.flatMap derivationChildWords ++ trailing := by
  obtain ⟨_, pending, length, contents⟩ := layout
  have empty : pending = [] := by cases pending <;> simp_all
  simpa only [empty, List.append_nil] using contents

end Lanius.Extraction.ParserDerivation
