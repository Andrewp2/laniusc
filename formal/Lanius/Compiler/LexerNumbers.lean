import Lanius.Compiler.Lexer
import Lanius.Compiler.Tokens

namespace Lanius.Compiler.Lexer

inductive DigitScanResult where
  | success (endOffset : Nat)
  | failure (errorOffset : Nat)
deriving DecidableEq, Repr

def isDigitForBase (byte : Byte) (base : Nat) : Bool :=
  if 48 ≤ byte.val && byte.val ≤ 57 then byte.val - 48 < base
  else if 97 ≤ byte.val && byte.val ≤ 102 then byte.val - 97 + 10 < base
  else if 65 ≤ byte.val && byte.val ≤ 70 then byte.val - 65 + 10 < base
  else false

theorem isDigitForBase_decimal_iff (byte : Byte) :
    isDigitForBase byte 10 = true ↔ 48 ≤ byte.val ∧ byte.val ≤ 57 := by
  native_decide +revert

@[simp] theorem isDigitForBase_underscore (base : Nat) :
    isDigitForBase ⟨95, by omega⟩ base = false := by
  simp [isDigitForBase]

/-- Continue after a required first digit has already been consumed. An
    underscore commits to a separator, so the byte after it is required. -/
def scanDigitTail (base : Nat) (input : List Byte) (offset : Nat) : DigitScanResult :=
  match input with
  | [] => .success offset
  | byte :: rest =>
      if isDigitForBase byte base then
        scanDigitTail base rest (offset + 1)
      else if byte.val == 95 then
        match rest with
        | [] => .failure (offset + 1)
        | next :: after =>
            if isDigitForBase next base then
              scanDigitTail base after (offset + 2)
            else
              .failure (offset + 1)
      else
        .success offset
termination_by input.length

inductive DigitTailScan (base : Nat) : List Byte → Nat → DigitScanResult → Prop
  | eof (offset) : DigitTailScan base [] offset (.success offset)
  | digit (byte rest offset result)
      (accepted : isDigitForBase byte base = true)
      (tail : DigitTailScan base rest (offset + 1) result) :
      DigitTailScan base (byte :: rest) offset result
  | separator (underscore next after offset result)
      (isSeparator : underscore.val = 95)
      (accepted : isDigitForBase next base = true)
      (tail : DigitTailScan base after (offset + 2) result) :
      DigitTailScan base (underscore :: next :: after) offset result
  | separatorAtEof (underscore offset)
      (isSeparator : underscore.val = 95) :
      DigitTailScan base [underscore] offset (.failure (offset + 1))
  | separatorBeforeInvalid (underscore next after offset)
      (isSeparator : underscore.val = 95)
      (rejected : isDigitForBase next base = false) :
      DigitTailScan base (underscore :: next :: after) offset
        (.failure (offset + 1))
  | boundary (byte rest offset)
      (rejected : isDigitForBase byte base = false)
      (notSeparator : byte.val ≠ 95) :
      DigitTailScan base (byte :: rest) offset (.success offset)

theorem scanDigitTail_spec (base : Nat) (input : List Byte) (offset : Nat) :
    DigitTailScan base input offset (scanDigitTail base input offset) := by
  rw [scanDigitTail.eq_def]
  cases input with
  | nil => exact .eof offset
  | cons byte rest =>
      simp only
      by_cases accepted : isDigitForBase byte base = true
      · rw [if_pos accepted]
        exact .digit byte rest offset _ accepted
          (scanDigitTail_spec base rest (offset + 1))
      · rw [if_neg accepted]
        by_cases separator : byte.val = 95
        · rw [if_pos (beq_iff_eq.mpr separator)]
          cases rest with
          | nil => exact .separatorAtEof byte offset separator
          | cons next after =>
              by_cases nextAccepted : isDigitForBase next base = true
              · simp only [nextAccepted, if_true]
                exact .separator byte next after offset _ separator nextAccepted
                  (scanDigitTail_spec base after (offset + 2))
              · have nextRejected : isDigitForBase next base = false :=
                  by cases value : isDigitForBase next base <;> simp_all
                simp only [nextAccepted]
                exact .separatorBeforeInvalid byte next after offset separator nextRejected
        · have notEqual : ¬(byte.val == 95) = true := by simp [separator]
          rw [if_neg notEqual]
          have rejected : isDigitForBase byte base = false := by
            cases value : isDigitForBase byte base <;> simp_all
          exact .boundary byte rest offset
            rejected separator

