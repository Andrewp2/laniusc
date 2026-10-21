import verified_compiler.tests.direct_byte_io_read_interface_read
import Lanius.Semantics.LocalEnvProof

namespace ByteIoReadInterface

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics ByteIoReadProof

namespace Step

/-- Actual host/copy observations, independent of lexical cell coordinates. -/
def Result (spec : ReadStep.Specification) (origin : State)
    (completion : Completion) (after : State) (next : Nat) : Prop :=
  ∃ value heap world,
    FileReadResult origin.heap origin.world spec.handle spec.address spec.request value heap world ∧
    after.world = world ∧ after.i32ArrayViews = origin.i32ArrayViews ∧
    match World.readFileBytes (World.record origin.world .read) spec.handle spec.request with
    | none => next = spec.total ∧ completion = .returned (some (.signed .i32 (-1))) ∧ after.heap = heap
    | some (bytes, _) =>
        if bytes = [] then next = spec.total ∧ completion = .returned (some (.signed .i32 spec.total)) ∧ after.heap = heap
        else if spec.total + bytes.length ≤ spec.capacity then next = spec.total + bytes.length ∧ completion = .next ∧
          BytesWrite heap after.heap (spec.destination + spec.total * 4) (bytes.flatMap Loop.encodeByte)
        else next = spec.total ∧ completion = .returned (some (.signed .i32 (-2))) ∧ after.heap = heap

theorem Result.prepend (result : Result spec ready completion after next)
    (frame : DataFrame origin ready) : Result spec origin completion after next := by
  simpa only [Result, frame.heap, frame.world, frame.views] using result

theorem Result.footprint (result : Result spec origin completion after next)
    (unique : HeapBlockBasesUnique origin.heap) : HeapWritesOn origin.heap after.heap spec.mutable := by
  obtain ⟨value, heap, world, read, _, _, outcome⟩ := result
  have first : HeapWritesOn origin.heap heap spec.mutable :=
    (read.footprint unique).weaken (fun _ inside => Or.inl inside)
  cases reading : World.readFileBytes (World.record origin.world .read) spec.handle spec.request with
  | none => simp only [reading] at outcome; simpa only [outcome.2.2] using first
  | some pair =>
    rcases pair with ⟨bytes, updated⟩
    simp only [reading] at outcome
    by_cases empty : bytes = []
    · simp only [if_pos empty] at outcome; simpa only [outcome.2.2] using first
    · by_cases bounded : spec.total + bytes.length ≤ spec.capacity
      · simp only [if_neg empty, if_pos bounded] at outcome
        exact first.trans (outcome.2.2.footprint.weaken (by
          intro location inside
          apply Or.inr
          rw [Loop.encode_length] at inside
          dsimp only [Address] at *
          constructor <;> omega))
      · simp only [if_neg empty, if_neg bounded] at outcome; simpa only [outcome.2.2] using first

/-- Reuse the proved actual byte-copy loop, then update total through the
same arbitrary-count environment used by the outer compiler consumer. -/
theorem chunk (input : Loop.Input ready) (env : LocalEnv base ready values)
    (total : values (reader.bindingId 1) = some (.signed .i32 input.total))
    (freshIndex : values (reader.bindingId 6) = none) :
    ∃ after, RunsStmt extractedProgram ready (reader.bindingStatement 6) .next after ∧
      LocalEnv base after (values.set (reader.bindingId 1) (.signed .i32 (input.total + input.bytes.length : Nat))) ∧
      BytesWrite ready.heap after.heap (input.destination + input.total * 4) (input.bytes.flatMap Loop.encodeByte) ∧
      after.world = ready.world ∧ after.i32ArrayViews = ready.i32ArrayViews := by
  obtain ⟨copied, copy, output⟩ := Loop.run input
  have copiedEnv := env.afterBindCells (value := .signed .i32 0) output.cells output.locals freshIndex
  have counted : copied.local? (reader.bindingId 5) = some (.signed .i32 input.bytes.length) :=
    output.read _ _ (by decide) input.count
  obtain ⟨after, add, afterEnv, effect⟩ := copiedEnv.assignI32
    (program := extractedProgram) (op := .add) (operand := input.bytes.length)
    (replacement := (input.total + input.bytes.length : Nat)) total
    (show RunsExpr extractedProgram copied (.local (reader.bindingId 5)) (.signed .i32 input.bytes.length) copied from by core_run)
    (by simpa only [evalAssignValue, assignOpBinary?] using
      eval_i32_addNat extractedProgram.target input.total input.bytes.length input.fits)
  have same : after.locals = (ready.bindLocal (reader.bindingId 6) (.signed .i32 0)).locals :=
    add.choose_spec.2.trans output.locals
  have restored := afterEnv.restoreScope (values := values) freshIndex same
  refine ⟨restoreLocals ready after, by core_stmt, ?_, ?_, effect.world.trans output.world, effect.views.trans output.views⟩
  · simpa only [LocalValues.restrict_set_present _ _ _ _ _ total, LocalValues.restrict_self] using restored
  · change BytesWrite ready.heap after.heap _ _
    simpa only [effect.heap, List.take_length] using output.written

