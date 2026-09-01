import Lanius.Extraction.Lexer.Relational.SourceMemory
import Lanius.Extraction.Lexer.Relational.Annotations
import Lanius.Extraction.Lexer.Relational.IdentifierEndDirect
import Lanius.Extraction.Lexer.Relational.ScannerWP

namespace Lanius.Extraction.Lexer.Relational.IdentifierEnd

open Lanius
open Lanius.Compiler.Lexer
open Lanius.Extraction.Lexer
open Lanius.Relational

/-- Stable source-oriented spelling of the pilot theorem. -/
theorem scanIdentifierEnd_returnsCorrectly (source : List Byte) :
    ReturnsCorrectly (contract source) :=
  Direct.returnsCorrectly source

/-- Structural relational WP for the checked function view. Predicate calls
are discharged through the typed predicate contract entry. -/
theorem scanIdentifierEnd_relationalWP
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    Lanius.Relational.SemanticWP.Command.WP
      (ScannerWP.machine source Functions.isIdentifierContinue
        isIdentifierContinue
        (PredicateContracts.identifier_returnsCorrectly source))
      Scanners.scanIdentifierEndView.command
      (fun completion afterWorld _afterEnvironment =>
        completion = .returned (some (.signed .i32
          (Int.ofNat (scanIdentifierEnd source start)))) ∧
        afterWorld = SourceMemory.sourceWorld source)
      (SourceMemory.sourceWorld source) (ScannerWP.parameterEnvironment source start) :=
  ScannerWP.identifierView_wp source start sourceBound startInBounds

/-- Auditable pilot bundle.  Keeping exact artifact reification alongside the
public contract prevents a coverage theorem from accidentally indexing only
the logical result or only the recovered syntax. -/
structure PilotMilestone where
  exactCommand : Reifies Functions.scanIdentifierEnd
    Scanners.scanIdentifierEndView.command
  partialCorrectness : ∀ source : List Byte,
    ReturnsCorrectly (contract source)

theorem milestone : Nonempty PilotMilestone :=
  ⟨{
    exactCommand := reification
    partialCorrectness := scanIdentifierEnd_returnsCorrectly
  }⟩

end Lanius.Extraction.Lexer.Relational.IdentifierEnd
