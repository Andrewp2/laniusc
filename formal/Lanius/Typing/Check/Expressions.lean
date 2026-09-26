import Lanius.Typing.Check.Atoms

namespace Lanius.Typing.Check

open Lanius

open Lanius.Core

open Lanius.Typing

mutual
  def patternFuelSize (pattern : Pattern) : Nat :=
    match pattern with
    | .wildcard | .bind _ | .literal _ => 1
    | .enumVariant _ _ payload => 1 + patternsFuelSize payload
  termination_by structural pattern

  def exprFuelSize (expression : Expr) : Nat :=
    match expression with
    | .value value => 1 + valueFuelSize value
    | .local _ | .constant _ => 1
    | .cast _ operand | .unary _ operand | .dereference operand
    | .intrinsic _ operand | .i32ArrayDataPtr operand | .i32SliceDataPtr operand
    | .stringDataPtr operand => 1 + exprFuelSize operand
    | .binary _ left right | .index left right | .alloc left right
    | .i32SliceFromRawParts left right
    | .typedSliceFromRawParts _ left right => 1 + exprFuelSize left + exprFuelSize right
    | .array _ elements => 1 + exprsFuelSize elements
    | .arrayToSlice _ array | .field array _ => 1 + exprFuelSize array
    | .structValue _ fields | .enumValue _ _ fields | .call _ fields =>
        1 + exprsFuelSize fields
    | .matchValue scrutinee arms => 1 + exprFuelSize scrutinee + armsFuelSize arms
    | .assign _ place value => 1 + placeFuelSize place + exprFuelSize value
    | .borrow _ place => 1 + placeFuelSize place
    | .realloc a b c d =>
        1 + exprFuelSize a + exprFuelSize b + exprFuelSize c + exprFuelSize d
    | .dealloc a b c | .storeByte a b c =>
        1 + exprFuelSize a + exprFuelSize b + exprFuelSize c
    | .loadByte a b => 1 + exprFuelSize a + exprFuelSize b
  termination_by structural expression

  def placeFuelSize (place : Place) : Nat :=
    match place with
    | .local _ => 1
    | .field base _ => 1 + placeFuelSize base
    | .index base index => 1 + placeFuelSize base + exprFuelSize index
  termination_by structural place

  def patternsFuelSize (patterns : List Pattern) : Nat :=
    match patterns with
    | [] => 0
    | head :: tail => patternFuelSize head + patternsFuelSize tail
  termination_by structural patterns

  def exprsFuelSize (expressions : List Expr) : Nat :=
    match expressions with
    | [] => 0
    | head :: tail => exprFuelSize head + exprsFuelSize tail
  termination_by structural expressions

  def armsFuelSize (arms : List (Pattern × Expr)) : Nat :=
    match arms with
    | [] => 0
    | (pattern, body) :: tail => patternFuelSize pattern + exprFuelSize body + armsFuelSize tail
  termination_by structural arms
end

