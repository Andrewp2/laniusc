import Lanius.Faithful.GenB.SelfBModel4

/-! # The lexer's preconditions (F14)

`lex_source`'s `plus` calls add 1, 2 or a token's length to a position in the
source, so none of them reaches `2 ^ 64` when the source is shorter than
`2 ^ 62`. The scans return positions at most the source's length and a few
more (`*_le`); `lx_raw` adds each token's finish to its offset, and its
offset and what is left of the source together stay at most the source's
length (once a token overshoots, nothing is left, and the rest has no
precondition). -/

namespace Lanius.Faithful.SelfPre

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget

/-! ## Lean-level bounds on the scans -/

theorem lxDrop_length : ∀ (l : List Nat) (n : Nat), (lxDrop l n).length = l.length - n
  | l, 0 => by unfold lxDrop; simp
  | [], n + 1 => by simp [lxDrop]
  | _ :: l, n + 1 => by
    simp only [lxDrop, Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel, List.length_cons]
    rw [lxDrop_length l n]
    omega

theorem lxDrop_nil_of {l : List Nat} {n : Nat} (h : l.length ≤ n) : lxDrop l n = [] := by
  have := lxDrop_length l n
  exact List.eq_nil_of_length_eq_zero (by omega)

theorem identRun_le : ∀ l : List Nat, lxIdentRun l ≤ l.length
  | [] => by simp [lxIdentRun]
  | b :: l => by
    have := identRun_le l
    simp only [lxIdentRun, List.length_cons]
    split <;> omega

theorem spaceRun_le : ∀ l : List Nat, lxSpaceRun l ≤ l.length
  | [] => by simp [lxSpaceRun]
  | b :: l => by
    have := spaceRun_le l
    simp only [lxSpaceRun, List.length_cons]
    split <;> omega

theorem lineRun_le : ∀ l : List Nat, lxLineRun l ≤ l.length
  | [] => by simp [lxLineRun]
  | b :: l => by
    have := lineRun_le l
    simp only [lxLineRun, List.length_cons]
    split <;> omega

theorem getElem?_lt {l : List Nat} {i x : Nat} (h : l[i]? = some x) : i < l.length := by
  rcases Nat.lt_or_ge i l.length with lt | ge
  · exact lt
  · rw [List.getElem?_eq_none ge] at h; cases h

theorem digitTail_le (base : Nat) : ∀ (rest : List Nat) (off f : Nat),
    lxDigitTail base rest off = .scanDone f → f ≤ off + rest.length
  | [], off, f, h => by simp only [lxDigitTail, Scan.scanDone.injEq] at h; omega
  | b :: more, off, f, h => by
    unfold lxDigitTail at h
    split at h
    · have := digitTail_le base more (off + 1) f h
      simp only [List.length_cons]; omega
    · split at h
      · split at h
        · cases h
        · rename_i next after
          split at h
          · have := digitTail_le base after (off + 2) f h
            simp only [List.length_cons]; omega
          · cases h
      · simp only [Scan.scanDone.injEq] at h; omega

theorem digitRun_le {s : List Nat} {st base f : Nat} (h : lxDigitRun s st base = .scanDone f) : f ≤ s.length := by
  unfold lxDigitRun at h
  have hl := lxDrop_length s st
  split at h
  · cases h
  · rename_i first rest e
    rw [e, List.length_cons] at hl
    split at h
    · have := digitTail_le base rest (st + 1) f h
      omega
    · cases h

theorem quoted_le (d : Nat) : ∀ (esc : Bool) (rest : List Nat) (off f : Nat),
    lxQuoted d esc rest off = .scanDone f → f ≤ off + rest.length
  | _, [], off, f, h => by simp [lxQuoted] at h
  | esc, b :: more, off, f, h => by
    simp only [lxQuoted] at h
    split at h
    · have := quoted_le d false more (off + 1) f h
      simp only [List.length_cons]; omega
    · split at h
      · cases h
      · split at h
        · simp only [Scan.scanDone.injEq] at h; simp only [List.length_cons]; omega
        · split at h
          · have := quoted_le d true more (off + 1) f h
            simp only [List.length_cons]; omega
          · have := quoted_le d false more (off + 1) f h
            simp only [List.length_cons]; omega

