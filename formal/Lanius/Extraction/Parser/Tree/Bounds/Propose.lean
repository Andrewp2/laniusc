import Lanius.Extraction.Parser.Tree.Bounds.Check
import Std.Data.HashMap

namespace Lanius.Extraction.ParserTreeBounds
open Lanius.Compiler.Parser
attribute [local instance] lexOrd

inductive ProposalError where
  | invalidProduction
  | missingAdvance
  | cyclicDependencies
deriving Repr, DecidableEq

private structure Edge where
  target : Nat
  left : Nat
  right : Option Nat
deriving Inhabited

/-- Propose resource potentials for the existing finite chart. This does not
recognize input or add chart items. Each transition depends on its prefix and,
for completion, its child. Acyclic dependencies are evaluated once in order;
cycles are rejected. The result still requires `checkCosts` and `checkRoots`:
neither this proposal algorithm nor its auxiliary indexes are trusted. -/
def proposeCosts (grammar : IndexedGrammar) (tokens : List Nat)
    (candidates : List Envelope.Item) : Except ProposalError Costs := do
  let productions := grammar.grammar.productions.toArray
  let canonical := grammar.grammar.canonical_kinds.toArray
  let tokens := tokens.toArray
  let mut items : Array Envelope.Item := #[]
  let mut ids : Std.HashMap Envelope.Item Nat := {}
  let mut completed : Std.HashMap (Nat × Nat) (Array Nat) := {}
  for entry in candidates do
    if !ids.contains entry then
      let some production := productions[entry.2.1]? | throw .invalidProduction
      let id := items.size
      ids := ids.insert entry id
      items := items.push entry
      if entry.2.2.1 == production.rhs.length then
        let key := (entry.2.2.2, production.lhs)
        completed := completed.insert key ((completed[key]?.getD #[]).push id)
  let mut outgoing : Array (Array Edge) := Array.replicate items.size #[]
  let mut incoming := Array.replicate items.size 0
  for id in [:items.size] do
    let entry := items[id]!
    let some production := productions[entry.2.1]? | throw .invalidProduction
    if let some symbol := production.rhs[entry.2.2.1]? then
      if symbol < grammar.grammar.n_kinds then
        if let some finish := scanTerminalArray grammar.grammar.split_token_kind
            grammar.grammar.split_component_kind tokens canonical entry.1 symbol then
          let some target := ids[(finish, entry.2.1, entry.2.2.1 + 1, entry.2.2.2)]?
            | throw .missingAdvance
          outgoing := outgoing.modify id (·.push ⟨target, id, none⟩)
          incoming := incoming.modify target (· + 1)
      else
        for childId in completed[(entry.1, symbol - grammar.grammar.n_kinds)]?.getD #[] do
          let child := items[childId]!
          let some target := ids[(child.1, entry.2.1, entry.2.2.1 + 1, entry.2.2.2)]?
            | throw .missingAdvance
          let edge : Edge := ⟨target, id, some childId⟩
          outgoing := outgoing.modify id (·.push edge)
          outgoing := outgoing.modify childId (·.push edge)
          incoming := incoming.modify target (· + 2)
  let mut ready := #[]
  for id in [:items.size] do
    if incoming[id]! == 0 then ready := ready.push id
  let mut costs : Array Cost := Array.replicate items.size Cost.zero
  -- At most one ready event per item. A bounded traversal also makes totality
  -- explicit independently of the auxiliary graph's implementation.
  for cursor in [:items.size] do
    let some id := ready[cursor]? | throw .cyclicDependencies
    for edge in outgoing[id]! do
      let left := costs[edge.left]!
      let required := left.join (match edge.right with
        | none => Cost.terminal
        | some child => costs[child]!.node)
      costs := costs.modify edge.target (·.maximum required)
      incoming := incoming.modify edge.target (· - 1)
      if incoming[edge.target]! == 0 then ready := ready.push edge.target
  let mut result : Costs := ∅
  for id in [:items.size] do
    result := result.insert items[id]! costs[id]!
  return result

end Lanius.Extraction.ParserTreeBounds
