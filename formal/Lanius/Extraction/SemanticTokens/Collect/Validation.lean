import Lanius.Extraction.SemanticTokens.Collect.Assignments
import Lanius.Extraction.SemanticTokens.Collect.NodeEntry

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Compiler.Parser

theorem assignment_words_fields {assignments : List Assignment} {assignment : Assignment} {index : Nat}
    (found : assignments[index]? = some assignment) :
    (assignments.flatMap Assignment.words)[index * 2]? = some (Int.ofNat assignment.first) ∧
    (assignments.flatMap Assignment.words)[index * 2 + 1]? =
      some ((assignment.second.map Int.ofNat).getD (-1)) := by
  induction assignments generalizing index with
  | nil => simp at found
  | cons first rest ih =>
      cases index with
      | zero =>
          have same : first = assignment := by simpa using found
          subst first
          cases second : assignment.second <;> simp [Assignment.words, second]
      | succ index =>
          simpa [Assignment.words, Nat.add_mul, Nat.add_assoc] using ih found

theorem NodeOwned.assignments {memory : NodeMemory}
    (held : NodeOwned memory memory.data.collection.records.length before) :
    I32PrefixLocal before 8 memory.data.outputCell (memory.data.collection.assignments.flatMap Assignment.words) := by
  refine ⟨memory.data.original.length, held.output,
    memory.data.original.drop (memory.data.tokens.length * 2), ?_, ?_⟩
  · rw [memory.data.collection.words_length, List.length_drop]
    have := memory.data.capacity
    omega
  · simpa only [memory.data.collection.written] using held.finished

/-- The actual semantic checks after reading the two assignment words. -/
def validationChecks : Stmt :=
  .sequence (reject (binary .lessEqual (read 24) (negative 1)))
    (.ifThenElse (binary .equal (read 25) (negative 1))
      (.sequence (reject (binary .notEqual (atIndex 0 (binary .add (read 11) (read 24))) (atIndex 2 (read 12)))) .skip)
      (.sequence (reject (binary .logicalOr (binary .logicalOr
        (binary .notEqual (atIndex 2 (read 12)) (atIndex 0 (number 5)))
        (binary .notEqual (atIndex 0 (binary .add (read 11) (read 24))) (atIndex 0 (number 6))))
        (binary .notEqual (atIndex 0 (binary .add (read 11) (read 25))) (atIndex 0 (number 6))))) .skip))

private theorem canonical_read {kind canonical : Nat} (data : GrammarData) (program : Program)
    (owned : data.Owns cell state) (id : VarId)
    (kindRead : state.local? id = some (.signed .i32 kind))
    (offsetRead : state.local? 11 = some (.signed .i32 data.layout.canonicalKindsOffset))
    (bound : kind < data.grammar.grammar.n_kinds)
    (found : data.grammar.grammar.canonical_kinds[kind]? = some canonical) :
    Evaluates program state (atIndex 0 (binary .add (read 11) (read id))) (.signed .i32 canonical) state := by
  have result := data.canonical owned program (read id) (read 11) kind
    (local_evaluates program kindRead) (local_evaluates program offsetRead) bound
  have rowBound : kind < data.grammar.grammar.canonical_kinds.length := by
    rw [data.wellFormed.canonicalKindCount]
    exact bound
  have selected : data.grammar.grammar.canonical_kinds.get ⟨kind, rowBound⟩ = canonical := by
    simpa only [List.get_eq_getElem, List.getElem?_eq_getElem rowBound, Option.some.injEq] using found
  simpa only [selected] using result

