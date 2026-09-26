import Lanius.Typing

namespace Lanius.Typing.Check

open Lanius
open Lanius.Core
open Lanius.Typing

abbrev ProofOf (predicate : Prop) := PLift predicate

def checkRawNominalSliceElement (program : Program) (element : Ty) :
    Option (ProofOf (RawNominalSliceElement program element)) :=
  match element with
  | .structure id =>
      match found : program.structure? id with
      | some declaration => some ⟨.structureType id declaration found⟩
      | none => none
  | .enumeration id =>
      match found : program.enumeration? id with
      | some declaration => some ⟨.enumerationType id declaration found⟩
      | none => none
  | _ => none

def checkRawSliceElement (program : Program) (element : Ty) :
    Option (ProofOf (RawSliceElement program element)) :=
  match element with
  | .scalar (.signed .i32) => some ⟨.i32⟩
  | .structure id =>
      match found : program.structure? id with
      | some declaration =>
          some ⟨.nominal (.structureType id declaration found)⟩
      | none => none
  | .enumeration id =>
      match found : program.enumeration? id with
      | some declaration =>
          some ⟨.nominal (.enumerationType id declaration found)⟩
      | none => none
  | _ => none

def checkArithmetic (type : Ty) : Option (ProofOf (ArithmeticTy type)) :=
  match type with
  | .scalar (.signed signed) => some ⟨.signed signed⟩
  | .scalar (.unsigned unsigned) => some ⟨.unsigned unsigned⟩
  | .scalar .f32 => some ⟨.f32⟩
  | .scalar .f64 => some ⟨.f64⟩
  | .scalar .char => some ⟨.character⟩
  | _ => none

def checkNegatable (type : Ty) : Option (ProofOf (NegatableTy type)) :=
  match type with
  | .scalar (.signed signed) => some ⟨.signed signed⟩
  | .scalar (.unsigned unsigned) => some ⟨.unsigned unsigned⟩
  | .scalar .f32 => some ⟨.f32⟩
  | .scalar .f64 => some ⟨.f64⟩
  | .scalar .char => some ⟨.character⟩
  | _ => none

def checkInteger (type : Ty) : Option (ProofOf (IntegerTy type)) :=
  match type with
  | .scalar (.signed signed) => some ⟨.signed signed⟩
  | .scalar (.unsigned unsigned) => some ⟨.unsigned unsigned⟩
  | .scalar .char => some ⟨.character⟩
  | _ => none

def checkOrdered (type : Ty) : Option (ProofOf (OrderedTy type)) :=
  match type with
  | .scalar (.signed signed) => some ⟨.signed signed⟩
  | .scalar (.unsigned unsigned) => some ⟨.unsigned unsigned⟩
  | .scalar .f32 => some ⟨.f32⟩
  | .scalar .f64 => some ⟨.f64⟩
  | .scalar .char => some ⟨.character⟩
  | _ => none

def checkEquality (type : Ty) : Option (ProofOf (EqualityTy type)) :=
  match type with
  | .scalar .bool => some ⟨.boolean⟩
  | .scalar (.signed signed) => some ⟨.signed signed⟩
  | .scalar (.unsigned unsigned) => some ⟨.unsigned unsigned⟩
  | .scalar .f32 => some ⟨.f32⟩
  | .scalar .f64 => some ⟨.f64⟩
  | .scalar .char => some ⟨.character⟩
  | .scalar .rawPtr => some ⟨.pointer⟩
  | .enumeration id => some ⟨.enumeration id⟩
  | _ => none

def checkPointerOffset (type : Ty) : Option (ProofOf (PointerOffsetTy type)) :=
  match type with
  | .scalar (.signed signed) => some ⟨.signed signed⟩
  | .scalar (.unsigned unsigned) => some ⟨.unsigned unsigned⟩
  | .scalar .char => some ⟨.character⟩
  | _ => none

def checkScalarCast (source target : ScalarTy) :
    Option (ProofOf (ScalarCast source target)) :=
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

