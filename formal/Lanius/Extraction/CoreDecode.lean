import Lanius.Core
import Lanius.Extraction.Artifact

namespace Lanius.Extraction

namespace CoreDecode

def pointerWidth : CorePointerWidth → Core.PointerWidth
  | .bits32 => .bits32
  | .bits64 => .bits64

def target (wire : CoreTarget) : Core.Target := {
  pointerWidth := pointerWidth wire.pointer_width
}

def signedIntTy : CoreSignedIntTy → Core.SignedIntTy
  | .i8 => .i8
  | .i16 => .i16
  | .i32 => .i32
  | .i64 => .i64
  | .isize => .isize

def unsignedIntTy : CoreUnsignedIntTy → Core.UnsignedIntTy
  | .u8 => .u8
  | .u16 => .u16
  | .u32 => .u32
  | .u64 => .u64
  | .usize => .usize

def scalarTy : CoreScalarTy → Core.ScalarTy
  | .bool => .bool
  | .signed ty => .signed (signedIntTy ty)
  | .unsigned ty => .unsigned (unsignedIntTy ty)
  | .f32 => .f32
  | .f64 => .f64
  | .char => .char
  | .string => .string
  | .raw_ptr => .rawPtr

def ty : CoreTy → Core.Ty
  | .unit => .unit
  | .scalar scalar => .scalar (scalarTy scalar)
  | .array element length => .array (ty element) length
  | .slice element => .slice (ty element)
  | .reference referent => .reference (ty referent)
  | .structure id => .structure id
  | .enumeration id => .enumeration id

def valueProjection : CoreValueProjection → Core.ValueProjection
  | .field field => .field field
  | .index index => .index index

mutual
  def value : CoreValue → Core.Value
    | .unit => .unit
    | .boolean boolean => .boolean boolean
    | .signed integerTy integer => .signed (signedIntTy integerTy) integer
    | .unsigned integerTy integer => .unsigned (unsignedIntTy integerTy) integer
    | .f32_bits bits => .f32Bits (UInt32.ofNat bits)
    | .f64_bits bits => .f64Bits (UInt64.ofNat bits)
    | .character character => .character (UInt32.ofNat character)
    | .string string => .string string
    | .pointer address => .pointer address
    | .array elements => .array (values elements)
    | .slice elementType cell projections start length =>
        .slice (ty elementType) cell (projections.map valueProjection) start length
    | .structure id fields => .structure id (values fields)
    | .enumeration id variant payload => .enumeration id variant (values payload)
    | .reference referent cell projections =>
        .reference (ty referent) cell (projections.map valueProjection)

  def values : List CoreValue → List Core.Value
    | [] => []
    | head :: tail => value head :: values tail
end

def unaryOp : CoreUnaryOp → Core.UnaryOp
  | .positive => .positive
  | .logical_not => .logicalNot
  | .negate => .negate

def binaryOp : CoreBinaryOp → Core.BinaryOp
  | .logical_and => .logicalAnd
  | .logical_or => .logicalOr
  | .equal => .equal
  | .not_equal => .notEqual
  | .less => .less
  | .less_equal => .lessEqual
  | .greater => .greater
  | .greater_equal => .greaterEqual
  | .add => .add
  | .subtract => .subtract
  | .multiply => .multiply
  | .divide => .divide
  | .remainder => .remainder
  | .bit_and => .bitAnd
  | .bit_or => .bitOr
  | .bit_xor => .bitXor
  | .shift_left => .shiftLeft
  | .shift_right => .shiftRight

def assignOp : CoreAssignOp → Core.AssignOp
  | .set => .set
  | .add => .add
  | .subtract => .subtract
  | .multiply => .multiply
  | .divide => .divide
  | .remainder => .remainder
  | .bit_xor => .bitXor
  | .shift_left => .shiftLeft
  | .shift_right => .shiftRight
  | .bit_and => .bitAnd
  | .bit_or => .bitOr

