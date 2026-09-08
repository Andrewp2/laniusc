import Lanius.Extraction.SemanticTokens.Collect.Guards
import Lanius.Compiler.ParserGrammar
import Lanius.Separation.I32Prefix

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Compiler.Parser

/-- Reuse the exact grammar encoding already carried by the frontend.
The packed semantic-code limit is the only additional grammar bound. -/
structure GrammarData where
  layout : PackedGrammarLayout
  grammar : IndexedGrammar
  words : List Int
  encoded : EncodesGrammar layout grammar words
  wellFormed : grammar.WellFormed
  wordsFit : words.length ≤ 2147483647
  kindsFit : grammar.grammar.n_kinds ≤ 32768

def GrammarData.Owns (data : GrammarData) (cell : CellId) (state : State) : Prop :=
  I32PrefixLocal state 0 cell data.words

theorem GrammarData.header (data : GrammarData) (owned : data.Owns cell state)
    (program : Program) (index value : Nat) (header : HeaderWord data.words index value) :
    Evaluates program state (atIndex 0 (number index)) (.signed .i32 value) state := by
  have evaluated := owned.read program (number index) index header.index_in_bounds
    (show Evaluates program state (number index) (.signed .i32 index) state from ⟨1, rfl⟩)
  simpa only [header.get, Int.ofNat_eq_natCast] using evaluated

theorem GrammarData.canonical (data : GrammarData) (owned : data.Owns cell state)
    (program : Program) (kindExpression offsetExpression : Expr) (kind : Nat)
    (kindRead : Evaluates program state kindExpression (.signed .i32 kind) state)
    (offsetRead : Evaluates program state offsetExpression (.signed .i32 data.layout.canonicalKindsOffset) state)
    (kindBound : kind < data.grammar.grammar.n_kinds) :
    Evaluates program state (atIndex 0 (binary .add offsetExpression kindExpression))
      (.signed .i32 (data.grammar.grammar.canonical_kinds.get
        ⟨kind, by simpa only [data.wellFormed.canonicalKindCount] using kindBound⟩)) state := by
  have rowBound : kind < data.grammar.grammar.canonical_kinds.length := by
    simpa only [data.wellFormed.canonicalKindCount] using kindBound
  have addressBound := data.encoded.canonicalKinds.row_in_bounds rowBound
  have address := evaluatesNatI32Add (leftValue := data.layout.canonicalKindsOffset) (rightValue := kind)
    offsetRead kindRead (by have := data.wordsFit; omega)
  have evaluated := owned.read program (binary .add offsetExpression kindExpression)
    (data.layout.canonicalKindsOffset + kind) addressBound address
  simpa only [data.encoded.canonicalKinds.get rowBound, Int.ofNat_eq_natCast] using evaluated

structure GrammarData.Loaded (data : GrammarData) (cell : CellId) (state : State) : Prop where
  owned : data.Owns cell state
  lengthRead : state.local? 1 = some (.signed .i32 data.words.length)
  kindRead : state.local? 10 = some (.signed .i32 data.grammar.grammar.n_kinds)
  offsetRead : state.local? 11 = some (.signed .i32 data.layout.canonicalKindsOffset)

theorem GrammarData.Loaded.guard {data : GrammarData} (loaded : data.Loaded cell state) (program : Program) :
    Evaluates program state grammarGuard (.boolean false) state := by
  have lengthRead := local_evaluates program loaded.lengthRead
  have kindRead := local_evaluates program loaded.kindRead
  have offsetRead := local_evaluates program loaded.offsetRead
  have kindPositive := data.wellFormed.kindCountPositive
  have kindBound := data.kindsFit
  have range := (data.encoded.validation_prelude data.wellFormed).canonicalKindsRange
  obtain ⟨_, offsetBound, tableBound⟩ := range
  have nonempty := lessEqual_evaluates kindRead
    (show Evaluates program state (number 0) (.signed .i32 0) state from ⟨1, rfl⟩)
  have bounded := greaterEqual_evaluates kindRead
    (show Evaluates program state (number 32769) (.signed .i32 32769) state from ⟨1, rfl⟩)
  have nonnegative := lessEqual_evaluates offsetRead (negativeOne_evaluates program state)
  have inside := negate_evaluates (lessEqual_evaluates offsetRead lengthRead)
  have subtraction := evaluatesNatI32Subtract (leftValue := data.words.length)
    (rightValue := data.layout.canonicalKindsOffset) lengthRead offsetRead offsetBound
    (by have := data.wordsFit; omega)
  have fits := negate_evaluates (lessEqual_evaluates kindRead subtraction)
  have all := evaluatesPureLogicalOr (evaluatesPureLogicalOr (evaluatesPureLogicalOr
    (evaluatesPureLogicalOr nonempty bounded) nonnegative) inside) fits
  have nonemptyFalse : ¬ ((data.grammar.grammar.n_kinds : Int) ≤ 0) := by omega
  have boundedFalse : ¬ ((32769 : Int) ≤ data.grammar.grammar.n_kinds) := by omega
  have offsetNonnegative : ¬ ((data.layout.canonicalKindsOffset : Int) ≤ -1) := by omega
  have insideTrue : (data.layout.canonicalKindsOffset : Int) ≤ data.words.length := by omega
  have tableTrue : (data.grammar.grammar.n_kinds : Int) ≤
      ((data.words.length - data.layout.canonicalKindsOffset : Nat) : Int) := by omega
  simpa only [grammarGuard, Int.ofNat_eq_natCast, nonemptyFalse, boundedFalse, offsetNonnegative,
    insideTrue, tableTrue, decide_true, decide_false, Bool.false_or, Bool.not_true] using all

