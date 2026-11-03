import Lanius.Open.F14.ReadFilesHeight.Stmt
import Lanius.Faithful.SelfPre.Files

/-! # `ReadFilesHeight`: the files read are lower than `2 ^ 40`

Each file `readFile` reads takes at least one word, so the files, with their
tokens, productions and parents, are at most the words (`readFiles_count`,
`readFiles_ok` with the files' count). A list of numbers is as high as it is
long, a token at most as high as the words (it starts inside them and its text
is at most them), so the files are at most three times as high as the words. -/

open Lanius.Mini
open Lanius.Faithful.SelfPre

namespace Lanius.Open.ReadFilesHeight

theorem hb_nats : ∀ l : List Nat, hb l = l.length
  | [] => rfl
  | a :: l => by simp only [hb_cons, hb_nat, Nat.zero_max, List.length_cons, hb_nats l]

theorem hb_tokens (B : Nat) : ∀ ts : List Token, (∀ t ∈ ts, t.start ≤ B ∧ t.text.length ≤ B) →
    hb ts ≤ ts.length + B
  | [], _ => by simp
  | t :: ts, h => by
    have ih := hb_tokens B ts (fun u hu => h u (List.mem_cons_of_mem _ hu))
    have ht := h t List.mem_cons_self
    have : hb t ≤ B := by
      cases t with
      | mk k s x =>
        simp only [hb_Token_mk, hb_nats] at ht ⊢
        omega
    simp only [hb_cons, List.length_cons]
    omega

theorem hb_files_le (B : Nat) : ∀ fs : List FileInput, TokensIn B fs →
    hb fs ≤ fs.length + filesSize fs + B
  | [], _ => by simp
  | f :: fs, h => by
    have ih := hb_files_le B fs (fun g hg => h g (List.mem_cons_of_mem _ hg))
    have hf : hb f ≤ f.tokens.length + f.prods.length + f.parents.length + B := by
      cases f with
      | mk ts ps qs =>
        have := hb_tokens B ts (h _ List.mem_cons_self)
        simp only [hb_FileInput_mk, hb_nats]
        omega
    simp only [hb_cons, List.length_cons, filesSize]
    omega

theorem readFiles_count : ∀ (ws : List (BitVec 32)) (count : Nat) (r : FilesRead), readFiles ws count = some r →
    r.files.length + filesSize r.files + r.rest.length ≤ ws.length
  | ws, 0, r, h => by
    unfold readFiles at h
    simp only [if_true, Option.some.injEq] at h
    subst h
    simp [filesSize]
  | ws, c + 1, r, h => by
    unfold readFiles at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    split at h
    · cases h
    · rename_i f ef
      have hf := (readFile_ok ef).1
      unfold filesAfter at h
      split at h
      · cases h
      · rename_i q eq
        have ih := readFiles_count f.rest c q eq
        simp only [Option.some.injEq] at h
        subst h
        simp only [filesSize, List.length_cons]
        omega

theorem readCountedFiles_count {ws : List (BitVec 32)} {r : FilesRead} (h : readCountedFiles ws = some r) :
    r.files.length + filesSize r.files ≤ ws.length := by
  unfold readCountedFiles at h
  split at h
  · cases h
  · have := readFiles_count _ _ r h
    simp only [List.length_cons]
    omega

end Lanius.Open.ReadFilesHeight

open Lanius.Open.ReadFilesHeight in
theorem Lanius.Open.ReadFilesHeight.proof : Lanius.Open.ReadFilesHeight := by
  intro W r h hW
  have hc := readCountedFiles_count h
  have hb := hb_files_le W.length r.files (readCountedFiles_ok h).2
  omega
