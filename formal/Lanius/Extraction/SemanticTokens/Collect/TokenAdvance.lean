import Lanius.Extraction.SemanticTokens.Collect.Record
import Lanius.Separation.LocalStore

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Compiler.Parser

private theorem advance_by {position : Nat} (program : Program) (amount : Nat)
    (wellFormed : StateWellFormed before)
    (cursor : (Assertion.localPointsTo 16 cell (some (.signed .i32 position))).holds before)
    (bounded : position + amount ≤ 2147483647) :
    ∃ after, Executes program before (.sequence (increment 16 amount) .skip) .next after ∧
      (Assertion.localPointsTo 16 cell (some (.signed .i32 (Int.ofNat (position + amount))))).holds after ∧
      CellEffect (CellSet.singleton cell) before after := by
  obtain ⟨after, assigned, owned, effect⟩ := evaluatesOwnedLocalUpdate wellFormed cursor
    (show Evaluates program before (number amount) (.signed .i32 amount) before from ⟨1, rfl⟩)
    (show evalAssignValue program.target .add (some (.signed .i32 position)) (.signed .i32 amount) =
      .ok (.signed .i32 (Int.ofNat (position + amount))) from by
      simp only [evalAssignValue, assignOpBinary?, evalBinaryValue, evalSignedBinary, BEq.rfl, if_true]
      rw [← Int.natCast_add]
      simpa only [Int.ofNat_eq_natCast] using congrArg
        (fun value => (Except.ok (Value.signed .i32 value) : Except Trap Value))
        (wrapSigned_i32_ofNat program.target (position + amount) bounded))
  exact ⟨after, executesSequence (executesExpression assigned) (executesSkip _ _), owned, effect⟩

private theorem split_advance {position : Nat} (data : GrammarData) (program : Program)
    (wellFormed : StateWellFormed before) (owned : data.Owns grammarCell before)
    (cursor : (Assertion.localPointsTo 16 cell (some (.signed .i32 position))).holds before)
    (rawRead : before.local? 21 = some (.signed .i32 data.grammar.grammar.split_token_kind))
    (canonicalRead : before.local? 22 = some (.signed .i32 data.grammar.grammar.split_component_kind))
    (bounded : position + 1 ≤ 2147483647) :
    ∃ after, Executes program before splitAdvance .next after ∧
      (Assertion.localPointsTo 16 cell (some (.signed .i32 (Int.ofNat (position + 1))))).holds after ∧
      CellEffect (CellSet.singleton cell) before after := by
  have rawHeader := data.header owned program 5 _ data.encoded.splitTokenKind
  have componentHeader := data.header owned program 6 _ data.encoded.splitComponentKind
  have rawCheck : Evaluates program before (binary .notEqual (read 21) (atIndex 0 (number 5))) (.boolean false) before :=
    evaluatesEagerBinary (by decide) (by decide) (local_evaluates program rawRead) rawHeader
      (by simp [evalBinaryValue, scalarEqual])
  have componentCheck : Evaluates program before (binary .notEqual (read 22) (atIndex 0 (number 6))) (.boolean false) before :=
    evaluatesEagerBinary (by decide) (by decide) (local_evaluates program canonicalRead) componentHeader
      (by simp [evalBinaryValue, scalarEqual])
  have guard : Evaluates program before splitGuard (.boolean false) before :=
    evaluatesPureLogicalOr rawCheck componentCheck
  obtain ⟨after, incremented, final, effect⟩ := advance_by program 1 wellFormed cursor bounded
  exact ⟨after, executesSequence (executesIfFalse guard (executesSkip _ _)) incremented, final, effect⟩

