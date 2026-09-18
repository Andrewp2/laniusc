import Lanius.Compiler.Parser.Workspace
import Lanius.Extraction.VerifiedFrontend.Parser.Program

namespace Lanius.Compiler.Parser

open Lanius.Core Lanius.Semantics Lanius.Extraction

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