theorem DigitTailScan.executes
    {base : Nat} {input : List Byte} {offset : Nat} {result : DigitScanResult}
    (scan : DigitTailScan base input offset result) :
    scanDigitTail base input offset = result := by
  induction scan with
  | eof => rw [scanDigitTail.eq_def]
  | digit byte rest offset result accepted tail inductionHypothesis =>
      rw [scanDigitTail.eq_def]
      simp only [accepted, if_true]
      exact inductionHypothesis
  | separator underscore next after offset result isSeparator accepted tail
      inductionHypothesis =>
      have underscoreRejected : isDigitForBase underscore base = false := by
        simp [isDigitForBase, isSeparator]
      rw [scanDigitTail.eq_def]
      simp [underscoreRejected, isSeparator, accepted, inductionHypothesis]
  | separatorAtEof underscore offset isSeparator =>
      have underscoreRejected : isDigitForBase underscore base = false := by
        simp [isDigitForBase, isSeparator]
      rw [scanDigitTail.eq_def]
      simp [underscoreRejected, isSeparator]
  | separatorBeforeInvalid underscore next after offset isSeparator rejected =>
      have underscoreRejected : isDigitForBase underscore base = false := by
        simp [isDigitForBase, isSeparator]
      rw [scanDigitTail.eq_def]
      simp [underscoreRejected, isSeparator, rejected]
  | boundary byte rest offset rejected notSeparator =>
      rw [scanDigitTail.eq_def]
      simp [rejected, notSeparator]

theorem DigitTailScan.functional
    {base : Nat} {input : List Byte} {offset : Nat} {left right : DigitScanResult}
    (leftScan : DigitTailScan base input offset left)
    (rightScan : DigitTailScan base input offset right) :
    left = right := by
  exact leftScan.executes.symm.trans rightScan.executes

theorem DigitTailScan.result_offset_ge
    {base : Nat} {input : List Byte} {offset : Nat} {result : DigitScanResult}
    (scan : DigitTailScan base input offset result) :
    match result with
    | .success finish => offset ≤ finish
    | .failure error => offset ≤ error := by
  induction scan with
  | eof => omega
  | digit _ _ _ result _ _ inductionHypothesis =>
      cases result <;> simp_all <;> omega
  | separator _ _ _ _ result _ _ _ inductionHypothesis =>
      cases result <;> simp_all <;> omega
  | separatorAtEof => omega
  | separatorBeforeInvalid => omega
  | boundary => omega

theorem DigitTailScan.success_end_ge
    {base : Nat} {input : List Byte} {offset finish : Nat}
    (scan : DigitTailScan base input offset (.success finish)) :
    offset ≤ finish := by
  exact scan.result_offset_ge

def scanDigitRun (source : List Byte) (start base : Nat) : DigitScanResult :=
  match source.drop start with
  | [] => .failure start
  | first :: rest =>
      if isDigitForBase first base then
        scanDigitTail base rest (start + 1)
      else
        .failure start

inductive DigitRunScan
    (source : List Byte) (start base : Nat) : DigitScanResult → Prop
  | missing (empty : source.drop start = []) :
      DigitRunScan source start base (.failure start)
  | invalid (first : Byte) (rest : List Byte)
      (input : source.drop start = first :: rest)
      (rejected : isDigitForBase first base = false) :
      DigitRunScan source start base (.failure start)
  | valid (first : Byte) (rest : List Byte) (result : DigitScanResult)
      (input : source.drop start = first :: rest)
      (accepted : isDigitForBase first base = true)
      (tail : DigitTailScan base rest (start + 1) result) :
      DigitRunScan source start base result

theorem scanDigitRun_spec (source : List Byte) (start base : Nat) :
    DigitRunScan source start base (scanDigitRun source start base) := by
  unfold scanDigitRun
  cases input : source.drop start with
  | nil => exact .missing input
  | cons first rest =>
      by_cases accepted : isDigitForBase first base = true
      · simp only [accepted, if_true]
        exact .valid first rest _ input accepted
          (scanDigitTail_spec base rest (start + 1))
      · simp only [accepted]
        have rejected : isDigitForBase first base = false := by
          cases value : isDigitForBase first base <;> simp_all
        exact .invalid first rest input rejected

