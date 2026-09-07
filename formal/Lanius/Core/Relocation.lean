import Lanius.Core

namespace Lanius.Core.Relocation

/-- Global symbol relocation leaves local IDs, field positions, cell IDs,
and byte addresses unchanged. Semantic transport additionally requires
injective type IDs and corresponding program lookups. -/
structure Symbols where
  typeId : TypeId → TypeId
  functionId : FunctionId → FunctionId
  constantId : ConstantId → ConstantId

def Symbols.identity : Symbols := ⟨id, id, id⟩

def Symbols.comp (outer inner : Symbols) : Symbols :=
  ⟨outer.typeId ∘ inner.typeId, outer.functionId ∘ inner.functionId,
    outer.constantId ∘ inner.constantId⟩

def ty (symbols : Symbols) : Ty → Ty
  | .unit => .unit
  | .scalar scalar => .scalar scalar
  | .array element count => .array (ty symbols element) count
  | .slice element => .slice (ty symbols element)
  | .reference referent => .reference (ty symbols referent)
  | .structure id => .structure (symbols.typeId id)
  | .enumeration id => .enumeration (symbols.typeId id)

mutual
  def value (symbols : Symbols) : Value → Value
    | .unit => .unit
    | .boolean v => .boolean v
    | .signed t v => .signed t v
    | .unsigned t v => .unsigned t v
    | .f32Bits v => .f32Bits v
    | .f64Bits v => .f64Bits v
    | .character v => .character v
    | .string v => .string v
    | .pointer v => .pointer v
    | .array vs => .array (values symbols vs)
    | .slice t cell path start length => .slice (ty symbols t) cell path start length
    | .structure id vs => .structure (symbols.typeId id) (values symbols vs)
    | .enumeration id variant vs => .enumeration (symbols.typeId id) variant (values symbols vs)
    | .reference t cell path => .reference (ty symbols t) cell path
  def values (symbols : Symbols) : List Value → List Value
    | [] => []
    | v :: rest => value symbols v :: values symbols rest
end

mutual
  def pattern (symbols : Symbols) : Pattern → Pattern
    | .wildcard => .wildcard
    | .bind id => .bind id
    | .literal v => .literal (value symbols v)
    | .enumVariant id variant vs => .enumVariant (symbols.typeId id) variant (patterns symbols vs)
  def patterns (symbols : Symbols) : List Pattern → List Pattern
    | [] => []
    | p :: rest => pattern symbols p :: patterns symbols rest
end

mutual
  def expression (symbols : Symbols) : Expr → Expr
    | .value v => .value (value symbols v)
    | .local id => .local id
    | .cast t v => .cast t (expression symbols v)
    | .unary op v => .unary op (expression symbols v)
    | .binary op left right => .binary op (expression symbols left) (expression symbols right)
    | .array t vs => .array (ty symbols t) (expressions symbols vs)
    | .arrayToSlice t v => .arrayToSlice (ty symbols t) (expression symbols v)
    | .index base index => .index (expression symbols base) (expression symbols index)
    | .structValue id vs => .structValue (symbols.typeId id) (expressions symbols vs)
    | .field base field => .field (expression symbols base) field
    | .enumValue id variant vs => .enumValue (symbols.typeId id) variant (expressions symbols vs)
    | .matchValue v branches => .matchValue (expression symbols v) (arms symbols branches)
    | .assign op target v => .assign op (place symbols target) (expression symbols v)
    | .borrow t target => .borrow (ty symbols t) (place symbols target)
    | .dereference v => .dereference (expression symbols v)
    | .constant id => .constant (symbols.constantId id)
    | .call id vs => .call (symbols.functionId id) (expressions symbols vs)
    | .intrinsic op v => .intrinsic op (expression symbols v)
    | .i32ArrayDataPtr v => .i32ArrayDataPtr (expression symbols v)
    | .i32SliceFromRawParts pointer length => .i32SliceFromRawParts (expression symbols pointer) (expression symbols length)
    | .i32SliceDataPtr v => .i32SliceDataPtr (expression symbols v)
    | .stringDataPtr v => .stringDataPtr (expression symbols v)
    | .alloc size alignment => .alloc (expression symbols size) (expression symbols alignment)
    | .realloc pointer oldSize newSize alignment => .realloc (expression symbols pointer) (expression symbols oldSize) (expression symbols newSize) (expression symbols alignment)
    | .dealloc pointer size alignment => .dealloc (expression symbols pointer) (expression symbols size) (expression symbols alignment)
    | .loadByte pointer offset => .loadByte (expression symbols pointer) (expression symbols offset)
    | .storeByte pointer offset v => .storeByte (expression symbols pointer) (expression symbols offset) (expression symbols v)
  def expressions (symbols : Symbols) : List Expr → List Expr
    | [] => []
    | e :: rest => expression symbols e :: expressions symbols rest
  def place (symbols : Symbols) : Place → Place
    | .local id => .local id
    | .field base field => .field (place symbols base) field
    | .index base index => .index (place symbols base) (expression symbols index)
  def arms (symbols : Symbols) : List (Pattern × Expr) → List (Pattern × Expr)
    | [] => []
    | (p, e) :: rest => (pattern symbols p, expression symbols e) :: arms symbols rest