theorem block_le : ∀ (rest : List Nat) (off f : Nat), lxBlock rest off = .scanDone f → f ≤ off + rest.length
  | [], off, f, h => by simp [lxBlock] at h
  | [_], off, f, h => by simp [lxBlock] at h
  | b :: next :: tail, off, f, h => by
    simp only [lxBlock] at h
    split at h
    · simp only [Scan.scanDone.injEq] at h; simp only [List.length_cons]; omega
    · have := block_le (next :: tail) (off + 1) f h
      simp only [List.length_cons] at this ⊢; omega

theorem exponent_le {s : List Nat} {e k f : Nat} (h : lxExponent s e = .numDone k f) : f ≤ s.length := by
  unfold lxExponent at h
  split at h
  · rename_i finish hd
    simp only [NumScan.numDone.injEq] at h
    have := digitRun_le hd
    omega
  · cases h

theorem afterFraction_le {s : List Nat} {fe k f : Nat} (hfe : fe ≤ s.length)
    (h : lxAfterFraction s fe = .numDone k f) : f ≤ s.length := by
  unfold lxAfterFraction at h
  split at h
  · simp only [NumScan.numDone.injEq] at h; omega
  · split at h
    · exact exponent_le h
    · simp only [NumScan.numDone.injEq] at h; omega

theorem fractionDigits_le {s : List Nat} {r : Scan} {k f : Nat}
    (hr : ∀ fe, r = .scanDone fe → fe ≤ s.length) (h : lxFractionDigits s r = .numDone k f) : f ≤ s.length := by
  unfold lxFractionDigits at h
  split at h
  · cases h
  · rename_i fe
    exact afterFraction_le (hr fe rfl) h

theorem fraction_le {s : List Nat} {fs k f : Nat} (hfs : fs ≤ s.length)
    (h : lxFraction s fs = .numDone k f) : f ≤ s.length := by
  unfold lxFraction at h
  split at h
  · simp only [NumScan.numDone.injEq] at h; omega
  · split at h
    · exact fractionDigits_le (fun _ e => digitRun_le e) h
    · split at h
      · exact exponent_le h
      · simp only [NumScan.numDone.injEq] at h; omega

theorem finishDecimal_le {s : List Nat} {ie k f : Nat} (hie : ie ≤ s.length)
    (h : lxFinishDecimal s ie = .numDone k f) : f ≤ s.length := by
  unfold lxFinishDecimal at h
  split at h
  · simp only [NumScan.numDone.injEq] at h; omega
  · rename_i next hn
    have := getElem?_lt hn
    split at h
    · exact exponent_le h
    · split at h
      · simp only [NumScan.numDone.injEq] at h; omega
      · split at h
        · simp only [NumScan.numDone.injEq] at h; omega
        · exact fraction_le (by omega) h

theorem number_le {s : List Nat} {st k f : Nat} (h : lxNumber s st = .numDone k f) : f ≤ s.length := by
  unfold lxNumber at h
  split at h
  · split at h
    · rename_i finish hd
      simp only [NumScan.numDone.injEq] at h
      have := digitRun_le hd
      omega
    · cases h
  · split at h
    · rename_i ie hd
      exact finishDecimal_le (digitRun_le hd) h
    · cases h

theorem leadingDot_le {s : List Nat} {st k f : Nat} (h : lxLeadingDot s st = .numDone k f) : f ≤ s.length :=
  fractionDigits_le (fun _ e => digitRun_le e) h

/-- Every spelling of the rules has at most 3 bytes. -/
def ShortRules (rules : List SymRule) : Prop := ∀ r ∈ rules, r.spelling.length ≤ 3

theorem symbolRules_short : ShortRules lxSymbolRules := by
  intro r hr
  have : lxSymbolRules.all (fun r => decide (r.spelling.length ≤ 3)) = true := by decide +kernel
  exact of_decide_eq_true (List.all_eq_true.mp this r hr)

