import Lanius.X86.Storage.Value
import Lanius.X86.Machine.Equality
import Lanius.X86.Machine.Boolean
import Lanius.Semantics

namespace Lanius.X86.Storage.Pointer

open Lanius.Core Lanius.Semantics

/-- The actual Core equality operation agrees with native address equality
on represented pointers. No agreement between their numerical addresses is
required; injectivity is a separate heap obligation, not an assumed result
of running the compiler. -/
theorem equal (locations : Locations) (injective : locations.PointerInjective)
    (leftMapped : locations.pointer left = some leftNative)
    (rightMapped : locations.pointer right = some rightNative) :
    evalBinaryValue target .equal (.pointer left) (.pointer right) =
      .ok (.boolean (decide (leftNative = rightNative))) := by
  have same := locations.pointer_eq_iff injective leftMapped rightMapped
  simp [evalBinaryValue, scalarEqual, Bool.beq_eq_decide_eq, same]

theorem notEqual (locations : Locations) (injective : locations.PointerInjective)
    (leftMapped : locations.pointer left = some leftNative)
    (rightMapped : locations.pointer right = some rightNative) :
    evalBinaryValue target .notEqual (.pointer left) (.pointer right) =
      .ok (.boolean (decide (leftNative ≠ rightNative))) := by
  have same := locations.pointer_eq_iff injective leftMapped rightMapped
  simp [evalBinaryValue, scalarEqual, Bool.beq_eq_decide_eq, same]

/-- CMP64 preserves the Core pointer-equality answer while retaining all
registers and memory. A surrounding instruction theorem must establish
that the compiler's bytes decode to this comparison. -/
theorem compare_equal (locations : Locations) (injective : locations.PointerInjective)
    (before : Machine.State) (leftRegister rightRegister : Machine.Register)
    (size : Nat)
    (leftMapped : locations.pointer left = some (before.registers leftRegister))
    (rightMapped : locations.pointer right = some (before.registers rightRegister)) :
    evalBinaryValue target .equal (.pointer left) (.pointer right) =
      .ok (.boolean (Machine.condition
        (before.compare64 leftRegister rightRegister size).flags 4)) ∧
      (before.compare64 leftRegister rightRegister size).registers = before.registers ∧
      (before.compare64 leftRegister rightRegister size).memory = before.memory := by
  refine ⟨?_, rfl, rfl⟩
  simpa only [Machine.State.compare64, Machine.compare_equal] using
    equal locations injective leftMapped rightMapped

theorem compare_notEqual (locations : Locations) (injective : locations.PointerInjective)
    (before : Machine.State) (leftRegister rightRegister : Machine.Register)
    (size : Nat)
    (leftMapped : locations.pointer left = some (before.registers leftRegister))
    (rightMapped : locations.pointer right = some (before.registers rightRegister)) :
    evalBinaryValue target .notEqual (.pointer left) (.pointer right) =
      .ok (.boolean (Machine.condition
        (before.compare64 leftRegister rightRegister size).flags 5)) := by
  simpa only [Machine.State.compare64, Machine.compare_notEqual] using
    notEqual locations injective leftMapped rightMapped

/-- The comparison window used after saving the left pointer in RCX and
evaluating the right pointer into RAX. Loaded bytes, rather than an assumed
comparison execution, supply the native step. `comparison_steps` below adds
SETcc/result materialization; enclosing source emission remains separate. -/
theorem compare_step (locations : Locations) (injective : locations.PointerInjective)
    (before : Machine.State)
    (leftMapped : locations.pointer left = some (before.registers 1))
    (rightMapped : locations.pointer right = some (before.registers 0))
    (loaded : Machine.CodeAt before.memory before.rip [0x48, 0x39, 0xc1]) :
    ∃ after, Machine.Step before after ∧
      evalBinaryValue target .equal (.pointer left) (.pointer right) =
        .ok (.boolean (Machine.condition after.flags 4)) ∧
      evalBinaryValue target .notEqual (.pointer left) (.pointer right) =
        .ok (.boolean (Machine.condition after.flags 5)) ∧
      after.registers = before.registers ∧ after.memory = before.memory := by
  let after := before.compare64 1 0 3
  have equalResult := compare_equal (target := target) locations injective before 1 0 3 leftMapped rightMapped
  exact ⟨after, .decoded _ loaded (.compare64 1 0) 3 (by decide) rfl,
    equalResult.1, compare_notEqual locations injective before 1 0 3 leftMapped rightMapped,
    equalResult.2⟩

/-- Equality/inequality of represented pointers produces the actual Core
Boolean in RAX after all three decoded instructions. Other registers and
memory survive, including when the native addresses differ from Core's. -/
theorem comparison_steps (locations : Locations) (injective : locations.PointerInjective)
    (negated : Bool) (before : Machine.State)
    (leftMapped : locations.pointer left = some (before.registers 1))
    (rightMapped : locations.pointer right = some (before.registers 0))
    (loaded : Machine.CodeAt before.memory before.rip
      (Machine.ReadOnly.code (Machine.Boolean.comparison (if negated then 5 else 4)))) :
    ∃ value after, Machine.Steps 3 before after ∧
      evalBinaryValue target (if negated then .notEqual else .equal) (.pointer left) (.pointer right) =
        .ok (.boolean value) ∧
      after.registers 0 = (if value then 1 else 0) ∧
      (∀ register, register ≠ 0 → after.registers register = before.registers register) ∧
      after.memory = before.memory ∧ after.rip = before.rip + 9 := by
  obtain ⟨after, steps, result, registers, memory, rip, _⟩ :=
    Machine.Boolean.comparison_steps (if negated then 5 else 4) before loaded
  refine ⟨_, after, steps, ?_, result, registers, memory, rip⟩
  cases negated
  · simpa only [Bool.false_eq_true, ↓reduceIte, Machine.compare_equal] using
      equal locations injective leftMapped rightMapped
  · simpa only [↓reduceIte, Machine.compare_notEqual] using
      notEqual locations injective leftMapped rightMapped

end Lanius.X86.Storage.Pointer
