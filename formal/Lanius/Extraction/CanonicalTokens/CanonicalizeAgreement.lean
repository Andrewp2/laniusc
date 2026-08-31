import Lanius.Extraction.CanonicalTokens.CanonicalizeExecution

namespace Lanius.Extraction.CanonicalTokens.CanonicalizeAgreement

open Lanius
open Lanius.Compiler
open Lanius.Compiler.Lexer
open Lanius.Extraction.CanonicalTokens

namespace Model

@[simp] theorem encodeToken_length (token : RawToken) :
    (CanonicalizeModel.encodeToken token).length = 3 := by
  rfl

@[simp] theorem encodeTokens_length (tokens : List RawToken) :
    (CanonicalizeModel.encodeTokens tokens).length = 3 * tokens.length := by
  induction tokens with
  | nil => rfl
  | cons token rest induction =>
      change (CanonicalizeModel.encodeToken token ++
        CanonicalizeModel.encodeTokens rest).length = _
      rw [List.length_append, encodeToken_length, induction]
      simp
      omega

@[simp] theorem sourceIntegers_drop_take_toNat (source : List Byte)
    (start count : Nat) :
    (((CanonicalizeModel.sourceIntegers source).drop start).take count).map
        Int.toNat =
      ((source.drop start).take count).map Fin.val := by
  simp [CanonicalizeModel.sourceIntegers, Function.comp_def]

theorem canonicalKind_result (source : List Byte) (token : RawToken) :
    CanonicalKind.result (CanonicalizeModel.sourceIntegers source)
        (Int.ofNat token.kind.gpuCode) token.start token.finish =
      Int.ofNat (canonicalKind source token).gpuCode := by
  have identifierCode :
      (Int.ofNat token.kind.gpuCode =
        Int.ofNat TokenKind.identifier.gpuCode) ↔
      token.kind = .identifier := by
    cases token.kind <;> native_decide
  by_cases identifier : token.kind = .identifier
  · have codeIsIdentifier :
        Int.ofNat token.kind.gpuCode =
          Int.ofNat TokenKind.identifier.gpuCode :=
      identifierCode.mpr identifier
    unfold CanonicalKind.result
    rw [if_pos codeIsIdentifier]
    unfold CanonicalKind.keywordKind CanonicalTokens.Model.keywordKind
      CanonicalTokens.Model.keywordSpan
    rw [sourceIntegers_drop_take_toNat]
    unfold canonicalKind tokenByteValues
    rw [if_pos identifier]
    cases exactKeywordKind
        (((source.drop token.start).take
          (token.finish - token.start)).map Fin.val) keywordRules <;> rfl
  · have codeIsNotIdentifier :
        Int.ofNat token.kind.gpuCode ≠
          Int.ofNat TokenKind.identifier.gpuCode := by
      intro same
      exact identifier (identifierCode.mp same)
    unfold CanonicalKind.result
    rw [if_neg codeIsNotIdentifier]
    unfold canonicalKind
    rw [if_neg identifier]

theorem isTriviaCode_gpuCode (kind : TokenKind) :
    CanonicalizeExecution.isTriviaCode (Int.ofNat kind.gpuCode) =
      isTriviaKind kind := by
  cases kind <;> native_decide

theorem writeTokens_append (records : List Int) (start : Nat)
    (left right : List RawToken) :
    CanonicalizeModel.writeTokens records start (left ++ right) =
      CanonicalizeModel.writeTokens
        (CanonicalizeModel.writeTokens records start left)
        (start + left.length) right := by
  induction left generalizing records start with
  | nil => simp [CanonicalizeModel.writeTokens]
  | cons token rest induction =>
      simp only [List.cons_append, CanonicalizeModel.writeTokens]
      rw [induction]
      simp only [List.length_cons]
      congr 1
      omega

@[simp] theorem encodeTokens_append (left right : List RawToken) :
    CanonicalizeModel.encodeTokens (left ++ right) =
      CanonicalizeModel.encodeTokens left ++
        CanonicalizeModel.encodeTokens right := by
  simp [CanonicalizeModel.encodeTokens, List.flatMap_append]