mutual
  def checkExprFuel (fuel : Nat) (program : Program) (context : Context) (expression : Expr) (type : Ty) :
      Option (ProofOf (ExprHasType program context expression type)) :=
    match fuel with
    | 0 => none
    | fuel + 1 => do
      let checked ← checkExprAnyFuel fuel program context expression
      if equal : checked.1 = type then
        some ⟨by simpa [equal] using checked.2.down⟩
      else none

  def checkExprAnyFuel (fuel : Nat) (program : Program) (context : Context) (expression : Expr) :
      Option (CheckedExpr program context expression) :=
    match fuel with
    | 0 => none
    | fuel + 1 => match expression with
    | .value value =>
        do let typed ← checkValueAnyFuel fuel program value
           if literal : Value.isLiteral value = true then
             pure ⟨typed.1, ⟨ExprHasType.value typed.2.down literal⟩⟩
           else none
    | .local id =>
        match found : context id with
        | none => none
        | some type => some ⟨type, ⟨.local found⟩⟩
    | .cast target operand =>
        do let typed ← checkExprAnyFuel fuel program context operand
           match typed with
           | ⟨.scalar source, typed⟩ =>
               let conversion ← checkScalarCast source target
               pure ⟨.scalar target, ⟨.cast typed.down conversion.down⟩⟩
           | _ => none
    | .unary operation operand =>
        do let typed ← checkExprAnyFuel fuel program context operand
           let operationTyped ← checkUnaryAny operation typed.1
           pure ⟨operationTyped.1, ⟨.unary typed.2.down operationTyped.2.down⟩⟩
    | .binary operation left right =>
        do let leftTyped ← checkExprAnyFuel fuel program context left
           let rightTyped ← checkExprAnyFuel fuel program context right
           let operationTyped ← checkBinaryAny operation leftTyped.1 rightTyped.1
           pure ⟨operationTyped.1, ⟨.binary leftTyped.2.down rightTyped.2.down
             operationTyped.2.down⟩⟩
    | .array elementType expressions =>
        do let elements ← checkExprsFuel fuel program context expressions
             (List.replicate expressions.length elementType)
           pure ⟨.array elementType expressions.length, ⟨.array elements.down⟩⟩
    | .arrayToSlice elementType array =>
        do let typed ← checkExprAnyFuel fuel program context array
           match typed with
           | ⟨.array actual length, typed⟩ =>
               if equal : actual = elementType then
                 pure ⟨.slice elementType, ⟨by
                   simpa [equal] using (ExprHasType.arrayToSlice typed.down)⟩⟩
               else none
           | _ => none
    | .index base index =>
        do let baseTyped ← checkExprAnyFuel fuel program context base
           let indexTyped ← checkExprAnyFuel fuel program context index
           let integerIndex ← checkInteger indexTyped.1
           match baseTyped with
           | ⟨.array elementType _length, baseTyped⟩ =>
               pure ⟨elementType, ⟨.indexArray baseTyped.down indexTyped.2.down
                 integerIndex.down⟩⟩
           | ⟨.slice elementType, baseTyped⟩ =>
               pure ⟨elementType, ⟨.indexSlice baseTyped.down indexTyped.2.down
                 integerIndex.down⟩⟩
           | _ => none
    | .structValue typeId fields =>
        match found : program.structure? typeId with
        | none => none
        | some declaration =>
            do let checked ← checkExprsFuel fuel program context fields declaration.fields
               pure ⟨.structure typeId, ⟨.structValue declaration found checked.down⟩⟩
    | .field base field =>
        do let baseTyped ← checkExprAnyFuel fuel program context base
           match baseTyped with
           | ⟨.structure typeId, baseTyped⟩ =>
               match found : program.structure? typeId with
               | none => none
               | some declaration =>
                   match fieldFound : declaration.fields[field]? with
                   | none => none
                   | some fieldType =>
                       pure ⟨fieldType, ⟨.field baseTyped.down declaration found fieldFound⟩⟩
           | _ => none
    | .enumValue typeId variant payload =>
        match found : program.enumeration? typeId with
        | none => none
        | some declaration =>
            match variantFound : declaration.variants[variant]? with
            | none => none
            | some payloadTypes =>
                do let checked ← checkExprsFuel fuel program context payload payloadTypes
                   pure ⟨.enumeration typeId, ⟨.enumValue declaration found variantFound
                     checked.down⟩⟩
    | .matchValue scrutinee arms =>
        do let scrutineeTyped ← checkExprAnyFuel fuel program context scrutinee
           let armsTyped ← checkMatchArmsAnyFuel fuel program context scrutineeTyped.1 arms
           pure ⟨armsTyped.1, ⟨.matchValue scrutineeTyped.2.down armsTyped.2.down⟩⟩
    | .assign operation place value =>
        do let placeTyped ← checkPlaceAnyFuel fuel program context place
           let valueTyped ← checkExprFuel fuel program context value placeTyped.1
           let operationTyped ← checkAssign operation placeTyped.1
           pure ⟨.unit, ⟨.assign placeTyped.2.down valueTyped.down operationTyped.down⟩⟩
    | .borrow referent place =>
        do let target ← checkPlaceFuel fuel program context place referent
           pure ⟨.reference referent, ⟨.borrow target.down⟩⟩
    | .dereference reference =>
        do let typed ← checkExprAnyFuel fuel program context reference
           match typed with
           | ⟨.reference referent, typed⟩ => some ⟨referent, ⟨.dereference typed.down⟩⟩
           | _ => none
    | .constant id =>
        match found : program.constant? id with
        | none => none
        | some declaration => some ⟨declaration.type, ⟨.constant declaration found⟩⟩
    | .call id arguments =>
        match found : program.function? id with
        | none => none
        | some function =>
            do let checked ← checkExprsFuel fuel program context arguments (function.parameters.map Prod.snd)
               pure ⟨function.returnType, ⟨.call function found checked.down⟩⟩
    | .intrinsic .printI32 argument =>
        do let checked ← checkExprFuel fuel program context argument (.scalar (.signed .i32))
           pure ⟨.unit, ⟨.printI32 checked.down⟩⟩
    | .intrinsic .assert argument =>
        do let checked ← checkExprFuel fuel program context argument (.scalar .bool)
           pure ⟨.unit, ⟨.assert checked.down⟩⟩
    | .i32ArrayDataPtr array =>
        do let checked ← checkExprAnyFuel fuel program context array
           match checked with
           | ⟨.array (.scalar (.signed .i32)) length, checked⟩ =>
               pure ⟨.scalar .rawPtr, ⟨.i32ArrayDataPtr checked.down⟩⟩
           | _ => none
    | .i32SliceFromRawParts pointer length =>
        do let pointerTyped ← checkExprFuel fuel program context pointer (.scalar .rawPtr)
           let lengthTyped ← checkExprFuel fuel program context length (.scalar (.signed .i32))
           pure ⟨.slice (.scalar (.signed .i32)), ⟨.i32SliceFromRawParts pointerTyped.down
             lengthTyped.down⟩⟩
    | .typedSliceFromRawParts element pointer length =>
        do let elementTyped ← checkRawNominalSliceElement program element
           let pointerTyped ← checkExprFuel fuel program context pointer (.scalar .rawPtr)
           let lengthTyped ← checkExprFuel fuel program context length (.scalar (.signed .i32))
           pure ⟨.slice element, ⟨.typedSliceFromRawParts elementTyped.down
             pointerTyped.down lengthTyped.down⟩⟩
    | .i32SliceDataPtr slice =>
        do let checked ← checkExprFuel fuel program context slice (.slice (.scalar (.signed .i32)))
           pure ⟨.scalar .rawPtr, ⟨.i32SliceDataPtr checked.down⟩⟩
    | .stringDataPtr string =>
        do let checked ← checkExprFuel fuel program context string (.scalar .string)
           pure ⟨.scalar .rawPtr, ⟨.stringDataPtr checked.down⟩⟩
    | .alloc size alignment =>
        do let sizeTyped ← checkExprFuel fuel program context size (.scalar (.unsigned .usize))
           let alignmentTyped ← checkExprFuel fuel program context alignment (.scalar (.unsigned .usize))
           pure ⟨.scalar .rawPtr, ⟨.alloc sizeTyped.down alignmentTyped.down⟩⟩
    | .realloc pointer oldSize newSize alignment =>
        do let pointerTyped ← checkExprFuel fuel program context pointer (.scalar .rawPtr)
           let oldSizeTyped ← checkExprFuel fuel program context oldSize (.scalar (.unsigned .usize))
           let newSizeTyped ← checkExprFuel fuel program context newSize (.scalar (.unsigned .usize))
           let alignmentTyped ← checkExprFuel fuel program context alignment (.scalar (.unsigned .usize))
           pure ⟨.scalar .rawPtr, ⟨.realloc pointerTyped.down oldSizeTyped.down
             newSizeTyped.down alignmentTyped.down⟩⟩
    | .dealloc pointer size alignment =>
        do let pointerTyped ← checkExprFuel fuel program context pointer (.scalar .rawPtr)
           let sizeTyped ← checkExprFuel fuel program context size (.scalar (.unsigned .usize))
           let alignmentTyped ← checkExprFuel fuel program context alignment (.scalar (.unsigned .usize))
           pure ⟨.unit, ⟨.dealloc pointerTyped.down sizeTyped.down alignmentTyped.down⟩⟩
    | .loadByte pointer offset =>
        do let pointerTyped ← checkExprFuel fuel program context pointer (.scalar .rawPtr)
           let offsetTyped ← checkExprFuel fuel program context offset (.scalar (.unsigned .usize))
           pure ⟨.scalar (.unsigned .u8), ⟨.loadByte pointerTyped.down offsetTyped.down⟩⟩
    | .storeByte pointer offset value =>
        do let pointerTyped ← checkExprFuel fuel program context pointer (.scalar .rawPtr)
           let offsetTyped ← checkExprFuel fuel program context offset (.scalar (.unsigned .usize))
           let valueTyped ← checkExprFuel fuel program context value (.scalar (.unsigned .u8))
           pure ⟨.unit, ⟨.storeByte pointerTyped.down offsetTyped.down valueTyped.down⟩⟩

  def checkExprsFuel (fuel : Nat) (program : Program) (context : Context) :
      (expressions : List Expr) → (types : List Ty) →
        Option (ProofOf (ExprsHaveTypes program context expressions types))
    | [], [] => match fuel with
      | 0 => none
      | _ => some ⟨.nil⟩
    | expression :: expressions, type :: types => match fuel with
      | 0 => none
      | fuel + 1 => do
          let head ← checkExprFuel fuel program context expression type
          let tail ← checkExprsFuel fuel program context expressions types
          pure ⟨.cons head.down tail.down⟩
    | _, _ => none

  def checkPlaceFuel (fuel : Nat) (program : Program) (context : Context) (place : Place) (type : Ty) :
      Option (ProofOf (PlaceHasType program context place type)) :=
    match fuel with
    | 0 => none
    | fuel + 1 => do
      let checked ← checkPlaceAnyFuel fuel program context place
      if equal : checked.1 = type then
        some ⟨by simpa [equal] using checked.2.down⟩
      else none

  def checkPlaceAnyFuel (fuel : Nat) (program : Program) (context : Context) (place : Place) :
      Option (CheckedPlace program context place) :=
    match fuel with
    | 0 => none
    | fuel + 1 => match place with
    | .local id =>
        match found : context id with
        | none => none
        | some type => some ⟨type, ⟨.local found⟩⟩
    | .field base field =>
        do let baseTyped ← checkPlaceAnyFuel fuel program context base
           match baseTyped with
           | ⟨.structure typeId, baseTyped⟩ =>
               match found : program.structure? typeId with
               | none => none
               | some declaration =>
                   match fieldFound : declaration.fields[field]? with
                   | none => none
                   | some fieldType =>
                       pure ⟨fieldType, ⟨.field baseTyped.down declaration found fieldFound⟩⟩
           | _ => none
    | .index base index =>
        do let baseTyped ← checkPlaceAnyFuel fuel program context base
           let indexTyped ← checkExprAnyFuel fuel program context index
           let integerIndex ← checkInteger indexTyped.1
           match baseTyped with
           | ⟨.array elementType _length, baseTyped⟩ =>
               pure ⟨elementType, ⟨.indexArray baseTyped.down indexTyped.2.down
                 integerIndex.down⟩⟩
           | ⟨.slice elementType, baseTyped⟩ =>
               pure ⟨elementType, ⟨.indexSlice baseTyped.down indexTyped.2.down
                 integerIndex.down⟩⟩
           | _ => none

  def checkMatchArmsFuel (fuel : Nat) (program : Program) (context : Context)
      (arms : List (Pattern × Expr)) (scrutineeType resultType : Ty) :
      Option (ProofOf (MatchArmsHaveType program context arms scrutineeType resultType)) :=
    match fuel with
    | 0 => none
    | fuel + 1 => do
      let checked ← checkMatchArmsAnyFuel fuel program context scrutineeType arms
      if equal : checked.1 = resultType then
        some ⟨by simpa [equal] using checked.2.down⟩
      else none

  def checkMatchArmsAnyFuel (fuel : Nat) (program : Program) (context : Context)
      (scrutineeType : Ty) :
      (arms : List (Pattern × Expr)) → Option (Σ resultType, ProofOf
        (MatchArmsHaveType program context arms scrutineeType resultType)) :=
    fun arms => match fuel with
    | 0 => none
    | fuel + 1 => match arms with
      | [] => none
      | [(pattern, body)] => do
          let patternTyped ← checkPattern program pattern scrutineeType
          let bodyTyped ← checkExprAnyFuel fuel program (context.bindAll patternTyped.1) body
          pure ⟨bodyTyped.1, ⟨.one patternTyped.2.down bodyTyped.2.down⟩⟩
      | (pattern, body) :: tail => do
          let patternTyped ← checkPattern program pattern scrutineeType
          let bodyTyped ← checkExprAnyFuel fuel program (context.bindAll patternTyped.1) body
          let tailTyped ← checkMatchArmsAnyFuel fuel program context scrutineeType tail
          if equal : bodyTyped.1 = tailTyped.1 then
            let bodyProof : ExprHasType program (context.bindAll patternTyped.1) body tailTyped.1 := by
              simpa [equal] using bodyTyped.2.down
            pure ⟨tailTyped.1, ⟨.cons patternTyped.2.down bodyProof tailTyped.2.down⟩⟩
          else none
