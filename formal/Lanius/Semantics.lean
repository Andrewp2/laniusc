import Lanius.Memory
import Lanius.World

namespace Lanius.Semantics

open Lanius
open Lanius.Core
open Lanius.Memory
open Lanius.World

structure Cell where
  id : CellId
  value : Option Value

/-- A raw pointer produced by `i32_array_data_ptr` retains the identity of the
    language place whose storage it exposes. The heap block supplies a stable,
    disjoint numeric address for host ABI operations; synchronization below
    preserves aliasing in both directions. -/
structure I32ArrayView where
  address : Address
  root : CellId
  projections : List ValueProjection
  length : Nat
deriving Repr

structure State where
  locals : List (VarId × CellId) := []
  cells : List Cell := []
  nextCell : CellId := 0
  heap : Heap := {}
  world : World.State := {}
  i32ArrayViews : List I32ArrayView := []

inductive Completion where
  | next
  | returned (value : Option Value)
  | breakLoop
  | continueLoop

inductive Outcome (α : Type) where
  | done (value : α) (state : State)
  | trapped (reason : Trap) (state : State)
  | exited (code : Int) (state : State)
  | outOfFuel

def State.cellId? (state : State) (id : VarId) : Option CellId :=
  (state.locals.find? (fun binding => binding.1 == id)).map Prod.snd

def State.cellEntry? (state : State) (id : CellId) : Option Cell :=
  state.cells.find? (fun cell => cell.id == id)

def State.cell? (state : State) (id : CellId) : Option Value :=
  state.cellEntry? id |>.bind Cell.value

def State.local? (state : State) (id : VarId) : Option Value :=
  state.cellId? id |>.bind state.cell?

def replaceCell : List Cell → CellId → Value → List Cell
  | [], _, _ => []
  | cell :: rest, id, value =>
      if cell.id == id then
        { cell with value := some value } :: replaceCell rest id value
      else cell :: replaceCell rest id value

def State.assignCell (state : State) (id : CellId) (value : Value) : Option State :=
  if state.cellEntry? id |>.isSome then
    some { state with cells := replaceCell state.cells id value }
  else
    none

def State.assignLocal (state : State) (id : VarId) (value : Value) : Option State :=
  state.cellId? id |>.bind fun cell => state.assignCell cell value

def State.bindCell (state : State) (id : VarId) (value : Option Value) : State :=
  let cell : Cell := { id := state.nextCell, value }
  {
    state with
    locals := (id, cell.id) :: state.locals
    cells := state.cells ++ [cell]
    nextCell := state.nextCell + 1
  }

def State.allocateTemporary (state : State) (value : Value) : CellId × State :=
  let cell : Cell := { id := state.nextCell, value := some value }
  (cell.id, {
    state with
    cells := state.cells ++ [cell]
    nextCell := state.nextCell + 1
  })

def State.bindLocal (state : State) (id : VarId) (value : Value) : State :=
  state.bindCell id (some value)

def State.bindUninitialized (state : State) (id : VarId) : State :=
  state.bindCell id none

private def removeFirstLocal : List (VarId × CellId) → VarId → List (VarId × CellId)
  | [], _ => []
  | binding :: rest, id =>
      if binding.1 == id then rest else binding :: removeFirstLocal rest id

def State.unbindLocal (state : State) (id : VarId) : State :=
  { state with locals := removeFirstLocal state.locals id }

private theorem mem_removeFirstLocal
    (binding : VarId × CellId) (bindings : List (VarId × CellId)) (id : VarId) :
    binding ∈ removeFirstLocal bindings id → binding ∈ bindings := by
  induction bindings with
  | nil => simp [removeFirstLocal]
  | cons head tail inductionHypothesis =>
      simp only [removeFirstLocal]
      split
      · intro member
        exact List.mem_cons_of_mem head member
      · intro member
        simp only [List.mem_cons] at member ⊢
        rcases member with headEqual | tailMember
        · exact .inl headEqual
        · exact .inr (inductionHypothesis tailMember)

theorem State.mem_of_mem_unbindLocal
    (state : State) (id : VarId) (binding : VarId × CellId)
    (member : binding ∈ (state.unbindLocal id).locals) :
    binding ∈ state.locals := by
  exact mem_removeFirstLocal binding state.locals id member

def State.bindLocals (state : State) (bindings : List (VarId × Value)) : State :=
  bindings.foldl (fun result binding => result.bindLocal binding.1 binding.2) state

def State.unbindLocals (state : State) (bindings : List (VarId × Value)) : State :=
  bindings.foldl (fun result binding => result.unbindLocal binding.1) state

def bindParameters
    (parameters : List (VarId × Ty)) (arguments : List Value) : Option (List (VarId × Value)) :=
  if parameters.length == arguments.length then
    some ((parameters.zip arguments).map fun pair => (pair.1.1, pair.2))
  else
    none

def signedModulus (target : Target) (type : SignedIntTy) : Int :=
  2 ^ type.bits target

def signedSignBit (target : Target) (type : SignedIntTy) : Int :=
  2 ^ (type.bits target - 1)

def wrapSigned (target : Target) (type : SignedIntTy) (value : Int) : Int :=
  let modulus := signedModulus target type
  let bits := value % modulus
  let signBit := signedSignBit target type
  if bits >= signBit then bits - modulus else bits

def unsignedModulus (target : Target) (type : UnsignedIntTy) : Nat :=
  2 ^ type.bits target

def wrapUnsigned (target : Target) (type : UnsignedIntTy) (value : Nat) : Nat :=
  value % unsignedModulus target type

def wrapUnsignedInt (target : Target) (type : UnsignedIntTy) (value : Int) : Nat :=
  Int.toNat (value % Int.ofNat (unsignedModulus target type))

private def signedBits (target : Target) (type : SignedIntTy) (value : Int) : Nat :=
  Int.toNat (value % signedModulus target type)

def truncDiv (left right : Int) : Int :=
  let quotient := left.natAbs / right.natAbs
  if (left < 0) = (right < 0) then Int.ofNat quotient else -Int.ofNat quotient

private def arithmeticShiftRight (value : Int) (amount : Nat) : Int :=
  let divisor : Int := Int.ofNat (2 ^ amount)
  if value >= 0 then value / divisor else -((-value + divisor - 1) / divisor)

