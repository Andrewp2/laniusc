import Lanius.Core

namespace Lanius.X86.Select

/-- Metadata carried by the supported Core-function transport. The returned
position is proof data; only its local identifier appears in `words`. -/
structure Input where
  functionId : Nat
  ids : List Nat
  position : Fin ids.length
  trailing : Bool
  countBound : ids.length ≤ 6
  distinct : ids.Nodup
  idsBound : ∀ id ∈ ids, id ≤ 2147483647
  functionBound : functionId ≤ 2147483647

def Input.bodyLength (input : Input) : Nat := if input.trailing then 6 else 4
def Input.bodyStart (input : Input) : Nat := 6 + input.ids.length * 2
def Input.returnStart (input : Input) : Nat := input.bodyStart + if input.trailing then 1 else 0
def Input.returnedId (input : Input) : Nat := input.ids.get input.position

def Input.headerWords (input : Input) : List Int :=
  [1, 64, (input.functionId : Int), 1, (input.ids.length : Int), (input.bodyLength : Int)]
def Input.fieldWords (input : Input) : List Int := input.ids.flatMap (fun id : Nat => [(id : Int), 1])
def Input.bodyWords (input : Input) : List Int :=
  if input.trailing then [2, 10, 1, 1, (input.returnedId : Int), 0] else [10, 1, 1, (input.returnedId : Int)]
def Input.words (input : Input) : List Int := input.headerWords ++ (input.fieldWords ++ input.bodyWords)

theorem Input.fields_length (ids : List Nat) :
    (ids.flatMap (fun id : Nat => [(id : Int), 1])).length = ids.length * 2 := by
  induction ids with
  | nil => rfl
  | cons id ids ih => simp [ih, Nat.add_mul, Nat.add_comm]; omega

theorem Input.words_length (input : Input) : input.words.length = input.bodyStart + input.bodyLength := by
  cases trailing : input.trailing <;>
    simp only [words, headerWords, fieldWords, bodyWords, bodyStart, bodyLength, trailing, Bool.false_eq_true, ↓reduceIte,
      List.length_append, List.length_cons, List.length_nil, fields_length] <;> omega

theorem Input.bounds (input : Input) :
    1 ≤ input.ids.length ∧ input.ids.length ≤ 6 ∧ input.bodyStart ≤ 18 ∧
      input.words.length ≤ 24 ∧ input.returnStart + 3 < input.words.length := by
  have position := input.position.isLt
  have count := input.countBound
  rw [input.words_length]
  cases trailing : input.trailing <;> simp [bodyStart, bodyLength, returnStart, trailing] <;> omega

theorem Input.field (ids : List Nat) (index : Fin ids.length) :
    (ids.flatMap (fun id : Nat => [(id : Int), 1]))[index.val * 2]? = some (ids.get index : Int) ∧
      (ids.flatMap (fun id : Nat => [(id : Int), 1]))[index.val * 2 + 1]? = some 1 := by
  induction ids with
  | nil => exact Fin.elim0 index
  | cons id ids ih =>
    rcases index with ⟨index, bound⟩
    cases index with
    | zero => simp
    | succ index =>
      have rest := ih ⟨index, by simpa using bound⟩
      simpa only [List.flatMap_cons, List.cons_append, List.nil_append, Nat.succ_mul,
        List.getElem?_cons_succ, List.get_cons_succ,
        Nat.add_assoc] using rest

theorem append_lookup (first second : List α) (index : Nat) :
    (first ++ second)[first.length + index]? = second[index]? := by
  rw [List.getElem?_append_right (by omega), Nat.add_sub_cancel_left]

theorem Input.header (input : Input) :
    input.words[0]? = some 1 ∧ input.words[1]? = some 64 ∧
    input.words[2]? = some (input.functionId : Int) ∧ input.words[3]? = some 1 ∧
    input.words[4]? = some (input.ids.length : Int) ∧ input.words[5]? = some (input.bodyLength : Int) := by
  simp only [words, headerWords, List.cons_append, List.nil_append,
    List.getElem?_cons_zero, List.getElem?_cons_succ, and_self]

theorem Input.word_field (input : Input) (index : Fin input.ids.length) :
    input.words[6 + index.val * 2]? = some (input.ids.get index : Int) ∧
      input.words[7 + index.val * 2]? = some 1 := by
  have headerSize : input.headerWords.length = 6 := rfl
  have fieldSize : input.fieldWords.length = input.ids.length * 2 := fields_length _
  constructor
  · rw [words, ← headerSize, append_lookup, List.getElem?_append_left (by rw [fieldSize]; have := index.isLt; omega)]
    exact (field input.ids index).1
  · rw [show 7 + index.val * 2 = input.headerWords.length + (index.val * 2 + 1) by rw [headerSize]; omega,
      words, append_lookup, List.getElem?_append_left (by rw [fieldSize]; have := index.isLt; omega)]
    exact (field input.ids index).2

theorem Input.word_body (input : Input) (offset : Nat) :
    input.words[input.bodyStart + offset]? = input.bodyWords[offset]? := by
  have prefixSize : (input.headerWords ++ input.fieldWords).length = input.bodyStart := by
    simp only [List.length_append, headerWords, List.length_cons, List.length_nil, fieldWords, fields_length, bodyStart]
  rw [words, ← List.append_assoc, ← prefixSize, append_lookup]

theorem Input.return_tags (input : Input) :
    input.words[input.returnStart]? = some 10 ∧ input.words[input.returnStart + 1]? = some 1 ∧
    input.words[input.returnStart + 2]? = some 1 ∧ input.words[input.returnStart + 3]? = some (input.returnedId : Int) := by
  cases trailing : input.trailing <;>
    simp only [returnStart, trailing, Bool.false_eq_true, ↓reduceIte, Nat.add_assoc]
  · change input.words[input.bodyStart + 0]? = _ ∧ _
    simp only [word_body, bodyWords, trailing, Bool.false_eq_true, ↓reduceIte,
      List.getElem?_cons_zero, List.getElem?_cons_succ, and_self]
  · simp only [word_body, bodyWords, trailing, ↓reduceIte,
      List.getElem?_cons_zero, List.getElem?_cons_succ, and_self]

theorem Input.unwrap_tags (input : Input) (trailing : input.trailing = true) :
    input.words[input.bodyStart]? = some 2 ∧ input.words[input.bodyStart + 5]? = some 0 := by
  change input.words[input.bodyStart + 0]? = _ ∧ _
  simp only [word_body, bodyWords, trailing, ↓reduceIte,
    List.getElem?_cons_zero, List.getElem?_cons_succ, and_self]

theorem Input.id_equal (input : Input) (left right : Fin input.ids.length) :
    input.ids.get left = input.ids.get right ↔ left.val = right.val :=
  List.getElem_inj input.distinct

end Lanius.X86.Select
