import Lanius.Mini.TextCorrect
import Lanius.Mini.LexCorrect

/-! # The driver's words are source files (roadmap step V5)

The self program's entry reads its input as 32-bit words (`frontEndWords`):
the file count, then each file's bytes, productions and parents, each a
count and then the values (`filesWords`). It lexes each file with the
extracted lexer, which is `lexTokens` (`lexSource_eq`, V3). So on the words of
files it is the several-file front end (`frontEndWords_files`), and any words
it accepts are the words of files whose numbers fit (`frontEndWords_some`).
With `compileWords`, the self program's function from input to output words
is `compileText` (`compileWords_files`, `compileWords_some`). -/

namespace Lanius.Mini

open Lanius.Compiler.Lexer (Byte)

/-- A count, then the numbers, one word each. -/
def countedWords (ns : List Nat) : List (BitVec 32) :=
  BitVec.ofNat 32 ns.length :: ns.map (BitVec.ofNat 32)

/-- A file's words: its counted bytes, productions and parents. -/
def fileWords (f : SourceFile) : List (BitVec 32) :=
  countedWords (vals f.source) ++ countedWords f.prods ++ countedWords f.parents

/-- The driver's input for these files. -/
def filesWords (files : List SourceFile) : List (BitVec 32) :=
  BitVec.ofNat 32 files.length :: files.flatMap fileWords

/-- A list's count and numbers fit in words. -/
def NumsFit (ns : List Nat) : Prop := ns.length < 2 ^ 32 ∧ ∀ n ∈ ns, n < 2 ^ 32

/-- A file's counts and numbers fit in words. -/
def FileFits (f : SourceFile) : Prop := f.source.length < 2 ^ 32 ∧ NumsFit f.prods ∧ NumsFit f.parents

/-- The files' counts and numbers fit in words. -/
def FilesFit (files : List SourceFile) : Prop := files.length < 2 ^ 32 ∧ ∀ f ∈ files, FileFits f

theorem wordNum_ofNat {n : Nat} (h : n < 2 ^ 32) : wordNum (BitVec.ofNat 32 n) = n := by
  simp [wordNum, Nat.mod_eq_of_lt h]

theorem ofNat_wordNum (w : BitVec 32) : BitVec.ofNat 32 (wordNum w) = w := by
  apply BitVec.eq_of_toNat_eq
  simp [wordNum]

theorem wordNum_lt (w : BitVec 32) : wordNum w < 2 ^ 32 := w.isLt

/-! ## Reading the words of files -/

theorem readNums_words : ∀ (ns : List Nat) (rest : List (BitVec 32)), (∀ n ∈ ns, n < 2 ^ 32) →
    readNums (ns.map (BitVec.ofNat 32) ++ rest) ns.length = some { nums := ns, rest := rest }
  | [], rest, _ => by unfold readNums; simp
  | n :: ns, rest, h => by
    unfold readNums
    simp only [List.length_cons, Nat.add_one_ne_zero, if_false, List.map_cons, List.cons_append,
      Nat.add_sub_cancel]
    rw [readNums_words ns rest (fun m hm => h m (by simp [hm])), wordNum_ofNat (h n (by simp))]
    rfl

theorem readCountedNums_words {ns : List Nat} (rest : List (BitVec 32)) (fit : NumsFit ns) :
    readCountedNums (countedWords ns ++ rest) = some { nums := ns, rest := rest } := by
  simp only [countedWords, List.cons_append, readCountedNums, wordNum_ofNat fit.1]
  exact readNums_words ns rest fit.2

theorem readBytes_words : ∀ (ns : List Nat) (rest : List (BitVec 32)), (∀ n ∈ ns, n < 256) →
    readBytes (ns.map (BitVec.ofNat 32) ++ rest) ns.length = some { nums := ns, rest := rest }
  | [], rest, _ => by unfold readBytes; simp
  | n :: ns, rest, h => by
    have hn := h n (by simp)
    unfold readBytes
    simp only [List.length_cons, Nat.add_one_ne_zero, if_false, List.map_cons, List.cons_append,
      Nat.add_sub_cancel]
    rw [readBytes_words ns rest (fun m hm => h m (by simp [hm])), wordNum_ofNat (by omega)]
    simp only [byteAfter, show ¬255 < n by omega, if_false]
    rfl

