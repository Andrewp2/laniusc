import Lanius.Extraction.CoreChecker
import Lanius.Typing

namespace Lanius.Extraction.CoreTyping

open Lanius
open Lanius.Core
open Lanius.Typing

structure Evidence (property : Prop) : Type where
  proof : property

instance : Coe (Evidence property) property where
  coe evidence := evidence.proof

structure InferredValue (program : Program) (value : Value) where
  type : Ty
  typed : ValueHasType program value type

structure InferredExpr (program : Program) (context : Context) (expression : Expr) where
  type : Ty
  typed : ExprHasType program context expression type

structure InferredPlace (program : Program) (context : Context) (place : Place) where
  type : Ty
  typed : PlaceHasType program context place type

structure InferredPattern (program : Program) (pattern : Pattern) (expected : Ty) where
  bindings : List (VarId × Ty)
  typed : PatternHasType program pattern expected bindings

structure CheckedPatterns (program : Program) (patterns : List Pattern)
    (types : List Ty) where
  bindings : List (VarId × Ty)
  typed : PatternsHaveTypes program patterns types bindings

structure InferredMatchArms (program : Program) (context : Context)
    (arms : List (Pattern × Expr)) (scrutineeType : Ty) where
  resultType : Ty
  typed : MatchArmsHaveType program context arms scrutineeType resultType

def arithmetic? : (type : Ty) → Option (Evidence (ArithmeticTy type))
  | .scalar (.signed type) => some ⟨.signed type⟩
  | .scalar (.unsigned type) => some ⟨.unsigned type⟩
  | .scalar .f32 => some ⟨.f32⟩
  | .scalar .f64 => some ⟨.f64⟩
  | .scalar .char => some ⟨.character⟩
  | _ => none

def negatable? : (type : Ty) → Option (Evidence (NegatableTy type))
  | .scalar (.signed type) => some ⟨.signed type⟩
  | .scalar (.unsigned type) => some ⟨.unsigned type⟩
  | .scalar .f32 => some ⟨.f32⟩
  | .scalar .f64 => some ⟨.f64⟩
  | .scalar .char => some ⟨.character⟩
  | _ => none

def integer? : (type : Ty) → Option (Evidence (IntegerTy type))
  | .scalar (.signed type) => some ⟨.signed type⟩
  | .scalar (.unsigned type) => some ⟨.unsigned type⟩
  | .scalar .char => some ⟨.character⟩
  | _ => none

def ordered? : (type : Ty) → Option (Evidence (OrderedTy type))
  | .scalar (.signed type) => some ⟨.signed type⟩
  | .scalar (.unsigned type) => some ⟨.unsigned type⟩
  | .scalar .f32 => some ⟨.f32⟩
  | .scalar .f64 => some ⟨.f64⟩
  | .scalar .char => some ⟨.character⟩
  | _ => none

def equality? : (type : Ty) → Option (Evidence (EqualityTy type))
  | .scalar .bool => some ⟨.boolean⟩
  | .scalar (.signed type) => some ⟨.signed type⟩
  | .scalar (.unsigned type) => some ⟨.unsigned type⟩
  | .scalar .f32 => some ⟨.f32⟩
  | .scalar .f64 => some ⟨.f64⟩
  | .scalar .char => some ⟨.character⟩
  | .scalar .rawPtr => some ⟨.pointer⟩
  | _ => none

def pointerOffset? : (type : Ty) → Option (Evidence (PointerOffsetTy type))
  | .scalar (.signed type) => some ⟨.signed type⟩
  | .scalar (.unsigned type) => some ⟨.unsigned type⟩
  | .scalar .char => some ⟨.character⟩
  | _ => none

def scalarCast? (source target : ScalarTy) : Option (Evidence (ScalarCast source target)) :=
  match source, target with
  | .signed source, .signed target => some ⟨.signedToSigned source target⟩
  | .signed source, .unsigned target => some ⟨.signedToUnsigned source target⟩
  | .unsigned source, .signed target => some ⟨.unsignedToSigned source target⟩
  | .unsigned source, .unsigned target => some ⟨.unsignedToUnsigned source target⟩
  | .signed source, .f32 => some ⟨.signedToF32 source⟩
  | .signed source, .f64 => some ⟨.signedToF64 source⟩
  | .unsigned source, .f32 => some ⟨.unsignedToF32 source⟩
  | .unsigned source, .f64 => some ⟨.unsignedToF64 source⟩
  | .char, .signed target => some ⟨.charToSigned target⟩
  | .char, .unsigned target => some ⟨.charToUnsigned target⟩
  | .char, .f32 => some ⟨.charToF32⟩
  | .char, .f64 => some ⟨.charToF64⟩
  | .f32, .f64 => some ⟨.f32ToF64⟩
  | .f64, .f32 => some ⟨.f64ToF32⟩
  | _, _ => none

