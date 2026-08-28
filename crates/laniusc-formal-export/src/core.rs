use serde::{Deserialize, Serialize};

use crate::artifact::CoreNodeId;

pub type TypeId = u32;
pub type FieldId = u32;
pub type VariantId = u32;
pub type VarId = u32;
pub type FunctionId = u32;
pub type ConstantId = u32;
pub type ExternId = u32;
pub type CellId = u32;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CorePointerWidth {
    Bits32,
    Bits64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CoreTarget {
    pub pointer_width: CorePointerWidth,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CoreSignedIntTy {
    I8,
    I16,
    I32,
    I64,
    Isize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CoreUnsignedIntTy {
    U8,
    U16,
    U32,
    U64,
    Usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CoreScalarTy {
    Bool,
    Signed { ty: CoreSignedIntTy },
    Unsigned { ty: CoreUnsignedIntTy },
    F32,
    F64,
    Char,
    String,
    RawPtr,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CoreTy {
    Unit,
    Scalar { ty: CoreScalarTy },
    Array { element: Box<CoreTy>, length: u64 },
    Slice { element: Box<CoreTy> },
    Reference { referent: Box<CoreTy> },
    Structure { id: TypeId },
    Enumeration { id: TypeId },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CoreValueProjection {
    Field { field: FieldId },
    Index { index: u64 },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CoreValue {
    Unit,
    Boolean {
        value: bool,
    },
    Signed {
        ty: CoreSignedIntTy,
        value: i64,
    },
    Unsigned {
        ty: CoreUnsignedIntTy,
        value: u64,
    },
    F32Bits {
        bits: u32,
    },
    F64Bits {
        bits: u64,
    },
    Character {
        value: u32,
    },
    String {
        value: String,
    },
    Pointer {
        address: u64,
    },
    Array {
        elements: Vec<CoreValue>,
    },
    Slice {
        element_type: CoreTy,
        cell: CellId,
        projections: Vec<CoreValueProjection>,
        start: u64,
        length: u64,
    },
    Structure {
        id: TypeId,
        fields: Vec<CoreValue>,
    },
    Enumeration {
        id: TypeId,
        variant: VariantId,
        payload: Vec<CoreValue>,
    },
    Reference {
        referent: CoreTy,
        cell: CellId,
        projections: Vec<CoreValueProjection>,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CoreUnaryOp {
    Positive,
    LogicalNot,
    Negate,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CoreBinaryOp {
    LogicalAnd,
    LogicalOr,
    Equal,
    NotEqual,
    Less,
    LessEqual,
    Greater,
    GreaterEqual,
    Add,
    Subtract,
    Multiply,
    Divide,
    Remainder,
    BitAnd,
    BitOr,
    BitXor,
    ShiftLeft,
    ShiftRight,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CoreAssignOp {
    Set,
    Add,
    Subtract,
    Multiply,
    Divide,
    Remainder,
    BitXor,
    ShiftLeft,
    ShiftRight,
    BitAnd,
    BitOr,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CoreHostService {
    OpenReadPath,
    OpenWritePath,
    ReadI32,
    WriteText,
    WriteI32,
    WriteByte,
    WriteNewline,
    CloseFile,
    I32ToF32,
    Exit,
    SecureU32,
    Alloc,
    Dealloc,
    Argc,
    ArgLen,
    ArgRead,
    UnixSeconds,
    CurrentDirRead,
    VarCount,
    VarKeyLen,
    VarKeyRead,
    VarLen,
    VarRead,
    Close,
    Read,
    Write,
    OpenRead,
    OpenWrite,
    OpenAppend,
    WriteStdout,
    WriteStderr,
    ReadStdin,
    FillSecureBytes,
    RemoveFile,
    CreateDir,
    RemoveDir,
    Rename,
    MonotonicRead,
    SystemRead,
    SleepMsI32,
    Realloc,
    AllocFailed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CoreCapability {
    Clock,
    Network,
    Thread,
    Gpu,
    TestHarness,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CoreExternalBehavior {
    Host { service: CoreHostService },
    Unavailable { capability: CoreCapability },
    Panic,
    Unreachable,
    Opaque { id: ExternId },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CoreIntrinsic {
    PrintI32,
    Assert,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CorePattern {
    pub id: CoreNodeId,
    pub value: CorePatternValue,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CorePatternValue {
    Wildcard,
    Bind {
        id: VarId,
    },
    Literal {
        value: CoreValue,
    },
    EnumVariant {
        type_id: TypeId,
        variant: VariantId,
        payload: Vec<CorePattern>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CoreExpr {
    pub id: CoreNodeId,
    pub value: CoreExprValue,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CoreExprValue {
    Value {
        value: CoreValue,
    },
    Local {
        id: VarId,
    },
    Cast {
        target: CoreScalarTy,
        operand: Box<CoreExpr>,
    },
    Unary {
        op: CoreUnaryOp,
        operand: Box<CoreExpr>,
    },
    Binary {
        op: CoreBinaryOp,
        left: Box<CoreExpr>,
        right: Box<CoreExpr>,
    },
    Array {
        element_type: CoreTy,
        elements: Vec<CoreExpr>,
    },
    ArrayToSlice {
        element_type: CoreTy,
        array: Box<CoreExpr>,
    },
    Index {
        base: Box<CoreExpr>,
        index: Box<CoreExpr>,
    },
    StructValue {
        id: TypeId,
        fields: Vec<CoreExpr>,
    },
    Field {
        base: Box<CoreExpr>,
        field: FieldId,
    },
    EnumValue {
        id: TypeId,
        variant: VariantId,
        payload: Vec<CoreExpr>,
    },
    MatchValue {
        scrutinee: Box<CoreExpr>,
        arms: Vec<(CorePattern, CoreExpr)>,
    },
    Assign {
        op: CoreAssignOp,
        place: CorePlace,
        value: Box<CoreExpr>,
    },
    Borrow {
        referent: CoreTy,
        place: CorePlace,
    },
    Dereference {
        reference: Box<CoreExpr>,
    },
    Constant {
        id: ConstantId,
    },
    Call {
        function: FunctionId,
        arguments: Vec<CoreExpr>,
    },
    Intrinsic {
        operation: CoreIntrinsic,
        argument: Box<CoreExpr>,
    },
    I32ArrayDataPtr {
        array: Box<CoreExpr>,
    },
    Alloc {
        size: Box<CoreExpr>,
        alignment: Box<CoreExpr>,
    },
    Realloc {
        pointer: Box<CoreExpr>,
        old_size: Box<CoreExpr>,
        new_size: Box<CoreExpr>,
        alignment: Box<CoreExpr>,
    },
    Dealloc {
        pointer: Box<CoreExpr>,
        size: Box<CoreExpr>,
        alignment: Box<CoreExpr>,
    },
    LoadByte {
        pointer: Box<CoreExpr>,
        offset: Box<CoreExpr>,
    },
    StoreByte {
        pointer: Box<CoreExpr>,
        offset: Box<CoreExpr>,
        value: Box<CoreExpr>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CorePlace {
    pub id: CoreNodeId,
    pub value: CorePlaceValue,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CorePlaceValue {
    Local {
        id: VarId,
    },
    Field {
        base: Box<CorePlace>,
        field: FieldId,
    },
    Index {
        base: Box<CorePlace>,
        index: Box<CoreExpr>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CoreStmt {
    pub id: CoreNodeId,
    pub value: CoreStmtValue,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CoreStmtValue {
    Skip,
    Expression {
        expression: CoreExpr,
    },
    Sequence {
        first: Box<CoreStmt>,
        second: Box<CoreStmt>,
    },
    LetLocal {
        id: VarId,
        ty: CoreTy,
        initializer: CoreExpr,
        body: Box<CoreStmt>,
    },
    LetUninitialized {
        id: VarId,
        ty: CoreTy,
        body: Box<CoreStmt>,
    },
    IfThenElse {
        condition: CoreExpr,
        then_branch: Box<CoreStmt>,
        else_branch: Box<CoreStmt>,
    },
    WhileLoop {
        condition: CoreExpr,
        body: Box<CoreStmt>,
    },
    ForValues {
        id: VarId,
        iterable: CoreExpr,
        body: Box<CoreStmt>,
    },
    ForRange {
        id: VarId,
        start: CoreExpr,
        stop: Option<CoreExpr>,
        inclusive: bool,
        body: Box<CoreStmt>,
    },
    ReturnValue {
        value: Option<CoreExpr>,
    },
    BreakLoop,
    ContinueLoop,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CoreStructDecl {
    pub id: TypeId,
    pub fields: Vec<CoreTy>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CoreEnumDecl {
    pub id: TypeId,
    pub variants: Vec<Vec<CoreTy>>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CoreFunction {
    pub id: FunctionId,
    pub parameters: Vec<(VarId, CoreTy)>,
    pub return_type: CoreTy,
    pub body: Option<CoreStmt>,
    pub external: Option<CoreExternalBehavior>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CoreConstant {
    pub id: ConstantId,
    pub ty: CoreTy,
    pub value: CoreValue,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CoreProgram {
    pub target: CoreTarget,
    pub structures: Vec<CoreStructDecl>,
    pub enumerations: Vec<CoreEnumDecl>,
    pub constants: Vec<CoreConstant>,
    pub functions: Vec<CoreFunction>,
}