theorem getElem!_set_ne (values : List Int) (updated index : Nat)
    (value : Int) (different : updated ≠ index) :
    (values.set updated value)[index]! = values[index]! := by
  simp [List.getElem!_eq_getElem?_getD, List.getElem?_set, different]

theorem writeToken_word_after (records : List Int) (tokenIndex word : Nat)
    (token : RawToken) (after : 3 * (tokenIndex + 1) ≤ word) :
    (CanonicalizeModel.writeToken records tokenIndex token)[word]! =
      records[word]! := by
  unfold CanonicalizeModel.writeToken
  simp only [Lanius.Semantics.setI32Value]
  rw [getElem!_set_ne, getElem!_set_ne, getElem!_set_ne]
  all_goals omega

theorem writeToken_eq_writeRecord (records : List Int) (tokenIndex : Nat)
    (token : RawToken) :
    CanonicalizeModel.writeToken records tokenIndex token =
      CanonicalizeExecution.writeRecord records tokenIndex
        (Int.ofNat token.kind.gpuCode) (Int.ofNat token.start)
        (Int.ofNat token.finish) := by
  rfl

theorem writeTokens_word_after (records : List Int) (tokenIndex word : Nat)
    (tokens : List RawToken)
    (after : 3 * (tokenIndex + tokens.length) ≤ word) :
    (CanonicalizeModel.writeTokens records tokenIndex tokens)[word]! =
      records[word]! := by
  induction tokens generalizing records tokenIndex with
  | nil => simp [CanonicalizeModel.writeTokens]
  | cons token rest induction =>
      simp only [CanonicalizeModel.writeTokens]
      simp only [List.length_cons] at after
      rw [induction]
      · apply writeToken_word_after
        omega
      · omega

theorem encoded_kind_at (leading trailing : List RawToken)
    (token : RawToken) :
    getElem! (CanonicalizeModel.encodeTokens (leading ++ token :: trailing))
        (3 * leading.length) = Int.ofNat token.kind.gpuCode := by
  rw [encodeTokens_append]
  rw [show CanonicalizeModel.encodeTokens (token :: trailing) =
    CanonicalizeModel.encodeToken token ++
      CanonicalizeModel.encodeTokens trailing by rfl]
  change getElem! (CanonicalizeModel.encodeTokens leading ++
    (CanonicalizeModel.encodeToken token ++
      CanonicalizeModel.encodeTokens trailing)) (3 * leading.length) = _
  rw [show 3 * leading.length =
    (CanonicalizeModel.encodeTokens leading).length by
      exact (encodeTokens_length leading).symm]
  simp [CanonicalizeModel.encodeToken,
    List.getElem!_eq_getElem?_getD]

theorem encoded_start_at (leading trailing : List RawToken)
    (token : RawToken) :
    getElem! (CanonicalizeModel.encodeTokens (leading ++ token :: trailing))
        (3 * leading.length + 1) = Int.ofNat token.start := by
  rw [encodeTokens_append]
  rw [show CanonicalizeModel.encodeTokens (token :: trailing) =
    CanonicalizeModel.encodeToken token ++
      CanonicalizeModel.encodeTokens trailing by rfl]
  change getElem! (CanonicalizeModel.encodeTokens leading ++
    (CanonicalizeModel.encodeToken token ++
      CanonicalizeModel.encodeTokens trailing)) (3 * leading.length + 1) = _
  rw [show 3 * leading.length =
    (CanonicalizeModel.encodeTokens leading).length by
      exact (encodeTokens_length leading).symm]
  simp [CanonicalizeModel.encodeToken,
    List.getElem!_eq_getElem?_getD]

