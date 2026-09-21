import Lanius.X86.Machine.ScalarEncoding

namespace Lanius.X86.Machine.ScalarEncodingComparisonTests

open Lanius.X86
open Lanius.X86.Machine

example : setConditionBytes 4 0 = [15, 148, 192] := by decide

example (code : Fin 16) (destination : Register) : decode (setConditionBytes code destination) = some (.setCondition code destination, (setConditionBytes code destination).length) := setCondition_decodes code destination

example : compareBytes 0 1 = [57, 200] := by decide

example (left right : Register) : decode (compareBytes left right) = some (.compare32 left right, (compareBytes left right).length) := compare_decodes left right

example (before : State) (left right : Register) (size : Nat) : (before.compare32 left right size).flags = subtractFlags before.flags ((before.registers left).setWidth 32) ((before.registers right).setWidth 32) := compare32_flags before left right size

example (before after : State) (left right : Register) (loaded : CodeAt before.memory before.rip (compareBytes left right)) (result : after = execute (.compare32 left right) (compareBytes left right).length before) : Step before after := compare_step before after left right loaded result

end Lanius.X86.Machine.ScalarEncodingComparisonTests