theorem best_mem : ∀ (rules : List SymRule) (input : List Nat) (r : SymRule), lxBest rules input = some r → r ∈ rules
  | [], _, _, h => by simp [lxBest] at h
  | rule :: more, input, r, h => by
    simp only [lxBest, lxBestAt] at h
    split at h
    · split at h
      · rename_i e
        simp only [Option.some.injEq] at h
        subst h
        exact List.mem_cons_self
      · rename_i current e
        simp only [Option.some.injEq, lxLonger] at h
        split at h
        · subst h; exact List.mem_cons_self
        · subst h; exact List.mem_cons_of_mem _ (best_mem more input current e)
    · exact List.mem_cons_of_mem _ (best_mem more input r h)

/-- **A token ends at most 3 past the source.** -/
theorem oneFirst_le {rules : List SymRule} (short : ShortRules rules) {s : List Nat} {st first : Nat}
    (hst : st < s.length) {t : RawTok} (h : lxOneFirst rules s st first = .oneDone t) :
    t.start = st ∧ t.finish ≤ s.length + 3 := by
  have hd := lxDrop_length s (st + 1)
  have hd2 := lxDrop_length s (st + 2)
  unfold lxOneFirst at h
  split at h
  · simp only [OneTok.oneDone.injEq] at h
    subst h
    refine ⟨rfl, ?_⟩
    have := identRun_le (lxDrop s (st + 1))
    simp only [lxIdentEnd]
    omega
  · split at h
    · unfold lxFromNumber at h
      split at h
      · rename_i k f e
        simp only [OneTok.oneDone.injEq] at h
        subst h
        refine ⟨rfl, ?_⟩
        have := number_le e
        simp only; omega
      · cases h
    · split at h
      · simp only [OneTok.oneDone.injEq] at h
        subst h
        refine ⟨rfl, ?_⟩
        have := spaceRun_le (lxDrop s (st + 1))
        simp only [lxSpaceEnd]
        omega
      · split at h
        · unfold lxDelimited at h
          split at h
          · rename_i f e
            simp only [OneTok.oneDone.injEq] at h
            subst h
            refine ⟨rfl, ?_⟩
            have := quoted_le 34 false _ _ _ e
            simp only; omega
          · cases h
        · split at h
          · unfold lxDelimited at h
            split at h
            · rename_i f e
              simp only [OneTok.oneDone.injEq] at h
              subst h
              refine ⟨rfl, ?_⟩
              have := quoted_le 39 false _ _ _ e
              simp only; omega
            · cases h
          · split at h
            · unfold lxSymbol at h
              split at h
              · cases h
              · rename_i first' _
                have fixed : ∀ t, lxFixed rules s st = .oneDone t → t.start = st ∧ t.finish ≤ s.length + 3 := by
                  intro t h
                  unfold lxFixed at h
                  split at h
                  · cases h
                  · rename_i rule e
                    have := short rule (best_mem _ _ _ e)
                    unfold lxFixedAt at h
                    split at h
                    · simp only [OneTok.oneDone.injEq] at h
                      subst h
                      refine ⟨rfl, ?_⟩
                      have := lineRun_le (lxDrop s (st + 2))
                      simp only [lxLineEnd]
                      omega
                    · split at h
                      · unfold lxDelimited lxBlockEnd at h
                        split at h
                        · rename_i f e'
                          simp only [OneTok.oneDone.injEq] at h
                          subst h
                          refine ⟨rfl, ?_⟩
                          have := block_le _ _ _ e'
                          simp only; omega
                        · cases h
                      · simp only [OneTok.oneDone.injEq] at h
                        subst h
                        refine ⟨rfl, ?_⟩
                        simp only; omega
                unfold lxSymbolAt at h
                split at h
                · split at h
                  · unfold lxDotAt at h
                    split at h
                    · unfold lxFromNumber at h
                      split at h
                      · rename_i k f e
                        simp only [OneTok.oneDone.injEq] at h
                        subst h
                        refine ⟨rfl, ?_⟩
                        have := leadingDot_le e
                        simp only; omega
                      · cases h
                    · exact fixed t h
                  · exact fixed t h
                · exact fixed t h
            · cases h

theorem oneAt_le {rules : List SymRule} (short : ShortRules rules) {s : List Nat} {st : Nat} {t : RawTok}
    (h : lxOneAt rules s st = .oneDone t) : t.start = st ∧ t.finish ≤ s.length + 3 := by
  unfold lxOneAt at h
  split at h
  · cases h
  · rename_i first e
    exact oneFirst_le short (getElem?_lt e) h

