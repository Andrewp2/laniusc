import verified_compiler.tests.direct_byte_io_read_outer
import Lanius.Semantics.TotalWhile

namespace ByteIoReadProof.Total

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics

private def reader := Extracted.«verified::byte_io».Functions.«read_file».core

/-- Observable buffer geometry, independent of temporary lexical bindings. -/
structure Configuration where
  address : Nat
  words : Nat
  destination : Nat
  capacity : Nat
  handle : Int

def Configuration.mutable (context : Configuration) (location : Address) : Prop :=
  (context.address ≤ location ∧ location < context.address + context.words * 4) ∨
  (context.destination ≤ location ∧ location < context.destination + context.capacity * 4)

/-- Persistent caller parameters, before allocating the mutable total cell.
    These are storage/binding facts, not successful execution assumptions. -/
structure Parameters (base : State) extends Configuration where
  formed : base.CellsWellFormed
  capacityFits : capacity < 2 ^ 31
  scratchSize : 16384 ≤ words
  separate : destination + capacity * 4 ≤ address ∨ address + words * 4 ≤ destination
  packed : base.local? (reader.argumentId 3) = some (.rawSlice (.scalar (.signed .i32)) address words)
  output : base.local? (reader.argumentId 1) = some (.rawSlice (.scalar (.signed .i32)) destination capacity)
  handleFound : base.local? (reader.argumentId 0) = some (.signed .i32 handle)
  capacityFound : base.local? (reader.argumentId 2) = some (.signed .i32 capacity)

/-- The pointer lookup is derived by the function's initializer, not supplied
    as an internal binding by the caller. -/
structure Context (base : State) extends Parameters base where
  pointerFound : base.local? (reader.bindingId 0) = some (.pointer address)

variable {base before after state : State} {context : Context base}
  {total : Nat} {completion : Completion}

/-- Only changing storage and the counter belong in the loop invariant. -/
structure Invariant (context : Context base) (state : State) (total : Nat) : Prop where
  counter : CountedLocal base state (reader.bindingId 1) total
  bounded : total ≤ context.capacity
  inputRoom : state.heap.Readable context.address (context.words * 4)
  outputRoom : state.heap.Readable context.destination (context.capacity * 4)
  unique : HeapBlockBasesUnique state.heap
  noViews : state.i32ArrayViews = []
  written : HeapWritesOn base.heap state.heap context.toConfiguration.mutable

def Invariant.input (current : Invariant context state total) : Outer.Input state := {
  address := context.address, words := context.words, destination := context.destination
  capacity := context.capacity, total := total, handle := context.handle
  capacityFits := context.capacityFits, scratchSize := context.scratchSize, totalBound := current.bounded
  inputRoom := current.inputRoom, outputRoom := current.outputRoom, separate := context.separate
  formed := current.counter.cells.after_cellsWellFormed context.formed, unique := current.unique, noViews := current.noViews
  packed := current.counter.read _ _ (by decide) context.packed
  output := current.counter.read _ _ (by decide) context.output
  cursor := current.counter.counter
  handleFound := current.counter.read _ _ (by decide) context.handleFound
  pointerFound := current.counter.read _ _ (by decide) context.pointerFound
  capacityFound := current.counter.read _ _ (by decide) context.capacityFound }

theorem Context.start (context : Context base)
    (inputRoom : base.heap.Readable context.address (context.words * 4))
    (outputRoom : base.heap.Readable context.destination (context.capacity * 4))
    (unique : HeapBlockBasesUnique base.heap) (noViews : base.i32ArrayViews = []) :
    Invariant context (base.bindLocal (reader.bindingId 1) (.signed .i32 0)) 0 :=
  ⟨CountedLocal.start context.formed _ 0, Nat.zero_le _, inputRoom, outputRoom, unique, noViews,
    HeapWritesOn.refl unique⟩

/-- The loop returns an error or its exact retained total, with valid buffers
    and caller cells. Exact whole-file contents are a separate refinement. -/
def Done (context : Context base) (completion : Completion) (after : State) : Prop :=
  ∃ total, Invariant context after total ∧
    (completion = .returned (some (.signed .i32 (-1))) ∨
     completion = .returned (some (.signed .i32 (-2))) ∨
     completion = .returned (some (.signed .i32 total)))

