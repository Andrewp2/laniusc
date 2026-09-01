import Lanius.Extraction.Lexer.Relational.SourceMemory
import Lanius.Extraction.Lexer.Relational.Annotations
import Lanius.Extraction.Lexer.Relational.WhitespaceEndDirect
import Lanius.Extraction.Lexer.Relational.ScannerWP

namespace Lanius.Extraction.Lexer.Relational.WhitespaceEnd

open Lanius
open Lanius.Compiler.Lexer
open Lanius.Extraction.Lexer
open Lanius.Relational

theorem scanWhitespaceEnd_returnsCorrectly (source : List Byte) :
    ReturnsCorrectly (contract source) :=
  Direct.returnsCorrectly source

theorem scanWhitespaceEnd_relationalWP
    (source : List Byte) (start : Nat)
    (sourceBound : source.length ≤ 2147483647)
    (startInBounds : start < source.length) :
    Lanius.Relational.SemanticWP.Command.WP
      (ScannerWP.machine source Functions.isWhitespace isWhitespace
        (PredicateContracts.whitespace_returnsCorrectly source))
      Scanners.scanWhitespaceEndView.command
      (fun completion afterWorld _afterEnvironment =>
        completion = .returned (some (.signed .i32
          (Int.ofNat (scanWhitespaceEnd source start)))) ∧
        afterWorld = SourceMemory.sourceWorld source)
      (SourceMemory.sourceWorld source) (ScannerWP.parameterEnvironment source start) :=
  ScannerWP.whitespaceView_wp source start sourceBound startInBounds

structure PilotMilestone where
  exactCommand : Reifies Functions.scanWhitespaceEnd
    Scanners.scanWhitespaceEndView.command
  partialCorrectness : ∀ source : List Byte,
    ReturnsCorrectly (contract source)

theorem milestone : Nonempty PilotMilestone :=
  ⟨{
    exactCommand := reification
    partialCorrectness := scanWhitespaceEnd_returnsCorrectly
  }⟩

end Lanius.Extraction.Lexer.Relational.WhitespaceEnd
