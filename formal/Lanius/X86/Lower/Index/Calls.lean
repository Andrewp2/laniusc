import Lanius.X86.Lower.Index.State
import Lanius.X86.Encode.Direct
import Lanius.X86.Encode.Guarded
import Lanius.X86.Control.Require

namespace Lanius.X86.Lower.Index.Emission

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.X86.Source Lanius.X86.Buffer

inductive Chunk where
  | normalize | length | pointer | compare | require

def Chunk.expression (chunk : Chunk) (constants : Source.Index.Constants program) (calls : Source.Index.Calls) : Expr :=
  match chunk with
  | .normalize => .call calls.normalize [read 0, read 1, Source.Index.next, .constant constants.rax.id, .constant constants.rax.id]
  | .length => Source.Index.loadLength constants calls
  | .pointer => Source.Index.loadPointer constants calls
  | .compare => Source.Index.compare constants calls
  | .require => Source.Index.require constants calls

def Chunk.cursor (chunk : Chunk) (constants : Source.Index.Constants program) : Expr :=
  match chunk with | .length => Source.Index.current constants | _ => Source.Index.next

def Chunk.bytes : Chunk → List UInt8
  | .normalize => Machine.Index.normalize.bytes
  | .length => (Machine.Index.load 10 11 8).bytes
  | .pointer => (Machine.Index.load 11 11 0).bytes
  | .compare => Machine.Index.compare.bytes
  | .require => Machine.Index.guard

theorem Chunk.size (chunk : Chunk) : chunk.bytes.length = match chunk with
    | .normalize | .compare => 3 | .length | .pointer => 7 | .require => 8 := by
  cases chunk <;> rfl

