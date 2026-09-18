import Lanius.Compiler.ParserLanguage

namespace Lanius.Compiler.Parser

/-- Random-access form of the declarative token-lattice scan, shared by
finite resource checkers. The caller builds each array once. -/
def scanTerminalArray (splitToken splitComponent : Nat) (tokens canonical : Array Nat)
    (position kind : Nat) : Option Nat :=
  match tokens[position / 2]?, canonical[kind]? with
  | some raw, some canonical => scanTerminalStep splitToken splitComponent raw canonical position
  | _, _ => none

theorem scanTerminalArray_eq :
    scanTerminalArray grammar.grammar.split_token_kind grammar.grammar.split_component_kind
      tokens.toArray grammar.grammar.canonical_kinds.toArray position kind =
      scanTerminal grammar tokens position kind := by
  simp only [scanTerminalArray, scanTerminal, List.getElem?_toArray]
  rfl

end Lanius.Compiler.Parser
