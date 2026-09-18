import Lanius.X86.Storage.Pointer
import Lanius.X86.Encode.Direct
import Lanius.X86.Encode.Condition
import Lanius.X86.Encode.Boolean
import Lanius.X86.Lower.Condition
import Lanius.X86.Lower.Operation
import Lanius.X86.Encode.Guarded
import Lean.Elab.Term
import Lean.Util.CollectAxioms

namespace Lanius.X86.Tests.Boolean

open Machine

-- Neutral REX must not disappear: without it, register codes 4–7 mean
-- unsupported legacy high bytes; with it they name SPL/BPL/SIL/DIL.
example : decode [0x0f, 0x94, 0xc4] = none := by decide
example : decode [0x40, 0x0f, 0x94, 0xc4] = some (.setCondition 4 4, 4) := by decide
example : decode [0x40, 0x0f, 0x94, 0xfc] = some (.setCondition 4 4, 4) := by decide
example : decode [0x45, 0x0f, 0x95, 0xc7] = some (.setCondition 5 15, 4) := by decide
example : decode [0x0f, 0xb6, 0xc4] = none := by decide
example : decode [0x40, 0x0f, 0xb6, 0xc4] = some (.zeroExtendByte 0 4, 4) := by decide
example : decode [0x48, 0x0f, 0xb6, 0xc4] = some (.zeroExtendByte 0 4, 4) := by decide
example : decode [0x45, 0x0f, 0xb6, 0xee] = some (.zeroExtendByte 13 14, 4) := by decide
example : decode [0x0f, 0xb6, 0xe0] = some (.zeroExtendByte 4 0, 3) := by decide
example : decode [0x0f, 0x94] = none := by decide
example : decode [0x0f, 0x94, 0x00] = none := by decide
example : decode [0x0f, 0xb6, 0x00] = none := by decide
example : decode [0x66, 0x0f, 0xb6, 0xc0] = none := by decide
example : decode [0x0f, 0x84, 1, 0, 0, 0] = some (.branch 4 1, 6) := by decide
example : decode [0x39, 0xc8] = some (.compare32 0 1, 2) := by decide
example : decode [0x45, 0x39, 0xd1] = some (.compare32 9 10, 3) := by decide
example : decode [0x48, 0x39, 0xc8] = some (.compare64 0 1, 3) := by decide
example : decode [0x66, 0x39, 0xc8] = none := by decide
example : decode [0x39, 0x08] = none := by decide
example : decode [0x39] = none := by decide

-- SETcc itself must retain the upper 56 bits; clearing them here would
-- make the combined sequence work but mis-model the individual instruction.
example (before : State) (code : Fin 16) (destination : Register) :
    ((before.setCondition code destination 3).registers destination).extractLsb' 8 56 =
      (before.registers destination).extractLsb' 8 56 := by
  simp only [State.setCondition, ↓reduceIte]
  exact BitVec.extractLsb'_append_eq_left

private def starting (code : Fin 16) (left right : BitVec 64) : State where
  registers := fun register => if register = 1 then left else if register = 0 then right else -1
  rip := 0
  memory address := ((ReadOnly.code (Machine.Boolean.comparison code))[address.toNat]?).getD 0
  flags := 0xffffffffffffffff

theorem loaded (code : Fin 16) (left right : BitVec 64) :
    CodeAt (starting code left right).memory 0 (ReadOnly.code (Machine.Boolean.comparison code)) := by
  intro index within
  have length : (ReadOnly.code (Machine.Boolean.comparison code)).length = 9 := rfl
  have small : index < 2^64 := by omega
  simp [starting, BitVec.toNat_ofNat, Nat.mod_eq_of_lt small, List.getElem?_eq_getElem within]

-- Same low 32 bits but different full-width addresses must compare unequal.
example : (ReadOnly.run (Machine.Boolean.comparison 4)
    (starting 4 0x100000001 1)).registers 0 = 0 := by decide
example : (ReadOnly.run (Machine.Boolean.comparison 5)
    (starting 5 0x100000001 1)).registers 0 = 1 := by decide
example : (ReadOnly.run (Machine.Boolean.comparison 4)
    (starting 4 0xffffffffffffffff 0xffffffffffffffff)).registers 0 = 1 := by decide

