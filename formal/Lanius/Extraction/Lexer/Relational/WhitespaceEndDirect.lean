import Lanius.Extraction.Lexer.Relational.SourceMemory
import Lanius.Relational.Adequacy
import Lanius.Extraction.Lexer.Relational.WhitespaceEndContract
import Lanius.Extraction.Lexer.Relational.WhitespaceEndABI
import Lanius.Extraction.Lexer.Relational.IdentifierEndStructure
import Lanius.Extraction.Lexer.Relational.ScannerReflection

namespace Lanius.Extraction.Lexer.Relational.WhitespaceEnd.Direct

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.Extraction.Lexer
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Effectful
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.FreshSimulation
open Lanius.Relational

def admissible (source : List Byte) (world : ReadOnly.World)
    (environment : Env 3) : Prop :=
  ScannerReflection.Admissible source world environment

def abi (source : List Byte) : CallABI (contract source) reification :=
  ABI.callABI source

theorem adequate (source : List Byte) :
    RelationalSuccessfulCoreRefinement reification
      (ScannerWP.registry source Functions.isWhitespace isWhitespace
        (PredicateContracts.whitespace_returnsCorrectly source))
      (admissible source) := by
  apply RelationalSuccessfulCoreRefinement.structuralWhen reification rfl
    IdentifierEnd.Structure.whitespaceActionFree
  rw [IdentifierEnd.Structure.whitespaceProofCommand]
  exact ScannerReflection.command_reflects source Functions.isWhitespace
    isWhitespace (PredicateContracts.whitespace_returnsCorrectly source)

theorem bodyWP (source : List Byte) (start : Nat)
    (abstractBefore : List Byte) (beforeWorld : ReadOnly.World)
    (pre : (contract source).Pre start abstractBefore)
    (abstractRep :
      (contract source).AbstractStateRep abstractBefore beforeWorld) :
    SemanticWP.Command.WP
      (ScannerWP.machine source Functions.isWhitespace isWhitespace
        (PredicateContracts.whitespace_returnsCorrectly source))
      Scanners.scanWhitespaceEndView.command
      (fun completion afterWorld _afterEnvironment =>
        ∃ result abstractAfter,
          completion = .returned
            (some ((contract source).encodeResult result)) ∧
          afterWorld = (abi source).proofWorld start abstractBefore beforeWorld ∧
          (contract source).AbstractStateRep abstractAfter afterWorld ∧
          (contract source).Post start result abstractBefore abstractAfter ∧
          (contract source).Frame abstractBefore abstractAfter)
      ((abi source).proofWorld start abstractBefore beforeWorld)
      ((abi source).environment start) := by
  obtain ⟨_abstractEq, sourceBound, startInBounds⟩ := pre
  subst abstractBefore
  intro completion afterWorld afterEnvironment evaluated
  obtain ⟨completionEq, worldEq⟩ :=
    ScannerWP.whitespaceView_wp source start sourceBound startInBounds
      completion afterWorld afterEnvironment evaluated
  subst completion
  subst afterWorld
  refine ⟨scanWhitespaceEnd source start, source, rfl, rfl, ?_, ?_, rfl⟩
  · simpa [contract, sourceIntegers, SourceMemory.sourceWorld,
      SourceMemory.sourceIntegers] using SourceMemory.sourceWorld_finds source
  · exact ⟨rfl, scanWhitespaceEnd_spec source start,
      scanWhitespaceEnd_after_start source start,
      scanWhitespaceEnd_le_source_length source start startInBounds⟩

theorem bodyAdmissible (source : List Byte) (start : Nat)
    (abstractBefore : List Byte) (beforeWorld : ReadOnly.World)
    (pre : (contract source).Pre start abstractBefore)
    (_abstractRep :
      (contract source).AbstractStateRep abstractBefore beforeWorld) :
    admissible source ((abi source).proofWorld start abstractBefore beforeWorld)
      ((abi source).environment start) := by
  obtain ⟨_abstractEq, sourceBound, startInBounds⟩ := pre
  exact ⟨start, sourceBound, startInBounds, rfl, rfl⟩

theorem postRep (source : List Byte) (start result : Nat)
    (abstractBefore abstractAfter : List Byte) (beforeWorld : ReadOnly.World)
    (_pre : (contract source).Pre start abstractBefore)
    (beforeRep :
      (contract source).AbstractStateRep abstractBefore beforeWorld)
    (_post :
      (contract source).Post start result abstractBefore abstractAfter)
    (frame : (contract source).Frame abstractBefore abstractAfter) :
    (contract source).AbstractStateRep abstractAfter beforeWorld := by
  change abstractAfter = abstractBefore at frame
  simpa [frame] using beforeRep

theorem returnsCorrectly (source : List Byte) :
    ReturnsCorrectly (contract source) :=
  ReturnsCorrectly.ofRelationalReadOnlyWP reification (abi source) (by decide)
    (adequate source) (bodyAdmissible source) (postRep source) (bodyWP source)

end Lanius.Extraction.Lexer.Relational.WhitespaceEnd.Direct