end

def statement (symbols : Symbols) : Stmt → Stmt
  | .skip => .skip
  | .expression e => .expression (expression symbols e)
  | .sequence first second => .sequence (statement symbols first) (statement symbols second)
  | .letLocal id t e body => .letLocal id (ty symbols t) (expression symbols e) (statement symbols body)
  | .letUninitialized id t body => .letUninitialized id (ty symbols t) (statement symbols body)
  | .ifThenElse condition yes no => .ifThenElse (expression symbols condition) (statement symbols yes) (statement symbols no)
  | .whileLoop condition body => .whileLoop (expression symbols condition) (statement symbols body)
  | .forValues id iterable body => .forValues id (expression symbols iterable) (statement symbols body)
  | .forRange id start stop inclusive body => .forRange id (expression symbols start)
      (stop.map (expression symbols)) inclusive (statement symbols body)
  | .returnValue v => .returnValue (v.map (expression symbols))
  | .breakLoop => .breakLoop
  | .continueLoop => .continueLoop

def function (symbols : Symbols) (declaration : Function) : Function := {
  id := symbols.functionId declaration.id
  parameters := declaration.parameters.map fun (id, t) => (id, ty symbols t)
  returnType := ty symbols declaration.returnType
  body := declaration.body.map (statement symbols)
  external := declaration.external
}

def constant (symbols : Symbols) (declaration : Constant) : Constant := {
  id := symbols.constantId declaration.id
  type := ty symbols declaration.type
  value := value symbols declaration.value
}

@[simp] theorem ty_identity (t : Ty) : ty Symbols.identity t = t := by
  induction t <;> simp_all [ty, Symbols.identity]

mutual
  @[simp] theorem value_identity (v : Value) : value Symbols.identity v = v := by
    cases v <;> simp [value, values_identity] <;> rfl
  @[simp] theorem values_identity (vs : List Value) : values Symbols.identity vs = vs := by
    cases vs <;> simp [values, value_identity, values_identity]
end

theorem ty_comp (outer inner : Symbols) (t : Ty) :
    ty outer (ty inner t) = ty (outer.comp inner) t := by
  induction t <;> simp_all [ty, Symbols.comp]

mutual
  theorem value_comp (outer inner : Symbols) (v : Value) :
      value outer (value inner v) = value (outer.comp inner) v := by
    cases v <;> simp [value, values_comp, ty_comp, Symbols.comp]
  theorem values_comp (outer inner : Symbols) (vs : List Value) :
      values outer (values inner vs) = values (outer.comp inner) vs := by
    cases vs <;> simp [values, value_comp, values_comp]
end

@[simp] theorem values_eq_map (symbols : Symbols) (vs : List Value) :
    values symbols vs = vs.map (value symbols) := by
  induction vs <;> simp_all [values]

theorem ty_leftInverse (outer inner : Symbols)
    (inverse : Function.LeftInverse outer.typeId inner.typeId) (t : Ty) :
    ty outer (ty inner t) = t := by
  have inverseEq : ∀ id, outer.typeId (inner.typeId id) = id := inverse
  induction t <;> simp_all [ty, inverseEq]

mutual
  theorem value_leftInverse (outer inner : Symbols)
      (inverse : Function.LeftInverse outer.typeId inner.typeId) (v : Value) :
      value outer (value inner v) = v := by
    have inverseEq : ∀ id, outer.typeId (inner.typeId id) = id := inverse
    cases v <;> simp only [value, ty_leftInverse outer inner inverse,
      values_leftInverse outer inner inverse, inverseEq]
  theorem values_leftInverse (outer inner : Symbols)
      (inverse : Function.LeftInverse outer.typeId inner.typeId) (vs : List Value) :
      values outer (values inner vs) = vs := by
    cases vs <;> simp only [values, value_leftInverse outer inner inverse,
      values_leftInverse outer inner inverse]
end

mutual
  @[simp] theorem pattern_identity (p : Pattern) : pattern Symbols.identity p = p := by
    cases p <;> simp [pattern, patterns_identity] <;> rfl
  @[simp] theorem patterns_identity (ps : List Pattern) : patterns Symbols.identity ps = ps := by
    cases ps <;> simp [patterns, pattern_identity, patterns_identity]
end

mutual
  @[simp] theorem expression_identity (e : Expr) : expression Symbols.identity e = e := by
    cases e <;> simp [expression, expression_identity, expressions_identity, place_identity, arms_identity] <;> rfl
  @[simp] theorem expressions_identity (es : List Expr) : expressions Symbols.identity es = es := by
    cases es <;> simp [expressions, expression_identity, expressions_identity]
  @[simp] theorem place_identity (p : Place) : place Symbols.identity p = p := by
    cases p <;> simp [place, place_identity, expression_identity]
  @[simp] theorem arms_identity (branches : List (Pattern × Expr)) : arms Symbols.identity branches = branches := by
    cases branches with
    | nil => rfl
    | cons first rest => cases first; simp [arms, expression_identity, arms_identity]
end

@[simp] theorem statement_identity (s : Stmt) : statement Symbols.identity s = s := by
  have expressions : expression Symbols.identity = id := funext expression_identity
  induction s <;> simp_all [statement]

end Lanius.Core.Relocation
