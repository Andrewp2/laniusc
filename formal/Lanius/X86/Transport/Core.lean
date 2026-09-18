import Lanius.Core
import Lanius.Core.Dependencies.Closure

namespace Lanius.X86.Transport

open Lanius.Core

/-- Bootstrap transport of actual Core syntax. This serializer does not lower
operations, assign stack slots, or emit machine bytes; those run in Lanius. -/
def type? : Ty → Option Int
  | .scalar (.signed .i32) => some 1
  | .scalar .bool => some 2
  | .scalar (.unsigned .usize) => some 3
  | .scalar .rawPtr => some 4
  | .scalar .string => some 5
  | .slice (.scalar (.signed .i32)) => some 6
  | .structure id => if id ≤ 2147483631 then some (16 + id) else none
  | _ => none

def binaryTag : BinaryOp → Int
  | .logicalAnd => 0 | .logicalOr => 1 | .equal => 2 | .notEqual => 3
  | .less => 4 | .lessEqual => 5 | .greater => 6 | .greaterEqual => 7
  | .add => 8 | .subtract => 9 | .multiply => 10 | .divide => 11 | .remainder => 12
  | .bitAnd => 13 | .bitOr => 14 | .bitXor => 15 | .shiftLeft => 16 | .shiftRight => 17

def unaryTag : UnaryOp → Int
  | .positive => 0 | .logicalNot => 1 | .negate => 2

def assignTag : AssignOp → Int
  | .set => 0 | .add => 1 | .subtract => 2 | .multiply => 3 | .divide => 4
  | .remainder => 5 | .bitXor => 6 | .shiftLeft => 7 | .shiftRight => 8 | .bitAnd => 9 | .bitOr => 10

def localId? (id : VarId) : Option Int := if id ≤ 2147483647 then some id else none

/-- Semantic service tags, not Linux syscall numbers or bootstrap builtin IDs. -/
def service? : ExternalBehavior → Option Int
  | .host .alloc => some 1
  | .host .openRead => some 2
  | .host .close => some 3
  | .host .read => some 4
  | .host .writeStdout => some 5
  | .host .writeByte => some 6
  | .host .argc => some 7
  | .host .argLen => some 8
  | .host .argRead => some 9
  | _ => none

def literal? : Value → Option (List Int)
  | .signed .i32 value => if -2147483648 ≤ value ∧ value ≤ 2147483647 then some [1, value] else none
  | .boolean value => some [2, if value then 1 else 0]
  | .unsigned .usize value => if value < 2^64 then
      some [3, (BitVec.ofNat 32 value).toInt, (BitVec.ofNat 32 (value / 2^32)).toInt] else none
  -- Core allocation identities are not native addresses. Only null has a
  -- target-independent literal representation; other pointers must come
  -- from parameters, allocations, or views with a storage correspondence.
  | .pointer value => if value = 0 then some [4, 0, 0] else none
  | .string value => if value.utf8ByteSize ≤ 65536 then
      some ([5, (value.utf8ByteSize : Int)] ++ value.toUTF8.toList.map (fun byte => (byte.toNat : Int))) else none
  | _ => none

theorem literal_pointer_accepted (value : Nat) (words : List Int) :
    literal? (.pointer value) = some words ↔ value = 0 ∧ words = [4, 0, 0] := by
  simp only [literal?]
  split <;> simp_all [eq_comm]

theorem literal_pointer_rejected (value : Nat) (nonzero : value ≠ 0) :
    literal? (.pointer value) = none := by
  simp [literal?, nonzero]

mutual
def expression? (program : Program) : Expr → Option (List Int)
  | .value value => return [0] ++ (← literal? value)
  | .local id => return [1, ← localId? id]
  | .cast target value => return [2, ← type? (.scalar target)] ++ (← expression? program value)
  | .unary op operand => return [3, unaryTag op] ++ (← expression? program operand)
  | .binary op left right => return [4, binaryTag op] ++ (← expression? program left) ++ (← expression? program right)
  | .assign op target value => return [12, assignTag op] ++ (← place? program target) ++ (← expression? program value)
  | .index base index => return [7] ++ (← expression? program base) ++ (← expression? program index)
  | .structValue id fields => return [8, ← type? (.structure id), fields.length] ++
      (← fields.mapM (expression? program)).flatten
  | .field base field => return [9, ← localId? field] ++ (← expression? program base)
  | .i32SliceFromRawParts pointer length => return [15] ++
      (← expression? program pointer) ++ (← expression? program length)
  | .i32SliceDataPtr slice => return [16] ++ (← expression? program slice)
  | .stringDataPtr string => return [17] ++ (← expression? program string)
  | .constant id => do
      let constant ← program.constant? id
      let _ ← literal? constant.value
      return [13, ← localId? id]
  | .call id arguments => do
      let function ← program.function? id
      if let some external := function.external then
        let _ ← service? external
      return [14, ← localId? id, arguments.length] ++ (← arguments.mapM (expression? program)).flatten
  | _ => none