/-- Both branches pass using semantic evidence retained from the selected
parse. All array reads and guards are executed, not supplied as hypotheses. -/
theorem validation_checks {assignment : Assignment} {token : Token} {tokens : List Token} {index : Nat}
    (data : GrammarData) (program : Program)
    (valid : assignment.Valid data.grammar.grammar token.kind)
    (rawFound : tokens[index]? = some token)
    (grammar : data.Owns grammarCell before)
    (kinds : I32PrefixLocal before 2 kindsCell (tokens.map (Int.ofNat ∘ Token.kind)))
    (cursor : before.local? 12 = some (.signed .i32 index))
    (offset : before.local? 11 = some (.signed .i32 data.layout.canonicalKindsOffset))
    (first : before.local? 24 = some (.signed .i32 assignment.first))
    (second : before.local? 25 = some (.signed .i32 ((assignment.second.map Int.ofNat).getD (-1)))) :
    Executes program before validationChecks .next before := by
  have nonnegative := lessEqual_evaluates (local_evaluates program first) (negativeOne_evaluates program before)
  have guard : Evaluates program before (binary .lessEqual (read 24) (negative 1)) (.boolean false) before := by
    simpa only [Int.ofNat_eq_natCast, show ¬ ((assignment.first : Int) ≤ -1) from by omega, decide_false] using nonnegative
  have raw := read_word program kinds (read 12) index
    (show (tokens.map (Int.ofNat ∘ Token.kind))[index]? = some (Int.ofNat token.kind) from by simp [rawFound])
    (local_evaluates program cursor)
  have condition : Evaluates program before (binary .equal (read 25) (negative 1))
      (.boolean (((assignment.second.map Int.ofNat).getD (-1)) == (-1 : Int))) before :=
    evaluatesEagerBinary (by decide) (by decide) (local_evaluates program second) (negativeOne_evaluates program before)
      (by simp [evalBinaryValue, scalarEqual])
  apply executesSequence (executesIfFalse guard (executesSkip _ _))
  cases secondKind : assignment.second with
  | none =>
      have meaning : data.grammar.grammar.canonical_kinds[assignment.first]? = some token.kind := by
        simpa only [Assignment.Valid, secondKind] using valid.2
      have canonical := canonical_read data program grammar 24 first offset valid.1 meaning
      have same : Evaluates program before
          (binary .notEqual (atIndex 0 (binary .add (read 11) (read 24))) (atIndex 2 (read 12)))
          (.boolean false) before :=
        evaluatesEagerBinary (by decide) (by decide) canonical raw (by simp [evalBinaryValue, scalarEqual])
      exact executesIfTrue (by simpa only [secondKind, Option.map_none, Option.getD_none, beq_self_eq_true] using condition)
        (executesSequence (executesIfFalse same (executesSkip _ _)) (executesSkip _ _))
  | some kind =>
      have meaning : kind < data.grammar.grammar.n_kinds ∧ token.kind = data.grammar.grammar.split_token_kind ∧
          data.grammar.grammar.canonical_kinds[assignment.first]? = some data.grammar.grammar.split_component_kind ∧
          data.grammar.grammar.canonical_kinds[kind]? = some data.grammar.grammar.split_component_kind := by
        simpa only [Assignment.Valid, secondKind] using valid.2
      have firstCanonical := canonical_read data program grammar 24 first offset valid.1 meaning.2.2.1
      have secondCanonical := canonical_read data program grammar 25
        (by simpa only [secondKind, Option.map_some, Option.getD_some, Int.ofNat_eq_natCast] using second) offset meaning.1 meaning.2.2.2
      have splitHeader := data.header grammar program 5 _ data.encoded.splitTokenKind
      have componentHeader := data.header grammar program 6 _ data.encoded.splitComponentKind
      have rawCheck : Evaluates program before (binary .notEqual (atIndex 2 (read 12)) (atIndex 0 (number 5)))
          (.boolean false) before :=
        evaluatesEagerBinary (by decide) (by decide) raw splitHeader (by simp [evalBinaryValue, scalarEqual, meaning.2.1])
      have firstCheck : Evaluates program before
          (binary .notEqual (atIndex 0 (binary .add (read 11) (read 24))) (atIndex 0 (number 6))) (.boolean false) before :=
        evaluatesEagerBinary (by decide) (by decide) firstCanonical componentHeader (by simp [evalBinaryValue, scalarEqual])
      have secondCheck : Evaluates program before
          (binary .notEqual (atIndex 0 (binary .add (read 11) (read 25))) (atIndex 0 (number 6))) (.boolean false) before :=
        evaluatesEagerBinary (by decide) (by decide) secondCanonical componentHeader (by simp [evalBinaryValue, scalarEqual])
      have all := evaluatesPureLogicalOr (evaluatesPureLogicalOr rawCheck firstCheck) secondCheck
      have different : (Int.ofNat kind == (-1 : Int)) = false :=
        beq_eq_false_iff_ne.mpr (by simp only [Int.ofNat_eq_natCast]; omega)
      exact executesIfFalse (by simpa only [secondKind, Option.map_some, Option.getD_some, different] using condition)
        (executesSequence (executesIfFalse all (executesSkip _ _)) (executesSkip _ _))

end Lanius.Extraction.SemanticTokens.Collect
