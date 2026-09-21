import Lanius.X86.LocalExpressionCheck

namespace Lanius.X86.ExpressionEnvironment

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86
open Lanius.X86.Machine

abbrev Location := LocalExpressionCheck.Location
abbrev Entry (coreBefore : Semantics.State) (machineBefore : Machine.State) :=
  LocalExpressionCheck.Environment coreBefore machineBefore

structure Environment (coreBefore : Semantics.State) (machineBefore : Machine.State) where
  lookup : VarId → Option (Entry coreBefore machineBefore)
  keyed : ∀ id entry, lookup id = some entry → entry.id = id

def Environment.empty : Environment coreBefore machineBefore :=
  { lookup := fun _ => none
    keyed := by intro id entry found; simp at found }

def Environment.extend (environment : Environment coreBefore machineBefore)
    (entry : Entry coreBefore machineBefore) : Environment coreBefore machineBefore :=
  { lookup := fun id => if id = entry.id then some entry else environment.lookup id
    keyed := by
      intro id foundEntry found
      by_cases same : id = entry.id
      · have foundEq : foundEntry = entry := by simpa [same] using found.symm
        subst foundEntry
        exact same.symm
      · exact environment.keyed id foundEntry (by simpa [same] using found) }

def Environment.Relates (environment : Environment coreBefore machineBefore)
    (id : VarId) (location : Location) (value : Int) : Prop :=
  ∃ entry, environment.lookup id = some entry ∧
    entry.location = location ∧ entry.value = value

theorem Environment.extend_relates
    (environment : Environment coreBefore machineBefore)
    (entry : Entry coreBefore machineBefore) :
    (environment.extend entry).Relates entry.id entry.location entry.value := by
  refine ⟨entry, ?_, rfl, rfl⟩
  simp [Environment.extend]

theorem Environment.extend_preserves
    (environment : Environment coreBefore machineBefore)
    (entry : Entry coreBefore machineBefore) {id : VarId} {location : Location} {value : Int}
    (different : id ≠ entry.id)
    (related : environment.Relates id location value) :
    (environment.extend entry).Relates id location value := by
  rcases related with ⟨foundEntry, found, foundLocation, foundValue⟩
  refine ⟨foundEntry, ?_, foundLocation, foundValue⟩
  simp [Environment.extend, different, found]

theorem loadLocal
    (environment : Environment coreBefore machineBefore) (program : Program) (id : VarId)
    (location : Location) (value : Int)
    (related : environment.Relates id location value)
    (loaded : CodeAt machineBefore.memory machineBefore.rip location.bodyBytes) :
    evalExpr 1 program coreBefore (.local id) =
        .done (.signed .i32 value) coreBefore ∧
      ∃ after, Step machineBefore after ∧
        after.registers ScalarValidator.resultRegister =
          (BitVec.ofInt 32 value).setWidth 64 ∧
        after.rip = machineBefore.rip + BitVec.ofNat 64 location.bodyBytes.length ∧
        after.registers rspRegister = machineBefore.registers rspRegister ∧
        (∀ register, register ≠ ScalarValidator.resultRegister →
          register ≠ rspRegister → after.registers register = machineBefore.registers register) ∧
        after.memory = machineBefore.memory ∧ after.flags = machineBefore.flags := by
  rcases related with ⟨entry, found, locationExact, valueExact⟩
  have idExact := environment.keyed id entry found
  have entryLoaded : CodeAt machineBefore.memory machineBefore.rip entry.location.bodyBytes := by
    simpa [locationExact] using loaded
  let checked : LocalExpressionCheck.Supported entry
      (.local entry.id) entry.location.bodyBytes :=
    { id := entry.id
      location := entry.location
      idExact := rfl
      locationExact := rfl
      sourceExact := rfl
      bytesExact := rfl }
  obtain ⟨after, coreRun, machineStep, result, rip, stack, preserved, memory, flags⟩ :=
    LocalExpressionCheck.preserves checked program entryLoaded
  have localEval := evalExpr_local_of_local? 0 program coreBefore entry.id
    (.signed .i32 entry.value) entry.localValue
  refine ⟨?_, after, machineStep, ?_, ?_, ?_, ?_, memory, flags⟩
  · simpa [idExact, valueExact] using localEval
  · simpa [valueExact] using result
  · simpa [locationExact] using rip
  · exact stack
  · exact preserved

end Lanius.X86.ExpressionEnvironment
