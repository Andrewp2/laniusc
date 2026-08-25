import Lanius.Core

namespace Lanius.Typing

open Lanius
open Lanius.Core

abbrev Context := VarId → Option Ty

def Context.empty : Context := fun _ => none

def Context.bind (context : Context) (id : VarId) (type : Ty) : Context :=
  fun candidate => if candidate == id then some type else context candidate

def Context.bindAll (context : Context) (bindings : List (VarId × Ty)) : Context :=
  bindings.foldl (fun result binding => result.bind binding.1 binding.2) context

def parameterContext (parameters : List (VarId × Ty)) : Context :=
  parameters.foldl (fun context parameter => context.bind parameter.1 parameter.2) Context.empty

mutual
  /-- Core literals are source-constructible values. References and slices
      carry runtime cell identities and therefore may only be produced by
      evaluation, never embedded directly in a typed syntax tree. -/
  def Value.isLiteral : Value → Bool
    | .array values => Values.areLiteral values
    | .structure _ fields => Values.areLiteral fields
    | .enumeration _ _ payload => Values.areLiteral payload
    | .slice _ _ _ _ _ | .reference _ _ _ => false
    | _ => true

  def Values.areLiteral : List Value → Bool
    | [] => true
    | value :: values => Value.isLiteral value && Values.areLiteral values
end

def signedMin (target : Target) (type : SignedIntTy) : Int :=
  -(2 ^ (type.bits target - 1))

def signedMax (target : Target) (type : SignedIntTy) : Int :=
  2 ^ (type.bits target - 1) - 1

def unsignedMax (target : Target) (type : UnsignedIntTy) : Nat :=
  2 ^ type.bits target - 1

mutual
  inductive ValueHasType (program : Program) : Value → Ty → Prop where
    | unit : ValueHasType program .unit .unit
    | boolean (value) : ValueHasType program (.boolean value) (.scalar .bool)
    | signed (type) (value)
        (lower : signedMin program.target type ≤ value)
        (upper : value ≤ signedMax program.target type) :
        ValueHasType program (.signed type value) (.scalar (.signed type))
    | unsigned (type) (value)
        (upper : value ≤ unsignedMax program.target type) :
        ValueHasType program (.unsigned type value) (.scalar (.unsigned type))
    | f32Bits (bits) : ValueHasType program (.f32Bits bits) (.scalar .f32)
    | f64Bits (bits) : ValueHasType program (.f64Bits bits) (.scalar .f64)
    | character (value) : ValueHasType program (.character value) (.scalar .char)
    | string (value) : ValueHasType program (.string value) (.scalar .string)
    | pointer (address) : ValueHasType program (.pointer address) (.scalar .rawPtr)
    | array (values) (elementType) (length : values.length = count)
        (elements : ValuesHaveTypes program values (List.replicate count elementType)) :
        ValueHasType program (.array values) (.array elementType count)
    | slice (elementType) (cell) (projections) (start) (length) :
        ValueHasType program (.slice elementType cell projections start length)
          (.slice elementType)
    | structure (declaration : StructDecl)
        (found : program.structure? declaration.id = some declaration)
        (fields : ValuesHaveTypes program values declaration.fields) :
        ValueHasType program (.structure declaration.id values) (.structure declaration.id)
    | enumeration (declaration : EnumDecl)
        (found : program.enumeration? declaration.id = some declaration)
        (variantFound : declaration.variants[variant]? = some payloadTypes)
        (payload : ValuesHaveTypes program values payloadTypes) :
        ValueHasType program
          (.enumeration declaration.id variant values) (.enumeration declaration.id)
    | reference (referent) (cell) (projections) :
        ValueHasType program (.reference referent cell projections) (.reference referent)

  inductive ValuesHaveTypes (program : Program) : List Value → List Ty → Prop where
    | nil : ValuesHaveTypes program [] []
    | cons (head : ValueHasType program value type)
        (tail : ValuesHaveTypes program values types) :
        ValuesHaveTypes program (value :: values) (type :: types)
