import Lanius.X86.Source.Require
import Lanius.X86.Control.Calls
import Lanius.X86.Buffer.Emission
import Lanius.X86.Buffer.Locals
import Lanius.X86.Machine.Index

namespace Lanius.X86.Control.Require

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer Lanius.X86.Control

def inputValues (output : Value) (capacity start : Int) (condition : Fin 16) : List Value :=
  [output, .signed .i32 capacity, .signed .i32 start, .signed .i32 condition.val]

@[simp] theorem inputValues_length : (inputValues output capacity start condition).length = 4 := rfl

def branchBytes (condition : Fin 16) : List UInt8 :=
  (Transfer.branch condition).header.map UInt8.ofNat ++ i32Bytes 2

def bytes (condition : Fin 16) : List UInt8 := branchBytes condition ++ [15, 11]

@[simp] theorem branchBytes_length : (branchBytes condition).length = 6 := by
  simp [branchBytes, Transfer.header, Transfer.conditional, i32Bytes_length]

@[simp] theorem bytes_length : (bytes condition).length = 8 := by
  simp [bytes]

def written (condition : Fin 16) (values : List Int) (start : Nat) : List Int :=
  writtenBytes (Relative.emittedValues (.branch condition) values start (start + 8)) (start + 6) [15, 11]

theorem emission (condition : Fin 16) (room : start + 8 ≤ values.length) :
    Emission values start (bytes condition) (written condition values start) := by
  have displacement : relativeDisplacement (start + 6) (start + 8) = 2 := by
    simp only [relativeDisplacement]
    omega
  have branch : Emission values start (branchBytes condition)
      (Relative.emittedValues (.branch condition) values start (start + 8)) := by
    refine ⟨Relative.emittedValues_length, ?_, ?_⟩
    · rw [branchBytes_length]
      have exactBytes := Relative.emittedValues_bytes (.branch condition) (by change start + 6 ≤ values.length; omega)
        (target := start + 8)
      change byteSlice _ start 6 = _ at exactBytes
      change _ = (Transfer.branch condition).header.map UInt8.ofNat ++ i32Bytes (relativeDisplacement (start + 6) (start + 8)) at exactBytes
      rw [displacement] at exactBytes
      exact exactBytes
    · intro index outside
      apply Relative.emittedValues_frame
      simpa [branchBytes_length, Transfer.size, Transfer.conditional] using outside
  have trap : Emission (Relative.emittedValues (.branch condition) values start (start + 8))
      (start + (branchBytes condition).length) [15, 11] (written condition values start) := by
    rw [branchBytes_length]
    refine ⟨writtenBytes_length, ?_, fun _ outside => writtenBytes_frame outside⟩
    exact writtenBytes_byteSlice (by simp only [Relative.emittedValues_length]; change start + 6 + 2 ≤ values.length; omega)
  exact branch.append trap

/-- Exhaustive decoding of the finite condition-code space, checked by the
kernel. There is no native evaluator assumption. -/
theorem decodes : ∀ condition : Fin 16,
    Machine.decode (bytes condition) = some (.branch condition 2, 6) := by decide

/-- A guard executes one branch. It either skips UD2 or reaches its precise
fault address; memory, registers, and flags are unchanged in both cases. -/
def Outcome (code : Fin 16) (before : Machine.State) : Prop :=
  let after := before.branch code 2 6
  Machine.Step before after ∧
    after.memory = before.memory ∧ after.registers = before.registers ∧ after.flags = before.flags ∧
    if Machine.condition before.flags code then after.rip = before.rip + 8
    else after.rip = before.rip + 6 ∧ Machine.Fault after

theorem executes (code : Fin 16) (before : Machine.State)
    (loaded : Machine.CodeAt before.memory before.rip (bytes code)) : Outcome code before := by
  refine ⟨.decoded _ loaded _ _ (decodes code) rfl, rfl, rfl, rfl, ?_⟩
  cases selected : Machine.condition before.flags code with
  | true => simp [Machine.State.branch, selected, BitVec.add_assoc]
  | false =>
      have rip : (before.branch code 2 6).rip = before.rip + 6 := by
        simp [Machine.State.branch, selected]
      have trapCode : Machine.CodeAt (before.branch code 2 6).memory (before.branch code 2 6).rip [15, 11] := by
        rw [show (before.branch code 2 6).memory = before.memory from rfl, rip]
        have remaining := (show Machine.CodeAt before.memory before.rip
          (branchBytes code ++ [15, 11]) from loaded).suffix
        rw [branchBytes_length] at remaining
        exact remaining
      exact ⟨rip, .ud2 trapCode⟩

