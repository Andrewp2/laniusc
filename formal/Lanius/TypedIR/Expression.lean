import Lanius.TypedIR.Literal

namespace Lanius.TypedIR.Intrinsic

open Lanius Core Typing

mutual
  /-- The syntax is the typing derivation: there is no raw expression field and
      no second expression-sized proof. Only resolved references and primitive
      operation facts carry local evidence. -/
  inductive Expr (signature : Signature) : Scope → Core.Ty → Type where
    | literal (value : Literal signature.target type) : Expr signature context type
    | local (binding : Local context type) : Expr signature context type
    | cast (operand : Expr signature context (.scalar source)) (conversion : ScalarCast source target) :
        Expr signature context (.scalar target)
    | unary (op : UnaryOp) (operand : Expr signature context input)
        (operation : UnaryOpHasType op input output) : Expr signature context output
    | binary (op : BinaryOp) (left : Expr signature context leftType)
        (right : Expr signature context rightType) (operation : BinaryOpHasType op leftType rightType output) :
        Expr signature context output
    | array (elements : Exprs signature context (List.replicate count element)) :
        Expr signature context (.array element count)
    | arrayToSlice (array : Expr signature context (.array element length)) : Expr signature context (.slice element)
    | indexArray (base : Expr signature context (.array element length)) (index : Expr signature context indexType)
        (integer : IntegerTy indexType) : Expr signature context element
    | indexSlice (base : Expr signature context (.slice element)) (index : Expr signature context indexType)
        (integer : IntegerTy indexType) : Expr signature context element
    | record (constructor : StructRef signature typeId fields) (values : Exprs signature context fields) :
        Expr signature context (.structure typeId)
    | field (base : Expr signature context (.structure typeId)) (record : StructRef signature typeId fields)
        (index : FieldId) (found : fields[index]? = some type) : Expr signature context type
    | variant (constructor : VariantRef signature typeId types) (payload : Exprs signature context types) :
        Expr signature context (.enumeration typeId)
    | matchValue (scrutinee : Expr signature context input) (arms : Arms signature context input output) :
        Expr signature context output
    | assign (op : AssignOp) (place : Place signature context type) (value : Expr signature context type)
        (operation : AssignOpHasType op type) : Expr signature context .unit
    | borrow (place : Place signature context type) : Expr signature context (.reference type)
    | dereference (reference : Expr signature context (.reference type)) : Expr signature context type
    | constant (reference : ConstantRef signature type) : Expr signature context type
    | call (reference : FunctionRef signature parameters result) (arguments : Exprs signature context parameters) :
        Expr signature context result
    | printI32 (argument : Expr signature context (.scalar (.signed .i32))) : Expr signature context .unit
    | assert (argument : Expr signature context (.scalar .bool)) : Expr signature context .unit
    | i32ArrayDataPtr (array : Expr signature context (.array (.scalar (.signed .i32)) length)) :
        Expr signature context (.scalar .rawPtr)
    | i32SliceFromRawParts (pointer : Expr signature context (.scalar .rawPtr))
        (length : Expr signature context (.scalar (.signed .i32))) : Expr signature context (.slice (.scalar (.signed .i32)))
    | typedSliceFromRawParts (element : Core.Ty) (declared : RawNominalSliceElement signature.declarations element)
        (pointer : Expr signature context (.scalar .rawPtr)) (length : Expr signature context (.scalar (.signed .i32))) :
        Expr signature context (.slice element)
    | i32SliceDataPtr (slice : Expr signature context (.slice (.scalar (.signed .i32)))) : Expr signature context (.scalar .rawPtr)
    | stringDataPtr (string : Expr signature context (.scalar .string)) : Expr signature context (.scalar .rawPtr)
    | alloc (size alignment : Expr signature context (.scalar (.unsigned .usize))) : Expr signature context (.scalar .rawPtr)
    | realloc (pointer : Expr signature context (.scalar .rawPtr))
        (oldSize newSize alignment : Expr signature context (.scalar (.unsigned .usize))) : Expr signature context (.scalar .rawPtr)
    | dealloc (pointer : Expr signature context (.scalar .rawPtr))
        (size alignment : Expr signature context (.scalar (.unsigned .usize))) : Expr signature context .unit
    | loadByte (pointer : Expr signature context (.scalar .rawPtr))
        (offset : Expr signature context (.scalar (.unsigned .usize))) : Expr signature context (.scalar (.unsigned .u8))
    | storeByte (pointer : Expr signature context (.scalar .rawPtr))
        (offset : Expr signature context (.scalar (.unsigned .usize)))
        (value : Expr signature context (.scalar (.unsigned .u8))) : Expr signature context .unit

  inductive Place (signature : Signature) : Scope → Core.Ty → Type where
    | local (binding : Local context type) : Place signature context type
    | field (base : Place signature context (.structure typeId)) (record : StructRef signature typeId fields)
        (index : FieldId) (found : fields[index]? = some type) : Place signature context type
    | indexArray (base : Place signature context (.array element length)) (index : Expr signature context indexType)
        (integer : IntegerTy indexType) : Place signature context element
    | indexSlice (base : Place signature context (.slice element)) (index : Expr signature context indexType)
        (integer : IntegerTy indexType) : Place signature context element

  inductive Exprs (signature : Signature) : Scope → List Core.Ty → Type where
    | nil : Exprs signature context []
    | cons (head : Expr signature context type) (tail : Exprs signature context types) : Exprs signature context (type :: types)

  inductive Arms (signature : Signature) : Scope → Core.Ty → Core.Ty → Type where
    | one (pattern : Pattern signature input bindings) (body : Expr signature (context.bindAll bindings) output) :
        Arms signature context input output
    | cons (pattern : Pattern signature input bindings) (body : Expr signature (context.bindAll bindings) output)
        (tail : Arms signature context input output) : Arms signature context input output
