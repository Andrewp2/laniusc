module

public import Lanius.Open.F14.PreFrontEndWords.Stmt
public import Lanius.Open.F14.PreBuildFiles.Stmt
public import Lanius.Open.F14.ReadFilesHeight.Stmt
public import Lanius.Open.F14.ValidateFilesHeight.Stmt
public import Lanius.Faithful.SelfPre.Validate

@[expose] public section

open Lanius.Mini
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget
open Lanius.Faithful.SelfPre

/-- `read_counted_files`, `validate_files` and `files_fuel` by the hand
lemmas (`SelfPre/Read`, `SelfPre/Validate`), `build_files` at height `2 ^ 61`
from the files' and trees' heights. -/
theorem Lanius.Open.PreFrontEndWords.red1 (hbf : Lanius.Open.PreBuildFiles)
    (hr : Lanius.Open.ReadFilesHeight) (hv : Lanius.Open.ValidateFilesHeight) :
    Lanius.Open.PreFrontEndWords := by
  intro N W b hW hb
  rcases N with _ | n
  · trivial
  simp only [Pre_front_end_words]
  refine ⟨pre_read_counted_files n W b (by omega), fun b1 _ hb1 => ?_⟩
  cases hrd : readCountedFiles W with
  | none => trivial
  | some r =>
    obtain ⟨hs, ht⟩ := readCountedFiles_ok hrd
    have hrh := hr W r hrd hW
    rcases n with _ | n
    · trivial
    simp only [Pre_front_end_read]
    split
    · rcases n with _ | n
      · trivial
      simp only [Pre_front_end_files]
      refine ⟨pre_validate_files (B := W.length) (by omega) n grammar r.files b1 (by omega) ht,
        fun b2 _ hb2 => ?_⟩
      cases hvf : validateFiles grammar r.files with
      | none => trivial
      | some ts =>
        have := hv r.files ts hvf hrh
        exact ⟨pre_files_fuel n r.files b2 (by omega), hbf n _ ts b2 (2 ^ 61) (by omega) (by omega)⟩
    · trivial
