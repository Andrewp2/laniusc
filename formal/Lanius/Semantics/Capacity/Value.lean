import Lanius.Semantics

namespace Lanius.Semantics.Capacity

open Lanius.Core

/-- A fixed callee allocation frontier and the old buffers reachable through
its arguments. Unreachable caller cells are not rewritten by transport. -/
structure Config where
  root : CellId
  boundary : CellId
  roots : CellId → Bool
  tail : List Value

def Config.reachable (config : Config) (cell : CellId) : Bool :=
  config.roots cell || decide (config.boundary ≤ cell)

structure Config.Valid (config : Config) : Prop where
  old : config.root < config.boundary
  included : config.roots config.root = true

mutual
  def plain : Value → Bool
    | .slice .. | .reference .. => false
    | .array entries | .structure _ entries | .enumeration _ _ entries => plains entries
    | _ => true
  def plains : List Value → Bool
    | [] => true
    | first :: rest => plain first && plains rest
end

mutual
  def closed (config : Config) : Value → Bool
    | .slice _ cell _ _ _ | .reference _ cell _ => config.reachable cell
    | .array entries | .structure _ entries | .enumeration _ _ entries => closeds config entries
    | _ => true
  def closeds (config : Config) : List Value → Bool
    | [] => true
    | first :: rest => closed config first && closeds config rest
end

mutual
  def value (config : Config) : Value → Value
    | .array entries => .array (values config entries)
    | .structure id entries => .structure id (values config entries)
    | .enumeration id variant entries => .enumeration id variant (values config entries)
    | .slice type cell path start length =>
        .slice type cell path start (if cell = config.root ∧ path = [] then length + config.tail.length else length)
    | other => other
  def values (config : Config) : List Value → List Value
    | [] => []
    | first :: rest => value config first :: values config rest
end

theorem values_eq_map (config : Config) (entries : List Value) :
    values config entries = entries.map (value config) := by
  induction entries <;> simp_all [values]

@[simp] theorem values_length (config : Config) (entries : List Value) :
    (values config entries).length = entries.length := by simp [values_eq_map]

@[simp] theorem values_append (config : Config) (left right : List Value) :
    values config (left ++ right) = values config left ++ values config right := by simp [values_eq_map]

@[simp] theorem values_getElem? (config : Config) (entries : List Value) (index : Nat) :
    (values config entries)[index]? = entries[index]?.map (value config) := by simp [values_eq_map]

theorem closeds_iff (config : Config) (entries : List Value) :
    closeds config entries = true ↔ ∀ entry ∈ entries, closed config entry = true := by
  induction entries <;> simp_all [closeds]

mutual
  theorem plain_fixed (config : Config) (entry : Value) (valid : plain entry = true) :
      value config entry = entry := by
    cases entry <;> simp_all only [plain, value, Bool.false_eq_true]
    all_goals rw [plains_fixed config _ valid]
  theorem plains_fixed (config : Config) (entries : List Value) (valid : plains entries = true) :
      values config entries = entries := by
    cases entries with
    | nil => rfl
    | cons first rest =>
      have parts : plain first = true ∧ plains rest = true := by simpa only [plains, Bool.and_eq_true] using valid
      simp only [values, plain_fixed config first parts.1, plains_fixed config rest parts.2]
end

mutual
  theorem plain_closed (config : Config) (entry : Value) (valid : plain entry = true) :
      closed config entry = true := by
    cases entry <;> simp_all only [plain, closed, Bool.false_eq_true]
    all_goals exact plains_closed config _ valid
  theorem plains_closed (config : Config) (entries : List Value) (valid : plains entries = true) :
      closeds config entries = true := by
    cases entries with
    | nil => rfl
    | cons first rest =>
      have parts : plain first = true ∧ plains rest = true := by simpa only [plains, Bool.and_eq_true] using valid
      simp only [closeds, plain_closed config first parts.1, plains_closed config rest parts.2, Bool.and_self]
end

mutual
  @[simp] theorem closed_value (config : Config) (entry : Value) : closed config (value config entry) = closed config entry := by
    cases entry <;> simp only [closed, value, closeds_values]
  @[simp] theorem closeds_values (config : Config) (entries : List Value) : closeds config (values config entries) = closeds config entries := by
    cases entries <;> simp only [values, closeds, closed_value, closeds_values]
end

def completion (config : Config) : Completion → Completion
  | .returned result => .returned (result.map (value config))
  | other => other

def completionClosed (config : Config) : Completion → Prop
  | .returned (some result) => closed config result = true
  | _ => True

end Lanius.Semantics.Capacity