end

mutual
  def Expr.erase : Expr signature context type → Core.Expr
    | .literal value => .value value.erase
    | .local binding => .local binding.id
    | .cast (target := target) operand _ => .cast target operand.erase
    | .unary op operand _ => .unary op operand.erase
    | .binary op left right _ => .binary op left.erase right.erase
    | .array (element := element) elements => .array element elements.erase
    | .arrayToSlice (element := element) array => .arrayToSlice element array.erase
    | .indexArray base index _ | .indexSlice base index _ => .index base.erase index.erase
    | .record (typeId := typeId) _ fields => .structValue typeId fields.erase
    | .field base _ index _ => .field base.erase index
    | .variant (typeId := typeId) constructor payload => .enumValue typeId constructor.ordinal payload.erase
    | .matchValue scrutinee arms => .matchValue scrutinee.erase arms.erase
    | .assign op place value _ => .assign op place.erase value.erase
    | .borrow (type := type) place => .borrow type place.erase
    | .dereference reference => .dereference reference.erase
    | .constant reference => .constant reference.id
    | .call reference arguments => .call reference.id arguments.erase
    | .printI32 argument => .intrinsic .printI32 argument.erase
    | .assert argument => .intrinsic .assert argument.erase
    | .i32ArrayDataPtr array => .i32ArrayDataPtr array.erase
    | .i32SliceFromRawParts pointer length => .i32SliceFromRawParts pointer.erase length.erase
    | .typedSliceFromRawParts element _ pointer length => .typedSliceFromRawParts element pointer.erase length.erase
    | .i32SliceDataPtr slice => .i32SliceDataPtr slice.erase
    | .stringDataPtr string => .stringDataPtr string.erase
    | .alloc size alignment => .alloc size.erase alignment.erase
    | .realloc pointer oldSize newSize alignment => .realloc pointer.erase oldSize.erase newSize.erase alignment.erase
    | .dealloc pointer size alignment => .dealloc pointer.erase size.erase alignment.erase
    | .loadByte pointer offset => .loadByte pointer.erase offset.erase
    | .storeByte pointer offset value => .storeByte pointer.erase offset.erase value.erase

  def Place.erase : Place signature context type → Core.Place
    | .local binding => .local binding.id
    | .field base _ index _ => .field base.erase index
    | .indexArray base index _ | .indexSlice base index _ => .index base.erase index.erase

  def Exprs.erase : Exprs signature context types → List Core.Expr
    | .nil => []
    | .cons head tail => head.erase :: tail.erase

  def Arms.erase : Arms signature context input output → List (Core.Pattern × Core.Expr)
    | .one pattern body => [(pattern.erase, body.erase)]
    | .cons pattern body tail => (pattern.erase, body.erase) :: tail.erase
end

theorem Exprs.length (values : Exprs signature context types) : values.erase.length = types.length :=
  match values with
  | .nil => rfl
  | .cons _ tail => congrArg Nat.succ (Exprs.length tail)

theorem Expr.erase_cast {signature : Signature} {context : Scope} {left right : Core.Ty}
    (same : left = right) (expression : Expr signature context left) :
    ((congrArg (Expr signature context) same).mp expression).erase = expression.erase := by
  cases same
  rfl

