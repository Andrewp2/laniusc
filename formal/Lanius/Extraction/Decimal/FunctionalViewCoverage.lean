import Lanius.Extraction.Decimal.ConcreteSemantics

namespace Lanius.Extraction.Decimal.FunctionalViewCoverage

open Lanius.Core
open Lanius.Extraction
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.EffectfulStateful
open Lanius.FunctionalView.FreshSimulation

/-! # Enforceable `decimal.lani` FunctionalView coverage

The inventory is reconstructed from the checked frontend artifact.  This
module therefore stops compiling if `decimal.lani` gains, loses, or renames a
function without a corresponding exact reification and checked execution
contract.
-/

def functionNames : Option (List String) :=
  (decodeReconstructedSurface verifiedFrontendDecimalArtifact).map fun surface =>
    (ArtifactContextChecker.collectFunctions surface.items).map (·.name)

theorem source_function_names : functionNames = some [
    "integer_scan", "float_scan", "number_failure", "scan_exponent",
    "finish_decimal"] := by
  native_decide

structure TheoremReference {proposition : Prop} (proof : proposition) where
  checked : proposition

private theorem reference {proposition : Prop} (proof : proposition) :
    TheoremReference proof :=
  ⟨proof⟩

structure ExactCoverage where
  sourceFunctionNames : TheoremReference source_function_names
  integerScan :
    Stateful.toCoreStmt Stateful.actionAdapter identityLayout 1
      Functions.integerScanView.command = Functions.integerScanBody
  floatScan :
    Stateful.toCoreStmt Stateful.actionAdapter identityLayout 1
      Functions.floatScanView.command = Functions.floatScanBody
  numberFailure :
    Stateful.toCoreStmt Stateful.actionAdapter identityLayout 1
      Functions.numberFailureView.command = Functions.numberFailureBody
  scanExponent :
    Stateful.toCoreStmt Stateful.actionAdapter identityLayout 3
      Functions.scanExponentView.command = Functions.scanExponentBody
  finishDecimal :
    Stateful.toCoreStmt Stateful.actionAdapter identityLayout 3
      Functions.finishDecimalView.command = Functions.finishDecimalBody

theorem exact_complete : Nonempty ExactCoverage := by
  exact ⟨{
    sourceFunctionNames := reference source_function_names
    integerScan := Functions.integerScan_toCore_exactly
    floatScan := Functions.floatScan_toCore_exactly
    numberFailure := Functions.numberFailure_toCore_exactly
    scanExponent := Functions.scanExponent_toCore_exactly
    finishDecimal := Functions.finishDecimal_toCore_exactly
  }⟩

structure SemanticCoverage where
  exact : ExactCoverage
  registryFrameSoundness : TheoremReference
    (fun source => ConcreteSemantics.framePreservingCallSoundness source)
  registryCallSoundness : TheoremReference
    (fun source => ConcreteSemantics.callSoundness source)
  integerScan : TheoremReference ConcreteSemantics.integerScan
  floatScan : TheoremReference ConcreteSemantics.floatScan
  numberFailure : TheoremReference ConcreteSemantics.numberFailure
  scanExponent : TheoremReference ConcreteSemantics.scanExponent
  finishDecimal : TheoremReference ConcreteSemantics.finishDecimal

private theorem exactCoverage : ExactCoverage := Classical.choice exact_complete

theorem concrete_complete : Nonempty SemanticCoverage := by
  exact ⟨{
    exact := exactCoverage
    registryFrameSoundness := reference
      (fun source => ConcreteSemantics.framePreservingCallSoundness source)
    registryCallSoundness := reference
      (fun source => ConcreteSemantics.callSoundness source)
    integerScan := reference ConcreteSemantics.integerScan
    floatScan := reference ConcreteSemantics.floatScan
    numberFailure := reference ConcreteSemantics.numberFailure
    scanExponent := reference ConcreteSemantics.scanExponent
    finishDecimal := reference ConcreteSemantics.finishDecimal
  }⟩

theorem complete : Nonempty SemanticCoverage := concrete_complete

end Lanius.Extraction.Decimal.FunctionalViewCoverage
