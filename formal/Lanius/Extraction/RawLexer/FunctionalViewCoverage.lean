import Lanius.Extraction.RawLexer.Results.Coverage
import Lanius.Extraction.RawLexer.ScanOne.Calls
import Lanius.Extraction.RawLexer.LexInto.EndToEnd

namespace Lanius.Extraction.RawLexer.FunctionalViewCoverage

open Lanius.Core
open Lanius.FunctionalView.Core
open Lanius.Extraction.RawLexer

/-! # Complete `raw_lexer.lani` FunctionalView gate

The declaration inventory comes from the reconstructed, checked Surface
artifact.  Exact coverage ties each mechanically reified view to its selected
Core body.  Semantic coverage is intentionally theorem-indexed; in particular,
the two control-flow functions must provide concrete contracts over the merged
checked frontend program rather than the parametric simulation lemmas used to
construct those contracts.
-/

structure TheoremReference {proposition : Prop} (proof : proposition) where
  checked : proposition

private theorem reference {proposition : Prop} (proof : proposition) :
    TheoremReference proof := ⟨proof⟩

structure ExactCoverage where
  sourceFunctionNames :
    TheoremReference Results.Coverage.raw_lexer_source_function_names
  lexStatus :
    toCoreStmt (identityLayout (arity := 1)) 1
        Results.Functions.lexStatusView.block = Results.Functions.lexStatusBody
  lexTokenCount :
    toCoreStmt (identityLayout (arity := 1)) 1
        Results.Functions.lexTokenCountView.block =
      Results.Functions.lexTokenCountBody
  lexErrorOffset :
    toCoreStmt (identityLayout (arity := 1)) 1
        Results.Functions.lexErrorOffsetView.block =
      Results.Functions.lexErrorOffsetBody
  completed :
    toCoreStmt (identityLayout (arity := 1)) 1
        Results.Functions.completedView.block = Results.Functions.completedBody
  lexicalFailure :
    toCoreStmt (identityLayout (arity := 2)) 2
        Results.Functions.lexicalFailureView.block =
      Results.Functions.lexicalFailureBody
  outputFull :
    toCoreStmt (identityLayout (arity := 2)) 2
        Results.Functions.outputFullView.block = Results.Functions.outputFullBody
  scanOne :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter identityLayout 3
        ScanOne.Functions.scanOneView.command = ScanOne.Functions.scanOneBody
  lexInto :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter identityLayout 4
        LexInto.Functions.lexIntoView.command = LexInto.Functions.lexIntoBody

theorem exact : Nonempty ExactCoverage := by
  exact ⟨{
    sourceFunctionNames :=
      reference Results.Coverage.raw_lexer_source_function_names
    lexStatus := Results.Functions.lexStatus_toCore_exactly
    lexTokenCount := Results.Functions.lexTokenCount_toCore_exactly
    lexErrorOffset := Results.Functions.lexErrorOffset_toCore_exactly
    completed := Results.Functions.completed_toCore_exactly
    lexicalFailure := Results.Functions.lexicalFailure_toCore_exactly
    outputFull := Results.Functions.outputFull_toCore_exactly
    scanOne := ScanOne.Functions.scanOne_toCore_exactly
    lexInto := LexInto.Functions.lexInto_toCore_exactly
  }⟩

/-- Concrete checked-program semantics for the six result functions.  The
    final eight-function witness below extends this reusable subset with the
    two control-flow contracts discharged against their concrete helper
    registries. -/
structure ResultSemanticCoverage where
  exact : ExactCoverage
  lexStatus : TheoremReference Results.Semantics.lexStatusCall_soundness
  lexTokenCount :
    TheoremReference Results.Semantics.lexTokenCountCall_soundness
  lexErrorOffset :
    TheoremReference Results.Semantics.lexErrorOffsetCall_soundness
  completed : TheoremReference Results.Semantics.completedCall_soundness
  lexicalFailure :
    TheoremReference Results.Semantics.lexicalFailureCall_soundness
  outputFull : TheoremReference Results.Semantics.outputFullCall_soundness

theorem resultSemantics : Nonempty ResultSemanticCoverage := by
  obtain ⟨exactCoverage⟩ := exact
  exact ⟨{
    exact := exactCoverage
    lexStatus := reference Results.Semantics.lexStatusCall_soundness
    lexTokenCount := reference Results.Semantics.lexTokenCountCall_soundness
    lexErrorOffset := reference Results.Semantics.lexErrorOffsetCall_soundness
    completed := reference Results.Semantics.completedCall_soundness
    lexicalFailure :=
      reference Results.Semantics.lexicalFailureCall_soundness
    outputFull := reference Results.Semantics.outputFullCall_soundness
  }⟩

/-- Complete semantic coverage of all eight checked functions reconstructed
from `raw_lexer.lani`.  The two control-flow entries name their concrete,
premise-free checked-program contracts rather than the generic simulation
lemmas used internally to prove them. -/
structure SemanticCoverage extends ResultSemanticCoverage where
  scanOne : TheoremReference (@ScanOne.Calls.callSoundness)
  lexInto : TheoremReference (@LexInto.EndToEnd.call_executes)

theorem complete : Nonempty SemanticCoverage := by
  obtain ⟨results⟩ := resultSemantics
  exact ⟨{
    toResultSemanticCoverage := results
    scanOne := reference ScanOne.Calls.callSoundness
    lexInto := reference LexInto.EndToEnd.call_executes
  }⟩

end Lanius.Extraction.RawLexer.FunctionalViewCoverage