def place? (program : Program) : Place → Option (List Int)
  | .local id => return [0, ← localId? id]
  | .field base field => return [1, ← localId? field] ++ (← place? program base)
  | .index base index => return [2] ++ (← place? program base) ++ (← expression? program index)
end

def statement? (program : Program) : Stmt → Option (List Int)
  | .skip => some [0]
  | .expression value => return [1] ++ (← expression? program value)
  | .sequence first rest => return [2] ++ (← statement? program first) ++ (← statement? program rest)
  | .letLocal id type initializer body => return [3, ← localId? id, ← type? type] ++
      (← expression? program initializer) ++ (← statement? program body)
  | .letUninitialized id type body => return [4, ← localId? id, ← type? type] ++ (← statement? program body)
  | .ifThenElse condition yes no => return [5] ++ (← expression? program condition) ++ (← statement? program yes) ++ (← statement? program no)
  | .whileLoop condition body => return [6] ++ (← expression? program condition) ++ (← statement? program body)
  | .returnValue (some value) => return [10, 1] ++ (← expression? program value)
  | .breakLoop => some [11]
  | .continueLoop => some [12]
  | _ => none

def function? (program : Program) (function : Function) : Option (List Int) := do
  do
    let id ← localId? function.id
    let result ← type? function.returnType
    let (kind, body) ← match function.external with
      | some external => do pure (2, [← service? external])
      | none => do pure (1, ← statement? program (← function.body))
    let parameters ← function.parameters.mapM fun (id, type) => do
      pure [← localId? id, ← type? type]
    let words := [kind, 64, id, result, (function.parameters.length : Int), (body.length : Int)] ++ parameters.flatten ++ body
    if words.length ≤ 65536 then some words else none

mutual
  private def constantsIn : Expr → List ConstantId
    | .constant id => [id]
    | .unary _ value | .field value _ | .cast _ value
    | .i32SliceDataPtr value | .stringDataPtr value => constantsIn value
    | .binary _ left right | .index left right | .i32SliceFromRawParts left right =>
        constantsIn left ++ constantsIn right
    | .assign _ target value => placeConstants target ++ constantsIn value
    | .structValue _ values | .call _ values => constantsInArgs values
    | _ => [] -- All other non-leaf constructors reject in expression?.
  private def constantsInArgs : List Expr → List ConstantId
    | [] => []
    | value :: rest => constantsIn value ++ constantsInArgs rest
  private def placeConstants : Place → List ConstantId
    | .local _ => []
    | .field base _ => placeConstants base
    | .index base index => placeConstants base ++ constantsIn index
end

private def statementConstants : Stmt → List ConstantId
  | .expression value | .returnValue (some value) => constantsIn value
  | .sequence first rest => statementConstants first ++ statementConstants rest
  | .letLocal _ _ value body => constantsIn value ++ statementConstants body
  | .letUninitialized _ _ body => statementConstants body
  | .ifThenElse condition yes no => constantsIn condition ++ statementConstants yes ++ statementConstants no
  | .whileLoop condition body => constantsIn condition ++ statementConstants body
  | _ => []

/-- Serialize a closed source-derived program. Core records and function IDs
remain semantic metadata: layout, register allocation, and linking run in
Lanius. Unsupported constants may be omitted only because every constant use
is checked by `expression?` and rejects unrepresentable values. -/
def program? (program : Program) (entry : FunctionId) : Option (List Int) := do
  if program.target != .x86_64 then none else do
    let reachable := Dependencies.closure program [entry]
    if !reachable.contains entry || !Dependencies.closed program reachable.contains then none else do
      let selected := program.functions.filter fun function => reachable.contains function.id
      let functions ← selected.mapM (function? program)
      if functions.isEmpty then none else do
        let structures ← program.structures.mapM fun record => do
          pure ([← localId? record.id, record.fields.length] ++ (← record.fields.mapM type?))
        let needed := (selected.flatMap fun function => function.body.toList.flatMap statementConstants).eraseDups
        let constants := (program.constants.filter fun constant => needed.contains constant.id).filterMap fun constant => do
          let values ← literal? constant.value
          let id ← localId? constant.id
          match constant.value with
          | .signed .i32 _ | .boolean _ => some ([id] ++ values ++ [0])
          | _ => some ([id] ++ values)
        let words := [2, 64, ← localId? entry, structures.length, constants.length, functions.length] ++
          structures.flatten ++ constants.flatten ++ functions.flatMap (fun words => (words.length : Int) :: words)
        if words.length ≤ 65536 then some words else none

end Lanius.X86.Transport