/-- The real collector cursor follows the parser's terminal scan, including
whole uses of the split-token kind and either virtual half. Local raw/canonical
values are tied to the same input lists, rather than an assumed passing guard. -/
theorem token_advance_execute {use : Use} {raw canonical : Nat}
    (data : GrammarData) (program : Program)
    (valid : use.Valid data.grammar tokens)
    (rawFound : tokens[use.token]? = some raw)
    (canonicalFound : data.grammar.grammar.canonical_kinds[use.kind]? = some canonical)
    (wellFormed : StateWellFormed before) (owned : data.Owns grammarCell before)
    (cursor : (Assertion.localPointsTo 16 cell (some (.signed .i32 use.position))).holds before)
    (rawRead : before.local? 21 = some (.signed .i32 raw))
    (canonicalRead : before.local? 22 = some (.signed .i32 canonical))
    (bounded : use.finish ≤ 2147483647) :
    ∃ after, Executes program before tokenAdvance .next after ∧
      (Assertion.localPointsTo 16 cell (some (.signed .i32 use.finish))).holds after ∧
      CellEffect (CellSet.singleton cell) before after := by
  have remainder := evaluatesNatI32Remainder (leftValue := use.position) (rightValue := 2)
    (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ cursor))
    (show Evaluates program before (number 2) (.signed .i32 2) before from ⟨1, rfl⟩)
    (by decide) (by have := Nat.mod_lt use.position (by decide : 0 < 2); omega)
  have parity : Evaluates program before
      (binary .equal (binary .remainder (read 16) (number 2)) (number 1))
      (.boolean (decide (use.position % 2 = 1))) before := by
    apply evaluatesEagerBinary (by decide) (by decide) remainder
      (show Evaluates program before (number 1) (.signed .i32 1) before from ⟨1, rfl⟩)
    simp only [evalBinaryValue, scalarEqual, BEq.rfl, if_true, Except.ok.injEq, Value.boolean.injEq]
    apply Bool.eq_iff_iff.mpr
    simp only [beq_iff_eq, decide_eq_true_eq, Int.ofNat_eq_natCast]
    omega
  have same : Evaluates program before (binary .equal (read 21) (read 22))
      (.boolean (decide (raw = canonical))) before := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program rawRead) (local_evaluates program canonicalRead)
    simp only [evalBinaryValue, scalarEqual, BEq.rfl, if_true, Except.ok.injEq, Value.boolean.injEq]
    apply Bool.eq_iff_iff.mpr
    simp only [beq_iff_eq, decide_eq_true_eq]
    omega
  rcases valid.shape with whole | first | second
  · obtain ⟨even, finish, value, physical, semantic⟩ := whole
    have rawEq : raw = value := Option.some.inj (rawFound.symm.trans physical)
    have canonicalEq : canonical = value := Option.some.inj (canonicalFound.symm.trans semantic)
    have evenFalse : use.position % 2 ≠ 1 := by omega
    have sameTrue : raw = canonical := rawEq.trans canonicalEq.symm
    obtain ⟨after, incremented, final, effect⟩ := advance_by program 2 wellFormed cursor (by omega)
    refine ⟨after, ?_, by simpa only [finish, Int.ofNat_eq_natCast] using final, effect⟩
    exact executesIfFalse (by simpa only [evenFalse, decide_false] using parity)
      (executesSequence (executesIfTrue (by simpa only [sameTrue, decide_true] using same) incremented) (executesSkip _ _))
  · obtain ⟨even, finish, physical, semantic, different⟩ := first
    have rawEq := Option.some.inj (rawFound.symm.trans physical)
    have canonicalEq := Option.some.inj (canonicalFound.symm.trans semantic)
    have evenFalse : use.position % 2 ≠ 1 := by omega
    have sameFalse : raw ≠ canonical := by simpa only [rawEq, canonicalEq] using different
    obtain ⟨after, advanced, final, effect⟩ := split_advance data program wellFormed owned cursor
      (by simpa only [rawEq] using rawRead) (by simpa only [canonicalEq] using canonicalRead) (by omega)
    refine ⟨after, ?_, by simpa only [finish, Int.ofNat_eq_natCast] using final, effect⟩
    exact executesIfFalse (by simpa only [evenFalse, decide_false] using parity)
      (executesSequence (executesIfFalse (by simpa only [sameFalse, decide_false] using same) advanced) (executesSkip _ _))
  · obtain ⟨odd, finish, physical, semantic⟩ := second
    have rawEq := Option.some.inj (rawFound.symm.trans physical)
    have canonicalEq := Option.some.inj (canonicalFound.symm.trans semantic)
    have oddTrue : use.position % 2 = 1 := by omega
    obtain ⟨after, advanced, final, effect⟩ := split_advance data program wellFormed owned cursor
      (by simpa only [rawEq] using rawRead) (by simpa only [canonicalEq] using canonicalRead) (by omega)
    exact ⟨after, executesIfTrue (by simpa only [oddTrue, decide_true] using parity) advanced,
      by simpa only [finish, Int.ofNat_eq_natCast] using final, effect⟩

end Lanius.Extraction.SemanticTokens.Collect