-- The code-loading domain is inhabited, with actual decoded steps rather
-- than just evaluating a state transformer without instruction fetches.
theorem full_width_steps : ∃ after, Steps 3 (starting 5 0x100000001 1) after ∧
    after.registers 0 = 1 ∧ after.rip = 9 := by
  obtain ⟨after, steps, result, _, _, rip, _⟩ :=
    Machine.Boolean.comparison_steps 5 _ (loaded 5 0x100000001 1)
  exact ⟨after, steps, result, rip⟩

-- The integer window uses the opposite operand-register order, and must
-- ignore upper bits without treating signed comparisons as unsigned.
private def starting32 (code : Fin 16) (left right : BitVec 64) : State :=
  { starting code right left with
    memory address := ((ReadOnly.code (Machine.Boolean.comparison32 code))[address.toNat]?).getD 0 }

theorem loaded32 (code : Fin 16) (left right : BitVec 64) :
    CodeAt (starting32 code left right).memory 0 (ReadOnly.code (Machine.Boolean.comparison32 code)) := by
  intro index within
  have length : (ReadOnly.code (Machine.Boolean.comparison32 code)).length = 8 := rfl
  have small : index < 2^64 := by omega
  simp [starting32, BitVec.toNat_ofNat, Nat.mod_eq_of_lt small, List.getElem?_eq_getElem within]

example : (ReadOnly.run (Machine.Boolean.comparison32 4) (starting32 4 0x100000001 1)).registers 0 = 1 := by decide
example : (ReadOnly.run (Machine.Boolean.comparison32 12) (starting32 12 0xffffffff80000000 1)).registers 0 = 1 := by decide
example : (ReadOnly.run (Machine.Boolean.comparison32 15) (starting32 15 0x7fffffff 0xffffffff)).registers 0 = 1 := by decide
example : (ReadOnly.run (Machine.Boolean.comparison32 14) (starting32 14 0x80000000 0x80000000)).registers 0 = 1 := by decide

theorem signed_overflow_steps : ∃ after, Steps 3 (starting32 12 0xffffffff80000000 1) after ∧
    after.registers 0 = 1 ∧ after.rip = 8 := by
  obtain ⟨value, after, steps, result, output, _, _, rip⟩ := Lower.Condition.native_steps
    (target := .x86_64) .less (by decide) (starting32 12 0xffffffff80000000 1) (loaded32 12 _ _)
  have valueTrue : value = true := by
    simpa [starting32, starting, Lanius.Semantics.evalBinaryValue, Lanius.Semantics.evalSignedBinary] using result.symm
  exact ⟨after, steps, by simpa [valueTrue] using output, rip⟩

run_elab do
  let standard := [``propext, ``Classical.choice, ``Quot.sound]
  for name in [``Machine.Boolean.materialize_run, ``Machine.Boolean.comparison_steps,
      ``Storage.Pointer.comparison_steps, ``Encode.Direct.succeeds,
      ``Encode.Condition.succeeds, ``Encode.Condition.rejects_condition, ``Encode.Condition.rejects_capacity,
      ``Encode.Condition.rejects_register, ``Encode.Condition.decodes, ``Encode.Condition.step,
      ``Encode.Boolean.write, ``Encode.Boolean.rejects, ``Encode.Boolean.steps,
      ``Lower.Condition.selects, ``Lower.Condition.code_range, ``Lower.Condition.core_result, ``Lower.Condition.native_steps,
      ``Lower.Operation.write, ``Lower.Operation.rejects, ``Lower.Operation.emitted_code,
      ``Machine.compare_less, ``Machine.compare_lessEqual, ``Machine.compare_greater, ``Machine.compare_greaterEqual,
      ``Encode.Guarded.compare32_decodes, ``Encode.Guarded.compare32_step, ``loaded32, ``signed_overflow_steps,
      ``Encode.Direct.zeroExtend_decodes, ``Encode.Direct.zeroExtend_step, ``loaded, ``full_width_steps] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "{name} depends on unexpected assumption {assumption}"
  Lean.logInfo "Boolean comparison: decoded CMP/SETcc/MOVZX, full-width results, byte aliases, dirty upper bits, and standard axioms only"

end Lanius.X86.Tests.Boolean
