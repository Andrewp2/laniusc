import Lanius.Compiler.ParserGrammar

namespace Lanius.Extraction.Entry.Grammar

open Lanius.Compiler.Parser

instance (words : List Int) (index value : Nat) : Decidable (HeaderWord words index value) :=
  inferInstanceAs (Decidable (words[index]? = some (Int.ofNat value)))

instance (words : List Int) (offset : Nat) (values : List Nat) : Decidable (PackedTableAt words offset values) :=
  inferInstanceAs (Decidable (grammarHeaderWords ≤ offset ∧ offset + values.length ≤ words.length ∧
    (words.drop offset).take values.length = natWords values))

structure EncodingEvidence (layout : PackedGrammarLayout) (grammar : IndexedGrammar) (words : List Int) : Type where
  proof : EncodesGrammar layout grammar words

/-- Authenticate the actual packed table against the parser's existing
semantic contract. No alternative grammar or serialization contract is used. -/
def checkEncoding? (layout : PackedGrammarLayout) (grammar : IndexedGrammar) (words : List Int) :
    Option (EncodingEvidence layout grammar words) :=
  if evidence : words.length = layout.wordLength ∧ grammarHeaderWords ≤ words.length ∧
      HeaderWord words 0 grammarVersion ∧
      HeaderWord words 1 grammar.grammar.n_kinds ∧
      HeaderWord words 2 grammar.productionCount ∧
      HeaderWord words 3 grammar.grammar.n_nonterminals ∧
      HeaderWord words 4 grammar.grammar.start_nonterminal ∧
      HeaderWord words 5 grammar.grammar.split_token_kind ∧
      HeaderWord words 6 grammar.grammar.split_component_kind ∧
      HeaderWord words 7 layout.canonicalKindsOffset ∧
      HeaderWord words 8 layout.productionLhsOffset ∧
      HeaderWord words 9 layout.rhsOffsetsOffset ∧
      HeaderWord words 10 layout.rhsLengthsOffset ∧
      HeaderWord words 11 layout.rhsSymbolsOffset ∧
      HeaderWord words 12 grammar.rhsSymbols.length ∧
      HeaderWord words 13 layout.lhsOffsetsOffset ∧
      HeaderWord words 14 layout.lhsCountsOffset ∧
      HeaderWord words 15 layout.lhsProductionsOffset ∧
      HeaderWord words 16 grammar.lhsProductions.length ∧
      PackedTableAt words layout.canonicalKindsOffset grammar.grammar.canonical_kinds ∧
      PackedTableAt words layout.productionLhsOffset grammar.productionLhs ∧
      PackedTableAt words layout.rhsOffsetsOffset grammar.rhsOffsets ∧
      PackedTableAt words layout.rhsLengthsOffset grammar.rhsLengths ∧
      PackedTableAt words layout.rhsSymbolsOffset grammar.rhsSymbols ∧
      PackedTableAt words layout.lhsOffsetsOffset grammar.lhsOffsets ∧
      PackedTableAt words layout.lhsCountsOffset grammar.lhsCounts ∧
      PackedTableAt words layout.lhsProductionsOffset grammar.lhsProductions then
    some ⟨by
      rcases evidence with ⟨a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z,aa⟩
      exact ⟨a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z,aa⟩⟩
  else none

end Lanius.Extraction.Entry.Grammar
