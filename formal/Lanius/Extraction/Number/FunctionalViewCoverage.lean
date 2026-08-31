import Lanius.Extraction.Number.Calls

namespace Lanius.Extraction.Number.FunctionalViewCoverage

open Lanius.Core
open Lanius.Compiler.Lexer
open Lanius.Extraction
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.FreshSimulation

/-! # Enforceable `number.lani` FunctionalView coverage

The source inventory comes from reconstruction of the checked artifact.  The
coverage witness therefore fails when a function is added, removed, renamed,
or loses either its exact reification or checked-program call contract.
-/

def functionNames : Option (List String) :=
  (decodeReconstructedSurface verifiedFrontendNumberArtifact).map fun surface =>
    (ArtifactContextChecker.collectFunctions surface.items).map (·.name)

theorem source_function_names :
    functionNames = some ["scan_number", "scan_leading_dot_number"] := by
  native_decide

structure TheoremReference {proposition : Prop} (proof : proposition) where
  checked : proposition

private theorem reference {proposition : Prop} (proof : proposition) :
    TheoremReference proof :=
  ⟨proof⟩

structure ExactCoverage where
  sourceFunctionNames : TheoremReference source_function_names
  scanNumber :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter identityLayout 3
        Functions.scanNumberView.command = Functions.scanNumberBody
  scanLeadingDotNumber :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter identityLayout 3
        Functions.scanLeadingDotNumberView.command =
      Functions.scanLeadingDotNumberBody

theorem exact_complete : Nonempty ExactCoverage := by
  exact ⟨{
    sourceFunctionNames := reference source_function_names
    scanNumber := Functions.scanNumber_toCore_exactly
    scanLeadingDotNumber := Functions.scanLeadingDotNumber_toCore_exactly
  }⟩

structure SemanticCoverage (source : List Byte) where
  exact : ExactCoverage
  concreteCalls : FramePreservingCallSoundness verifiedFrontendCore
    (Calls.numberCalls source)
  scanNumber : ∀ (world : ReadOnly.World) (start : Nat),
    world.i32Slice? 0 = some (Model.sourceIntegers source) →
    source.length ≤ 2147483647 → start < source.length →
    (Calls.numberCalls source).evaluate world
        Functions.scanNumberFunction.id (Model.argumentValues source start) =
      .ok (Model.encoded (Compiler.Lexer.scanNumber source start), world)
  scanLeadingDotNumber : ∀ (world : ReadOnly.World) (start : Nat),
    world.i32Slice? 0 = some (Model.sourceIntegers source) →
    source.length ≤ 2147483647 → start < source.length →
    (Calls.numberCalls source).evaluate world
        Functions.scanLeadingDotNumberFunction.id
        (Model.argumentValues source start) =
      .ok (Model.encoded
        (Compiler.Lexer.scanLeadingDotNumber source start), world)

private theorem exactCoverage : ExactCoverage :=
  Classical.choice exact_complete

theorem complete (source : List Byte) : Nonempty (SemanticCoverage source) := by
  exact ⟨{
    exact := exactCoverage
    concreteCalls := Calls.numberFramePreservingCallSoundness source
    scanNumber := fun world start sourceFound sourceBound startInBounds =>
      Calls.numberCalls_scanNumber source world start sourceFound sourceBound
        startInBounds
    scanLeadingDotNumber :=
      fun world start sourceFound sourceBound startInBounds =>
        Calls.numberCalls_scanLeadingDotNumber source world start sourceFound
          sourceBound startInBounds
  }⟩

end Lanius.Extraction.Number.FunctionalViewCoverage
