import Lanius.Extraction.OutputPacking.Prefix
import Lanius.Extraction.CertificateEmitterFrame

namespace Lanius.Extraction.CertificateEmitterPackingExecution

open Lanius Lanius.Core Lanius.Extraction Lanius.Semantics
open Lanius.Extraction.OutputPacking Lanius.Extraction.CertificateEmitterFrame
structure SourcePackStep (program : Program) (body : Stmt) (root : CellId) where
  before : State
  after : State
  remaining : List UInt8
  afterRemaining : List UInt8
  output : List Value
  afterOutput : List Value
  chunk : List UInt8
  threshold : Nat
  stable : StableStmt threshold program before body .next after
  memory : after.cellEntry? root = some { id := root, value := some (.array afterOutput) }
  frame : WriteFrame before after root (.array afterOutput)
  reads : remaining = chunk ++ afterRemaining
  lanes : ∀ lane, lane < 4 →
    (remaining[lane]?).getD 0 = (chunk[lane]?).getD 0
  chunkBound : 0 < chunk.length ∧ chunk.length ≤ 4
  fullOrFinal : chunk.length = 4 ∨ afterRemaining = []
  write : afterOutput = output ++ pack chunk

def PackTrace (program : Program) (body : Stmt) (root : CellId)
    (steps : List (SourcePackStep program body root)) (caller : State)
    (bytes : List UInt8) (output : List Value) (final : State)
    (remaining : List UInt8) (finalOutput : List Value) : Prop :=
  match steps with
  | [] => final = caller ∧ remaining = bytes ∧ finalOutput = output
  | step :: rest =>
      step.before = caller ∧ step.remaining = bytes ∧ step.output = output ∧ PackTrace
        program body root rest step.after step.afterRemaining step.afterOutput final remaining finalOutput

theorem pack_append_four_or_final (chunk rest : List UInt8)
    (shape : chunk.length = 4 ∨ rest = []) :
    pack (chunk ++ rest) = pack chunk ++ pack rest := by
  rcases shape with four | empty
  · cases chunk with
    | nil => simp at four
    | cons a tail =>
      cases tail with
      | nil => simp at four
      | cons b tail =>
        cases tail with
        | nil => simp at four
        | cons c tail =>
          cases tail with
          | nil => simp at four
          | cons d tail =>
            have tailEmpty : tail = [] := by
              apply List.eq_nil_of_length_eq_zero
              simpa using four
            subst tail
            rfl
  · subst rest
    simp [pack]

private theorem frame_root_bound {before after : State} {root : CellId} {value : Value}
    (frame : WriteFrame before after root value) (bound : root < before.nextCell) :
    root < after.nextCell := by
  rcases frame with ⟨middle, caller, _, next, _, _, _, _⟩
  rcases caller.cells with ⟨_, _, frontier, _⟩
  rw [next]
  exact Nat.lt_of_lt_of_le bound frontier

theorem sourcePackTrace_result
    (trace : PackTrace program body root steps caller bytes output final [] finalOutput)
    (rootBound : root < caller.nextCell) : finalOutput = output ++ pack bytes ∧ steps.length =
      (bytes.length + 3) / 4 ∧ (steps = [] ∧ final = caller ∨ WriteFrame caller final root (.array finalOutput)) := by
  induction steps generalizing caller bytes output with
  | nil =>
      simp only [PackTrace] at trace
      rcases trace with ⟨rfl, rfl, rfl⟩
      simp [pack]
  | cons step rest ih =>
      simp only [PackTrace] at trace
      rcases trace with ⟨beforeEq, remainingEq, outputEq, tail⟩
      subst beforeEq; subst remainingEq
      have nextBound := frame_root_bound step.frame rootBound
      have tailResult := ih tail nextBound
      rcases tailResult with ⟨tailOutput, tailCount, tailFrame⟩
      refine ⟨?_, ?_, ?_⟩
      · rw [tailOutput, step.write, step.reads,
          outputEq, pack_append_four_or_final _ _ step.fullOrFinal]
        simp [List.append_assoc]
      · rw [List.length_cons, tailCount, step.reads]
        simp only [List.length_append]
        rcases step.fullOrFinal with full | final
        · rw [full]
          omega
        · rw [final]
          simp only [List.length_nil, Nat.add_zero]
          have lower := step.chunkBound.1
          have upper := step.chunkBound.2
          have cases : step.chunk.length = 1 ∨ step.chunk.length = 2 ∨
              step.chunk.length = 3 ∨ step.chunk.length = 4 := by omega
          rcases cases with h | h | h | h <;> simp [h]
      · rcases tailFrame with ⟨restNil, finalEq⟩ | frame
        · right
          have tailShape : final = step.after ∧ step.afterRemaining = [] ∧
              finalOutput = step.afterOutput := by simpa [restNil, PackTrace] using tail
          rw [tailShape.1, tailShape.2.2]
          exact step.frame
        · right
          exact WriteFrame.trans step.frame frame rootBound

theorem pack_in_place_complete (bytes : List UInt8) (trace : PackTrace program body root steps caller bytes [] final [] finalOutput)
    (rootBound : root < caller.nextCell) : finalOutput.take ((bytes.length + 3) / 4) = pack bytes ∧
      steps.length = (bytes.length + 3) / 4 ∧
      (steps = [] ∧ final = caller ∨ WriteFrame caller final root (.array finalOutput)) := by
  have result := sourcePackTrace_result trace rootBound; refine ⟨?_, result.2.1, result.2.2⟩
  rw [result.1, List.nil_append, ← pack_length bytes]
  exact List.take_length

end Lanius.Extraction.CertificateEmitterPackingExecution
