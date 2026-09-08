import Lanius.Extraction.SemanticTokens.Collect.TokenStore

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Compiler.Parser ParserTreeLayout

/-- Resources unchanged while entering the token branch's lexical scopes. -/
private structure TokenResources (data : GrammarData) (use : Use)
    (grammarCell outputCell cursorCell : CellId) (values : List Int) (state : State) : Prop where
  wellFormed : StateWellFormed state
  grammar : data.Owns grammarCell state
  cursor : (Assertion.localPointsTo 16 cursorCell (some (.signed .i32 use.position))).holds state
  output : state.local? 8 = some (.slice i32 outputCell [] 0 values.length)
  backing : state.cellEntry? outputCell = some {
    id := outputCell, value := some (.array (signedI32Values values)) }

private theorem TokenResources.bindLocal {data : GrammarData} {use : Use}
    (held : TokenResources data use grammarCell outputCell cursorCell values before)
    (id : VarId) (value : Value) (different : id ≠ 0 ∧ id ≠ 8 ∧ id ≠ 16) :
    TokenResources data use grammarCell outputCell cursorCell values (before.bindLocal id value) := by
  exact ⟨bindLocal_preserves_well_formed _ _ _ held.wellFormed,
    held.grammar.bindLocal held.wellFormed id value different.1,
    bindLocal_preserves_localPointsTo_of_ne before id 16 value cursorCell _ held.wellFormed different.2.2 held.cursor,
    (bindLocal_preserves_other_local held.wellFormed different.2.1).trans held.output,
    ((bindLocal_effect before id value).oldCells outputCell
      (StateWellFormed.cell_lt_next_of_entry held.wellFormed held.backing) (by simp [CellSet.empty])).trans held.backing⟩