def GrammarData.entered (data : GrammarData) (state : State) : State :=
  (state.bindLocal 10 (.signed .i32 data.grammar.grammar.n_kinds)).bindLocal 11
    (.signed .i32 data.layout.canonicalKindsOffset)

theorem GrammarData.loaded (data : GrammarData) (wellFormed : StateWellFormed before)
    (owned : data.Owns cell before) (lengthRead : before.local? 1 = some (.signed .i32 data.words.length)) :
    data.Loaded cell (data.entered before) := by
  have kindWF := bindLocal_preserves_well_formed before 10 (.signed .i32 data.grammar.grammar.n_kinds) wellFormed
  have kindOwned := owned.bindLocal wellFormed 10 (.signed .i32 data.grammar.grammar.n_kinds) (by decide)
  refine ⟨kindOwned.bindLocal kindWF 11 (.signed .i32 data.layout.canonicalKindsOffset) (by decide), ?_, ?_, ?_⟩
  · exact (bindLocal_preserves_other_local kindWF (by decide : (11 : VarId) ≠ 1)).trans
      ((bindLocal_preserves_other_local wellFormed (by decide : (10 : VarId) ≠ 1)).trans lengthRead)
  · exact (bindLocal_preserves_other_local kindWF (by decide : (11 : VarId) ≠ 10)).trans
      (Assertion.localPointsTo_local _ _ _ _ (bindLocal_owns_fresh before 10 (.signed .i32 data.grammar.grammar.n_kinds) wellFormed))
  · exact Assertion.localPointsTo_local _ _ _ _
      (bindLocal_owns_fresh _ 11 (.signed .i32 data.layout.canonicalKindsOffset) kindWF)

/-- Execute the two actual grammar reads and their guard, then enter the
continuation with checked metadata. No grammar-read or guard-execution premise
is supplied by the caller. -/
theorem GrammarData.setup (data : GrammarData) (program : Program) (wellFormed : StateWellFormed before)
    (owned : data.Owns cell before) (lengthRead : before.local? 1 = some (.signed .i32 data.words.length))
    (continuation : data.Loaded cell (data.entered before) → StateWellFormed (data.entered before) →
      ∃ after, Executes program (data.entered before) rest completion after ∧
        CellEffect writes (data.entered before) after) :
    ∃ after, Executes program before
      (declare 10 (atIndex 0 (number 1)) (declare 11 (atIndex 0 (number 7))
        (.sequence (reject grammarGuard) rest))) completion after ∧ CellEffect writes before after := by
  have first := data.header owned program 1 data.grammar.grammar.n_kinds data.encoded.kindCount
  have kindWF := bindLocal_preserves_well_formed before 10 (.signed .i32 data.grammar.grammar.n_kinds) wellFormed
  have kindOwned := owned.bindLocal wellFormed 10 (.signed .i32 data.grammar.grammar.n_kinds) (by decide)
  have second := data.header kindOwned program 7 data.layout.canonicalKindsOffset data.encoded.canonicalKindsOffset
  have loaded := data.loaded wellFormed owned lengthRead
  have readyWF := bindLocal_preserves_well_formed _ 11 (.signed .i32 data.layout.canonicalKindsOffset) kindWF
  obtain ⟨completed, run, effect⟩ := continuation loaded readyWF
  have guarded : Executes program (data.entered before) (.sequence (reject grammarGuard) rest) completion completed :=
    executesSequence (executesIfFalse (loaded.guard program) (executesSkip _ _)) run
  have inner := executesLetLocal (id := 11) (type := i32) second guarded
  have outer := executesLetLocal (id := 10) (type := i32) first inner
  have innerEffect := CellEffect.closeLocal _ 11 (.signed .i32 data.layout.canonicalKindsOffset) kindWF effect
  have outerEffect := CellEffect.closeLocal before 10 (.signed .i32 data.grammar.grammar.n_kinds) wellFormed innerEffect
  exact ⟨_, outer, outerEffect⟩

end Lanius.Extraction.SemanticTokens.Collect