theorem vals_lt (source : List Byte) : ∀ n ∈ vals source, n < 256 := by
  intro n hn
  obtain ⟨b, -, rfl⟩ := List.mem_map.1 hn
  exact b.isLt

theorem readCountedBytes_words {source : List Byte} (rest : List (BitVec 32)) (fit : source.length < 2 ^ 32) :
    readCountedBytes (countedWords (vals source) ++ rest) = some { nums := vals source, rest := rest } := by
  simp only [countedWords, List.cons_append, readCountedBytes]
  rw [wordNum_ofNat (by simpa using fit)]
  exact readBytes_words (vals source) rest (vals_lt source)

theorem readFile_words {f : SourceFile} (rest : List (BitVec 32)) (fit : FileFits f) :
    readFile (fileWords f ++ rest) =
      match lexTokens f.source with
      | some tokens => some { file := { tokens := tokens, prods := f.prods, parents := f.parents }, rest := rest }
      | none => none := by
  simp only [fileWords, List.append_assoc, readFile]
  rw [readCountedBytes_words _ fit.1]
  simp only [readFileParents]
  rw [readCountedNums_words _ fit.2.1]
  simp only [readFileEnd]
  rw [readCountedNums_words _ fit.2.2]
  simp only [fileLexed, lexSource_eq]
  cases lexTokens f.source with
  | some tokens => rfl
  | none => rfl

theorem readFiles_words : ∀ (files : List SourceFile) (rest : List (BitVec 32)), (∀ f ∈ files, FileFits f) →
    readFiles (files.flatMap fileWords ++ rest) files.length =
      match lexFiles files with
      | some inputs => some { files := inputs, rest := rest }
      | none => none
  | [], rest, _ => by unfold readFiles; simp [lexFiles]
  | f :: more, rest, fit => by
    unfold readFiles
    simp only [List.length_cons, Nat.add_one_ne_zero, if_false, List.flatMap_cons, List.append_assoc,
      Nat.add_sub_cancel]
    rw [readFile_words _ (fit f (by simp))]
    have ih := readFiles_words more rest (fun g hg => fit g (by simp [hg]))
    cases hl : lexTokens f.source with
    | none => simp [lexFiles, hl]
    | some tokens =>
      simp only
      rw [ih]
      cases hm : lexFiles more with
      | none => simp [lexFiles, hl, hm, filesAfter]
      | some inputs => simp [lexFiles, hl, hm, filesAfter]

/-- On the words of files, the driver's front end is the several-file front
end. -/
theorem frontEndWords_files {files : List SourceFile} (fit : FilesFit files) :
    frontEndWords grammar (filesWords files) = sourceProgramFiles files := by
  have h := readFiles_words files [] fit.2
  rw [List.append_nil] at h
  simp only [frontEndWords, filesWords, readCountedFiles, wordNum_ofNat fit.1, h, sourceProgramFiles]
  cases lexFiles files with
  | none => rfl
  | some inputs => rfl

/-! ## Words the driver accepts are the words of files -/

theorem readNums_some : ∀ (count : Nat) (words : List (BitVec 32)) (r : NumsRead), readNums words count = some r →
    r.nums.length = count ∧ (∀ n ∈ r.nums, n < 2 ^ 32) ∧ words = r.nums.map (BitVec.ofNat 32) ++ r.rest
  | 0, words, r, h => by
    unfold readNums at h
    simp only [if_true, Option.some.injEq] at h
    subst h
    simp
  | count + 1, [], r, h => by unfold readNums at h; simp at h
  | count + 1, w :: ws, r, h => by
    unfold readNums at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    cases hr : readNums ws count with
    | none => simp [hr, numsAfter] at h
    | some r' =>
      simp only [hr, numsAfter, Option.some.injEq] at h
      subst h
      obtain ⟨len, lt, eq⟩ := readNums_some count ws r' hr
      refine ⟨by simp [len], ?_, by simp [ofNat_wordNum, eq]⟩
      intro n hn
      simp only [List.mem_cons] at hn
      rcases hn with rfl | hn
      · exact wordNum_lt w
      · exact lt n hn