/-- Execute both real emitter calls and the intervening lexical binding.
The jump target skips precisely the two-byte UD2, at any output offset. -/
theorem body (checked : Source.Require.Checked program branch trap) (condition : Fin 16) (capacity start : Nat)
    (wellFormed : StateWellFormed before)
    (inputs : Locals (inputValues (.slice i32 cell [] 0 values.length) capacity start condition) frontier before)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + 8 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after, Executes program.core before (Source.Require.body branch.source.function.id trap.source.function.id)
        (.returned (some (.signed .i32 (start + 8 : Nat)))) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values (written condition values start))) } ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  have target := evaluatesNatI32Add (local_evaluates program.core (inputs.found ⟨2, by simp⟩))
    (show Evaluates program.core before (number 8) (.signed .i32 (8 : Nat)) before from ⟨1, rfl⟩) (by omega)
  have args : ArgumentsEvaluateTo program.core before Source.Require.branchArguments
      (branchValues (.slice i32 cell [] 0 values.length) capacity start condition.val (start + 8 : Nat)) before :=
    .cons (local_evaluates program.core (inputs.found ⟨0, by simp⟩))
      (.cons (local_evaluates program.core (inputs.found ⟨1, by simp⟩))
        (.cons (local_evaluates program.core (inputs.found ⟨2, by simp⟩))
          (.cons (local_evaluates program.core (inputs.found ⟨3, by simp⟩)) (.cons target (.nil _ _)))))
  obtain ⟨branched, branchRun, branchBacking, _, branchEffect, branchHeap⟩ :=
    branch_success branch condition capacity start (start + 8) wellFormed (by omega) storage bounded (by omega) backing args
  let middle := Relative.emittedValues (.branch condition) values start (start + 8)
  let next := start + 6
  let scope := branched.bindLocal 4 (.signed .i32 next)
  have scopeWF := bindLocal_preserves_well_formed branched 4 (.signed .i32 next) branchEffect.wellFormed
  have notArray : ∀ index : Fin 4, (inputValues (.slice i32 cell [] 0 values.length) capacity start condition).get index ≠
      .array (signedI32Values values) := by
    intro ⟨index, bound⟩
    have cases : index = 0 ∨ index = 1 ∨ index = 2 ∨ index = 3 := by omega
    rcases cases with rfl | rfl | rfl | rfl <;> intro same <;> cases same
  have scopeInputs := (inputs.store wellFormed branchEffect backing notArray).bind branchEffect.wellFormed
    (show (inputValues (.slice i32 cell [] 0 values.length) capacity start condition).length ≤ 4 from by simp) (.signed .i32 next)
  have scopeNext := bindLocal_finds_local branched 4 (.signed .i32 next) branchEffect.wellFormed
  have scopeBacking := ((bindLocal_effect branched 4 (.signed .i32 next)).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry branchEffect.wellFormed branchBacking) (by simp [CellSet.empty])).trans branchBacking
  have trapArgs : ArgumentsEvaluateTo program.core scope [read 0, read 1, read 4]
      (fixedValues (.slice i32 cell [] 0 middle.length) capacity next) scope := by
    have outputRead : scope.local? 0 = some (.slice i32 cell [] 0 middle.length) := by
      have read := scopeInputs.found ⟨0, by simp⟩
      change scope.local? 0 = some (.slice i32 cell [] 0 values.length) at read
      simpa only [middle, Relative.emittedValues_length] using read
    exact .cons (local_evaluates program.core outputRead)
      (.cons (local_evaluates program.core (scopeInputs.found ⟨1, by simp⟩))
        (.cons (local_evaluates program.core scopeNext) (.nil _ _)))
  obtain ⟨completed, trapRun, contents, trapEffect, trapHeap⟩ := fixed_success trap capacity next scopeWF
    (by change start + 6 + 2 ≤ capacity; omega) (by simpa only [middle, Relative.emittedValues_length] using storage)
    bounded scopeBacking trapArgs
  have tail : Executes program.core scope (returned (.call trap.source.function.id [read 0, read 1, read 4]))
      (.returned (some (.signed .i32 (start + 8 : Nat)))) completed := by
    have size : next + [15, 11].length = start + 8 := rfl
    rw [size] at trapRun
    exact executesSequenceReturned (executesReturnValue trapRun)
  exact ⟨restoreLocals branched completed, executesLetLocal branchRun tail, contents,
    branchEffect.trans (CellEffect.closeLocal branched 4 (.signed .i32 next) branchEffect.wellFormed trapEffect),
    branchHeap.trans (HeapFrame.closeLocal branched 4 (.signed .i32 next) trapHeap)⟩

theorem emits (checked : Source.Require.Checked program branch trap) (condition : Fin 16) (capacity start : Nat)
    (wellFormed : StateWellFormed before)
    (backing : before.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values values)) })
    (room : start + 8 ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      (inputValues (.slice i32 cell [] 0 values.length) capacity start condition) before) :
    ∃ after emitted, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (start + 8 : Nat)) after ∧
      after.cellEntry? cell = some { id := cell, value := some (.array (signedI32Values emitted)) } ∧
      Emission values start (bytes condition) emitted ∧
      (∀ machine, Machine.CodeAt machine.memory machine.rip (byteSlice emitted start 8) → Outcome condition machine) ∧
      CellEffect (CellSet.singleton cell) before after ∧ HeapFrame before after := by
  let params := parameterBindings (fun index : Fin 4 =>
    (inputValues (.slice i32 cell [] 0 values.length) capacity start condition).get index)
  have calleeWF := enterCall_preserves_wellFormed wellFormed (bindings := params)
  have inputs := Locals.ofReads (values := inputValues (.slice i32 cell [] 0 values.length) capacity start condition) calleeWF
    (fun index => enterCall_parameterBindings_matches wellFormed index)
  have calleeBacking := ((enterCall_effect before params).oldCells cell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  obtain ⟨completed, run, contents, effect, heap⟩ := body checked condition capacity start calleeWF inputs calleeBacking room storage bounded
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl run effect
  have window := emission condition (values := values) (by omega : start + 8 ≤ values.length)
  refine ⟨restoreLocals before completed, written condition values start, called.1, contents,
    window, ?_, called.2, HeapFrame.closeCall before params heap⟩
  intro machine loaded
  have exactBytes := window.bytes
  rw [bytes_length] at exactBytes
  rw [exactBytes] at loaded
  exact executes condition machine loaded

/-- The condition used by checked indexing is exactly the already-proved
machine guard, not a second independently chosen instruction sequence. -/
theorem below_bytes : bytes 2 = Machine.Index.guard := by decide

end Lanius.X86.Control.Require