theorem encoded_finish_at (leading trailing : List RawToken)
    (token : RawToken) :
    getElem! (CanonicalizeModel.encodeTokens (leading ++ token :: trailing))
        (3 * leading.length + 2) = Int.ofNat token.finish := by
  rw [encodeTokens_append]
  rw [show CanonicalizeModel.encodeTokens (token :: trailing) =
    CanonicalizeModel.encodeToken token ++
      CanonicalizeModel.encodeTokens trailing by rfl]
  change getElem! (CanonicalizeModel.encodeTokens leading ++
    (CanonicalizeModel.encodeToken token ++
      CanonicalizeModel.encodeTokens trailing)) (3 * leading.length + 2) = _
  rw [show 3 * leading.length =
    (CanonicalizeModel.encodeTokens leading).length by
      exact (encodeTokens_length leading).symm]
  simp [CanonicalizeModel.encodeToken,
    List.getElem!_eq_getElem?_getD]

theorem written_kind_at_unread (sourcePrefix sourceSuffix accepted : List RawToken)
    (token : RawToken) (acceptedBound : accepted.length ≤ sourcePrefix.length) :
    getElem! (CanonicalizeModel.writeTokens
      (CanonicalizeModel.encodeTokens (sourcePrefix ++ token :: sourceSuffix))
      0 accepted) (3 * sourcePrefix.length) =
      Int.ofNat token.kind.gpuCode := by
  rw [writeTokens_word_after]
  · exact encoded_kind_at sourcePrefix sourceSuffix token
  · simp only [Nat.zero_add]
    omega

theorem written_start_at_unread (sourcePrefix sourceSuffix accepted : List RawToken)
    (token : RawToken) (acceptedBound : accepted.length ≤ sourcePrefix.length) :
    getElem! (CanonicalizeModel.writeTokens
      (CanonicalizeModel.encodeTokens (sourcePrefix ++ token :: sourceSuffix))
      0 accepted) (3 * sourcePrefix.length + 1) =
      Int.ofNat token.start := by
  rw [writeTokens_word_after]
  · exact encoded_start_at sourcePrefix sourceSuffix token
  · simp only [Nat.zero_add]
    omega

theorem written_finish_at_unread (sourcePrefix sourceSuffix accepted : List RawToken)
    (token : RawToken) (acceptedBound : accepted.length ≤ sourcePrefix.length) :
    getElem! (CanonicalizeModel.writeTokens
      (CanonicalizeModel.encodeTokens (sourcePrefix ++ token :: sourceSuffix))
      0 accepted) (3 * sourcePrefix.length + 2) =
      Int.ofNat token.finish := by
  rw [writeTokens_word_after]
  · exact encoded_finish_at sourcePrefix sourceSuffix token
  · simp only [Nat.zero_add]
    omega

def canonicalToken (source : List Byte) (token : RawToken) : RawToken :=
  { token with kind := canonicalKind source token }

@[simp] theorem canonicalToken_kind (source : List Byte) (token : RawToken) :
    (canonicalToken source token).kind = canonicalKind source token := rfl

@[simp] theorem canonicalToken_start (source : List Byte) (token : RawToken) :
    (canonicalToken source token).start = token.start := rfl

@[simp] theorem canonicalToken_finish (source : List Byte) (token : RawToken) :
    (canonicalToken source token).finish = token.finish := rfl

