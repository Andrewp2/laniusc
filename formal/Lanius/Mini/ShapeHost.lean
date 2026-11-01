import Lanius.Mini.Shape
import Lanius.World

/-! # Host calls on typed arguments (review finding 2, step 3)

The host services the verified compiler lowers (`hostService?`: writing a
byte, writing standard output and error, reading standard input, sleeping,
the two clocks and the secure bytes), called with arguments of their
parameter types' shapes, never give `typeMismatch`, and what they return is
an `i32`. -/

namespace Lanius.Mini

open Lanius.Core (Value Ty HostService)

/-- The host services the verified compiler lowers. -/
def LoweredService (s : HostService) : Prop :=
  s = .writeByte ∨ s = .writeStdout ∨ s = .writeStderr ∨ s = .readStdin ∨ s = .sleepMsI32 ∨
    s = .monotonicRead ∨ s = .systemRead ∨ s = .fillSecureBytes

/-- What a host call gives on shaped arguments: no `typeMismatch`, and a
returned value of the service's result shape. -/
def HostOk (P : Core.Program) (s : HostService) : Lanius.World.EffectResult → Prop
  | .typeMismatch _ _ => False
  | .returned v _ _ => Shape P v s.returnType
  | _ => True

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
  rcases lowered with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  all_goals first
    | (obtain ⟨x, y, rfl, hx, hy⟩ := shapes_two shaped; cases hx; cases hy)
    | (obtain ⟨x, rfl, hx⟩ := shapes_one shaped; cases hx)
  all_goals
    simp only [Lanius.World.call, Lanius.World.callSimple]
    repeat' split
  all_goals (try (rename_i heq; repeat' split at heq))
  all_goals simp_all [HostOk, i32Result_shape, HostService.returnType]
  all_goals (rename_i heq; obtain ⟨rfl, -⟩ := heq; exact i32Result_shape P _)

end Lanius.Mini