def checkUnary (operation : UnaryOp) (input output : Ty) :
    Option (ProofOf (UnaryOpHasType operation input output)) :=
  match operation with
  | .positive =>
      if equal : input = output then
        do let typed ← checkArithmetic input
           pure ⟨by simpa [equal] using UnaryOpHasType.positive typed.down⟩
      else none
  | .logicalNot =>
      if inputOk : input = .scalar .bool then
        if outputOk : output = .scalar .bool then
          some ⟨by simpa [inputOk, outputOk] using UnaryOpHasType.logicalNot⟩
        else none
      else none
  | .negate =>
      if equal : input = output then
        do let typed ← checkNegatable input
           pure ⟨by simpa [equal] using UnaryOpHasType.negate typed.down⟩
      else none

def checkBinary (operation : BinaryOp) (left right output : Ty) :
    Option (ProofOf (BinaryOpHasType operation left right output)) :=
  match operation with
  | .logicalAnd =>
      if l : left = .scalar .bool then
        if r : right = .scalar .bool then
          if o : output = .scalar .bool then
            some ⟨by simpa [l, r, o] using BinaryOpHasType.logicalAnd⟩
          else none
        else none
      else none
  | .logicalOr =>
      if l : left = .scalar .bool then
        if r : right = .scalar .bool then
          if o : output = .scalar .bool then
            some ⟨by simpa [l, r, o] using BinaryOpHasType.logicalOr⟩
          else none
        else none
      else none
  | .equal =>
      if equal : left = right then
        if out : output = .scalar .bool then
          do let typed ← checkEquality left
             pure ⟨by simpa [equal, out] using BinaryOpHasType.equal typed.down⟩
        else none
      else none
  | .notEqual =>
      if equal : left = right then
        if out : output = .scalar .bool then
          do let typed ← checkEquality left
             pure ⟨by simpa [equal, out] using BinaryOpHasType.notEqual typed.down⟩
        else none
      else none
  | .less =>
      if equal : left = right then
        if out : output = .scalar .bool then
          do let typed ← checkOrdered left
             pure ⟨by simpa [equal, out] using BinaryOpHasType.less typed.down⟩
        else none
      else none
  | .lessEqual =>
      if equal : left = right then
        if out : output = .scalar .bool then
          do let typed ← checkOrdered left
             pure ⟨by simpa [equal, out] using BinaryOpHasType.lessEqual typed.down⟩
        else none
      else none
  | .greater =>
      if equal : left = right then
        if out : output = .scalar .bool then
          do let typed ← checkOrdered left
             pure ⟨by simpa [equal, out] using BinaryOpHasType.greater typed.down⟩
        else none
      else none
  | .greaterEqual =>
      if equal : left = right then
        if out : output = .scalar .bool then
          do let typed ← checkOrdered left
             pure ⟨by simpa [equal, out] using BinaryOpHasType.greaterEqual typed.down⟩
        else none
      else none
  | .add =>
      if pointer : left = .scalar .rawPtr then
        if out : output = .scalar .rawPtr then
          do let typed ← checkPointerOffset right
             pure ⟨by simpa [pointer, out] using BinaryOpHasType.pointerAdd typed.down⟩
        else none
      else if equal : left = right then
        if out : output = left then
          do let typed ← checkArithmetic left
             pure ⟨by simpa [equal, out] using BinaryOpHasType.add typed.down⟩
        else none
      else none
  | .subtract =>
      if pointer : left = .scalar .rawPtr then
        if out : output = .scalar .rawPtr then
          do let typed ← checkPointerOffset right
             pure ⟨by simpa [pointer, out] using BinaryOpHasType.pointerSubtract typed.down⟩
        else none
      else if equal : left = right then
        if out : output = left then
          do let typed ← checkArithmetic left
             pure ⟨by simpa [equal, out] using BinaryOpHasType.subtract typed.down⟩
        else none
      else none
  | .multiply =>
      if equal : left = right then
        if out : output = left then
          do let typed ← checkArithmetic left
             pure ⟨by simpa [equal, out] using BinaryOpHasType.multiply typed.down⟩
        else none
      else none
  | .divide =>
      if equal : left = right then
        if out : output = left then
          do let typed ← checkArithmetic left
             pure ⟨by simpa [equal, out] using BinaryOpHasType.divide typed.down⟩
        else none
      else none
  | .remainder =>
      if equal : left = right then
        if out : output = left then
          do let typed ← checkInteger left
             pure ⟨by simpa [equal, out] using BinaryOpHasType.remainder typed.down⟩
        else none
      else none
  | .bitAnd =>
      if equal : left = right then
        if out : output = left then
          do let typed ← checkInteger left
             pure ⟨by simpa [equal, out] using BinaryOpHasType.bitAnd typed.down⟩
        else none
      else none
  | .bitOr =>
      if equal : left = right then
        if out : output = left then
          do let typed ← checkInteger left
             pure ⟨by simpa [equal, out] using BinaryOpHasType.bitOr typed.down⟩
        else none
      else none
  | .bitXor =>
      if equal : left = right then
        if out : output = left then
          do let typed ← checkInteger left
             pure ⟨by simpa [equal, out] using BinaryOpHasType.bitXor typed.down⟩
        else none
      else none
  | .shiftLeft =>
      if equal : left = right then
        if out : output = left then
          do let typed ← checkInteger left
             pure ⟨by simpa [equal, out] using BinaryOpHasType.shiftLeft typed.down⟩
        else none
      else none
  | .shiftRight =>
      if equal : left = right then
        if out : output = left then
          do let typed ← checkInteger left
             pure ⟨by simpa [equal, out] using BinaryOpHasType.shiftRight typed.down⟩
        else none
      else none

