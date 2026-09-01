import Lanius.Extraction.Lexer.Relational.IdentifierEnd
import Lanius.Extraction.Lexer.Relational.WhitespaceEnd

/-! # Fast assurance profile

This target records the kernel dependency sets of both public scanner pilot
theorems.  CI captures this output and checks it against the profile allowlist;
the declarations themselves remain ordinary kernel-checked Lean theorems.
-/

#print axioms
  Lanius.Extraction.Lexer.Relational.IdentifierEnd.scanIdentifierEnd_returnsCorrectly

#print axioms
  Lanius.Extraction.Lexer.Relational.WhitespaceEnd.scanWhitespaceEnd_returnsCorrectly
