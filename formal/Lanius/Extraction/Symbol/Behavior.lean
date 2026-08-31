import Lanius.Extraction.Symbol.Calls

namespace Lanius.Extraction.Symbol.Behavior

/-! A compact mathematical specification of the longest fixed-symbol match. -/

structure Match where
  kind : Int
  length : Int
  deriving DecidableEq, Repr

def classify (first second third : Int) : Match :=
  if first = 60 then
    if second = 60 then
      if third = 61 then ⟨52, 3⟩ else ⟨43, 2⟩
    else if second = 61 then ⟨14, 2⟩
    else if second = 62 then ⟨24, 2⟩ else ⟨12, 1⟩
  else if first = 62 then
    if second = 62 then
      if third = 61 then ⟨53, 3⟩ else ⟨44, 2⟩
    else if second = 61 then ⟨15, 2⟩ else ⟨13, 1⟩
  else if first = 43 then
    if second = 61 then ⟨46, 2⟩
    else if second = 43 then ⟨56, 2⟩ else ⟨6, 1⟩
  else if first = 45 then
    if second = 61 then ⟨47, 2⟩
    else if second = 45 then ⟨57, 2⟩
    else if second = 62 then ⟨75, 2⟩ else ⟨27, 1⟩
  else if first = 61 then
    if second = 61 then ⟨16, 2⟩
    else if second = 62 then ⟨113, 2⟩ else ⟨8, 1⟩
  else if first = 47 then
    if second = 47 then ⟨10, 2⟩
    else if second = 42 then ⟨11, 2⟩
    else if second = 61 then ⟨49, 2⟩ else ⟨9, 1⟩
  else if first = 38 then
    if second = 38 then ⟨17, 2⟩
    else if second = 61 then ⟨54, 2⟩ else ⟨25, 1⟩
  else if first = 124 then
    if second = 124 then ⟨18, 2⟩
    else if second = 61 then ⟨55, 2⟩ else ⟨26, 1⟩
  else if first = 33 then
    if second = 61 then ⟨40, 2⟩ else ⟨19, 1⟩
  else if first = 42 then
    if second = 61 then ⟨48, 2⟩ else ⟨7, 1⟩
  else if first = 37 then
    if second = 61 then ⟨50, 2⟩ else ⟨41, 1⟩
  else if first = 94 then
    if second = 61 then ⟨51, 2⟩ else ⟨42, 1⟩
  else if first = 46 then
    if second = 46 then ⟨182, 2⟩ else ⟨35, 1⟩
  else if first = 40 then ⟨4, 1⟩
  else if first = 41 then ⟨5, 1⟩
  else if first = 91 then ⟨20, 1⟩
  else if first = 93 then ⟨21, 1⟩
  else if first = 123 then ⟨22, 1⟩
  else if first = 125 then ⟨23, 1⟩
  else if first = 126 then ⟨45, 1⟩
  else if first = 44 then ⟨36, 1⟩
  else if first = 59 then ⟨37, 1⟩
  else if first = 58 then ⟨38, 1⟩
  else ⟨39, 1⟩

def fromSource (source : List Int) (sourceLength start : Nat) : Option Match := do
  let first ← source[start]?
  let second := if start + 1 < sourceLength then source[start + 1]?.getD (-1)
    else -1
  let third := if start + 2 < sourceLength then source[start + 2]?.getD (-1)
    else -1
  pure (classify first second third)

theorem classify_shift_left_assign :
    classify 60 60 61 = ⟨52, 3⟩ := by decide

theorem classify_shift_right_assign :
    classify 62 62 61 = ⟨53, 3⟩ := by decide

theorem classify_prefers_two_byte_operator :
    classify 43 43 (-1) = ⟨56, 2⟩ := by decide

theorem classify_defaults_to_question
    (notKnown : first ≠ 60 ∧ first ≠ 62 ∧ first ≠ 43 ∧ first ≠ 45 ∧
      first ≠ 61 ∧ first ≠ 47 ∧ first ≠ 38 ∧ first ≠ 124 ∧
      first ≠ 33 ∧ first ≠ 42 ∧ first ≠ 37 ∧ first ≠ 94 ∧
      first ≠ 46 ∧ first ≠ 40 ∧ first ≠ 41 ∧ first ≠ 91 ∧
      first ≠ 93 ∧ first ≠ 123 ∧ first ≠ 125 ∧ first ≠ 126 ∧
      first ≠ 44 ∧ first ≠ 59 ∧ first ≠ 58) :
    classify first second third = ⟨39, 1⟩ := by
  rcases notKnown with
    ⟨h60, h62, h43, h45, h61, h47, h38, h124, h33, h42, h37,
      h94, h46, h40, h41, h91, h93, h123, h125, h126, h44, h59, h58⟩
  simp [classify, h60, h62, h43, h45, h61, h47, h38, h124, h33,
    h42, h37, h94, h46, h40, h41, h91, h93, h123, h125, h126,
    h44, h59, h58]

end Lanius.Extraction.Symbol.Behavior