end

def checkExpr (program : Program) (context : Context) (expression : Expr) (type : Ty) :
    Option (ProofOf (ExprHasType program context expression type)) :=
  checkExprFuel (checkerFuel (exprFuelSize expression)) program context expression type

def checkExprAny (program : Program) (context : Context) (expression : Expr) :
    Option (CheckedExpr program context expression) :=
  checkExprAnyFuel (checkerFuel (exprFuelSize expression)) program context expression

def checkExprs (program : Program) (context : Context) :
    (expressions : List Expr) → (types : List Ty) →
      Option (ProofOf (ExprsHaveTypes program context expressions types)) :=
  fun expressions types => checkExprsFuel (checkerFuel (exprsFuelSize expressions)) program context expressions types

def checkPlace (program : Program) (context : Context) (place : Place) (type : Ty) :
    Option (ProofOf (PlaceHasType program context place type)) :=
  checkPlaceFuel (checkerFuel (placeFuelSize place)) program context place type

def checkPlaceAny (program : Program) (context : Context) (place : Place) :
    Option (CheckedPlace program context place) :=
  checkPlaceAnyFuel (checkerFuel (placeFuelSize place)) program context place

def checkMatchArms (program : Program) (context : Context)
    (arms : List (Pattern × Expr)) (scrutineeType resultType : Ty) :
    Option (ProofOf (MatchArmsHaveType program context arms scrutineeType resultType)) :=
  checkMatchArmsFuel (checkerFuel (armsFuelSize arms)) program context arms scrutineeType resultType

def checkMatchArmsAny (program : Program) (context : Context)
    (scrutineeType : Ty) (arms : List (Pattern × Expr)) :
    Option (Σ resultType, ProofOf
      (MatchArmsHaveType program context arms scrutineeType resultType)) :=
  checkMatchArmsAnyFuel (checkerFuel (armsFuelSize arms)) program context scrutineeType arms

end Lanius.Typing.Check
