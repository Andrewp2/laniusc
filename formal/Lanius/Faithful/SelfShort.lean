import Lanius.Faithful.SelfCompiler
import Lanius.Faithful.SelfLive

/-! # Why Core's run of `w` fails (review #5, piece (c))

`selfCompiler_outcome` lets the self-built verified compiler fault when
Core's run of `w` fails at every fuel. `failing_short` says why that
happens: the cost semantics gives the pure compile no value at any fuel, or
the output room is shorter than the binary's words, or the heap limit is
short, `limit < selfNext W room + h` for every cost `h` that `selfCost`
gives (`SelfShort`). -/

namespace Lanius.Faithful.SelfShort

open Lanius.Mini
open Lanius.Faithful
open Lanius.Faithful.Self
open Lanius.Faithful.SelfDriver
open Lanius.Faithful.SelfCompiler
open Lanius.Faithful.SelfLive

/-- Why Core's run of `w` on the words `W` of `files`, with `room` output
words and heap limit `limit`, may fail at every fuel: the pure compile has no
cost at any fuel (`selfCost`: `oracle_read`'s `cons` calls, `grammar()`,
`front_end_words` and `compile_words`), or `compileText files`'s binary has
more words than `room`, or it has a cost and the heap limit is short, below
`selfNext W room + h` for every cost `h` it has. -/
def SelfShort (files : List SourceFile) (room limit : Nat) : Prop :=
  (∀ N, selfCost N (filesWords files) = none) ∨
  (∃ ws, binaryWords (compileText files) = some ws ∧ room < ws.length) ∨
  ((∃ N h, selfCost N (filesWords files) = some h) ∧
    ∀ N h, selfCost N (filesWords files) = some h → limit < selfNext (filesWords files) room + h)

/-- **Core's run of `w` fails only for a reason.** When Core's run of `w`
on `selfStart` fails at every fuel (it diverges, stops at a trap, or ends
with the heap past `limit`), one of `SelfShort`'s reasons holds. -/
theorem failing_short {files : List SourceFile} (fit : FilesFit files)
    (wordsLt : (filesWords files).length < 2 ^ 31) {room limit : Nat} (roomLt : room < 2 ^ 31)
    (small : limit < 2 ^ 62) (fails : ∀ fuel, Failing limit (selfRun (filesWords files) room fuel)) :
    SelfShort files room limit := by
  have nonempty := filesWords_pos files
  by_cases costs : ∃ N h, selfCost N (filesWords files) = some h
  · by_cases fits : ∀ ws, binaryWords (compileText files) = some ws → ws.length ≤ room
    · by_cases short : ∀ N h, selfCost N (filesWords files) = some h →
          limit < selfNext (filesWords files) room + h
      · exact .inr (.inr ⟨costs, short⟩)
      · exfalso
        obtain ⟨N, h, cost, within⟩ : ∃ N h, selfCost N (filesWords files) = some h ∧
            selfNext (filesWords files) room + h ≤ limit := by
          refine Classical.byContradiction fun none => short fun N h cost => ?_
          exact Nat.lt_of_not_le fun le => none ⟨N, h, cost, le⟩
        obtain ⟨v, st', ⟨K, run⟩, next⟩ := driver_live (st := selfStart (filesWords files) room)
          (inp := selfInput) (outp := selfOutput (filesWords files)) (N := N) (h := h)
          (start_inv nonempty) wordsLt roomLt (start_reads wordsLt) start_readable
          (.inr (start_range_input nonempty))
          (if h : room = 0 then .inl h else .inr (start_range_output (Nat.pos_of_ne_zero h)))
          rfl cost (by show selfNext (filesWords files) room + h ≤ 2 ^ 64; omega)
          (fun ws words => fits ws (by rw [← compileWords_files fit]; exact words))
        have fail := fails K
        rw [show selfRun (filesWords files) room K = .done v st' from run K (Nat.le_refl K)] at fail
        have start : (selfStart (filesWords files) room).heap.nextAddress = selfNext (filesWords files) room := rfl
        rw [start] at next
        simp only [Failing] at fail
        exact Nat.lt_irrefl _ (Nat.lt_of_lt_of_le fail (Nat.le_trans next within))
    · refine .inr (.inl ?_)
      refine Classical.byContradiction fun none => fits fun ws words => ?_
      exact Nat.le_of_not_lt fun lt => none ⟨ws, words, lt⟩
  · refine .inl fun N => ?_
    cases cost : selfCost N (filesWords files) with
    | none => rfl
    | some h => exact absurd ⟨N, h, cost⟩ costs

#print axioms failing_short

end Lanius.Faithful.SelfShort