structure UnaryTyping (operation : UnaryOp) (input : Ty) where
  output : Ty
  typed : UnaryOpHasType operation input output

def unaryTyping? (operation : UnaryOp) (input : Ty) : Option (UnaryTyping operation input) :=
  match operation with
  | .positive => do
      let proof ← arithmetic? input
      pure ⟨input, .positive proof⟩
  | .logicalNot =>
      match input with
      | .scalar .bool => some ⟨.scalar .bool, .logicalNot⟩
      | _ => none
  | .negate => do
      let proof ← negatable? input
      pure ⟨input, .negate proof⟩

structure BinaryTyping (operation : BinaryOp) (left right : Ty) where
  output : Ty
  typed : BinaryOpHasType operation left right output

def sameOperandBinary?
    (left right : Ty)
    (make : (type : Ty) → Option (BinaryTyping operation type type)) :
    Option (BinaryTyping operation left right) := do
  if same : left = right then
    let ⟨output, proof⟩ ← make left
    pure ⟨output, same ▸ proof⟩
  else none

def binaryTyping? (operation : BinaryOp) (left right : Ty) :
    Option (BinaryTyping operation left right) :=
  match operation with
  | .logicalAnd =>
      match left, right with
      | .scalar .bool, .scalar .bool => some ⟨.scalar .bool, .logicalAnd⟩
      | _, _ => none
  | .logicalOr =>
      match left, right with
      | .scalar .bool, .scalar .bool => some ⟨.scalar .bool, .logicalOr⟩
      | _, _ => none
  | .equal => sameOperandBinary? left right fun type => do
      pure ⟨.scalar .bool, .equal (← equality? type)⟩
  | .notEqual => sameOperandBinary? left right fun type => do
      pure ⟨.scalar .bool, .notEqual (← equality? type)⟩
  | .less => sameOperandBinary? left right fun type => do
      pure ⟨.scalar .bool, .less (← ordered? type)⟩
  | .lessEqual => sameOperandBinary? left right fun type => do
      pure ⟨.scalar .bool, .lessEqual (← ordered? type)⟩
  | .greater => sameOperandBinary? left right fun type => do
      pure ⟨.scalar .bool, .greater (← ordered? type)⟩
  | .greaterEqual => sameOperandBinary? left right fun type => do
      pure ⟨.scalar .bool, .greaterEqual (← ordered? type)⟩
  | .add =>
      if pointer : left = .scalar .rawPtr then do
        let offset ← pointerOffset? right
        pure ⟨.scalar .rawPtr, pointer ▸ BinaryOpHasType.pointerAdd offset⟩
      else sameOperandBinary? left right fun type => do
        pure ⟨type, .add (← arithmetic? type)⟩
  | .subtract =>
      if pointer : left = .scalar .rawPtr then do
        let offset ← pointerOffset? right
        pure ⟨.scalar .rawPtr, pointer ▸ BinaryOpHasType.pointerSubtract offset⟩
      else sameOperandBinary? left right fun type => do
        pure ⟨type, .subtract (← arithmetic? type)⟩
  | .multiply => sameOperandBinary? left right fun type => do
      pure ⟨type, .multiply (← arithmetic? type)⟩
  | .divide => sameOperandBinary? left right fun type => do
      pure ⟨type, .divide (← arithmetic? type)⟩
  | .remainder => sameOperandBinary? left right fun type => do
      pure ⟨type, .remainder (← integer? type)⟩
  | .bitAnd => sameOperandBinary? left right fun type => do
      pure ⟨type, .bitAnd (← integer? type)⟩
  | .bitOr => sameOperandBinary? left right fun type => do
      pure ⟨type, .bitOr (← integer? type)⟩
  | .bitXor => sameOperandBinary? left right fun type => do
      pure ⟨type, .bitXor (← integer? type)⟩
  | .shiftLeft => sameOperandBinary? left right fun type => do
      pure ⟨type, .shiftLeft (← integer? type)⟩
  | .shiftRight => sameOperandBinary? left right fun type => do
      pure ⟨type, .shiftRight (← integer? type)⟩

def assignTyping? (operation : AssignOp) (type : Ty) :
    Option (Evidence (AssignOpHasType operation type)) :=
  match operation with
  | .set => some ⟨.set⟩
  | .add => (fun proof => ⟨.add proof⟩) <$> arithmetic? type
  | .subtract => (fun proof => ⟨.subtract proof⟩) <$> arithmetic? type
  | .multiply => (fun proof => ⟨.multiply proof⟩) <$> arithmetic? type
  | .divide => (fun proof => ⟨.divide proof⟩) <$> arithmetic? type
  | .remainder => (fun proof => ⟨.remainder proof⟩) <$> integer? type
  | .bitXor => (fun proof => ⟨.bitXor proof⟩) <$> integer? type
  | .shiftLeft => (fun proof => ⟨.shiftLeft proof⟩) <$> integer? type
  | .shiftRight => (fun proof => ⟨.shiftRight proof⟩) <$> integer? type
  | .bitAnd => (fun proof => ⟨.bitAnd proof⟩) <$> integer? type
  | .bitOr => (fun proof => ⟨.bitOr proof⟩) <$> integer? type