end

mutual
  inductive PatternHasType (program : Program) : Pattern → Ty → List (VarId × Ty) → Prop where
    | wildcard : PatternHasType program .wildcard type []
    | bind (id : VarId) : PatternHasType program (.bind id) type [(id, type)]
    | literal (typed : ValueHasType program value type) :
        PatternHasType program (.literal value) type []
    | enumVariant (declaration : EnumDecl)
        (found : program.enumeration? typeId = some declaration)
        (variantFound : declaration.variants[variant]? = some payloadTypes)
        (payload : PatternsHaveTypes program patterns payloadTypes bindings) :
        PatternHasType program (.enumVariant typeId variant patterns)
          (.enumeration typeId) bindings

  inductive PatternsHaveTypes (program : Program) :
      List Pattern → List Ty → List (VarId × Ty) → Prop where
    | nil : PatternsHaveTypes program [] [] []
    | cons
        (head : PatternHasType program pattern type headBindings)
        (tail : PatternsHaveTypes program patterns types tailBindings) :
        PatternsHaveTypes program (pattern :: patterns) (type :: types)
          (headBindings ++ tailBindings)
end

inductive ArithmeticTy : Ty → Prop where
  | signed (type) : ArithmeticTy (.scalar (.signed type))
  | unsigned (type) : ArithmeticTy (.scalar (.unsigned type))
  | f32 : ArithmeticTy (.scalar .f32)
  | f64 : ArithmeticTy (.scalar .f64)
  | character : ArithmeticTy (.scalar .char)

inductive NegatableTy : Ty → Prop where
  | signed (type) : NegatableTy (.scalar (.signed type))
  | unsigned (type) : NegatableTy (.scalar (.unsigned type))
  | f32 : NegatableTy (.scalar .f32)
  | f64 : NegatableTy (.scalar .f64)
  | character : NegatableTy (.scalar .char)

inductive IntegerTy : Ty → Prop where
  | signed (type) : IntegerTy (.scalar (.signed type))
  | unsigned (type) : IntegerTy (.scalar (.unsigned type))
  | character : IntegerTy (.scalar .char)

inductive OrderedTy : Ty → Prop where
  | signed (type) : OrderedTy (.scalar (.signed type))
  | unsigned (type) : OrderedTy (.scalar (.unsigned type))
  | f32 : OrderedTy (.scalar .f32)
  | f64 : OrderedTy (.scalar .f64)
  | character : OrderedTy (.scalar .char)

inductive EqualityTy : Ty → Prop where
  | boolean : EqualityTy (.scalar .bool)
  | signed (type) : EqualityTy (.scalar (.signed type))
  | unsigned (type) : EqualityTy (.scalar (.unsigned type))
  | f32 : EqualityTy (.scalar .f32)
  | f64 : EqualityTy (.scalar .f64)
  | character : EqualityTy (.scalar .char)
  | pointer : EqualityTy (.scalar .rawPtr)

inductive PointerOffsetTy : Ty → Prop where
  | signed (type) : PointerOffsetTy (.scalar (.signed type))
  | unsigned (type) : PointerOffsetTy (.scalar (.unsigned type))
  | character : PointerOffsetTy (.scalar .char)

inductive UnaryOpHasType : UnaryOp → Ty → Ty → Prop where
  | positive (type : ArithmeticTy operandType) :
      UnaryOpHasType .positive operandType operandType
  | logicalNot : UnaryOpHasType .logicalNot (.scalar .bool) (.scalar .bool)
  | negate (type : NegatableTy operandType) :
      UnaryOpHasType .negate operandType operandType

/-- Once the operator and operand type are fixed, unary typing determines one
    result type. -/
theorem UnaryOpHasType.output_unique
    (left : UnaryOpHasType operation operand leftOutput)
    (right : UnaryOpHasType operation operand rightOutput) :
    leftOutput = rightOutput := by
  cases left <;> cases right <;> rfl

