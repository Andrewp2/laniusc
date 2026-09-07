import Lanius.Extraction.CanonicalTokens.Ascii.Body
import Lanius.Extraction.CanonicalTokens.Ascii.Specification

namespace Lanius.Extraction.CanonicalTokens.Ascii

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

structure Buffers where
  sourceCell : CellId
  packedCell : CellId
  cursorCell : CellId
  source : List Int
  packed : List Int
  storage : List UInt8
  spelling : List UInt8
  start : Nat
  encoded : encodeI32Array (signedI32Values packed) = .ok storage
  bytes : storage.take spelling.length = spelling
  capacity : start + spelling.length ≤ source.length
  bounded : source.length ≤ 2147483647
  source_cursor : sourceCell ≠ cursorCell
  packed_cursor : packedCell ≠ cursorCell

structure Invariant (buffers : Buffers) (locals : Locals) (index : Nat) (before : State) : Prop where
  wellFormed : StateWellFormed before
  sourceLocal : before.local? locals.source = some
    (.slice (.scalar (.signed .i32)) buffers.sourceCell [] 0 buffers.source.length)
  sourceContents : before.cellEntry? buffers.sourceCell = some {
    id := buffers.sourceCell, value := some (.array (signedI32Values buffers.source)) }
  packedLocal : before.local? locals.packed = some
    (.slice (.scalar (.signed .i32)) buffers.packedCell [] 0 buffers.packed.length)
  packedContents : before.cellEntry? buffers.packedCell = some {
    id := buffers.packedCell, value := some (.array (signedI32Values buffers.packed)) }
  start : before.local? locals.start = some (.signed .i32 buffers.start)
  limit : before.local? locals.length = some (.signed .i32 buffers.spelling.length)
  cursor : (Assertion.localPointsTo locals.cursor buffers.cursorCell (some (.signed .i32 index))).holds before
  stable : ∀ localId, localId ∈ [locals.source, locals.packed, locals.start, locals.length] →
    ∀ cell, before.cellId? localId = some cell → cell ≠ buffers.cursorCell

private theorem preserve {next : Nat} (invariant : Invariant buffers locals index before)
    (effect : ModifiesOnly (CellSet.singleton buffers.cursorCell) before after)
    (wellFormed : StateWellFormed after)
    (cursor : (Assertion.localPointsTo locals.cursor buffers.cursorCell (some (.signed .i32 next))).holds after) :
    Invariant buffers locals next after := by
  refine ⟨wellFormed, ?_, ?_, ?_, ?_, ?_, ?_, cursor, ?_⟩
  · exact effect.preserves_local invariant.wellFormed invariant.sourceLocal
      (invariant.stable _ (by simp))
  · exact effect.preserves_entry invariant.wellFormed invariant.sourceContents buffers.source_cursor
  · exact effect.preserves_local invariant.wellFormed invariant.packedLocal
      (invariant.stable _ (by simp))
  · exact effect.preserves_entry invariant.wellFormed invariant.packedContents buffers.packed_cursor
  · exact effect.preserves_local invariant.wellFormed invariant.start (invariant.stable _ (by simp))
  · exact effect.preserves_local invariant.wellFormed invariant.limit (invariant.stable _ (by simp))
  · intro localId member cell found
    apply invariant.stable localId member cell
    simpa only [State.cellId?, effect.locals] using found

private theorem condition (program : Program) (invariant : Invariant buffers locals index before) :
    Evaluates program before (.binary .notEqual (.local locals.cursor) (.local locals.length))
      (.boolean (!(Int.ofNat index == Int.ofNat buffers.spelling.length))) before := by
  have cursorResult : Evaluates program before (.local locals.cursor) (.signed .i32 index) before :=
    ⟨1, evalLocal_of_local 0 program before _ _ (Assertion.localPointsTo_local _ _ _ _ invariant.cursor)⟩
  have lengthResult : Evaluates program before (.local locals.length) (.signed .i32 buffers.spelling.length) before :=
    ⟨1, evalLocal_of_local 0 program before _ _ invariant.limit⟩
  exact evaluatesEagerBinary (by decide) (by decide) cursorResult lengthResult (by rfl)