def scalarEqual : Value → Value → Option Bool
  | .unit, .unit => some true
  | .boolean left, .boolean right => some (left == right)
  | .signed leftType left, .signed rightType right =>
      if leftType == rightType then some (left == right) else none
  | .unsigned leftType left, .unsigned rightType right =>
      if leftType == rightType then some (left == right) else none
  | .f32Bits left, .f32Bits right =>
      some (Float32.beq (Float32.ofBits left) (Float32.ofBits right))
  | .f64Bits left, .f64Bits right =>
      some (Float.beq (Float.ofBits left) (Float.ofBits right))
  | .character left, .character right => some (left == right)
  | .string left, .string right => some (left == right)
  | .pointer left, .pointer right => some (left == right)
  | _, _ => none

mutual
  def matchPattern : Pattern → Value → Option (List (VarId × Value))
    | .wildcard, _ => some []
    | .bind id, value => some [(id, value)]
    | .literal expected, value =>
        match scalarEqual expected value with
        | some true => some []
        | _ => none
    | .enumVariant expectedType expectedVariant patterns,
        .enumeration actualType actualVariant values =>
        if expectedType == actualType && expectedVariant == actualVariant then
          matchPatterns patterns values
        else
          none
    | _, _ => none

  def matchPatterns : List Pattern → List Value → Option (List (VarId × Value))
    | [], [] => some []
    | pattern :: patterns, value :: values =>
        match matchPattern pattern value, matchPatterns patterns values with
        | some head, some tail => some (head ++ tail)
        | _, _ => none
    | _, _ => none
end

def evalUnaryValue (target : Target) (op : UnaryOp) (value : Value) : Except Trap Value :=
  match op, value with
  | .positive, value@(.signed _ _) => .ok value
  | .positive, value@(.unsigned _ _) => .ok value
  | .positive, value@(.f32Bits _) => .ok value
  | .positive, value@(.f64Bits _) => .ok value
  | .positive, value@(.character _) => .ok value
  | .logicalNot, .boolean value => .ok (.boolean !value)
  | .negate, .signed type value => .ok (.signed type (wrapSigned target type (-value)))
  | .negate, .unsigned type value =>
      .ok (.unsigned type (wrapUnsignedInt target type (-(Int.ofNat value))))
  | .negate, .f32Bits bits => .ok (.f32Bits (Float32.neg (Float32.ofBits bits)).toBits)
  | .negate, .f64Bits bits => .ok (.f64Bits (Float.neg (Float.ofBits bits)).toBits)
  | .negate, .character value =>
      .ok (.character (UInt32.ofNat ((2 ^ 32 - value.toNat) % (2 ^ 32))))
  | _, _ => .error .typeMismatch

def evalScalarCast (target : Target) (destination : ScalarTy)
    (value : Value) : Except Trap Value :=
  match destination, value with
  | .signed targetType, .signed _ source =>
      .ok (.signed targetType (wrapSigned target targetType source))
  | .unsigned targetType, .signed _ source =>
      .ok (.unsigned targetType (wrapUnsignedInt target targetType source))
  | .signed targetType, .unsigned _ source =>
      .ok (.signed targetType (wrapSigned target targetType (Int.ofNat source)))
  | .unsigned targetType, .unsigned _ source =>
      .ok (.unsigned targetType (wrapUnsigned target targetType source))
  | .f32, .signed _ source => .ok (.f32Bits (Float32.ofInt source).toBits)
  | .f64, .signed _ source => .ok (.f64Bits (Float.ofInt source).toBits)
  | .f32, .unsigned _ source => .ok (.f32Bits (Float32.ofInt (Int.ofNat source)).toBits)
  | .f64, .unsigned _ source => .ok (.f64Bits (Float.ofNat source).toBits)
  | .signed targetType, .character source =>
      .ok (.signed targetType (wrapSigned target targetType (Int.ofNat source.toNat)))
  | .unsigned targetType, .character source =>
      .ok (.unsigned targetType (wrapUnsigned target targetType source.toNat))
  | .f32, .character source =>
      .ok (.f32Bits (Float32.ofInt (Int.ofNat source.toNat)).toBits)
  | .f64, .character source => .ok (.f64Bits (Float.ofNat source.toNat).toBits)
  | .f64, .f32Bits source => .ok (.f64Bits (Float32.ofBits source).toFloat.toBits)
  | .f32, .f64Bits source => .ok (.f32Bits (Float.ofBits source).toFloat32.toBits)
  | _, _ => .error .typeMismatch

def evalSignedBinary
    (target : Target) (op : BinaryOp) (type : SignedIntTy)
    (left right : Int) : Except Trap Value :=
  let result := fun value => Value.signed type (wrapSigned target type value)
  let minimum := -signedSignBit target type
  match op with
  | .less => .ok (.boolean (left < right))
  | .lessEqual => .ok (.boolean (left <= right))
  | .greater => .ok (.boolean (left > right))
  | .greaterEqual => .ok (.boolean (left >= right))
  | .add => .ok (result (left + right))
  | .subtract => .ok (result (left - right))
  | .multiply => .ok (result (left * right))
  | .divide =>
      if right == 0 then .error .divisionByZero
      else if left == minimum && right == -1 then .error .signedDivisionOverflow
      else .ok (result (truncDiv left right))
  | .remainder =>
      if right == 0 then .error .divisionByZero
      else if left == minimum && right == -1 then .error .signedDivisionOverflow
      else .ok (result (left - truncDiv left right * right))
  | .bitAnd =>
      .ok (result (Int.ofNat (Nat.land
        (signedBits target type left) (signedBits target type right))))
  | .bitOr =>
      .ok (result (Int.ofNat (Nat.lor
        (signedBits target type left) (signedBits target type right))))
  | .bitXor =>
      .ok (result (Int.ofNat (Nat.xor
        (signedBits target type left) (signedBits target type right))))
  | .shiftLeft =>
      if right < 0 || right >= Int.ofNat (type.bits target) then .error .invalidShift
      else .ok (result (left * Int.ofNat (2 ^ Int.toNat right)))
  | .shiftRight =>
      if right < 0 || right >= Int.ofNat (type.bits target) then .error .invalidShift
      else .ok (result (arithmeticShiftRight left (Int.toNat right)))
  | _ => .error .typeMismatch