/-- Every currently supported unary operator preserves its operand type. -/
theorem UnaryOpHasType.input_eq_output
    (typed : UnaryOpHasType operation input output) : input = output := by
  cases typed <;> rfl

/-- Every implicit numeric conversion accepted by surface elaboration becomes
    an explicit core cast. This keeps dynamic arithmetic homogeneous and makes
    narrowing behavior visible to proofs. -/
inductive ScalarCast : ScalarTy → ScalarTy → Prop where
  | signedToSigned (source target) : ScalarCast (.signed source) (.signed target)
  | signedToUnsigned (source target) : ScalarCast (.signed source) (.unsigned target)
  | unsignedToSigned (source target) : ScalarCast (.unsigned source) (.signed target)
  | unsignedToUnsigned (source target) : ScalarCast (.unsigned source) (.unsigned target)
  | signedToF32 (source) : ScalarCast (.signed source) .f32
  | signedToF64 (source) : ScalarCast (.signed source) .f64
  | unsignedToF32 (source) : ScalarCast (.unsigned source) .f32
  | unsignedToF64 (source) : ScalarCast (.unsigned source) .f64
  | charToSigned (target) : ScalarCast .char (.signed target)
  | charToUnsigned (target) : ScalarCast .char (.unsigned target)
  | charToF32 : ScalarCast .char .f32
  | charToF64 : ScalarCast .char .f64
  | f32ToF64 : ScalarCast .f32 .f64
  | f64ToF32 : ScalarCast .f64 .f32

inductive IntegralScalar : ScalarTy → Prop where
  | signed (type) : IntegralScalar (.signed type)
  | unsigned (type) : IntegralScalar (.unsigned type)
  | character : IntegralScalar .char

/-- The right operand supersedes the ordinary left-domain rule only for a
    widening floating promotion. This makes float dominance symmetric without
    creating two possible domains for signed/unsigned integer mixtures. -/
inductive RightDominatesBinary : ScalarTy → ScalarTy → Prop where
  | integralToF32 (source : IntegralScalar type) : RightDominatesBinary type .f32
  | integralToF64 (source : IntegralScalar type) : RightDominatesBinary type .f64
  | f32ToF64 : RightDominatesBinary .f32 .f64

inductive BinaryOpHasType : BinaryOp → Ty → Ty → Ty → Prop where
  | logicalAnd : BinaryOpHasType .logicalAnd (.scalar .bool) (.scalar .bool) (.scalar .bool)
  | logicalOr : BinaryOpHasType .logicalOr (.scalar .bool) (.scalar .bool) (.scalar .bool)
  | equal (type : EqualityTy operandType) :
      BinaryOpHasType .equal operandType operandType (.scalar .bool)
  | notEqual (type : EqualityTy operandType) :
      BinaryOpHasType .notEqual operandType operandType (.scalar .bool)
  | less (type : OrderedTy operandType) :
      BinaryOpHasType .less operandType operandType (.scalar .bool)
  | lessEqual (type : OrderedTy operandType) :
      BinaryOpHasType .lessEqual operandType operandType (.scalar .bool)
  | greater (type : OrderedTy operandType) :
      BinaryOpHasType .greater operandType operandType (.scalar .bool)
  | greaterEqual (type : OrderedTy operandType) :
      BinaryOpHasType .greaterEqual operandType operandType (.scalar .bool)
  | add (type : ArithmeticTy operandType) :
      BinaryOpHasType .add operandType operandType operandType
  | pointerAdd (offset : PointerOffsetTy offsetType) :
      BinaryOpHasType .add (.scalar .rawPtr) offsetType (.scalar .rawPtr)
  | subtract (type : ArithmeticTy operandType) :
      BinaryOpHasType .subtract operandType operandType operandType
  | pointerSubtract (offset : PointerOffsetTy offsetType) :
      BinaryOpHasType .subtract (.scalar .rawPtr) offsetType (.scalar .rawPtr)
  | multiply (type : ArithmeticTy operandType) :
      BinaryOpHasType .multiply operandType operandType operandType
  | divide (type : ArithmeticTy operandType) :
      BinaryOpHasType .divide operandType operandType operandType
  | remainder (type : IntegerTy operandType) :
      BinaryOpHasType .remainder operandType operandType operandType
  | bitAnd (type : IntegerTy operandType) :
      BinaryOpHasType .bitAnd operandType operandType operandType
  | bitOr (type : IntegerTy operandType) :
      BinaryOpHasType .bitOr operandType operandType operandType
  | bitXor (type : IntegerTy operandType) :
      BinaryOpHasType .bitXor operandType operandType operandType
  | shiftLeft (type : IntegerTy operandType) :
      BinaryOpHasType .shiftLeft operandType operandType operandType
  | shiftRight (type : IntegerTy operandType) :
      BinaryOpHasType .shiftRight operandType operandType operandType