mutual
  def checkValue (program : Program) :
      (value : Value) → (type : Ty) →
        Option (Evidence (ValueHasType program value type))
    | .unit, .unit => some ⟨.unit⟩
    | .boolean value, .scalar .bool => some ⟨.boolean value⟩
    | .signed actual value, .scalar (.signed expected) =>
        if same : actual = expected then
          if lower : signedMin program.target actual ≤ value then
            if upper : value ≤ signedMax program.target actual then
              some ⟨same ▸ ValueHasType.signed actual value lower upper⟩
            else none
          else none
        else none
    | .unsigned actual value, .scalar (.unsigned expected) =>
        if same : actual = expected then
          if upper : value ≤ unsignedMax program.target actual then
            some ⟨same ▸ ValueHasType.unsigned actual value upper⟩
          else none
        else none
    | .f32Bits bits, .scalar .f32 => some ⟨.f32Bits bits⟩
    | .f64Bits bits, .scalar .f64 => some ⟨.f64Bits bits⟩
    | .character value, .scalar .char => some ⟨.character value⟩
    | .string value, .scalar .string => some ⟨.string value⟩
    | .pointer address, .scalar .rawPtr => some ⟨.pointer address⟩
    | .array values, .array element count => do
        if length : values.length = count then
          let elements ← checkValues program values (List.replicate count element)
          pure ⟨.array values element length elements⟩
        else none
    | .slice actual cell projections start length, .slice expected =>
        if same : actual = expected then
          some ⟨same ▸ ValueHasType.slice actual cell projections start length⟩
        else none
    | .structure id values, .structure expected => do
        if same : id = expected then
          match found : program.structure? id with
          | none => none
          | some declaration =>
              if declarationId : declaration.id = id then do
                let fields ← checkValues program values declaration.fields
                have foundAtDeclaration :
                    program.structure? declaration.id = some declaration := by
                  simpa [declarationId] using found
                pure ⟨same ▸ declarationId ▸
                  ValueHasType.structure declaration foundAtDeclaration fields⟩
              else none
        else none
    | .enumeration id variant values, .enumeration expected => do
        if same : id = expected then
          match found : program.enumeration? id with
          | none => none
          | some declaration =>
              if declarationId : declaration.id = id then
                match variantFound : declaration.variants[variant]? with
                | none => none
                | some payloadTypes => do
                    let payload ← checkValues program values payloadTypes
                    have foundAtDeclaration :
                        program.enumeration? declaration.id = some declaration := by
                      simpa [declarationId] using found
                    pure ⟨same ▸ declarationId ▸
                      ValueHasType.enumeration declaration foundAtDeclaration
                        variantFound payload⟩
              else none
        else none
    | .reference actual cell projections, .reference expected =>
        if same : actual = expected then
          some ⟨same ▸ ValueHasType.reference actual cell projections⟩
        else none
    | _, _ => none

  def checkValues (program : Program) :
      (values : List Value) → (types : List Ty) →
        Option (Evidence (ValuesHaveTypes program values types))
    | [], [] => some ⟨.nil⟩
    | value :: values, type :: types => do
        pure ⟨.cons (← checkValue program value type) (← checkValues program values types)⟩
    | _, _ => none
end

