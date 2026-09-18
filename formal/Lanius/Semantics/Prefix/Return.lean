import Lanius.Semantics.Prefix

namespace Lanius.Semantics.Prefix
open Lanius.Core Lanius.CallContracts

/-- A return reached through a proved prefix completes the enclosing
statement and skips its remaining tails. Closing lexical scopes changes only
local mappings; every caller observes the same final cells, heap, and world. -/
theorem Reaches.completeReturn (reached : Reaches program before statement ready continuation)
    (run : Executes program ready continuation (.returned value) after) :
    ∃ final, Executes program before statement (.returned value) final ∧
      ∀ caller, restoreLocals caller final = restoreLocals caller after := by
  induction reached with
  | here => exact ⟨after, run, fun _ => rfl⟩
  | sequenceHead _ ih =>
    obtain ⟨final, executed, same⟩ := ih run
    exact ⟨final, executesSequenceReturned executed, same⟩
  | sequence first _ ih =>
    obtain ⟨final, executed, same⟩ := ih run
    exact ⟨final, executesSequence first executed, same⟩
  | letLocal initializer _ ih =>
    obtain ⟨final, executed, same⟩ := ih run
    exact ⟨_, executesLetLocal initializer executed, fun caller => same caller⟩
  | letUninitialized _ ih =>
    obtain ⟨final, executed, same⟩ := ih run
    exact ⟨_, executesLetUninitialized executed, fun caller => same caller⟩
  | ifTrue condition _ ih =>
    obtain ⟨final, executed, same⟩ := ih run
    exact ⟨final, executesIfTrue condition executed, same⟩

end Lanius.Semantics.Prefix
