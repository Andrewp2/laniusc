import Lanius.Basic

namespace Lanius.Core

inductive PointerWidth where
  | bits32
  | bits64
deriving DecidableEq, Repr

structure Target where
  pointerWidth : PointerWidth
deriving DecidableEq, Repr

def Target.x86_64 : Target := { pointerWidth := .bits64 }
def Target.wasm32 : Target := { pointerWidth := .bits32 }

inductive SignedIntTy where
  | i8
  | i16
  | i32
  | i64
  | isize
deriving DecidableEq, Repr

inductive UnsignedIntTy where
  | u8
  | u16
  | u32
  | u64
  | usize
deriving DecidableEq, Repr

def PointerWidth.bits : PointerWidth → Nat
  | .bits32 => 32
  | .bits64 => 64

def SignedIntTy.bits (target : Target) : SignedIntTy → Nat
  | .i8 => 8
  | .i16 => 16
  | .i32 => 32
  | .i64 => 64
  | .isize => target.pointerWidth.bits

def UnsignedIntTy.bits (target : Target) : UnsignedIntTy → Nat
  | .u8 => 8
  | .u16 => 16
  | .u32 => 32
  | .u64 => 64
  | .usize => target.pointerWidth.bits

/-- Resolved scalar types retain source-visible integer widths. The current
    GPU compiler's compact type codes are an implementation detail, not the
    definition of these types. -/
inductive ScalarTy where
  | bool
  | signed (type : SignedIntTy)
  | unsigned (type : UnsignedIntTy)
  | f32
  | f64
  | char
  | string
  | rawPtr
deriving DecidableEq, Repr

inductive Ty where
  | unit
  | scalar (type : ScalarTy)
  | array (element : Ty) (length : Nat)
  | slice (element : Ty)
  | reference (referent : Ty)
  | structure (id : TypeId)
  | enumeration (id : TypeId)
deriving DecidableEq, Repr

inductive ValueProjection where
  | field (field : FieldId)
  | index (index : Nat)
deriving DecidableEq, Repr

inductive Value where
  | unit
  | boolean (value : Bool)
  | signed (type : SignedIntTy) (value : Int)
  | unsigned (type : UnsignedIntTy) (value : Nat)
  | f32Bits (bits : UInt32)
  | f64Bits (bits : UInt64)
  /-- A literal starts as a Unicode scalar, but arithmetic can produce any
      32-bit code. The resolved value therefore uses its machine domain. -/
  | character (value : UInt32)
  | string (value : String)
  | pointer (address : Address)
  | array (elements : List Value)
  | slice (elementType : Ty) (cell : CellId) (projections : List ValueProjection)
      (start length : Nat)
  | structure (id : TypeId) (fields : List Value)
  | enumeration (id : TypeId) (variant : VariantId) (payload : List Value)
  | reference (referent : Ty) (cell : CellId) (projections : List ValueProjection)
deriving Repr

deriving instance BEq for Value

inductive UnaryOp where
  | positive
  | logicalNot
  | negate
deriving DecidableEq, Repr

inductive BinaryOp where
  | logicalAnd
  | logicalOr
  | equal
  | notEqual
  | less
  | lessEqual
  | greater
  | greaterEqual
  | add
  | subtract
  | multiply
  | divide
  | remainder
  | bitAnd
  | bitOr
  | bitXor
  | shiftLeft
  | shiftRight
deriving DecidableEq, Repr

inductive AssignOp where
  | set
  | add
  | subtract
  | multiply
  | divide
  | remainder
  | bitXor
  | shiftLeft
  | shiftRight
  | bitAnd
  | bitOr
deriving DecidableEq, Repr

/-- Canonical runtime services recognized by the current compiler. These are
    semantic identities, not the numeric builtin-table slots used by `laniusc`. -/
