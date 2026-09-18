import Lean.Elab.Tactic.Omega

namespace Lanius.Compiler.Parser

/-! # Parser workspace layout

The extracted Earley recognizer uses one caller-owned `i32` slice.  A chart
prefix occupies two words per lattice position; fixed-width state records
occupy the remaining suffix.  This file states that layout independently of
the mutable array representation and proves the address arithmetic safe,
injective, and phase-separated.
-/

def chartWords : Nat := 2

def stateWords : Nat := 9

/-- Largest token count for which `(tokenCount * 2 + 1) * 2` is a
    nonnegative signed-i32 word offset. -/
def maxTokenCount : Nat := 536870911

def finalPosition (tokenCount : Nat) : Nat :=
  tokenCount * 2

def chartCount (tokenCount : Nat) : Nat :=
  finalPosition tokenCount + 1

def stateBase (tokenCount : Nat) : Nat :=
  chartCount tokenCount * chartWords

def chartWord (position field : Nat) : Nat :=
  position * chartWords + field

def stateWord (base stateId field : Nat) : Nat :=
  base + stateId * stateWords + field

def stateCapacity (tokenCount workspaceLength : Nat) : Nat :=
  (workspaceLength - stateBase tokenCount) / stateWords

theorem stateBase_eq (tokenCount : Nat) :
    stateBase tokenCount = tokenCount * 4 + 2 := by
  simp [stateBase, chartCount, finalPosition, chartWords]
  omega

theorem stateBase_le_i32Max
    {tokenCount : Nat} (tokenBound : tokenCount ≤ maxTokenCount) :
    stateBase tokenCount ≤ 2147483647 := by
  rw [stateBase_eq]
  simp only [maxTokenCount] at tokenBound
  omega

theorem finalPosition_lt_stateBase (tokenCount : Nat) :
    finalPosition tokenCount < stateBase tokenCount := by
  simp [finalPosition, stateBase_eq]
  omega

theorem chartWord_lt_stateBase
    {tokenCount position field : Nat}
    (positionBound : position ≤ finalPosition tokenCount)
    (fieldBound : field < chartWords) :
    chartWord position field < stateBase tokenCount := by
  simp only [finalPosition, chartWords] at positionBound fieldBound
  simp only [chartWord, chartWords, stateBase_eq]
  omega

theorem chartWord_injective
    {leftPosition leftField rightPosition rightField : Nat}
    (leftFieldBound : leftField < chartWords)
    (rightFieldBound : rightField < chartWords)
    (sameWord : chartWord leftPosition leftField =
      chartWord rightPosition rightField) :
    leftPosition = rightPosition ∧ leftField = rightField := by
  simp only [chartWords] at leftFieldBound rightFieldBound
  simp only [chartWord, chartWords] at sameWord
  omega

theorem stateWord_ge_base (base stateId field : Nat) :
    base ≤ stateWord base stateId field := by
  simp only [stateWord]
  omega

theorem stateRecord_relative_lt_capacity
    {tokenCount workspaceLength stateId field : Nat}
    (stateIdBound : stateId < stateCapacity tokenCount workspaceLength)
    (fieldBound : field < stateWords) :
    stateId * stateWords + field <
      stateCapacity tokenCount workspaceLength * stateWords := by
  simp only [stateWords] at stateIdBound fieldBound ⊢
  omega

theorem stateCapacity_words_le_suffix
    (tokenCount workspaceLength : Nat) :
    stateCapacity tokenCount workspaceLength * stateWords ≤
      workspaceLength - stateBase tokenCount := by
  simpa [stateCapacity] using
    Nat.div_mul_le_self (workspaceLength - stateBase tokenCount) stateWords

theorem stateWord_lt_workspace
    {tokenCount workspaceLength stateId field : Nat}
    (baseFits : stateBase tokenCount ≤ workspaceLength)
    (stateIdBound : stateId < stateCapacity tokenCount workspaceLength)
    (fieldBound : field < stateWords) :
    stateWord (stateBase tokenCount) stateId field < workspaceLength := by
  have relativeLt := stateRecord_relative_lt_capacity stateIdBound fieldBound
  have capacityFits := stateCapacity_words_le_suffix tokenCount workspaceLength
  have relativeFits : stateId * stateWords + field <
      workspaceLength - stateBase tokenCount :=
    Nat.lt_of_lt_of_le relativeLt capacityFits
  simp only [stateWord]
  omega

theorem stateWord_injective
    {base leftState leftField rightState rightField : Nat}
    (leftFieldBound : leftField < stateWords)
    (rightFieldBound : rightField < stateWords)
    (sameWord : stateWord base leftState leftField =
      stateWord base rightState rightField) :
    leftState = rightState ∧ leftField = rightField := by
  simp only [stateWords] at leftFieldBound rightFieldBound
  simp only [stateWord, stateWords] at sameWord
  omega

theorem chart_state_words_disjoint
    {tokenCount chartPosition chartField stateId stateField : Nat}
    (positionBound : chartPosition ≤ finalPosition tokenCount)
    (chartFieldBound : chartField < chartWords) :
    chartWord chartPosition chartField ≠
      stateWord (stateBase tokenCount) stateId stateField := by
  have chartBeforeBase := chartWord_lt_stateBase positionBound chartFieldBound
  have stateAfterBase := stateWord_ge_base
    (stateBase tokenCount) stateId stateField
  omega

/-- The exact assumptions established by `recognize` before it initializes
    the chart prefix. -/
structure WorkspaceLayout where
  tokenCount : Nat
  workspaceLength : Nat
  tokenBound : tokenCount ≤ maxTokenCount
  baseFits : stateBase tokenCount ≤ workspaceLength
  workspaceI32 : workspaceLength ≤ 2147483647

def WorkspaceLayout.capacity (layout : WorkspaceLayout) : Nat :=
  stateCapacity layout.tokenCount layout.workspaceLength

theorem WorkspaceLayout.chart_address_valid
    (layout : WorkspaceLayout) {position field : Nat}
    (positionBound : position ≤ finalPosition layout.tokenCount)
    (fieldBound : field < chartWords) :
    chartWord position field < layout.workspaceLength := by
  exact Nat.lt_of_lt_of_le
    (chartWord_lt_stateBase positionBound fieldBound) layout.baseFits

theorem WorkspaceLayout.state_address_valid
    (layout : WorkspaceLayout) {stateId field : Nat}
    (stateIdBound : stateId < layout.capacity)
    (fieldBound : field < stateWords) :
    stateWord (stateBase layout.tokenCount) stateId field <
      layout.workspaceLength := by
  exact stateWord_lt_workspace layout.baseFits stateIdBound fieldBound

theorem WorkspaceLayout.chart_address_i32
    (layout : WorkspaceLayout) {position field : Nat}
    (positionBound : position ≤ finalPosition layout.tokenCount)
    (fieldBound : field < chartWords) :
    chartWord position field ≤ 2147483647 := by
  exact Nat.le_trans
    (Nat.le_of_lt (layout.chart_address_valid positionBound fieldBound))
    layout.workspaceI32

theorem WorkspaceLayout.state_address_i32
    (layout : WorkspaceLayout) {stateId field : Nat}
    (stateIdBound : stateId < layout.capacity)
    (fieldBound : field < stateWords) :
    stateWord (stateBase layout.tokenCount) stateId field ≤ 2147483647 := by
  exact Nat.le_trans
    (Nat.le_of_lt (layout.state_address_valid stateIdBound fieldBound))
    layout.workspaceI32

end Lanius.Compiler.Parser