def hostService : CoreHostService → Core.HostService
  | .open_read_path => .openReadPath
  | .open_write_path => .openWritePath
  | .read_i32 => .readI32
  | .write_text => .writeText
  | .write_i32 => .writeI32
  | .write_byte => .writeByte
  | .write_newline => .writeNewline
  | .close_file => .closeFile
  | .i32_to_f32 => .i32ToF32
  | .exit => .exit
  | .secure_u32 => .secureU32
  | .alloc => .alloc
  | .dealloc => .dealloc
  | .argc => .argc
  | .arg_len => .argLen
  | .arg_read => .argRead
  | .unix_seconds => .unixSeconds
  | .current_dir_read => .currentDirRead
  | .var_count => .varCount
  | .var_key_len => .varKeyLen
  | .var_key_read => .varKeyRead
  | .var_len => .varLen
  | .var_read => .varRead
  | .close => .close
  | .read => .read
  | .write => .write
  | .open_read => .openRead
  | .open_write => .openWrite
  | .open_append => .openAppend
  | .write_stdout => .writeStdout
  | .write_stderr => .writeStderr
  | .read_stdin => .readStdin
  | .fill_secure_bytes => .fillSecureBytes
  | .remove_file => .removeFile
  | .create_dir => .createDir
  | .remove_dir => .removeDir
  | .rename => .rename
  | .monotonic_read => .monotonicRead
  | .system_read => .systemRead
  | .sleep_ms_i32 => .sleepMsI32
  | .realloc => .realloc
  | .alloc_failed => .allocFailed

def capability : CoreCapability → Lanius.Capability
  | .clock => .clock
  | .network => .network
  | .thread => .thread
  | .gpu => .gpu
  | .test_harness => .testHarness

def externalBehavior : CoreExternalBehavior → Core.ExternalBehavior
  | .host service => .host (hostService service)
  | .unavailable unavailableCapability =>
      .unavailable (capability unavailableCapability)
  | .panic => .panic
  | .unreachable => .unreachable
  | .opaque id => .opaque id

def intrinsic : CoreIntrinsic → Core.Intrinsic
  | .print_i32 => .printI32
  | .assert => .assert

mutual
  def pattern : CorePattern → Core.Pattern
    | ⟨_, .wildcard⟩ => .wildcard
    | ⟨_, .bind id⟩ => .bind id
    | ⟨_, .literal literal⟩ => .literal (value literal)
    | ⟨_, .enum_variant typeId variant payload⟩ =>
        .enumVariant typeId variant (patterns payload)

  def patterns : List CorePattern → List Core.Pattern
    | [] => []
    | head :: tail => pattern head :: patterns tail

  def expression : CoreExpr → Core.Expr
    | ⟨_, .value literal⟩ => .value (value literal)
    | ⟨_, .local id⟩ => .local id
    | ⟨_, .cast target operand⟩ => .cast (scalarTy target) (expression operand)
    | ⟨_, .unary operation operand⟩ => .unary (unaryOp operation) (expression operand)
    | ⟨_, .binary operation left right⟩ =>
        .binary (binaryOp operation) (expression left) (expression right)
    | ⟨_, .array elementType elements⟩ => .array (ty elementType) (expressions elements)
    | ⟨_, .array_to_slice elementType array⟩ =>
        .arrayToSlice (ty elementType) (expression array)
    | ⟨_, .index base index⟩ => .index (expression base) (expression index)
    | ⟨_, .struct_value id fields⟩ => .structValue id (expressions fields)
    | ⟨_, .field base field⟩ => .field (expression base) field
    | ⟨_, .enum_value id variant payload⟩ =>
        .enumValue id variant (expressions payload)
    | ⟨_, .match_value scrutinee arms⟩ =>
        .matchValue (expression scrutinee) (matchArms arms)
    | ⟨_, .assign operation destination assignedValue⟩ =>
        .assign (assignOp operation) (place destination) (expression assignedValue)
    | ⟨_, .borrow referent borrowed⟩ => .borrow (ty referent) (place borrowed)
    | ⟨_, .dereference reference⟩ => .dereference (expression reference)
    | ⟨_, .constant id⟩ => .constant id
    | ⟨_, .call function arguments⟩ => .call function (expressions arguments)
    | ⟨_, .intrinsic operation argument⟩ =>
        .intrinsic (intrinsic operation) (expression argument)
    | ⟨_, .i32_array_data_ptr array⟩ => .i32ArrayDataPtr (expression array)
    | ⟨_, .alloc size alignment⟩ => .alloc (expression size) (expression alignment)
    | ⟨_, .realloc pointer oldSize newSize alignment⟩ =>
        .realloc (expression pointer) (expression oldSize)
          (expression newSize) (expression alignment)
    | ⟨_, .dealloc pointer size alignment⟩ =>
        .dealloc (expression pointer) (expression size) (expression alignment)
    | ⟨_, .load_byte pointer offset⟩ => .loadByte (expression pointer) (expression offset)
    | ⟨_, .store_byte pointer offset storedValue⟩ =>
        .storeByte (expression pointer) (expression offset) (expression storedValue)

  def expressions : List CoreExpr → List Core.Expr
    | [] => []
    | head :: tail => expression head :: expressions tail

  def matchArms : List (CorePattern × CoreExpr) → List (Core.Pattern × Core.Expr)
    | [] => []
    | (armPattern, armExpression) :: tail =>
        (pattern armPattern, expression armExpression) :: matchArms tail

  def place : CorePlace → Core.Place
    | ⟨_, .local id⟩ => .local id
    | ⟨_, .field base field⟩ => .field (place base) field
    | ⟨_, .index base index⟩ => .index (place base) (expression index)
