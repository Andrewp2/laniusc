import Lanius.Automation.VCGen
import Lanius.Extraction.Lexer.Relational.ScannerReflection

namespace Lanius.Extraction.Lexer.Relational.Annotations

open Lanius
open Lanius.Compiler.Lexer
open Lanius.FunctionalView

/-- Generated source identity plus the explicit proof invariant used at the
checked identifier-scanner loop. -/
def identifier (source : List Byte) :
    Lanius.Automation.VCGen.AnnotationRegistry
      Lanius.FunctionalView.Core.ReadOnly.World :=
  Lanius.Automation.VCGen.AnnotationRegistry.single
    Functions.scanIdentifierEndLoop (ScannerReflection.LoopInvariant source)

def whitespace (source : List Byte) :
    Lanius.Automation.VCGen.AnnotationRegistry
      Lanius.FunctionalView.Core.ReadOnly.World :=
  Lanius.Automation.VCGen.AnnotationRegistry.single
    Functions.scanWhitespaceEndLoop (ScannerReflection.LoopInvariant source)

@[simp] theorem identifier_finds (source : List Byte) :
    (identifier source).loopInvariant 4 Functions.scanIdentifierEndLoop =
      some (ScannerReflection.LoopInvariant source) := by
  simp [identifier]

@[simp] theorem whitespace_finds (source : List Byte) :
    (whitespace source).loopInvariant 4 Functions.scanWhitespaceEndLoop =
      some (ScannerReflection.LoopInvariant source) := by
  simp [whitespace]

end Lanius.Extraction.Lexer.Relational.Annotations