private theorem observedStep (current : Invariant context before total)
    (body : RunsStmt extractedProgram before (reader.whileLoop 0).2 completion after)
    (result : ReadStep.Result current.input.specification before base before completion after) :
    Done context completion after ∨
      ∃ next, completion = .next ∧ total < next ∧ Invariant context after next := by
  change ReadStep.Result
    ⟨context.address, context.destination, context.capacity, total, context.handle,
      if context.capacity - total < 65536 then context.capacity - total + 1 else 65536⟩
    before base before completion after at result
  have footprint := result.footprint current.unique
  have writes : HeapWritesOn before.heap after.heap context.toConfiguration.mutable := footprint.weaken (by
    intro location inside
    rcases inside with scratch | output
    · apply Or.inl
      have room : (if context.capacity - total < 65536 then context.capacity - total + 1 else 65536) ≤
          context.words * 4 := by split <;> have := context.scratchSize <;> omega
      exact ⟨scratch.1, Nat.lt_of_lt_of_le scratch.2 (Nat.add_le_add_left room _)⟩
    · exact Or.inr output)
  obtain ⟨value, heap, world, read, worldEq, views, outcome⟩ := result
  have restored : restoreLocals before after = after := by
    unfold restoreLocals
    rw [← body.choose_spec.2]
  have finish (next : Nat) (bounded : next ≤ context.capacity)
      (counter : CountedLocal base (restoreLocals before after) (reader.bindingId 1) next) :
      Invariant context after next :=
    ⟨by simpa only [restored] using counter, bounded, writes.readable _ _ current.inputRoom,
      writes.readable _ _ current.outputRoom, writes.unique, views.trans current.noViews,
      current.written.trans writes⟩
  cases reading : World.readFileBytes (World.record before.world .read) context.handle
      (if context.capacity - total < 65536 then context.capacity - total + 1 else 65536) with
  | none =>
      simp only [FileReadResult, reading] at read outcome
      exact Or.inl ⟨total, finish total current.bounded outcome.2.2, Or.inl outcome.1⟩
  | some pair =>
      rcases pair with ⟨bytes, updated⟩
      simp only [FileReadResult, reading] at read outcome
      by_cases empty : bytes = []
      · simp only [if_pos empty] at outcome
        exact Or.inl ⟨total, finish total current.bounded outcome.2.2, Or.inr (Or.inr outcome.1)⟩
      · by_cases bounded : total + bytes.length ≤ context.capacity
        · simp only [if_neg empty, if_pos bounded] at outcome
          exact Or.inr ⟨total + bytes.length, outcome.1,
            by have := List.length_pos_iff.mpr empty; omega,
            finish _ bounded outcome.2.1⟩
        · simp only [if_neg empty, if_neg bounded] at outcome
          exact Or.inl ⟨total, finish total current.bounded outcome.2.2, Or.inr (Or.inl outcome.1)⟩

/-- Add heap/world observations to the existing execution proof. Clients
    prove one step from its retained effect, never a second loop execution. -/
structure Tracker (context : Context base) where
  Inv : Nat → Heap → World.State → Prop
  Done : Completion → Heap → World.State → Prop
  observe : ∀ {before after total completion},
    (current : Invariant context before total) → Inv total before.heap before.world →
    RunsStmt extractedProgram before (reader.whileLoop 0).2 completion after →
    ReadStep.Result current.input.specification before base before completion after →
    (Total.Done context completion after → Done completion after.heap after.world) ∧
    (∀ next, completion = .next → Invariant context after next → Inv next after.heap after.world)

def Tracker.unobserved : Tracker context := {
  Inv := fun _ _ _ => True, Done := fun _ _ _ => True
  observe := by intros; exact ⟨fun _ => True.intro, fun _ _ _ => True.intro⟩ }

private def remaining (capacity : Nat) (state : State) : Nat :=
  capacity - (match state.local? (reader.bindingId 1) with
    | some (.signed .i32 total) => total.toNat
    | _ => 0)

/-- Total execution of the actual outer loop, including all early returns.
    Positive reads decrease remaining capacity; no execution oracle is assumed. -/
theorem runTracked (current : Invariant context before total) (tracker : Tracker context)
    (tracked : tracker.Inv total before.heap before.world) :
    ∃ completion after, RunsStmt extractedProgram before
      (.whileLoop (reader.whileLoop 0).1 (reader.whileLoop 0).2) completion after ∧
      Done context completion after ∧ tracker.Done completion after.heap after.world := by
  let oracle : TotalWhileOracle (remaining context.capacity) extractedProgram
      (reader.whileLoop 0).1 (reader.whileLoop 0).2 := {
    Inv := fun state => ∃ total, Invariant context state total ∧ tracker.Inv total state.heap state.world
    Done := fun completion state => Done context completion state ∧ tracker.Done completion state.heap state.world
    step := by
      intro state ⟨total, current, tracked⟩
      obtain ⟨completion, after, body, result⟩ := Outer.iteration current.input current.counter context.formed
      have observed := tracker.observe current tracked body result
      let threshold := body.choose
      have stable := body.choose_spec.1
      refine Or.inr ⟨1, threshold, state, completion, after, ?_, stable, ?_, ?_⟩
      · exact StableExpr.value
      · intro terminal
        rcases observedStep current body result with done | ⟨next, same, _, _⟩
        · have final := observed.1 done
          obtain ⟨index, invariant, first | second | third⟩ := done <;>
            subst completion <;> exact ⟨⟨index, invariant, by simp [normalizeCompletion]⟩,
              by simpa only [normalizeCompletion] using final⟩
        · exact (terminal.1 same).elim
      · intro continues
        rcases observedStep current body result with done | ⟨next, same, progress, invariant⟩
        · obtain ⟨index, _, outcomes⟩ := done
          rcases outcomes with error | error | returned <;> rcases continues with same | same <;> simp_all
        · refine ⟨?_, next, invariant, observed.2 next same invariant⟩
          simp only [remaining, invariant.counter.counter, current.counter.counter, Int.toNat_natCast]
          have := invariant.bounded
          omega }
  obtain ⟨threshold, completion, after, stable, done⟩ := executeTotalWhile
    (remaining context.capacity) extractedProgram (reader.whileLoop 0).1 (reader.whileLoop 0).2
    oracle before ⟨total, current, tracked⟩
  exact ⟨completion, after, RunsStmt.ofExec (stable threshold (Nat.le_refl _)), done⟩