inductive HostService where
  | openReadPath | openWritePath | readI32
  | writeText | writeI32 | writeByte | writeNewline | closeFile
  | i32ToF32 | exit | secureU32
  | alloc | dealloc | argc | argLen | argRead | unixSeconds
  | currentDirRead | varCount | varKeyLen | varKeyRead | varLen | varRead
  | close | read | write | openRead | openWrite | openAppend
  | writeStdout | writeStderr | readStdin | fillSecureBytes
  | removeFile | createDir | removeDir | rename
  | monotonicRead | systemRead | sleepMsI32 | realloc | allocFailed
deriving DecidableEq, Repr

def HostService.parameterTypes : HostService → List Ty
  | .openReadPath | .openWritePath => [.scalar .string]
  | .readI32 => [.scalar (.signed .i32), .scalar (.signed .i32)]
  | .writeText => [.scalar (.signed .i32), .scalar .string]
  | .writeI32 | .writeByte =>
      [.scalar (.signed .i32), .scalar (.signed .i32)]
  | .writeNewline | .closeFile | .close => [.scalar (.signed .i32)]
  | .i32ToF32 | .exit | .argLen | .varKeyLen | .sleepMsI32 =>
      [.scalar (.signed .i32)]
  | .secureU32 | .argc | .unixSeconds | .varCount => []
  | .alloc => [.scalar (.unsigned .usize), .scalar (.unsigned .usize)]
  | .dealloc =>
      [.scalar .rawPtr, .scalar (.unsigned .usize), .scalar (.unsigned .usize)]
  | .argRead | .varKeyRead =>
      [.scalar (.signed .i32), .scalar .rawPtr, .scalar (.unsigned .usize)]
  | .currentDirRead | .fillSecureBytes | .writeStdout | .writeStderr | .readStdin =>
      [.scalar .rawPtr, .scalar (.unsigned .usize)]
  | .varLen => [.scalar .rawPtr, .scalar (.unsigned .usize)]
  | .varRead =>
      [.scalar .rawPtr, .scalar (.unsigned .usize), .scalar .rawPtr,
        .scalar (.unsigned .usize)]
  | .read | .write =>
      [.scalar (.signed .i32), .scalar .rawPtr, .scalar (.unsigned .usize)]
  | .openRead | .openWrite | .openAppend | .removeFile | .createDir | .removeDir =>
      [.scalar .rawPtr, .scalar (.unsigned .usize)]
  | .rename =>
      [.scalar .rawPtr, .scalar (.unsigned .usize), .scalar .rawPtr,
        .scalar (.unsigned .usize)]
  | .monotonicRead | .systemRead =>
      [.scalar .rawPtr, .scalar (.unsigned .usize)]
  | .realloc =>
      [.scalar .rawPtr, .scalar (.unsigned .usize), .scalar (.unsigned .usize),
        .scalar (.unsigned .usize)]
  | .allocFailed => [.scalar (.unsigned .usize), .scalar (.unsigned .usize)]

def HostService.returnType : HostService → Ty
  | .i32ToF32 => .scalar .f32
  | .secureU32 => .scalar (.unsigned .u32)
  | .alloc | .realloc => .scalar .rawPtr
  | .dealloc | .exit | .allocFailed => .unit
  | _ => .scalar (.signed .i32)

inductive ExternalBehavior where
  | host (service : HostService)
  | unavailable (capability : Capability)
  | panic
  | unreachable
  | opaque (id : ExternId)
deriving DecidableEq, Repr

/-- Intrinsics are compiler-defined language operations, distinct from host
    ABI services and from source functions. Their identities are semantic and
    therefore do not expose the numeric tags used by the GPU compiler. -/
inductive Intrinsic where
  | printI32
  | assert
deriving DecidableEq, Repr