theorem firstPass_from (source : List Byte)
    (processed remaining accepted : List RawToken)
    (acceptedBound : accepted.length ≤ processed.length) :
    CanonicalizeExecution.firstPass
        (CanonicalizeModel.sourceIntegers source)
        (processed ++ remaining).length processed.length
        (CanonicalizeModel.writeTokens
          (CanonicalizeModel.encodeTokens (processed ++ remaining)) 0 accepted)
        accepted.length =
      (CanonicalizeModel.writeTokens
          (CanonicalizeModel.encodeTokens (processed ++ remaining)) 0
          (accepted ++ filterRetagTokens source remaining),
        accepted.length + (filterRetagTokens source remaining).length) := by
  induction remaining generalizing processed accepted with
  | nil =>
      rw [CanonicalizeExecution.firstPass]
      simp [filterRetagTokens]
  | cons token rest induction =>
      let original := CanonicalizeModel.encodeTokens
        (processed ++ token :: rest)
      let current := CanonicalizeModel.writeTokens original 0 accepted
      have inputBound : processed.length < (processed ++ token :: rest).length := by
        simp
      have kindAt : current[3 * processed.length]! =
          Int.ofNat token.kind.gpuCode := by
        exact written_kind_at_unread processed rest accepted token acceptedBound
      have startAt : current[3 * processed.length + 1]! =
          Int.ofNat token.start := by
        exact written_start_at_unread processed rest accepted token acceptedBound
      have finishAt : current[3 * processed.length + 2]! =
          Int.ofNat token.finish := by
        exact written_finish_at_unread processed rest accepted token acceptedBound
      rw [CanonicalizeExecution.firstPass]
      simp only [inputBound, dite_true]
      change CanonicalizeExecution.firstPass
          (CanonicalizeModel.sourceIntegers source)
          (processed ++ token :: rest).length (processed.length + 1)
          (CanonicalizeExecution.firstStepRecords
            (CanonicalizeModel.sourceIntegers source) current accepted.length
            current[3 * processed.length]!
            current[3 * processed.length + 1]!
            current[3 * processed.length + 2]!)
          (CanonicalizeExecution.firstStepOutput accepted.length
            current[3 * processed.length]!) = _
      rw [kindAt, startAt, finishAt]
      simp only [CanonicalizeExecution.firstStepRecords,
        CanonicalizeExecution.firstStepOutput]
      rw [isTriviaCode_gpuCode]
      by_cases trivia : isTriviaKind token.kind = true
      · rw [trivia]
        simp only [if_true]
        have recurse := induction (processed := processed ++ [token])
          (accepted := accepted) (by simp; omega)
        simpa [original, current, filterRetagTokens, canonicalizeToken, trivia,
          List.append_assoc] using recurse
      · have kept : isTriviaKind token.kind = false := by
          cases found : isTriviaKind token.kind <;> simp_all
        rw [kept]
        simp only [Bool.false_eq_true, if_false]
        rw [show (Int.ofNat token.start).toNat = token.start by
          exact Int.toNat_natCast token.start]
        rw [show (Int.ofNat token.finish).toNat = token.finish by
          exact Int.toNat_natCast token.finish]
        rw [canonicalKind_result]
        have recurse := induction (processed := processed ++ [token])
          (accepted := accepted ++ [canonicalToken source token])
          (by simp; omega)
        have nextRecords :
            CanonicalizeExecution.writeRecord current accepted.length
                (Int.ofNat (canonicalKind source token).gpuCode)
                (Int.ofNat token.start) (Int.ofNat token.finish) =
              CanonicalizeModel.writeTokens original 0
                (accepted ++ [canonicalToken source token]) := by
          rw [writeTokens_append]
          simp [CanonicalizeModel.writeTokens, writeToken_eq_writeRecord,
            current, original, canonicalToken]
        rw [nextRecords]
        have recurse' := recurse
        simp [original, current, filterRetagTokens, canonicalizeToken, kept,
          canonicalToken, List.append_assoc] at recurse' ⊢
        rw [show accepted.length +
          ((filterRetagTokens source rest).length + 1) =
            accepted.length + 1 +
              (filterRetagTokens source rest).length by omega]
        exact recurse'

theorem firstPass_agrees (source : List Byte) (raw : List RawToken) :
    CanonicalizeExecution.firstPass
        (CanonicalizeModel.sourceIntegers source) raw.length 0
        (CanonicalizeModel.encodeTokens raw) 0 =
      (CanonicalizeModel.writeTokens (CanonicalizeModel.encodeTokens raw) 0
          (filterRetagTokens source raw),
        (filterRetagTokens source raw).length) := by
  simpa [CanonicalizeModel.writeTokens] using
    firstPass_from source [] raw [] (by simp)