/-- The five output-only calls in the actual indexing body. The source
cursor expression is evaluated explicitly: the first descriptor load reads
workspace CODE; the other four calls read the lexical cursor. -/
theorem call (chunk : Chunk) (checked : Source.Index.Checked emitters)
    (ready : Ready before output work temporary frontier capacity slot kind cursor values workspace)
    (start : Nat) (position : Evaluates emitters.pack.program.core before (chunk.cursor checked.constants) (.signed .i32 start) before)
    (room : start + chunk.bytes.length ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after emitted, Evaluates emitters.pack.program.core before (chunk.expression checked.constants checked.helpers.calls)
        (.signed .i32 (start + chunk.bytes.length : Nat)) after ∧
      after.cellEntry? output = some { id := output, value := some (.array (signedI32Values emitted)) } ∧
      Buffer.Emission values start chunk.bytes emitted ∧
      CellEffect (CellSet.singleton output) before after ∧ HeapFrame before after := by
  have outRead : before.local? 0 = some (.slice i32 output [] 0 values.length) := ready.inputs.found ⟨0, by simp⟩
  have capRead : before.local? 1 = some (.signed .i32 capacity) := ready.inputs.found ⟨1, by simp⟩
  have rax := checked.constants.rax.evaluates (before := before)
  have r10 := checked.constants.r10.evaluates (before := before)
  have r11 := checked.constants.r11.evaluates (before := before)
  have cmp := checked.constants.cmp.evaluates (before := before)
  have below := checked.constants.below.evaluates (before := before)
  rcases checked.constants.values with ⟨_, _, _, raxValue, r10Value, r11Value, cmpValue, belowValue⟩
  rw [raxValue] at rax
  rw [r10Value] at r10
  rw [r11Value] at r11
  rw [cmpValue] at cmp
  rw [belowValue] at below
  cases chunk with
  | normalize =>
      have args : ArgumentsEvaluateTo emitters.pack.program.core before
          [read 0, read 1, Source.Index.next, .constant checked.constants.rax.id, .constant checked.constants.rax.id]
          (Encode.Direct.inputs .signExtend (.slice i32 output [] 0 values.length) capacity start 64 0 0) before :=
        .cons (local_evaluates _ outRead) (.cons (local_evaluates _ capRead) (.cons position
          (.cons rax (.cons rax (.nil _ _)))))
      obtain ⟨after, run, contents, effect, heap⟩ := (Encode.Direct.succeeds
        (emitters.registerWrappers .signExtend) .w64 0 0 capacity start room storage bounded).call
        ready.wellFormed args ready.outputBacking
      have emission := (Encode.Direct.config .signExtend .w64 0 0).emission (values := values) (Nat.le_trans room storage)
      exact ⟨after, _, run, contents, ⟨emission.length, emission.bytes, emission.frame⟩, effect, heap⟩
  | length =>
      have args : ArgumentsEvaluateTo emitters.pack.program.core before
          [read 0, read 1, Source.Index.current checked.constants, number 64,
            .constant checked.constants.r10.id, .constant checked.constants.r11.id, number 8]
          (Encode.Memory.moveValues (.slice i32 output [] 0 values.length) capacity start .w64 10 11 8) before :=
        .cons (local_evaluates _ outRead) (.cons (local_evaluates _ capRead) (.cons position
          (.cons ⟨1, rfl⟩ (.cons r10 (.cons r11 (.cons ⟨1, rfl⟩ (.nil _ _)))))))
      obtain ⟨after, emitted, run, contents, bytes, _, length, frame, effect, heap⟩ := Encode.Memory.move_emits
        checked.helpers.load .w64 10 11 8 capacity start ready.wellFormed room storage bounded ready.outputBacking args
      exact ⟨after, emitted, run, contents, ⟨length, bytes, frame⟩, effect, heap⟩
  | pointer =>
      have args : ArgumentsEvaluateTo emitters.pack.program.core before
          [read 0, read 1, Source.Index.next, number 64,
            .constant checked.constants.r11.id, .constant checked.constants.r11.id, number 0]
          (Encode.Memory.moveValues (.slice i32 output [] 0 values.length) capacity start .w64 11 11 0) before :=
        .cons (local_evaluates _ outRead) (.cons (local_evaluates _ capRead) (.cons position
          (.cons ⟨1, rfl⟩ (.cons r11 (.cons r11 (.cons ⟨1, rfl⟩ (.nil _ _)))))))
      obtain ⟨after, emitted, run, contents, bytes, _, length, frame, effect, heap⟩ := Encode.Memory.move_emits
        checked.helpers.load .w64 11 11 0 capacity start ready.wellFormed room storage bounded ready.outputBacking args
      exact ⟨after, emitted, run, contents, ⟨length, bytes, frame⟩, effect, heap⟩
  | compare =>
      let choice : Encode.Guarded.Choice .binary := ⟨57, by decide⟩
      have args : ArgumentsEvaluateTo emitters.pack.program.core before
          [read 0, read 1, Source.Index.next, number 64, .constant checked.constants.cmp.id,
            .constant checked.constants.rax.id, .constant checked.constants.r10.id]
          (Encode.Guarded.inputs .binary (.slice i32 output [] 0 values.length) capacity start 64 57 0 10) before :=
        .cons (local_evaluates _ outRead) (.cons (local_evaluates _ capRead) (.cons position
          (.cons ⟨1, rfl⟩ (.cons cmp (.cons rax (.cons r10 (.nil _ _)))))))
      obtain ⟨after, run, contents, effect, heap⟩ := (Encode.Guarded.succeeds
        checked.helpers.compare choice .w64 0 10 capacity start room storage bounded).call
        ready.wellFormed args ready.outputBacking
      have emission := (Encode.Guarded.config .binary choice .w64 0 10).emission (values := values) (Nat.le_trans room storage)
      have encoding : (Encode.Guarded.config .binary choice .w64 0 10).bytes.map UInt8.ofNat = Chunk.compare.bytes := by decide
      have exactBytes := emission.bytes
      rw [encoding] at exactBytes
      exact ⟨after, _, run, contents, ⟨emission.length, exactBytes, emission.frame⟩, effect, heap⟩
  | require =>
      have args : ArgumentsEvaluateTo emitters.pack.program.core before
          [read 0, read 1, Source.Index.next, .constant checked.constants.below.id]
          (Control.Require.inputValues (.slice i32 output [] 0 values.length) capacity start 2) before :=
        .cons (local_evaluates _ outRead) (.cons (local_evaluates _ capRead) (.cons position (.cons below (.nil _ _))))
      obtain ⟨after, emitted, run, contents, emission, _, effect, heap⟩ := Control.Require.emits
        checked.helpers.require 2 capacity start ready.wellFormed ready.outputBacking room storage bounded args
      exact ⟨after, emitted, run, contents, emission, effect, heap⟩

/-- Compose the actual call with its source assignment, retaining the
emitted window and the cursor/array invariant for the following statement. -/
theorem step (chunk : Chunk) (checked : Source.Index.Checked emitters)
    (ready : Ready before output work temporary frontier capacity slot kind cursor values workspace)
    (start : Nat) (position : Evaluates emitters.pack.program.core before (chunk.cursor checked.constants) (.signed .i32 start) before)
    (room : start + chunk.bytes.length ≤ capacity) (storage : capacity ≤ values.length) (bounded : capacity ≤ 2147483647) :
    ∃ after emitted, Executes emitters.pack.program.core before (Source.Index.setNext (chunk.expression checked.constants checked.helpers.calls)) .next after ∧
      Ready after output work temporary frontier capacity slot kind (start + chunk.bytes.length) emitted workspace ∧
      Buffer.Emission values start chunk.bytes emitted ∧
      CellEffect (CellSet.union (CellSet.singleton output) (CellSet.singleton temporary)) before after ∧ HeapFrame before after := by
  obtain ⟨middle, emitted, run, contents, emission, effect, heap⟩ := call chunk checked ready start position room storage bounded
  obtain ⟨after, assigned, afterReady, combined, combinedHeap⟩ := ready.assign run effect heap contents emission.length
  exact ⟨after, emitted, assigned, afterReady, emission, combined, combinedHeap⟩

end Lanius.X86.Lower.Index.Emission
