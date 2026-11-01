module

/-! # Machines: one transition function, one induction

A state machine is `step : S → E → O × S`: an event's output and the next
state (docs/state-machines-design.md). `Machine.run` feeds it a list of
events. A property that holds at the start and that every step preserves
holds after every run (`Machine.inv_run`), and a property of each step's
output from such states holds of every output (`Machine.inv_outputs`). A
proof about a machine is then the invariant, its start case and one case per
(state, event) pair.

A trace property is a statement about every state a run passes through
(`Machine.states`, `Machine.inv_states`). It is checked with a spec monitor
as in P: a second machine beside the first (`Machine.withSpec`) that watches
each event and the state it led to and changes nothing
(`Machine.run_withSpec_fst`). Its states record what the property needs to
remember of the past, and the property is an invariant of the pair. A
machine without an output, extracted as `step : S → E → S`, runs as
`Machine.silent step`. -/

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

/-- The states after each event of `events`, from `s`, in order. -/
def Machine.states (step : S → E → O × S) (s : S) : List E → List S
  | [] => []
  | e :: es => (step s e).2 :: Machine.states step (step s e).2 es

theorem Machine.inv_states {step : S → E → O × S} {Inv : S → Prop} {s : S} (es : List E)
    (h0 : Inv s) (hs : ∀ s e, Inv s → Inv (step s e).2) : ∀ t ∈ Machine.states step s es, Inv t := by
  induction es generalizing s with
  | nil => simp [Machine.states]
  | cons e es ih =>
    intro t mem
    simp only [Machine.states, List.mem_cons] at mem
    rcases mem with rfl | mem
    · exact hs s e h0
    · exact ih (hs s e h0) t mem

theorem Machine.run_append (step : S → E → O × S) (s : S) (xs ys : List E) :
    Machine.run step s (xs ++ ys) = Machine.run step (Machine.run step s xs) ys := by
  induction xs generalizing s with
  | nil => rfl
  | cons e es ih => exact ih _

/-- A machine without an output, as one whose output is `()`. -/
def Machine.silent (step : S → E → S) : S → E → Unit × S :=
  fun s e => ((), step s e)

/-- `step` with a spec monitor beside it: `spec` sees each event and the
state it led to. -/
def Machine.withSpec {W : Type} (step : S → E → O × S) (spec : W → E → S → W) : S × W → E → O × (S × W) :=
  fun p e => ((step p.1 e).1, ((step p.1 e).2, spec p.2 e (step p.1 e).2))

/-- The monitor changes nothing: the machine beside it runs as it would alone. -/
theorem Machine.run_withSpec_fst {W : Type} (step : S → E → O × S) (spec : W → E → S → W)
    (s : S) (w : W) (es : List E) :
    (Machine.run (Machine.withSpec step spec) (s, w) es).1 = Machine.run step s es := by
  induction es generalizing s w with
  | nil => rfl
  | cons e es ih => exact ih _ _

end Lanius.Machines