theorem readCountedNums_some {words : List (BitVec 32)} {r : NumsRead} (h : readCountedNums words = some r) :
    NumsFit r.nums ∧ words = countedWords r.nums ++ r.rest := by
  cases words with
  | nil => simp [readCountedNums] at h
  | cons w ws =>
    simp only [readCountedNums] at h
    obtain ⟨len, lt, eq⟩ := readNums_some _ ws r h
    refine ⟨⟨by rw [len]; exact wordNum_lt w, lt⟩, ?_⟩
    simp [countedWords, len, ofNat_wordNum, eq]

theorem readBytes_some : ∀ (count : Nat) (words : List (BitVec 32)) (r : NumsRead), readBytes words count = some r →
    r.nums.length = count ∧ (∀ n ∈ r.nums, n < 256) ∧ words = r.nums.map (BitVec.ofNat 32) ++ r.rest
  | 0, words, r, h => by
    unfold readBytes at h
    simp only [if_true, Option.some.injEq] at h
    subst h
    simp
  | count + 1, [], r, h => by unfold readBytes at h; simp at h
  | count + 1, w :: ws, r, h => by
    unfold readBytes at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    by_cases big : 255 < wordNum w
    · simp [byteAfter, big] at h
    · simp only [byteAfter, big, if_false] at h
      cases hr : readBytes ws count with
      | none => simp [hr, numsAfter] at h
      | some r' =>
        simp only [hr, numsAfter, Option.some.injEq] at h
        subst h
        obtain ⟨len, lt, eq⟩ := readBytes_some count ws r' hr
        refine ⟨by simp [len], ?_, by simp [ofNat_wordNum, eq]⟩
        intro n hn
        simp only [List.mem_cons] at hn
        rcases hn with rfl | hn
        · omega
        · exact lt n hn

theorem bytes_of_lt : ∀ (ns : List Nat), (∀ n ∈ ns, n < 256) → ∃ source : List Byte, vals source = ns
  | [], _ => ⟨[], rfl⟩
  | n :: ns, h => by
    obtain ⟨source, eq⟩ := bytes_of_lt ns (fun m hm => h m (by simp [hm]))
    exact ⟨⟨n, h n (by simp)⟩ :: source, by simp [eq]⟩

theorem readCountedBytes_some {words : List (BitVec 32)} {r : NumsRead} (h : readCountedBytes words = some r) :
    ∃ source : List Byte, vals source = r.nums ∧ source.length < 2 ^ 32 ∧ words = countedWords r.nums ++ r.rest := by
  cases words with
  | nil => simp [readCountedBytes] at h
  | cons w ws =>
    simp only [readCountedBytes] at h
    obtain ⟨len, lt, eq⟩ := readBytes_some _ ws r h
    obtain ⟨source, vs⟩ := bytes_of_lt r.nums lt
    refine ⟨source, vs, ?_, ?_⟩
    · have : (vals source).length = source.length := List.length_map _
      rw [← this, vs, len]
      exact wordNum_lt w
    · simp [countedWords, len, ofNat_wordNum, eq]

theorem readFile_some {words : List (BitVec 32)} {r : FileRead} (h : readFile words = some r) :
    ∃ f, FileFits f ∧ words = fileWords f ++ r.rest := by
  unfold readFile at h
  cases hb : readCountedBytes words with
  | none => simp [hb] at h
  | some b =>
    obtain ⟨source, vs, len, wb⟩ := readCountedBytes_some hb
    simp only [hb, readFileParents] at h
    cases hp : readCountedNums b.rest with
    | none => simp [hp] at h
    | some p =>
      obtain ⟨pfit, wp⟩ := readCountedNums_some hp
      simp only [hp, readFileEnd] at h
      cases hq : readCountedNums p.rest with
      | none => simp [hq] at h
      | some q =>
        obtain ⟨qfit, wq⟩ := readCountedNums_some hq
        simp only [hq, fileLexed] at h
        cases hl : lexSource b.nums with
        | none => simp [hl] at h
        | some tokens =>
          simp only [hl, Option.some.injEq] at h
          subst h
          refine ⟨{ source := source, prods := p.nums, parents := q.nums }, ⟨len, pfit, qfit⟩, ?_⟩
          simp only [fileWords, vs, List.append_assoc]
          rw [wb, wp, wq]

