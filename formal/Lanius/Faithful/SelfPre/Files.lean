module

public import Lanius.Faithful.SelfPre.Read
import all Lanius.Machines.SqliteStatement.P.start
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Frontend.P.lxCanonicalKind
import all Lanius.Mini.Frontend.P.lxDotAt
import all Lanius.Mini.Frontend.P.lxSymbolStart
import all Lanius.Mini.Frontend.P.readCountedBytes

@[expose] public section

/-! # The files read: their sizes (F14)

What `read_counted_files` reads is no bigger than the words it reads: the
files' tokens, productions and parents together are at most the words
(`readCountedFiles_ok`), each token starts inside its source, and its text
is at most the source. A file's tokens are at most its bytes and one more:
`lx_raw` makes at most one token a step, and its fuel is the source's length
and one more. -/

namespace Lanius.Faithful.SelfPre

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget

/-! ## The lexer's tokens -/

theorem lxTake_length_le : ∀ (l : List Nat) (n : Nat), (lxTake l n).length ≤ l.length
  | l, 0 => by unfold lxTake; simp
  | [], n + 1 => by unfold lxTake; simp
  | _ :: l, n + 1 => by
    unfold lxTake
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel, List.length_cons]
    have := lxTake_length_le l n
    omega

theorem lxRaw_nil {rules : List SymRule} {fuel off : Nat} {raws : List RawTok}
    (h : lxRaw rules [] fuel off = some raws) : raws = [] := by
  unfold lxRaw at h
  split at h
  · cases h
  · simp only [Option.some.injEq] at h
    exact h.symm