theorem writeToken_set_before (records : List Int) (tokenIndex word : Nat)
    (token : RawToken) (value : Int) (before : word < 3 * tokenIndex) :
    CanonicalizeModel.writeToken (records.set word value) tokenIndex token =
      (CanonicalizeModel.writeToken records tokenIndex token).set word value := by
  let row := 3 * tokenIndex
  change (((records.set word value).set row
      (Int.ofNat token.kind.gpuCode)).set (row + 1)
      (Int.ofNat token.start)).set (row + 2) (Int.ofNat token.finish) = _
  calc
    _ = (((records.set row (Int.ofNat token.kind.gpuCode)).set word value).set
          (row + 1) (Int.ofNat token.start)).set
          (row + 2) (Int.ofNat token.finish) := by
      rw [List.set_comm value (Int.ofNat token.kind.gpuCode) (by omega)]
    _ = (((records.set row (Int.ofNat token.kind.gpuCode)).set
          (row + 1) (Int.ofNat token.start)).set word value).set
          (row + 2) (Int.ofNat token.finish) := by
      rw [List.set_comm value (Int.ofNat token.start) (by omega)]
    _ = ((((records.set row (Int.ofNat token.kind.gpuCode)).set
          (row + 1) (Int.ofNat token.start)).set
          (row + 2) (Int.ofNat token.finish)).set word value) := by
      rw [List.set_comm value (Int.ofNat token.finish) (by omega)]

theorem writeTokens_set_before (records : List Int) (tokenIndex word : Nat)
    (tokens : List RawToken) (value : Int) (before : word < 3 * tokenIndex) :
    CanonicalizeModel.writeTokens (records.set word value) tokenIndex tokens =
      (CanonicalizeModel.writeTokens records tokenIndex tokens).set word value := by
  induction tokens generalizing records tokenIndex with
  | nil => simp [CanonicalizeModel.writeTokens]
  | cons token rest induction =>
      simp only [CanonicalizeModel.writeTokens]
      rw [writeToken_set_before records tokenIndex word token value before]
      rw [induction]
      omega

def withKind (token : RawToken) (kind : TokenKind) : RawToken :=
  { token with kind := kind }

theorem writeToken_withKind (records : List Int) (tokenIndex : Nat)
    (token : RawToken) (kind : TokenKind) :
    CanonicalizeModel.writeToken records tokenIndex (withKind token kind) =
      (CanonicalizeModel.writeToken records tokenIndex token).set
        (3 * tokenIndex) (Int.ofNat kind.gpuCode) := by
  unfold CanonicalizeModel.writeToken withKind Lanius.Semantics.setI32Value
  let row := 3 * tokenIndex
  change ((records.set row (Int.ofNat kind.gpuCode)).set
      (row + 1) (Int.ofNat token.start)).set
      (row + 2) (Int.ofNat token.finish) = _
  symm
  calc
    _ = ((((records.set row (Int.ofNat token.kind.gpuCode)).set row
          (Int.ofNat kind.gpuCode)).set (row + 1)
          (Int.ofNat token.start)).set (row + 2)
          (Int.ofNat token.finish)) := by
      rw [List.set_comm (Int.ofNat token.finish) (Int.ofNat kind.gpuCode)
        (by omega)]
      rw [List.set_comm (Int.ofNat token.start) (Int.ofNat kind.gpuCode)
        (by omega)]
    _ = _ := by rw [List.set_set]

theorem writeTokens_withKind (records : List Int) (start : Nat)
    (processed remaining : List RawToken) (token : RawToken)
    (kind : TokenKind) :
    CanonicalizeModel.writeTokens records start
        (processed ++ withKind token kind :: remaining) =
      (CanonicalizeModel.writeTokens records start
        (processed ++ token :: remaining)).set
          (3 * (start + processed.length)) (Int.ofNat kind.gpuCode) := by
  rw [writeTokens_append, writeTokens_append]
  simp only [CanonicalizeModel.writeTokens, List.length_cons]
  rw [writeToken_withKind]
  rw [writeTokens_set_before]
  omega

theorem gpuCode_eq_dotDot (kind : TokenKind) :
    (Int.ofNat kind.gpuCode == (182 : Int)) = (kind == .dotDot) := by
  cases kind <;> native_decide

theorem gpuCode_eq_assign (kind : TokenKind) :
    (Int.ofNat kind.gpuCode == (8 : Int)) = (kind == .assign) := by
  cases kind <;> native_decide

theorem gpuCode_eq_dotDot_prop (kind : TokenKind) :
    Int.ofNat kind.gpuCode = (182 : Int) ↔ kind = .dotDot := by
  cases kind <;> native_decide