theorem run (current : Invariant context before total) :
    ∃ completion after, RunsStmt extractedProgram before
      (.whileLoop (reader.whileLoop 0).1 (reader.whileLoop 0).2) completion after ∧ Done context completion after := by
  obtain ⟨completion, after, run, done, _⟩ := runTracked current .unobserved True.intro
  exact ⟨completion, after, run, done⟩

#print axioms runTracked
#print axioms run

/-- Observable result after removing the total's lexical binding. Caller
    cells and both buffers remain valid; only the fresh counter is hidden. -/
def Result (context : Configuration) (base : State) (value : Value) (after : State) : Prop :=
  ∃ total, total ≤ context.capacity ∧ FreshCellFrame base after ∧
    after.heap.Readable context.address (context.words * 4) ∧
    after.heap.Readable context.destination (context.capacity * 4) ∧
    HeapBlockBasesUnique after.heap ∧ after.i32ArrayViews = [] ∧
    (value = .signed .i32 (-1) ∨ value = .signed .i32 (-2) ∨ value = .signed .i32 total) ∧
    HeapWritesOn base.heap after.heap context.mutable

/-- Actual total initializer, complete outer loop and enclosing scope.
    The return following `while true` is unreachable, derived from `run`. -/
theorem declarationTracked (context : Context base) (tracker : Tracker context)
    (tracked : tracker.Inv 0 base.heap base.world)
    (inputRoom : base.heap.Readable context.address (context.words * 4))
    (outputRoom : base.heap.Readable context.destination (context.capacity * 4))
    (unique : HeapBlockBasesUnique base.heap) (noViews : base.i32ArrayViews = []) :
    ∃ value after, RunsStmt extractedProgram base (reader.bindingStatement 1) (.returned (some value)) after ∧
      Result context.toConfiguration base value after ∧
      tracker.Done (.returned (some value)) after.heap after.world := by
  obtain ⟨completion, after, loop, done, final⟩ :=
    runTracked (context.start inputRoom outputRoom unique noViews) tracker tracked
  have returned : ∃ value, completion = .returned (some value) := by
    obtain ⟨index, _, first | second | third⟩ := done
    · exact ⟨_, first⟩
    · exact ⟨_, second⟩
    · exact ⟨_, third⟩
  obtain ⟨value, rfl⟩ := returned
  have initial : RunsExpr extractedProgram base (reader.bindingInitializer 1) (.signed .i32 0) base := by core_run
  have rest := RunsStmt.sequenceCompleted loop (by intro equal; cases equal)
    (match reader.bindingStatement 1 with | .letLocal _ _ _ (.sequence _ rest) => rest | _ => .skip)
  have executed := RunsStmt.letLocal (id := reader.bindingId 1) (type := .scalar (.signed .i32))
    (afterInit := base) initial rest
  refine ⟨value, restoreLocals base after, Eq.mp (by congr 1 <;> rfl) executed, ?_⟩
  obtain ⟨index, current, values⟩ := done
  simp only [Completion.returned.injEq, Option.some.injEq] at values
  exact ⟨⟨index, current.bounded, current.counter.cells.restoreLocals,
    current.inputRoom, current.outputRoom, current.unique, current.noViews, values, current.written⟩, final⟩

theorem declaration (context : Context base)
    (inputRoom : base.heap.Readable context.address (context.words * 4))
    (outputRoom : base.heap.Readable context.destination (context.capacity * 4))
    (unique : HeapBlockBasesUnique base.heap) (noViews : base.i32ArrayViews = []) :
    ∃ value after, RunsStmt extractedProgram base (reader.bindingStatement 1) (.returned (some value)) after ∧
      Result context.toConfiguration base value after := by
  obtain ⟨value, after, run, result, _⟩ := declarationTracked context .unobserved True.intro inputRoom outputRoom unique noViews
  exact ⟨value, after, run, result⟩

#print axioms declarationTracked
#print axioms declaration

end ByteIoReadProof.Total
