import Lanius.X86.Encode.Arithmetic
import Lanius.X86.Lower.Operation.Arithmetic
import Lean

namespace Lanius.X86.Tests.Arithmetic

open Lanius.X86.Machine

example : decode [1, 200] = some (.alu32 .add 0 1, 2) := by decide
example : decode [41, 200] = some (.alu32 .subtract 0 1, 2) := by decide
example : decode [69, 33, 200] = some (.alu32 .and 8 9, 3) := by decide
example : decode [65, 9, 207] = some (.alu32 .or 15 1, 3) := by decide
example : decode [68, 49, 248] = some (.alu32 .xor 0 15, 3) := by decide
example : decode [72, 41, 200] = some (.subtract64 0 1, 3) := by decide
example : ([[], [1], [69, 33], [1, 8], [72, 1, 200], [102, 1, 200], [240, 1, 200]] : List (List UInt8)).all
    (fun bytes => (decode bytes).isNone) = true := by decide

private def before (left right : Nat) : State := {
  registers := fun register => if register = 0 then BitVec.ofNat 64 left
    else if register = 1 then BitVec.ofNat 64 right else 0x5555555555555555
  flags := 0x400, rip := 100, memory := fun _ => 0x5a }

private def result (operation : Alu) (left right : Nat) (auxiliary : Bool := false) : State :=
  (before left right).alu32 operation 0 1 auxiliary 2

-- Carry and signed overflow differ; destination writes clear dirty high bits.
example : (result .add 0xffffffff7fffffff 1).registers 0 = 0x80000000 ∧
    (result .add 0xffffffff7fffffff 1).flags.getLsbD 11 = true ∧
    (result .add 0xffffffff7fffffff 1).flags.getLsbD 0 = false := by decide
example : (result .add 0xffffffffffffffff 1).registers 0 = 0 ∧
    (result .add 0xffffffffffffffff 1).flags.getLsbD 11 = false ∧
    (result .add 0xffffffffffffffff 1).flags.getLsbD 0 = true := by decide
example : (result .subtract 0xffffffff80000000 1).registers 0 = 0x7fffffff ∧
    (result .subtract 0xffffffff80000000 1).flags.getLsbD 11 = true := by decide
example : (result .subtract 0 1).registers 0 = 0xffffffff ∧
    (result .subtract 0 1).flags.getLsbD 0 = true := by decide
example : (result .and 0xffffffffffffffff 0x80000000 true).registers 0 = 0x80000000 ∧
    (result .or 0xffffffff80000000 1).registers 0 = 0x80000001 ∧
    (result .xor 0xffffffffffffffff 0x80000000).registers 0 = 0x7fffffff := by decide
example (auxiliary : Bool) : (result .xor 0xffffffff 0xffffffff auxiliary).flags.getLsbD 4 = auxiliary := by
  cases auxiliary <;> decide
example (operation : Alu) (left right : Nat) (auxiliary : Bool) :
    (result operation left right auxiliary).flags.getLsbD 10 = true := by
  exact (Alu.flags_direction operation (before left right).flags
    ((before left right).registers 0 |>.setWidth 32) ((before left right).registers 1 |>.setWidth 32) auxiliary).trans
      (by decide : (1024#64).getLsbD 10 = true)

run_elab do
  for name in [``Encode.Arithmetic.decodes, ``Encode.Arithmetic.core_result, ``Encode.Arithmetic.native,
      ``Encode.Arithmetic.preserves, ``Encode.Arithmetic.succeeds, ``Alu.flags_direction,
      ``Lower.Operation.Arithmetic.dispatch, ``Lower.Operation.Arithmetic.succeeds,
      ``Lower.Operation.Arithmetic.rejects, ``Source.Operation.Arithmetic.selects,
      ``Buffer.Locals.letCall, ``Lanius.Extraction.Source.CheckedInternal.specStorage] do
    for assumption in ← Lean.collectAxioms name do
      unless [``propext, ``Classical.choice, ``Quot.sound].contains assumption do
        throwError "{name} depends on unexpected assumption {assumption}"

end Lanius.X86.Tests.Arithmetic
