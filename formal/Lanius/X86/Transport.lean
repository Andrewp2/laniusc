import Lanius.Core

namespace Lanius.X86.Transport

open Lanius Lanius.Core

/-! The canonical, position-independent Core word transport consumed by the
    Lanius x86 compiler.  This module deliberately contains no machine-code
    choices: it is the semantic boundary between Core lowering and backend
    verification.  `none` is an explicit rejection of the current backend
    subset. -/

def typeTag : Ty → Option Int
  | .scalar (.signed .i32) => some 1
  | .scalar .bool => some 2
  | .scalar (.unsigned .usize) => some 3
  | .scalar .rawPtr => some 4
  | .scalar .string => some 5
  | .slice (.scalar (.signed .i32)) => some 6
  | .slice (.structure id) =>
      if id < 1073741808 then some (1073741824 + Int.ofNat id) else none
  | .slice (.enumeration id) =>
      if id < 1073741808 then some (1073741824 + Int.ofNat id) else none
  | .structure id =>
      if id < 1073741808 then some (16 + Int.ofNat id) else none
  | .enumeration id =>
      if id < 1073741808 then some (16 + Int.ofNat id) else none
  | _ => none

abbrev resultTypeTag : Ty → Option Int
  | .unit => some 0
  | type => typeTag type

def signedWord (value : Nat) : Int :=
  let word := value % (2 ^ 32)
  if word < 2 ^ 31 then Int.ofNat word else Int.ofNat word - 2 ^ 32

def words64 (value : Nat) : List Int :=
  [signedWord value, signedWord (value / 2 ^ 32)]

def unaryTag : UnaryOp → Int
  | .positive => 0
  | .logicalNot => 1
  | .negate => 2

def binaryTag : BinaryOp → Int
  | .logicalAnd => 0
  | .logicalOr => 1
  | .equal => 2
  | .notEqual => 3
  | .less => 4
  | .lessEqual => 5
  | .greater => 6
  | .greaterEqual => 7
  | .add => 8
  | .subtract => 9
  | .multiply => 10
  | .divide => 11
  | .remainder => 12
  | .bitAnd => 13
  | .bitOr => 14
  | .bitXor => 15
  | .shiftLeft => 16
  | .shiftRight => 17

def assignTag : AssignOp → Int
  | .set => 0
  | .add => 1
  | .subtract => 2
  | .multiply => 3
  | .divide => 4
  | .remainder => 5
  | .bitXor => 6
  | .shiftLeft => 7
  | .shiftRight => 8
  | .bitAnd => 9
  | .bitOr => 10

def encodeValue : Value → Option (List Int)
  | .signed .i32 value => some [0, 1, value]
  | .boolean value => some [0, 2, if value then 1 else 0]
  | .unsigned .usize value => some ([0, 3] ++ words64 value)
  -- Core addresses are abstract identities; only null is a literal that can
  -- cross this transport boundary.  Native addresses come from runtime code.
  | .pointer value => if value == 0 then some [0, 4, 0, 0] else none
  | .string value =>
      let bytes := value.toUTF8.data.toList
      some ([0, 5, Int.ofNat bytes.length] ++ bytes.map (Int.ofNat ·.toNat))
  | _ => none

mutual
  def encodeExpr : Expr → Option (List Int)
    | .value value => encodeValue value
    | .local id => some [1, Int.ofNat id]
    | .cast target operand => do
        let target ← match target with
          | .signed .i32 => some 1
          | .unsigned .usize => some 3
          | _ => none
        return [2, target] ++ (← encodeExpr operand)
    | .unary operation operand =>
        return [3, unaryTag operation] ++ (← encodeExpr operand)
    | .binary operation left right =>
        return [4, binaryTag operation] ++ (← encodeExpr left) ++ (← encodeExpr right)
    | .index base index => return [7] ++ (← encodeExpr base) ++ (← encodeExpr index)
    | .structValue id fields => do
        let encoded ← fields.mapM encodeExpr
        return [8, 16 + Int.ofNat id, Int.ofNat fields.length] ++ encoded.flatten
    | .field base field => return [9, Int.ofNat field] ++ (← encodeExpr base)
    | .assign operation place value =>
        return [12, assignTag operation] ++ (← encodePlace place) ++ (← encodeExpr value)
    | .constant id => some [13, Int.ofNat id]
    | .call function arguments => do
        let encoded ← arguments.mapM encodeExpr
        return [14, Int.ofNat function, Int.ofNat arguments.length] ++ encoded.flatten
    | .i32SliceFromRawParts pointer length =>
        return [15] ++ (← encodeExpr pointer) ++ (← encodeExpr length)
    | .typedSliceFromRawParts element pointer length => do
        let (kind, id) ← match element with
          | .structure id => some (0, Int.ofNat id)
          | .enumeration id => some (1, Int.ofNat id)
          | .scalar (.signed .i32) => some (2, 0)
          | _ => none
        return [22, kind, id] ++ (← encodeExpr pointer) ++ (← encodeExpr length)
    | .i32SliceDataPtr slice => return [16] ++ (← encodeExpr slice)
    | .stringDataPtr string => return [17] ++ (← encodeExpr string)
    | _ => none

  def encodePlace : Place → Option (List Int)
    | .local id => some [0, Int.ofNat id]
    | .field base field => return [1, Int.ofNat field] ++ (← encodePlace base)
    | .index base index => return [2] ++ (← encodePlace base) ++ (← encodeExpr index)
