namespace Lanius.Extraction

structure Production where
  lhs : Nat
  rhs : List Nat
deriving DecidableEq, Repr

/-- A grammar uses the same compact symbol representation as the production
    compiler: terminals are below `n_kinds`; nonterminals are offset by it. -/
structure Grammar where
  n_kinds : Nat
  n_nonterminals : Nat
  start_nonterminal : Nat
  split_token_kind : Nat
  split_component_kind : Nat
  canonical_kinds : List Nat
  productions : List Production
deriving DecidableEq, Repr

def Grammar.production? (grammar : Grammar) (id : Nat) : Option Production :=
  grammar.productions[id]?

def Grammar.symbolIsTerminal (grammar : Grammar) (symbol : Nat) : Bool :=
  symbol < grammar.n_kinds

def Grammar.symbolNonterminal (grammar : Grammar) (symbol : Nat) : Option Nat :=
  if symbol < grammar.n_kinds then none
  else
    let nonterminal := symbol - grammar.n_kinds
    if nonterminal < grammar.n_nonterminals then some nonterminal else none

end Lanius.Extraction