/-- The actual Core loop terminates and rejects exactly the first unequal
byte. Reads are justified by the packed encoding, not a helper-call axiom. -/
theorem executes_loop (program : Program) (buffers : Buffers) (locals : Locals)
    (processed remaining : List UInt8) (before : State)
    (spelling : buffers.spelling = processed ++ remaining)
    (invariant : Invariant buffers locals processed.length before)
    (expected_source : locals.expected ≠ locals.source)
    (expected_start : locals.expected ≠ locals.start)
    (expected_cursor : locals.expected ≠ locals.cursor) :
    ∃ after, Executes program before locals.loop
        (if matchesBytes buffers.source (buffers.start + processed.length) remaining then .next
          else .returned (some (.boolean false))) after ∧
      StateWellFormed after ∧ ModifiesOnly (CellSet.singleton buffers.cursorCell) before after := by
  have tested := condition program invariant
  cases remaining with
  | nil =>
      have finished : buffers.spelling = processed := by simpa using spelling
      refine ⟨before, executesWhileFalse ?_, invariant.wellFormed, ModifiesOnly.reflAny _ _⟩
      simpa [finished] using tested
  | cons byte rest =>
      have count : buffers.spelling.length = processed.length + 1 + rest.length := by
        simp [spelling]; omega
      have inBounds : buffers.start + processed.length < buffers.source.length := by
        have := buffers.capacity
        omega
      have different : Int.ofNat processed.length ≠ Int.ofNat buffers.spelling.length := by
        intro equal
        have lengths := Int.ofNat.inj equal
        omega
      have conditionTrue : Evaluates program before
          (.binary .notEqual (.local locals.cursor) (.local locals.length)) (.boolean true) before := by
        rw [beq_eq_false_iff_ne.mpr different] at tested
        exact tested
      have selected : buffers.storage[processed.length]? = some byte := by
        have selected := congrArg (fun bytes : List UInt8 => bytes[processed.length]?) buffers.bytes
        have bound : processed.length < buffers.spelling.length := by omega
        simpa [List.getElem?_take, bound, spelling] using selected
      have packedResult : Evaluates program before (.local locals.packed)
          (.slice (.scalar (.signed .i32)) buffers.packedCell [] 0 buffers.packed.length) before :=
        ⟨1, evalLocal_of_local 0 program before _ _ invariant.packedLocal⟩
      have cursorResult : Evaluates program before (.local locals.cursor) (.signed .i32 processed.length) before :=
        ⟨1, evalLocal_of_local 0 program before _ _ (Assertion.localPointsTo_local _ _ _ _ invariant.cursor)⟩
      have expectedByte := Input.evaluates_encoded_byte program before (.local locals.packed)
        (.local locals.cursor) buffers.packedCell buffers.packed buffers.storage processed.length byte
        (by have := buffers.bounded; omega) packedResult cursorResult invariant.packedContents buffers.encoded selected
      obtain ⟨middle, body, middleWF, cursor, effect⟩ := executes_body program before locals
        buffers.sourceCell buffers.cursorCell buffers.source buffers.start processed.length byte
        invariant.wellFormed inBounds buffers.bounded expected_source expected_start expected_cursor
        invariant.sourceLocal invariant.sourceContents invariant.start invariant.cursor expectedByte
      have observed : buffers.source[buffers.start + processed.length]? =
          some (buffers.source.get ⟨buffers.start + processed.length, inBounds⟩) := by simp [inBounds]
      by_cases same : buffers.source.get ⟨buffers.start + processed.length, inBounds⟩ = (byte.toNat : Int)
      · simp only [if_pos same] at body cursor
        have equal : (buffers.source[buffers.start + processed.length]? == some (byte.toNat : Int)) = true := by
          apply beq_iff_eq.mpr
          rw [observed, same]
        have nextInvariant : Invariant buffers locals (processed ++ [byte]).length middle := by
          simpa using preserve invariant effect middleWF cursor
        have nextSpelling : buffers.spelling = (processed ++ [byte]) ++ rest := by
          simpa [List.append_assoc] using spelling
        obtain ⟨after, run, afterWF, loopEffect⟩ := executes_loop program buffers locals (processed ++ [byte]) rest
          middle nextSpelling nextInvariant expected_source expected_start expected_cursor
        refine ⟨after, ?_, afterWF, effect.trans_same loopEffect⟩
        have completed := executesWhileTrueThen conditionTrue body run
        simpa only [Locals.loop, matchesBytes, equal, Bool.true_and,
          List.length_append, List.length_singleton, Nat.add_assoc] using completed
      · simp only [if_neg same] at body cursor
        have unequal : (buffers.source[buffers.start + processed.length]? == some (byte.toNat : Int)) = false := by
          apply beq_eq_false_iff_ne.mpr
          intro equal
          rw [observed] at equal
          exact same (Option.some.inj equal)
        refine ⟨middle, ?_, middleWF, effect⟩
        simpa only [Locals.loop, matchesBytes, unequal, Bool.false_and, Bool.false_eq_true, ↓reduceIte] using
          executesWhileReturned conditionTrue body
