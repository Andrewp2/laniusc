module

/-! # Machines: one transition function, one induction

A state machine is `step : S → E → O × S`: an event's output and the next
state (docs/state-machines-design.md). `Machine.run` feeds it a list of
events. A property that holds at the start and that every step preserves
holds after every run (`Machine.inv_run`), and a property of each step's
output from such states holds of every output (`Machine.inv_outputs`). A
proof about a machine is then the invariant, its start case and one case per
(state, event) pair. -/

@[expose] public section
namespace Lanius.Machines

variable {S E O : Type}

/-- The state after feeding `events` to `step`, from `s`. -/
def Machine.run (step : S → E → O × S) (s : S) : List E → S
  | [] => s
  | e :: es => Machine.run step (step s e).2 es

/-- The outputs of feeding `events` to `step`, from `s`, in order. -/
def Machine.outputs (step : S → E → O × S) (s : S) : List E → List O
  | [] => []
  | e :: es => (step s e).1 :: Machine.outputs step (step s e).2 es

theorem Machine.inv_run {step : S → E → O × S} {Inv : S → Prop} {s : S} (es : List E)
    (h0 : Inv s) (hs : ∀ s e, Inv s → Inv (step s e).2) : Inv (Machine.run step s es) := by
  induction es generalizing s with
  | nil => exact h0
  | cons e es ih => exact ih (hs s e h0)

theorem Machine.inv_outputs {step : S → E → O × S} {Inv : S → Prop} {P : O → Prop} {s : S}
    (es : List E) (h0 : Inv s) (hs : ∀ s e, Inv s → Inv (step s e).2)
    (ho : ∀ s e, Inv s → P (step s e).1) : ∀ o ∈ Machine.outputs step s es, P o := by
  induction es generalizing s with
  | nil => simp [Machine.outputs]
  | cons e es ih =>
    intro o mem
    simp only [Machine.outputs, List.mem_cons] at mem
    rcases mem with rfl | mem
    · exact ho s e h0
    · exact ih (hs s e h0) o mem

end Lanius.Machines
