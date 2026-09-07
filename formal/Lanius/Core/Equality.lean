import Lanius.Core

namespace Lanius.Core

namespace Equality

structure Evidence {α : Type u} (left right : α) : Type where
  equal : left = right

-- Nested Core syntax does not support automatic DecidableEq derivation.
-- These checks return actual equality evidence, not an unchecked Boolean.
def atom? [DecidableEq α] (left right : α) : Option (Evidence left right) :=
  if same : left = right then some ⟨same⟩ else none

mutual
  def value? : (left right : Value) → Option (Evidence left right)
    | .unit, .unit => some ⟨rfl⟩
    | .boolean a, .boolean b => do
        let ⟨h⟩ ← atom? a b
        pure ⟨congrArg Value.boolean h⟩
    | .signed t a, .signed u b => do
        let ⟨ht⟩ ← atom? t u
        let ⟨hv⟩ ← atom? a b
        pure ⟨by cases ht; cases hv; rfl⟩
    | .unsigned t a, .unsigned u b => do
        let ⟨ht⟩ ← atom? t u
        let ⟨hv⟩ ← atom? a b
        pure ⟨by cases ht; cases hv; rfl⟩
    | .f32Bits a, .f32Bits b => do
        let ⟨h⟩ ← atom? a b
        pure ⟨congrArg Value.f32Bits h⟩
    | .f64Bits a, .f64Bits b => do
        let ⟨h⟩ ← atom? a b
        pure ⟨congrArg Value.f64Bits h⟩
    | .character a, .character b => do
        let ⟨h⟩ ← atom? a b
        pure ⟨congrArg Value.character h⟩
    | .string a, .string b => do
        let ⟨h⟩ ← atom? a b
        pure ⟨congrArg Value.string h⟩
    | .pointer a, .pointer b => do
        let ⟨h⟩ ← atom? a b
        pure ⟨congrArg Value.pointer h⟩
    | .array a, .array b => do
        let ⟨h⟩ ← values? a b
        pure ⟨congrArg Value.array h⟩
    | .slice t c p s n, .slice u d q v m => do
        let ⟨h⟩ ← atom? (t, c, p, s, n) (u, d, q, v, m)
        pure ⟨by cases h; rfl⟩
    | .structure t a, .structure u b => do
        let ⟨ht⟩ ← atom? t u
        let ⟨hv⟩ ← values? a b
        pure ⟨by cases ht; cases hv; rfl⟩
    | .enumeration t k a, .enumeration u j b => do
        let ⟨ht⟩ ← atom? (t, k) (u, j)
        let ⟨hv⟩ ← values? a b
        pure ⟨by cases ht; cases hv; rfl⟩
    | .reference t c p, .reference u d q => do
        let ⟨h⟩ ← atom? (t, c, p) (u, d, q)
        pure ⟨by cases h; rfl⟩
    | _, _ => none
  def values? : (left right : List Value) → Option (Evidence left right)
    | [], [] => some ⟨rfl⟩
    | a :: as, b :: bs => do
        let ⟨h⟩ ← value? a b
        let ⟨hs⟩ ← values? as bs
        pure ⟨by cases h; cases hs; rfl⟩
    | _, _ => none
end


mutual
  def pattern? : (left right : Pattern) → Option (Evidence left right)
    | .wildcard, .wildcard => some ⟨rfl⟩
    | .bind id, .bind id' => do
        let ⟨h0⟩ ← atom? id id'
        pure ⟨by cases h0; rfl⟩
    | .literal v, .literal v' => do
        let ⟨h0⟩ ← value? v v'
        pure ⟨by cases h0; rfl⟩
    | .enumVariant id variant vs, .enumVariant id' variant' vs' => do
        let ⟨h0⟩ ← atom? id id'
        let ⟨h1⟩ ← atom? variant variant'
        let ⟨h2⟩ ← patterns? vs vs'
        pure ⟨by cases h0; cases h1; cases h2; rfl⟩
    | _, _ => none
  def patterns? : (left right : List Pattern) → Option (Evidence left right)
    | [], [] => some ⟨rfl⟩
    | a :: as, b :: bs => do
        let ⟨h⟩ ← pattern? a b
        let ⟨hs⟩ ← patterns? as bs
        pure ⟨by cases h; cases hs; rfl⟩
    | _, _ => none
