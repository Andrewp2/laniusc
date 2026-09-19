import Lanius.Extraction.CompactOutput.Digit
import Lanius.Separation.HeapFrame

namespace Lanius.Extraction.Entry.Hex

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.Source Lanius.Extraction.CompactOutput

def body : Stmt :=
  .sequence (.ifThenElse
    (binary .logicalAnd (binary .greaterEqual (read 0) (number 48))
      (binary .lessEqual (read 0) (number 57)))
    (returned (binary .subtract (read 0) (number 48))) .skip)
    (returned (binary .subtract (read 0) (number 87)))

abbrev Checked (program : CoreSynthesis.Program.CheckedProgram artifacts) :=
  CheckedInternal program ["app", "main"] "hex_nibble" [(0, i32)] i32 body

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts) : Option (Checked program) :=
  checkInternal? program ["app", "main"] "hex_nibble" [(0, i32)] i32 body

/-- The source helper decodes every lowercase hexadecimal digit, not only
the particular digits occurring in the embedded grammar. -/
theorem executes (program : Program) (value : Nat) (bounded : value < 16)
    (found : before.local? 0 = some (.signed .i32 (hexDigit value))) :
    Executes program before body (.returned (some (.signed .i32 value))) before := by
  have lower : Evaluates program before (binary .greaterEqual (read 0) (number 48))
      (.boolean true) before := by
    apply evaluatesEagerBinary (by decide) (by decide)
      (local_evaluates program found) (show Evaluates program before (number 48) (.signed .i32 48) before from evaluatesValue)
    simp [evalBinaryValue, evalSignedBinary, hexDigit]
    split <;> omega
  have upper : Evaluates program before (binary .lessEqual (read 0) (number 57))
      (.boolean (decide (value < 10))) before := by
    apply evaluatesEagerBinary (by decide) (by decide)
      (local_evaluates program found) (show Evaluates program before (number 57) (.signed .i32 57) before from evaluatesValue)
    simp only [evalBinaryValue, evalSignedBinary, BEq.rfl, if_true, Except.ok.injEq,
      Value.boolean.injEq, decide_eq_decide]
    unfold hexDigit
    split <;> omega
  have condition := evaluatesPureLogicalAnd lower upper
  by_cases small : value < 10
  · have digit : hexDigit value = 48 + value := by simp [hexDigit, small]
    have sub := evaluatesNatI32Subtract (local_evaluates program found)
      (show Evaluates program before (number 48) (.signed .i32 48) before from evaluatesValue)
      (by omega : 48 ≤ hexDigit value) (by omega : hexDigit value - 48 ≤ 2147483647)
    have result : hexDigit value - 48 = value := by omega
    rw [result] at sub
    exact executesSequenceReturned (executesIfTrue
      (by simpa [small] using condition) (executesSequenceReturned (executesReturnValue sub)))
  · have digit : hexDigit value = 87 + value := by simp [hexDigit, small]
    have sub := evaluatesNatI32Subtract (local_evaluates program found)
      (show Evaluates program before (number 87) (.signed .i32 87) before from evaluatesValue)
      (by omega : 87 ≤ hexDigit value) (by omega : hexDigit value - 87 ≤ 2147483647)
    have result : hexDigit value - 87 = value := by omega
    rw [result] at sub
    exact executesSequence (executesIfFalse (by simpa [small] using condition) (executesSkip program before))
      (executesSequenceReturned (executesReturnValue sub))

theorem Checked.decode (checked : Checked program) (value : Nat) (bounded : value < 16)
    (wellFormed : StateWellFormed before)
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments [.signed .i32 (hexDigit value)] before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
      (.signed .i32 value) after ∧ CellEffect CellSet.empty before after ∧ HeapFrame before after := by
  let bindings : List (Lanius.VarId × Value) := [(0, .signed .i32 (hexDigit value))]
  have found : (enterCall before bindings).local? 0 = some (.signed .i32 (hexDigit value)) :=
    enterCall_local_of_binding before [] [] 0 (.signed .i32 (hexDigit value)) wellFormed (by simp)
  have run := executes program.core value bounded found
  have called := checked.call wellFormed argumentsResult (bindings := bindings) rfl run
    (CellEffect.refl (writes := CellSet.empty) (enterCall_preserves_wellFormed wellFormed))
  exact ⟨restoreLocals before (enterCall before bindings),
    called.1, called.2,
    HeapFrame.closeCall before bindings (HeapFrame.refl _)⟩

end Lanius.Extraction.Entry.Hex