def checkAssign (operation : AssignOp) (type : Ty) :
    Option (ProofOf (AssignOpHasType operation type)) :=
  match operation with
  | .set => some ⟨.set⟩
  | .add => do let typed ← checkArithmetic type; pure ⟨.add typed.down⟩
  | .subtract => do let typed ← checkArithmetic type; pure ⟨.subtract typed.down⟩
  | .multiply => do let typed ← checkArithmetic type; pure ⟨.multiply typed.down⟩
  | .divide => do let typed ← checkArithmetic type; pure ⟨.divide typed.down⟩
  | .remainder => do let typed ← checkInteger type; pure ⟨.remainder typed.down⟩
  | .bitXor => do let typed ← checkInteger type; pure ⟨.bitXor typed.down⟩
  | .shiftLeft => do let typed ← checkInteger type; pure ⟨.shiftLeft typed.down⟩
  | .shiftRight => do let typed ← checkInteger type; pure ⟨.shiftRight typed.down⟩
  | .bitAnd => do let typed ← checkInteger type; pure ⟨.bitAnd typed.down⟩
  | .bitOr => do let typed ← checkInteger type; pure ⟨.bitOr typed.down⟩

theorem structureId_of_found {program : Program} {id : TypeId} {declaration : StructDecl}
    (found : program.structure? id = some declaration) : id = declaration.id := by
  cases program with
  | mk target structures enumerations constants functions =>
      change structures.find? (fun declaration => declaration.id == id) = some declaration at found
      induction structures with
      | nil => simp at found
      | cons head tail ih =>
          simp only [List.find?] at found
          split at found
          · next h =>
              have same : head.id = id := of_decide_eq_true h
              have equal : head = declaration := Option.some.inj found
              subst declaration
              exact same.symm
          · next h => exact ih found

theorem enumerationId_of_found {program : Program} {id : TypeId} {declaration : EnumDecl}
    (found : program.enumeration? id = some declaration) : id = declaration.id := by
  cases program with
  | mk target structures enumerations constants functions =>
      change enumerations.find? (fun declaration => declaration.id == id) = some declaration at found
      induction enumerations with
      | nil => simp at found
      | cons head tail ih =>
          simp only [List.find?] at found
          split at found
          · next h =>
              have same : head.id = id := of_decide_eq_true h
              have equal : head = declaration := Option.some.inj found
              subst declaration
              exact same.symm
          · next h => exact ih found
def checkerFuel (size : Nat) : Nat := size * 4 + 4

mutual
  def valueFuelSize (value : Value) : Nat :=
    match value with
    | .array values => 1 + valuesFuelSize values
    | .structure _ fields => 1 + valuesFuelSize fields
    | .enumeration _ _ payload => 1 + valuesFuelSize payload
    | _ => 1
  termination_by structural value

  def valuesFuelSize (values : List Value) : Nat :=
    match values with
    | [] => 0
    | head :: tail => valueFuelSize head + valuesFuelSize tail
  termination_by structural values
