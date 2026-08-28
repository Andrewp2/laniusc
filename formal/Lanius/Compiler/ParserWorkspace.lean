import Lanius.Extraction.VerifiedParserProgram

namespace Lanius.Compiler.Parser

open Lanius.Core
open Lanius.Semantics
open Lanius.Extraction

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

theorem WorkspaceLayout.chart_value_eq_address
    (layout : WorkspaceLayout) {position field : Nat}
    (positionBound : position ≤ finalPosition layout.tokenCount)
    (fieldBound : field < chartWords) :
    parserChartWordValue verifiedParserCore.target
        (Int.ofNat position) (Int.ofNat field) =
      Int.ofNat (chartWord position field) := by
  have addressBound := layout.chart_address_i32 positionBound fieldBound
  have productBound : position * chartWords ≤ 2147483647 := by
    have beforeAddress : position * chartWords ≤ chartWord position field := by
      simp only [chartWord]
      omega
    exact Nat.le_trans beforeAddress addressBound
  have productWrap := wrapSigned_i32_ofNat verifiedParserCore.target
    (position * chartWords) productBound
  have addressWrap := wrapSigned_i32_ofNat verifiedParserCore.target
    (chartWord position field) addressBound
  rw [parserChartWordValue]
  have productCast : Int.ofNat position * 2 =
      Int.ofNat (position * chartWords) := by
    simp [chartWords]
  rw [productCast, productWrap]
  have addressCast : Int.ofNat (position * chartWords) + Int.ofNat field =
      Int.ofNat (chartWord position field) := by
    simp [chartWord]
  rw [addressCast, addressWrap]

theorem WorkspaceLayout.state_value_eq_address
    (layout : WorkspaceLayout) {stateId field : Nat}
    (stateIdBound : stateId < layout.capacity)
    (fieldBound : field < stateWords) :
    parserStateWordValue verifiedParserCore.target
        (Int.ofNat (stateBase layout.tokenCount))
        (Int.ofNat stateId) (Int.ofNat field) =
      Int.ofNat
        (stateWord (stateBase layout.tokenCount) stateId field) := by
  have addressBound := layout.state_address_i32 stateIdBound fieldBound
  have productBound : stateId * stateWords ≤ 2147483647 := by
    have beforeAddress : stateId * stateWords ≤
        stateWord (stateBase layout.tokenCount) stateId field := by
      simp only [stateWord]
      omega
    exact Nat.le_trans beforeAddress addressBound
  have baseProductBound :
      stateBase layout.tokenCount + stateId * stateWords ≤
        2147483647 := by
    have beforeAddress :
        stateBase layout.tokenCount + stateId * stateWords ≤
          stateWord (stateBase layout.tokenCount) stateId field := by
      simp only [stateWord]
      omega
    exact Nat.le_trans beforeAddress addressBound
  have productWrap := wrapSigned_i32_ofNat verifiedParserCore.target
    (stateId * stateWords) productBound
  have baseProductWrap := wrapSigned_i32_ofNat verifiedParserCore.target
    (stateBase layout.tokenCount + stateId * stateWords) baseProductBound
  have addressWrap := wrapSigned_i32_ofNat verifiedParserCore.target
    (stateWord (stateBase layout.tokenCount) stateId field) addressBound
  rw [parserStateWordValue]
  have productCast : Int.ofNat stateId * 9 =
      Int.ofNat (stateId * stateWords) := by
    simp [stateWords]
  rw [productCast, productWrap]
  have baseProductCast :
      Int.ofNat (stateBase layout.tokenCount) +
          Int.ofNat (stateId * stateWords) =
        Int.ofNat
          (stateBase layout.tokenCount + stateId * stateWords) := by
    simp
  rw [baseProductCast, baseProductWrap]
  have addressCast :
      Int.ofNat (stateBase layout.tokenCount + stateId * stateWords) +
          Int.ofNat field =
        Int.ofNat
          (stateWord (stateBase layout.tokenCount) stateId field) := by
    simp [stateWord]
  rw [addressCast, addressWrap]

theorem WorkspaceLayout.extracted_chart_word_executes
    (layout : WorkspaceLayout) (state : State) {position field : Nat}
    (positionBound : position ≤ finalPosition layout.tokenCount)
    (fieldBound : field < chartWords)
    (positionLocal : state.local? 0 =
      some (.signed .i32 (Int.ofNat position)))
    (fieldLocal : state.local? 1 =
      some (.signed .i32 (Int.ofNat field))) :
    Executes verifiedParserCore state extractedParserChartWordBody
      (.returned (some (.signed .i32
        (Int.ofNat (chartWord position field))))) state := by
  have result := extractedParserChartWordBody_executes state
    (Int.ofNat position) (Int.ofNat field) positionLocal fieldLocal
  rw [layout.chart_value_eq_address positionBound fieldBound] at result
  exact result

theorem WorkspaceLayout.extracted_state_word_executes
    (layout : WorkspaceLayout) (state : State) {stateId field : Nat}
    (stateIdBound : stateId < layout.capacity)
    (fieldBound : field < stateWords)
    (baseLocal : state.local? 0 = some (.signed .i32
      (Int.ofNat (stateBase layout.tokenCount))))
    (stateIdLocal : state.local? 1 =
      some (.signed .i32 (Int.ofNat stateId)))
    (fieldLocal : state.local? 2 =
      some (.signed .i32 (Int.ofNat field))) :
    Executes verifiedParserCore state extractedParserStateWordBody
      (.returned (some (.signed .i32 (Int.ofNat
        (stateWord (stateBase layout.tokenCount) stateId field))))) state := by
  have result := extractedParserStateWordBody_executes state
    (Int.ofNat (stateBase layout.tokenCount))
    (Int.ofNat stateId) (Int.ofNat field)
    baseLocal stateIdLocal fieldLocal
  rw [layout.state_value_eq_address stateIdBound fieldBound] at result
  exact result

end Lanius.Compiler.Parser