def inferValue (program : Program) (value : Value) : Option (InferredValue program value) :=
  match value with
  | .unit => some ⟨.unit, .unit⟩
  | .boolean boolean => some ⟨.scalar .bool, .boolean boolean⟩
  | .signed type integer =>
      if lower : signedMin program.target type ≤ integer then
        if upper : integer ≤ signedMax program.target type then
          some ⟨.scalar (.signed type), .signed type integer lower upper⟩
        else none
      else none
  | .unsigned type integer =>
      if upper : integer ≤ unsignedMax program.target type then
        some ⟨.scalar (.unsigned type), .unsigned type integer upper⟩
      else none
  | .f32Bits bits => some ⟨.scalar .f32, .f32Bits bits⟩
  | .f64Bits bits => some ⟨.scalar .f64, .f64Bits bits⟩
  | .character character => some ⟨.scalar .char, .character character⟩
  | .string string => some ⟨.scalar .string, .string string⟩
  | .pointer address => some ⟨.scalar .rawPtr, .pointer address⟩
  | .array [] => none
  | .array (head :: tail) => do
      let ⟨elementType, headTyped⟩ ← inferValue program head
      let tailTyped ← checkValues program tail (List.replicate tail.length elementType)
      pure ⟨.array elementType (head :: tail).length,
        .array (head :: tail) elementType rfl (.cons headTyped tailTyped)⟩
  | .slice elementType cell projections start length =>
      some ⟨.slice elementType, .slice elementType cell projections start length⟩
  | .structure id fields => do
      match found : program.structure? id with
      | none => none
      | some declaration =>
          if declarationId : declaration.id = id then do
            let typedFields ← checkValues program fields declaration.fields
            have foundAtDeclaration :
                program.structure? declaration.id = some declaration := by
              simpa [declarationId] using found
            pure ⟨.structure id, declarationId ▸
              ValueHasType.structure declaration foundAtDeclaration typedFields⟩
          else none
  | .enumeration id variant payload => do
      match found : program.enumeration? id with
      | none => none
      | some declaration =>
          if declarationId : declaration.id = id then
            match variantFound : declaration.variants[variant]? with
            | none => none
            | some payloadTypes => do
                let typedPayload ← checkValues program payload payloadTypes
                have foundAtDeclaration :
                    program.enumeration? declaration.id = some declaration := by
                  simpa [declarationId] using found
                pure ⟨.enumeration id, declarationId ▸
                  ValueHasType.enumeration declaration foundAtDeclaration
                    variantFound typedPayload⟩
          else none
  | .reference referent cell projections =>
      some ⟨.reference referent, .reference referent cell projections⟩

/-- Compare a retained inference result without traversing its expression again. -/
def InferredExpr.check (inferred : InferredExpr program context expression) (expected : Ty) :
    Option (Evidence (ExprHasType program context expression expected)) :=
  if same : inferred.type = expected then some ⟨same ▸ inferred.typed⟩ else none

def InferredPlace.check (inferred : InferredPlace program context place) (expected : Ty) :
    Option (Evidence (PlaceHasType program context place expected)) :=
  if same : inferred.type = expected then some ⟨same ▸ inferred.typed⟩ else none