theorem DigitRunScan.executes
    {source : List Byte} {start base : Nat} {result : DigitScanResult}
    (scan : DigitRunScan source start base result) :
    scanDigitRun source start base = result := by
  cases scan with
  | missing empty => simp [scanDigitRun, empty]
  | invalid first rest input rejected => simp [scanDigitRun, input, rejected]
  | valid first rest result input accepted tail =>
      simp [scanDigitRun, input, accepted, tail.executes]

theorem DigitRunScan.functional
    {source : List Byte} {start base : Nat} {left right : DigitScanResult}
    (leftScan : DigitRunScan source start base left)
    (rightScan : DigitRunScan source start base right) :
    left = right := by
  exact leftScan.executes.symm.trans rightScan.executes

theorem DigitRunScan.success_end_after_start
    {source : List Byte} {start base finish : Nat}
    (scan : DigitRunScan source start base (.success finish)) :
    start < finish := by
  cases scan with
  | valid _ _ _ _ _ tail =>
      have tailBound := tail.success_end_ge
      omega

theorem scanDigitRun_success_end_after_start
    {source : List Byte} {start base finish : Nat}
    (result : scanDigitRun source start base = .success finish) :
    start < finish := by
  have scan := scanDigitRun_spec source start base
  rw [result] at scan
  exact scan.success_end_after_start

inductive NumberScanResult where
  | success (kind : TokenKind) (endOffset : Nat)
  | failure (errorOffset : Nat)
deriving DecidableEq, Repr

def byteValueAt (source : List Byte) (offset : Nat) : Option Nat :=
  source[offset]?.map Fin.val

def exponentDigitsStart (source : List Byte) (exponentStart : Nat) : Nat :=
  let unsignedStart := exponentStart + 1
  match byteValueAt source unsignedStart with
  | some byte => if byte == 43 || byte == 45 then unsignedStart + 1 else unsignedStart
  | none => unsignedStart

theorem exponentDigitsStart_after_exponent
    (source : List Byte) (exponentStart : Nat) :
    exponentStart < exponentDigitsStart source exponentStart := by
  unfold exponentDigitsStart
  simp only
  split
  · split <;> omega
  · omega

def scanExponent
    (source : List Byte) (exponentStart : Nat) : NumberScanResult :=
  match scanDigitRun source (exponentDigitsStart source exponentStart) 10 with
  | .success finish => .success .float finish
  | .failure error => .failure error

theorem scanExponent_deterministic
    (source : List Byte) (exponentStart : Nat) {left right : NumberScanResult}
    (leftResult : scanExponent source exponentStart = left)
    (rightResult : scanExponent source exponentStart = right) :
    left = right := by
  exact leftResult.symm.trans rightResult

theorem scanExponent_success_end_after_start
    {source : List Byte} {exponentStart finish : Nat}
    (result : scanExponent source exponentStart = .success .float finish) :
    exponentStart < finish := by
  unfold scanExponent at result
  cases digits : scanDigitRun source (exponentDigitsStart source exponentStart) 10 with
  | success digitEnd =>
      simp [digits] at result
      subst digitEnd
      exact Nat.lt_trans (exponentDigitsStart_after_exponent source exponentStart)
        (scanDigitRun_success_end_after_start digits)
  | failure error => simp [digits] at result

theorem scanExponent_any_success_end_after_start
    {source : List Byte} {exponentStart finish : Nat} {kind : TokenKind}
    (result : scanExponent source exponentStart = .success kind finish) :
    exponentStart < finish := by
  unfold scanExponent at result
  cases digits : scanDigitRun source (exponentDigitsStart source exponentStart) 10 with
  | success digitEnd =>
      simp [digits] at result
      rcases result with ⟨_, rfl⟩
      exact Nat.lt_trans (exponentDigitsStart_after_exponent source exponentStart)
        (scanDigitRun_success_end_after_start digits)
  | failure error => simp [digits] at result

