import Lanius.Compiler.LexerStreamOffsets

-- Audit the universal bridge used by the source execution proof. No native
-- decision oracle or project-specific axiom may justify scanner equivalence.
#print axioms Lanius.Compiler.Lexer.scanOne_eq_scanOneAt
#print axioms Lanius.Compiler.Lexer.scanNumber_offset
#print axioms Lanius.Compiler.Lexer.scanQuotedBody_offset
#print axioms Lanius.Compiler.Lexer.scanBlockBody_offset