theorem gpuCode_eq_assign_prop (kind : TokenKind) :
    Int.ofNat kind.gpuCode = (8 : Int) ↔ kind = .assign := by
  cases kind <;> native_decide

def inclusiveHead (current next : RawToken) : RawToken :=
  if isInclusiveRangePair current next then
    withKind current .dotDotEqual
  else
    current

theorem writeToken_word_before (records : List Int) (tokenIndex word : Nat)
    (token : RawToken) (before : word < 3 * tokenIndex) :
    (CanonicalizeModel.writeToken records tokenIndex token)[word]! =
      records[word]! := by
  unfold CanonicalizeModel.writeToken
  simp only [Lanius.Semantics.setI32Value]
  rw [getElem!_set_ne, getElem!_set_ne, getElem!_set_ne]
  all_goals omega

theorem writeTokens_word_before (records : List Int) (tokenIndex word : Nat)
    (tokens : List RawToken) (before : word < 3 * tokenIndex) :
    (CanonicalizeModel.writeTokens records tokenIndex tokens)[word]! =
      records[word]! := by
  induction tokens generalizing records tokenIndex with
  | nil => simp [CanonicalizeModel.writeTokens]
  | cons token rest induction =>
      simp only [CanonicalizeModel.writeTokens]
      rw [induction]
      · exact writeToken_word_before records tokenIndex word token before
      · omega

theorem writeToken_kind_same (records : List Int) (tokenIndex : Nat)
    (token : RawToken) (inBounds : 3 * tokenIndex < records.length) :
    getElem! (CanonicalizeModel.writeToken records tokenIndex token)
        (3 * tokenIndex) = Int.ofNat token.kind.gpuCode := by
  simp [CanonicalizeModel.writeToken, Lanius.Semantics.setI32Value,
    List.getElem!_eq_getElem?_getD, List.getElem?_set, inBounds]

theorem writeToken_start_same (records : List Int) (tokenIndex : Nat)
    (token : RawToken) (inBounds : 3 * tokenIndex + 1 < records.length) :
    getElem! (CanonicalizeModel.writeToken records tokenIndex token)
        (3 * tokenIndex + 1) = Int.ofNat token.start := by
  simp [CanonicalizeModel.writeToken, Lanius.Semantics.setI32Value,
    List.getElem!_eq_getElem?_getD, List.getElem?_set, inBounds]

theorem writeToken_finish_same (records : List Int) (tokenIndex : Nat)
    (token : RawToken) (inBounds : 3 * tokenIndex + 2 < records.length) :
    getElem! (CanonicalizeModel.writeToken records tokenIndex token)
        (3 * tokenIndex + 2) = Int.ofNat token.finish := by
  simp [CanonicalizeModel.writeToken, Lanius.Semantics.setI32Value,
    List.getElem!_eq_getElem?_getD, List.getElem?_set, inBounds]

theorem writeTokens_kind_at (records : List Int) (start : Nat)
    (processed remaining : List RawToken) (token : RawToken)
    (inBounds : 3 * (start + processed.length) < records.length) :
    (CanonicalizeModel.writeTokens records start
      (processed ++ token :: remaining))[3 * (start + processed.length)]! =
        Int.ofNat token.kind.gpuCode := by
  rw [writeTokens_append]
  simp only [CanonicalizeModel.writeTokens]
  rw [writeTokens_word_before]
  · apply writeToken_kind_same _ _ token
    simpa using inBounds
  · omega

theorem writeTokens_start_at (records : List Int) (start : Nat)
    (processed remaining : List RawToken) (token : RawToken)
    (inBounds : 3 * (start + processed.length) + 1 < records.length) :
    (CanonicalizeModel.writeTokens records start
      (processed ++ token :: remaining))[3 * (start + processed.length) + 1]! =
        Int.ofNat token.start := by
  rw [writeTokens_append]
  simp only [CanonicalizeModel.writeTokens]
  rw [writeTokens_word_before]
  · apply writeToken_start_same _ _ token
    simpa using inBounds
  · omega