def finishDecimal
    (source : List Byte) (integerEnd : Nat) : NumberScanResult :=
  match byteValueAt source integerEnd with
  | none => .success .integer integerEnd
  | some next =>
      if next == 101 || next == 69 then
        scanExponent source integerEnd
      else if next != 46 then
        .success .integer integerEnd
      else if byteValueAt source (integerEnd + 1) == some 46 then
        .success .integer integerEnd
      else
        let fractionStart := integerEnd + 1
        match byteValueAt source fractionStart with
        | some first =>
            if 48 ≤ first && first ≤ 57 then
              match scanDigitRun source fractionStart 10 with
              | .failure error => .failure error
              | .success fractionEnd =>
                  match byteValueAt source fractionEnd with
                  | some exponent =>
                      if exponent == 101 || exponent == 69 then
                        scanExponent source fractionEnd
                      else
                        .success .float fractionEnd
                  | none => .success .float fractionEnd
            else if first == 101 || first == 69 then
              scanExponent source fractionStart
            else
              .success .float fractionStart
        | none => .success .float fractionStart

theorem finishDecimal_deterministic
    (source : List Byte) (integerEnd : Nat) {left right : NumberScanResult}
    (leftResult : finishDecimal source integerEnd = left)
    (rightResult : finishDecimal source integerEnd = right) :
    left = right := by
  exact leftResult.symm.trans rightResult

theorem finishDecimal_success_end_ge
    {source : List Byte} {integerEnd finish : Nat} {kind : TokenKind}
    (result : finishDecimal source integerEnd = .success kind finish) :
    integerEnd ≤ finish := by
  unfold finishDecimal at result
  cases nextAt : byteValueAt source integerEnd with
  | none =>
      simp [nextAt] at result
      omega
  | some next =>
      simp only [nextAt] at result
      by_cases beginsExponent : (next == 101 || next == 69) = true
      · simp only [beginsExponent, if_true] at result
        exact Nat.le_of_lt (scanExponent_any_success_end_after_start result)
      · simp only [beginsExponent] at result
        by_cases isDot : next = 46
        · have notNotDot : (next != 46) = false := by simp [isDot]
          simp only [notNotDot] at result
          by_cases beginsRange : byteValueAt source (integerEnd + 1) = some 46
          · simp [beginsRange] at result
            omega
          · have notRange : (byteValueAt source (integerEnd + 1) == some 46) = false := by
              simp [beginsRange]
            simp only [notRange] at result
            cases firstAt : byteValueAt source (integerEnd + 1) with
            | none =>
                simp [firstAt] at result
                omega
            | some first =>
                simp only [firstAt] at result
                by_cases isDigit : (48 ≤ first && first ≤ 57) = true
                · simp only [isDigit, if_true] at result
                  cases fraction : scanDigitRun source (integerEnd + 1) 10 with
                  | failure error => simp [fraction] at result
                  | success fractionEnd =>
                      have fractionAdvances :=
                        scanDigitRun_success_end_after_start fraction
                      simp only [fraction] at result
                      cases exponentAt : byteValueAt source fractionEnd with
                      | none =>
                          simp [exponentAt] at result
                          omega
                      | some exponent =>
                          simp only [exponentAt] at result
                          by_cases hasExponent :
                              (exponent == 101 || exponent == 69) = true
                          · simp only [hasExponent, if_true] at result
                            have exponentAdvances :=
                              scanExponent_any_success_end_after_start result
                            omega
                          · simp [hasExponent] at result
                            omega
                · simp only [isDigit] at result
                  by_cases hasExponent : (first == 101 || first == 69) = true
                  · simp only [hasExponent, if_true] at result
                    have exponentAdvances :=
                      scanExponent_any_success_end_after_start result
                    omega
                  · simp [hasExponent] at result
                    omega
        · have notDot : (next != 46) = true := by simp [isDot]
          simp [notDot] at result
          omega

def prefixedBase (source : List Byte) (start : Nat) : Option Nat :=
  if byteValueAt source start != some 48 then none
  else
    match byteValueAt source (start + 1) with
    | some prefixByte =>
        if prefixByte == 120 || prefixByte == 88 then some 16
        else if prefixByte == 98 || prefixByte == 66 then some 2
        else if prefixByte == 111 || prefixByte == 79 then some 8
        else none
    | none => none

theorem prefixedBase_supported
    (source : List Byte) (start base : Nat)
    (selected : prefixedBase source start = some base) :
    base = 2 ∨ base = 8 ∨ base = 16 := by
  unfold prefixedBase at selected
  split at selected <;> simp_all
  split at selected
  · split at selected <;> simp_all
    split at selected <;> simp_all
  · simp at selected