mutual
  def inferExpr (program : Program) (context : Context) :
      (expression : Expr) → Option (InferredExpr program context expression)
    | .value value => do
        if literal : Value.isLiteral value = true then
          let ⟨type, typed⟩ ← inferValue program value
          pure ⟨type, .value typed literal⟩
        else none
    | .local id =>
        match found : context id with
        | some type => some ⟨type, .local found⟩
        | none => none
    | .cast target operand => do
        let ⟨operandType, operandTyped⟩ ← inferExpr program context operand
        match operandType, operandTyped with
        | .scalar source, operandTyped => do
            let conversion ← scalarCast? source target
            pure ⟨.scalar target, .cast operandTyped conversion.proof⟩
        | _, _ => none
    | .unary operation operand => do
        let ⟨input, operandTyped⟩ ← inferExpr program context operand
        let ⟨output, operationTyped⟩ ← unaryTyping? operation input
        pure ⟨output, .unary operandTyped operationTyped⟩
    | .binary operation left right => do
        let ⟨leftType, leftTyped⟩ ← inferExpr program context left
        let ⟨rightType, rightTyped⟩ ← inferExpr program context right
        let ⟨output, operationTyped⟩ ← binaryTyping? operation leftType rightType
        pure ⟨output, .binary leftTyped rightTyped operationTyped⟩
    | .array elementType elements => do
        let typed ← checkExprs program context elements
          (List.replicate elements.length elementType)
        pure ⟨.array elementType elements.length, .array typed⟩
    | .arrayToSlice elementType array => do
        let ⟨arrayType, arrayTyped⟩ ← inferExpr program context array
        match arrayType, arrayTyped with
        | .array actual length, arrayTyped =>
            if same : actual = elementType then do
              pure ⟨.slice elementType, .arrayToSlice (same ▸ arrayTyped)⟩
            else none
        | _, _ => none
    | .index base index => do
        let ⟨baseType, baseTyped⟩ ← inferExpr program context base
        let ⟨indexType, indexTyped⟩ ← inferExpr program context index
        let integerIndex ← integer? indexType
        match baseType, baseTyped with
        | .array elementType _, baseTyped =>
            pure ⟨elementType, .indexArray baseTyped indexTyped integerIndex.proof⟩
        | .slice elementType, baseTyped =>
            pure ⟨elementType, .indexSlice baseTyped indexTyped integerIndex.proof⟩
        | _, _ => none
    | .structValue id fields => do
        match found : program.structure? id with
        | none => none
        | some declaration =>
            if declarationId : declaration.id = id then do
              let typed ← checkExprs program context fields declaration.fields
              have foundAtDeclaration :
                  program.structure? declaration.id = some declaration := by
                simpa [declarationId] using found
              pure ⟨.structure id, declarationId ▸
                ExprHasType.structValue declaration foundAtDeclaration typed⟩
            else none
    | .field base field => do
        let ⟨baseType, baseTyped⟩ ← inferExpr program context base
        match baseType, baseTyped with
        | .structure id, baseTyped => do
            match found : program.structure? id with
            | none => none
            | some declaration =>
                match fieldFound : declaration.fields[field]? with
                | none => none
                | some type =>
                    pure ⟨type, .field baseTyped declaration found fieldFound⟩
        | _, _ => none
    | .enumValue id variant payload => do
        match found : program.enumeration? id with
        | none => none
        | some declaration =>
            if declarationId : declaration.id = id then
              match variantFound : declaration.variants[variant]? with
              | none => none
              | some payloadTypes => do
                  let typed ← checkExprs program context payload payloadTypes
                  have foundAtDeclaration :
                      program.enumeration? declaration.id = some declaration := by
                    simpa [declarationId] using found
                  pure ⟨.enumeration id, declarationId ▸
                    ExprHasType.enumValue declaration foundAtDeclaration
                      variantFound typed⟩
            else none
    | .matchValue scrutinee arms => do
        let ⟨scrutineeType, scrutineeTyped⟩ ← inferExpr program context scrutinee
        let ⟨resultType, armsTyped⟩ ← inferMatchArms program context arms scrutineeType
        pure ⟨resultType, .matchValue scrutineeTyped armsTyped⟩
    | .assign operation place value => do
        let ⟨type, placeTyped⟩ ← inferPlace program context place
        let valueTyped ← (← inferExpr program context value).check type
        pure ⟨.unit, .assign placeTyped valueTyped (← assignTyping? operation type)⟩
    | .borrow referent place => do
        let placeTyped ← (← inferPlace program context place).check referent
        pure ⟨.reference referent, .borrow placeTyped⟩
    | .dereference reference => do
        let ⟨type, referenceTyped⟩ ← inferExpr program context reference
        match type, referenceTyped with
        | .reference referent, referenceTyped => pure ⟨referent, .dereference referenceTyped⟩
        | _, _ => none
    | .constant id => do
        match found : program.constant? id with
        | none => none
        | some declaration => pure ⟨declaration.type, .constant declaration found⟩
    | .call id arguments => do
        match found : program.function? id with
        | none => none
        | some function => do
            let typed ← checkExprs program context arguments
              (function.parameters.map Prod.snd)
            pure ⟨function.returnType, .call function found typed⟩
    | .intrinsic .printI32 argument => do
        pure ⟨.unit, .printI32 (← (← inferExpr program context argument).check
          (.scalar (.signed .i32)))⟩
    | .intrinsic .assert argument => do
        pure ⟨.unit, .assert (← (← inferExpr program context argument).check (.scalar .bool))⟩
    | .i32ArrayDataPtr array => do
        let ⟨type, arrayTyped⟩ ← inferExpr program context array
        match type, arrayTyped with
        | .array (.scalar (.signed .i32)) _, arrayTyped =>
            pure ⟨.scalar .rawPtr, .i32ArrayDataPtr arrayTyped⟩
        | _, _ => none
    | .i32SliceFromRawParts pointer length => do
        pure ⟨.slice (.scalar (.signed .i32)), .i32SliceFromRawParts
          (← (← inferExpr program context pointer).check (.scalar .rawPtr))
          (← (← inferExpr program context length).check (.scalar (.signed .i32)))⟩
    | .i32SliceDataPtr slice => do
        pure ⟨.scalar .rawPtr, .i32SliceDataPtr
          (← (← inferExpr program context slice).check (.slice (.scalar (.signed .i32))))⟩
    | .stringDataPtr string => do
        pure ⟨.scalar .rawPtr, .stringDataPtr
          (← (← inferExpr program context string).check (.scalar .string))⟩
    | .alloc size alignment => do
        pure ⟨.scalar .rawPtr, .alloc
          (← (← inferExpr program context size).check (.scalar (.unsigned .usize)))
          (← (← inferExpr program context alignment).check (.scalar (.unsigned .usize)))⟩
    | .realloc pointer oldSize newSize alignment => do
        pure ⟨.scalar .rawPtr, .realloc
          (← (← inferExpr program context pointer).check (.scalar .rawPtr))
          (← (← inferExpr program context oldSize).check (.scalar (.unsigned .usize)))
          (← (← inferExpr program context newSize).check (.scalar (.unsigned .usize)))
          (← (← inferExpr program context alignment).check (.scalar (.unsigned .usize)))⟩
    | .dealloc pointer size alignment => do
        pure ⟨.unit, .dealloc
          (← (← inferExpr program context pointer).check (.scalar .rawPtr))
          (← (← inferExpr program context size).check (.scalar (.unsigned .usize)))
          (← (← inferExpr program context alignment).check (.scalar (.unsigned .usize)))⟩
    | .loadByte pointer offset => do
        pure ⟨.scalar (.unsigned .u8), .loadByte
          (← (← inferExpr program context pointer).check (.scalar .rawPtr))
          (← (← inferExpr program context offset).check (.scalar (.unsigned .usize)))⟩
    | .storeByte pointer offset value => do
        pure ⟨.unit, .storeByte
          (← (← inferExpr program context pointer).check (.scalar .rawPtr))
          (← (← inferExpr program context offset).check (.scalar (.unsigned .usize)))
          (← (← inferExpr program context value).check (.scalar (.unsigned .u8)))⟩
  termination_by structural expression => expression

  def checkExprs (program : Program) (context : Context) :
      (expressions : List Expr) → (types : List Ty) →
        Option (Evidence (ExprsHaveTypes program context expressions types))
    | [], [] => some ⟨.nil⟩
    | expression :: expressions, type :: types => do
        pure ⟨.cons (← (← inferExpr program context expression).check type)
          (← checkExprs program context expressions types)⟩
    | _, _ => none
  termination_by structural expressions _ => expressions

  def inferPlace (program : Program) (context : Context) :
      (place : Place) → Option (InferredPlace program context place)
    | .local id =>
        match found : context id with
        | some type => some ⟨type, .local found⟩
        | none => none
    | .field base field => do
        let ⟨baseType, baseTyped⟩ ← inferPlace program context base
        match baseType, baseTyped with
        | .structure id, baseTyped => do
            match found : program.structure? id with
            | none => none
            | some declaration =>
                match fieldFound : declaration.fields[field]? with
                | none => none
                | some type => do
                    pure ⟨type, .field baseTyped declaration found fieldFound⟩
        | _, _ => none
    | .index base index => do
        let ⟨baseType, baseTyped⟩ ← inferPlace program context base
        let ⟨indexType, indexTyped⟩ ← inferExpr program context index
        let integerIndex ← integer? indexType
        match baseType, baseTyped with
        | .array elementType _, baseTyped =>
            pure ⟨elementType, .indexArray baseTyped indexTyped integerIndex.proof⟩
        | .slice elementType, baseTyped =>
            pure ⟨elementType, .indexSlice baseTyped indexTyped integerIndex.proof⟩
        | _, _ => none
  termination_by structural place => place

  def inferPattern (program : Program) :
      (pattern : Pattern) → (expected : Ty) →
        Option (InferredPattern program pattern expected)
    | .wildcard, _ => some ⟨[], .wildcard⟩
    | .bind id, expected => some ⟨[(id, expected)], .bind id⟩
    | .literal value, expected => do
        pure ⟨[], .literal (← checkValue program value expected)⟩
    | .enumVariant typeId variant payload, .enumeration expectedId => do
        if same : typeId = expectedId then
          match found : program.enumeration? typeId with
          | none => none
          | some declaration =>
              match variantFound : declaration.variants[variant]? with
              | none => none
              | some payloadTypes => do
                  let ⟨bindings, payloadTyped⟩ ←
                    checkPatterns program payload payloadTypes
                  pure ⟨bindings, same ▸ PatternHasType.enumVariant declaration
                    found variantFound payloadTyped⟩
        else none
    | .enumVariant _ _ _, _ => none

  def checkPatterns (program : Program) :
      (patterns : List Pattern) → (types : List Ty) →
        Option (CheckedPatterns program patterns types)
    | [], [] => some ⟨[], .nil⟩
    | pattern :: patterns, type :: types => do
        let ⟨headBindings, head⟩ ← inferPattern program pattern type
        let ⟨tailBindings, tail⟩ ← checkPatterns program patterns types
        pure ⟨headBindings ++ tailBindings, .cons head tail⟩
    | _, _ => none

  def checkMatchArms (program : Program) (context : Context) :
      (arms : List (Pattern × Expr)) → (scrutineeType resultType : Ty) →
        Option (Evidence
          (MatchArmsHaveType program context arms scrutineeType resultType))
    | [(pattern, body)], scrutineeType, resultType => do
        let ⟨bindings, patternTyped⟩ ← inferPattern program pattern scrutineeType
        let bodyTyped ← (← inferExpr program (context.bindAll bindings) body).check resultType
        pure ⟨.one patternTyped bodyTyped⟩
    | (pattern, body) :: (nextPattern, nextBody) :: rest,
        scrutineeType, resultType => do
        let ⟨bindings, patternTyped⟩ ← inferPattern program pattern scrutineeType
        let bodyTyped ← (← inferExpr program (context.bindAll bindings) body).check resultType
        let tailTyped ← checkMatchArms program context
          ((nextPattern, nextBody) :: rest) scrutineeType resultType
        pure ⟨.cons patternTyped bodyTyped.proof tailTyped.proof⟩
    | _, _, _ => none
  termination_by structural arms _ _ => arms

  def inferMatchArms (program : Program) (context : Context) :
      (arms : List (Pattern × Expr)) → (scrutineeType : Ty) →
        Option (InferredMatchArms program context arms scrutineeType)
    | [(pattern, body)], scrutineeType => do
        let ⟨bindings, patternTyped⟩ ← inferPattern program pattern scrutineeType
        let ⟨resultType, bodyTyped⟩ ← inferExpr program (context.bindAll bindings) body
        pure ⟨resultType, .one patternTyped bodyTyped⟩
    | (pattern, body) :: (nextPattern, nextBody) :: rest, scrutineeType => do
        let ⟨bindings, patternTyped⟩ ← inferPattern program pattern scrutineeType
        let ⟨resultType, bodyTyped⟩ ← inferExpr program (context.bindAll bindings) body
        let tailTyped ← checkMatchArms program context
          ((nextPattern, nextBody) :: rest) scrutineeType resultType
        pure ⟨resultType, .cons patternTyped bodyTyped tailTyped.proof⟩
    | _, _ => none
  termination_by structural arms _ => arms