end

mutual
  def checkValueFuel (fuel : Nat) (program : Program) (value : Value) (type : Ty) :
      Option (ProofOf (ValueHasType program value type)) :=
    match fuel with
    | 0 => none
    | fuel + 1 => match value, type with
    | .unit, .unit => some ⟨.unit⟩
    | .boolean value, .scalar .bool => some ⟨.boolean value⟩
    | .signed signed value, .scalar (.signed expected) =>
        if equal : signed = expected then
          if lower : signedMin program.target signed ≤ value then
            if upper : value ≤ signedMax program.target signed then
              some ⟨by simpa [equal] using ValueHasType.signed signed value lower upper⟩
            else none
          else none
        else none
    | .unsigned unsigned value, .scalar (.unsigned expected) =>
        if equal : unsigned = expected then
            if upper : value ≤ unsignedMax program.target unsigned then
            some ⟨by simpa [equal] using ValueHasType.unsigned unsigned value upper⟩
          else none
        else none
    | .f32Bits bits, .scalar .f32 => some ⟨.f32Bits bits⟩
    | .f64Bits bits, .scalar .f64 => some ⟨.f64Bits bits⟩
    | .character value, .scalar .char => some ⟨.character value⟩
    | .string value, .scalar .string => some ⟨.string value⟩
    | .pointer address, .scalar .rawPtr => some ⟨.pointer address⟩
    | .slice elementType cell projections start length, .slice expected =>
        if equal : elementType = expected then
          some ⟨by simpa [equal] using
            ValueHasType.slice elementType cell projections start length⟩
        else none
    | .rawSlice elementType address length, .slice expected =>
        if equal : elementType = expected then
          do let element ← checkRawSliceElement program elementType
             pure ⟨by simpa [equal] using
               ValueHasType.rawSlice element.down address length⟩
        else none
    | .reference referent cell projections, .reference expected =>
        if equal : referent = expected then
          some ⟨by simpa [equal] using
            ValueHasType.reference referent cell projections⟩
        else none
    | .array values, .array elementType count =>
        if length : values.length = count then
          do let elements ← checkValuesFuel fuel program values (List.replicate count elementType)
             pure ⟨by simpa [length] using
               ValueHasType.array values elementType length elements.down⟩
        else none
    | .structure id values, .structure expectedId =>
        if idEqual : id = expectedId then
          match found : program.structure? expectedId with
          | none => none
          | some declaration =>
              do let fields ← checkValuesFuel fuel program values declaration.fields
                 have found' : program.structure? declaration.id = some declaration := by
                   simpa [structureId_of_found found] using found
                 pure ⟨by simpa [idEqual, structureId_of_found found] using
                   ValueHasType.structure declaration found' fields.down⟩
        else none
    | .enumeration id variant values, .enumeration expectedId =>
        if idEqual : id = expectedId then
          match found : program.enumeration? expectedId with
          | none => none
          | some declaration =>
              match variantFound : declaration.variants[variant]? with
              | none => none
              | some payloadTypes =>
                  do let payload ← checkValuesFuel fuel program values payloadTypes
                     have found' : program.enumeration? declaration.id = some declaration := by
                       simpa [enumerationId_of_found found] using found
                     pure ⟨by simpa [idEqual, enumerationId_of_found found] using
                       ValueHasType.enumeration declaration found' variantFound payload.down⟩
        else none
    | _, _ => none

  def checkValuesFuel (fuel : Nat) (program : Program) :
      (values : List Value) → (types : List Ty) →
        Option (ProofOf (ValuesHaveTypes program values types))
    | [], [] => match fuel with
      | 0 => none
      | _ => some ⟨.nil⟩
    | value :: values, type :: types => match fuel with
      | 0 => none
      | fuel + 1 => do
          let head ← checkValueFuel fuel program value type
          let tail ← checkValuesFuel fuel program values types
          pure ⟨.cons head.down tail.down⟩
    | _, _ => none

  def checkValueAnyFuel (fuel : Nat) (program : Program) (value : Value) :
      Option (Σ type, ProofOf (ValueHasType program value type)) :=
    match fuel with
    | 0 => none
    | fuel + 1 => match value with
    | .unit => some ⟨.unit, ⟨.unit⟩⟩
    | .boolean value => some ⟨.scalar .bool, ⟨.boolean value⟩⟩
    | .signed signed value =>
        do let checked ← checkValueFuel fuel program (.signed signed value) (.scalar (.signed signed))
           pure ⟨.scalar (.signed signed), checked⟩
    | .unsigned unsigned value =>
        do let checked ← checkValueFuel fuel program (.unsigned unsigned value) (.scalar (.unsigned unsigned))
           pure ⟨.scalar (.unsigned unsigned), checked⟩
    | .f32Bits bits => some ⟨.scalar .f32, ⟨.f32Bits bits⟩⟩
    | .f64Bits bits => some ⟨.scalar .f64, ⟨.f64Bits bits⟩⟩
    | .character value => some ⟨.scalar .char, ⟨.character value⟩⟩
    | .string value => some ⟨.scalar .string, ⟨.string value⟩⟩
    | .pointer address => some ⟨.scalar .rawPtr, ⟨.pointer address⟩⟩
    | .slice elementType cell projections start length =>
        some ⟨.slice elementType, ⟨.slice elementType cell projections start length⟩⟩
    | .rawSlice elementType address length =>
        do let element ← checkRawSliceElement program elementType
           pure ⟨.slice elementType,
             ⟨.rawSlice element.down address length⟩⟩
    | .reference referent cell projections =>
        some ⟨.reference referent, ⟨.reference referent cell projections⟩⟩
    | .array [] => none
    | .array (head :: tail) =>
        do let first ← checkValueAnyFuel fuel program head
           let rest ← checkValuesFuel fuel program tail (List.replicate tail.length first.1)
           let elements : ValuesHaveTypes program (head :: tail)
               (first.1 :: List.replicate tail.length first.1) :=
             .cons first.2.down rest.down
           pure ⟨.array first.1 (tail.length + 1), ⟨by
             simpa using ValueHasType.array (head :: tail) first.1 (by simp) elements⟩⟩
    | .structure id values =>
        do let checked ← checkValueFuel fuel program (.structure id values) (.structure id)
           pure ⟨.structure id, checked⟩
    | .enumeration id variant values =>
        do let checked ← checkValueFuel fuel program (.enumeration id variant values) (.enumeration id)
           pure ⟨.enumeration id, checked⟩
