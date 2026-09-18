import Lanius.X86.Frame.Layout
import Lanius.X86.Source.Buffer
import Lanius.X86.Buffer.Reservation
import Lanius.X86.Relative.Core
import Lanius.Separation.HeapFrame
import Lanius.FunctionalViewCoreCallFrame

namespace Lanius.X86.Frame

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.X86.Source Lanius.X86.Buffer Lanius.FunctionalView.Core

def displacementExpr : Expr := .binary .multiply (.unary .negate (.binary .add (read 0) (number 1))) (number 8)
def bytesExpr : Expr := .binary .multiply (.binary .divide (.binary .add (read 0) (number 1)) (number 2)) (number 16)

abbrev CheckedDisplacement (program : Lanius.Extraction.CoreSynthesis.Program.CheckedProgram artifacts) :=
  Lanius.Extraction.Source.CheckedInternal program ["backend", "frame"] "displacement" [(0, i32)] i32 (returned displacementExpr)
abbrev CheckedBytes (program : Lanius.Extraction.CoreSynthesis.Program.CheckedProgram artifacts) :=
  Lanius.Extraction.Source.CheckedInternal program ["backend", "frame"] "bytes" [(0, i32)] i32 (returned bytesExpr)

def checkDisplacement? (program : Lanius.Extraction.CoreSynthesis.Program.CheckedProgram artifacts) : Option (CheckedDisplacement program) :=
  Lanius.Extraction.Source.checkInternal? program ["backend", "frame"] "displacement" [(0, i32)] i32 (returned displacementExpr)
def checkBytes? (program : Lanius.Extraction.CoreSynthesis.Program.CheckedProgram artifacts) : Option (CheckedBytes program) :=
  Lanius.Extraction.Source.checkInternal? program ["backend", "frame"] "bytes" [(0, i32)] i32 (returned bytesExpr)

theorem displacement_evaluates (program : Program) (slot : Nat) (bounded : slot ≤ 1048576)
    (found : before.local? 0 = some (.signed .i32 slot)) :
    Evaluates program before displacementExpr (.signed .i32 (displacement slot)) before := by
  have added := evaluatesNatI32Add (leftValue := slot) (rightValue := 1) (local_evaluates program found)
    (show Evaluates program before (number 1) (.signed .i32 1) before from ⟨1, rfl⟩) (by omega)
  have negative : Evaluates program before (.unary .negate (.binary .add (read 0) (number 1)))
      (.signed .i32 (-(slot + 1 : Nat) : Int)) before := by
    apply evaluatesUnary added
    have wrap := wrap_relative program.target (slot + 1) 0 (by omega) (by decide)
    simpa only [evalUnaryValue, relativeDisplacement, Int.natCast_zero, Int.zero_sub, Int.ofNat_eq_natCast] using
      congrArg (fun value => (Except.ok (Value.signed .i32 value) : Except Lanius.Trap Value)) wrap
  apply evaluatesEagerBinary (by decide) (by decide) negative
    (show Evaluates program before (number 8) (.signed .i32 8) before from ⟨1, rfl⟩)
  have wrap : wrapSigned program.target .i32 (displacement slot) = displacement slot := by
    have wrapped := wrap_relative program.target ((slot + 1) * 8) 0 (by omega) (by decide)
    simpa [relativeDisplacement, displacement, Int.natCast_mul, Int.neg_mul] using wrapped
  change Except.ok (Value.signed .i32 (wrapSigned program.target .i32 (displacement slot))) = _
  rw [wrap]

theorem bytes_evaluates (program : Program) (slots : Nat) (bounded : slots ≤ 1048576)
    (found : before.local? 0 = some (.signed .i32 slots)) :
    Evaluates program before bytesExpr (.signed .i32 (bytes slots)) before := by
  have added := evaluatesNatI32Add (leftValue := slots) (rightValue := 1) (local_evaluates program found)
    (show Evaluates program before (number 1) (.signed .i32 1) before from ⟨1, rfl⟩) (by omega)
  have divided := evaluatesNatI32Divide (leftValue := slots + 1) (rightValue := 2) added
    (show Evaluates program before (number 2) (.signed .i32 2) before from ⟨1, rfl⟩) (by decide) (by omega)
  exact evaluatesNatI32Multiply (leftValue := (slots + 1) / 2) (rightValue := 16) divided
    (show Evaluates program before (number 16) (.signed .i32 16) before from ⟨1, rfl⟩) (by omega)

theorem displacement_call (checked : CheckedDisplacement program) (slot : Nat) (bounded : slot ≤ 1048576)
    (wellFormed : StateWellFormed before)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments [.signed .i32 slot] before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments) (.signed .i32 (displacement slot)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let bindings := parameterBindings (fun _ : Fin 1 => Value.signed .i32 slot)
  let entered := enterCall before bindings
  have enteredWF := enterCall_preserves_wellFormed wellFormed (bindings := bindings)
  have found : entered.local? 0 = some (.signed .i32 slot) := enterCall_parameterBindings_matches wellFormed ⟨0, by decide⟩
  have run := executesSequenceReturned (second := .skip) (executesReturnValue (displacement_evaluates program.core slot bounded found))
  have called := checked.call wellFormed argumentsResult (bindings := bindings) rfl run (CellEffect.refl (writes := CellSet.empty) enteredWF)
  exact ⟨restoreLocals before entered, called.1, called.2, HeapFrame.closeCall before bindings (HeapFrame.refl entered)⟩

theorem bytes_call (checked : CheckedBytes program) (slots : Nat) (bounded : slots ≤ 1048576)
    (wellFormed : StateWellFormed before)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments [.signed .i32 slots] before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments) (.signed .i32 (bytes slots)) after ∧
      CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let bindings := parameterBindings (fun _ : Fin 1 => Value.signed .i32 slots)
  let entered := enterCall before bindings
  have enteredWF := enterCall_preserves_wellFormed wellFormed (bindings := bindings)
  have found : entered.local? 0 = some (.signed .i32 slots) := enterCall_parameterBindings_matches wellFormed ⟨0, by decide⟩
  have run := executesSequenceReturned (second := .skip) (executesReturnValue (bytes_evaluates program.core slots bounded found))
  have called := checked.call wellFormed argumentsResult (bindings := bindings) rfl run (CellEffect.refl (writes := CellSet.empty) enteredWF)
  exact ⟨restoreLocals before entered, called.1, called.2, HeapFrame.closeCall before bindings (HeapFrame.refl entered)⟩

end Lanius.X86.Frame