mutual
  inductive Pattern where
    | wildcard
    | bind (id : VarId)
    | literal (value : Value)
    | enumVariant (type : TypeId) (variant : VariantId) (payload : List Pattern)

  inductive Expr where
    | value (value : Value)
    | local (id : VarId)
    | cast (target : ScalarTy) (operand : Expr)
    | unary (op : UnaryOp) (operand : Expr)
    | binary (op : BinaryOp) (left right : Expr)
    | array (elementType : Ty) (elements : List Expr)
    /-- Contextual array-to-slice conversion. Place-shaped expressions borrow
        their original cell; other arrays acquire stable temporary storage. -/
    | arrayToSlice (elementType : Ty) (array : Expr)
    | index (base index : Expr)
    | structValue (id : TypeId) (fields : List Expr)
    | field (base : Expr) (field : FieldId)
    | enumValue (id : TypeId) (variant : VariantId) (payload : List Expr)
    | matchValue (scrutinee : Expr) (arms : List (Pattern × Expr))
    | assign (op : AssignOp) (place : Place) (value : Expr)
    | borrow (referent : Ty) (place : Place)
    | dereference (reference : Expr)
    | constant (id : ConstantId)
    | call (function : FunctionId) (arguments : List Expr)
    | intrinsic (operation : Intrinsic) (argument : Expr)
    /-- Compiler intrinsic `i32_array_data_ptr`. Place-shaped expressions
        alias their existing cell; other array expressions acquire a stable
        temporary cell during evaluation. -/
    | i32ArrayDataPtr (array : Expr)
    | alloc (size alignment : Expr)
    | realloc (pointer oldSize newSize alignment : Expr)
    | dealloc (pointer size alignment : Expr)
    | loadByte (pointer offset : Expr)
    | storeByte (pointer offset value : Expr)

  inductive Place where
    | local (id : VarId)
    | field (base : Place) (field : FieldId)
    | index (base : Place) (index : Expr)
end

deriving instance BEq for Pattern, Expr, Place
deriving instance Repr for Pattern, Expr, Place

inductive Stmt where
  | skip
  | expression (expression : Expr)
  | sequence (first second : Stmt)
  | letLocal (id : VarId) (type : Ty) (initializer : Expr) (body : Stmt)
  | letUninitialized (id : VarId) (type : Ty) (body : Stmt)
  | ifThenElse (condition : Expr) (thenBranch elseBranch : Stmt)
  | whileLoop (condition : Expr) (body : Stmt)
  | forValues (id : VarId) (iterable : Expr) (body : Stmt)
  | forRange (id : VarId) (start : Expr) (stop : Option Expr)
      (inclusive : Bool) (body : Stmt)
  | returnValue (value : Option Expr)
  | breakLoop
  | continueLoop

deriving instance BEq for Stmt
deriving instance Repr for Stmt

structure StructDecl where
  id : TypeId
  fields : List Ty
deriving DecidableEq, Repr

structure EnumDecl where
  id : TypeId
  variants : List (List Ty)
deriving DecidableEq, Repr

structure Function where
  id : FunctionId
  parameters : List (VarId × Ty)
  returnType : Ty
  body : Option Stmt
  external : Option ExternalBehavior := none
deriving BEq, Repr

structure Constant where
  id : ConstantId
  type : Ty
  value : Value
deriving BEq, Repr

structure Program where
  target : Target := Target.x86_64
  structures : List StructDecl := []
  enumerations : List EnumDecl := []
  constants : List Constant := []
  functions : List Function := []
deriving BEq, Repr

def Program.function? (program : Program) (id : FunctionId) : Option Function :=
  program.functions.find? (fun function => function.id == id)

def Program.structure? (program : Program) (id : TypeId) : Option StructDecl :=
  program.structures.find? (fun declaration => declaration.id == id)

def Program.enumeration? (program : Program) (id : TypeId) : Option EnumDecl :=
  program.enumerations.find? (fun declaration => declaration.id == id)

def Program.constant? (program : Program) (id : ConstantId) : Option Constant :=
  program.constants.find? (fun declaration => declaration.id == id)

end Lanius.Core
