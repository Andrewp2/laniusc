import Lanius.Extraction.Entry.Grammar.Indexed

open Lanius.Compiler.Parser Lanius.Extraction

/-- Input preparation for the untrusted Lanius proposer, not a new grammar
specification or extractor. The resource checker uses `indexedLanius`
independently; a packing bug can only cause candidate rejection. -/
private def grammarWords : List Nat := Id.run do
  let indexed := Entry.Grammar.indexedLanius
  let grammar := indexed.grammar
  let tables := [grammar.canonical_kinds, indexed.productionLhs, indexed.rhsOffsets,
    indexed.rhsLengths, indexed.rhsSymbols, indexed.lhsOffsets, indexed.lhsCounts, indexed.lhsProductions]
  let offsets := offsetsFrom 17 tables
  return [1, grammar.n_kinds, indexed.productionCount, grammar.n_nonterminals,
    grammar.start_nonterminal, grammar.split_token_kind, grammar.split_component_kind,
    offsets[0]!, offsets[1]!, offsets[2]!, offsets[3]!, offsets[4]!, indexed.rhsSymbols.length,
    offsets[5]!, offsets[6]!, offsets[7]!, indexed.lhsProductions.length] ++ tables.flatten

private def wordBytes (words : List Nat) : ByteArray :=
  ByteArray.mk ((words.flatMap fun value =>
    [UInt8.ofNat value, UInt8.ofNat (value / 256), UInt8.ofNat (value / 65536),
      UInt8.ofNat (value / 16777216)]).toArray)

def main (arguments : List String) : IO UInt32 := do
  let [output] := arguments | throw (IO.userError "expected packed-grammar output path")
  IO.FS.writeBinFile output (wordBytes grammarWords)
  return 0
