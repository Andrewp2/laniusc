module

public import Lanius.Open.F14.PreBinaryWordsV3.Stmt
public import Lanius.Mini.Validate
public import Lanius.Mini.Source
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.compileSource
import all Lanius.Mini.Compiler.P.linkedSize
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.packRound

@[expose] public section

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

set_option linter.unusedSimpArgs false

namespace Lanius.Open.PreBinaryWordsV3

/-- A round packs the bytes it does not leave. -/
theorem packRound_count : ∀ (k : Nat) (xs : List UInt8),
    (packRound xs k).count + (packRound xs k).rest.length = xs.length
  | 0, xs => by rw [packRound.eq_def]; simp
  | k + 1, [] => by rw [packRound.eq_def]; simp [roundEnd]
  | k + 1, [a] => by rw [packRound.eq_def]; simp [roundCons, roundEnd]
  | k + 1, [a, b] => by rw [packRound.eq_def]; simp [roundCons, roundEnd]
  | k + 1, [a, b, c] => by rw [packRound.eq_def]; simp [roundCons, roundEnd]
  | k + 1, a :: b :: c :: d :: rd => by
    have ih := packRound_count k rd
    rw [packRound.eq_def]
    simp only [Nat.add_one_ne_zero, if_false, roundCons, Nat.add_sub_cancel, List.length_cons]
    omega

theorem packRounds_count : ∀ (fuel : Nat) (xs : List UInt8),
    (packRounds xs fuel).count + (packRounds xs fuel).rest.length = xs.length
  | 0, xs => by rw [packRounds.eq_def]; simp only [if_true]; exact packRound_count _ xs
  | fuel + 1, xs => by
    have hr := packRound_count 4096 xs
    rw [packRounds.eq_def]
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel]
    split
    · exact hr
    · rename_i x more heq
      have ih := packRounds_count fuel (packRound xs 4096).rest
      simp only [roundJoin]
      omega

theorem pre_round_cons (n : Nat) (w : BitVec 32) (k : Nat) (r : Round) (b : Nat) (small : r.count + k < 2 ^ 64) :
    Pre_round_cons n w k r b := by
  cases n with
  | zero => simp [Pre_round_cons]
  | succ n => simp only [Pre_round_cons, Pre_plus]; intro _ _ _; exact small

theorem pre_pack_round : ∀ (n : Nat) (xs : List UInt8) (k b : Nat), xs.length < 2 ^ 62 → Pre_pack_round n xs k b
  | 0, _, _, _, _ => by rw [Pre_pack_round.eq_def]; simp
  | n + 1, xs, k, b, small => by
    rw [Pre_pack_round.eq_def]
    dsimp only
    split
    · trivial
    · match xs with
      | [] => trivial
      | [a] => exact pre_round_cons n _ 1 roundEnd b (by simp [roundEnd])
      | [a, c] => exact pre_round_cons n _ 2 roundEnd b (by simp [roundEnd])
      | [a, c, d] => exact pre_round_cons n _ 3 roundEnd b (by simp [roundEnd])
      | a :: c :: d :: e :: rd =>
        simp only [List.length_cons] at small
        refine ⟨pre_pack_round n rd (k - 1) b (by omega), fun b4 _ _ => pre_round_cons n _ 4 _ b4 ?_⟩
        have := packRound_count (k - 1) rd
        omega

theorem pre_pack_rounds : ∀ (n : Nat) (xs : List UInt8) (fuel b : Nat), xs.length < 2 ^ 62 →
    Pre_pack_rounds n xs fuel b
  | 0, _, _, _, _ => by rw [Pre_pack_rounds.eq_def]; simp
  | n + 1, xs, fuel, b, small => by
    rw [Pre_pack_rounds.eq_def]
    dsimp only
    split
    · exact pre_pack_round n xs _ b small
    · refine ⟨pre_pack_round n xs 4096 b small, fun b2 _ _ => ?_⟩
      have hr := packRound_count 4096 xs
      split
      · trivial
      · refine ⟨pre_pack_rounds n _ (fuel - 1) b2 (by omega), fun b3 _ _ => ?_⟩
        cases n with
        | zero => simp [Pre_round_join]
        | succ n =>
          simp only [Pre_round_join, Pre_plus]
          intro _ _ _
          have := packRounds_count (fuel - 1) (packRound xs 4096).rest
          omega

theorem pre_length_of_usize : ∀ (n : Nat) (xs : List Nat) (b : Nat), xs.length < 2 ^ 62 → Pre_length_of_usize n xs b
  | 0, _, _, _ => by simp [Pre_length_of_usize]
  | n + 1, [], _, _ => by simp [Pre_length_of_usize]
  | n + 1, x :: rest, b, small => by
    simp only [List.length_cons] at small
    simp only [Pre_length_of_usize, Pre_plus]
    exact ⟨pre_length_of_usize n rest b (by omega), by omega⟩

theorem codes_length_le : ∀ codes : List Code, 24 * codes.length ≤ linkedSize codes
  | [] => by simp [linkedSize]
  | code :: rest => by
    have := codes_length_le rest
    simp only [linkedSize, Code.size, List.length_cons]
    omega

/-- A binary the compiler returns has an image of at most `2 ^ 30` bytes and at most as many entries. -/
theorem binary_small {p : SrcProgram} {binary : Binary} (compiled : compileSource p = some binary) :
    binary.image.length ≤ imageLimit ∧ binary.entries.length ≤ imageLimit := by
  obtain ⟨-, -, funcs, -, optimized⟩ := compileSource_some compiled
  have prog : ∃ q, compileProgram q = some binary := by
    rcases compileOptimized_some optimized with h | ⟨q, -, h⟩
    · exact ⟨_, h⟩
    · exact ⟨q, h⟩
  obtain ⟨q, hq⟩ := prog
  obtain ⟨-, entries, image, len, -⟩ := compileProgram_spec hq
  have hl := codes_length_le binary.codes
  have hi : linkedSize binary.codes ≤ binary.image.length := by
    rw [image, List.length_append, linkFrom_length]; omega
  refine ⟨len, ?_⟩
  rw [entries, layout_length]
  omega

end Lanius.Open.PreBinaryWordsV3

theorem Lanius.Open.PreBinaryWordsV3.proof : Lanius.Open.PreBinaryWordsV3 := by
  intro p n b
  cases n with
  | zero => simp [Pre_binary_words]
  | succ n =>
    rw [Pre_binary_words.eq_def]
    dsimp only
    cases compiled : compileSource p with
    | none => trivial
    | some binary =>
      obtain ⟨img, ent⟩ := Lanius.Open.PreBinaryWordsV3.binary_small compiled
      simp only [imageLimit] at img ent
      refine ⟨Lanius.Open.PreBinaryWordsV3.pre_pack_rounds n _ _ b (by omega), fun b1 _ _ => ?_⟩
      cases n with
      | zero => simp [Pre_image_words]
      | succ n => exact Lanius.Open.PreBinaryWordsV3.pre_length_of_usize n _ b1 (by omega)