def evalUnsignedBinary
    (target : Target) (op : BinaryOp) (type : UnsignedIntTy)
    (left right : Nat) : Except Trap Value :=
  let modulus := unsignedModulus target type
  let result := fun value => Value.unsigned type (wrapUnsigned target type value)
  match op with
  | .less => .ok (.boolean (left < right))
  | .lessEqual => .ok (.boolean (left <= right))
  | .greater => .ok (.boolean (left > right))
  | .greaterEqual => .ok (.boolean (left >= right))
  | .add => .ok (result (left + right))
  | .subtract => .ok (result (left + modulus - right % modulus))
  | .multiply => .ok (result (left * right))
  | .divide => if right == 0 then .error .divisionByZero else .ok (result (left / right))
  | .remainder => if right == 0 then .error .divisionByZero else .ok (result (left % right))
  | .bitAnd => .ok (result (Nat.land left right))
  | .bitOr => .ok (result (Nat.lor left right))
  | .bitXor => .ok (result (Nat.xor left right))
  | .shiftLeft =>
      if right >= type.bits target then .error .invalidShift
      else .ok (result (left * 2 ^ right))
  | .shiftRight =>
      if right >= type.bits target then .error .invalidShift
      else .ok (result (left / 2 ^ right))
  | _ => .error .typeMismatch

def evalF32Binary (op : BinaryOp) (leftBits rightBits : UInt32) : Except Trap Value :=
  let left := Float32.ofBits leftBits
  let right := Float32.ofBits rightBits
  let result := fun value : Float32 => Value.f32Bits value.toBits
  match op with
  | .less => .ok (.boolean (left < right))
  | .lessEqual => .ok (.boolean (left <= right))
  | .greater => .ok (.boolean (left > right))
  | .greaterEqual => .ok (.boolean (left >= right))
  | .add => .ok (result (left + right))
  | .subtract => .ok (result (left - right))
  | .multiply => .ok (result (left * right))
  | .divide => .ok (result (left / right))
  | _ => .error .typeMismatch

def evalF64Binary (op : BinaryOp) (leftBits rightBits : UInt64) : Except Trap Value :=
  let left := Float.ofBits leftBits
  let right := Float.ofBits rightBits
  let result := fun value : Float => Value.f64Bits value.toBits
  match op with
  | .less => .ok (.boolean (left < right))
  | .lessEqual => .ok (.boolean (left <= right))
  | .greater => .ok (.boolean (left > right))
  | .greaterEqual => .ok (.boolean (left >= right))
  | .add => .ok (result (left + right))
  | .subtract => .ok (result (left - right))
  | .multiply => .ok (result (left * right))
  | .divide => .ok (result (left / right))
  | _ => .error .typeMismatch

def evalCharBinary
    (op : BinaryOp) (leftCode rightCode : UInt32) : Except Trap Value :=
  let left := leftCode.toNat
  let right := rightCode.toNat
  let modulus := 2 ^ 32
  let result := fun value => Value.character (UInt32.ofNat (value % modulus))
  match op with
  | .less => .ok (.boolean (left < right))
  | .lessEqual => .ok (.boolean (left <= right))
  | .greater => .ok (.boolean (left > right))
  | .greaterEqual => .ok (.boolean (left >= right))
  | .add => .ok (result (left + right))
  | .subtract => .ok (result (left + modulus - right % modulus))
  | .multiply => .ok (result (left * right))
  | .divide => if right == 0 then .error .divisionByZero else .ok (result (left / right))
  | .remainder =>
      if right == 0 then .error .divisionByZero else .ok (result (left % right))
  | .bitAnd => .ok (result (Nat.land left right))
  | .bitOr => .ok (result (Nat.lor left right))
  | .bitXor => .ok (result (Nat.xor left right))
  | .shiftLeft =>
      if right >= 32 then .error .invalidShift else .ok (result (left * 2 ^ right))
  | .shiftRight =>
      if right >= 32 then .error .invalidShift else .ok (result (left / 2 ^ right))
  | _ => .error .typeMismatch

def pointerOffset
    (target : Target) (subtract : Bool) (address : Address) (offset : Int) : Value :=
  let modulus : Int := 2 ^ target.pointerWidth.bits
  let result := if subtract then Int.ofNat address - offset else Int.ofNat address + offset
  .pointer (Int.toNat (result % modulus))

def evalBinaryValue
    (target : Target) (op : BinaryOp) (left right : Value) : Except Trap Value :=
  match op, left, right with
  | .logicalAnd, .boolean left, .boolean right => .ok (.boolean (left && right))
  | .logicalOr, .boolean left, .boolean right => .ok (.boolean (left || right))
  | .equal, left, right =>
      match scalarEqual left right with
      | some equal => .ok (.boolean equal)
      | none => .error .typeMismatch
  | .notEqual, left, right =>
      match scalarEqual left right with
      | some equal => .ok (.boolean !equal)
      | none => .error .typeMismatch
  | .add, .pointer address, .signed _ offset =>
      .ok (pointerOffset target false address offset)
  | .add, .pointer address, .unsigned _ offset =>
      .ok (pointerOffset target false address (Int.ofNat offset))
  | .add, .pointer address, .character offset =>
      .ok (pointerOffset target false address (Int.ofNat offset.toNat))
  | .subtract, .pointer address, .signed _ offset =>
      .ok (pointerOffset target true address offset)
  | .subtract, .pointer address, .unsigned _ offset =>
      .ok (pointerOffset target true address (Int.ofNat offset))
  | .subtract, .pointer address, .character offset =>
      .ok (pointerOffset target true address (Int.ofNat offset.toNat))
  | op, .signed leftType left, .signed rightType right =>
      if leftType == rightType then evalSignedBinary target op leftType left right
      else .error .typeMismatch
  | op, .unsigned leftType left, .unsigned rightType right =>
      if leftType == rightType then evalUnsignedBinary target op leftType left right
      else .error .typeMismatch
  | op, .f32Bits left, .f32Bits right => evalF32Binary op left right
  | op, .f64Bits left, .f64Bits right => evalF64Binary op left right
  | op, .character left, .character right => evalCharBinary op left right
  | _, _, _ => .error .typeMismatch

def assignOpBinary? : AssignOp → Option BinaryOp
  | .set => none
  | .add => some .add
  | .subtract => some .subtract
  | .multiply => some .multiply
  | .divide => some .divide
  | .remainder => some .remainder
  | .bitXor => some .bitXor
  | .shiftLeft => some .shiftLeft
  | .shiftRight => some .shiftRight
  | .bitAnd => some .bitAnd
  | .bitOr => some .bitOr