theorem writeTokens_finish_at (records : List Int) (start : Nat)
    (processed remaining : List RawToken) (token : RawToken)
    (inBounds : 3 * (start + processed.length) + 2 < records.length) :
    (CanonicalizeModel.writeTokens records start
      (processed ++ token :: remaining))[3 * (start + processed.length) + 2]! =
        Int.ofNat token.finish := by
  rw [writeTokens_append]
  simp only [CanonicalizeModel.writeTokens]
  rw [writeTokens_word_before]
  · apply writeToken_finish_same _ _ token
    simpa using inBounds
  · omega

theorem secondMatches_written (records : List Int)
    (processed rest : List RawToken) (current next : RawToken)
    (capacity : 3 * (processed ++ current :: next :: rest).length ≤
      records.length) :
    CanonicalizeExecution.secondMatches
        (CanonicalizeModel.writeTokens records 0
          (processed ++ current :: next :: rest)) processed.length =
      isInclusiveRangePair current next := by
  unfold CanonicalizeExecution.secondMatches isInclusiveRangePair
  have capacity' : 3 * (processed.length + rest.length + 2) ≤
      records.length := by
    simp only [List.length_append, List.length_cons, List.length_nil] at capacity
    omega
  have currentKind := writeTokens_kind_at records 0 processed
    (next :: rest) current (by omega)
  have nextKind :
      (CanonicalizeModel.writeTokens records 0
        (processed ++ current :: next :: rest))[3 * (processed.length + 1)]! =
        Int.ofNat next.kind.gpuCode := by
    simpa [List.append_assoc] using
      (writeTokens_kind_at records 0 (processed ++ [current]) rest next
        (by
          simp only [List.length_append, List.length_cons, List.length_nil]
          omega))
  have nextStart :
      (CanonicalizeModel.writeTokens records 0
        (processed ++ current :: next :: rest))[3 * (processed.length + 1) + 1]! =
        Int.ofNat next.start := by
    simpa [List.append_assoc] using
      (writeTokens_start_at records 0 (processed ++ [current]) rest next
        (by
          simp only [List.length_append, List.length_cons, List.length_nil]
          omega))
  have currentFinish := writeTokens_finish_at records 0 processed
    (next :: rest) current (by omega)
  simp only [Nat.zero_add] at currentKind nextKind nextStart currentFinish
  rw [currentKind, nextKind, nextStart, currentFinish]
  have currentDecision :
      decide (Int.ofNat current.kind.gpuCode = (182 : Int)) =
        decide (current.kind = .dotDot) := by
    apply Bool.eq_iff_iff.mpr
    simpa using gpuCode_eq_dotDot_prop current.kind
  have nextDecision :
      decide (Int.ofNat next.kind.gpuCode = (8 : Int)) =
        decide (next.kind = .assign) := by
    apply Bool.eq_iff_iff.mpr
    simpa using gpuCode_eq_assign_prop next.kind
  rw [currentDecision, nextDecision]
  have positionDecision :
      decide (Int.ofNat next.start = Int.ofNat current.finish) =
        decide (next.start = current.finish) := by
    apply Bool.eq_iff_iff.mpr
    simp only [decide_eq_true_eq]
    constructor
    · intro equal
      apply Int.ofNat_inj.mp
      simpa using equal
    · intro equal
      simpa using congrArg Int.ofNat equal
  rw [positionDecision]

theorem secondStepRecords_written (records : List Int)
    (processed rest : List RawToken) (current next : RawToken)
    (capacity : 3 * (processed ++ current :: next :: rest).length ≤
      records.length) :
    CanonicalizeExecution.secondStepRecords
        (CanonicalizeModel.writeTokens records 0
          (processed ++ current :: next :: rest)) processed.length =
      CanonicalizeModel.writeTokens records 0
        (processed ++ inclusiveHead current next :: next :: rest) := by
  unfold CanonicalizeExecution.secondStepRecords
  rw [secondMatches_written records processed rest current next capacity]
  cases paired : isInclusiveRangePair current next with
  | false => simp [inclusiveHead, paired]
  | true =>
      simp only [paired, if_true, inclusiveHead]
      have rewritten := writeTokens_withKind records 0 processed
        (next :: rest) current .dotDotEqual
      have dotDotEqualCode : Int.ofNat TokenKind.dotDotEqual.gpuCode = 189 := by
        native_decide
      rw [dotDotEqualCode] at rewritten
      simpa [Nat.zero_add, Lanius.Semantics.setI32Value] using rewritten.symm