end

def encodeStmt : Stmt → Option (List Int)
  | .skip => some [0]
  | .expression expression => return [1] ++ (← encodeExpr expression)
  | .sequence first second => return [2] ++ (← encodeStmt first) ++ (← encodeStmt second)
  | .letLocal id type initializer body => do
      let type ← typeTag type
      return [3, Int.ofNat id, type] ++ (← encodeExpr initializer) ++ (← encodeStmt body)
  | .letUninitialized id type body => do
      let type ← typeTag type
      return [4, Int.ofNat id, type] ++ (← encodeStmt body)
  | .ifThenElse condition thenBranch elseBranch =>
      return [5] ++ (← encodeExpr condition) ++ (← encodeStmt thenBranch) ++
        (← encodeStmt elseBranch)
  | .whileLoop condition body => return [6] ++ (← encodeExpr condition) ++ (← encodeStmt body)
  | .returnValue (some value) => return [10, 1] ++ (← encodeExpr value)
  | .returnValue none => some [10, 0]
  | .breakLoop => some [11]
  | .continueLoop => some [12]
  | _ => none

def encodeParameters (parameters : List (VarId × Ty)) : Option (List Int) := do
  let encoded ← parameters.mapM fun (id, type) => do
    return [Int.ofNat id, ← typeTag type]
  return encoded.flatten

def serviceTag : HostService → Option Int
  | .alloc => some 1
  | .openRead => some 2
  | .close => some 3
  | .read => some 4
  | .writeStdout => some 5
  | .writeByte => some 6
  | .argc => some 7
  | .argLen => some 8
  | .argRead => some 9
  | _ => none

def encodeFunction (function : Function) : Option (List Int) := do
  let result ← resultTypeTag function.returnType
  let parameters ← encodeParameters function.parameters
  match function.body, function.external with
  | some body, none =>
      let body ← encodeStmt body
      return [1, 64, Int.ofNat function.id, result,
        Int.ofNat function.parameters.length, Int.ofNat body.length] ++ parameters ++ body
  | none, some (.host service) =>
      if function.parameters.map Prod.snd != service.parameterTypes ||
          function.returnType != service.returnType then none else
      let service ← serviceTag service
      return [2, 64, Int.ofNat function.id, result,
        Int.ofNat function.parameters.length, 1] ++ parameters ++ [service]
  | _, _ => none

def encodeStructure (declaration : StructDecl) : Option (List Int) := do
  let fields ← declaration.fields.mapM typeTag
  let layout := [Int.ofNat declaration.id, 0, Int.ofNat fields.length] ++ fields
  return Int.ofNat layout.length :: layout

def encodeEnumeration (declaration : EnumDecl) : Option (List Int) := do
  let variants ← declaration.variants.mapM fun fields => do
    let types ← fields.mapM typeTag
    return Int.ofNat types.length :: types
  let layout := [Int.ofNat declaration.id, 1, Int.ofNat variants.length] ++
    variants.flatten
  return Int.ofNat layout.length :: layout

def encodeConstant (constant : Constant) : Option (List Int) :=
  match constant.type, constant.value with
  | .scalar (.signed .i32), .signed .i32 value => some [Int.ofNat constant.id, 1, value, 0]
  | .scalar .bool, .boolean value => some [Int.ofNat constant.id, 2, if value then 1 else 0, 0]
  | .scalar (.unsigned .usize), .unsigned .usize value =>
      some ([Int.ofNat constant.id, 3] ++ words64 value)
  | .scalar .rawPtr, .pointer 0 => some [Int.ofNat constant.id, 4, 0, 0]
  | .scalar .string, .string value =>
      let bytes := value.toUTF8.data.toList
      some ([Int.ofNat constant.id, 5, Int.ofNat bytes.length] ++
        bytes.map (Int.ofNat ·.toNat))
  | _, _ => none

def encodeProgram (entrypoint : FunctionId) (program : Program) : Option (List Int) := do
  if program.target != Target.x86_64 then none else
  let structures ← program.structures.mapM encodeStructure
  let enumerations ← program.enumerations.mapM encodeEnumeration
  let constants ← program.constants.mapM encodeConstant
  let functions ← program.functions.mapM encodeFunction
  let functions := functions.map fun function => Int.ofNat function.length :: function
  return [3, 64, Int.ofNat entrypoint, Int.ofNat (structures.length + enumerations.length),
    Int.ofNat constants.length, Int.ofNat functions.length] ++
    structures.flatten ++ enumerations.flatten ++ constants.flatten ++ functions.flatten

def EncodesProgram (entrypoint : FunctionId) (program : Program)
    (words : List Int) : Prop := encodeProgram entrypoint program = some words

end Lanius.X86.Transport
