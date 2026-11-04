module

public import Lanius.Mini.Shape
public import Lanius.World

@[expose] public section

/-! # Host calls on typed arguments (review finding 2, step 3)

The host services the verified compiler lowers (`hostService?`: writing a
byte, writing standard output and error, reading standard input, sleeping,
the two clocks and the secure bytes), called with arguments of their
parameter types' shapes, never give `typeMismatch`, and what they return is
an `i32`. -/

namespace Lanius.Mini.NoMismatch

open Lanius.Core (Value Ty HostService)

/-- The host services the verified compiler lowers. -/
def LoweredService (s : HostService) : Prop :=
  s = .writeByte ∨ s = .writeStdout ∨ s = .writeStderr ∨ s = .readStdin ∨ s = .sleepMsI32 ∨
    s = .monotonicRead ∨ s = .systemRead ∨ s = .fillSecureBytes ∨ s = .writeText ∨ s = .writeNewline

/-- What a host call gives on shaped arguments: no `typeMismatch`, and a
returned value of the service's result shape. -/
def HostOk (P : Core.Program) (s : HostService) : Lanius.World.EffectResult → Prop
  | .typeMismatch _ _ => False
  | .returned v _ _ => Shape P v s.returnType
  | .trapped r _ _ => r ≠ .typeMismatch
  | _ => True

/-! ## Heap byte errors are not `typeMismatch` -/

theorem loadByte_ne {heap : Memory.Heap} {p o : Nat} {r : Lanius.Trap} (h : heap.loadByte p o = .error r) :
    r ≠ .typeMismatch := by
  simp only [Memory.Heap.loadByte] at h
  repeat' split at h
  all_goals (try split at h)
  all_goals (cases h <;> decide)

theorem storeByte_ne {heap : Memory.Heap} {p o : Nat} {b : UInt8} {r : Lanius.Trap}
    (h : heap.storeByte p o b = .error r) : r ≠ .typeMismatch := by
  simp only [Memory.Heap.storeByte] at h
  repeat' split at h
  all_goals (try split at h)
  all_goals (cases h <;> decide)

theorem loadBytesFrom_ne {heap : Memory.Heap} {p : Nat} :
    ∀ {o n : Nat} {r : Lanius.Trap}, Memory.loadBytesFrom heap p o n = .error r → r ≠ .typeMismatch
  | _, 0, _, h => by cases h
  | o, n + 1, r, h => by
    simp only [Memory.loadBytesFrom] at h
    split at h
    · cases h; exact loadByte_ne (by assumption)
    · split at h
      · cases h; exact loadBytesFrom_ne (by assumption)
      · cases h

theorem storeBytesFrom_ne {p : Nat} :
    ∀ {heap : Memory.Heap} {o : Nat} {bytes : List UInt8} {r : Lanius.Trap},
      Memory.storeBytesFrom heap p o bytes = .error r → r ≠ .typeMismatch
  | _, _, [], _, h => by cases h
  | heap, o, b :: rest, r, h => by
    simp only [Memory.storeBytesFrom] at h
    split at h
    · cases h; exact storeByte_ne (by assumption)
    · exact storeBytesFrom_ne h

theorem shapes_two {P : Core.Program} {args : List Value} {a b : Ty} (h : Shapes P args [a, b]) :
    ∃ x y, args = [x, y] ∧ Shape P x a ∧ Shape P y b := by
  match args, h with
  | [x, y], h =>
    obtain ⟨hx, h'⟩ := h.cons_inv
    exact ⟨x, y, rfl, hx, h'.cons_inv.1⟩
  | [], h => exact absurd h.1 (by simp)
  | [_], h => exact absurd h.1 (by simp)
  | _ :: _ :: _ :: _, h => exact absurd h.1 (by simp)

theorem shapes_one {P : Core.Program} {args : List Value} {a : Ty} (h : Shapes P args [a]) :
    ∃ x, args = [x] ∧ Shape P x a := by
  match args, h with
  | [x], h => exact ⟨x, rfl, h.cons_inv.1⟩
  | [], h => exact absurd h.1 (by simp)
  | _ :: _ :: _, h => exact absurd h.1 (by simp)

theorem i32Result_shape (P : Core.Program) (v : Int) : Shape P (Lanius.World.i32Result v) (.scalar (.signed .i32)) :=
  .signed _ _

theorem host_ok {P : Core.Program} {heap : Memory.Heap} {world : Lanius.World.State} {s : HostService}
    {args : List Value} (lowered : LoweredService s) (shaped : Shapes P args s.parameterTypes) :
    HostOk P s (Lanius.World.call heap world s args) := by
  rcases lowered with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  all_goals first
    | (obtain ⟨x, y, rfl, hx, hy⟩ := shapes_two shaped; cases hx; cases hy)
    | (obtain ⟨x, rfl, hx⟩ := shapes_one shaped; cases hx)
  all_goals
    simp only [Lanius.World.call, Lanius.World.callSimple]
    repeat' split
  all_goals (try (rename_i heq; repeat' split at heq))
  all_goals simp_all [HostOk, i32Result_shape, HostService.returnType]
  all_goals first
    | (rename_i heq; obtain ⟨rfl, -⟩ := heq; exact i32Result_shape P _)
    | (rename_i heq; exact loadBytesFrom_ne heq)
    | (rename_i heq; exact storeBytesFrom_ne heq)
    | skip

end Lanius.Mini.NoMismatch
