import Init.Data.List.Impl

namespace Lanius.Data.List

noncomputable def map (function : α → β) (values : List α) : List β :=
  List.rec [] (fun value _ rest => function value :: rest) values

theorem map_eq : @map = @_root_.List.map := by
  funext α β function values
  induction values with
  | nil => rfl
  | cons value values ih =>
      change function value :: map function values = _
      rw [ih]
      rfl

@[csimp] private theorem map_eq_mapTR : @map = @_root_.List.mapTR :=
  map_eq.trans _root_.List.map_eq_mapTR

noncomputable def append (left right : List α) : List α :=
  List.rec right (fun value _ rest => value :: rest) left

theorem append_eq : @append = @_root_.List.append := by
  funext α left right
  induction left with
  | nil => rfl
  | cons value values ih =>
      change value :: append values right = _
      rw [ih]
      rfl

@[csimp] private theorem append_eq_appendTR : @append = @_root_.List.appendTR :=
  append_eq.trans _root_.List.append_eq_appendTR

noncomputable def flatten (values : List (List α)) : List α :=
  List.rec [] (fun value _ rest => append value rest) values

theorem flatten_eq : @flatten = @_root_.List.flatten := by
  funext α values
  induction values with
  | nil => rfl
  | cons value values ih =>
      change append value (flatten values) = _
      rw [append_eq, ih]
      rfl

@[csimp] private theorem flatten_eq_flattenTR : @flatten = @_root_.List.flattenTR :=
  flatten_eq.trans _root_.List.flatten_eq_flattenTR

/-- Distribute mapping over chunks without normalizing their payloads. -/
theorem flatten_map (function : α → β) (chunks : List (List α)) :
    flatten (map (map function) chunks) = map function (flatten chunks) := by
  simp only [flatten_eq, map_eq, _root_.List.map_flatten]

/-- Ordinary first-match lookup, with an explicit recursor for kernel
    reduction. The compiler uses the standard executable implementation. -/
noncomputable def find? (predicate : α → Bool) (values : List α) : Option α :=
  List.rec none (fun value _ rest => if predicate value then some value else rest) values

@[csimp] theorem find?_eq : @find? = @_root_.List.find? := by
  funext α predicate values
  induction values with
  | nil => rfl
  | cons value values ih =>
      change (if predicate value then some value else find? predicate values) = _
      rw [ih]
      simp only [_root_.List.find?_cons]
      cases predicate value <;> rfl

/-- Search the existing chunks without first materializing their concatenation.
    This keeps reduction depth bounded by a chunk plus the chunk-list spine. -/
noncomputable def findChunks (predicate : α → Bool) (chunks : List (List α)) : Option α :=
  List.rec none (fun chunk _ found => (find? predicate chunk).or found) chunks

theorem findChunks_eq (predicate : α → Bool) (chunks : List (List α)) :
    findChunks predicate chunks = (flatten chunks).find? predicate := by
  rw [flatten_eq]
  induction chunks with
  | nil => rfl
  | cons chunk rest ih =>
    simpa only [findChunks, _root_.List.flatten_cons, _root_.List.find?_append,
      find?_eq, flatten_eq] using
      congrArg (fun found => (chunk.find? predicate).or found) ih

end Lanius.Data.List