end

mutual
  def expression? : (left right : Expr) → Option (Evidence left right)
    | .value v, .value v' => do
        let ⟨h0⟩ ← value? v v'
        pure ⟨by cases h0; rfl⟩
    | .local id, .local id' => do
        let ⟨h0⟩ ← atom? id id'
        pure ⟨by cases h0; rfl⟩
    | .cast t v, .cast t' v' => do
        let ⟨h0⟩ ← atom? t t'
        let ⟨h1⟩ ← expression? v v'
        pure ⟨by cases h0; cases h1; rfl⟩
    | .unary op v, .unary op' v' => do
        let ⟨h0⟩ ← atom? op op'
        let ⟨h1⟩ ← expression? v v'
        pure ⟨by cases h0; cases h1; rfl⟩
    | .binary op a b, .binary op' a' b' => do
        let ⟨h0⟩ ← atom? op op'
        let ⟨h1⟩ ← expression? a a'
        let ⟨h2⟩ ← expression? b b'
        pure ⟨by cases h0; cases h1; cases h2; rfl⟩
    | .array t vs, .array t' vs' => do
        let ⟨h0⟩ ← atom? t t'
        let ⟨h1⟩ ← expressions? vs vs'
        pure ⟨by cases h0; cases h1; rfl⟩
    | .arrayToSlice t v, .arrayToSlice t' v' => do
        let ⟨h0⟩ ← atom? t t'
        let ⟨h1⟩ ← expression? v v'
        pure ⟨by cases h0; cases h1; rfl⟩
    | .index base index, .index base' index' => do
        let ⟨h0⟩ ← expression? base base'
        let ⟨h1⟩ ← expression? index index'
        pure ⟨by cases h0; cases h1; rfl⟩
    | .structValue id vs, .structValue id' vs' => do
        let ⟨h0⟩ ← atom? id id'
        let ⟨h1⟩ ← expressions? vs vs'
        pure ⟨by cases h0; cases h1; rfl⟩
    | .field base field, .field base' field' => do
        let ⟨h0⟩ ← expression? base base'
        let ⟨h1⟩ ← atom? field field'
        pure ⟨by cases h0; cases h1; rfl⟩
    | .enumValue id variant vs, .enumValue id' variant' vs' => do
        let ⟨h0⟩ ← atom? id id'
        let ⟨h1⟩ ← atom? variant variant'
        let ⟨h2⟩ ← expressions? vs vs'
        pure ⟨by cases h0; cases h1; cases h2; rfl⟩
    | .matchValue v branches, .matchValue v' branches' => do
        let ⟨h0⟩ ← expression? v v'
        let ⟨h1⟩ ← arms? branches branches'
        pure ⟨by cases h0; cases h1; rfl⟩
    | .assign op target v, .assign op' target' v' => do
        let ⟨h0⟩ ← atom? op op'
        let ⟨h1⟩ ← place? target target'
        let ⟨h2⟩ ← expression? v v'
        pure ⟨by cases h0; cases h1; cases h2; rfl⟩
    | .borrow t target, .borrow t' target' => do
        let ⟨h0⟩ ← atom? t t'
        let ⟨h1⟩ ← place? target target'
        pure ⟨by cases h0; cases h1; rfl⟩
    | .dereference v, .dereference v' => do
        let ⟨h0⟩ ← expression? v v'
        pure ⟨by cases h0; rfl⟩
    | .constant id, .constant id' => do
        let ⟨h0⟩ ← atom? id id'
        pure ⟨by cases h0; rfl⟩
    | .call id vs, .call id' vs' => do
        let ⟨h0⟩ ← atom? id id'
        let ⟨h1⟩ ← expressions? vs vs'
        pure ⟨by cases h0; cases h1; rfl⟩
    | .intrinsic op v, .intrinsic op' v' => do
        let ⟨h0⟩ ← atom? op op'
        let ⟨h1⟩ ← expression? v v'
        pure ⟨by cases h0; cases h1; rfl⟩
    | .i32ArrayDataPtr v, .i32ArrayDataPtr v' => do
        let ⟨h0⟩ ← expression? v v'
        pure ⟨by cases h0; rfl⟩
    | .i32SliceFromRawParts p n, .i32SliceFromRawParts p' n' => do
        let ⟨h0⟩ ← expression? p p'
        let ⟨h1⟩ ← expression? n n'
        pure ⟨by cases h0; cases h1; rfl⟩
    | .i32SliceDataPtr v, .i32SliceDataPtr v' => do
        let ⟨h0⟩ ← expression? v v'
        pure ⟨by cases h0; rfl⟩
    | .stringDataPtr v, .stringDataPtr v' => do
        let ⟨h0⟩ ← expression? v v'
        pure ⟨by cases h0; rfl⟩
    | .alloc n a, .alloc n' a' => do
        let ⟨h0⟩ ← expression? n n'
        let ⟨h1⟩ ← expression? a a'
        pure ⟨by cases h0; cases h1; rfl⟩
    | .realloc p old next a, .realloc p' old' next' a' => do
        let ⟨h0⟩ ← expression? p p'
        let ⟨h1⟩ ← expression? old old'
        let ⟨h2⟩ ← expression? next next'
        let ⟨h3⟩ ← expression? a a'
        pure ⟨by cases h0; cases h1; cases h2; cases h3; rfl⟩
    | .dealloc p n a, .dealloc p' n' a' => do
        let ⟨h0⟩ ← expression? p p'
        let ⟨h1⟩ ← expression? n n'
        let ⟨h2⟩ ← expression? a a'
        pure ⟨by cases h0; cases h1; cases h2; rfl⟩
    | .loadByte p offset, .loadByte p' offset' => do
        let ⟨h0⟩ ← expression? p p'
        let ⟨h1⟩ ← expression? offset offset'
        pure ⟨by cases h0; cases h1; rfl⟩
    | .storeByte p offset v, .storeByte p' offset' v' => do
        let ⟨h0⟩ ← expression? p p'
        let ⟨h1⟩ ← expression? offset offset'
        let ⟨h2⟩ ← expression? v v'
        pure ⟨by cases h0; cases h1; cases h2; rfl⟩
    | _, _ => none
  def expressions? : (left right : List Expr) → Option (Evidence left right)
    | [], [] => some ⟨rfl⟩
    | a :: as, b :: bs => do
        let ⟨h⟩ ← expression? a b
        let ⟨hs⟩ ← expressions? as bs
        pure ⟨by cases h; cases hs; rfl⟩
    | _, _ => none
  def place? : (left right : Place) → Option (Evidence left right)
    | .local id, .local id' => do
        let ⟨h0⟩ ← atom? id id'
        pure ⟨by cases h0; rfl⟩
    | .field base field, .field base' field' => do
        let ⟨h0⟩ ← place? base base'
        let ⟨h1⟩ ← atom? field field'
        pure ⟨by cases h0; cases h1; rfl⟩
    | .index base index, .index base' index' => do
        let ⟨h0⟩ ← place? base base'
        let ⟨h1⟩ ← expression? index index'
        pure ⟨by cases h0; cases h1; rfl⟩
    | _, _ => none
  def arms? : (left right : List (Pattern × Expr)) → Option (Evidence left right)
    | [], [] => some ⟨rfl⟩
    | (p, e) :: rest, (q, f) :: tail => do
        let ⟨hp⟩ ← pattern? p q
        let ⟨he⟩ ← expression? e f
        let ⟨hs⟩ ← arms? rest tail
        pure ⟨by cases hp; cases he; cases hs; rfl⟩
    | _, _ => none