end

def checkValue (program : Program) (value : Value) (type : Ty) :
    Option (ProofOf (ValueHasType program value type)) :=
  checkValueFuel (checkerFuel (valueFuelSize value)) program value type

def checkValues (program : Program) :
    (values : List Value) → (types : List Ty) →
      Option (ProofOf (ValuesHaveTypes program values types)) :=
  fun values types => checkValuesFuel (checkerFuel (valuesFuelSize values)) program values types

def checkValueAny (program : Program) (value : Value) :
    Option (Σ type, ProofOf (ValueHasType program value type)) :=
  checkValueAnyFuel (checkerFuel (valueFuelSize value)) program value

mutual
  def checkPattern (program : Program) (pattern : Pattern) (type : Ty) :
      Option (Σ bindings, ProofOf (PatternHasType program pattern type bindings)) :=
    match pattern with
    | .wildcard => some ⟨[], ⟨.wildcard⟩⟩
    | .bind id => some ⟨[(id, type)], ⟨.bind id⟩⟩
    | .literal value =>
        do let typed ← checkValue program value type
           pure ⟨[], ⟨.literal typed.down⟩⟩
    | .enumVariant typeId variant payload =>
        match type with
        | .enumeration expectedId =>
            if equal : typeId = expectedId then
              match found : program.enumeration? expectedId with
              | none => none
              | some declaration =>
                  match variantFound : declaration.variants[variant]? with
                  | none => none
                  | some payloadTypes =>
                      do let checked ← checkPatterns program payload payloadTypes
                         pure ⟨checked.1, ⟨by
                           simpa [equal] using
                             (PatternHasType.enumVariant declaration found variantFound
                               checked.2.down)⟩⟩
            else none
        | _ => none

  def checkPatterns (program : Program) :
      (patterns : List Pattern) → (types : List Ty) →
      Option (Σ bindings, ProofOf (PatternsHaveTypes program patterns types bindings))
    | [], [] => some ⟨[], ⟨.nil⟩⟩
    | pattern :: patterns, type :: types =>
        do let head ← checkPattern program pattern type
           let tail ← checkPatterns program patterns types
           pure ⟨head.1 ++ tail.1, ⟨.cons head.2.down tail.2.down⟩⟩
    | _, _ => none
