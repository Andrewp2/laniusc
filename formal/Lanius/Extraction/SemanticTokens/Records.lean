import Lanius.Extraction.SemanticTokens.Bounds

namespace Lanius.Extraction.SemanticTokens

open Lanius.Compiler.Parser ParserTreeLayout

/-- The complete logical input contract for the collector's postorder loop.
It is constructed below from the selected tree, never from assumed acceptance
of the collector or the compact checker. -/
structure CollectionRecords (grammar : IndexedGrammar) (tokens : List Token)
    (tree : Lanius.Compiler.Parser.ParseTree) (nodeBase wordBase : Nat) where
  records : List RecordVisit
  recordsEq : records = (treeVisits grammar (tokens.map Token.kind) nodeBase wordBase 0 tree).1
  assignments : List Assignment
  computed : assignmentsFrom? (records.flatMap RecordVisit.uses) 0 tokens.length = some assignments
  lengthEq : assignments.length = tokens.length
  validAssignments : ∀ (index : Nat) (token : Token), tokens[index]? = some token →
    ∃ assignment : Assignment, assignments[index]? = some assignment ∧ assignment.Valid grammar.grammar token.kind
  acceptedKinds : semanticKindsValid grammar.grammar tokens (assignments.map Assignment.code) = true
  unique : ((records.flatMap RecordVisit.uses).map Use.slot).Nodup
  offsets : records.map RecordVisit.offset = (treeFrom nodeBase wordBase tree).offsets
  stored : ∀ record ∈ records, record.Stored wordBase (treeFrom nodeBase wordBase tree).words
  valid : ∀ record ∈ records, record.Valid grammar (tokens.map Token.kind)
  bounded : ∀ record ∈ records, record.finish ≤ finalPosition tokens.length
  linked : RecordsLinked nodeBase records

/-- All materialized-record and semantic-assignment facts needed by collect
follow from the successful frontend's selected parse. This does not yet prove
the Lanius collect body executes. -/
theorem selected_collection_records (tokens : List Token)
    (parse : MaterializedParse grammar (tokens.map Token.kind))
    (kindsBound : grammar.grammar.n_kinds ≤ 32768) (nodeBase wordBase : Nat) :
    Nonempty (CollectionRecords grammar tokens parse.tree nodeBase wordBase) := by
  obtain ⟨uses, path, _, order, recordsValid, unique⟩ := selected_tree_visits parse nodeBase wordBase
  obtain ⟨assignments, computed, lengthEq, valid⟩ := path.assignments_from
    (start := 0) (count := tokens.length) (by simp)
  refine ⟨{
    records := (treeVisits grammar (tokens.map Token.kind) nodeBase wordBase 0 parse.tree).1
    recordsEq := rfl
    assignments
    computed := (assignmentsFrom_permutation path.positions_unique order).symm.trans computed
    lengthEq
    validAssignments := by
      intro index token found
      have rawFound : (tokens.map Token.kind)[0 + index]? = some token.kind := by simp [found]
      exact valid index token.kind rawFound (List.getElem?_eq_some_iff.mp found).1
    acceptedKinds := ?_
    unique
    offsets := (tree_visits_layout (grammar := grammar) (tokens := tokens.map Token.kind) parse.tree nodeBase wordBase 0).1
    stored := tree_visits_stored parse.tree nodeBase wordBase 0
    valid := recordsValid
    bounded := ?_
    linked := (tree_visits_linked (grammar := grammar) (tokens := tokens.map Token.kind) parse.tree nodeBase wordBase 0).1
  }⟩
  · apply semanticKinds_of_assignments grammar.grammar kindsBound tokens assignments lengthEq
    intro index token found
    have rawFound : (tokens.map Token.kind)[0 + index]? = some token.kind := by simp [found]
    exact valid index token.kind rawFound (List.getElem?_eq_some_iff.mp found).1
  · intro record member
    simpa only [List.length_map] using (tree_visits_bounded parse.recognizes nodeBase wordBase record member).2

theorem CollectionRecords.words_length {data : CollectionRecords grammar tokens tree nodeBase wordBase} :
    (data.assignments.flatMap Assignment.words).length = 2 * tokens.length := by
  rw [assignments_words_length, data.lengthEq]

theorem CollectionRecords.token_child {data : CollectionRecords grammar tokens tree nodeBase wordBase}
    (recordMember : record ∈ data.records) (childMember : ChildVisit.token use ∈ record.children) :
    use.Valid grammar (tokens.map Token.kind) ∧ use.slot = use.position ∧
      use.token < tokens.length ∧ use.finish ≤ finalPosition tokens.length := by
  obtain ⟨valid, _, upper⟩ := (data.valid record recordMember).member childMember
  exact ⟨valid, valid.slot, by simpa only [List.length_map] using valid.tokenBound,
    Nat.le_trans upper (data.bounded record recordMember)⟩

end Lanius.Extraction.SemanticTokens