/-- Once the operator and both operand types are fixed, binary typing
    determines one result type. -/
theorem BinaryOpHasType.output_unique
    (left : BinaryOpHasType operation leftType rightType leftOutput)
    (right : BinaryOpHasType operation leftType rightType rightOutput) :
    leftOutput = rightOutput := by
  cases left <;> cases right <;> rfl

inductive AssignOpHasType : AssignOp → Ty → Prop where
  | set : AssignOpHasType .set type
  | add (type : ArithmeticTy operandType) : AssignOpHasType .add operandType
  | subtract (type : ArithmeticTy operandType) : AssignOpHasType .subtract operandType
  | multiply (type : ArithmeticTy operandType) : AssignOpHasType .multiply operandType
  | divide (type : ArithmeticTy operandType) : AssignOpHasType .divide operandType
  | remainder (type : IntegerTy operandType) : AssignOpHasType .remainder operandType
  | bitXor (type : IntegerTy operandType) : AssignOpHasType .bitXor operandType
  | shiftLeft (type : IntegerTy operandType) : AssignOpHasType .shiftLeft operandType
  | shiftRight (type : IntegerTy operandType) : AssignOpHasType .shiftRight operandType
  | bitAnd (type : IntegerTy operandType) : AssignOpHasType .bitAnd operandType
  | bitOr (type : IntegerTy operandType) : AssignOpHasType .bitOr operandType