def evalAssignValue
    (target : Target) (op : AssignOp) (current : Option Value) (right : Value) :
    Except Trap Value :=
  match assignOpBinary? op with
  | none => .ok right
  | some binary =>
      match current with
      | none => .error .uninitializedLocal
      | some left => evalBinaryValue target binary left right

/-- Exactly the expression forms that preserve an existing storage identity
    can back a raw aggregate view without first allocating a temporary. -/
def expressionPlace? : Expr → Option Place
  | .local id => some (.local id)
  | .field base field => do
      let place ← expressionPlace? base
      pure (.field place field)
  | .index base index => do
      let place ← expressionPlace? base
      pure (.index place index)
  | _ => none

def setValue : List Value → Nat → Value → List Value
  | [], _, _ => []
  | _ :: rest, 0, value => value :: rest
  | first :: rest, index + 1, value => first :: setValue rest index value

def integerIndex : Value → Except Trap Nat
  | .signed _ value => if value < 0 then .error .arrayBounds else .ok value.toNat
  | .unsigned _ value => .ok value
  | _ => .error .typeMismatch

structure ResolvedPlace where
  root : CellId
  projections : List ValueProjection
  value : Option Value

def replaceProjectedValue : Value → List ValueProjection → Value → Except Trap Value
  | _, [], replacement => .ok replacement
  | .structure id fields, .field field :: rest, replacement =>
      match fields[field]? with
      | none => .error .typeMismatch
      | some old =>
          match replaceProjectedValue old rest replacement with
          | .ok updated => .ok (.structure id (setValue fields field updated))
          | .error reason => .error reason
  | .array elements, .index index :: rest, replacement =>
      match elements[index]? with
      | none => .error .arrayBounds
      | some old =>
          match replaceProjectedValue old rest replacement with
          | .ok updated => .ok (.array (setValue elements index updated))
          | .error reason => .error reason
  | _, _, _ => .error .typeMismatch

def writeResolvedPlace
    (state : State) (place : ResolvedPlace) (value : Value) : Except Trap State :=
  match place.projections with
  | [] =>
      match state.assignCell place.root value with
      | some assigned => .ok assigned
      | none => .error .typeMismatch
  | _ =>
      match state.cellEntry? place.root with
      | none => .error .typeMismatch
      | some { value := none, .. } => .error .uninitializedLocal
      | some { value := some rootValue, .. } =>
          match replaceProjectedValue rootValue place.projections value with
          | .error reason => .error reason
          | .ok updated =>
              match state.assignCell place.root updated with
              | some assigned => .ok assigned
              | none => .error .typeMismatch

def projectedValue : Value → List ValueProjection → Except Trap Value
  | value, [] => .ok value
  | .structure _ fields, .field field :: rest =>
      match fields[field]? with
      | none => .error .typeMismatch
      | some value => projectedValue value rest
  | .array elements, .index index :: rest =>
      match elements[index]? with
      | none => .error .arrayBounds
      | some value => projectedValue value rest
  | _, _ => .error .typeMismatch

def readCellProjection
    (state : State) (cell : CellId) (projections : List ValueProjection) :
    Except Trap Value :=
  match state.cellEntry? cell with
  | none => .error .invalidPointer
  | some { value := none, .. } => .error .uninitializedLocal
  | some { value := some root, .. } => projectedValue root projections

def i32Bytes (value : Int) : List UInt8 :=
  let bits := Int.toNat (value % (2 ^ 32))
  (List.range 4).map fun index => UInt8.ofNat ((bits / (2 ^ (8 * index))) % 256)

def encodeI32Array : List Value → Except Trap (List UInt8)
  | [] => .ok []
  | .signed .i32 value :: rest =>
      match encodeI32Array rest with
      | .ok bytes => .ok (i32Bytes value ++ bytes)
      | .error reason => .error reason
  | _ => .error .typeMismatch

def decodeI32 : List UInt8 → Int
  | byte0 :: byte1 :: byte2 :: byte3 :: _ =>
      let bits := byte0.toNat + byte1.toNat * 2 ^ 8 +
        byte2.toNat * 2 ^ 16 + byte3.toNat * 2 ^ 24
      if bits >= 2 ^ 31 then Int.ofNat bits - 2 ^ 32 else Int.ofNat bits
  | _ => 0

def decodeI32Array : Nat → List UInt8 → Except Trap (List Value)
  | 0, bytes => if bytes.isEmpty then .ok [] else .error .rawMemoryBounds
  | length + 1, bytes =>
      if bytes.length < 4 then .error .rawMemoryBounds
      else
        match decodeI32Array length (bytes.drop 4) with
        | .ok rest => .ok (.signed .i32 (decodeI32 (bytes.take 4)) :: rest)
        | .error reason => .error reason

def State.i32ArrayView?
    (state : State) (root : CellId) (projections : List ValueProjection) :
    Option I32ArrayView :=
  state.i32ArrayViews.find? fun view =>
    decide (view.root = root ∧ view.projections = projections)

def syncI32ViewsToHeapFrom :
    List I32ArrayView → State → Except Trap State
  | [], state => .ok state
  | view :: rest, state =>
      match readCellProjection state view.root view.projections with
      | .ok (.array elements) =>
          if elements.length != view.length then .error .typeMismatch
          else
            match encodeI32Array elements with
            | .error reason => .error reason
            | .ok bytes =>
                match state.heap.storeBytes view.address bytes with
                | .error reason => .error reason
                | .ok heap => syncI32ViewsToHeapFrom rest { state with heap }
      | .ok _ => .error .typeMismatch
      | .error reason => .error reason

def syncI32ViewsToHeap (state : State) : Except Trap State :=
  syncI32ViewsToHeapFrom state.i32ArrayViews state

def syncI32ViewsFromHeapFrom :
    List I32ArrayView → State → Except Trap State
  | [], state => .ok state
  | view :: rest, state =>
      match state.heap.loadBytes view.address (view.length * 4) with
      | .error reason => .error reason
      | .ok bytes =>
          match decodeI32Array view.length bytes with
          | .error reason => .error reason
          | .ok elements =>
              match writeResolvedPlace state
                  { root := view.root, projections := view.projections, value := none }
                  (.array elements) with
              | .error reason => .error reason
              | .ok next => syncI32ViewsFromHeapFrom rest next

def syncI32ViewsFromHeap (state : State) : Except Trap State :=
  syncI32ViewsFromHeapFrom state.i32ArrayViews state