end

def optional? (equal : (left right : α) → Option (Evidence left right)) :
    (left right : Option α) → Option (Evidence left right)
  | none, none => some ⟨rfl⟩
  | some left, some right => do
      let ⟨h⟩ ← equal left right
      pure ⟨congrArg some h⟩
  | _, _ => none

def statement? : (left right : Stmt) → Option (Evidence left right)
  | .skip, .skip => some ⟨rfl⟩
  | .expression e, .expression e' => do
      let ⟨h0⟩ ← expression? e e'
      pure ⟨by cases h0; rfl⟩
  | .sequence a b, .sequence a' b' => do
      let ⟨h0⟩ ← statement? a a'
      let ⟨h1⟩ ← statement? b b'
      pure ⟨by cases h0; cases h1; rfl⟩
  | .letLocal id t e body, .letLocal id' t' e' body' => do
      let ⟨h0⟩ ← atom? id id'
      let ⟨h1⟩ ← atom? t t'
      let ⟨h2⟩ ← expression? e e'
      let ⟨h3⟩ ← statement? body body'
      pure ⟨by cases h0; cases h1; cases h2; cases h3; rfl⟩
  | .letUninitialized id t body, .letUninitialized id' t' body' => do
      let ⟨h0⟩ ← atom? id id'
      let ⟨h1⟩ ← atom? t t'
      let ⟨h2⟩ ← statement? body body'
      pure ⟨by cases h0; cases h1; cases h2; rfl⟩
  | .ifThenElse condition yes no, .ifThenElse condition' yes' no' => do
      let ⟨h0⟩ ← expression? condition condition'
      let ⟨h1⟩ ← statement? yes yes'
      let ⟨h2⟩ ← statement? no no'
      pure ⟨by cases h0; cases h1; cases h2; rfl⟩
  | .whileLoop condition body, .whileLoop condition' body' => do
      let ⟨h0⟩ ← expression? condition condition'
      let ⟨h1⟩ ← statement? body body'
      pure ⟨by cases h0; cases h1; rfl⟩
  | .forValues id es body, .forValues id' es' body' => do
      let ⟨h0⟩ ← atom? id id'
      let ⟨h1⟩ ← expression? es es'
      let ⟨h2⟩ ← statement? body body'
      pure ⟨by cases h0; cases h1; cases h2; rfl⟩
  | .forRange id start stop inclusive body, .forRange id' start' stop' inclusive' body' => do
      let ⟨h0⟩ ← atom? id id'
      let ⟨h1⟩ ← expression? start start'
      let ⟨h2⟩ ← optional? expression? stop stop'
      let ⟨h3⟩ ← atom? inclusive inclusive'
      let ⟨h4⟩ ← statement? body body'
      pure ⟨by cases h0; cases h1; cases h2; cases h3; cases h4; rfl⟩
  | .returnValue v, .returnValue v' => do
      let ⟨h0⟩ ← optional? expression? v v'
      pure ⟨by cases h0; rfl⟩
  | .breakLoop, .breakLoop => some ⟨rfl⟩
  | .continueLoop, .continueLoop => some ⟨rfl⟩
  | _, _ => none

def function? (left right : Function) : Option (Evidence left right) := do
  let ⟨h⟩ ← atom? (left.id, left.parameters, left.returnType, left.external)
    (right.id, right.parameters, right.returnType, right.external)
  let ⟨body⟩ ← optional? statement? left.body right.body
  pure ⟨by cases left; cases right; cases h; cases body; rfl⟩

def constant? (left right : Constant) : Option (Evidence left right) := do
  let ⟨h⟩ ← atom? (left.id, left.type) (right.id, right.type)
  let ⟨v⟩ ← value? left.value right.value
  pure ⟨by cases left; cases right; cases h; cases v; rfl⟩

end Equality

end Lanius.Core
