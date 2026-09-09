import Lanius.Extraction.CompactOutput.Chunks
import Lanius.Extraction.CompactOutput.Word.Assign
import Lanius.Extraction.CompactOutput.Word.Chunks
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.CompactOutput.Chunks

open Lanius.Extraction.CompactOutput

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``appendAll_append, ``appendAll_hexByte, ``Word.assign_word,
      ``Word.appendAll_sentinel, ``Word.appendAll_word_sentinel,
      ``Word.appendAll_following_word] do
    unless (← Lean.getEnv).contains name do
      throwError "Missing chunk theorem {name}"
    for axiomName in ← Lean.collectAxioms name do
      unless standard.contains axiomName do
        throwError "Chunk theorem {name} depends on {axiomName}"
  Lean.logInfo "Six chunk/field composition and execution theorems: standard axioms only."

end Lanius.Extraction.Tests.CompactOutput.Chunks