def mapI32ArrayView
    (state : State) (root : CellId) (projections : List ValueProjection)
    (elements : List Value) : Outcome Value :=
  match state.i32ArrayView? root projections with
  | some view =>
      match syncI32ViewsToHeap state with
      | .ok synchronized => .done (.pointer view.address) synchronized
      | .error reason => .trapped reason state
  | none =>
      match encodeI32Array elements with
      | .error reason => .trapped reason state
      | .ok bytes =>
          match state.heap.mapBorrowed bytes 4 with
          | .allocated address heap =>
              let view : I32ArrayView := {
                address, root, projections, length := elements.length
              }
              .done (.pointer address) {
                state with
                heap
                i32ArrayViews := state.i32ArrayViews ++ [view]
              }
          | .exhausted heap => .trapped .allocationFailure { state with heap }
          | .trapped reason heap => .trapped reason { state with heap }

def worldCallOutcome
    (functionId : FunctionId) (state : State) : World.EffectResult → Outcome Value
  | .returned value heap world =>
      match syncI32ViewsFromHeap { state with heap, world } with
      | .ok next => .done value next
      | .error reason => .trapped reason { state with heap, world }
  | .exited code heap world =>
      match syncI32ViewsFromHeap { state with heap, world } with
      | .ok next => .exited code next
      | .error reason => .trapped reason { state with heap, world }
  | .unavailable _ heap world =>
      .trapped (.unmodeledExtern functionId) { state with heap, world }
  | .trapped reason heap world =>
      .trapped reason { state with heap, world }
  | .typeMismatch heap world =>
      .trapped .typeMismatch { state with heap, world }

def opaqueCallOutcome
    (external : ExternId) (state : State) : World.OpaqueCallResult → Outcome Value
  | .returned value world =>
      match syncI32ViewsFromHeap { state with world } with
      | .ok next => .done value next
      | .error reason => .trapped reason { state with world }
  | .trapped reason world => .trapped reason { state with world }
  | .unmodeled world => .trapped (.unmodeledExtern external) { state with world }

def sliceValues
    (state : State) (cell : CellId) (projections : List ValueProjection)
    (start length : Nat) : Except Trap (List Value) :=
  match readCellProjection state cell projections with
  | .ok (.array elements) =>
      if start + length ≤ elements.length then
        .ok ((elements.drop start).take length)
      else
        .error .arrayBounds
  | .ok _ => .error .typeMismatch
  | .error reason => .error reason

def dereferenceValue (state : State) : Value → Except Trap Value
  | .reference _ cell projections =>
      readCellProjection state cell projections
  | _ => .error .typeMismatch

def restoreLocals (caller : State) (completed : State) : State :=
  { completed with locals := caller.locals }

def restoreOutcomeLocals (caller : State) : Outcome α → Outcome α
  | .done value completed => .done value (restoreLocals caller completed)
  | .trapped reason completed => .trapped reason (restoreLocals caller completed)
  | .exited code completed => .exited code (restoreLocals caller completed)
  | .outOfFuel => .outOfFuel

def rangeFinished (current : Int) (stop : Option Int) (inclusive : Bool) : Bool :=
  match stop with
  | none => false
  | some bound => if inclusive then current > bound else current >= bound

