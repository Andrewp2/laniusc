import Lanius.Extraction.CompactDecode.Acceptance.Records
import Lanius.Extraction.CompactDecode.Acceptance.Terminals

namespace Lanius.Extraction.CompactDecode

open Lanius.Compiler.Parser SemanticTokens

theorem visit_children_match
    (typed : ChildSymbols grammar records 0 symbols children)
    (path : VisitPath grammar raw children start finish)
    (sameGrammar : grammar.grammar = laniusGrammar)
    (linked : ∀ child ∈ children, child.Linked 0 records current)
    (advanced : ∀ use, ChildVisit.token use ∈ children →
      advanceTerminal kinds use.position use.kind = some use.finish) :
    ChildrenMatch laniusGrammar kinds (records.map decodedNode) current
      symbols (children.map decodedChild) start finish := by
  induction typed generalizing start finish with
  | nil => cases path; exact .empty _
  | @cons symbol child symbols children head tail ih =>
      cases path with
      | cons valid rest =>
        have tailMatch := ih rest
          (fun child member => linked child (List.mem_cons_of_mem _ member))
          (fun use member => advanced use (List.mem_cons_of_mem _ member))
        cases child with
        | token use =>
          obtain ⟨rfl, kindBound⟩ := head
          exact .terminal (sameGrammar ▸ kindBound) valid.tokenEq
            (advanced use List.mem_cons_self) tailMatch
        | node childId start finish =>
          obtain ⟨_, record, production, found, lookup, symbolEq, ntBound⟩ := head
          obtain ⟨_, earlier, stored, storedFound, sameStart, sameFinish⟩ := linked _ List.mem_cons_self
          have same : stored = record := Option.some.inj (storedFound.symm.trans found)
          subst stored
          have decodedFound : (records.map decodedNode)[childId]? = some (decodedNode record) := by
            simpa only [List.getElem?_map, Nat.sub_zero, Option.map_some] using
              congrArg (Option.map decodedNode) found
          have decoderLookup : laniusGrammar.production? record.production = some production := by
            rw [← sameGrammar]; exact lookup
          have symbolIndex : symbol - laniusGrammar.n_kinds = production.lhs := by
            rw [symbolEq, sameGrammar]; omega
          refine .nonterminal (by rw [symbolEq, sameGrammar]; omega)
            (by rw [symbolIndex]; exact sameGrammar ▸ ntBound) earlier decodedFound
            (by simp [decodedNode, decoderLookup, symbolIndex]) sameStart ?_
          simpa only [decodedNode, sameFinish, ChildVisit.finish] using tailMatch

theorem collection_node_match
    (parse : MaterializedParse grammar (tokens.map Token.kind))
    (collection : CollectionRecords grammar tokens parse.tree 0 0)
    (sameGrammar : grammar.grammar = laniusGrammar)
    (kindsBound : grammar.grammar.n_kinds ≤ 32768)
    (found : collection.records[index]? = some record) :
    NodeMatches laniusGrammar (collection.assignments.map Assignment.code)
      (collection.records.map decodedNode) index (decodedNode record) := by
  have member := List.mem_of_getElem? found
  obtain ⟨production, lookup, typed⟩ := collection_record_symbols parse collection member
  have decoderLookup : laniusGrammar.production? record.production = some production := by
    rw [← sameGrammar]; exact lookup
  refine .intro production decoderLookup (by simp [decodedNode, decoderLookup])
    (collection.valid record member).monotone ?_ ?_
  · simpa only [decodedNode, List.length_map, collection.lengthEq, finalPosition] using
      collection.bounded record member
  · apply visit_children_match typed (collection.valid record member) sameGrammar
    · simpa only [Nat.zero_add] using collection.linked index record found
    · intro use useMember
      apply collection_terminal_advance parse collection kindsBound
      exact List.mem_flatMap.mpr ⟨record, member, List.mem_flatMap.mpr
        ⟨ChildVisit.token use, useMember, List.mem_cons_self⟩⟩

theorem nodes_match_mapped (records : List RecordVisit) (offset : Nat)
    (valid : ∀ index record, records[index]? = some record →
      NodeMatches grammar kinds nodes (offset + index) (decodedNode record)) :
    NodesMatchFrom grammar kinds nodes offset (records.map decodedNode) := by
  induction records generalizing offset with
  | nil => exact .empty _
  | cons record records ih =>
      refine .cons (by simpa only [Nat.add_zero] using valid 0 record rfl) ?_
      apply ih
      intro index record found
      simpa only [Nat.add_assoc, Nat.add_comm 1 index] using valid (index + 1) record found

theorem collection_nodes_accepted
    (parse : MaterializedParse grammar (tokens.map Token.kind))
    (collection : CollectionRecords grammar tokens parse.tree 0 0)
    (sameGrammar : grammar.grammar = laniusGrammar)
    (kindsBound : grammar.grammar.n_kinds ≤ 32768) :
    checkNodesFrom laniusGrammar (collection.assignments.map Assignment.code)
      (collection.records.map decodedNode) 0 (collection.records.map decodedNode) = true := by
  apply nodes_match_accepted
  apply nodes_match_mapped
  intro index record found
  simpa only [Nat.zero_add] using collection_node_match parse collection sameGrammar kindsBound found

end Lanius.Extraction.CompactDecode