/-! ## The preconditions -/

/-- The conditions of the models' `if`s, as propositions. -/
macro "pcond" : tactic => `(tactic| simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq,
  Bool.not_eq_eq_eq_not, Bool.not_true, decide_eq_false_iff_not] at *)

theorem pre_length_of_usize : ∀ (n : Nat) (xs : List Nat) (b : Nat), xs.length < 2 ^ 63 → Pre_length_of_usize n xs b
  | 0, _, _, _ => trivial
  | _ + 1, [], _, _ => by simp only [Pre_length_of_usize]
  | n + 1, _ :: xs, b, h => by
    simp only [Pre_length_of_usize, Pre_plus]
    simp only [List.length_cons] at h
    exact ⟨pre_length_of_usize n xs b (by omega), by omega⟩

theorem pre_lx_ident_run : ∀ (n : Nat) (xs : List Nat) (b : Nat), xs.length < 2 ^ 63 → Pre_lx_ident_run n xs b
  | 0, _, _, _ => trivial
  | _ + 1, [], _, _ => by simp only [Pre_lx_ident_run]
  | 1, _ :: _, _, _ => by simp only [Pre_lx_ident_run, Pre_lx_ident_run_at]
  | n + 2, x :: xs, b, h => by
    simp only [Pre_lx_ident_run, Pre_lx_ident_run_at, Pre_plus]
    simp only [List.length_cons] at h
    have := identRun_le xs
    split
    · exact ⟨pre_lx_ident_run n xs b (by omega), by omega⟩
    · trivial

theorem pre_lx_space_run : ∀ (n : Nat) (xs : List Nat) (b : Nat), xs.length < 2 ^ 63 → Pre_lx_space_run n xs b
  | 0, _, _, _ => trivial
  | _ + 1, [], _, _ => by simp only [Pre_lx_space_run]
  | 1, _ :: _, _, _ => by simp only [Pre_lx_space_run, Pre_lx_space_run_at]
  | n + 2, x :: xs, b, h => by
    simp only [Pre_lx_space_run, Pre_lx_space_run_at, Pre_plus]
    simp only [List.length_cons] at h
    have := spaceRun_le xs
    split
    · exact ⟨pre_lx_space_run n xs b (by omega), by omega⟩
    · trivial

theorem pre_lx_line_run : ∀ (n : Nat) (xs : List Nat) (b : Nat), xs.length < 2 ^ 63 → Pre_lx_line_run n xs b
  | 0, _, _, _ => trivial
  | _ + 1, [], _, _ => by simp only [Pre_lx_line_run]
  | 1, _ :: _, _, _ => by simp only [Pre_lx_line_run, Pre_lx_line_run_at]
  | n + 2, x :: xs, b, h => by
    simp only [Pre_lx_line_run, Pre_lx_line_run_at, Pre_plus]
    simp only [List.length_cons] at h
    have := lineRun_le xs
    split
    · exact ⟨pre_lx_line_run n xs b (by omega), by omega⟩
    · trivial

theorem pre_lx_ident_end (n : Nat) (s : List Nat) (st b : Nat) (hs : s.length < 2 ^ 62) (hst : st < 2 ^ 62) :
    Pre_lx_ident_end n s st b := by
  rcases n with _ | n
  · trivial
  have hd := lxDrop_length s (st + 1)
  have := identRun_le (lxDrop s (st + 1))
  simp only [Pre_lx_ident_end, Pre_plus]
  exact ⟨by omega, by omega, pre_lx_ident_run n _ b (by omega), by omega⟩

theorem pre_lx_space_end (n : Nat) (s : List Nat) (st b : Nat) (hs : s.length < 2 ^ 62) (hst : st < 2 ^ 62) :
    Pre_lx_space_end n s st b := by
  rcases n with _ | n
  · trivial
  have hd := lxDrop_length s (st + 1)
  have := spaceRun_le (lxDrop s (st + 1))
  simp only [Pre_lx_space_end, Pre_plus]
  exact ⟨by omega, by omega, pre_lx_space_run n _ b (by omega), by omega⟩

theorem pre_lx_line_end (n : Nat) (s : List Nat) (st b : Nat) (hs : s.length < 2 ^ 62) (hst : st < 2 ^ 62) :
    Pre_lx_line_end n s st b := by
  rcases n with _ | n
  · trivial
  have hd := lxDrop_length s (st + 2)
  have := lineRun_le (lxDrop s (st + 2))
  simp only [Pre_lx_line_end, Pre_plus]
  exact ⟨by omega, by omega, pre_lx_line_run n _ b (by omega), by omega⟩

theorem pre_lx_quoted : ∀ (n d : Nat) (esc : Bool) (rest : List Nat) (off b : Nat), off + rest.length < 2 ^ 63 →
    Pre_lx_quoted n d esc rest off b
  | 0, _, _, _, _, _, _ => trivial
  | _ + 1, _, _, [], _, _, _ => by simp only [Pre_lx_quoted]
  | 1, _, _, _ :: _, _, _, _ => by simp only [Pre_lx_quoted, Pre_lx_quoted_at]
  | n + 2, d, esc, x :: xs, off, b, h => by
    simp only [Pre_lx_quoted, Pre_lx_quoted_at, Pre_plus]
    simp only [List.length_cons] at h
    split
    · exact ⟨by omega, pre_lx_quoted n d false xs (off + 1) b (by omega)⟩
    · split
      · trivial
      · split
        · omega
        · split
          · exact ⟨by omega, pre_lx_quoted n d true xs (off + 1) b (by omega)⟩
          · exact ⟨by omega, pre_lx_quoted n d false xs (off + 1) b (by omega)⟩

theorem pre_lx_block : ∀ (n : Nat) (rest : List Nat) (off b : Nat), off + rest.length < 2 ^ 63 →
    Pre_lx_block n rest off b
  | 0, _, _, _, _ => trivial
  | _ + 1, [], _, _, _ => by simp only [Pre_lx_block]
  | 1, _ :: _, _, _, _ => by simp only [Pre_lx_block, Pre_lx_block_at]
  | _ + 2, [_], off, _, h => by
    simp only [Pre_lx_block, Pre_lx_block_at, Pre_plus]
    simp only [List.length_cons, List.length_nil] at h
    omega
  | 2, _ :: _ :: _, _, _, _ => by simp only [Pre_lx_block, Pre_lx_block_at, Pre_lx_block_next]
  | n + 3, x :: y :: ys, off, b, h => by
    simp only [Pre_lx_block, Pre_lx_block_at, Pre_lx_block_next, Pre_plus]
    simp only [List.length_cons] at h
    split
    · omega
    · refine ⟨by omega, pre_lx_block n (y :: ys) (off + 1) b ?_⟩
      simp only [List.length_cons]
      omega

theorem pre_lx_block_end (n : Nat) (s : List Nat) (st b : Nat) (hs : s.length < 2 ^ 62) (hst : st < 2 ^ 62) :
    Pre_lx_block_end n s st b := by
  rcases n with _ | n
  · trivial
  have hd := lxDrop_length s (st + 2)
  simp only [Pre_lx_block_end, Pre_plus]
  exact ⟨by omega, by omega, pre_lx_block n _ _ b (by omega)⟩

theorem pre_lx_base_digit (n x base b : Nat) : Pre_lx_base_digit n x base b := by
  rcases n with _ | n
  · trivial
  simp only [Pre_lx_base_digit, Pre_plus]
  split
  · trivial
  · split
    · rename_i h
      pcond
      omega
    · split
      · rename_i h
        pcond
        omega
      · trivial

theorem pre_lx_digit_tail : ∀ (n base : Nat) (rest : List Nat) (off b : Nat), off + rest.length < 2 ^ 63 →
    Pre_lx_digit_tail n base rest off b := by
  intro n
  induction n using Nat.strongRecOn with
  | _ n ih =>
    intro base rest off b h
    match n, rest with
    | 0, _ => trivial
    | _ + 1, [] => simp only [Pre_lx_digit_tail]
    | 1, _ :: _ => simp only [Pre_lx_digit_tail, Pre_lx_digit_tail_at]
    | m + 2, x :: xs =>
      simp only [Pre_lx_digit_tail, Pre_lx_digit_tail_at, Pre_plus]
      simp only [List.length_cons] at h
      refine ⟨pre_lx_base_digit _ _ _ _, ?_⟩
      split
      · exact ⟨by omega, ih m (by omega) base xs (off + 1) b (by omega)⟩
      · split
        · match m, xs with
          | _, [] => simp only [List.length_nil] at h; omega
          | 0, _ :: _ => trivial
          | k + 1, y :: ys =>
            simp only [Pre_lx_digit_sep, Pre_plus]
            simp only [List.length_cons] at h
            refine ⟨pre_lx_base_digit _ _ _ _, ?_⟩
            split
            · exact ⟨by omega, ih k (by omega) base ys (off + 2) b (by omega)⟩
            · omega
        · trivial

theorem pre_lx_digit_run (n : Nat) (s : List Nat) (st base b : Nat) (hs : s.length < 2 ^ 62) :
    Pre_lx_digit_run n s st base b := by
  rcases n with _ | n
  · trivial
  have hd := lxDrop_length s st
  simp only [Pre_lx_digit_run]
  split
  · trivial
  · rename_i x xs e
    rw [e, List.length_cons] at hd
    rcases n with _ | n
    · trivial
    simp only [Pre_lx_digit_run_at, Pre_plus]
    refine ⟨pre_lx_base_digit _ _ _ _, ?_⟩
    split
    · exact ⟨by omega, pre_lx_digit_tail n base xs (st + 1) b (by omega)⟩
    · trivial

theorem pre_lx_exponent_digits (n : Nat) (s : List Nat) (e b : Nat) (he : e < 2 ^ 62) :
    Pre_lx_exponent_digits n s e b := by
  rcases n with _ | n
  · trivial
  simp only [Pre_lx_exponent_digits, Pre_plus]
  refine ⟨by omega, ?_⟩
  split
  · rcases n with _ | n
    · trivial
    simp only [Pre_lx_exponent_sign, Pre_plus]
    split
    · exact ⟨by omega, by omega⟩
    · omega
  · omega

theorem pre_lx_exponent (n : Nat) (s : List Nat) (e b : Nat) (hs : s.length < 2 ^ 62) (he : e < 2 ^ 62) :
    Pre_lx_exponent n s e b := by
  rcases n with _ | n
  · trivial
  simp only [Pre_lx_exponent]
  exact ⟨pre_lx_exponent_digits n s e b he, pre_lx_digit_run n s _ 10 b hs⟩

theorem pre_lx_after_fraction (n : Nat) (s : List Nat) (fe b : Nat) (hs : s.length < 2 ^ 62) :
    Pre_lx_after_fraction n s fe b := by
  rcases n with _ | n
  · trivial
  simp only [Pre_lx_after_fraction]
  split
  · rename_i x e
    have := getElem?_lt e
    rcases n with _ | n
    · trivial
    simp only [Pre_lx_after_fraction_at]
    split
    · exact pre_lx_exponent n s fe b hs (by omega)
    · trivial
  · trivial

theorem pre_lx_fraction_digits (n : Nat) (s : List Nat) (r : Scan) (b : Nat) (hs : s.length < 2 ^ 62) :
    Pre_lx_fraction_digits n s r b := by
  rcases n with _ | n
  · trivial
  simp only [Pre_lx_fraction_digits]
  split
  · exact pre_lx_after_fraction n s _ b hs
  · trivial

theorem pre_lx_fraction (n : Nat) (s : List Nat) (fs b : Nat) (hs : s.length < 2 ^ 62) :
    Pre_lx_fraction n s fs b := by
  rcases n with _ | n
  · trivial
  simp only [Pre_lx_fraction]
  split
  · rename_i x e
    have := getElem?_lt e
    rcases n with _ | n
    · trivial
    simp only [Pre_lx_fraction_at]
    split
    · exact ⟨pre_lx_digit_run n s fs 10 b hs, pre_lx_fraction_digits n s _ b hs⟩
    · split
      · exact pre_lx_exponent n s fs b hs (by omega)
      · trivial
  · trivial

theorem pre_lx_finish_decimal (n : Nat) (s : List Nat) (ie b : Nat) (hs : s.length < 2 ^ 62) :
    Pre_lx_finish_decimal n s ie b := by
  rcases n with _ | n
  · trivial
  simp only [Pre_lx_finish_decimal]
  split
  · rename_i x e
    have := getElem?_lt e
    rcases n with _ | n
    · trivial
    simp only [Pre_lx_decimal_next, Pre_plus]
    split
    · exact pre_lx_exponent n s ie b hs (by omega)
    · split
      · trivial
      · refine ⟨by omega, ?_⟩
        split
        · trivial
        · exact ⟨by omega, pre_lx_fraction n s _ b hs⟩
  · trivial

theorem pre_lx_prefixed_base (n : Nat) (s : List Nat) (st b : Nat) (hst : st < 2 ^ 62) :
    Pre_lx_prefixed_base n s st b := by
  rcases n with _ | n
  · trivial
  simp only [Pre_lx_prefixed_base, Pre_plus]
  split
  · trivial
  · omega

theorem pre_lx_number (n : Nat) (s : List Nat) (st b : Nat) (hs : s.length < 2 ^ 62) (hst : st < 2 ^ 62) :
    Pre_lx_number n s st b := by
  rcases n with _ | n
  · trivial
  simp only [Pre_lx_number, Pre_plus]
  refine ⟨pre_lx_prefixed_base n s st b hst, ?_⟩
  split
  · exact ⟨by omega, pre_lx_digit_run n s _ _ b hs⟩
  · refine ⟨pre_lx_digit_run n s _ _ b hs, ?_⟩
    split
    · exact pre_lx_finish_decimal n s _ b hs
    · trivial

theorem pre_lx_leading_dot (n : Nat) (s : List Nat) (st b : Nat) (hs : s.length < 2 ^ 62) (hst : st < 2 ^ 62) :
    Pre_lx_leading_dot n s st b := by
  rcases n with _ | n
  · trivial
  simp only [Pre_lx_leading_dot, Pre_plus]
  exact ⟨by omega, pre_lx_digit_run n s _ _ b hs, pre_lx_fraction_digits n s _ b hs⟩

theorem pre_lx_best : ∀ (n : Nat) (rules : List SymRule) (input : List Nat) (b : Nat), ShortRules rules →
    Pre_lx_best n rules input b
  | 0, _, _, _, _ => trivial
  | _ + 1, [], _, _, _ => by simp only [Pre_lx_best]
  | n + 1, r :: more, input, b, short => by
    simp only [Pre_lx_best]
    have smore : ShortRules more := fun x hx => short x (List.mem_cons_of_mem _ hx)
    refine ⟨pre_lx_best n more input b smore, ?_⟩
    rcases n with _ | n
    · trivial
    simp only [Pre_lx_best_at]
    split
    · split
      · rename_i cur e
        have h1 := short r List.mem_cons_self
        have h2 := smore cur (best_mem _ _ _ e)
        rcases n with _ | n
        · trivial
        simp only [Pre_lx_longer]
        exact ⟨pre_length_of_usize n _ b (by omega), pre_length_of_usize n _ b (by omega)⟩
      · trivial
    · trivial

theorem pre_lx_fixed (n : Nat) (rules : List SymRule) (s : List Nat) (st b : Nat) (short : ShortRules rules)
    (hs : s.length < 2 ^ 62) (hst : st < 2 ^ 62) : Pre_lx_fixed n rules s st b := by
  rcases n with _ | n
  · trivial
  simp only [Pre_lx_fixed]
  intro b1 _ _
  refine ⟨pre_lx_best n rules _ b1 short, ?_⟩
  split
  · rename_i rule e
    have := short rule (best_mem _ _ _ e)
    rcases n with _ | n
    · trivial
    simp only [Pre_lx_fixed_at, Pre_plus]
    split
    · exact pre_lx_line_end n s st b1 hs hst
    · split
      · exact pre_lx_block_end n s st b1 hs hst
      · exact ⟨pre_length_of_usize n _ b1 (by omega), by omega⟩
  · trivial

theorem pre_lx_symbol (n : Nat) (rules : List SymRule) (s : List Nat) (st b : Nat) (short : ShortRules rules)
    (hs : s.length < 2 ^ 62) (hst : st < 2 ^ 62) : Pre_lx_symbol n rules s st b := by
  rcases n with _ | n
  · trivial
  simp only [Pre_lx_symbol]
  split
  · rcases n with _ | n
    · trivial
    simp only [Pre_lx_symbol_at, Pre_plus]
    have dot : ∀ x, Pre_lx_dot_at n rules s st x b := by
      intro x
      rcases n with _ | n
      · trivial
      simp only [Pre_lx_dot_at]
      split
      · exact pre_lx_leading_dot n s st b hs hst
      · exact pre_lx_fixed n rules s st b short hs hst
    split
    · refine ⟨by omega, ?_⟩
      split
      · exact dot _
      · exact pre_lx_fixed n rules s st b short hs hst
    · exact pre_lx_fixed n rules s st b short hs hst
  · trivial

theorem pre_lx_one_at (n : Nat) (rules : List SymRule) (s : List Nat) (st b : Nat) (short : ShortRules rules)
    (hs : s.length < 2 ^ 62) : Pre_lx_one_at n rules s st b := by
  rcases n with _ | n
  · trivial
  simp only [Pre_lx_one_at]
  split
  · rename_i first e
    have hst := getElem?_lt e
    have hd := lxDrop_length s (st + 1)
    rcases n with _ | n
    · trivial
    simp only [Pre_lx_one_first, Pre_plus]
    split
    · exact pre_lx_ident_end n s st b hs (by omega)
    · split
      · exact pre_lx_number n s st b hs (by omega)
      · split
        · exact pre_lx_space_end n s st b hs (by omega)
        · split
          · exact ⟨by omega, by omega, pre_lx_quoted n _ _ _ _ b (by omega)⟩
          · split
            · exact ⟨by omega, by omega, pre_lx_quoted n _ _ _ _ b (by omega)⟩
            · split
              · exact pre_lx_symbol n rules s st b short hs (by omega)
              · trivial
  · trivial

theorem pre_lx_raw_nil (n : Nat) (rules : List SymRule) (fuel off b : Nat) : Pre_lx_raw n rules [] fuel off b := by
  rcases n with _ | n
  · trivial
  simp only [Pre_lx_raw]
  split <;> trivial

theorem pre_lx_raw : ∀ (n : Nat) (rules : List SymRule) (rest : List Nat) (fuel off b : Nat), ShortRules rules →
    off + rest.length < 2 ^ 62 → Pre_lx_raw n rules rest fuel off b
  | 0, _, _, _, _, _, _, _ => trivial
  | n + 1, rules, rest, fuel, off, b, short, h => by
    simp only [Pre_lx_raw]
    split
    · trivial
    · split
      · trivial
      · rename_i x xs
        simp only [List.length_cons] at h
        refine ⟨pre_lx_one_at n rules _ 0 b short (by simp only [List.length_cons]; omega), ?_⟩
        intro b1 _ _
        split
        · rename_i t e
          obtain ⟨ts, tf⟩ := oneAt_le short e
          simp only [List.length_cons] at tf
          simp only [Pre_plus, Nat.add_sub_cancel_left]
          refine ⟨?_, by omega, by omega, ?_⟩
          · rcases n with _ | n
            · trivial
            simp only [Pre_lx_shift, Pre_plus]
            exact ⟨by omega, by omega⟩
          · rcases Nat.lt_or_ge (x :: xs).length t.finish with over | within
            · rw [lxDrop_nil_of (Nat.le_of_lt over)]
              exact pre_lx_raw_nil n rules _ _ b1
            · refine pre_lx_raw n rules _ _ _ b1 short ?_
              rw [lxDrop_length]
              simp only [List.length_cons] at within ⊢
              omega
        · trivial

theorem pre_lex_source (n : Nat) (s : List Nat) (b : Nat) (hs : s.length < 2 ^ 62) : Pre_lex_source n s b := by
  rcases n with _ | n
  · trivial
  simp only [Pre_lex_source, Pre_plus]
  intro b1 _ _
  exact ⟨pre_length_of_usize n s b1 (by omega), by omega, pre_lx_raw n _ s _ 0 b1 symbolRules_short (by omega)⟩

#print axioms pre_lex_source

end Lanius.Faithful.SelfPre