end

def checkExpr (program : Program) (context : Context) (expression : Expr) (expected : Ty) :
    Option (Evidence (ExprHasType program context expression expected)) := do
  (← inferExpr program context expression).check expected

def checkPlace (program : Program) (context : Context) (place : Place) (expected : Ty) :
    Option (Evidence (PlaceHasType program context place expected)) := do
  (← inferPlace program context place).check expected

def checkOptionalExpr (program : Program) (context : Context) (type : Ty) :
    (expression : Option Expr) →
      Option (Evidence (OptionExprHasType program context type expression))
  | none => some ⟨.none⟩
  | some expression => do
      pure ⟨.some (← checkExpr program context expression type)⟩

def checkStmt (program : Program) (returnType : Ty) :
    (context : Context) → (inLoop : Bool) → (statement : Stmt) →
      Option (Evidence (StmtHasType program returnType context inLoop statement))
  | _, _, .skip => some ⟨.skip⟩
  | context, _, .expression expression => do
      let ⟨_, typed⟩ ← inferExpr program context expression
      pure ⟨.expression typed⟩
  | context, inLoop, .sequence first second => do
      pure ⟨.sequence
        (← checkStmt program returnType context inLoop first)
        (← checkStmt program returnType context inLoop second)⟩
  | context, inLoop, .letLocal id type initializer body => do
      pure ⟨.letLocal
        (← checkExpr program context initializer type)
        (← checkStmt program returnType (context.bind id type) inLoop body)⟩
  | context, inLoop, .letUninitialized id type body => do
      pure ⟨.letUninitialized
        (← checkStmt program returnType (context.bind id type) inLoop body)⟩
  | context, inLoop, .ifThenElse condition thenBranch elseBranch => do
      pure ⟨.ifThenElse
        (← checkExpr program context condition (.scalar .bool))
        (← checkStmt program returnType context inLoop thenBranch)
        (← checkStmt program returnType context inLoop elseBranch)⟩
  | context, _, .whileLoop condition body => do
      pure ⟨.whileLoop
        (← checkExpr program context condition (.scalar .bool))
        (← checkStmt program returnType context true body)⟩
  | context, _, .forValues id iterable body => do
      let ⟨iterableType, iterableTyped⟩ ← inferExpr program context iterable
      match iterableType, iterableTyped with
      | .array elementType _, iterableTyped =>
          let bodyTyped ← checkStmt program returnType
            (context.bind id elementType) true body
          pure ⟨.forArray iterableTyped bodyTyped.proof⟩
      | .slice elementType, iterableTyped =>
          let bodyTyped ← checkStmt program returnType
            (context.bind id elementType) true body
          pure ⟨.forSlice iterableTyped bodyTyped.proof⟩
      | _, _ => none
  | context, _, .forRange id start stop _inclusive body => do
      pure ⟨.forRange
        (← checkExpr program context start (.scalar (.signed .i32)))
        (← checkOptionalExpr program context (.scalar (.signed .i32)) stop)
        (← checkStmt program returnType
          (context.bind id (.scalar (.signed .i32))) true body)⟩
  | _, _, .returnValue none =>
      if unit : returnType = .unit then some ⟨.returnUnit unit⟩ else none
  | context, _, .returnValue (some value) =>
      do pure ⟨.returnValue (← checkExpr program context value returnType)⟩
  | _, true, .breakLoop => some ⟨.breakLoop⟩
  | _, false, .breakLoop => none
  | _, true, .continueLoop => some ⟨.continueLoop⟩
  | _, false, .continueLoop => none