mutual
  theorem Expr.wellTyped (expression : Expr signature scope type) (linked : signature.Realizes program)
      (valid : scope.Realizes context) :
      ExprHasType program context expression.erase type :=
    match expression with
    | .literal value => .value (linked.value (value.wellTyped (program := signature.declarations))) value.isLiteral
    | .local binding => .local (valid _ _ binding.found)
    | .cast operand conversion => .cast (operand.wellTyped linked valid) conversion
    | .unary _ operand operation => .unary (operand.wellTyped linked valid) operation
    | .binary _ left right operation => .binary (left.wellTyped linked valid) (right.wellTyped linked valid) operation
    | .array (count := count) (element := element) elements => by
        have length : elements.erase.length = count := by simpa only [List.length_replicate] using elements.length
        have typed : ExprsHaveTypes program context elements.erase
            (List.replicate elements.erase.length element) := by
          simpa only [length] using elements.wellTyped linked valid
        simpa only [Expr.erase, length] using ExprHasType.array typed
    | .arrayToSlice array => .arrayToSlice (array.wellTyped linked valid)
    | .indexArray base index integer => .indexArray (base.wellTyped linked valid) (index.wellTyped linked valid) integer
    | .indexSlice base index integer => .indexSlice (base.wellTyped linked valid) (index.wellTyped linked valid) integer
    | .record constructor fields => .structValue constructor.declaration (linked.structure constructor.found)
        (by simpa only [constructor.fieldsMatch] using fields.wellTyped linked valid)
    | .field base record _ found => .field (base.wellTyped linked valid) record.declaration
        (linked.structure record.found) (by simpa only [record.fieldsMatch] using found)
    | .variant constructor payload => .enumValue constructor.declaration
        (linked.enumeration constructor.found) constructor.payloadMatch (payload.wellTyped linked valid)
    | .matchValue scrutinee arms => .matchValue (scrutinee.wellTyped linked valid) (arms.wellTyped linked valid)
    | .assign _ place value operation => .assign (place.wellTyped linked valid) (value.wellTyped linked valid) operation
    | .borrow place => .borrow (place.wellTyped linked valid)
    | .dereference reference => .dereference (reference.wellTyped linked valid)
    | .constant reference => by
        obtain ⟨declaration, found, typeMatch⟩ := Option.map_eq_some_iff.mp reference.found
        simpa only [Expr.erase, typeMatch] using
          (ExprHasType.constant (context := context) declaration (linked.constant found))
    | .call reference arguments => by
        obtain ⟨function, found, same⟩ := linked.function reference.found
        have parameters := congrArg FunctionType.parameters same
        have result := congrArg FunctionType.result same
        change function.parameters.map Prod.snd = _ at parameters
        change function.returnType = _ at result
        have typed : ExprsHaveTypes program context arguments.erase (function.parameters.map Prod.snd) := by
          simpa only [parameters] using arguments.wellTyped linked valid
        simpa only [Expr.erase, result] using ExprHasType.call function found typed
    | .printI32 argument => .printI32 (argument.wellTyped linked valid)
    | .assert argument => .assert (argument.wellTyped linked valid)
    | .i32ArrayDataPtr array => .i32ArrayDataPtr (array.wellTyped linked valid)
    | .i32SliceFromRawParts pointer length => .i32SliceFromRawParts (pointer.wellTyped linked valid) (length.wellTyped linked valid)
    | .typedSliceFromRawParts _ declared pointer length =>
        .typedSliceFromRawParts (linked.nominal declared) (pointer.wellTyped linked valid) (length.wellTyped linked valid)
    | .i32SliceDataPtr slice => .i32SliceDataPtr (slice.wellTyped linked valid)
    | .stringDataPtr string => .stringDataPtr (string.wellTyped linked valid)
    | .alloc size alignment => .alloc (size.wellTyped linked valid) (alignment.wellTyped linked valid)
    | .realloc pointer oldSize newSize alignment => .realloc (pointer.wellTyped linked valid)
        (oldSize.wellTyped linked valid) (newSize.wellTyped linked valid) (alignment.wellTyped linked valid)
    | .dealloc pointer size alignment => .dealloc (pointer.wellTyped linked valid) (size.wellTyped linked valid) (alignment.wellTyped linked valid)
    | .loadByte pointer offset => .loadByte (pointer.wellTyped linked valid) (offset.wellTyped linked valid)
    | .storeByte pointer offset value => .storeByte (pointer.wellTyped linked valid) (offset.wellTyped linked valid) (value.wellTyped linked valid)

  theorem Place.wellTyped (place : Place signature scope type) (linked : signature.Realizes program)
      (valid : scope.Realizes context) :
      PlaceHasType program context place.erase type :=
    match place with
    | .local binding => .local (valid _ _ binding.found)
    | .field base record _ found => .field (base.wellTyped linked valid) record.declaration
        (linked.structure record.found) (by simpa only [record.fieldsMatch] using found)
    | .indexArray base index integer => .indexArray (base.wellTyped linked valid) (index.wellTyped linked valid) integer
    | .indexSlice base index integer => .indexSlice (base.wellTyped linked valid) (index.wellTyped linked valid) integer

  theorem Exprs.wellTyped (expressions : Exprs signature scope types) (linked : signature.Realizes program)
      (valid : scope.Realizes context) :
      ExprsHaveTypes program context expressions.erase types :=
    match expressions with
    | .nil => .nil
    | .cons head tail => .cons (head.wellTyped linked valid) (tail.wellTyped linked valid)

  theorem Arms.wellTyped (arms : Arms signature scope input output) (linked : signature.Realizes program)
      (valid : scope.Realizes context) :
      MatchArmsHaveType program context arms.erase input output :=
    match arms with
    | .one pattern body => .one (pattern.wellTyped linked) (body.wellTyped linked (valid.bindAll _))
    | .cons pattern body tail => .cons (pattern.wellTyped linked) (body.wellTyped linked (valid.bindAll _)) (tail.wellTyped linked valid)
end

end Lanius.TypedIR.Intrinsic