theorem secondPass_from (records : List Int)
    (processed remaining : List RawToken)
    (capacity : 3 * (processed ++ remaining).length ≤ records.length) :
    (CanonicalizeExecution.secondPass
      (CanonicalizeModel.writeTokens records 0 (processed ++ remaining))
      (processed ++ remaining).length processed.length).1 =
      CanonicalizeModel.writeTokens records 0
        (processed ++ retagInclusiveRanges remaining) := by
  induction remaining generalizing processed with
  | nil =>
      have stopped : ¬ processed.length + 1 < processed.length := by omega
      rw [CanonicalizeExecution.secondPass]
      simp [stopped, retagInclusiveRanges]
  | cons current tail induction =>
      cases tail with
      | nil =>
          have stopped : ¬ processed.length + 1 <
              processed.length + 1 := by omega
          rw [CanonicalizeExecution.secondPass]
          simp [stopped, retagInclusiveRanges]
      | cons next rest =>
          have inBounds : processed.length + 1 <
              (processed ++ current :: next :: rest).length := by simp
          rw [CanonicalizeExecution.secondPass]
          simp only [inBounds, dite_true]
          rw [secondStepRecords_written records processed rest current next
            capacity]
          have recurse := induction (processed :=
            processed ++ [inclusiveHead current next]) (by
              simpa [List.append_assoc] using capacity)
          simpa [retagInclusiveRanges, inclusiveHead, withKind,
            List.append_assoc] using recurse

theorem secondPass_agrees (records : List Int) (tokens : List RawToken)
    (capacity : 3 * tokens.length ≤ records.length) :
    (CanonicalizeExecution.secondPass
      (CanonicalizeModel.writeTokens records 0 tokens) tokens.length 0).1 =
      CanonicalizeModel.writeTokens records 0
        (retagInclusiveRanges tokens) := by
  simpa using secondPass_from records [] tokens capacity

theorem filterRetagTokens_length_le (source : List Byte)
    (tokens : List RawToken) :
    (filterRetagTokens source tokens).length ≤ tokens.length := by
  induction tokens with
  | nil => simp [filterRetagTokens]
  | cons token rest induction =>
      unfold filterRetagTokens canonicalizeToken
      split <;> simp_all <;> omega

@[simp] theorem retagInclusiveRanges_length (tokens : List RawToken) :
    (retagInclusiveRanges tokens).length = tokens.length := by
  induction tokens with
  | nil => rfl
  | cons current tail induction =>
      cases tail with
      | nil => rfl
      | cons next rest =>
          simp only [retagInclusiveRanges, List.length_cons]
          simpa only [List.length_cons, Nat.succ_eq_add_one] using
            congrArg Nat.succ induction

theorem result_agrees (request : CanonicalizeModel.Request) :
    CanonicalizeExecution.result
        (CanonicalizeModel.sourceIntegers request.source)
        request.records request.raw.length =
      (request.resultRecords, request.resultCount) := by
  rw [request.recordsEncodeRaw]
  unfold CanonicalizeExecution.result
  rw [firstPass_agrees]
  simp only [Prod.fst, Prod.snd]
  rw [secondPass_agrees]
  · simp [CanonicalizeModel.Request.resultRecords,
      CanonicalizeModel.Request.resultCount, CanonicalizeModel.outputRecords,
      CanonicalizeModel.outputCount, CanonicalizeModel.outputTokens,
      canonicalizeTokens, request.recordsEncodeRaw]
  · rw [encodeTokens_length]
    exact Nat.mul_le_mul_left 3
      (filterRetagTokens_length_le request.source request.raw)

end Model

end Lanius.Extraction.CanonicalTokens.CanonicalizeAgreement