theorem lxRaw_ok {rules : List SymRule} (short : ShortRules rules) (L : Nat) :
    ∀ (fuel : Nat) (rest : List Nat) (off : Nat) (raws : List RawTok), off + rest.length ≤ L →
      lxRaw rules rest fuel off = some raws → raws.length ≤ fuel ∧ ∀ t ∈ raws, t.start < L
  | 0, _, _, _, _, h => by unfold lxRaw at h; simp at h
  | fuel + 1, rest, off, raws, hl, h => by
    unfold lxRaw at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    split at h
    · simp only [Option.some.injEq] at h
      subst h
      simp
    · rename_i x xs
      simp only [List.length_cons] at hl
      split at h
      · cases h
      · rename_i t e
        obtain ⟨ts, tf⟩ := oneAt_le short e
        unfold lxPrepend at h
        split at h
        · cases h
        · rename_i raws' e'
          simp only [Option.some.injEq] at h
          subst h
          have rest' : raws'.length ≤ fuel ∧ ∀ u ∈ raws', u.start < L := by
            rw [Nat.add_sub_cancel_left] at e'
            rcases Nat.lt_or_ge (x :: xs).length t.finish with over | within
            · rw [lxDrop_nil_of (Nat.le_of_lt over)] at e'
              rw [lxRaw_nil e']
              simp
            · refine lxRaw_ok short L fuel _ _ raws' ?_ e'
              rw [lxDrop_length]
              simp only [List.length_cons] at within ⊢
              omega
          refine ⟨by simp only [List.length_cons]; omega, ?_⟩
          intro u hu
          simp only [List.mem_cons] at hu
          rcases hu with rfl | hu
          · simp only [lxShift, ts]
            omega
          · exact rest'.2 u hu

theorem lxFilter_ok (keywords : List SymRule) (source : List Nat) (L : Nat) :
    ∀ (raws : List RawTok) (rest : List Nat) (pos : Nat), (∀ t ∈ raws, t.start < L) →
      (lxFilter keywords source rest pos raws).length ≤ raws.length ∧
        ∀ t ∈ lxFilter keywords source rest pos raws, t.start < L
  | [], _, _, _ => by simp [lxFilter]
  | t :: more, rest, pos, h => by
    have ih := lxFilter_ok keywords source L more (lxDropTo source rest pos t.start) t.start
      (fun u hu => h u (List.mem_cons_of_mem _ hu))
    have ht := h t List.mem_cons_self
    unfold lxFilter
    split
    · simp only [List.length_cons]
      exact ⟨by omega, ih.2⟩
    · simp only [List.length_cons, List.mem_cons]
      refine ⟨by omega, ?_⟩
      intro u hu
      rcases hu with rfl | hu
      · exact ht
      · exact ih.2 u hu

theorem lxRanges_ok (L : Nat) : ∀ (raws : List RawTok), (∀ t ∈ raws, t.start < L) →
    (lxRanges raws).length ≤ raws.length ∧ ∀ t ∈ lxRanges raws, t.start < L
  | [], _ => by simp [lxRanges]
  | [t], h => by simp only [lxRanges]; exact ⟨Nat.le_refl _, h⟩
  | t :: next :: rest, h => by
    have ih := lxRanges_ok L (next :: rest) (fun u hu => h u (List.mem_cons_of_mem _ hu))
    have ht := h t List.mem_cons_self
    simp only [lxRanges] at ih ⊢
    simp only [List.length_cons, List.mem_cons] at ih ⊢
    refine ⟨by omega, ?_⟩
    intro u hu
    rcases hu with rfl | hu
    · unfold lxRangePair
      split
      · exact ht
      · exact ht
    · exact ih.2 u hu

theorem lxDropTo_length (source rest : List Nat) (pos target : Nat) (h : rest.length ≤ source.length) :
    (lxDropTo source rest pos target).length ≤ source.length := by
  unfold lxDropTo
  split
  · rw [lxDrop_length]; omega
  · rw [lxDrop_length]; omega

theorem lxTokens_ok (source : List Nat) (L : Nat) :
    ∀ (raws : List RawTok) (rest : List Nat) (pos : Nat), rest.length ≤ source.length → (∀ t ∈ raws, t.start < L) →
      (lxTokens source rest pos raws).length = raws.length ∧
        ∀ t ∈ lxTokens source rest pos raws, t.start < L ∧ t.text.length ≤ source.length
  | [], _, _, _, _ => by simp [lxTokens]
  | t :: more, rest, pos, hr, h => by
    have hd := lxDropTo_length source rest pos t.start hr
    have ih := lxTokens_ok source L more (lxDropTo source rest pos t.start) t.start hd
      (fun u hu => h u (List.mem_cons_of_mem _ hu))
    have ht := h t List.mem_cons_self
    unfold lxTokens
    simp only [List.length_cons, List.mem_cons]
    refine ⟨by omega, ?_⟩
    intro u hu
    rcases hu with rfl | hu
    · have := lxTake_length_le (lxDropTo source rest pos t.start) (t.finish - t.start)
      unfold lxToken lxTokenText
      split
      · simp only; omega
      · simp only; omega
    · exact ih.2 u hu

/-- **A file's tokens are at most its bytes and one more; each starts inside the
source, and its text is at most the source.** -/
theorem lexSource_ok {s : List Nat} {ts : List Token} (h : lexSource s = some ts) :
    ts.length ≤ s.length + 1 ∧ ∀ t ∈ ts, t.start < s.length ∧ t.text.length ≤ s.length := by
  unfold lexSource at h
  split at h
  · cases h
  · rename_i raw e
    simp only [Option.some.injEq] at h
    subst h
    have r := lxRaw_ok symbolRules_short s.length _ s 0 raw (by omega) e
    have f := lxFilter_ok lxKeywordRules s s.length raw s 0 r.2
    have g := lxRanges_ok s.length _ f.2
    have k := lxTokens_ok s s.length _ s 0 (Nat.le_refl _) g.2
    exact ⟨by omega, k.2⟩

/-! ## The files -/

/-- The tokens, productions and parents of the files, together. -/
def filesSize : List FileInput → Nat
  | [] => 0
  | f :: fs => f.tokens.length + f.prods.length + f.parents.length + filesSize fs

/-- Every token of the files starts at most at `B`, and its text is at most `B`. -/
def TokensIn (B : Nat) (fs : List FileInput) : Prop :=
  ∀ f ∈ fs, ∀ t ∈ f.tokens, t.start ≤ B ∧ t.text.length ≤ B

theorem readFile_ok {ws : List (BitVec 32)} {f : FileRead} (h : readFile ws = some f) :
    f.file.tokens.length + f.file.prods.length + f.file.parents.length + f.rest.length < ws.length ∧
      ∀ t ∈ f.file.tokens, t.start ≤ ws.length ∧ t.text.length ≤ ws.length := by
  unfold readFile at h
  split at h
  · cases h
  · rename_i bs eb
    have h1 := readCountedBytes_le eb
    unfold readFileParents at h
    split at h
    · cases h
    · rename_i p ep
      have h2 := readCountedNums_le ep
      unfold readFileEnd at h
      split at h
      · cases h
      · rename_i q eq
        have h3 := readCountedNums_le eq
        unfold fileLexed at h
        split at h
        · cases h
        · rename_i ts et
          have lx := lexSource_ok et
          simp only [Option.some.injEq] at h
          subst h
          simp only
          refine ⟨by omega, fun t ht => ?_⟩
          have := lx.2 t ht
          omega

theorem readFiles_ok : ∀ (ws : List (BitVec 32)) (count : Nat) (r : FilesRead), readFiles ws count = some r →
    filesSize r.files + r.rest.length ≤ ws.length ∧ TokensIn ws.length r.files
  | ws, 0, r, h => by
    unfold readFiles at h
    simp only [if_true, Option.some.injEq] at h
    subst h
    simp [filesSize, TokensIn]
  | ws, c + 1, r, h => by
    unfold readFiles at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    split at h
    · cases h
    · rename_i f ef
      have hf := readFile_ok ef
      unfold filesAfter at h
      split at h
      · cases h
      · rename_i q eq
        have ih := readFiles_ok f.rest c q eq
        simp only [Option.some.injEq] at h
        subst h
        simp only [filesSize]
        refine ⟨by omega, ?_⟩
        intro g hg t ht
        simp only [List.mem_cons] at hg
        rcases hg with rfl | hg
        · exact hf.2 t ht
        · have := ih.2 g hg t ht
          omega

/-- **What `read_counted_files` reads is no bigger than the words.** -/
theorem readCountedFiles_ok {ws : List (BitVec 32)} {r : FilesRead} (h : readCountedFiles ws = some r) :
    filesSize r.files ≤ ws.length ∧ TokensIn ws.length r.files := by
  unfold readCountedFiles at h
  split at h
  · cases h
  · rename_i w rest
    have := readFiles_ok rest _ r h
    simp only [List.length_cons]
    refine ⟨by omega, fun f hf t ht => ?_⟩
    have := this.2 f hf t ht
    omega

#print axioms readCountedFiles_ok

end Lanius.Faithful.SelfPre