end

mutual
  def statement : CoreStmt → Core.Stmt
    | ⟨_, .skip⟩ => .skip
    | ⟨_, .expression expressionValue⟩ => .expression (expression expressionValue)
    | ⟨_, .sequence first second⟩ => .sequence (statement first) (statement second)
    | ⟨_, .let_local id localTy initializer body⟩ =>
        .letLocal id (ty localTy) (expression initializer) (statement body)
    | ⟨_, .let_uninitialized id localTy body⟩ =>
        .letUninitialized id (ty localTy) (statement body)
    | ⟨_, .if_then_else condition thenBranch elseBranch⟩ =>
        .ifThenElse (expression condition) (statement thenBranch) (statement elseBranch)
    | ⟨_, .while_loop condition body⟩ =>
        .whileLoop (expression condition) (statement body)
    | ⟨_, .for_values id iterable body⟩ =>
        .forValues id (expression iterable) (statement body)
    | ⟨_, .for_range id start stop inclusive body⟩ =>
        .forRange id (expression start) (stop.map expression) inclusive (statement body)
    | ⟨_, .return_value returnValue⟩ => .returnValue (returnValue.map expression)
    | ⟨_, .break_loop⟩ => .breakLoop
    | ⟨_, .continue_loop⟩ => .continueLoop
end

def structDecl (declaration : CoreStructDecl) : Core.StructDecl := {
  id := declaration.id
  fields := declaration.fields.map ty
}

def enumDecl (declaration : CoreEnumDecl) : Core.EnumDecl := {
  id := declaration.id
  variants := declaration.variants.map (List.map ty)
}

def function (wire : CoreFunction) : Core.Function := {
  id := wire.id
  parameters := wire.parameters.map fun parameter => (parameter.1, ty parameter.2)
  returnType := ty wire.return_type
  body := wire.body.map statement
  external := wire.external.map externalBehavior
}

def constant (wire : CoreConstant) : Core.Constant := {
  id := wire.id
  type := ty wire.ty
  value := value wire.value
}

def program (wire : CoreProgram) : Core.Program := {
  target := target wire.target
  structures := wire.structures.map structDecl
  enumerations := wire.enumerations.map enumDecl
  constants := wire.constants.map constant
  functions := wire.functions.map function
}

end CoreDecode

end Lanius.Extraction