mutual
  inductive ExprHasType (program : Program) : Context → Expr → Ty → Prop where
    | value (typed : ValueHasType program value type)
        (literal : Value.isLiteral value = true := by decide) :
        ExprHasType program context (.value value) type
    | local (found : context localId = some type) :
        ExprHasType program context (.local localId) type
    | cast (operand : ExprHasType program context expression (.scalar sourceType))
        (conversion : ScalarCast sourceType targetType) :
        ExprHasType program context (.cast targetType expression) (.scalar targetType)
    | unary (operand : ExprHasType program context expression inputType)
        (operation : UnaryOpHasType op inputType outputType) :
        ExprHasType program context (.unary op expression) outputType
    | binary (left : ExprHasType program context leftExpr leftType)
        (right : ExprHasType program context rightExpr rightType)
        (operation : BinaryOpHasType op leftType rightType outputType) :
        ExprHasType program context (.binary op leftExpr rightExpr) outputType
    | array (elements : ExprsHaveTypes program context expressions
        (List.replicate expressions.length elementType)) :
        ExprHasType program context (.array elementType expressions)
          (.array elementType expressions.length)
    | arrayToSlice
        (array : ExprHasType program context arrayExpression (.array elementType length)) :
        ExprHasType program context (.arrayToSlice elementType arrayExpression) (.slice elementType)
    | indexArray (base : ExprHasType program context baseExpr (.array elementType length))
        (index : ExprHasType program context indexExpr indexType)
        (integerIndex : IntegerTy indexType) :
        ExprHasType program context (.index baseExpr indexExpr) elementType
    | indexSlice (base : ExprHasType program context baseExpr (.slice elementType))
        (index : ExprHasType program context indexExpr indexType)
        (integerIndex : IntegerTy indexType) :
        ExprHasType program context (.index baseExpr indexExpr) elementType
    | structValue (declaration : StructDecl)
        (found : program.structure? typeId = some declaration)
        (fields : ExprsHaveTypes program context expressions declaration.fields) :
        ExprHasType program context (.structValue typeId expressions) (.structure typeId)
    | field (base : ExprHasType program context baseExpr (.structure typeId))
        (declaration : StructDecl) (found : program.structure? typeId = some declaration)
        (fieldFound : declaration.fields[field]? = some type) :
        ExprHasType program context (.field baseExpr field) type
    | enumValue (declaration : EnumDecl)
        (found : program.enumeration? typeId = some declaration)
        (variantFound : declaration.variants[variant]? = some payloadTypes)
        (payload : ExprsHaveTypes program context expressions payloadTypes) :
        ExprHasType program context
          (.enumValue typeId variant expressions) (.enumeration typeId)
    | matchValue (scrutinee : ExprHasType program context scrutineeExpr scrutineeType)
        (typedArms : MatchArmsHaveType program context armList scrutineeType resultType) :
        ExprHasType program context (.matchValue scrutineeExpr armList) resultType
    | assign (target : PlaceHasType program context place type)
        (value : ExprHasType program context valueExpr type)
        (operation : AssignOpHasType op type) :
        ExprHasType program context (.assign op place valueExpr) .unit
    | borrow (target : PlaceHasType program context place referent) :
        ExprHasType program context (.borrow referent place) (.reference referent)
    | dereference
        (reference : ExprHasType program context referenceExpr (.reference referent)) :
        ExprHasType program context (.dereference referenceExpr) referent
    | constant (declaration : Constant)
        (found : program.constant? constantId = some declaration) :
        ExprHasType program context (.constant constantId) declaration.type
    | call (function : Function)
        (found : program.function? functionId = some function)
        (arguments : ExprsHaveTypes program context expressions (function.parameters.map Prod.snd)) :
        ExprHasType program context (.call functionId expressions) function.returnType
    | printI32
        (argument : ExprHasType program context expression (.scalar (.signed .i32))) :
        ExprHasType program context (.intrinsic .printI32 expression) .unit
    | assert
        (argument : ExprHasType program context expression (.scalar .bool)) :
        ExprHasType program context (.intrinsic .assert expression) .unit
    | i32ArrayDataPtr
        (array : ExprHasType program context expression
          (.array (.scalar (.signed .i32)) length)) :
        ExprHasType program context (.i32ArrayDataPtr expression) (.scalar .rawPtr)
    | alloc
        (size : ExprHasType program context sizeExpr (.scalar (.unsigned .usize)))
        (alignment : ExprHasType program context alignmentExpr (.scalar (.unsigned .usize))) :
        ExprHasType program context (.alloc sizeExpr alignmentExpr) (.scalar .rawPtr)
    | realloc
        (pointer : ExprHasType program context pointerExpr (.scalar .rawPtr))
        (oldSize : ExprHasType program context oldSizeExpr (.scalar (.unsigned .usize)))
        (newSize : ExprHasType program context newSizeExpr (.scalar (.unsigned .usize)))
        (alignment : ExprHasType program context alignmentExpr (.scalar (.unsigned .usize))) :
        ExprHasType program context
          (.realloc pointerExpr oldSizeExpr newSizeExpr alignmentExpr) (.scalar .rawPtr)
    | dealloc
        (pointer : ExprHasType program context pointerExpr (.scalar .rawPtr))
        (size : ExprHasType program context sizeExpr (.scalar (.unsigned .usize)))
        (alignment : ExprHasType program context alignmentExpr (.scalar (.unsigned .usize))) :
        ExprHasType program context (.dealloc pointerExpr sizeExpr alignmentExpr) .unit
    | loadByte
        (pointer : ExprHasType program context pointerExpr (.scalar .rawPtr))
        (offset : ExprHasType program context offsetExpr (.scalar (.unsigned .usize))) :
        ExprHasType program context (.loadByte pointerExpr offsetExpr)
          (.scalar (.unsigned .u8))
    | storeByte
        (pointer : ExprHasType program context pointerExpr (.scalar .rawPtr))
        (offset : ExprHasType program context offsetExpr (.scalar (.unsigned .usize)))
        (value : ExprHasType program context valueExpr (.scalar (.unsigned .u8))) :
        ExprHasType program context (.storeByte pointerExpr offsetExpr valueExpr) .unit

  inductive PlaceHasType (program : Program) : Context → Place → Ty → Prop where
    | local (found : context localId = some type) :
        PlaceHasType program context (.local localId) type
    | field (base : PlaceHasType program context basePlace (.structure typeId))
        (declaration : StructDecl) (found : program.structure? typeId = some declaration)
        (fieldFound : declaration.fields[field]? = some type) :
        PlaceHasType program context (.field basePlace field) type
    | indexArray (base : PlaceHasType program context basePlace (.array elementType length))
        (index : ExprHasType program context indexExpr indexType)
        (integerIndex : IntegerTy indexType) :
        PlaceHasType program context (.index basePlace indexExpr) elementType
    | indexSlice (base : PlaceHasType program context basePlace (.slice elementType))
        (index : ExprHasType program context indexExpr indexType)
        (integerIndex : IntegerTy indexType) :
        PlaceHasType program context (.index basePlace indexExpr) elementType

  inductive ExprsHaveTypes (program : Program) : Context → List Expr → List Ty → Prop where
    | nil : ExprsHaveTypes program context [] []
    | cons (head : ExprHasType program context expression type)
        (tail : ExprsHaveTypes program context expressions types) :
        ExprsHaveTypes program context (expression :: expressions) (type :: types)

  inductive MatchArmsHaveType (program : Program) :
      Context → List (Pattern × Expr) → Ty → Ty → Prop where
    | one
        (pattern : PatternHasType program armPattern scrutineeType bindings)
        (body : ExprHasType program (context.bindAll bindings) armBody resultType) :
        MatchArmsHaveType program context [(armPattern, armBody)] scrutineeType resultType
    | cons
        (pattern : PatternHasType program armPattern scrutineeType bindings)
        (body : ExprHasType program (context.bindAll bindings) armBody resultType)
        (tail : MatchArmsHaveType program context arms scrutineeType resultType) :
        MatchArmsHaveType program context
          ((armPattern, armBody) :: arms) scrutineeType resultType