termination_by remaining.length

/-- The fallthrough return and the early mismatch return both implement the
same Boolean specification, with no execution of the tail after rejection. -/
theorem executes_finish (program : Program) (buffers : Buffers) (locals : Locals)
    (before : State) (invariant : Invariant buffers locals 0 before)
    (expected_source : locals.expected ≠ locals.source)
    (expected_start : locals.expected ≠ locals.start)
    (expected_cursor : locals.expected ≠ locals.cursor) :
    ∃ after, Executes program before locals.finish
      (.returned (some (.boolean (matchesBytes buffers.source buffers.start buffers.spelling)))) after ∧
      StateWellFormed after ∧ ModifiesOnly (CellSet.singleton buffers.cursorCell) before after := by
  obtain ⟨after, run, wellFormed, effect⟩ := executes_loop program buffers locals [] buffers.spelling
    before rfl invariant expected_source expected_start expected_cursor
  simp only [List.length_nil, Nat.add_zero] at run
  refine ⟨after, ?_, wellFormed, effect⟩
  cases matched : matchesBytes buffers.source buffers.start buffers.spelling with
  | false =>
      simp only [matched, Bool.false_eq_true, ↓reduceIte] at run ⊢
      exact executesSequenceReturned run
  | true =>
      simp only [matched, ↓reduceIte] at run ⊢
      exact executesSequence run (executesSequenceReturned
        (executesReturnValue (show Evaluates program after (.value (.boolean true)) (.boolean true) after from ⟨1, rfl⟩)))

/-- Any successful evaluation of this source loop agrees with the byte-span
specification; the witness execution above is not a separate interpreter. -/
theorem loop_sound (program : Program) (buffers : Buffers) (locals : Locals)
    (processed remaining : List UInt8) (before : State)
    (spelling : buffers.spelling = processed ++ remaining)
    (invariant : Invariant buffers locals processed.length before)
    (expected_source : locals.expected ≠ locals.source)
    (expected_start : locals.expected ≠ locals.start)
    (expected_cursor : locals.expected ≠ locals.cursor)
    (actual : Executes program before locals.loop completion after) :
    completion = (if matchesBytes buffers.source (buffers.start + processed.length) remaining
      then .next else .returned (some (.boolean false))) ∧
      StateWellFormed after ∧ ModifiesOnly (CellSet.singleton buffers.cursorCell) before after := by
  obtain ⟨expected, executed, wellFormed, effect⟩ := executes_loop program buffers locals
    processed remaining before spelling invariant expected_source expected_start expected_cursor
  obtain ⟨sameCompletion, sameState⟩ := Lanius.Fuel.executes_deterministic actual executed
  subst after
  exact ⟨sameCompletion, wellFormed, effect⟩

end Lanius.Extraction.CanonicalTokens.Ascii