/-- Complete execution of the checked token branch: read the semantic kind,
validate its token/cursor bounds, load the raw and canonical kinds, compute
the unique assignment address, write it, advance, and close all four scopes.
The enclosing traversal supplies the unused-slot invariant, not executions. -/
theorem token_child_execute {use : Use} {record : RecordVisit} {childIndex : Nat}
    (data : GrammarData) (program : Program)
    (valid : use.Valid data.grammar tokens)
    (stored : record.Stored 0 words)
    (childFound : record.children[childIndex]? = some (.token use))
    (wellFormed : StateWellFormed before)
    (grammarOwned : data.Owns grammarCell before)
    (kindsOwned : I32PrefixLocal before 2 kindsCell (tokens.map Int.ofNat))
    (recordsOwned : I32PrefixLocal before 4 recordsCell words)
    (countRead : before.local? 3 = some (.signed .i32 tokens.length))
    (kindCountRead : before.local? 10 = some (.signed .i32 data.grammar.grammar.n_kinds))
    (canonicalOffsetRead : before.local? 11 = some (.signed .i32 data.layout.canonicalKindsOffset))
    (payloadRead : before.local? 19 = some (.signed .i32 use.token))
    (slotRead : before.local? 18 = some (.signed .i32 (Int.ofNat (record.offset + 4 + childIndex * 3))))
    (cursor : (Assertion.localPointsTo 16 cursorCell (some (.signed .i32 use.position))).holds before)
    (outputLocal : before.local? 8 = some (.slice i32 outputCell [] 0 values.length))
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values values)) })
    (available : values[use.slot]? = some (-1))
    (grammarSeparate : grammarCell ≠ outputCell)
    (wordsFit : words.length ≤ 2147483647)
    (tokensFit : tokens.length * 2 ≤ 2147483647) :
    ∃ after, Executes program before tokenBody .next after ∧
      (Assertion.localPointsTo 16 cursorCell (some (.signed .i32 use.finish))).holds after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values (values.set use.slot use.kind))) } ∧
      CellEffect (CellSet.union (CellSet.singleton outputCell) (CellSet.singleton cursorCell)) before after := by
  have held : TokenResources data use grammarCell outputCell cursorCell values before :=
    ⟨wellFormed, grammarOwned, cursor, outputLocal, backing⟩
  have tokenBound := valid.tokenBound
  have kindBound := valid.kindBound
  have finishBound := scanTerminal_some_le_finalPosition _ _ _ _ _ valid.scanned
  have slotBound : use.slot < tokens.length * 2 := by
    have remainder := Nat.mod_lt use.position (by decide : 0 < 2)
    simp only [Use.slot]
    omega
  have rawFound : tokens[use.token]? = some (tokens.get ⟨use.token, tokenBound⟩) := by simp
  let raw := tokens.get ⟨use.token, tokenBound⟩
  have canonicalBound : use.kind < data.grammar.grammar.canonical_kinds.length := by
    simpa only [data.wellFormed.canonicalKindCount] using kindBound
  let canonical := data.grammar.grammar.canonical_kinds.get ⟨use.kind, canonicalBound⟩
  have canonicalFound : data.grammar.grammar.canonical_kinds[use.kind]? = some canonical := by simp [canonical]
  obtain ⟨_, _, semanticRead⟩ := record_child_read program recordsOwned stored childFound (read 18)
    (local_evaluates program slotRead) wordsFit
  let first := before.bindLocal 20 (.signed .i32 use.kind)
  have firstHeld : TokenResources data use grammarCell outputCell cursorCell values first :=
    held.bindLocal 20 (.signed .i32 use.kind) (by decide)
  have firstLocal {id : VarId} {value : Value} (different : (20 : VarId) ≠ id)
      (found : before.local? id = some value) : first.local? id = some value :=
    (bindLocal_preserves_other_local wellFormed different).trans found
  have semanticLocal : first.local? 20 = some (.signed .i32 use.kind) := bindLocal_finds_local _ _ _ wellFormed
  have tokenRead := local_evaluates program (firstLocal (by decide) payloadRead)
  have countResult := local_evaluates program (firstLocal (by decide) countRead)
  have indexCheck := greaterEqual_evaluates tokenRead countResult
  have quotient := evaluatesNatI32Divide (leftValue := use.position) (rightValue := 2)
    (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ firstHeld.cursor))
    (show Evaluates program first (number 2) (.signed .i32 2) first from ⟨1, rfl⟩)
    (by decide) (by have := valid.tokenEq; omega)
  have positionCheck : Evaluates program first
      (binary .notEqual (read 19) (binary .divide (read 16) (number 2))) (.boolean false) first := by
    apply evaluatesEagerBinary (by decide) (by decide) tokenRead quotient
    simp [evalBinaryValue, scalarEqual, valid.tokenEq]
  have nonnegativeCheck := lessEqual_evaluates (local_evaluates program semanticLocal) (negativeOne_evaluates program first)
  have kindCheck := greaterEqual_evaluates (local_evaluates program semanticLocal)
    (local_evaluates program (firstLocal (by decide) kindCountRead))
  have guard := evaluatesPureLogicalOr (evaluatesPureLogicalOr (evaluatesPureLogicalOr
    indexCheck positionCheck) nonnegativeCheck) kindCheck
  have indexFalse : ¬ ((tokens.length : Int) ≤ use.token) := by omega
  have negativeFalse : ¬ ((use.kind : Int) ≤ -1) := by omega
  have kindFalse : ¬ ((data.grammar.grammar.n_kinds : Int) ≤ use.kind) := by omega
  simp only [indexFalse, negativeFalse, kindFalse, decide_false, Bool.false_or] at guard
  have rawRead := read_word program (kindsOwned.bindLocal wellFormed 20 (.signed .i32 use.kind) (by decide))
    (read 19) use.token (by simp [List.getElem?_map, rawFound, raw] : (tokens.map Int.ofNat)[use.token]? = some (Int.ofNat raw)) tokenRead
  let second := first.bindLocal 21 (.signed .i32 raw)
  have secondHeld : TokenResources data use grammarCell outputCell cursorCell values second :=
    firstHeld.bindLocal 21 (.signed .i32 raw) (by decide)
  have secondLocal {id : VarId} {value : Value} (different : (21 : VarId) ≠ id)
      (found : first.local? id = some value) : second.local? id = some value :=
    (bindLocal_preserves_other_local firstHeld.wellFormed different).trans found
  have rawLocal : second.local? 21 = some (.signed .i32 raw) := bindLocal_finds_local _ _ _ firstHeld.wellFormed
  have canonicalRead := data.canonical secondHeld.grammar program (read 20) (read 11) use.kind
    (local_evaluates program (secondLocal (by decide) semanticLocal))
    (local_evaluates program (secondLocal (by decide) (firstLocal (by decide) canonicalOffsetRead))) kindBound
  let third := second.bindLocal 22 (.signed .i32 canonical)
  have thirdHeld : TokenResources data use grammarCell outputCell cursorCell values third :=
    secondHeld.bindLocal 22 (.signed .i32 canonical) (by decide)
  have thirdLocal {id : VarId} {value : Value} (different : (22 : VarId) ≠ id)
      (found : second.local? id = some value) : third.local? id = some value :=
    (bindLocal_preserves_other_local secondHeld.wellFormed different).trans found
  have canonicalLocal : third.local? 22 = some (.signed .i32 canonical) := bindLocal_finds_local _ _ _ secondHeld.wellFormed
  have payloadThird := thirdLocal (by decide) (secondLocal (by decide) (firstLocal (by decide) payloadRead))
  have doubled := evaluatesNatI32Multiply (leftValue := use.token) (rightValue := 2)
    (local_evaluates program payloadThird) (show Evaluates program third (number 2) (.signed .i32 2) third from ⟨1, rfl⟩)
    (by omega)
  have remainder := evaluatesNatI32Remainder (leftValue := use.position) (rightValue := 2)
    (local_evaluates program (Assertion.localPointsTo_local _ _ _ _ thirdHeld.cursor))
    (show Evaluates program third (number 2) (.signed .i32 2) third from ⟨1, rfl⟩)
    (by decide) (by have := Nat.mod_lt use.position (by decide : 0 < 2); omega)
  have assignmentRead := evaluatesNatI32Add (leftValue := use.token * 2) (rightValue := use.position % 2)
    doubled remainder (by change use.slot ≤ 2147483647; omega)
  let fourth := third.bindLocal 23 (.signed .i32 use.slot)
  have fourthHeld : TokenResources data use grammarCell outputCell cursorCell values fourth :=
    thirdHeld.bindLocal 23 (.signed .i32 use.slot) (by decide)
  have fourthLocal {id : VarId} {value : Value} (different : (23 : VarId) ≠ id)
      (found : third.local? id = some value) : fourth.local? id = some value :=
    (bindLocal_preserves_other_local thirdHeld.wellFormed different).trans found
  have assignmentLocal : fourth.local? 23 = some (.signed .i32 use.slot) := bindLocal_finds_local _ _ _ thirdHeld.wellFormed
  obtain ⟨completed, tailRun, cursorAfter, contents, effect⟩ := token_store_execute data program valid rawFound canonicalFound
    fourthHeld.wellFormed fourthHeld.grammar fourthHeld.cursor
    (fourthLocal (by decide) (thirdLocal (by decide) (secondLocal (by decide) semanticLocal)))
    (fourthLocal (by decide) (thirdLocal (by decide) rawLocal))
    (fourthLocal (by decide) canonicalLocal) assignmentLocal fourthHeld.output fourthHeld.backing
    available grammarSeparate (by simp only [finalPosition] at finishBound; omega)
  have fourthRun := executesLetLocal (id := 23) (type := i32) assignmentRead tailRun
  have thirdRun := executesLetLocal (id := 22) (type := i32) canonicalRead fourthRun
  have secondRun := executesLetLocal (id := 21) (type := i32) rawRead thirdRun
  have run := executesLetLocal (id := 20) (type := i32) semanticRead
    (executesSequence (executesIfFalse (thenBranch := returned (negative 1)) guard (executesSkip _ _)) secondRun)
  have fourthEffect := CellEffect.closeLocal third 23 (.signed .i32 use.slot) thirdHeld.wellFormed effect
  have thirdEffect := CellEffect.closeLocal second 22 (.signed .i32 canonical) secondHeld.wellFormed fourthEffect
  have secondEffect := CellEffect.closeLocal first 21 (.signed .i32 raw) firstHeld.wellFormed thirdEffect
  have finalEffect := CellEffect.closeLocal before 20 (.signed .i32 use.kind) wellFormed secondEffect
  exact ⟨_, run, ⟨cursor.1, cursorAfter.2⟩, contents, finalEffect⟩

end Lanius.Extraction.SemanticTokens.Collect