end

inductive OptionExprHasType (program : Program) (context : Context) (type : Ty) :
    Option Expr → Prop where
  | none : OptionExprHasType program context type none
  | some (typed : ExprHasType program context expression type) :
      OptionExprHasType program context type (some expression)

inductive StmtHasType
    (program : Program) (returnType : Ty) : Context → Bool → Stmt → Prop where
  | skip : StmtHasType program returnType context inLoop .skip
  | expression (typed : ExprHasType program context expression type) :
      StmtHasType program returnType context inLoop (.expression expression)
  | sequence
      (first : StmtHasType program returnType context inLoop firstStmt)
      (second : StmtHasType program returnType context inLoop secondStmt) :
      StmtHasType program returnType context inLoop (.sequence firstStmt secondStmt)
  | letLocal
      (initializer : ExprHasType program context initializerExpr type)
      (body : StmtHasType program returnType (context.bind localId type) inLoop bodyStmt) :
      StmtHasType program returnType context inLoop
        (.letLocal localId type initializerExpr bodyStmt)
  | letUninitialized
      (body : StmtHasType program returnType (context.bind localId type) inLoop bodyStmt) :
      StmtHasType program returnType context inLoop
        (.letUninitialized localId type bodyStmt)
  | ifThenElse
      (condition : ExprHasType program context conditionExpr (.scalar .bool))
      (thenBranch : StmtHasType program returnType context inLoop thenStmt)
      (elseBranch : StmtHasType program returnType context inLoop elseStmt) :
      StmtHasType program returnType context inLoop
        (.ifThenElse conditionExpr thenStmt elseStmt)
  | whileLoop
      (condition : ExprHasType program context conditionExpr (.scalar .bool))
      (body : StmtHasType program returnType context true bodyStmt) :
      StmtHasType program returnType context inLoop (.whileLoop conditionExpr bodyStmt)
  | forArray
      (iterable : ExprHasType program context iterableExpr (.array elementType length))
      (body : StmtHasType program returnType (context.bind localId elementType) true bodyStmt) :
      StmtHasType program returnType context inLoop
        (.forValues localId iterableExpr bodyStmt)
  | forSlice
      (iterable : ExprHasType program context iterableExpr (.slice elementType))
      (body : StmtHasType program returnType (context.bind localId elementType) true bodyStmt) :
      StmtHasType program returnType context inLoop
        (.forValues localId iterableExpr bodyStmt)
  | forRange
      (start : ExprHasType program context startExpr (.scalar (.signed .i32)))
      (stop : OptionExprHasType program context (.scalar (.signed .i32)) stopExpr)
      (body : StmtHasType program returnType
        (context.bind localId (.scalar (.signed .i32))) true bodyStmt) :
      StmtHasType program returnType context inLoop
        (.forRange localId startExpr stopExpr inclusive bodyStmt)
  | returnUnit (isUnit : returnType = .unit) :
      StmtHasType program returnType context inLoop (.returnValue none)
  | returnValue (value : ExprHasType program context expression returnType) :
      StmtHasType program returnType context inLoop (.returnValue (some expression))
  | breakLoop : StmtHasType program returnType context true .breakLoop
  | continueLoop : StmtHasType program returnType context true .continueLoop

