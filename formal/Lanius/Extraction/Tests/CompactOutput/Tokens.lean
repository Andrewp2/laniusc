import Lanius.Extraction.CompactOutput.Tokens.Failure
import Lanius.Extraction.CompactOutput.Tokens.Success
import Lanius.Extraction.CompactOutput.Tokens.State
import Lanius.Extraction.CompactOutput.Tokens.Loop
import Lanius.Extraction.CompactOutput.Tokens.Guard
import Lanius.Extraction.CompactOutput.Tokens.Function
import Lanius.Extraction.CompactOutput.Tokens.Call
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.CompactOutput.Tokens

open Lanius.Extraction.CompactOutput

run_elab do
  let standard : Array Lean.Name := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``Tokens.row_index, ``Tokens.read_row, ``Tokens.fields_valid,
      ``Tokens.initialize_fields, ``Tokens.write_fields, ``Tokens.Entry.write,
      ``Tokens.Entry.failure, ``Tokens.Entry.success, ``Tokens.Owned.transition,
      ``Tokens.Owned.condition, ``Tokens.execute_loop, ``Tokens.entry_guard,
      ``Tokens.entry_guard_passes, ``Tokens.entry_guard_rejects,
      ``Tokens.Function.Entry.invariant, ``Tokens.Function.Entry.execute, ``Tokens.Checked.write] do
    unless (← Lean.getEnv).contains name do throwError "Missing token serializer theorem {name}"
    for axiomName in ← Lean.collectAxioms name do
      unless standard.contains axiomName do throwError "Token serializer theorem {name} depends on {axiomName}"
  Lean.logInfo "Token reads, scoped writes, and complete successful/failing iterations use standard axioms only."

end Lanius.Extraction.Tests.CompactOutput.Tokens