def definitelyReturns? : (statement : Stmt) →
    Option (Evidence (DefinitelyReturns statement))
  | .returnValue value => some ⟨.returnValue (value := value)⟩
  | .sequence first second =>
      match definitelyReturns? first with
      | some proof => some ⟨.sequenceLeft proof⟩
      | none => do pure ⟨.sequenceRight (← definitelyReturns? second)⟩
  | .letLocal _id _type _initializer body =>
      do pure ⟨.letLocal (← definitelyReturns? body)⟩
  | .letUninitialized _id _type body =>
      do pure ⟨.letUninitialized (← definitelyReturns? body)⟩
  | .ifThenElse _condition thenBranch elseBranch => do
      pure ⟨.ifThenElse (← definitelyReturns? thenBranch)
        (← definitelyReturns? elseBranch)⟩
  | _ => none

def checkFunction (program : Program) (function : Function) :
    Option (Evidence (FunctionWellTyped program function)) :=
  match bodyFound : function.body, externalFound : function.external with
  | none, some (.host service) => do
      if parameters : function.parameters.map Prod.snd = service.parameterTypes then
        if returned : function.returnType = service.returnType then
          pure ⟨by
            unfold FunctionWellTyped
            rw [bodyFound, externalFound]
            exact ⟨parameters, returned⟩⟩
        else none
      else none
  | none, some (.panic) | none, some (.unreachable) => do
      if parameters : function.parameters = [] then
        if returned : function.returnType = .unit then
          pure ⟨by
            unfold FunctionWellTyped
            rw [bodyFound, externalFound]
            exact ⟨parameters, returned⟩⟩
        else none
      else none
  | none, some (.unavailable _) | none, some (.opaque _) =>
      some ⟨by
        unfold FunctionWellTyped
        rw [bodyFound, externalFound]
        trivial⟩
  | some body, none => do
      let typed ← checkStmt program function.returnType
        (parameterContext function.parameters) false body
      let returned : Evidence
          (function.returnType = .unit ∨ DefinitelyReturns body) ←
        if unit : function.returnType = .unit then pure ⟨Or.inl unit⟩
        else do pure ⟨Or.inr (← definitelyReturns? body)⟩
      pure ⟨by
        unfold FunctionWellTyped
        rw [bodyFound]
        exact ⟨externalFound, typed.proof, returned.proof⟩⟩
  | _, _ => none