def scanNumber (source : List Byte) (start : Nat) : NumberScanResult :=
  match prefixedBase source start with
  | some base =>
      match scanDigitRun source (start + 2) base with
      | .success finish => .success .integer finish
      | .failure error => .failure error
  | none =>
      match scanDigitRun source start 10 with
      | .success integerEnd => finishDecimal source integerEnd
      | .failure error => .failure error

theorem scanNumber_deterministic
    (source : List Byte) (start : Nat) {left right : NumberScanResult}
    (leftResult : scanNumber source start = left)
    (rightResult : scanNumber source start = right) :
    left = right := by
  exact leftResult.symm.trans rightResult

theorem scanNumber_success_end_after_start
    {source : List Byte} {start finish : Nat} {kind : TokenKind}
    (result : scanNumber source start = .success kind finish) :
    start < finish := by
  unfold scanNumber at result
  cases selectedBase : prefixedBase source start with
  | some base =>
      simp only [selectedBase] at result
      cases digits : scanDigitRun source (start + 2) base with
      | failure error => simp [digits] at result
      | success digitEnd =>
          simp [digits] at result
          rcases result with ⟨_, rfl⟩
          have digitsAdvance := scanDigitRun_success_end_after_start digits
          omega
  | none =>
      simp only [selectedBase] at result
      cases integer : scanDigitRun source start 10 with
      | failure error => simp [integer] at result
      | success integerEnd =>
          simp only [integer] at result
          have integerAdvances := scanDigitRun_success_end_after_start integer
          have finishBound := finishDecimal_success_end_ge result
          omega

def scanLeadingDotNumber
    (source : List Byte) (start : Nat) : NumberScanResult :=
  match scanDigitRun source (start + 1) 10 with
  | .failure error => .failure error
  | .success fractionEnd =>
      match byteValueAt source fractionEnd with
      | some exponent =>
          if exponent == 101 || exponent == 69 then
            scanExponent source fractionEnd
          else
            .success .float fractionEnd
      | none => .success .float fractionEnd

theorem scanLeadingDotNumber_deterministic
    (source : List Byte) (start : Nat) {left right : NumberScanResult}
    (leftResult : scanLeadingDotNumber source start = left)
    (rightResult : scanLeadingDotNumber source start = right) :
    left = right := by
  exact leftResult.symm.trans rightResult

theorem scanLeadingDotNumber_success_end_after_start
    {source : List Byte} {start finish : Nat} {kind : TokenKind}
    (result : scanLeadingDotNumber source start = .success kind finish) :
    start < finish := by
  unfold scanLeadingDotNumber at result
  cases fraction : scanDigitRun source (start + 1) 10 with
  | failure error => simp [fraction] at result
  | success fractionEnd =>
      have fractionAdvances := scanDigitRun_success_end_after_start fraction
      simp only [fraction] at result
      cases exponentAt : byteValueAt source fractionEnd with
      | none =>
          simp [exponentAt] at result
          omega
      | some exponent =>
          simp only [exponentAt] at result
          by_cases hasExponent : (exponent == 101 || exponent == 69) = true
          · simp only [hasExponent, if_true] at result
            have exponentAdvances := scanExponent_any_success_end_after_start result
            omega
          · simp [hasExponent] at result
            omega

theorem scanNumber_decimal_fraction_exponent :
    scanNumber ([49, 50, 46, 51, 52, 101, 43, 53, 95, 54, 32, 120] : List Byte) 0 =
      .success .float 10 := by
  native_decide

theorem scanNumber_stops_before_range :
    scanNumber ([49, 50, 46, 46, 51, 52] : List Byte) 0 =
      .success .integer 2 := by
  native_decide

theorem scanNumber_requires_prefixed_digit :
    scanNumber ([48, 120] : List Byte) 0 = .failure 2 := by
  native_decide

theorem scanNumber_reports_missing_exponent_digit :
    scanNumber ([49, 101, 43] : List Byte) 0 = .failure 3 := by
  native_decide

theorem scanLeadingDotNumber_decimal :
    scanLeadingDotNumber ([46, 53] : List Byte) 0 = .success .float 2 := by
  native_decide

end Lanius.Compiler.Lexer
