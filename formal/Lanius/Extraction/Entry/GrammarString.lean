import Lanius.Extraction.Entry.GrammarLoop
import Lanius.Extraction.CanonicalTokens.Ascii.Entry

namespace Lanius.Extraction.Entry.Grammar

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

/-- The string-backed initializer produces the exact expected packed words.
The decoding equality concerns the literal bytes, not an assumed execution. -/
theorem stringInitializer (program : Program) (before : State) (text : String)
    (binding : Lanius.VarId) (words : List Int)
    (wellFormed : StateWellFormed before)
    (found : before.local? binding = some (.string text))
    (size : (Lanius.World.utf8Bytes text).length = words.length * 4)
    (decoded : decodeI32Array words.length (Lanius.World.utf8Bytes text) = .ok (signedI32Values words)) :
    ∃ after, Evaluates program before
      (.i32SliceFromRawParts (.stringDataPtr (.local binding)) (.value (.signed .i32 words.length)))
      (.slice (.scalar (.signed .i32)) before.nextCell [] 0 words.length) after ∧
      after.cellEntry? before.nextCell = some {
        id := before.nextCell, value := some (.array (signedI32Values words)) } ∧
      StateWellFormed after ∧ after.locals = before.locals ∧
      (∀ cell, cell < before.nextCell → after.cellEntry? cell = before.cellEntry? cell) ∧
      after.nextCell = before.nextCell + 1 ∧ after.world = before.world ∧
      CellDomainExtension before after ∧ (∀ id, after.local? id = before.local? id) ∧
      I32BorrowedResources before words.length after := by
  obtain ⟨actual, address, pointed, after, count, pointer, locals, cells, raw, encoded,
      actualDecoded, contents, afterWF, afterLocals, preserved, nextCell, world, domain, localValues, resources⟩ :=
    CanonicalTokens.Ascii.string_words before text words.length wellFormed size
  have exactWords : signedI32Values actual = signedI32Values words :=
    Except.ok.inj (actualDecoded.symm.trans decoded)
  rw [exactWords] at contents
  have textResult : Evaluates program before (.local binding) (.string text) before :=
    evaluatesLocal found
  exact ⟨after, evaluatesI32SliceFromRawParts (evaluatesStringDataPtr textResult pointer)
      (show Evaluates program pointed (.value (.signed .i32 words.length))
        (.signed .i32 words.length) pointed from evaluatesValue) raw,
    contents, afterWF, afterLocals, preserved, nextCell, world, domain, localValues, resources⟩

end Lanius.Extraction.Entry.Grammar