/-- The host initializer and the actual count/capacity guards, including all
modeled read failures. The count scope is handled by LocalEnv, not cell IDs. -/
theorem run (input : ReadStep.Input ready) (env : LocalEnv base ready values)
    (total : values (reader.bindingId 1) = some (.signed .i32 input.total))
    (freshCount : values (reader.bindingId 5) = none)
    (freshIndex : values (reader.bindingId 6) = none) :
    EnvStmt extractedProgram base ready (reader.bindingStatement 5)
      (fun next : Nat => values.set (reader.bindingId 1) (.signed .i32 next))
      (fun next completion after => Result input.specification ready completion after next) := by
  apply EnvStmt.letFramed env freshCount
    (spec := fun value after => ∃ heap world, after = { ready with heap, world } ∧
      FileReadResult ready.heap ready.world input.handle input.address input.request value heap world)
    (insideValues := fun value (next : Nat) => (values.set (reader.bindingId 5) value).set
      (reader.bindingId 1) (.signed .i32 next))
  · obtain ⟨value, heap, world, initial, result⟩ := ReadStep.initial input
    exact ⟨value, { ready with heap, world }, initial,
      ⟨[], by simp, Nat.le_refl _, by simp⟩, heap, world, rfl, result⟩
  · intro value read boundEnv observed
    obtain ⟨heap, world, equal, result⟩ := observed
    subst read
    let bound := ({ ready with heap, world } : State).bindLocal (reader.bindingId 5) value
    have oldTotal : (values.set (reader.bindingId 5) value) (reader.bindingId 1) =
        some (.signed .i32 input.total) := by
      simpa only [LocalValues.set_other _ _ _ _ (by decide : reader.bindingId 1 ≠ reader.bindingId 5)] using total
    have unchanged : LocalEnv base bound ((values.set (reader.bindingId 5) value).set
        (reader.bindingId 1) (.signed .i32 input.total)) := by
      simpa only [LocalValues.set_of_found oldTotal] using boundEnv
    core_facts [input]
    have requestFound : bound.local? (reader.bindingId 2) = some (.signed .i32 input.request) :=
      State.bindLocal_local?_of_ne _ input.formed _ _ _ _ (by decide) input.requestFound
    have remainingFound : bound.local? (reader.bindingId 3) = some (.signed .i32 (input.capacity - input.total : Nat)) :=
      State.bindLocal_local?_of_ne _ input.formed _ _ _ _ (by decide) input.remainingFound
    cases reading : World.readFileBytes (World.record ready.world .read) input.handle input.request with
    | none =>
      have invalid : value = .signed .i32 (-1) := by
        have failed := result
        simp only [FileReadResult, reading] at failed
        exact failed.1.trans (by unfold World.i32Result; congr 1)
      have found : bound.local? (reader.bindingId 5) = some (.signed .i32 (-1)) :=
        invalid ▸ input.formed.bindLocal_local _ value
      refine EnvStmt.ofRun (result := input.total) (completion := .returned (some (.signed .i32 (-1)))) ?_ unchanged ?_
      · core_stmt
      exact ⟨value, heap, world, result, rfl, rfl,
        by simp only [ReadStep.Input.specification, reading]; exact ⟨by trivial, by trivial, rfl⟩⟩
    | some pair =>
      rcases pair with ⟨bytes, updated⟩
      obtain ⟨same, _, within, written⟩ := result.success reading input.requestFits
      subst value
      have found : bound.local? (reader.bindingId 5) = some (.signed .i32 bytes.length) :=
        input.formed.bindLocal_local _ _
      by_cases empty : bytes = []
      · subst bytes
        refine EnvStmt.ofRun (result := input.total) (completion := .returned (some (.signed .i32 input.total))) ?_ unchanged ?_
        · core_stmt
        exact ⟨_, heap, world, result, rfl, rfl,
          by simp only [ReadStep.Input.specification, reading]; exact ⟨by trivial, by trivial, rfl⟩⟩
      · have positive : 0 < bytes.length := List.length_pos_iff.mpr empty
        by_cases bounded : input.total + bytes.length ≤ input.capacity
        · let copyInput := input.chunk (world := world) written within bounded
          obtain ⟨after, copy, afterEnv, copied, finalWorld, views⟩ := chunk copyInput boundEnv
            (by simpa only [copyInput, ReadStep.Input.chunk] using oldTotal)
            (by simpa only [LocalValues.set_other _ _ _ _ (by decide : reader.bindingId 6 ≠ reader.bindingId 5)] using freshIndex)
          core_env_guards
          refine EnvStmt.ofRun (result := (input.total + bytes.length : Nat)) copy afterEnv ?_
          exact ⟨_, heap, world, result, finalWorld, views,
            by simp only [ReadStep.Input.specification, reading, if_neg empty, if_pos bounded]
               exact ⟨True.intro, True.intro, copied⟩⟩
        · refine EnvStmt.ofRun (result := input.total) (completion := .returned (some (.signed .i32 (-2)))) ?_ unchanged ?_
          · core_stmt
          exact ⟨_, heap, world, result, rfl, rfl,
            by simp only [ReadStep.Input.specification, reading, if_neg empty, if_neg bounded]
               exact ⟨by trivial, by trivial, rfl⟩⟩
  · intro value next
    simp only [LocalValues.restrict_set_present _ _ _ _ _ total,
      LocalValues.restrict_set_fresh _ _ _ _ freshCount, LocalValues.restrict_self]

#print axioms run

end Step
end ByteIoReadInterface
