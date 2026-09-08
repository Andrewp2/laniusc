import Lanius.Extraction.SemanticTokens.Order
import Lanius.Extraction.Parser.Tree.Layout

namespace Lanius.Extraction.SemanticTokens

open Lanius.Compiler.Parser ParserTreeLayout

/-- A collector child retains its lattice span. A node child moves the cursor
but makes no assignment; its terminals were visited in earlier records. -/
inductive ChildVisit where
  | token (use : Use)
  | node (id start finish : Nat)
deriving Repr

def ChildVisit.start : ChildVisit → Nat
  | .token use => use.position
  | .node _ start _ => start

def ChildVisit.finish : ChildVisit → Nat
  | .token use => use.finish
  | .node _ _ finish => finish

def ChildVisit.reference : ChildVisit → Child
  | .token use => .token use.token use.kind
  | .node id _ _ => .state id

def ChildVisit.uses : ChildVisit → List Use
  | .token use => [use]
  | .node _ _ _ => []

/-- Proof view of one existing materialized record, not another exporter.
The original layout remains the authority for word offsets and node IDs. -/
structure RecordVisit where
  offset : Nat
  production : Nat
  start : Nat
  finish : Nat
  children : List ChildVisit
deriving Repr

def RecordVisit.uses (record : RecordVisit) : List Use :=
  record.children.flatMap ChildVisit.uses

def RecordVisit.words (record : RecordVisit) : List Int :=
  recordHeader record.production record.start record.finish record.children.length ++
    record.children.flatMap (fun child => derivationChildWords child.reference)

mutual
  /-- Annotate the existing layout with the positions the collector visits.
  Soundness below rules out the fallback for every recognized terminal. -/
  def treeVisits (grammar : IndexedGrammar) (tokens : List Nat) (nodeBase wordBase position : Nat) :
      Lanius.Compiler.Parser.ParseTree → List RecordVisit × ChildVisit
    | .terminal token kind =>
      ([], .token ⟨position, (scanTerminal grammar tokens position kind).getD position, token, kind⟩)
    | .nonterminal production _ start finish children =>
      let nested := forestVisits grammar tokens nodeBase (wordBase + 4 + children.length * 3) start children
      let layout := forestFrom nodeBase (wordBase + 4 + children.length * 3) children
      (nested.1 ++ [⟨wordBase, production, start, finish, nested.2⟩],
        .node (nodeBase + layout.offsets.length) start finish)

  def forestVisits (grammar : IndexedGrammar) (tokens : List Nat) (nodeBase wordBase position : Nat) :
      List Lanius.Compiler.Parser.ParseTree → List RecordVisit × List ChildVisit
    | [] => ([], [])
    | tree :: trees =>
      let first := treeVisits grammar tokens nodeBase wordBase position tree
      let layout := treeFrom nodeBase wordBase tree
      let rest := forestVisits grammar tokens (nodeBase + layout.offsets.length)
        (wordBase + layout.words.length) first.2.finish trees
      (first.1 ++ rest.1, first.2 :: rest.2)
end

theorem forest_visits_length (trees : List Lanius.Compiler.Parser.ParseTree) :
    (forestVisits grammar tokens nodeBase wordBase position trees).2.length = trees.length := by
  induction trees generalizing nodeBase wordBase position with
  | nil => rfl
  | cons tree trees ih => simp only [forestVisits, List.length_cons, ih]

mutual
  /-- Every token kind, state reference, and offset is retained exactly. -/
  theorem tree_visits_layout (tree : Lanius.Compiler.Parser.ParseTree)
      (nodeBase wordBase position : Nat) :
      (treeVisits grammar tokens nodeBase wordBase position tree).1.map RecordVisit.offset =
        (treeFrom nodeBase wordBase tree).offsets ∧
      (treeVisits grammar tokens nodeBase wordBase position tree).2.reference =
        (treeFrom nodeBase wordBase tree).roots := by
    cases tree with
    | terminal token kind => exact ⟨rfl, rfl⟩
    | nonterminal production nonterminal start finish children =>
      have nested := forest_visits_layout (grammar := grammar) (tokens := tokens) children
        nodeBase (wordBase + 4 + children.length * 3) start
      exact ⟨by simp only [treeVisits, treeFrom, List.map_append, List.map_cons, List.map_nil, nested.1], rfl⟩
  termination_by sizeOf tree

  theorem forest_visits_layout (trees : List Lanius.Compiler.Parser.ParseTree)
      (nodeBase wordBase position : Nat) :
      (forestVisits grammar tokens nodeBase wordBase position trees).1.map RecordVisit.offset =
        (forestFrom nodeBase wordBase trees).offsets ∧
      (forestVisits grammar tokens nodeBase wordBase position trees).2.map ChildVisit.reference =
        (forestFrom nodeBase wordBase trees).roots := by
    cases trees with
    | nil => exact ⟨rfl, rfl⟩
    | cons tree trees =>
      have head := tree_visits_layout (grammar := grammar) (tokens := tokens) tree nodeBase wordBase position
      have tail := forest_visits_layout (grammar := grammar) (tokens := tokens) trees
        (nodeBase + (treeFrom nodeBase wordBase tree).offsets.length)
        (wordBase + (treeFrom nodeBase wordBase tree).words.length)
        (treeVisits grammar tokens nodeBase wordBase position tree).2.finish
      simp only [forestVisits, forestFrom, List.map_append, List.map_cons, head.1, head.2, tail.1, tail.2,
        and_self]
  termination_by sizeOf trees
end

end Lanius.Extraction.SemanticTokens
