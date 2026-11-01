module

public import Lanius.Machines.Machine

/-! # The lowering of `run` (phase M3)

`m.run(events, count)` does not call `step` per event. laniusc elaborates it
to one loop per state (docs/state-machines-design.md, "M3 decisions"):

```text
run:        while (at < count) { at = match (state) { S(d) -> run_S(d, at), ... }; }
run_S(d):   while (at < count) {
              e = events[at]; at += 1;
              the arms of S on e, where
                stay; and goto S(d')    are  d = d'; continue;
                goto T(d') with T ≠ S   is   state = T(d'); return at;
            }
            state = S(d); return at;
```

A transition back to the same state is a jump to the top of its loop, with
the state's data in locals; only a transition to another state stores the
state and goes through the dispatch. `tag s` is the state a machine value is
in (which loop runs), so `stay` and `goto S` are exactly the steps after which
`tag` is unchanged.

`Machine.inner` is one state's loop and `Machine.lowered` the dispatch loop.
`Machine.lowered_eq_run` proves that they compute `Machine.run step s
events`, so every theorem about `run` (`inv_run`, the trace properties)
holds of the lowered code. -/

@[expose] public section
namespace Lanius.Machines

variable {S E O T : Type} [DecidableEq T]

/-- One state's loop: consume events while each keeps the machine in the
same state; stop after the first that leaves it, or at the end. -/
def Machine.inner (step : S → E → O × S) (tag : S → T) (s : S) : List E → S × List E
  | [] => (s, [])
  | e :: es =>
    if tag (step s e).2 = tag s then Machine.inner step tag (step s e).2 es
    else ((step s e).2, es)

/-- The dispatch loop, with `fuel` at least the number of events left. -/
def Machine.lowered (step : S → E → O × S) (tag : S → T) : Nat → S → List E → S
  | 0, s, _ => s
  | _ + 1, s, [] => s
  | fuel + 1, s, e :: es =>
    Machine.lowered step tag fuel (Machine.inner step tag s (e :: es)).1 (Machine.inner step tag s (e :: es)).2

/-- A state's loop runs `step` over the events it consumes, and leaves the
rest. -/
theorem Machine.inner_run (step : S → E → O × S) (tag : S → T) (s : S) (es : List E) :
    ∃ taken, taken ++ (Machine.inner step tag s es).2 = es ∧
      Machine.run step s taken = (Machine.inner step tag s es).1 ∧
      (es ≠ [] → (Machine.inner step tag s es).2.length < es.length) := by
  induction es generalizing s with
  | nil => exact ⟨[], rfl, rfl, fun h => absurd rfl h⟩
  | cons e es ih =>
    by_cases h : tag (step s e).2 = tag s
    · obtain ⟨taken, h1, h2, -⟩ := ih (step s e).2
      refine ⟨e :: taken, ?_, ?_, ?_⟩
      · simp only [Machine.inner, h, if_true, List.cons_append, h1]
      · simp only [Machine.inner, h, if_true, Machine.run, h2]
      · intro _
        simp only [Machine.inner, h, if_true]
        have := congrArg List.length h1
        simp only [List.length_append] at this
        simp only [List.length_cons]; omega
    · refine ⟨[e], ?_, ?_, ?_⟩
      · simp [Machine.inner, h]
      · simp [Machine.inner, h, Machine.run]
      · intro _; simp [Machine.inner, h]

/-- The lowering theorem: the loops compute `Machine.run`. -/
theorem Machine.lowered_eq_run (step : S → E → O × S) (tag : S → T) (fuel : Nat) (s : S) (es : List E)
    (h : es.length ≤ fuel) : Machine.lowered step tag fuel s es = Machine.run step s es := by
  induction fuel generalizing s es with
  | zero =>
    cases es with
    | nil => rfl
    | cons e es => simp at h
  | succ fuel ih =>
    cases es with
    | nil => rfl
    | cons e es =>
      obtain ⟨taken, h1, h2, h3⟩ := Machine.inner_run step tag s (e :: es)
      have shorter := h3 (List.cons_ne_nil e es)
      simp only [List.length_cons] at shorter h
      simp only [Machine.lowered]
      rw [ih _ _ (by omega), ← h2, ← Machine.run_append, h1]

/-- `run` from a state over all of `events`. -/
def Machine.runLowered (step : S → E → O × S) (tag : S → T) (s : S) (events : List E) : S :=
  Machine.lowered step tag events.length s events

theorem Machine.runLowered_eq_run (step : S → E → O × S) (tag : S → T) (s : S) (events : List E) :
    Machine.runLowered step tag s events = Machine.run step s events :=
  Machine.lowered_eq_run step tag _ s events (Nat.le_refl _)

end Lanius.Machines
