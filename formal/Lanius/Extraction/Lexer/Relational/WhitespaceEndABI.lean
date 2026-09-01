import Lanius.Extraction.Lexer.Relational.SourceMemory
import Lanius.Relational.Adequacy
import Lanius.Extraction.Lexer.Relational.WhitespaceEndContract
import Lanius.Extraction.Lexer.Relational.WhitespaceEndReification
import Lanius.Extraction.Lexer.Relational.ScannerWP

namespace Lanius.Extraction.Lexer.Relational.WhitespaceEnd.ABI

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Compiler.Lexer
open Lanius.Compiler.Lexer.Program
open Lanius.Extraction
open Lanius.Extraction.Lexer
open Lanius.FunctionalView
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.FreshSimulation
open Lanius.Relational
open Lanius.Extraction.Lexer.Relational.WhitespaceEnd

/-! Physical call-entry details for the checked scanner are isolated here.
The algorithm proof consumes only the resulting `CallABI` value. -/

def callABI (source : List Byte) :
    CallABI (contract source) reification where
  environment := ScannerWP.parameterEnvironment source
  proofWorld := fun _ _ _ => SourceMemory.sourceWorld source
  parametersBound := by
    intro start
    change Nat at start
    change bindParameters Scanners.scanWhitespaceEndFunction.parameters
      (scannerArguments source start) =
      some (parameterBindings (ScannerWP.parameterEnvironment source start))
    rw [show Scanners.scanWhitespaceEndFunction.parameters =
      [(0, .slice i32Type), (1, i32Type), (2, i32Type)] by rfl]
    rfl
  projectCallee := by
    intro callerArity layout localCell callerEnvironment beforeWorld
      afterArguments start abstractBefore pre abstractRep wellFormed represented
    obtain ⟨_abstractEq, _, _⟩ := pre
    subst abstractBefore
    have full := represented.enterCallParameters wellFormed
      (environment := ScannerWP.parameterEnvironment source start)
    have sourceFound : beforeWorld.i32Slice? 0 =
        some (SourceMemory.sourceIntegers source) := by
      change beforeWorld.i32Slice? 0 = some (sourceIntegers source)
        at abstractRep
      simpa [sourceIntegers, SourceMemory.sourceIntegers] using abstractRep
    simpa [reification] using
      SourceMemory.representationOnlySource full sourceFound

end Lanius.Extraction.Lexer.Relational.WhitespaceEnd.ABI
