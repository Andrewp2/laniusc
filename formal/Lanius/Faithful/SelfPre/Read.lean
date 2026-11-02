import Lanius.Faithful.SelfPre.Lex

/-! # Reading the input's files: preconditions (F14)

`read_counted_files` reads counted runs of words; each run it reads is
shorter than the words, so every source it lexes is shorter than the input
(`pre_read_counted_files`, from `pre_lex_source`). -/

namespace Lanius.Faithful.SelfPre

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget

/-! ## What is read is shorter than the words -/

theorem readNums_le : ∀ (ws : List (BitVec 32)) (count : Nat) (r : NumsRead),
    readNums ws count = some r → r.nums.length + r.rest.length ≤ ws.length
  | ws, 0, r, h => by
    unfold readNums at h
    simp only [if_true, Option.some.injEq] at h
    subst h
    simp
  | [], _ + 1, r, h => by unfold readNums at h; simp at h
  | w :: ws, c + 1, r, h => by
    unfold readNums at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    unfold numsAfter at h
    split at h
    · cases h
    · rename_i q e
      simp only [Option.some.injEq] at h
      subst h
      have := readNums_le ws c q e
      simp only [List.length_cons]
      omega

theorem readBytes_le : ∀ (ws : List (BitVec 32)) (count : Nat) (r : NumsRead),
    readBytes ws count = some r → r.nums.length + r.rest.length ≤ ws.length
  | ws, 0, r, h => by
    unfold readBytes at h
    simp only [if_true, Option.some.injEq] at h
    subst h
    simp
  | [], _ + 1, r, h => by unfold readBytes at h; simp at h
  | w :: ws, c + 1, r, h => by
    unfold readBytes at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    unfold byteAfter at h
    split at h
    · cases h
    · unfold numsAfter at h
      split at h
      · cases h
      · rename_i q e
        simp only [Option.some.injEq] at h
        subst h
        have := readBytes_le ws c q e
        simp only [List.length_cons]
        omega

theorem readCountedNums_le {ws : List (BitVec 32)} {r : NumsRead} (h : readCountedNums ws = some r) :
    r.nums.length + r.rest.length < ws.length := by
  unfold readCountedNums at h
  split at h
  · cases h
  · rename_i w rest
    have := readNums_le rest _ r h
    simp only [List.length_cons]
    omega

theorem readCountedBytes_le {ws : List (BitVec 32)} {r : NumsRead} (h : readCountedBytes ws = some r) :
    r.nums.length + r.rest.length < ws.length := by
  unfold readCountedBytes at h
  split at h
  · cases h
  · rename_i w rest
    have := readBytes_le rest _ r h
    simp only [List.length_cons]
    omega

theorem readFile_le {ws : List (BitVec 32)} {f : FileRead} (h : readFile ws = some f) : f.rest.length < ws.length := by
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
        · simp only [Option.some.injEq] at h
          subst h
          simp only
          omega

/-! ## The preconditions -/

theorem pre_read_file (n : Nat) (ws : List (BitVec 32)) (b : Nat) (hw : ws.length < 2 ^ 62) :
    Pre_read_file n ws b := by
  rcases n with _ | n
  · trivial
  simp only [Pre_read_file]
  intro b1 _ _
  split
  · rename_i bs eb
    have h1 := readCountedBytes_le eb
    intro b2 _ _
    rcases n with _ | n
    · trivial
    simp only [Pre_read_file_parents]
    split
    · rename_i p ep
      have h2 := readCountedNums_le ep
      intro b3 _ _
      rcases n with _ | n
      · trivial
      simp only [Pre_read_file_end]
      split
      · exact pre_lex_source n _ b3 (by omega)
      · trivial
    · trivial
  · trivial

theorem pre_read_files : ∀ (n : Nat) (ws : List (BitVec 32)) (count b : Nat), ws.length < 2 ^ 62 →
    Pre_read_files n ws count b
  | 0, _, _, _, _ => trivial
  | n + 1, ws, count, b, hw => by
    simp only [Pre_read_files]
    split
    · trivial
    · refine ⟨pre_read_file n ws b hw, ?_⟩
      intro b1 _ _
      split
      · rename_i f ef
        exact pre_read_files n _ _ b1 (by have := readFile_le ef; omega)
      · trivial

theorem pre_read_counted_files (n : Nat) (ws : List (BitVec 32)) (b : Nat) (hw : ws.length < 2 ^ 62) :
    Pre_read_counted_files n ws b := by
  rcases n with _ | n
  · trivial
  simp only [Pre_read_counted_files]
  split
  · trivial
  · rename_i w rest
    exact pre_read_files n rest _ b (by simp only [List.length_cons] at hw; omega)

#print axioms pre_read_counted_files

end Lanius.Faithful.SelfPre
