import Lanius.Mini.Reading.Lits

/-! # The reading, V8f: the program

`Reading roots p`: the source program `p` read from the parse trees of
several files, the first the program's own. Each file declares what its
items say in its module (`FileDeclsR`, `CollectedR`), the names are well
formed (`WellNamed`), the function instances are those of the first file's
functions without type parameters closed under calls in first-request order
(`MonoR`), the type instances are those its type declarations without
parameters need and then those the functions' types need (`TypeTable`,
`TypeTableMore`), and the program is the instances' functions closed
against the two tables, with their literals typed (`ClosedProgram`).
`buildFiles_sound`: what `buildFiles` returns is a reading. -/

namespace Lanius.Mini.Reading

open Lanius.Mini

def Reading (roots : List CTree) (p : SrcProgram) : Prop :=
  ∃ (first : CTree) (rest : List CTree) (f : FileDecls) (r : Collected) (mono : Mono) (seeded types : List Inst),
    roots = first :: rest ∧ FileDeclsR first f ∧ CollectedR rest r ∧
    WellNamed { decls := f.decls.append r.decls, modules := f.home :: r.modules } ∧
    MonoR (f.decls.append r.decls) (rootInsts f.decls.fns 0) [] 0 mono ∧
    TypeTable (f.decls.append r.decls) (seedInsts f.decls.types 0) (seedTys (seedInsts f.decls.types 0)) seeded ∧
    TypeTableMore (f.decls.append r.decls) seeded (funcsTys mono.funcs) types ∧
    ClosedProgram (f.decls.append r.decls) mono.table types mono.funcs p

theorem buildFiles_sound {fuel : Nat} {roots : List CTree} {p : SrcProgram} (h : buildFiles fuel roots = some p) :
    Reading roots p := by
  cases roots with
  | nil => simp [buildFiles] at h
  | cons first rest =>
    simp only [buildFiles] at h
    cases hf : fileDecls fuel first with
    | none => rw [hf] at h; cases h
    | some f =>
      rw [hf] at h
      simp only at h
      cases hc : collectFiles fuel rest { decls := f.decls, modules := [f.home] } with
      | none => rw [hc] at h; simp [buildCollected] at h
      | some c =>
        rw [hc] at h
        obtain ⟨r, cr, rfl⟩ := collectFiles_sound hc
        simp only [buildCollected, buildChecked] at h
        split at h
        · rename_i wn
          cases hm : monoLoop fuel fuel (f.decls.append r.decls) (rootInsts f.decls.fns 0) [] 0 with
          | none => rw [hm] at h; simp [buildMono] at h
          | some mono =>
            rw [hm] at h
            simp only [buildMono] at h
            obtain ⟨ts, hts, cp⟩ := buildClosed_sound h
            cases ht : typeTable fuel (f.decls.append r.decls) (seedInsts f.decls.types 0)
                (seedTys (seedInsts f.decls.types 0)) with
            | none => rw [ht, typeTableMore_none] at hts; cases hts
            | some seeded =>
              rw [ht] at hts
              exact ⟨first, rest, f, r, mono, seeded, ts, rfl, fileDecls_sound hf, cr, wellNamed_sound wn,
                monoLoop_sound hm, typeTable_sound ht, typeTableMore_sound hts, cp⟩
        · cases h

end Lanius.Mini.Reading
