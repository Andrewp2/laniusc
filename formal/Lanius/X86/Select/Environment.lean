import Lanius.X86.Select.Syntax
import Lanius.X86.Select.Input

namespace Lanius.X86.Select.Environment

open Lanius.Core Lanius.FunctionalView Lanius.FunctionalView.Core Lanius.FunctionalView.Stateful

theorem set_push_last (environment : Env arity) (value replacement : Value) :
    Env.set (environment.push value) ⟨arity, Nat.lt_succ_self arity⟩ replacement = environment.push replacement := by
  funext index
  by_cases old : index.val < arity
  · have different : index.val ≠ arity := by omega
    simp [Env.set, Env.push, old, Fin.ext_iff, different]
  · have same : index.val = arity := by have := index.isLt; omega
    simp [Env.set, Env.push, Fin.ext_iff, same]

theorem set_push_before (environment : Env arity) (index : Fin arity) (value replacement : Value) :
    Env.set (environment.push value) ⟨index.val, Nat.lt_succ_of_lt index.isLt⟩ replacement =
      (Env.set environment index replacement).push value := by
  funext candidate
  by_cases old : candidate.val < arity
  · simp [Env.set, Env.push, old, Fin.ext_iff]
  · have different : candidate.val ≠ index.val := by have := index.isLt; omega
    simp [Env.set, Env.push, old, Fin.ext_iff, different]

def initial (input : Input) (cell : CellId) : Env 2 := fun index =>
  if index.val = 0 then .slice Syntax.i32 cell [] 0 input.words.length else .signed .i32 input.words.length
def counts (input : Input) (cell : CellId) : Env 4 :=
  ((initial input cell).push (.signed .i32 input.ids.length)).push (.signed .i32 input.bodyLength)
def body (input : Input) (cell : CellId) : Env 5 := (counts input cell).push (.signed .i32 input.bodyStart)
def first (input : Input) (cell : CellId) (offset : Nat) : Env 6 := (body input cell).push (.signed .i32 offset)
def returned (input : Input) (cell : CellId) : Env 7 :=
  (first input cell input.returnStart).push (.signed .i32 input.returnedId)
def selected (input : Input) (cell : CellId) (value : Int) : Env 8 := (returned input cell).push (.signed .i32 value)
def indexed (input : Input) (cell : CellId) (value : Int) (index : Nat) : Env 9 :=
  (selected input cell value).push (.signed .i32 index)
def identified (input : Input) (cell : CellId) (value : Int) (index id : Nat) : Env 10 :=
  (indexed input cell value index).push (.signed .i32 id)
def earlier (input : Input) (cell : CellId) (value : Int) (index id previous : Nat) : Env 11 :=
  (identified input cell value index id).push (.signed .i32 previous)

theorem earlier_increment {id : Nat} :
    Env.set (earlier input cell value index id previous) ⟨10, by decide⟩ (.signed .i32 (previous + 1 : Nat)) =
      earlier input cell value index id (previous + 1) := set_push_last _ _ _

theorem index_increment {id : Nat} :
    Env.set (earlier input cell value index id previous) ⟨8, by decide⟩ (.signed .i32 (index + 1 : Nat)) =
      earlier input cell value (index + 1) id previous := by
  rw [earlier, set_push_before _ ⟨8, by decide⟩, identified,
    set_push_before _ ⟨8, by decide⟩, indexed, set_push_last]
  rfl

theorem select_index {id : Nat} :
    Env.set (earlier input cell value index id previous) ⟨7, by decide⟩ (.signed .i32 index) =
      earlier input cell index index id previous := by
  rw [earlier, set_push_before _ ⟨7, by decide⟩, identified,
    set_push_before _ ⟨7, by decide⟩, indexed, set_push_before _ ⟨7, by decide⟩,
    selected, set_push_last]
  rfl

end Lanius.X86.Select.Environment