end

def checkUnaryAny (operation : UnaryOp) (input : Ty) :
    Option (Σ output, ProofOf (UnaryOpHasType operation input output)) :=
  match operation with
  | .logicalNot => do
      let checked ← checkUnary .logicalNot input (.scalar .bool)
      pure ⟨.scalar .bool, checked⟩
  | .positive => do
      let checked ← checkUnary .positive input input
      pure ⟨input, checked⟩
  | .negate => do
      let checked ← checkUnary .negate input input
      pure ⟨input, checked⟩

def checkBinaryAny (operation : BinaryOp) (left right : Ty) :
    Option (Σ output, ProofOf (BinaryOpHasType operation left right output)) :=
  match operation with
  | .logicalAnd => do
      let checked ← checkBinary .logicalAnd left right (.scalar .bool)
      pure ⟨.scalar .bool, checked⟩
  | .logicalOr => do
      let checked ← checkBinary .logicalOr left right (.scalar .bool)
      pure ⟨.scalar .bool, checked⟩
  | .equal => do
      let checked ← checkBinary .equal left right (.scalar .bool)
      pure ⟨.scalar .bool, checked⟩
  | .notEqual => do
      let checked ← checkBinary .notEqual left right (.scalar .bool)
      pure ⟨.scalar .bool, checked⟩
  | .less => do
      let checked ← checkBinary .less left right (.scalar .bool)
      pure ⟨.scalar .bool, checked⟩
  | .lessEqual => do
      let checked ← checkBinary .lessEqual left right (.scalar .bool)
      pure ⟨.scalar .bool, checked⟩
  | .greater => do
      let checked ← checkBinary .greater left right (.scalar .bool)
      pure ⟨.scalar .bool, checked⟩
  | .greaterEqual => do
      let checked ← checkBinary .greaterEqual left right (.scalar .bool)
      pure ⟨.scalar .bool, checked⟩
  | .add =>
      if _pointer : left = .scalar .rawPtr then
        do let checked ← checkBinary .add left right (.scalar .rawPtr)
           pure ⟨.scalar .rawPtr, checked⟩
      else
        do let checked ← checkBinary .add left right left
           pure ⟨left, checked⟩
  | .subtract =>
      if _pointer : left = .scalar .rawPtr then
        do let checked ← checkBinary .subtract left right (.scalar .rawPtr)
           pure ⟨.scalar .rawPtr, checked⟩
      else
        do let checked ← checkBinary .subtract left right left
           pure ⟨left, checked⟩
  | .multiply => do
      let checked ← checkBinary .multiply left right left
      pure ⟨left, checked⟩
  | .divide => do
      let checked ← checkBinary .divide left right left
      pure ⟨left, checked⟩
  | .remainder => do
      let checked ← checkBinary .remainder left right left
      pure ⟨left, checked⟩
  | .bitAnd => do
      let checked ← checkBinary .bitAnd left right left
      pure ⟨left, checked⟩
  | .bitOr => do
      let checked ← checkBinary .bitOr left right left
      pure ⟨left, checked⟩
  | .bitXor => do
      let checked ← checkBinary .bitXor left right left
      pure ⟨left, checked⟩
  | .shiftLeft => do
      let checked ← checkBinary .shiftLeft left right left
      pure ⟨left, checked⟩
  | .shiftRight => do
      let checked ← checkBinary .shiftRight left right left
      pure ⟨left, checked⟩

abbrev CheckedExpr (program : Program) (context : Context) (expression : Expr) :=
  Σ type, ProofOf (ExprHasType program context expression type)

abbrev CheckedPlace (program : Program) (context : Context) (place : Place) :=
  Σ type, ProofOf (PlaceHasType program context place type)

end Lanius.Typing.Check