theorem readFiles_some : ∀ (count : Nat) (words : List (BitVec 32)) (r : FilesRead), readFiles words count = some r →
    ∃ files : List SourceFile, files.length = count ∧ (∀ f ∈ files, FileFits f) ∧
      words = files.flatMap fileWords ++ r.rest
  | 0, words, r, h => by
    unfold readFiles at h
    simp only [if_true, Option.some.injEq] at h
    subst h
    exact ⟨[], rfl, by simp, rfl⟩
  | count + 1, words, r, h => by
    unfold readFiles at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    cases hf : readFile words with
    | none => simp [hf] at h
    | some fr =>
      obtain ⟨f, fit, wf⟩ := readFile_some hf
      simp only [hf] at h
      cases hr : readFiles fr.rest count with
      | none => simp [hr, filesAfter] at h
      | some r' =>
        simp only [hr, filesAfter, Option.some.injEq] at h
        subst h
        obtain ⟨files, len, fits, wr⟩ := readFiles_some count fr.rest r' hr
        refine ⟨f :: files, by simp [len], ?_, ?_⟩
        · intro g hg
          simp only [List.mem_cons] at hg
          rcases hg with rfl | hg
          · exact fit
          · exact fits g hg
        · rw [wf, wr]
          simp

/-- Words the driver's front end accepts are the words of files whose
numbers fit, and its program is theirs. -/
theorem frontEndWords_some {words : List (BitVec 32)} {sp : SrcProgram} (h : frontEndWords grammar words = some sp) :
    ∃ files, FilesFit files ∧ words = filesWords files ∧ sourceProgramFiles files = some sp := by
  have decoded : ∃ files, FilesFit files ∧ words = filesWords files := by
    unfold frontEndWords at h
    cases hr : readCountedFiles words with
    | none => simp [hr] at h
    | some r =>
      simp only [hr, frontEndRead] at h
      cases words with
      | nil => simp [readCountedFiles] at hr
      | cons w ws =>
        simp only [readCountedFiles] at hr
        obtain ⟨files, len, fits, wr⟩ := readFiles_some _ ws r hr
        cases hrest : r.rest with
        | cons _ _ => simp [hrest] at h
        | nil =>
          refine ⟨files, ⟨by rw [len]; exact wordNum_lt w, fits⟩, ?_⟩
          rw [filesWords, len, ofNat_wordNum, wr, hrest, List.append_nil]
  obtain ⟨files, fit, rfl⟩ := decoded
  exact ⟨files, fit, rfl, by rw [← frontEndWords_files fit]; exact h⟩

/-! ## The self program's function is `compileText` -/

/-- On the words of files, the self program's function gives the words of
`compileText`'s binary. -/
theorem compileWords_files {files : List SourceFile} (fit : FilesFit files) :
    compileWords (frontEndWords grammar (filesWords files)) = binaryWords (compileText files) := by
  rw [frontEndWords_files fit, compileText]
  cases sourceProgramFiles files with
  | none => rfl
  | some sp => rfl

/-- Words the self program's function accepts are the words of files, and
its output is the words of `compileText`'s binary for them. -/
theorem compileWords_some {words out : List (BitVec 32)} (h : compileWords (frontEndWords grammar words) = some out) :
    ∃ files binary, FilesFit files ∧ words = filesWords files ∧ compileText files = some binary ∧
      binaryWords (some binary) = some out := by
  cases hf : frontEndWords grammar words with
  | none => simp [hf, compileWords] at h
  | some sp =>
    obtain ⟨files, fit, rfl, hs⟩ := frontEndWords_some hf
    cases hc : compileSource sp with
    | none => simp [hf, compileWords, hc, binaryWords] at h
    | some binary =>
      refine ⟨files, binary, fit, rfl, by simp [compileText, hs, hc], ?_⟩
      simpa [hf, compileWords, hc] using h

end Lanius.Mini