def checkConstant (program : Program) (constant : Constant) :
    Option (Evidence (ConstantWellTyped program constant)) :=
  checkValue program constant.value constant.type

def checkConstants (program : Program) :
    (constants : List Constant) →
      Option (Evidence (∀ constant ∈ constants, ConstantWellTyped program constant))
  | [] => some ⟨by simp⟩
  | head :: tail => do
      let headTyped ← checkConstant program head
      let tailTyped ← checkConstants program tail
      pure ⟨by
        intro constant member
        rcases List.mem_cons.mp member with rfl | inTail
        · exact headTyped.proof
        · exact tailTyped.proof _ inTail⟩

def checkFunctions (program : Program) :
    (functions : List Function) →
      Option (Evidence (∀ function ∈ functions, FunctionWellTyped program function))
  | [] => some ⟨by simp⟩
  | head :: tail => do
      let headTyped ← checkFunction program head
      let tailTyped ← checkFunctions program tail
      pure ⟨by
        intro function member
        rcases List.mem_cons.mp member with rfl | inTail
        · exact headTyped.proof
        · exact tailTyped.proof _ inTail⟩

def checkProgram (program : Program) : Option (Evidence (ProgramWellTyped program)) := do
  let constants ← checkConstants program program.constants
  let functions ← checkFunctions program program.functions
  pure ⟨⟨constants.proof, functions.proof⟩⟩

/-- A decoded Core proposal together with the two facts consumers need:
    it is the structurally checked decoding of this artifact, and it satisfies
    the repository's existing Core typing judgment. -/
structure CheckedCoreArtifact (artifact : Artifact) where
  program : Program
  decoded : decodeCheckedCore artifact = some program
  wellTyped : ProgramWellTyped program

def decodeTypedCore (artifact : Artifact) : Option (CheckedCoreArtifact artifact) :=
  match decoded : decodeCheckedCore artifact with
  | none => none
  | some program =>
      match checkProgram program with
      | none => none
      | some typed => some ⟨program, decoded, typed.proof⟩

def checkCoreArtifactTyping (artifact : Artifact) : Bool :=
  (decodeTypedCore artifact).isSome

def CoreArtifactWellTyped (artifact : Artifact) : Prop :=
  Nonempty (CheckedCoreArtifact artifact)

theorem checkCoreArtifactTyping_sound {artifact : Artifact}
    (accepted : checkCoreArtifactTyping artifact = true) :
    CoreArtifactWellTyped artifact := by
  unfold checkCoreArtifactTyping at accepted
  cases found : decodeTypedCore artifact with
  | none => simp [found] at accepted
  | some checked => exact ⟨checked⟩

end Lanius.Extraction.CoreTyping