inductive DefinitelyReturns : Stmt → Prop where
  | returnValue : DefinitelyReturns (.returnValue value)
  | sequenceLeft (returns : DefinitelyReturns first) :
      DefinitelyReturns (.sequence first second)
  | sequenceRight (returns : DefinitelyReturns second) :
      DefinitelyReturns (.sequence first second)
  | letLocal (returns : DefinitelyReturns body) :
      DefinitelyReturns (.letLocal localId type initializer body)
  | letUninitialized (returns : DefinitelyReturns body) :
      DefinitelyReturns (.letUninitialized localId type body)
  | ifThenElse
      (thenReturns : DefinitelyReturns thenBranch)
      (elseReturns : DefinitelyReturns elseBranch) :
      DefinitelyReturns (.ifThenElse condition thenBranch elseBranch)

def FunctionWellTyped (program : Program) (function : Function) : Prop :=
  match function.body with
  | none =>
      match function.external with
      | none => False
      | some (.host service) =>
          function.parameters.map Prod.snd = service.parameterTypes ∧
            function.returnType = service.returnType
      | some (.panic) | some (.unreachable) =>
          function.parameters = [] ∧ function.returnType = .unit
      | some (.unavailable _) | some (.opaque _) => True
  | some body =>
      function.external = none ∧
        StmtHasType program function.returnType
          (parameterContext function.parameters) false body ∧
        (function.returnType = .unit ∨ DefinitelyReturns body)

def ConstantWellTyped (program : Program) (constant : Constant) : Prop :=
  ValueHasType program constant.value constant.type

def ProgramWellTyped (program : Program) : Prop :=
  (∀ constant ∈ program.constants, ConstantWellTyped program constant) ∧
    (∀ function ∈ program.functions, FunctionWellTyped program function)

end Lanius.Typing