mutual
  def evalExpr : Nat → Program → State → Expr → Outcome Value
    | 0, _, _, _ => .outOfFuel
    | fuel + 1, program, state, expression =>
        match expression with
        | .value value => .done value state
        | .local id =>
            match state.cellId? id with
            | none => .trapped .typeMismatch state
            | some cell =>
                match state.cellEntry? cell with
                | none => .trapped .typeMismatch state
                | some { value := none, .. } => .trapped .uninitializedLocal state
                | some { value := some value, .. } => .done value state
        | .cast targetType operand =>
            match evalExpr fuel program state operand with
            | .done value next =>
                match evalScalarCast program.target targetType value with
                | .ok result => .done result next
                | .error reason => .trapped reason next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .unary op operand =>
            match evalExpr fuel program state operand with
            | .done value next =>
                match evalUnaryValue program.target op value with
                | .ok result => .done result next
                | .error reason => .trapped reason next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .binary .logicalAnd left right =>
            match evalExpr fuel program state left with
            | .done (.boolean false) next => .done (.boolean false) next
            | .done (.boolean true) next => evalExpr fuel program next right
            | .done _ next => .trapped .typeMismatch next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .binary .logicalOr left right =>
            match evalExpr fuel program state left with
            | .done (.boolean true) next => .done (.boolean true) next
            | .done (.boolean false) next => evalExpr fuel program next right
            | .done _ next => .trapped .typeMismatch next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .binary op left right =>
            match evalExpr fuel program state left with
            | .done leftValue afterLeft =>
                match evalExpr fuel program afterLeft right with
                | .done rightValue afterRight =>
                    match evalBinaryValue program.target op leftValue rightValue with
                    | .ok result => .done result afterRight
                    | .error reason => .trapped reason afterRight
                | .trapped reason next => .trapped reason next
                | .exited code exitedState => .exited code exitedState
                | .outOfFuel => .outOfFuel
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .array _ elements =>
            match evalExprs fuel program state elements with
            | .done values next => .done (.array values) next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .arrayToSlice elementType array =>
            match expressionPlace? array with
            | some place =>
                match evalPlace fuel program state place with
                | .done { root, projections, value := some (.array elements) } next =>
                    .done (.slice elementType root projections 0 elements.length) next
                | .done { value := none, .. } next => .trapped .uninitializedLocal next
                | .done _ next => .trapped .typeMismatch next
                | .trapped reason next => .trapped reason next
                | .exited code exitedState => .exited code exitedState
                | .outOfFuel => .outOfFuel
            | none =>
                match evalExpr fuel program state array with
                | .done (.array elements) next =>
                    let (root, withTemporary) := next.allocateTemporary (.array elements)
                    .done (.slice elementType root [] 0 elements.length) withTemporary
                | .done _ next => .trapped .typeMismatch next
                | .trapped reason next => .trapped reason next
                | .exited code exitedState => .exited code exitedState
                | .outOfFuel => .outOfFuel
        | .index base index =>
            match evalExpr fuel program state base with
            | .done (.array elements) afterBase =>
                match evalExpr fuel program afterBase index with
                | .done value afterIndex =>
                    match integerIndex value with
                    | .error reason => .trapped reason afterIndex
                    | .ok index =>
                        match elements[index]? with
                        | some result => .done result afterIndex
                        | none => .trapped .arrayBounds afterIndex
                | .trapped reason next => .trapped reason next
                | .exited code exitedState => .exited code exitedState
                | .outOfFuel => .outOfFuel
            | .done (.slice _ cell projections start length) afterBase =>
                match evalExpr fuel program afterBase index with
                | .done indexValue afterIndex =>
                    match integerIndex indexValue with
                    | .error reason => .trapped reason afterIndex
                    | .ok index =>
                        if index < length then
                          match sliceValues afterIndex cell projections start length with
                          | .ok elements =>
                              match elements[index]? with
                              | some result => .done result afterIndex
                              | none => .trapped .arrayBounds afterIndex
                          | .error reason => .trapped reason afterIndex
                        else
                          .trapped .arrayBounds afterIndex
                | .trapped reason next => .trapped reason next
                | .exited code exitedState => .exited code exitedState
                | .outOfFuel => .outOfFuel
            | .done _ next => .trapped .typeMismatch next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .structValue id fields =>
            match evalExprs fuel program state fields with
            | .done values next => .done (.structure id values) next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .field base field =>
            match evalExpr fuel program state base with
            | .done (.structure _ fields) next =>
                match fields[field]? with
                | some value => .done value next
                | none => .trapped .typeMismatch next
            | .done _ next => .trapped .typeMismatch next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .enumValue id variant payload =>
            match evalExprs fuel program state payload with
            | .done values next => .done (.enumeration id variant values) next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .matchValue scrutinee arms =>
            match evalExpr fuel program state scrutinee with
            | .done value next => evalMatchArms fuel program next value arms
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .assign op place valueExpression =>
            match evalPlace fuel program state place with
            | .done resolved afterPlace =>
                match evalExpr fuel program afterPlace valueExpression with
                | .done right afterValue =>
                    match evalAssignValue program.target op resolved.value right with
                    | .error reason => .trapped reason afterValue
                    | .ok result =>
                        match writeResolvedPlace afterValue resolved result with
                        | .ok assigned => .done .unit assigned
                        | .error reason => .trapped reason afterValue
                | .trapped reason next => .trapped reason next
                | .exited code exitedState => .exited code exitedState
                | .outOfFuel => .outOfFuel
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .borrow referent place =>
            match evalPlace fuel program state place with
            | .done { value := none, .. } next => .trapped .uninitializedLocal next
            | .done resolved next =>
                .done (.reference referent resolved.root resolved.projections) next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .dereference reference =>
            match evalExpr fuel program state reference with
            | .done value next =>
                match dereferenceValue next value with
                | .ok result => .done result next
                | .error reason => .trapped reason next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .constant id =>
            match program.constant? id with
            | some declaration => .done declaration.value state
            | none => .trapped .typeMismatch state
        | .call id arguments =>
            match evalExprs fuel program state arguments with
            | .done values afterArguments =>
                match program.function? id with
                | none => .trapped .typeMismatch afterArguments
                | some function =>
                    match function.body, bindParameters function.parameters values with
                    | _, none => .trapped .typeMismatch afterArguments
                    | none, some _ =>
                        match function.external with
                        | none => .trapped .typeMismatch afterArguments
                        | some (.unavailable capability) =>
                            .trapped (.serviceUnavailable capability) afterArguments
                        | some .panic => .trapped .panic afterArguments
                        | some .unreachable => .trapped .reachedUnreachable afterArguments
                        | some (.opaque externId) =>
                            match syncI32ViewsToHeap afterArguments with
                            | .error reason => .trapped reason afterArguments
                            | .ok synchronized =>
                                opaqueCallOutcome externId synchronized
                                  (synchronized.world.callOpaque externId values)
                        | some (.host service) =>
                            match syncI32ViewsToHeap afterArguments with
                            | .error reason => .trapped reason afterArguments
                            | .ok synchronized =>
                                worldCallOutcome id synchronized
                                  (World.call synchronized.heap synchronized.world
                                    service values)
                    | some body, some locals =>
                        let callee := ({ afterArguments with locals := [] }).bindLocals locals
                        match execStmt fuel program callee body with
                        | .done (.returned (some value)) completed =>
                            .done value (restoreLocals afterArguments completed)
                        | .done (.returned none) completed =>
                            if function.returnType = .unit then
                              .done .unit (restoreLocals afterArguments completed)
                            else
                              .trapped .missingReturn (restoreLocals afterArguments completed)
                        | .done .next completed =>
                            if function.returnType = .unit then
                              .done .unit (restoreLocals afterArguments completed)
                            else
                              .trapped .missingReturn (restoreLocals afterArguments completed)
                        | .done _ completed =>
                            .trapped .typeMismatch (restoreLocals afterArguments completed)
                        | .trapped reason completed =>
                            .trapped reason (restoreLocals afterArguments completed)
                        | .exited code exitedState =>
                            .exited code (restoreLocals afterArguments exitedState)
                        | .outOfFuel => .outOfFuel
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .intrinsic operation argument =>
            match evalExpr fuel program state argument with
            | .done value next =>
                match operation, value with
                | .printI32, .signed .i32 integer =>
                    .done .unit { next with world := next.world.afterPrintI32 integer }
                | .assert, .boolean true => .done .unit next
                | .assert, .boolean false => .trapped .assertionFailed next
                | _, _ => .trapped .typeMismatch next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .i32ArrayDataPtr array =>
            match expressionPlace? array with
            | some place =>
                match evalPlace fuel program state place with
                | .done { root, projections, value := some (.array elements) } next =>
                    mapI32ArrayView next root projections elements
                | .done { value := none, .. } next => .trapped .uninitializedLocal next
                | .done _ next => .trapped .typeMismatch next
                | .trapped reason next => .trapped reason next
                | .exited code exitedState => .exited code exitedState
                | .outOfFuel => .outOfFuel
            | none =>
                match evalExpr fuel program state array with
                | .done (.array elements) next =>
                    let (root, withTemporary) := next.allocateTemporary (.array elements)
                    mapI32ArrayView withTemporary root [] elements
                | .done _ next => .trapped .typeMismatch next
                | .trapped reason next => .trapped reason next
                | .exited code exitedState => .exited code exitedState
                | .outOfFuel => .outOfFuel
        | .alloc size alignment =>
            match evalExpr fuel program state size with
            | .done (.unsigned .usize sizeValue) afterSize =>
                match evalExpr fuel program afterSize alignment with
                | .done (.unsigned .usize alignmentValue) afterAlignment =>
                    match afterAlignment.heap.allocate sizeValue alignmentValue with
                    | .allocated pointer heap => .done (.pointer pointer) { afterAlignment with heap }
                    | .exhausted heap => .done (.pointer null) { afterAlignment with heap }
                    | .trapped reason heap => .trapped reason { afterAlignment with heap }
                | .done _ next => .trapped .typeMismatch next
                | .trapped reason next => .trapped reason next
                | .exited code exitedState => .exited code exitedState
                | .outOfFuel => .outOfFuel
            | .done _ next => .trapped .typeMismatch next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .realloc pointer oldSize newSize alignment =>
            match evalExprs fuel program state [pointer, oldSize, newSize, alignment] with
            | .done [.pointer pointerValue, .unsigned .usize oldSizeValue,
                .unsigned .usize newSizeValue, .unsigned .usize alignmentValue] next =>
                match syncI32ViewsToHeap next with
                | .error reason => .trapped reason next
                | .ok synchronized =>
                    match synchronized.heap.reallocate pointerValue oldSizeValue
                        newSizeValue alignmentValue with
                    | .allocated replacement heap =>
                        .done (.pointer replacement) { synchronized with heap }
                    | .exhausted heap => .done (.pointer null) { synchronized with heap }
                    | .trapped reason heap => .trapped reason { synchronized with heap }
            | .done _ next => .trapped .typeMismatch next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .dealloc pointer size alignment =>
            match evalExprs fuel program state [pointer, size, alignment] with
            | .done [.pointer pointerValue, .unsigned .usize sizeValue,
                .unsigned .usize alignmentValue] next =>
                match syncI32ViewsToHeap next with
                | .error reason => .trapped reason next
                | .ok synchronized =>
                    match synchronized.heap.deallocate pointerValue sizeValue alignmentValue with
                    | .ok heap => .done .unit { synchronized with heap }
                    | .error reason => .trapped reason synchronized
            | .done _ next => .trapped .typeMismatch next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .loadByte pointer offset =>
            match evalExprs fuel program state [pointer, offset] with
            | .done [.pointer pointerValue, .unsigned .usize offsetValue] next =>
                match syncI32ViewsToHeap next with
                | .error reason => .trapped reason next
                | .ok synchronized =>
                    match synchronized.heap.loadByte pointerValue offsetValue with
                    | .ok value => .done (.unsigned .u8 value.toNat) synchronized
                    | .error reason => .trapped reason synchronized
            | .done _ next => .trapped .typeMismatch next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .storeByte pointer offset value =>
            match evalExprs fuel program state [pointer, offset, value] with
            | .done [.pointer pointerValue, .unsigned .usize offsetValue,
                .unsigned .u8 byteValue] next =>
                match syncI32ViewsToHeap next with
                | .error reason => .trapped reason next
                | .ok synchronized =>
                    match synchronized.heap.storeByte pointerValue offsetValue
                        (UInt8.ofNat byteValue) with
                    | .error reason => .trapped reason synchronized
                    | .ok heap =>
                        match syncI32ViewsFromHeap { synchronized with heap } with
                        | .ok updated => .done .unit updated
                        | .error reason => .trapped reason { synchronized with heap }
            | .done _ next => .trapped .typeMismatch next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel

  def evalExprs : Nat → Program → State → List Expr → Outcome (List Value)
    | 0, _, _, _ => .outOfFuel
    | _ + 1, _, state, [] => .done [] state
    | fuel + 1, program, state, expression :: expressions =>
        match evalExpr fuel program state expression with
        | .done value next =>
            match evalExprs fuel program next expressions with
            | .done values completed => .done (value :: values) completed
            | .trapped reason completed => .trapped reason completed
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .trapped reason next => .trapped reason next
        | .exited code exitedState => .exited code exitedState
        | .outOfFuel => .outOfFuel

  def evalMatchArms : Nat → Program → State → Value → List (Pattern × Expr) → Outcome Value
    | 0, _, _, _, _ => .outOfFuel
    | _ + 1, _, state, _, [] => .trapped .nonExhaustiveMatch state
    | fuel + 1, program, state, value, (pattern, body) :: arms =>
        match matchPattern pattern value with
        | none => evalMatchArms fuel program state value arms
        | some bindings =>
            restoreOutcomeLocals state
              (evalExpr fuel program (state.bindLocals bindings) body)

  def evalPlace : Nat → Program → State → Place → Outcome ResolvedPlace
    | 0, _, _, _ => .outOfFuel
    | _ + 1, _, state, .local id =>
        match state.cellId? id with
        | none => .trapped .typeMismatch state
        | some cell =>
            match state.cellEntry? cell with
            | none => .trapped .typeMismatch state
            | some entry =>
                .done { root := cell, projections := [], value := entry.value } state
    | fuel + 1, program, state, .field base field =>
        match evalPlace fuel program state base with
        | .done resolved next =>
            match resolved.value with
            | none => .trapped .uninitializedLocal next
            | some (.structure _ fields) =>
                match fields[field]? with
                | some value => .done {
                    resolved with
                    projections := resolved.projections ++ [.field field]
                    value := some value
                  } next
                | none => .trapped .typeMismatch next
            | _ => .trapped .typeMismatch next
        | .trapped reason next => .trapped reason next
        | .exited code exitedState => .exited code exitedState
        | .outOfFuel => .outOfFuel
    | fuel + 1, program, state, .index base indexExpression =>
        match evalPlace fuel program state base with
        | .done resolved afterBase =>
            match resolved.value with
            | none => .trapped .uninitializedLocal afterBase
            | some (.array elements) =>
                match evalExpr fuel program afterBase indexExpression with
                | .done indexValue afterIndex =>
                    match integerIndex indexValue with
                    | .error reason => .trapped reason afterIndex
                    | .ok index =>
                        match elements[index]? with
                        | some value => .done {
                            resolved with
                            projections := resolved.projections ++ [.index index]
                            value := some value
                          } afterIndex
                        | none => .trapped .arrayBounds afterIndex
                | .trapped reason next => .trapped reason next
                | .exited code exitedState => .exited code exitedState
                | .outOfFuel => .outOfFuel
            | some (.slice _ cell projections start length) =>
                match evalExpr fuel program afterBase indexExpression with
                | .done indexValue afterIndex =>
                    match integerIndex indexValue with
                    | .error reason => .trapped reason afterIndex
                    | .ok index =>
                        if index < length then
                          match sliceValues afterIndex cell projections start length with
                          | .error reason => .trapped reason afterIndex
                          | .ok elements =>
                              match elements[index]? with
                              | none => .trapped .arrayBounds afterIndex
                              | some value => .done {
                                  root := cell
                                  projections := projections ++ [.index (start + index)]
                                  value := some value
                                } afterIndex
                        else
                          .trapped .arrayBounds afterIndex
                | .trapped reason next => .trapped reason next
                | .exited code exitedState => .exited code exitedState
                | .outOfFuel => .outOfFuel
            | _ => .trapped .typeMismatch afterBase
        | .trapped reason next => .trapped reason next
        | .exited code exitedState => .exited code exitedState
        | .outOfFuel => .outOfFuel

  def execForValues : Nat → Program → State → VarId → List Value → Stmt →
      Outcome Completion
    | 0, _, _, _, _, _ => .outOfFuel
    | _ + 1, _, state, _, [], _ => .done .next state
    | fuel + 1, program, state, id, value :: values, body =>
        match execStmt fuel program (state.bindLocal id value) body with
        | .done .next completed
        | .done .continueLoop completed =>
            execForValues fuel program (restoreLocals state completed) id values body
        | .done .breakLoop completed => .done .next (restoreLocals state completed)
        | .done returned@(.returned _) completed =>
            .done returned (restoreLocals state completed)
        | .trapped reason completed =>
            .trapped reason (restoreLocals state completed)
        | .exited code exitedState =>
            .exited code (restoreLocals state exitedState)
        | .outOfFuel => .outOfFuel

  def execForRange : Nat → Program → State → VarId → Int → Option Int → Bool →
      Stmt → Outcome Completion
    | 0, _, _, _, _, _, _, _ => .outOfFuel
    | fuel + 1, program, state, id, current, stop, inclusive, body =>
        if rangeFinished current stop inclusive then
          .done .next state
        else
          match execStmt fuel program (state.bindLocal id (.signed .i32 current)) body with
          | .done .next completed
          | .done .continueLoop completed =>
              let unbound := restoreLocals state completed
              if inclusive && stop == some current then
                .done .next unbound
              else
                let next := wrapSigned program.target .i32 (current + 1)
                execForRange fuel program unbound id next stop inclusive body
          | .done .breakLoop completed => .done .next (restoreLocals state completed)
          | .done returned@(.returned _) completed =>
              .done returned (restoreLocals state completed)
          | .trapped reason completed =>
              .trapped reason (restoreLocals state completed)
          | .exited code exitedState =>
              .exited code (restoreLocals state exitedState)
          | .outOfFuel => .outOfFuel

  def execStmt : Nat → Program → State → Stmt → Outcome Completion
    | 0, _, _, _ => .outOfFuel
    | fuel + 1, program, state, statement =>
        match statement with
        | .skip => .done .next state
        | .expression expression =>
            match evalExpr fuel program state expression with
            | .done _ next => .done .next next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .sequence first second =>
            match execStmt fuel program state first with
            | .done .next next => execStmt fuel program next second
            | .done completion next => .done completion next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .letLocal id _ initializer body =>
            match evalExpr fuel program state initializer with
            | .done value next =>
                restoreOutcomeLocals next
                  (execStmt fuel program (next.bindLocal id value) body)
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .letUninitialized id _ body =>
            restoreOutcomeLocals state
              (execStmt fuel program (state.bindUninitialized id) body)
        | .ifThenElse condition thenBranch elseBranch =>
            match evalExpr fuel program state condition with
            | .done (.boolean true) next => execStmt fuel program next thenBranch
            | .done (.boolean false) next => execStmt fuel program next elseBranch
            | .done _ next => .trapped .typeMismatch next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .whileLoop condition body =>
            match evalExpr fuel program state condition with
            | .done (.boolean false) next => .done .next next
            | .done (.boolean true) next =>
                match execStmt fuel program next body with
                | .done .next completed
                | .done .continueLoop completed =>
                    execStmt fuel program completed (.whileLoop condition body)
                | .done .breakLoop completed => .done .next completed
                | .done returned@(.returned _) completed => .done returned completed
                | .trapped reason completed => .trapped reason completed
                | .exited code exitedState => .exited code exitedState
                | .outOfFuel => .outOfFuel
            | .done _ next => .trapped .typeMismatch next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .forValues id iterable body =>
            match evalExpr fuel program state iterable with
            | .done (.array values) next => execForValues fuel program next id values body
            | .done (.slice _ cell projections start length) next =>
                match sliceValues next cell projections start length with
                | .ok values => execForValues fuel program next id values body
                | .error reason => .trapped reason next
            | .done _ next => .trapped .typeMismatch next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .forRange id start stop inclusive body =>
            match evalExpr fuel program state start with
            | .done (.signed .i32 startValue) afterStart =>
                match stop with
                | none =>
                    execForRange fuel program afterStart id startValue none inclusive body
                | some stopExpression =>
                    match evalExpr fuel program afterStart stopExpression with
                    | .done (.signed .i32 stopValue) afterStop =>
                        execForRange fuel program afterStop id startValue
                          (some stopValue) inclusive body
                    | .done _ next => .trapped .typeMismatch next
                    | .trapped reason next => .trapped reason next
                    | .exited code exitedState => .exited code exitedState
                    | .outOfFuel => .outOfFuel
            | .done _ next => .trapped .typeMismatch next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .returnValue none => .done (.returned none) state
        | .returnValue (some expression) =>
            match evalExpr fuel program state expression with
            | .done value next => .done (.returned (some value)) next
            | .trapped reason next => .trapped reason next
            | .exited code exitedState => .exited code exitedState
            | .outOfFuel => .outOfFuel
        | .breakLoop => .done .breakLoop state
        | .continueLoop => .done .continueLoop state
end

def Evaluates
    (program : Program) (state : State) (expression : Expr)
    (value : Value) (finalState : State) : Prop :=
  ∃ fuel, evalExpr fuel program state expression = .done value finalState

def Traps
    (program : Program) (state : State) (expression : Expr)
    (reason : Trap) (finalState : State) : Prop :=
  ∃ fuel, evalExpr fuel program state expression = .trapped reason finalState

def Executes
    (program : Program) (state : State) (statement : Stmt)
    (completion : Completion) (finalState : State) : Prop :=
  ∃ fuel, execStmt fuel program state statement = .done completion finalState

end Lanius.Semantics
