import Lanius.ProgramElaboration.Expression

namespace Lanius.ProgramElaboration

open Lanius

inductive SymbolicRangeBoundChecks (context : SymbolicBodyContext) :
    Surface.RangeBound → Prop where
  | integer
      (checked : SymbolicExprChecks context (.literal (.integer text))
        (.scalar (.signed .i32))) :
      SymbolicRangeBoundChecks context (.integer text)
  | postfix
      (formed : Surface.RangeBoundPostfix surfaceExpression)
      (checked : SymbolicExprChecks context surfaceExpression
        (.scalar (.signed .i32))) :
      SymbolicRangeBoundChecks context (.postfix surfaceExpression)

inductive SymbolicRangeChecks (context : SymbolicBodyContext) :
    Surface.RangeKind → Option Surface.RangeBound →
      Option Surface.RangeBound → Prop where
  | full : SymbolicRangeChecks context .full none none
  | from (start : SymbolicRangeBoundChecks context surfaceStart) :
      SymbolicRangeChecks context .from (some surfaceStart) none
  | toExclusive (stop : SymbolicRangeBoundChecks context surfaceStop) :
      SymbolicRangeChecks context .toExclusive none (some surfaceStop)
  | toInclusive (stop : SymbolicRangeBoundChecks context surfaceStop) :
      SymbolicRangeChecks context .toInclusive none (some surfaceStop)
  | exclusive
      (start : SymbolicRangeBoundChecks context surfaceStart)
      (stop : SymbolicRangeBoundChecks context surfaceStop) :
      SymbolicRangeChecks context .exclusive
        (some surfaceStart) (some surfaceStop)
  | inclusive
      (start : SymbolicRangeBoundChecks context surfaceStart)
      (stop : SymbolicRangeBoundChecks context surfaceStop) :
      SymbolicRangeChecks context .inclusive
        (some surfaceStart) (some surfaceStop)

/-- Range bounds use the ordinary recursive expression-checking relation and
    expose the exact `i32` core term consumed by the loop. -/
inductive RangeBoundSpecializes
    (substitution : Static.Substitution)
    (groundReturnType : Static.GroundTy)
    (symbolic : SymbolicBodyContext)
    (concrete : SurfaceElaboration.Context)
    (contexts : symbolic.Specializes substitution groundReturnType concrete) :
    Surface.RangeBound → Core.Expr → Prop where
  | integer
      (checked : ExprCheckingDerivationSpecializes substitution groundReturnType
        symbolic concrete contexts (.literal (.integer text))
        (.scalar (.signed .i32)) (.scalar (.signed .i32)) core) :
      RangeBoundSpecializes substitution groundReturnType symbolic concrete
        contexts (.integer text) core
  | postfix
      (formed : Surface.RangeBoundPostfix surfaceExpression)
      (checked : ExprCheckingDerivationSpecializes substitution groundReturnType
        symbolic concrete contexts surfaceExpression (.scalar (.signed .i32))
        (.scalar (.signed .i32)) core) :
      RangeBoundSpecializes substitution groundReturnType symbolic concrete
        contexts (.postfix surfaceExpression) core

inductive RangeSpecializes
    (substitution : Static.Substitution)
    (groundReturnType : Static.GroundTy)
    (symbolic : SymbolicBodyContext)
    (concrete : SurfaceElaboration.Context)
    (contexts : symbolic.Specializes substitution groundReturnType concrete) :
    Surface.RangeKind → Option Surface.RangeBound →
      Option Surface.RangeBound → Core.Expr → Option Core.Expr → Bool → Prop where
  | full : RangeSpecializes substitution groundReturnType symbolic concrete
      contexts .full none none (.value (.signed .i32 0)) none false
  | from
      (start : RangeBoundSpecializes substitution groundReturnType symbolic
        concrete contexts surfaceStart coreStart) :
      RangeSpecializes substitution groundReturnType symbolic concrete contexts
        .from (some surfaceStart) none coreStart none false
  | toExclusive
      (stop : RangeBoundSpecializes substitution groundReturnType symbolic
        concrete contexts surfaceStop coreStop) :
      RangeSpecializes substitution groundReturnType symbolic concrete contexts
        .toExclusive none (some surfaceStop) (.value (.signed .i32 0))
        (some coreStop) false
  | toInclusive
      (stop : RangeBoundSpecializes substitution groundReturnType symbolic
        concrete contexts surfaceStop coreStop) :
      RangeSpecializes substitution groundReturnType symbolic concrete contexts
        .toInclusive none (some surfaceStop) (.value (.signed .i32 0))
        (some coreStop) true
  | exclusive
      (start : RangeBoundSpecializes substitution groundReturnType symbolic
        concrete contexts surfaceStart coreStart)
      (stop : RangeBoundSpecializes substitution groundReturnType symbolic
        concrete contexts surfaceStop coreStop) :
      RangeSpecializes substitution groundReturnType symbolic concrete contexts
        .exclusive (some surfaceStart) (some surfaceStop) coreStart
        (some coreStop) false
  | inclusive
      (start : RangeBoundSpecializes substitution groundReturnType symbolic
        concrete contexts surfaceStart coreStart)
      (stop : RangeBoundSpecializes substitution groundReturnType symbolic
        concrete contexts surfaceStop coreStop) :
      RangeSpecializes substitution groundReturnType symbolic concrete contexts
        .inclusive (some surfaceStart) (some surfaceStop) coreStart
        (some coreStop) true

theorem RangeBoundSpecializes.symbolicCheck
    (specialized : RangeBoundSpecializes substitution groundReturnType symbolicContext
      concrete contexts surface core) :
    SymbolicRangeBoundChecks symbolicContext surface := by
  cases specialized with
  | integer checked => exact .integer checked.symbolicCheck
  | «postfix» formed checked => exact .postfix formed checked.symbolicCheck

theorem RangeBoundSpecializes.lowers
    (specialized : RangeBoundSpecializes substitution groundReturnType symbolicContext
      concrete contexts surface core) :
    SurfaceElaboration.RangeBoundLowers concrete surface core := by
  cases specialized with
  | integer checked => exact .integer checked.concreteCheck.2
  | «postfix» formed checked => exact .postfix formed checked.concreteCheck.2

theorem RangeSpecializes.symbolicChecks
    (specialized : RangeSpecializes substitution groundReturnType symbolicContext
      concrete contexts kind start stop coreStart coreStop isInclusive) :
    SymbolicRangeChecks symbolicContext kind start stop := by
  cases specialized with
  | full => exact .full
  | «from» start => exact .from start.symbolicCheck
  | toExclusive stop => exact .toExclusive stop.symbolicCheck
  | toInclusive stop => exact .toInclusive stop.symbolicCheck
  | exclusive start stop =>
      exact .exclusive start.symbolicCheck stop.symbolicCheck
  | inclusive start stop =>
      exact .inclusive start.symbolicCheck stop.symbolicCheck

theorem RangeSpecializes.lowers
    (specialized : RangeSpecializes substitution groundReturnType symbolicContext
      concrete contexts kind start stop coreStart coreStop isInclusive) :
    SurfaceElaboration.RangeLowers concrete kind start stop coreStart coreStop
      isInclusive := by
  cases specialized with
  | full => exact .full
  | «from» start => exact .from start.lowers
  | toExclusive stop => exact .toExclusive stop.lowers
  | toInclusive stop => exact .toInclusive stop.lowers
  | exclusive start stop => exact .exclusive start.lowers stop.lowers
  | inclusive start stop => exact .inclusive start.lowers stop.lowers

/-- Symbolic recognition of the two standard-library nominal range values
    supported by the current compiler's path-iterable rule. -/
inductive SymbolicNamedRangeHasElement
    (context : SymbolicBodyContext) (path : Surface.Path) : Bool → Prop where
  | exclusive
      (constructor : SurfaceElaboration.StructConstructorScheme)
      (selected : SurfaceElaboration.SelectsStructConstructor context.globals
        SurfaceElaboration.coreRangeTypePath constructor)
      (distinct : ∀ candidate,
        SurfaceElaboration.SelectsStructConstructor context.globals
          SurfaceElaboration.coreRangeInclusiveTypePath candidate →
        candidate.sourceType ≠ constructor.sourceType)
      (iterable : SymbolicExprInfers context (.path path)
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])) :
      SymbolicNamedRangeHasElement context path false
  | inclusive
      (constructor : SurfaceElaboration.StructConstructorScheme)
      (selected : SurfaceElaboration.SelectsStructConstructor context.globals
        SurfaceElaboration.coreRangeInclusiveTypePath constructor)
      (distinct : ∀ candidate,
        SurfaceElaboration.SelectsStructConstructor context.globals
          SurfaceElaboration.coreRangeTypePath candidate →
        candidate.sourceType ≠ constructor.sourceType)
      (iterable : SymbolicExprInfers context (.path path)
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])) :
      SymbolicNamedRangeHasElement context path true

/-- One nominal range path is recognized at symbolic types, grounded to the
    same canonical nominal instance, and projected through its exact concrete
    `start` and `end` field rows. -/
inductive NamedRangeSpecializes
    (substitution : Static.Substitution)
    (groundReturnType : Static.GroundTy)
    (symbolic : SymbolicBodyContext)
    (concrete : SurfaceElaboration.Context)
    (contexts : symbolic.Specializes substitution groundReturnType concrete)
    (path : Surface.Path) : Core.Expr → Core.Expr → Bool → Prop where
  | exclusive
      (constructor : SurfaceElaboration.StructConstructorScheme)
      (selected : SurfaceElaboration.SelectsStructConstructor symbolic.globals
        SurfaceElaboration.coreRangeTypePath constructor)
      (distinct : ∀ candidate,
        SurfaceElaboration.SelectsStructConstructor symbolic.globals
          SurfaceElaboration.coreRangeInclusiveTypePath candidate →
        candidate.sourceType ≠ constructor.sourceType)
      (iterable : ExprInferenceDerivationSpecializes substitution
        groundReturnType symbolic concrete contexts (.path path)
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        coreIterable)
      (startField endField : SurfaceElaboration.FieldEntry)
      (startSelected : SurfaceElaboration.SelectsField concrete
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        "start" startField)
      (endSelected : SurfaceElaboration.SelectsField concrete
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        "end" endField)
      (startType : startField.type = .scalar (.signed .i32))
      (endType : endField.type = .scalar (.signed .i32)) :
      NamedRangeSpecializes substitution groundReturnType symbolic concrete
        contexts path (.field coreIterable startField.field)
        (.field coreIterable endField.field) false
  | inclusive
      (constructor : SurfaceElaboration.StructConstructorScheme)
      (selected : SurfaceElaboration.SelectsStructConstructor symbolic.globals
        SurfaceElaboration.coreRangeInclusiveTypePath constructor)
      (distinct : ∀ candidate,
        SurfaceElaboration.SelectsStructConstructor symbolic.globals
          SurfaceElaboration.coreRangeTypePath candidate →
        candidate.sourceType ≠ constructor.sourceType)
      (iterable : ExprInferenceDerivationSpecializes substitution
        groundReturnType symbolic concrete contexts (.path path)
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        coreIterable)
      (startField endField : SurfaceElaboration.FieldEntry)
      (startSelected : SurfaceElaboration.SelectsField concrete
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        "start" startField)
      (endSelected : SurfaceElaboration.SelectsField concrete
        (.nominal constructor.sourceType [.scalar (.signed .i32)] [])
        "end" endField)
      (startType : startField.type = .scalar (.signed .i32))
      (endType : endField.type = .scalar (.signed .i32)) :
      NamedRangeSpecializes substitution groundReturnType symbolic concrete
        contexts path (.field coreIterable startField.field)
        (.field coreIterable endField.field) true

theorem NamedRangeSpecializes.symbolic
    (specialized : NamedRangeSpecializes substitution groundReturnType
      symbolicContext concrete contexts path coreStart coreStop isInclusive) :
    SymbolicNamedRangeHasElement symbolicContext path isInclusive := by
  cases specialized with
  | exclusive constructor selected distinct iterable startField endField startSelected
      endSelected startType endType =>
      exact .exclusive constructor selected distinct iterable.symbolicInference
  | inclusive constructor selected distinct iterable startField endField startSelected
      endSelected startType endType =>
      exact .inclusive constructor selected distinct iterable.symbolicInference

theorem NamedRangeSpecializes.lowers
    (specialized : NamedRangeSpecializes substitution groundReturnType
      symbolicContext concrete contexts path coreStart coreStop isInclusive) :
    SurfaceElaboration.NamedRangeLowers concrete path coreStart coreStop
      isInclusive := by
  cases specialized with
  | exclusive constructor selected distinct iterable startField endField startSelected
      endSelected startType endType =>
      exact .exclusive constructor (contexts.selectsStructConstructor selected)
        iterable.concreteInference.2 startField endField startSelected endSelected
        startType endType
  | inclusive constructor selected distinct iterable startField endField startSelected
      endSelected startType endType =>
      exact .inclusive constructor (contexts.selectsStructConstructor selected)
        iterable.concreteInference.2 startField endField startSelected endSelected
        startType endType

inductive SymbolicForIterableHasElement
    (context : SymbolicBodyContext) :
    Surface.ForIterable → Static.Ty → Prop where
  | array
      (iterable : SymbolicExprInfers context (.path path)
        (.array elementType length)) :
      SymbolicForIterableHasElement context (.path path) elementType
  | slice
      (iterable : SymbolicExprInfers context (.path path)
        (.slice elementType)) :
      SymbolicForIterableHasElement context (.path path) elementType
  | namedRange
      (range : SymbolicNamedRangeHasElement context path inclusive) :
      SymbolicForIterableHasElement context (.path path)
        (.scalar (.signed .i32))
  | range
      (checked : SymbolicRangeChecks context kind surfaceStart surfaceStop) :
      SymbolicForIterableHasElement context
        (.range kind surfaceStart surfaceStop) (.scalar (.signed .i32))

/-- Parameter bindings are retained in the same newest-first order produced by
    repeated concrete `bindLocal` allocation. Source parameter names are
    declaration-wide unique, but preserving allocator order also makes the
    symbolic and concrete body contexts structurally compositional. -/
inductive SymbolicParametersBind :
    List Surface.Parameter → List Static.Ty →
      List SymbolicLocalBinding → Prop where
  | nil : SymbolicParametersBind [] [] []
  | named
      (tail : SymbolicParametersBind surfaceTail typeTail bindingTail) :
      SymbolicParametersBind (.named name annotation :: surfaceTail)
        (type :: typeTail) (bindingTail ++ [{ name := name, type := type }])
  | selfValue
      (tail : SymbolicParametersBind surfaceTail typeTail bindingTail) :
      SymbolicParametersBind (.selfValue annotation :: surfaceTail)
        (type :: typeTail) (bindingTail ++ [{ name := "self", type }])
  | selfReference
      (tail : SymbolicParametersBind surfaceTail typeTail bindingTail) :
      SymbolicParametersBind (.selfReference :: surfaceTail)
        (type :: typeTail) (bindingTail ++ [{ name := "self", type }])

theorem SymbolicParametersBind.lengths
    (bound : SymbolicParametersBind surface parameters bindings) :
    parameters.length = surface.length := by
  induction bound with
  | nil => rfl
  | named tail tailIH => simp [tailIH]
  | selfValue tail tailIH => simp [tailIH]
  | selfReference tail tailIH => simp [tailIH]

mutual
  inductive SymbolicStmtsWellTyped :
      SymbolicBodyContext → Bool → List Surface.Stmt → Prop where
    | nil : SymbolicStmtsWellTyped context inLoop []
    | expression
        (head : SymbolicExprInfers context surfaceExpression type)
        (tail : SymbolicStmtsWellTyped context inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop
          (.expression surfaceExpression :: surfaceTail)
    | letInferred
        (initializer : SymbolicExprInfers context surfaceInitializer type)
        (tail : SymbolicStmtsWellTyped (context.bind name type)
          inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop
          (.letLocal name none (some surfaceInitializer) :: surfaceTail)
    | letAnnotated
        (annotation : TypeRetains context.globals surfaceType type)
        (initializer : SymbolicExprChecks context surfaceInitializer type)
        (tail : SymbolicStmtsWellTyped (context.bind name type)
          inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop
          (.letLocal name (some surfaceType) (some surfaceInitializer) :: surfaceTail)
    | letUninitialized
        (annotation : TypeRetains context.globals surfaceType type)
        (tail : SymbolicStmtsWellTyped (context.bind name type)
          inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop
          (.letLocal name (some surfaceType) none :: surfaceTail)
    | returnUnit
        (unit : context.returnType = .unit)
        (tail : SymbolicStmtsWellTyped context inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop
          (.returnValue none :: surfaceTail)
    | returnValue
        (value : SymbolicExprChecks context surfaceValue context.returnType)
        (tail : SymbolicStmtsWellTyped context inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop
          (.returnValue (some surfaceValue) :: surfaceTail)
    | ifThenElse
        (condition : SymbolicExprChecks context surfaceCondition (.scalar .bool))
        (thenBody : SymbolicStmtsWellTyped context inLoop surfaceThen)
        (elseBody : SymbolicStmtsWellTyped context inLoop surfaceElse)
        (tail : SymbolicStmtsWellTyped context inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop
          (.ifThenElse surfaceCondition surfaceThen surfaceElse :: surfaceTail)
    | whileLoop
        (condition : SymbolicExprChecks context surfaceCondition (.scalar .bool))
        (body : SymbolicStmtsWellTyped context true surfaceBody)
        (tail : SymbolicStmtsWellTyped context inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop
          (.whileLoop surfaceCondition surfaceBody :: surfaceTail)
    | forLoop
        (iterable : SymbolicForIterableHasElement context
          surfaceIterable elementType)
        (body : SymbolicStmtsWellTyped (context.bind name elementType)
          true surfaceBody)
        (tail : SymbolicStmtsWellTyped context inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop
          (.forLoop name surfaceIterable surfaceBody :: surfaceTail)
    | breakLoop
        (inside : inLoop = true)
        (tail : SymbolicStmtsWellTyped context inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop (.breakLoop :: surfaceTail)
    | continueLoop
        (inside : inLoop = true)
        (tail : SymbolicStmtsWellTyped context inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop (.continueLoop :: surfaceTail)
    | block
        (body : SymbolicStmtsWellTyped context inLoop surfaceBody)
        (tail : SymbolicStmtsWellTyped context inLoop surfaceTail) :
        SymbolicStmtsWellTyped context inLoop
          (.block surfaceBody :: surfaceTail)
end

/-- Statement specialization consumes exact-output recursive expression
    derivations. The symbolic judgment, grounded type, and emitted child term
    therefore come from one occurrence witness rather than parallel premises. -/
inductive StmtsSpecialize
    (substitution : Static.Substitution)
    (groundReturnType : Static.GroundTy) :
    SymbolicBodyContext → SurfaceElaboration.Context → VarId → Bool →
      List Surface.Stmt → Core.Stmt → VarId → Prop where
  | nil
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next
        inLoop [] .skip next
  | expression
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (head : ExprInferenceDerivationSpecializes substitution groundReturnType
        symbolic concrete contexts surfaceExpression symbolicType groundType
        coreExpression)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete next
        inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.expression surfaceExpression :: surfaceTail)
        (.sequence (.expression coreExpression) coreTail) final
  | letInferred
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (initializer : ExprInferenceDerivationSpecializes substitution
        groundReturnType symbolic concrete contexts surfaceInitializer
        symbolicType groundType coreInitializer)
      (coreType : groundType.toCore concrete.monomorphization = some loweredType)
      (tail : StmtsSpecialize substitution groundReturnType
        (symbolic.bind name symbolicType)
        (concrete.bindLocal name next groundType) (next + 1) inLoop
        surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.letLocal name none (some surfaceInitializer) :: surfaceTail)
        (.letLocal next loweredType coreInitializer coreTail) final
  | letAnnotated
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (annotation : TypeRetains symbolic.globals surfaceType symbolicType)
      (initializer : ExprCheckingDerivationSpecializes substitution
        groundReturnType symbolic concrete contexts surfaceInitializer
        symbolicType groundType coreInitializer)
      (coreType : groundType.toCore concrete.monomorphization = some loweredType)
      (tail : StmtsSpecialize substitution groundReturnType
        (symbolic.bind name symbolicType)
        (concrete.bindLocal name next groundType) (next + 1) inLoop
        surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.letLocal name (some surfaceType) (some surfaceInitializer) :: surfaceTail)
        (.letLocal next loweredType coreInitializer coreTail) final
  | letUninitialized
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (annotation : TypeRetains symbolic.globals surfaceType symbolicType)
      (typeGrounds : symbolicType.instantiate substitution = some groundType)
      (coreType : groundType.toCore concrete.monomorphization = some loweredType)
      (tail : StmtsSpecialize substitution groundReturnType
        (symbolic.bind name symbolicType)
        (concrete.bindLocal name next groundType) (next + 1) inLoop
        surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.letLocal name (some surfaceType) none :: surfaceTail)
        (.letUninitialized next loweredType coreTail) final
  | returnUnit
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (unit : symbolic.returnType = .unit)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete next
        inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.returnValue none :: surfaceTail)
        (.sequence (.returnValue none) coreTail) final
  | returnValue
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (value : ExprCheckingDerivationSpecializes substitution groundReturnType
        symbolic concrete contexts surfaceValue symbolic.returnType
        groundReturnType coreValue)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete next
        inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.returnValue (some surfaceValue) :: surfaceTail)
        (.sequence (.returnValue (some coreValue)) coreTail) final
  | ifThenElse
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (condition : ExprCheckingDerivationSpecializes substitution
        groundReturnType symbolic concrete contexts surfaceCondition
        (.scalar .bool) (.scalar .bool) coreCondition)
      (thenBody : StmtsSpecialize substitution groundReturnType symbolic concrete
        next inLoop surfaceThen coreThen thenNext)
      (elseBody : StmtsSpecialize substitution groundReturnType symbolic concrete
        next inLoop surfaceElse coreElse elseNext)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete
        (Nat.max thenNext elseNext) inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.ifThenElse surfaceCondition surfaceThen surfaceElse :: surfaceTail)
        (.sequence (.ifThenElse coreCondition coreThen coreElse) coreTail) final
  | whileLoop
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (condition : ExprCheckingDerivationSpecializes substitution
        groundReturnType symbolic concrete contexts surfaceCondition
        (.scalar .bool) (.scalar .bool) coreCondition)
      (body : StmtsSpecialize substitution groundReturnType symbolic concrete next
        true surfaceBody coreBody bodyNext)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete
        bodyNext inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.whileLoop surfaceCondition surfaceBody :: surfaceTail)
        (.sequence (.whileLoop coreCondition coreBody) coreTail) final
  | forArray
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (iterable : ExprInferenceDerivationSpecializes substitution
        groundReturnType symbolic concrete contexts (.path path)
        (.array elementType length) (.array groundElement groundLength)
        coreIterable)
      (body : StmtsSpecialize substitution groundReturnType
        (symbolic.bind name elementType)
        (concrete.bindLocal name next groundElement) (next + 1) true
        surfaceBody coreBody bodyNext)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete
        bodyNext inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.forLoop name (.path path) surfaceBody :: surfaceTail)
        (.sequence (.forValues next coreIterable coreBody) coreTail) final
  | forSlice
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (iterable : ExprInferenceDerivationSpecializes substitution
        groundReturnType symbolic concrete contexts (.path path)
        (.slice elementType) (.slice groundElement) coreIterable)
      (body : StmtsSpecialize substitution groundReturnType
        (symbolic.bind name elementType)
        (concrete.bindLocal name next groundElement) (next + 1) true
        surfaceBody coreBody bodyNext)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete
        bodyNext inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.forLoop name (.path path) surfaceBody :: surfaceTail)
        (.sequence (.forValues next coreIterable coreBody) coreTail) final
  | forNamedRange
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (range : NamedRangeSpecializes substitution groundReturnType symbolic
        concrete contexts path coreStart coreStop inclusive)
      (body : StmtsSpecialize substitution groundReturnType
        (symbolic.bind name (.scalar (.signed .i32)))
        (concrete.bindLocal name next (.scalar (.signed .i32))) (next + 1) true
        surfaceBody coreBody bodyNext)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete
        bodyNext inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.forLoop name (.path path) surfaceBody :: surfaceTail)
        (.sequence (.forRange next coreStart (some coreStop) inclusive coreBody)
          coreTail) final
  | forRange
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (range : RangeSpecializes substitution groundReturnType symbolic concrete
        contexts kind surfaceStart surfaceStop coreStart coreStop inclusive)
      (body : StmtsSpecialize substitution groundReturnType
        (symbolic.bind name (.scalar (.signed .i32)))
        (concrete.bindLocal name next (.scalar (.signed .i32))) (next + 1) true
        surfaceBody coreBody bodyNext)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete
        bodyNext inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.forLoop name (.range kind surfaceStart surfaceStop) surfaceBody :: surfaceTail)
        (.sequence (.forRange next coreStart coreStop inclusive coreBody) coreTail) final
  | breakLoop
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (inside : inLoop = true)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete next
        inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.breakLoop :: surfaceTail) (.sequence .breakLoop coreTail) final
  | continueLoop
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (inside : inLoop = true)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete next
        inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.continueLoop :: surfaceTail) (.sequence .continueLoop coreTail) final
  | block
      (contexts : symbolic.Specializes substitution groundReturnType concrete)
      (bounded : SurfaceElaboration.LocalIdsBelow concrete next)
      (body : StmtsSpecialize substitution groundReturnType symbolic concrete next
        inLoop surfaceBody coreBody bodyNext)
      (tail : StmtsSpecialize substitution groundReturnType symbolic concrete
        bodyNext inLoop surfaceTail coreTail final) :
      StmtsSpecialize substitution groundReturnType symbolic concrete next inLoop
        (.block surfaceBody :: surfaceTail) (.sequence coreBody coreTail) final

theorem StmtsSpecialize.symbolic
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    {next final : VarId} {inLoop : Bool}
    {surface : List Surface.Stmt} {core : Core.Stmt}
    (specialized : StmtsSpecialize substitution groundReturnType symbolic concrete
      next inLoop surface core final) :
    SymbolicStmtsWellTyped symbolic inLoop surface := by
  induction specialized with
  | nil => exact .nil
  | expression contexts bounded head tail tailIH =>
      exact .expression head.symbolicInference tailIH
  | letInferred contexts bounded initializer coreType tail tailIH =>
      exact .letInferred initializer.symbolicInference tailIH
  | letAnnotated contexts bounded annotation initializer coreType tail tailIH =>
      exact .letAnnotated annotation initializer.symbolicCheck tailIH
  | letUninitialized contexts bounded annotation typeGrounds coreType tail tailIH =>
      exact .letUninitialized annotation tailIH
  | returnUnit contexts bounded unit tail tailIH => exact .returnUnit unit tailIH
  | returnValue contexts bounded value tail tailIH =>
      exact .returnValue value.symbolicCheck tailIH
  | ifThenElse contexts bounded condition thenBody elseBody tail
      thenIH elseIH tailIH =>
      exact .ifThenElse condition.symbolicCheck thenIH elseIH tailIH
  | whileLoop contexts bounded condition body tail bodyIH tailIH =>
      exact .whileLoop condition.symbolicCheck bodyIH tailIH
  | forArray contexts bounded iterable body tail bodyIH tailIH =>
      exact .forLoop (.array iterable.symbolicInference) bodyIH tailIH
  | forSlice contexts bounded iterable body tail bodyIH tailIH =>
      exact .forLoop (.slice iterable.symbolicInference) bodyIH tailIH
  | forNamedRange contexts bounded range body tail bodyIH tailIH =>
      exact .forLoop (.namedRange range.symbolic) bodyIH tailIH
  | forRange contexts bounded range body tail bodyIH tailIH =>
      exact .forLoop (.range range.symbolicChecks) bodyIH tailIH
  | breakLoop contexts bounded inside tail tailIH => exact .breakLoop inside tailIH
  | continueLoop contexts bounded inside tail tailIH =>
      exact .continueLoop inside tailIH
  | block contexts bounded body tail bodyIH tailIH => exact .block bodyIH tailIH

theorem StmtsSpecialize.lowers
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    {next final : VarId} {inLoop : Bool}
    {surface : List Surface.Stmt} {core : Core.Stmt}
    (specialized : StmtsSpecialize substitution groundReturnType symbolic concrete
      next inLoop surface core final) :
    SurfaceElaboration.StmtsLower concrete next surface core final := by
  induction specialized with
  | nil => exact .nil
  | expression contexts bounded head tail tailIH =>
      exact .expression head.concreteInference.2 tailIH
  | letInferred contexts bounded initializer coreType tail tailIH =>
      exact .letInferred bounded.fresh initializer.concreteInference.2 coreType tailIH
  | letAnnotated contexts bounded annotation initializer coreType tail tailIH =>
      exact .letAnnotated bounded.fresh
        (annotation.specializes contexts initializer.concreteCheck.1)
        initializer.concreteCheck.2 coreType tailIH
  | letUninitialized contexts bounded annotation typeGrounds coreType tail tailIH =>
      exact .letUninitialized bounded.fresh
        (annotation.specializes contexts typeGrounds) coreType tailIH
  | returnUnit contexts bounded unit tail tailIH => exact .returnUnit tailIH
  | returnValue contexts bounded value tail tailIH =>
      exact .returnValue value.concreteCheck.2 tailIH
  | ifThenElse contexts bounded condition thenBody elseBody tail
      thenIH elseIH tailIH =>
      exact .ifThenElse condition.concreteCheck.2 thenIH elseIH tailIH
  | whileLoop contexts bounded condition body tail bodyIH tailIH =>
      exact .whileLoop condition.concreteCheck.2 bodyIH tailIH
  | forArray contexts bounded iterable body tail bodyIH tailIH =>
      exact .forArray bounded.fresh iterable.concreteInference.2 bodyIH tailIH
  | forSlice contexts bounded iterable body tail bodyIH tailIH =>
      exact .forSlice bounded.fresh iterable.concreteInference.2 bodyIH tailIH
  | forNamedRange contexts bounded range body tail bodyIH tailIH =>
      exact .forNamedRange bounded.fresh range.lowers bodyIH tailIH
  | forRange contexts bounded range body tail bodyIH tailIH =>
      exact .forRange bounded.fresh range.lowers bodyIH tailIH
  | breakLoop contexts bounded inside tail tailIH => exact .breakLoop tailIH
  | continueLoop contexts bounded inside tail tailIH => exact .continueLoop tailIH
  | block contexts bounded body tail bodyIH tailIH => exact .block bodyIH tailIH

theorem StmtsSpecialize.contexts
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    {next final : VarId} {inLoop : Bool}
    {surface : List Surface.Stmt} {core : Core.Stmt}
    (specialized : StmtsSpecialize substitution groundReturnType symbolic concrete
      next inLoop surface core final) :
    symbolic.Specializes substitution groundReturnType concrete := by
  cases specialized <;> assumption

theorem StmtsSpecialize.initialBounded
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    {next final : VarId} {inLoop : Bool}
    {surface : List Surface.Stmt} {core : Core.Stmt}
    (specialized : StmtsSpecialize substitution groundReturnType symbolic concrete
      next inLoop surface core final) :
    SurfaceElaboration.LocalIdsBelow concrete next := by
  cases specialized <;> assumption

theorem StmtsSpecialize.final_ge
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    {next final : VarId} {inLoop : Bool}
    {surface : List Surface.Stmt} {core : Core.Stmt}
    (specialized : StmtsSpecialize substitution groundReturnType symbolic concrete
      next inLoop surface core final) :
    next ≤ final := by
  induction specialized with
  | nil => exact Nat.le_refl _
  | expression contexts bounded head tail tailIH => exact tailIH
  | letInferred contexts bounded initializer coreType tail tailIH =>
      exact Nat.le_trans (Nat.le_succ _) tailIH
  | letAnnotated contexts bounded annotation initializer coreType tail tailIH =>
      exact Nat.le_trans (Nat.le_succ _) tailIH
  | letUninitialized contexts bounded annotation typeGrounds coreType tail tailIH =>
      exact Nat.le_trans (Nat.le_succ _) tailIH
  | returnUnit contexts bounded unit tail tailIH => exact tailIH
  | returnValue contexts bounded value tail tailIH => exact tailIH
  | ifThenElse contexts bounded condition thenBody elseBody tail
      thenIH elseIH tailIH =>
      exact Nat.le_trans (Nat.le_trans thenIH (Nat.le_max_left _ _)) tailIH
  | whileLoop contexts bounded condition body tail bodyIH tailIH =>
      exact Nat.le_trans bodyIH tailIH
  | forArray contexts bounded iterable body tail bodyIH tailIH =>
      exact Nat.le_trans (Nat.le_trans (Nat.le_succ _) bodyIH) tailIH
  | forSlice contexts bounded iterable body tail bodyIH tailIH =>
      exact Nat.le_trans (Nat.le_trans (Nat.le_succ _) bodyIH) tailIH
  | forNamedRange contexts bounded range body tail bodyIH tailIH =>
      exact Nat.le_trans (Nat.le_trans (Nat.le_succ _) bodyIH) tailIH
  | forRange contexts bounded range body tail bodyIH tailIH =>
      exact Nat.le_trans (Nat.le_trans (Nat.le_succ _) bodyIH) tailIH
  | breakLoop contexts bounded inside tail tailIH => exact tailIH
  | continueLoop contexts bounded inside tail tailIH => exact tailIH
  | block contexts bounded body tail bodyIH tailIH => exact Nat.le_trans bodyIH tailIH

theorem StmtsSpecialize.finalBounded
    {substitution : Static.Substitution}
    {groundReturnType : Static.GroundTy}
    {symbolic : SymbolicBodyContext}
    {concrete : SurfaceElaboration.Context}
    {next final : VarId} {inLoop : Bool}
    {surface : List Surface.Stmt} {core : Core.Stmt}
    (specialized : StmtsSpecialize substitution groundReturnType symbolic concrete
      next inLoop surface core final) :
    SurfaceElaboration.LocalIdsBelow concrete final :=
  specialized.initialBounded.mono specialized.final_ge

def FunctionBodySymbolicallyTyped
    (globals : SurfaceElaboration.Context)
    (assumptions : List Static.TraitPattern)
    (parameters : List Surface.Parameter)
    (parameterTypes : List Static.Ty)
    (returnType : Static.Ty)
    (body : List Surface.Stmt) : Prop :=
  ∃ bindings,
    SymbolicParametersBind parameters parameterTypes bindings ∧
      SymbolicStmtsWellTyped {
        globals
        assumptions
        returnType
        locals := bindings
      } false body

def symbolicMethodParameterTypes (scheme : Static.MethodScheme) : List Static.Ty :=
  match scheme.receiverMode with
  | .none => scheme.argumentTypes
  | .value | .explicit => scheme.receiverType :: scheme.argumentTypes
  | .reference => .reference scheme.receiverType :: scheme.argumentTypes

/-- Parameters allocate dense core local IDs from left to right and extend the
    body context. A receiver type is present only while lowering an impl method
    or a trait method instance. -/
inductive ParametersLower :
    SurfaceElaboration.Context → Option Static.GroundTy → VarId →
      List Surface.Parameter → List Static.GroundTy →
      List (VarId × Core.Ty) → SurfaceElaboration.Context → VarId → Prop where
  | nil : ParametersLower context none next [] [] [] context next
  | named
      (notShadowed : SurfaceElaboration.NoLocalNamed context.locals name)
      (type : SurfaceElaboration.TypeGrounds context surfaceType groundType)
      (coreType : groundType.toCore context.monomorphization = some loweredType)
      (tail : ParametersLower (context.bindLocal name next groundType) none (next + 1)
        surfaceTail groundTail coreTail result final) :
      ParametersLower context none next
        (.named name surfaceType :: surfaceTail)
        (groundType :: groundTail) ((next, loweredType) :: coreTail) result final
  | namedReceiver
      (notShadowed : SurfaceElaboration.NoLocalNamed context.locals name)
      (type : SurfaceElaboration.TypeGrounds context surfaceType receiverType)
      (coreType : receiverType.toCore context.monomorphization = some loweredType)
      (tail : ParametersLower (context.bindLocal name next receiverType) none (next + 1)
        surfaceTail groundTail coreTail result final) :
      ParametersLower context (some receiverType) next
        (.named name surfaceType :: surfaceTail)
        (receiverType :: groundTail) ((next, loweredType) :: coreTail) result final
  | selfValue
      (notShadowed : SurfaceElaboration.NoLocalNamed context.locals "self")
      (tail : ParametersLower (context.bindLocal "self" next receiverType)
        none (next + 1) surfaceTail groundTail coreTail result final)
      (coreType : receiverType.toCore context.monomorphization = some loweredType) :
      ParametersLower context (some receiverType) next
        (.selfValue none :: surfaceTail)
        (receiverType :: groundTail) ((next, loweredType) :: coreTail) result final
  | selfValueTyped
      (notShadowed : SurfaceElaboration.NoLocalNamed context.locals "self")
      (annotation : SurfaceElaboration.TypeGrounds context surfaceType receiverType)
      (tail : ParametersLower (context.bindLocal "self" next receiverType)
        none (next + 1) surfaceTail groundTail coreTail result final)
      (coreType : receiverType.toCore context.monomorphization = some loweredType) :
      ParametersLower context (some receiverType) next
        (.selfValue (some surfaceType) :: surfaceTail)
        (receiverType :: groundTail) ((next, loweredType) :: coreTail) result final
  | selfReference
      (notShadowed : SurfaceElaboration.NoLocalNamed context.locals "self")
      (coreReferent : receiverType.toCore context.monomorphization = some referent)
      (tail : ParametersLower
        (context.bindLocal "self" next (.reference receiverType))
        none (next + 1) surfaceTail groundTail coreTail result final) :
      ParametersLower context (some receiverType) next
        (.selfReference :: surfaceTail)
        (.reference receiverType :: groundTail)
        ((next, .reference referent) :: coreTail) result final

/-- Symbolic parameter retention and concrete dense allocation extend one
    specializing context in lockstep. The theorem is lookup-order exact because
    `SymbolicParametersBind` and `ParametersLower` both retain newest bindings
    first. -/
theorem SymbolicParametersBind.specializes
    {symbolic : SymbolicBodyContext}
    (bound : SymbolicParametersBind surface symbolicTypes symbolicBindings)
    (contexts : symbolic.Specializes substitution groundReturnType concrete)
    (typesGround : Static.instantiateTypes substitution symbolicTypes =
      some groundTypes)
    (lowered : ParametersLower concrete receiver next surface groundTypes
      coreParameters result final) :
    (symbolic.bindMany symbolicBindings).Specializes substitution
      groundReturnType result := by
  induction bound generalizing symbolic concrete receiver next groundTypes
      coreParameters result final with
  | nil =>
      simp [Static.instantiateTypes] at typesGround
      subst groundTypes
      cases lowered
      simpa [SymbolicBodyContext.bindMany] using contexts
  | @named surfaceTail typeTail bindingTail name annotation type tail tailIH =>
      cases headGrounded : type.instantiate substitution with
      | none => simp [Static.instantiateTypes, headGrounded] at typesGround
      | some groundType =>
          cases tailGrounded : Static.instantiateTypes substitution typeTail with
          | none =>
              simp [Static.instantiateTypes, headGrounded, tailGrounded]
                at typesGround
          | some groundTail =>
              simp [Static.instantiateTypes, headGrounded, tailGrounded]
                at typesGround
              subst groundTypes
              cases lowered with
              | named notShadowed typeLowered coreType loweredTail =>
                  have tailContexts := tailIH
                    (contexts.bind name next type groundType headGrounded)
                    tailGrounded loweredTail
                  simpa [SymbolicBodyContext.bindMany, List.foldr_append] using
                    tailContexts
              | namedReceiver notShadowed typeLowered coreType loweredTail =>
                  have tailContexts := tailIH
                    (contexts.bind name next type groundType headGrounded)
                    tailGrounded loweredTail
                  simpa [SymbolicBodyContext.bindMany, List.foldr_append] using
                    tailContexts
  | @selfValue surfaceTail typeTail bindingTail annotation type tail tailIH =>
      cases headGrounded : type.instantiate substitution with
      | none => simp [Static.instantiateTypes, headGrounded] at typesGround
      | some groundType =>
          cases tailGrounded : Static.instantiateTypes substitution typeTail with
          | none =>
              simp [Static.instantiateTypes, headGrounded, tailGrounded]
                at typesGround
          | some groundTail =>
              simp [Static.instantiateTypes, headGrounded, tailGrounded]
                at typesGround
              subst groundTypes
              cases lowered with
              | selfValue notShadowed loweredTail coreType =>
                  have tailContexts := tailIH
                    (contexts.bind "self" next type _ headGrounded)
                    tailGrounded loweredTail
                  simpa [SymbolicBodyContext.bindMany, List.foldr_append] using
                    tailContexts
              | selfValueTyped notShadowed annotationLowered loweredTail coreType =>
                  have tailContexts := tailIH
                    (contexts.bind "self" next type groundType headGrounded)
                    tailGrounded loweredTail
                  simpa [SymbolicBodyContext.bindMany, List.foldr_append] using
                    tailContexts
  | @selfReference surfaceTail typeTail bindingTail type tail tailIH =>
      cases headGrounded : type.instantiate substitution with
      | none => simp [Static.instantiateTypes, headGrounded] at typesGround
      | some groundType =>
          cases tailGrounded : Static.instantiateTypes substitution typeTail with
          | none =>
              simp [Static.instantiateTypes, headGrounded, tailGrounded]
                at typesGround
          | some groundTail =>
              simp [Static.instantiateTypes, headGrounded, tailGrounded]
                at typesGround
              subst groundTypes
              cases lowered with
              | selfReference notShadowed coreReferent loweredTail =>
                  have tailContexts := tailIH
                    (contexts.bind "self" next type _ headGrounded)
                    tailGrounded loweredTail
                  simpa [SymbolicBodyContext.bindMany, List.foldr_append] using
                    tailContexts

/-- One monomorphic function artifact is derived from one declaration-wide
    symbolic body derivation. Parameters, return interpretation, local-ID
    allocation, statement specialization, and the emitted core function all
    share their exact source occurrence in this single witness. -/
inductive FunctionSpecializes
    (program : Core.Program)
    (baseContext : SurfaceElaboration.Context)
    (surface : Surface.Function)
    (scheme : Static.FunctionScheme)
    (resolved : Static.FunctionInstance)
    (core : Core.Function) : Prop where
  | intro
      (substitution : Static.Substitution)
      (instantiated : Static.FunctionInstantiates baseContext.implementations
        scheme substitution resolved)
      (baseLocals : baseContext.locals = [])
      (symbolicBindings : List SymbolicLocalBinding)
      (symbolicParameters : SymbolicParametersBind surface.parameters
        scheme.parameterTypes symbolicBindings)
      (coreParameters : List (VarId × Core.Ty))
      (bodyContext : SurfaceElaboration.Context)
      (nextLocal : VarId)
      (parameters : ParametersLower { baseContext with substitution }
        none 0 surface.parameters resolved.parameterTypes coreParameters
        bodyContext nextLocal)
      (returnRetained : ReturnTypeRetains baseContext surface.name
        surface.returnType scheme.returnType)
      (coreReturnType : Core.Ty)
      (returnTypeCore : resolved.returnType.toCore baseContext.monomorphization =
        some coreReturnType)
      (coreBody : Core.Stmt)
      (finalLocal : VarId)
      (body : StmtsSpecialize substitution resolved.returnType {
          globals := baseContext
          assumptions := scheme.requirements
          returnType := scheme.returnType
          locals := symbolicBindings
        } bodyContext nextLocal false surface.body coreBody finalLocal)
      (definition : core = {
        id := resolved.function
        parameters := coreParameters
        returnType := coreReturnType
        body := some coreBody
      })
      (target : program.target = baseContext.target)
      (member : core ∈ program.functions)
      (typed : Typing.FunctionWellTyped program core) :
      FunctionSpecializes program baseContext surface scheme resolved core

/-- The independently checked result of lowering one monomorphic function
    instance. Generic substitution and instance identity are explicit inputs;
    the resulting core function must also satisfy the ordinary program typing
    judgment. -/
inductive FunctionLowers
    (program : Core.Program)
    (baseContext : SurfaceElaboration.Context)
    (surface : Surface.Function)
    (scheme : Static.FunctionScheme)
    (monomorphicInstance : Static.FunctionInstance)
    (core : Core.Function) : Prop where
  | intro
      (substitution : Static.Substitution)
      (instantiated : Static.FunctionInstantiates baseContext.implementations
        scheme substitution monomorphicInstance)
      (declarationParameters : scheme.parameterTypes.length = surface.parameters.length)
      (groundParameters : List Static.GroundTy)
      (coreParameters : List (VarId × Core.Ty))
      (bodyContext : SurfaceElaboration.Context)
      (nextLocal : VarId)
      (parameters : ParametersLower { baseContext with substitution := substitution }
        none 0 surface.parameters groundParameters coreParameters bodyContext nextLocal)
      (parameterTypes : groundParameters = monomorphicInstance.parameterTypes)
      (groundReturnType : Static.GroundTy)
      (returnType : ReturnTypeGrounds { baseContext with substitution := substitution }
        surface.name surface.returnType groundReturnType)
      (selectedReturnType : groundReturnType = monomorphicInstance.returnType)
      (coreReturnType : Core.Ty)
      (returnTypeCore : groundReturnType.toCore baseContext.monomorphization =
        some coreReturnType)
      (coreBody : Core.Stmt)
      (finalLocal : VarId)
      (body : SurfaceElaboration.StmtsLower bodyContext nextLocal
        surface.body coreBody finalLocal)
      (definition : core = {
        id := monomorphicInstance.function
        parameters := coreParameters
        returnType := coreReturnType
        body := some coreBody
      })
      (target : program.target = baseContext.target)
      (member : core ∈ program.functions)
      (typed : Typing.FunctionWellTyped program core) :
      FunctionLowers program baseContext surface scheme monomorphicInstance core

theorem FunctionSpecializes.symbolic
    (specialized : FunctionSpecializes program baseContext surface scheme
      resolved core) :
    FunctionBodySymbolicallyTyped baseContext scheme.requirements
      surface.parameters scheme.parameterTypes scheme.returnType surface.body := by
  cases specialized with
  | intro substitution instantiated baseLocals symbolicBindings symbolicParameters
      coreParameters bodyContext nextLocal parameters
      returnRetained coreReturnType returnTypeCore coreBody finalLocal body
      definition target member typed =>
      exact ⟨symbolicBindings, symbolicParameters, body.symbolic⟩

theorem FunctionSpecializes.lowers
    (specialized : FunctionSpecializes program baseContext surface scheme
      resolved core) :
    FunctionLowers program baseContext surface scheme resolved core := by
  cases specialized with
  | intro substitution instantiated baseLocals symbolicBindings symbolicParameters
      coreParameters bodyContext nextLocal parameters
      returnRetained coreReturnType returnTypeCore coreBody finalLocal body
      definition target member typed =>
      have initialContexts := SymbolicBodyContext.declarationSpecializes
        baseContext scheme.requirements scheme.returnType substitution
        resolved.returnType baseLocals instantiated.returnType
      apply FunctionLowers.intro
          (substitution := substitution)
          (groundParameters := resolved.parameterTypes)
          (coreParameters := coreParameters)
          (bodyContext := bodyContext)
          (nextLocal := nextLocal)
          (groundReturnType := resolved.returnType)
          (coreReturnType := coreReturnType)
          (coreBody := coreBody)
          (finalLocal := finalLocal)
      · exact instantiated
      · exact symbolicParameters.lengths
      · exact parameters
      · rfl
      · exact returnRetained.specializes initialContexts instantiated.returnType
      · rfl
      · exact returnTypeCore
      · exact body.lowers
      · exact definition
      · exact target
      · exact member
      · exact typed

theorem FunctionSpecializes.instanceTypes
    (specialized : FunctionSpecializes program baseContext surface scheme
      resolved core) :
    ∃ substitution,
      Static.instantiateTypes substitution scheme.parameterTypes =
        some resolved.parameterTypes ∧
      scheme.returnType.instantiate substitution = some resolved.returnType := by
  cases specialized with
  | intro substitution instantiated baseLocals symbolicBindings symbolicParameters
      coreParameters bodyContext nextLocal parameters
      returnRetained coreReturnType returnTypeCore coreBody finalLocal body
      definition target member typed =>
      exact ⟨substitution, instantiated.parameterTypes, instantiated.returnType⟩

theorem FunctionSpecializes.parameterContexts
    (specialized : FunctionSpecializes program baseContext surface scheme
      resolved core) :
    ∃ substitution symbolicBindings bodyContext,
      ({
        globals := baseContext
        assumptions := scheme.requirements
        returnType := scheme.returnType
        locals := symbolicBindings
      } : SymbolicBodyContext).Specializes substitution resolved.returnType
        bodyContext := by
  cases specialized with
  | intro substitution instantiated baseLocals actualBindings symbolicParameters
      coreParameters bodyContext nextLocal parameters returnRetained
      coreReturnType returnTypeCore coreBody finalLocal body definition target
      member typed =>
      have initial := SymbolicBodyContext.declarationSpecializes
        baseContext scheme.requirements scheme.returnType substitution
        resolved.returnType baseLocals instantiated.returnType
      have parameterContexts := symbolicParameters.specializes initial
        instantiated.parameterTypes parameters
      exact ⟨substitution, actualBindings, bodyContext, by
        simpa [SymbolicBodyContext.bindMany_eq, baseLocals] using
          parameterContexts⟩

/-- Closed nongeneric functions are the common boundary used by executable
    examples and zero-argument entrypoints. This theorem keeps the semantic
    obligations visible while discharging the structurally empty substitution
    and parameter traversal once. -/
theorem FunctionLowers.closedNongeneric
    (instantiated : Static.FunctionInstantiates baseContext.implementations
      scheme {} monomorphicInstance)
    (surfaceParameters : surface.parameters = [])
    (schemeParameters : scheme.parameterTypes = [])
    (instanceParameters : monomorphicInstance.parameterTypes = [])
    (groundReturnType : Static.GroundTy)
    (returnType : ReturnTypeGrounds { baseContext with substitution := {} }
      surface.name surface.returnType groundReturnType)
    (selectedReturnType : groundReturnType = monomorphicInstance.returnType)
    (coreReturnType : Core.Ty)
    (returnTypeCore : groundReturnType.toCore baseContext.monomorphization =
      some coreReturnType)
    (coreBody : Core.Stmt)
    (finalLocal : VarId)
    (body : SurfaceElaboration.StmtsLower
      { baseContext with substitution := {} } 0 surface.body coreBody finalLocal)
    (definition : core = {
      id := monomorphicInstance.function
      parameters := []
      returnType := coreReturnType
      body := some coreBody
    })
    (target : program.target = baseContext.target)
    (member : core ∈ program.functions)
    (typed : Typing.FunctionWellTyped program core) :
    FunctionLowers program baseContext surface scheme monomorphicInstance core := by
  apply FunctionLowers.intro
      (substitution := {})
      (groundParameters := [])
      (coreParameters := [])
      (bodyContext := { baseContext with substitution := {} })
      (nextLocal := 0)
      (groundReturnType := groundReturnType)
      (coreReturnType := coreReturnType)
      (coreBody := coreBody)
      (finalLocal := finalLocal)
  · exact instantiated
  · simp [schemeParameters, surfaceParameters]
  · simpa [surfaceParameters] using
      (ParametersLower.nil
        (context := { baseContext with substitution := {} }) (next := 0))
  · simpa [instanceParameters]
  · exact returnType
  · exact selectedReturnType
  · exact returnTypeCore
  · exact body
  · exact definition
  · exact target
  · exact member
  · exact typed

/-- Concrete lowering retains the ground instantiation that fixes the emitted
    parameter and return types of this specialization. -/
theorem FunctionLowers.instanceTypes
    (lowered : FunctionLowers program baseContext surface scheme
      monomorphicInstance core) :
    ∃ substitution,
      Static.instantiateTypes substitution scheme.parameterTypes =
        some monomorphicInstance.parameterTypes ∧
      scheme.returnType.instantiate substitution =
        some monomorphicInstance.returnType := by
  cases lowered with
  | intro substitution instantiated declarationParameters groundParameters
      coreParameters bodyContext nextLocal parameters parameterTypes
      groundReturnType returnType selectedReturnType coreReturnType
      returnTypeCore coreBody finalLocal body definition target member typed =>
      exact ⟨substitution, instantiated.parameterTypes,
        instantiated.returnType⟩

/-- Type-alias collection preserves the source target and assigns semantic
    generic parameter IDs. Expansion occurs in `TypeGrounds`, where recursive
    aliases have no finite derivation and are therefore rejected. -/
inductive CollectedTypeAlias
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (header : Declarations.DeclarationHeader)
    (entry : SurfaceElaboration.TypeAliasEntry) : Prop where
  | intro
      (address : Declarations.ItemAddress)
      (name : Surface.Name)
      (isPublic : Bool)
      (surfaceParameters : List Surface.GenericParameter)
      (predicates : List Surface.WherePredicate)
      (target : Surface.TypeExpr)
      (source : header.source = .item address)
      (headerMember : header ∈ catalog.headers)
      (headerMatches : Declarations.HeaderMatches pack header)
      (itemFound : pack.item? address = some
        (.typeAlias name isPublic surfaceParameters predicates target))
      (headerKind : header.kind = .typeAlias)
      (entryMember : entry ∈ context.typeAliases)
      (declaration : entry.declaration = header.declaration)
      (entryModule : entry.moduleId = header.moduleId)
      (namesUnique : GenericParameterNamesUnique surfaceParameters)
      (parameters : GenericParametersLower (context.forModule header.moduleId)
        0 0 surfaceParameters
        entry.parameters finalType finalConst)
      (genericRequirements whereRequirements : List Static.TraitPattern)
      (genericBounds : GenericBoundsRetain
        (withGenericParameters (context.forModule header.moduleId) entry.parameters)
        surfaceParameters genericRequirements)
      (whereBounds : WherePredicatesRetain
        (withGenericParameters (context.forModule header.moduleId) entry.parameters)
        predicates whereRequirements)
      (entryRequirements : entry.requirements =
        genericRequirements ++ whereRequirements)
      (entryTarget : entry.target = target) :
      CollectedTypeAlias pack catalog context header entry

inductive CollectedFunctionScheme
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (header : Declarations.DeclarationHeader)
    (scheme : Static.FunctionScheme) :
    SurfaceElaboration.Context → Prop where
  | intro
      (address : Declarations.ItemAddress)
      (surface : Surface.Function)
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (parameterTypes : List Static.Ty)
      (returnType : Static.Ty)
      (genericRequirements whereRequirements : List Static.TraitPattern)
      (source : header.source = .item address)
      (headerMember : header ∈ catalog.headers)
      (headerMatches : Declarations.HeaderMatches pack header)
      (itemFound : pack.item? address = some (.function surface))
      (headerKind : header.kind = .function)
      (schemeMember : scheme ∈ context.functions)
      (declaration : scheme.declaration = header.declaration)
      (namesUnique : GenericParameterNamesUnique surface.genericParameters)
      (parametersCollected : GenericParametersLower
        (context.forModule header.moduleId) 0 0
        surface.genericParameters genericParameters finalType finalConst)
      (schemeParameters : scheme.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (parameters : ParameterTypesRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.parameters parameterTypes)
      (schemeParameterTypes : scheme.parameterTypes = parameterTypes)
      (returned : ReturnTypeRetains
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.name surface.returnType returnType)
      (schemeReturnType : scheme.returnType = returnType)
      (genericBounds : GenericBoundsRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.genericParameters genericRequirements)
      (whereBounds : WherePredicatesRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.wherePredicates whereRequirements)
      (schemeRequirements : scheme.requirements =
        genericRequirements ++ whereRequirements)
      (bodyScoped : SourceWellFormed.FunctionBodyWellScoped
        (context.forModule header.moduleId) surface.parameters surface.body)
      (bodyTyped : FunctionBodySymbolicallyTyped
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        scheme.requirements surface.parameters scheme.parameterTypes
        scheme.returnType surface.body) :
      CollectedFunctionScheme pack catalog context header scheme
        (withGenericParameters (context.forModule header.moduleId)
          genericParameters)

/-- A collected source function exposes the declaration occurrence that owns
    its callable scheme row. -/
theorem CollectedFunctionScheme.source_declaration
    (collected : CollectedFunctionScheme pack catalog context header scheme
      bodyContext) :
    ∃ address, header.source = .item address ∧
      scheme.declaration = header.declaration := by
  cases collected with
  | intro address _surface _genericParameters _parameterTypes _returnType
      _genericRequirements _whereRequirements source _headerMember
      _headerMatches _itemFound _headerKind _schemeMember declaration
      _namesUnique _parametersCollected _schemeParameters _parameters
      _schemeParameterTypes _returned _schemeReturnType _genericBounds
      _whereBounds _schemeRequirements _bodyScoped _bodyTyped =>
      exact ⟨address, source, declaration⟩

theorem CollectedFunctionScheme.signature_substitute_unique
    (collected : CollectedFunctionScheme pack catalog context header scheme
      bodyContext)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      scheme.genericParameters typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      scheme.genericParameters typeArguments constArguments)
    (leftParameters : Static.substituteTypes leftSubstitution
      scheme.parameterTypes = some leftParameterTypes)
    (rightParameters : Static.substituteTypes rightSubstitution
      scheme.parameterTypes = some rightParameterTypes)
    (leftReturn : scheme.returnType.substitute leftSubstitution =
      some leftReturnType)
    (rightReturn : scheme.returnType.substitute rightSubstitution =
      some rightReturnType) :
    leftParameterTypes = rightParameterTypes ∧
      leftReturnType = rightReturnType := by
  cases collected with
  | intro address surface genericParameters retainedParameterTypes
      retainedReturnType genericRequirements whereRequirements source
      headerMember headerMatches itemFound headerKind schemeMember declaration
      namesUnique parametersCollected schemeParameters parameters
      schemeParameterTypes returned schemeReturnType genericBounds whereBounds
      schemeRequirements bodyScoped bodyTyped =>
      rw [schemeParameters] at leftBound rightBound
      rw [schemeParameterTypes] at leftParameters rightParameters
      rw [schemeReturnType] at leftReturn rightReturn
      have parameterEquality :=
        parameters.substitute_eq_of_arguments leftBound rightBound
      have returnEquality := returned.substitute_eq_of_arguments
        leftBound rightBound
      rw [leftParameters, rightParameters] at parameterEquality
      rw [leftReturn, rightReturn] at returnEquality
      exact ⟨Option.some.inj parameterEquality,
        Option.some.inj returnEquality⟩

/-- A collected internal function artifact uses the exact generic declaration
    context exposed by scheme collection and one coupled body-specialization
    witness. The source occurrence is repeated only to index the specialized
    body; deterministic source-pack lookup prevents it from naming another
    function. -/
inductive CollectedFunctionLowers
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (program : Core.Program)
    (baseContext : SurfaceElaboration.Context)
    (header : Declarations.DeclarationHeader)
    (scheme : Static.FunctionScheme)
    (resolved : Static.FunctionInstance)
    (core : Core.Function) : Prop where
  | intro
      (address : Declarations.ItemAddress)
      (surface : Surface.Function)
      (bodyContext : SurfaceElaboration.Context)
      (source : header.source = .item address)
      (itemFound : pack.item? address = some (.function surface))
      (schemeCollected : CollectedFunctionScheme pack catalog baseContext
        header scheme bodyContext)
      (instanceMember : resolved ∈ baseContext.functionInstances)
      (instanceDeclaration : resolved.declaration = header.declaration)
      (specializes : FunctionSpecializes program bodyContext surface scheme
        resolved core) :
      CollectedFunctionLowers pack catalog program baseContext header scheme
        resolved core

inductive TraitMethodHeaders
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (parent : Declarations.ItemAddress) :
    Nat → List Surface.TraitMethod → List Nat → Prop where
  | nil : TraitMethodHeaders pack catalog parent index [] []
  | cons
      (header : Declarations.DeclarationHeader)
      (member : header ∈ catalog.headers)
      (source : header.source = .traitMethod parent index)
      (kind : header.kind = .traitMethod)
      (headerValid : Declarations.HeaderMatches pack header)
      (tail : TraitMethodHeaders pack catalog parent (index + 1)
        surfaceTail declarationTail) :
      TraitMethodHeaders pack catalog parent index (surfaceHead :: surfaceTail)
        (header.declaration :: declarationTail)

inductive TraitMethodParametersRetain (context : SurfaceElaboration.Context) :
    List Surface.Parameter → List Static.TraitMethodParameter → Prop where
  | nil : TraitMethodParametersRetain context [] []
  | named
      (type : TypeRetains context surfaceType retainedType)
      (tail : TraitMethodParametersRetain context surfaceTail retainedTail) :
      TraitMethodParametersRetain context (.named name surfaceType :: surfaceTail)
        (.named retainedType :: retainedTail)
  | selfValue
      (tail : TraitMethodParametersRetain context surfaceTail retainedTail) :
      TraitMethodParametersRetain context (.selfValue none :: surfaceTail)
        (.receiver .value none :: retainedTail)
  | selfValueTyped
      (type : TypeRetains context surfaceType retainedType)
      (tail : TraitMethodParametersRetain context surfaceTail retainedTail) :
      TraitMethodParametersRetain context (.selfValue (some surfaceType) :: surfaceTail)
        (.receiver .value (some retainedType) :: retainedTail)
  | selfReference
      (tail : TraitMethodParametersRetain context surfaceTail retainedTail) :
      TraitMethodParametersRetain context (.selfReference :: surfaceTail)
        (.receiver .reference none :: retainedTail)

inductive CollectedTraitScheme
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (header : Declarations.DeclarationHeader)
    (scheme : Static.TraitScheme) : Prop where
  | intro
      (address : Declarations.ItemAddress)
      (surface : Surface.TraitDecl)
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (genericRequirements whereRequirements : List Static.TraitPattern)
      (methodDeclarations : List Nat)
      (source : header.source = .item address)
      (headerMember : header ∈ catalog.headers)
      (headerMatches : Declarations.HeaderMatches pack header)
      (itemFound : pack.item? address = some (.trait surface))
      (headerKind : header.kind = .trait)
      (schemeMember : scheme ∈ context.traits)
      (declaration : scheme.declaration = header.declaration)
      (visibility : scheme.isPublic = surface.isPublic)
      (namesUnique : GenericParameterNamesUnique surface.genericParameters)
      (typeParametersOnly : GenericParametersAreTypes surface.genericParameters)
      (parametersCollected : GenericParametersLower
        (context.forModule header.moduleId) 0 0
        surface.genericParameters genericParameters finalType finalConst)
      (schemeParameters : scheme.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (genericBounds : GenericBoundsRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.genericParameters genericRequirements)
      (whereBounds : WherePredicatesRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.wherePredicates whereRequirements)
      (schemeRequirements : scheme.requirements =
        genericRequirements ++ whereRequirements)
      (methods : TraitMethodHeaders pack catalog address 0
        surface.methods methodDeclarations)
      (schemeMethods : scheme.methodDeclarations = methodDeclarations) :
      CollectedTraitScheme pack catalog context header scheme

/-- Current Lanius accepts generic syntax on trait methods during parsing but
    rejects method-local generics and method-local `where` clauses during trait
    validation.  The contract relation records that boundary explicitly. -/
inductive CollectedTraitMethodContract
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (parentHeader methodHeader : Declarations.DeclarationHeader)
    (traitScheme : Static.TraitScheme)
    (contract : Static.TraitMethodContract) : Prop where
  | intro
      (parent : Declarations.ItemAddress)
      (index : Nat)
      (surfaceTrait : Surface.TraitDecl)
      (surfaceMethod : Surface.TraitMethod)
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (retainedParameters : List Static.TraitMethodParameter)
      (retainedReturnType : Static.Ty)
      (parentSource : parentHeader.source = .item parent)
      (parentMember : parentHeader ∈ catalog.headers)
      (parentMatches : Declarations.HeaderMatches pack parentHeader)
      (parentFound : pack.item? parent = some (.trait surfaceTrait))
      (parentKind : parentHeader.kind = .trait)
      (methodSource : methodHeader.source = .traitMethod parent index)
      (methodMember : methodHeader ∈ catalog.headers)
      (methodMatches : Declarations.HeaderMatches pack methodHeader)
      (methodFound : surfaceTrait.methods[index]? = some surfaceMethod)
      (methodKind : methodHeader.kind = .traitMethod)
      (traitMember : traitScheme ∈ context.traits)
      (traitDeclaration : traitScheme.declaration = parentHeader.declaration)
      (parametersCollected : GenericParametersLower
        (context.forModule parentHeader.moduleId) 0 0
        surfaceTrait.genericParameters genericParameters finalType finalConst)
      (schemeParameters : traitScheme.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (methodGenericsUnsupported :
        surfaceMethod.signature.genericParameters = [])
      (methodWhereUnsupported : surfaceMethod.signature.wherePredicates = [])
      (parameters : TraitMethodParametersRetain
        (withGenericParameters (context.forModule parentHeader.moduleId)
          genericParameters)
        surfaceMethod.signature.parameters retainedParameters)
      (returned : ReturnTypeRetains
        (withGenericParameters (context.forModule parentHeader.moduleId)
          genericParameters)
        surfaceMethod.signature.name surfaceMethod.signature.returnType retainedReturnType)
      (contractMember : contract ∈ context.traitMethods)
      (contractTrait : contract.trait = traitScheme.trait)
      (contractDeclaration : contract.declaration = methodHeader.declaration)
      (contractName : contract.name = surfaceMethod.signature.name)
      (contractVisibility : contract.isPublic = surfaceMethod.signature.isPublic)
      (contractParameters : contract.parameters = retainedParameters)
      (contractReturnType : contract.returnType = retainedReturnType) :
      CollectedTraitMethodContract pack catalog context parentHeader methodHeader
        traitScheme contract

inductive ImplTraitRetains (context : SurfaceElaboration.Context)
    (receiver : Static.Ty) :
    Option Surface.TypeExpr → Option Static.TraitPattern →
      Option Static.TraitScheme → Prop where
  | inherent : ImplTraitRetains context receiver none none none
  | trait
      (selected : SelectsTrait context { segments } trait)
      (argumentsFound : SurfaceElaboration.pathTypeArguments? { segments } =
        some surfaceArguments)
      (arguments : TypesRetain context surfaceArguments retainedArguments) :
      ImplTraitRetains context receiver (some (.path segments))
        (some { trait := trait.trait, receiver, arguments := retainedArguments })
        (some trait)

inductive ImplementationMethodHeaders
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (parent : Declarations.ItemAddress) :
    Nat → List Surface.Function → List Nat → Prop where
  | nil : ImplementationMethodHeaders pack catalog parent index [] []
  | cons
      (header : Declarations.DeclarationHeader)
      (member : header ∈ catalog.headers)
      (source : header.source = .implementationMethod parent index)
      (kind : header.kind = .implementationMethod)
      (headerValid : Declarations.HeaderMatches pack header)
      (tail : ImplementationMethodHeaders pack catalog parent (index + 1)
        surfaceTail declarationTail) :
      ImplementationMethodHeaders pack catalog parent index
        (surfaceHead :: surfaceTail) (header.declaration :: declarationTail)

inductive CollectedImplScheme
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (header : Declarations.DeclarationHeader)
    (scheme : Static.ImplScheme) : Prop where
  | intro
      (address : Declarations.ItemAddress)
      (surface : Surface.ImplDecl)
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (receiver : Static.Ty)
      (implementedTrait : Option Static.TraitPattern)
      (selectedTrait : Option Static.TraitScheme)
      (genericRequirements whereRequirements : List Static.TraitPattern)
      (methodDeclarations : List Nat)
      (source : header.source = .item address)
      (headerMember : header ∈ catalog.headers)
      (headerMatches : Declarations.HeaderMatches pack header)
      (itemFound : pack.item? address = some (.implementation surface))
      (headerKind : header.kind = .implementation)
      (schemeMember : scheme ∈ context.implementations)
      (declaration : scheme.declaration = header.declaration)
      (visibility : scheme.isPublic = surface.isPublic)
      (namesUnique : GenericParameterNamesUnique surface.genericParameters)
      (parametersCollected : GenericParametersLower
        (context.forModule header.moduleId) 0 0
        surface.genericParameters genericParameters finalType finalConst)
      (schemeParameters : scheme.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (receiverType : TypeRetains
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.receiverType receiver)
      (schemeReceiver : scheme.receiver = receiver)
      (traitType : ImplTraitRetains
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        receiver surface.traitType implementedTrait selectedTrait)
      (schemeTrait : scheme.implementedTrait = implementedTrait)
      (genericBounds : GenericBoundsRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.genericParameters genericRequirements)
      (whereBounds : WherePredicatesRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.wherePredicates whereRequirements)
      (schemeRequirements : scheme.requirements =
        genericRequirements ++ whereRequirements)
      (traitVisibility : match selectedTrait with
        | none => True
        | some trait => Static.TraitImplVisibilityMatches trait scheme)
      (methods : ImplementationMethodHeaders pack catalog address 0
        surface.methods methodDeclarations)
      (schemeMethods : scheme.methodDeclarations = methodDeclarations) :
      CollectedImplScheme pack catalog context header scheme

/-- An implementation receiver depends only on the implementation's declared
    generic parameters. Agreement on that domain makes receiver substitution
    functional even when a caller carries additional method-local bindings. -/
theorem CollectedImplScheme.receiver_substitute_eq_of_parameter_agreement
    (collected : CollectedImplScheme pack catalog context header scheme)
    (typeAgreement : ∀ parameter,
      .typeParameter parameter ∈ scheme.genericParameters →
        leftSubstitution.types parameter = rightSubstitution.types parameter)
    (constAgreement : ∀ parameter,
      .constParameter parameter ∈ scheme.genericParameters →
        leftSubstitution.constants parameter =
          rightSubstitution.constants parameter) :
    scheme.receiver.substitute leftSubstitution =
      scheme.receiver.substitute rightSubstitution := by
  cases collected with
  | intro address surface genericParameters receiver implementedTrait
      selectedTrait genericRequirements whereRequirements methodDeclarations
      source headerMember headerMatches itemFound headerKind schemeMember
      declaration visibility namesUnique parametersCollected schemeParameters
      receiverType schemeReceiver traitType schemeTrait genericBounds
      whereBounds schemeRequirements traitVisibility methods schemeMethods =>
      rw [schemeReceiver]
      exact receiverType.substitute_eq_of_parameter_agreement
        (fun parameter member => typeAgreement parameter (by
          rw [schemeParameters]
          exact member))
        (fun parameter member => constAgreement parameter (by
          rw [schemeParameters]
          exact member))

inductive ImplementationMethodParametersRetain
    (context : SurfaceElaboration.Context) (receiver : Static.Ty) :
    List Surface.Parameter → List Static.Ty → Prop where
  | nil : ImplementationMethodParametersRetain context receiver [] []
  | named
      (type : TypeRetains context surfaceType retainedType)
      (tail : ImplementationMethodParametersRetain context receiver
        surfaceTail retainedTail) :
      ImplementationMethodParametersRetain context receiver
        (.named name surfaceType :: surfaceTail) (retainedType :: retainedTail)
  | selfValue
      (tail : ImplementationMethodParametersRetain context receiver
        surfaceTail retainedTail) :
      ImplementationMethodParametersRetain context receiver
        (.selfValue none :: surfaceTail) (receiver :: retainedTail)
  | selfValueTyped
      (type : TypeRetains context surfaceType receiver)
      (tail : ImplementationMethodParametersRetain context receiver
        surfaceTail retainedTail) :
      ImplementationMethodParametersRetain context receiver
        (.selfValue (some surfaceType) :: surfaceTail) (receiver :: retainedTail)
  | selfReference
      (tail : ImplementationMethodParametersRetain context receiver
        surfaceTail retainedTail) :
      ImplementationMethodParametersRetain context receiver
        (.selfReference :: surfaceTail) (.reference receiver :: retainedTail)

def SelectsTraitMethodContract
    (context : SurfaceElaboration.Context)
    (trait : Static.TraitScheme)
    (pattern : Static.TraitPattern)
    (name : Surface.Name)
    (parameterTypes : List Static.Ty)
    (returnType : Static.Ty)
    (selected : Static.TraitMethodContract) : Prop :=
  selected ∈ context.traitMethods ∧
    selected.trait = trait.trait ∧
    selected.name = name ∧
    Static.TraitMethodContractSpecializes trait pattern selected
      parameterTypes returnType ∧
    ∀ candidate,
      candidate ∈ context.traitMethods →
      candidate.trait = trait.trait →
      candidate.name = name →
      Static.TraitMethodContractSpecializes trait pattern candidate
        parameterTypes returnType →
      candidate.declaration = selected.declaration

inductive CollectedTraitImplementationMethodConforms
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (parentHeader methodHeader : Declarations.DeclarationHeader)
    (implementation : Static.ImplScheme)
    (contract : Static.TraitMethodContract) :
    SurfaceElaboration.Context → List Static.Ty → Static.Ty → Prop where
  | intro
      (parent : Declarations.ItemAddress)
      (index : Nat)
      (surfaceImpl : Surface.ImplDecl)
      (surfaceMethod : Surface.Function)
      (implParameters : List SurfaceElaboration.TypeAliasParameter)
      (pattern : Static.TraitPattern)
      (trait : Static.TraitScheme)
      (parameterTypes : List Static.Ty)
      (returnType : Static.Ty)
      (parentSource : parentHeader.source = .item parent)
      (parentFound : pack.item? parent = some (.implementation surfaceImpl))
      (implementationCollected : CollectedImplScheme pack catalog context
        parentHeader implementation)
      (implements : implementation.implementedTrait = some pattern)
      (traitMember : trait ∈ context.traits)
      (traitIdentity : trait.trait = pattern.trait)
      (methodSource : methodHeader.source = .implementationMethod parent index)
      (methodMember : methodHeader ∈ catalog.headers)
      (methodMatches : Declarations.HeaderMatches pack methodHeader)
      (methodFound : surfaceImpl.methods[index]? = some surfaceMethod)
      (methodKind : methodHeader.kind = .implementationMethod)
      (implParametersCollected : GenericParametersLower
        (context.forModule parentHeader.moduleId) 0 0
        surfaceImpl.genericParameters implParameters finalType finalConst)
      (implementationParameters : implementation.genericParameters =
        implParameters.map aliasParameterToStatic)
      (methodGenericsUnsupported : surfaceMethod.genericParameters = [])
      (methodWhereUnsupported : surfaceMethod.wherePredicates = [])
      (parameters : ImplementationMethodParametersRetain
        (withGenericParameters (context.forModule parentHeader.moduleId) implParameters)
        implementation.receiver
        surfaceMethod.parameters parameterTypes)
      (returned : ReturnTypeRetains
        (withGenericParameters (context.forModule parentHeader.moduleId) implParameters)
        surfaceMethod.name surfaceMethod.returnType returnType)
      (selected : SelectsTraitMethodContract context trait pattern
        surfaceMethod.name parameterTypes returnType contract)
      (visibility : contract.isPublic = surfaceMethod.isPublic)
      (bodyScoped : SourceWellFormed.FunctionBodyWellScoped
        (context.forModule parentHeader.moduleId)
        surfaceMethod.parameters surfaceMethod.body)
      (bodyTyped : FunctionBodySymbolicallyTyped
        (withGenericParameters (context.forModule parentHeader.moduleId)
          implParameters)
        implementation.requirements surfaceMethod.parameters parameterTypes
        returnType surfaceMethod.body) :
      CollectedTraitImplementationMethodConforms pack catalog context
        parentHeader methodHeader implementation contract
        (withGenericParameters (context.forModule parentHeader.moduleId)
          implParameters) parameterTypes returnType

def TraitImplementationConforms
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (parentHeader : Declarations.DeclarationHeader)
    (implementation : Static.ImplScheme) : Prop :=
  (∀ methodHeader, methodHeader ∈ catalog.headers →
    ∀ parent index,
      methodHeader.source = .implementationMethod parent index →
      parentHeader.source = .item parent →
      ∃ contract bodyContext parameterTypes returnType,
        CollectedTraitImplementationMethodConforms pack catalog context
          parentHeader methodHeader implementation contract bodyContext
          parameterTypes returnType) ∧
  ∀ pattern trait contract,
    implementation.implementedTrait = some pattern →
    trait ∈ context.traits → trait.trait = pattern.trait →
    contract ∈ context.traitMethods → contract.trait = trait.trait →
    contract.declaration ∈ trait.methodDeclarations →
    ∃ methodHeader bodyContext parameterTypes returnType,
      methodHeader ∈ catalog.headers ∧
      CollectedTraitImplementationMethodConforms pack catalog context
        parentHeader methodHeader implementation contract bodyContext
        parameterTypes returnType

/-- A demanded trait-implementation method body specializes the exact symbolic
    parameter and return types selected by trait-contract conformance. The
    ground implementation goal, parameter allocation, statement tree, and
    emitted function are retained in the same derivation. -/
inductive TraitImplementationMethodSpecializes
    (program : Core.Program)
    (baseContext : SurfaceElaboration.Context)
    (surface : Surface.Function)
    (implementation : Static.ImplScheme)
    (methodHeader : Declarations.DeclarationHeader)
    (symbolicParameterTypes : List Static.Ty)
    (symbolicReturnType : Static.Ty)
    (resolved : Static.TraitImplementationMethodInstance)
    (core : Core.Function) : Prop where
  | intro
      (substitution : Static.Substitution)
      (pattern : Static.TraitPattern)
      (goal : Static.TraitGoal)
      (parametersBound : Static.ParametersBound substitution
        implementation.genericParameters)
      (implements : implementation.implementedTrait = some pattern)
      (goalInstantiated : pattern.instantiate substitution = some goal)
      (requirements : Static.RequirementsSatisfied baseContext.implementations
        substitution implementation.requirements)
      (instanceMember : resolved ∈
        baseContext.traitImplementationMethodInstances)
      (instanceImplementation : resolved.implementation = implementation.id)
      (instanceDeclaration : resolved.declaration = methodHeader.declaration)
      (symbolicBindings : List SymbolicLocalBinding)
      (symbolicParameters : SymbolicParametersBind surface.parameters
        symbolicParameterTypes symbolicBindings)
      (initialContexts : ({
          globals := baseContext
          assumptions := implementation.requirements
          returnType := symbolicReturnType
          locals := []
        } : SymbolicBodyContext).Specializes substitution resolved.returnType
          { baseContext with substitution })
      (parameterTypesGround : Static.instantiateTypes substitution
        symbolicParameterTypes = some resolved.parameterTypes)
      (coreParameters : List (VarId × Core.Ty))
      (bodyContext : SurfaceElaboration.Context)
      (nextLocal : VarId)
      (parameters : ParametersLower { baseContext with substitution }
        (some goal.receiver) 0 surface.parameters resolved.parameterTypes
        coreParameters bodyContext nextLocal)
      (returnRetained : ReturnTypeRetains baseContext surface.name
        surface.returnType symbolicReturnType)
      (coreReturnType : Core.Ty)
      (returnTypeCore : resolved.returnType.toCore baseContext.monomorphization =
        some coreReturnType)
      (coreBody : Core.Stmt)
      (finalLocal : VarId)
      (body : StmtsSpecialize substitution resolved.returnType {
          globals := baseContext
          assumptions := implementation.requirements
          returnType := symbolicReturnType
          locals := symbolicBindings
        } bodyContext nextLocal false surface.body coreBody finalLocal)
      (definition : core = {
        id := resolved.function
        parameters := coreParameters
        returnType := coreReturnType
        body := some coreBody
      })
      (target : program.target = baseContext.target)
      (member : core ∈ program.functions)
      (typed : Typing.FunctionWellTyped program core) :
      TraitImplementationMethodSpecializes program baseContext surface
        implementation methodHeader symbolicParameterTypes symbolicReturnType
        resolved core

theorem TraitImplementationMethodSpecializes.symbolic
    (specialized : TraitImplementationMethodSpecializes program baseContext
      surface implementation methodHeader symbolicParameterTypes
      symbolicReturnType resolved core) :
    FunctionBodySymbolicallyTyped baseContext implementation.requirements
      surface.parameters symbolicParameterTypes symbolicReturnType surface.body := by
  cases specialized with
  | intro substitution pattern goal parametersBound implements goalInstantiated
      requirements instanceMember instanceImplementation instanceDeclaration
      symbolicBindings symbolicParameters initialContexts parameterTypesGround
      coreParameters bodyContext nextLocal parameters returnRetained
      coreReturnType returnTypeCore coreBody finalLocal body definition target
      member typed =>
      exact ⟨symbolicBindings, symbolicParameters, body.symbolic⟩

theorem TraitImplementationMethodSpecializes.instanceTypes
    (specialized : TraitImplementationMethodSpecializes program baseContext
      surface implementation methodHeader symbolicParameterTypes
      symbolicReturnType resolved core) :
    ∃ substitution,
      Static.instantiateTypes substitution symbolicParameterTypes =
        some resolved.parameterTypes ∧
      symbolicReturnType.instantiate substitution = some resolved.returnType := by
  cases specialized with
  | intro substitution pattern goal parametersBound implements goalInstantiated
      requirements instanceMember instanceImplementation instanceDeclaration
      symbolicBindings symbolicParameters initialContexts parameterTypesGround
      coreParameters bodyContext nextLocal parameters returnRetained
      coreReturnType returnTypeCore coreBody finalLocal body definition target
      member typed =>
      exact ⟨substitution, parameterTypesGround, initialContexts.returnType⟩

theorem TraitImplementationMethodSpecializes.parameterContexts
    (specialized : TraitImplementationMethodSpecializes program baseContext
      surface implementation methodHeader symbolicParameterTypes
      symbolicReturnType resolved core) :
    ∃ substitution symbolicBindings bodyContext,
      ({
        globals := baseContext
        assumptions := implementation.requirements
        returnType := symbolicReturnType
        locals := symbolicBindings
      } : SymbolicBodyContext).Specializes substitution resolved.returnType
        bodyContext := by
  cases specialized with
  | intro substitution pattern goal parametersBound implements goalInstantiated
      requirements instanceMember instanceImplementation instanceDeclaration
      actualBindings symbolicParameters initialContexts parameterTypesGround
      coreParameters bodyContext nextLocal parameters returnRetained
      coreReturnType returnTypeCore coreBody finalLocal body definition target
      member typed =>
      have parameterContexts := symbolicParameters.specializes initialContexts
        parameterTypesGround parameters
      have baseLocals : baseContext.locals = [] :=
        initialContexts.locals.concrete_eq_nil
      exact ⟨substitution, actualBindings, bodyContext, by
        simpa [SymbolicBodyContext.bindMany_eq, baseLocals] using
          parameterContexts⟩

/-- Complete trait-method artifacts retain both source-contract conformance and
    the coupled specialization of that exact source occurrence. -/
inductive TraitImplementationMethodFunctionLowers
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (program : Core.Program)
    (baseContext : SurfaceElaboration.Context)
    (parentHeader methodHeader : Declarations.DeclarationHeader)
    (implementation : Static.ImplScheme)
    (contract : Static.TraitMethodContract)
    (resolved : Static.TraitImplementationMethodInstance)
    (core : Core.Function) : Prop where
  | intro
      (parent : Declarations.ItemAddress)
      (index : Nat)
      (surfaceImpl : Surface.ImplDecl)
      (surfaceMethod : Surface.Function)
      (symbolicContext : SurfaceElaboration.Context)
      (symbolicParameterTypes : List Static.Ty)
      (symbolicReturnType : Static.Ty)
      (parentSource : parentHeader.source = .item parent)
      (parentFound : pack.item? parent = some (.implementation surfaceImpl))
      (methodSource : methodHeader.source = .implementationMethod parent index)
      (methodFound : surfaceImpl.methods[index]? = some surfaceMethod)
      (conforms : CollectedTraitImplementationMethodConforms pack catalog
        baseContext parentHeader methodHeader implementation contract
        symbolicContext symbolicParameterTypes symbolicReturnType)
      (specializes : TraitImplementationMethodSpecializes program symbolicContext
        surfaceMethod implementation methodHeader symbolicParameterTypes
        symbolicReturnType resolved core) :
      TraitImplementationMethodFunctionLowers pack catalog program baseContext
        parentHeader methodHeader implementation contract resolved core

/-- Classify an inherent implementation function after type retention. A
    receiverless function, or a function whose ordinary first parameter is not
    the implementation receiver, is associated-only. `self`, `&self`, and an
    ordinary first parameter equal to the receiver retain the three callable
    receiver modes used by member and associated lookup. -/
inductive InherentMethodParametersRetain
    (context : SurfaceElaboration.Context) (receiver : Static.Ty) :
    List Surface.Parameter → Static.ReceiverMode → List Static.Ty → Prop where
  | named
      (receiverType : TypeRetains context surfaceReceiver receiver)
      (tail : ParameterTypesRetain context surfaceTail retainedTail) :
      InherentMethodParametersRetain context receiver
        (.named receiverName surfaceReceiver :: surfaceTail) .explicit retainedTail
  | associatedNil :
      InherentMethodParametersRetain context receiver [] .none []
  | associatedNamed
      (notReceiver : ¬ TypeRetains context surfaceFirst receiver)
      (first : TypeRetains context surfaceFirst retainedFirst)
      (tail : ParameterTypesRetain context surfaceTail retainedTail) :
      InherentMethodParametersRetain context receiver
        (.named firstName surfaceFirst :: surfaceTail) .none
        (retainedFirst :: retainedTail)
  | selfValue
      (tail : ParameterTypesRetain context surfaceTail retainedTail) :
      InherentMethodParametersRetain context receiver
        (.selfValue none :: surfaceTail) .value retainedTail
  | selfValueTyped
      (receiverType : TypeRetains context surfaceReceiver receiver)
      (tail : ParameterTypesRetain context surfaceTail retainedTail) :
      InherentMethodParametersRetain context receiver
        (.selfValue (some surfaceReceiver) :: surfaceTail) .value retainedTail
  | selfReference
      (tail : ParameterTypesRetain context surfaceTail retainedTail) :
      InherentMethodParametersRetain context receiver
        (.selfReference :: surfaceTail) .reference retainedTail

/-- Receiver syntax does not enter the ordinary argument vector. Every
    retained non-receiver method parameter therefore inherits declaration-
    domain substitution functionality from `ParameterTypesRetain`. -/
theorem InherentMethodParametersRetain.arguments_substitute_eq_of_arguments
    (retained : InherentMethodParametersRetain
      (withGenericParameters baseContext declaredParameters) receiver
      surfaceParameters receiverMode argumentTypes)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      (declaredParameters.map aliasParameterToStatic)
      typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      (declaredParameters.map aliasParameterToStatic)
      typeArguments constArguments) :
    Static.substituteTypes leftSubstitution argumentTypes =
      Static.substituteTypes rightSubstitution argumentTypes := by
  cases retained with
  | named _ tail => exact tail.substitute_eq_of_arguments leftBound rightBound
  | associatedNil => rfl
  | associatedNamed _ first tail =>
      simp [Static.substituteTypes,
        first.substitute_eq_of_arguments leftBound rightBound,
        tail.substitute_eq_of_arguments leftBound rightBound]
  | selfValue tail => exact tail.substitute_eq_of_arguments leftBound rightBound
  | selfValueTyped _ tail =>
      exact tail.substitute_eq_of_arguments leftBound rightBound
  | selfReference tail =>
      exact tail.substitute_eq_of_arguments leftBound rightBound

inductive CollectedInherentMethodScheme
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (parentHeader methodHeader : Declarations.DeclarationHeader)
    (implementation : Static.ImplScheme)
    (scheme : Static.MethodScheme) :
    SurfaceElaboration.Context → Prop where
  | intro
      (parent : Declarations.ItemAddress)
      (index : Nat)
      (surfaceImpl : Surface.ImplDecl)
      (surfaceMethod : Surface.Function)
      (implParameters : List SurfaceElaboration.TypeAliasParameter)
      (receiverMode : Static.ReceiverMode)
      (argumentTypes : List Static.Ty)
      (returnType : Static.Ty)
      (parentSource : parentHeader.source = .item parent)
      (parentMember : parentHeader ∈ catalog.headers)
      (parentMatches : Declarations.HeaderMatches pack parentHeader)
      (parentFound : pack.item? parent = some (.implementation surfaceImpl))
      (parentKind : parentHeader.kind = .implementation)
      (implementationCollected : CollectedImplScheme pack catalog context
        parentHeader implementation)
      (inherent : implementation.implementedTrait = none)
      (methodSource : methodHeader.source = .implementationMethod parent index)
      (methodMember : methodHeader ∈ catalog.headers)
      (methodMatches : Declarations.HeaderMatches pack methodHeader)
      (methodFound : surfaceImpl.methods[index]? = some surfaceMethod)
      (methodKind : methodHeader.kind = .implementationMethod)
      (implParametersCollected : GenericParametersLower
        (context.forModule parentHeader.moduleId) 0 0
        surfaceImpl.genericParameters implParameters implFinalType implFinalConst)
      (implementationParameters : implementation.genericParameters =
        implParameters.map aliasParameterToStatic)
      (methodGenericsUnsupported : surfaceMethod.genericParameters = [])
      (methodWhereUnsupported : surfaceMethod.wherePredicates = [])
      (parameters : InherentMethodParametersRetain
        (withGenericParameters (context.forModule parentHeader.moduleId)
          implParameters)
        implementation.receiver surfaceMethod.parameters receiverMode argumentTypes)
      (returned : ReturnTypeRetains
        (withGenericParameters (context.forModule parentHeader.moduleId)
          implParameters)
        surfaceMethod.name surfaceMethod.returnType returnType)
      (schemeMember : scheme ∈ context.methods)
      (schemeName : scheme.name = surfaceMethod.name)
      (schemeDeclaration : scheme.declaration = methodHeader.declaration)
      (schemeModule : scheme.moduleId = parentHeader.moduleId)
      (schemeVisibility : scheme.isPublic = surfaceMethod.isPublic)
      (schemeReceiverMode : scheme.receiverMode = receiverMode)
      (schemeReceiver : scheme.receiverType = implementation.receiver)
      (schemeArguments : scheme.argumentTypes = argumentTypes)
      (schemeReturn : scheme.returnType = returnType)
      (schemeParameters : scheme.genericParameters = implementation.genericParameters)
      (schemeRequirements : scheme.requirements = implementation.requirements)
      (bodyScoped : SourceWellFormed.FunctionBodyWellScoped
        (context.forModule parentHeader.moduleId)
        surfaceMethod.parameters surfaceMethod.body)
      (bodyTyped : FunctionBodySymbolicallyTyped
        (withGenericParameters (context.forModule parentHeader.moduleId)
          implParameters)
        scheme.requirements surfaceMethod.parameters
        (symbolicMethodParameterTypes scheme) scheme.returnType
        surfaceMethod.body) :
      CollectedInherentMethodScheme pack catalog context parentHeader methodHeader
        implementation scheme
        (withGenericParameters (context.forModule parentHeader.moduleId)
          implParameters)

/-- Every accepted inherent method is traced back to source syntax whose
    method-local generic and `where` lists are empty. Enclosing implementation
    generics are unaffected. -/
theorem CollectedInherentMethodScheme.source_restrictions
    (collected : CollectedInherentMethodScheme pack catalog context parentHeader
      methodHeader implementation scheme bodyContext) :
    ∃ parent index surfaceImpl surfaceMethod,
      parentHeader.source = .item parent ∧
      pack.item? parent = some (.implementation surfaceImpl) ∧
      methodHeader.source = .implementationMethod parent index ∧
      surfaceImpl.methods[index]? = some surfaceMethod ∧
      surfaceMethod.genericParameters = [] ∧
      surfaceMethod.wherePredicates = [] := by
  cases collected with
  | intro parent index surfaceImpl surfaceMethod implParameters
      receiverMode argumentTypes returnType parentSource parentMember parentMatches
      parentFound parentKind implementationCollected inherent methodSource
      methodMember methodMatches methodFound methodKind implParametersCollected
      implementationParameters methodGenericsUnsupported methodWhereUnsupported
      parameters returned schemeMember schemeName schemeDeclaration schemeModule
      schemeVisibility schemeReceiverMode schemeReceiver schemeArguments schemeReturn
      schemeParameters schemeRequirements bodyScoped bodyTyped =>
      exact ⟨parent, index, surfaceImpl, surfaceMethod, parentSource, parentFound,
        methodSource, methodFound, methodGenericsUnsupported,
        methodWhereUnsupported⟩

/-- A collected inherent method signature observes only the implementation's
    ordered generic argument vector. The current compiler parses but rejects
    method-local generic parameters and predicates. -/
theorem CollectedInherentMethodScheme.signature_substitute_unique
    (collected : CollectedInherentMethodScheme pack catalog context parentHeader
      methodHeader implementation scheme bodyContext)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      scheme.genericParameters typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      scheme.genericParameters typeArguments constArguments)
    (leftReceiver : scheme.receiverType.substitute leftSubstitution =
      some leftReceiverType)
    (rightReceiver : scheme.receiverType.substitute rightSubstitution =
      some rightReceiverType)
    (leftArguments : Static.substituteTypes leftSubstitution
      scheme.argumentTypes = some leftArgumentTypes)
    (rightArguments : Static.substituteTypes rightSubstitution
      scheme.argumentTypes = some rightArgumentTypes)
    (leftReturn : scheme.returnType.substitute leftSubstitution =
      some leftReturnType)
    (rightReturn : scheme.returnType.substitute rightSubstitution =
      some rightReturnType) :
    leftReceiverType = rightReceiverType ∧
      leftArgumentTypes = rightArgumentTypes ∧
      leftReturnType = rightReturnType := by
  cases collected with
  | intro parent index surfaceImpl surfaceMethod implParameters
      receiverMode argumentTypes returnType parentSource parentMember parentMatches parentFound
      parentKind implementationCollected inherent methodSource methodMember
      methodMatches methodFound methodKind implParametersCollected
      implementationParameters methodGenericsUnsupported methodWhereUnsupported
      parameters returned
      schemeMember schemeName schemeDeclaration schemeModule schemeVisibility
      schemeReceiverMode schemeReceiver schemeArguments schemeReturn
      schemeParameters schemeRequirements bodyScoped bodyTyped =>
      have receiverEquality :=
        implementationCollected.receiver_substitute_eq_of_parameter_agreement
          (fun parameter member => leftBound.type_agrees rightBound (by
            rw [schemeParameters]
            exact member))
          (fun parameter member => leftBound.const_agrees rightBound (by
            rw [schemeParameters]
            exact member))
      rw [schemeReceiver] at leftReceiver rightReceiver
      rw [leftReceiver, rightReceiver] at receiverEquality
      have concreteReceiverEquality := Option.some.inj receiverEquality
      rw [schemeParameters, implementationParameters] at leftBound rightBound
      rw [schemeArguments] at leftArguments rightArguments
      rw [schemeReturn] at leftReturn rightReturn
      have argumentEquality :=
        parameters.arguments_substitute_eq_of_arguments leftBound rightBound
      have returnEquality :=
        returned.substitute_eq_of_arguments leftBound rightBound
      rw [leftArguments, rightArguments] at argumentEquality
      rw [leftReturn, rightReturn] at returnEquality
      exact ⟨concreteReceiverEquality, Option.some.inj argumentEquality,
        Option.some.inj returnEquality⟩

def methodGroundParameterTypes (resolved : Static.MethodInstance) :
    List Static.GroundTy :=
  match resolved.receiverMode with
  | .none => resolved.argumentTypes
  | .value | .explicit => resolved.receiverType :: resolved.argumentTypes
  | .reference => .reference resolved.receiverType :: resolved.argumentTypes

def methodReceiverType? (resolved : Static.MethodInstance) :
    Option Static.GroundTy :=
  match resolved.receiverMode with
  | .none => none
  | .value | .reference | .explicit => some resolved.receiverType

theorem methodInstantiationParameterTypes
    (instantiated : Static.MethodInstantiates implementations scheme substitution
      resolved) :
    Static.instantiateTypes substitution (symbolicMethodParameterTypes scheme) =
      some (methodGroundParameterTypes resolved) := by
  obtain ⟨receiverGrounds, argumentGrounds, returnGrounds, declaration,
    name, mode⟩ := instantiated.signature
  cases schemeMode : scheme.receiverMode with
  | none =>
      rw [schemeMode] at mode
      simp [symbolicMethodParameterTypes, methodGroundParameterTypes, schemeMode,
        mode, Static.instantiateTypes, argumentGrounds]
  | value =>
      rw [schemeMode] at mode
      simp [symbolicMethodParameterTypes, methodGroundParameterTypes, schemeMode,
        mode, Static.instantiateTypes, receiverGrounds, argumentGrounds]
  | reference =>
      rw [schemeMode] at mode
      simp [symbolicMethodParameterTypes, methodGroundParameterTypes, schemeMode,
        mode, Static.instantiateTypes, Static.Ty.instantiate, receiverGrounds,
        argumentGrounds]
  | explicit =>
      rw [schemeMode] at mode
      simp [symbolicMethodParameterTypes, methodGroundParameterTypes, schemeMode,
        mode, Static.instantiateTypes, receiverGrounds, argumentGrounds]

inductive MethodFunctionLowers
    (program : Core.Program)
    (baseContext : SurfaceElaboration.Context)
    (surface : Surface.Function)
    (scheme : Static.MethodScheme)
    (monomorphicInstance : Static.MethodInstance)
    (core : Core.Function) : Prop where
  | intro
      (substitution : Static.Substitution)
      (groundParameters : List Static.GroundTy)
      (coreParameters : List (VarId × Core.Ty))
      (bodyContext : SurfaceElaboration.Context)
      (nextLocal : VarId)
      (groundReturnType : Static.GroundTy)
      (coreReturnType : Core.Ty)
      (coreBody : Core.Stmt)
      (finalLocal : VarId)
      (instantiated : Static.MethodInstantiates baseContext.implementations
        scheme substitution monomorphicInstance)
      (parameters : ParametersLower { baseContext with substitution := substitution }
        (methodReceiverType? monomorphicInstance) 0 surface.parameters groundParameters
        coreParameters bodyContext nextLocal)
      (parameterTypes : groundParameters =
        methodGroundParameterTypes monomorphicInstance)
      (returned : ReturnTypeGrounds { baseContext with substitution := substitution }
        surface.name surface.returnType groundReturnType)
      (selectedReturnType : groundReturnType = monomorphicInstance.returnType)
      (returnTypeCore : groundReturnType.toCore baseContext.monomorphization =
        some coreReturnType)
      (body : SurfaceElaboration.StmtsLower bodyContext nextLocal surface.body
        coreBody finalLocal)
      (definition : core = {
        id := monomorphicInstance.function
        parameters := coreParameters
        returnType := coreReturnType
        body := some coreBody
      })
      (target : program.target = baseContext.target)
      (member : core ∈ program.functions)
      (typed : Typing.FunctionWellTyped program core) :
      MethodFunctionLowers program baseContext surface scheme monomorphicInstance core

/-- One finite inherent-method artifact specializes the exact generic body
    context collected for its declaration. Receiver adaptation, dense parameter
    allocation, symbolic typing, concrete lowering, and the emitted core row
    are therefore one derivation rather than independently chosen witnesses. -/
inductive MethodSpecializes
    (program : Core.Program)
    (baseContext : SurfaceElaboration.Context)
    (surface : Surface.Function)
    (scheme : Static.MethodScheme)
    (resolved : Static.MethodInstance)
    (core : Core.Function) : Prop where
  | intro
      (substitution : Static.Substitution)
      (instantiated : Static.MethodInstantiates baseContext.implementations
        scheme substitution resolved)
      (baseLocals : baseContext.locals = [])
      (symbolicBindings : List SymbolicLocalBinding)
      (symbolicParameters : SymbolicParametersBind surface.parameters
        (symbolicMethodParameterTypes scheme) symbolicBindings)
      (coreParameters : List (VarId × Core.Ty))
      (bodyContext : SurfaceElaboration.Context)
      (nextLocal : VarId)
      (parameters : ParametersLower { baseContext with substitution }
        (methodReceiverType? resolved) 0 surface.parameters
        (methodGroundParameterTypes resolved) coreParameters bodyContext nextLocal)
      (returnRetained : ReturnTypeRetains baseContext surface.name
        surface.returnType scheme.returnType)
      (coreReturnType : Core.Ty)
      (returnTypeCore : resolved.returnType.toCore baseContext.monomorphization =
        some coreReturnType)
      (coreBody : Core.Stmt)
      (finalLocal : VarId)
      (body : StmtsSpecialize substitution resolved.returnType {
          globals := baseContext
          assumptions := scheme.requirements
          returnType := scheme.returnType
          locals := symbolicBindings
        } bodyContext nextLocal false surface.body coreBody finalLocal)
      (definition : core = {
        id := resolved.function
        parameters := coreParameters
        returnType := coreReturnType
        body := some coreBody
      })
      (target : program.target = baseContext.target)
      (member : core ∈ program.functions)
      (typed : Typing.FunctionWellTyped program core) :
      MethodSpecializes program baseContext surface scheme resolved core

theorem MethodSpecializes.symbolic
    (specialized : MethodSpecializes program baseContext surface scheme
      resolved core) :
    FunctionBodySymbolicallyTyped baseContext scheme.requirements
      surface.parameters (symbolicMethodParameterTypes scheme)
      scheme.returnType surface.body := by
  cases specialized with
  | intro substitution instantiated baseLocals symbolicBindings symbolicParameters
      coreParameters bodyContext nextLocal parameters
      returnRetained coreReturnType returnTypeCore coreBody finalLocal body
      definition target member typed =>
      exact ⟨symbolicBindings, symbolicParameters, body.symbolic⟩

theorem MethodSpecializes.lowers
    (specialized : MethodSpecializes program baseContext surface scheme
      resolved core) :
    MethodFunctionLowers program baseContext surface scheme resolved core := by
  cases specialized with
  | intro substitution instantiated baseLocals symbolicBindings symbolicParameters
      coreParameters bodyContext nextLocal parameters
      returnRetained coreReturnType returnTypeCore coreBody finalLocal body
      definition target member typed =>
      have signature := instantiated.signature
      have initialContexts := SymbolicBodyContext.declarationSpecializes
        baseContext scheme.requirements scheme.returnType substitution
        resolved.returnType baseLocals signature.2.2.1
      apply MethodFunctionLowers.intro
          (substitution := substitution)
          (groundParameters := methodGroundParameterTypes resolved)
          (coreParameters := coreParameters)
          (bodyContext := bodyContext)
          (nextLocal := nextLocal)
          (groundReturnType := resolved.returnType)
          (coreReturnType := coreReturnType)
          (coreBody := coreBody)
          (finalLocal := finalLocal)
      · exact instantiated
      · exact parameters
      · rfl
      · exact returnRetained.specializes initialContexts signature.2.2.1
      · rfl
      · exact returnTypeCore
      · exact body.lowers
      · exact definition
      · exact target
      · exact member
      · exact typed

theorem MethodSpecializes.instanceTypes
    (specialized : MethodSpecializes program baseContext surface scheme
      resolved core) :
    ∃ substitution,
      scheme.receiverType.instantiate substitution = some resolved.receiverType ∧
      Static.instantiateTypes substitution scheme.argumentTypes =
        some resolved.argumentTypes ∧
      scheme.returnType.instantiate substitution = some resolved.returnType := by
  cases specialized with
  | intro substitution instantiated baseLocals symbolicBindings symbolicParameters
      coreParameters bodyContext nextLocal parameters
      returnRetained coreReturnType returnTypeCore coreBody finalLocal body
      definition target member typed =>
      exact ⟨substitution, instantiated.signature.1,
        instantiated.signature.2.1, instantiated.signature.2.2.1⟩

theorem MethodSpecializes.parameterContexts
    (specialized : MethodSpecializes program baseContext surface scheme
      resolved core) :
    ∃ substitution symbolicBindings bodyContext,
      ({
        globals := baseContext
        assumptions := scheme.requirements
        returnType := scheme.returnType
        locals := symbolicBindings
      } : SymbolicBodyContext).Specializes substitution resolved.returnType
        bodyContext := by
  cases specialized with
  | intro substitution instantiated baseLocals actualBindings symbolicParameters
      coreParameters bodyContext nextLocal parameters returnRetained
      coreReturnType returnTypeCore coreBody finalLocal body definition target
      member typed =>
      have signature := instantiated.signature
      have initial := SymbolicBodyContext.declarationSpecializes
        baseContext scheme.requirements scheme.returnType substitution
        resolved.returnType baseLocals signature.2.2.1
      have parameterContexts := symbolicParameters.specializes initial
        (methodInstantiationParameterTypes instantiated) parameters
      exact ⟨substitution, actualBindings, bodyContext, by
        simpa [SymbolicBodyContext.bindMany_eq, baseLocals] using
          parameterContexts⟩

inductive CollectedInherentMethodFunctionLowers
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (program : Core.Program)
    (context : SurfaceElaboration.Context)
    (parentHeader methodHeader : Declarations.DeclarationHeader)
    (implementation : Static.ImplScheme)
    (scheme : Static.MethodScheme)
    (resolved : Static.MethodInstance)
    (core : Core.Function) : Prop where
  | intro
      (parent : Declarations.ItemAddress)
      (index : Nat)
      (surfaceImpl : Surface.ImplDecl)
      (surfaceMethod : Surface.Function)
      (bodyContext : SurfaceElaboration.Context)
      (parentSource : parentHeader.source = .item parent)
      (parentFound : pack.item? parent = some (.implementation surfaceImpl))
      (methodSource : methodHeader.source = .implementationMethod parent index)
      (methodFound : surfaceImpl.methods[index]? = some surfaceMethod)
      (schemeCollected : CollectedInherentMethodScheme pack catalog context
        parentHeader methodHeader implementation scheme bodyContext)
      (instanceMember : resolved ∈ context.methodInstances)
      (instanceDeclaration : resolved.declaration = methodHeader.declaration)
      (specializes : MethodSpecializes program bodyContext surfaceMethod scheme
        resolved core) :
      CollectedInherentMethodFunctionLowers pack catalog program context
        parentHeader methodHeader implementation scheme resolved core

inductive EnumVariantHeaders
    (pack : Declarations.SourcePack) (catalog : Declarations.Catalog)
    (parent : Declarations.ItemAddress) :
    Nat → List Surface.EnumVariant → List Nat → Prop where
  | nil : EnumVariantHeaders pack catalog parent index [] []
  | cons
      (header : Declarations.DeclarationHeader)
      (member : header ∈ catalog.headers)
      (source : header.source = .enumVariant parent index)
      (kind : header.kind = .enumVariant)
      (headerValid : Declarations.HeaderMatches pack header)
      (tail : EnumVariantHeaders pack catalog parent (index + 1)
        surfaceTail declarationTail) :
      EnumVariantHeaders pack catalog parent index (surfaceHead :: surfaceTail)
        (header.declaration :: declarationTail)

def StructFieldNamesUnique (fields : List Surface.StructField) : Prop :=
  fields.Pairwise fun left right => left.name ≠ right.name

def EnumVariantNamesUnique (variants : List Surface.EnumVariant) : Prop :=
  variants.Pairwise fun left right => left.name ≠ right.name

inductive CollectedNominalScheme
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (header : Declarations.DeclarationHeader)
    (scheme : Static.NominalScheme) : Prop where
  | structureType
      (address : Declarations.ItemAddress)
      (surface : Surface.StructDecl)
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (genericRequirements whereRequirements : List Static.TraitPattern)
      (source : header.source = .item address)
      (headerMember : header ∈ catalog.headers)
      (headerMatches : Declarations.HeaderMatches pack header)
      (itemFound : pack.item? address = some (.structure surface))
      (headerKind : header.kind = .structureType)
      (schemeMember : scheme ∈ context.nominalSchemes)
      (declaration : scheme.declaration = header.declaration)
      (kind : scheme.kind = .structure)
      (visibility : scheme.isPublic = surface.isPublic)
      (namesUnique : GenericParameterNamesUnique surface.genericParameters)
      (fieldNamesUnique : StructFieldNamesUnique surface.fields)
      (parametersCollected : GenericParametersLower
        (context.forModule header.moduleId) 0 0
        surface.genericParameters genericParameters finalType finalConst)
      (schemeParameters : scheme.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (genericBounds : GenericBoundsRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.genericParameters genericRequirements)
      (whereBounds : WherePredicatesRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.wherePredicates whereRequirements)
      (schemeRequirements : scheme.requirements =
        genericRequirements ++ whereRequirements)
      (noMembers : scheme.memberDeclarations = []) :
      CollectedNominalScheme pack catalog context header scheme
  | enumeration
      (address : Declarations.ItemAddress)
      (surface : Surface.EnumDecl)
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (genericRequirements whereRequirements : List Static.TraitPattern)
      (variantDeclarations : List Nat)
      (source : header.source = .item address)
      (headerMember : header ∈ catalog.headers)
      (headerMatches : Declarations.HeaderMatches pack header)
      (itemFound : pack.item? address = some (.enumeration surface))
      (headerKind : header.kind = .enumeration)
      (schemeMember : scheme ∈ context.nominalSchemes)
      (declaration : scheme.declaration = header.declaration)
      (kind : scheme.kind = .enumeration)
      (visibility : scheme.isPublic = surface.isPublic)
      (namesUnique : GenericParameterNamesUnique surface.genericParameters)
      (variantNamesUnique : EnumVariantNamesUnique surface.variants)
      (parametersCollected : GenericParametersLower
        (context.forModule header.moduleId) 0 0
        surface.genericParameters genericParameters finalType finalConst)
      (schemeParameters : scheme.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (genericBounds : GenericBoundsRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.genericParameters genericRequirements)
      (whereBounds : WherePredicatesRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.wherePredicates whereRequirements)
      (schemeRequirements : scheme.requirements =
        genericRequirements ++ whereRequirements)
      (variants : EnumVariantHeaders pack catalog address 0
        surface.variants variantDeclarations)
      (schemeMembers : scheme.memberDeclarations = variantDeclarations) :
      CollectedNominalScheme pack catalog context header scheme

/-- A struct constructor retains declaration-level field types before
    monomorphization. Field IDs are dense and follow declaration order. -/
inductive StructFieldSchemesRetain
    (context : SurfaceElaboration.Context) :
    FieldId → List Surface.StructField →
      List SurfaceElaboration.StructFieldScheme → Prop where
  | nil : StructFieldSchemesRetain context next [] []
  | cons
      (type : TypeRetains context surfaceField.type retainedType)
      (tail : StructFieldSchemesRetain context (next + 1)
        surfaceTail retainedTail) :
      StructFieldSchemesRetain context next (surfaceField :: surfaceTail)
        ({ name := surfaceField.name, field := next, type := retainedType } ::
          retainedTail)

/-- Every retained struct-field type depends only on the owning declaration's
    ordered generic arguments. Entries outside that parameter domain cannot
    change the substituted field type. -/
theorem StructFieldSchemesRetain.field_substitute_unique
    (retained : StructFieldSchemesRetain
      (withGenericParameters baseContext declaredParameters)
      next surfaceFields retainedFields)
    (member : field ∈ retainedFields)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      (declaredParameters.map aliasParameterToStatic)
      typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      (declaredParameters.map aliasParameterToStatic)
      typeArguments constArguments)
    (leftSubstituted : field.type.substitute leftSubstitution = some leftType)
    (rightSubstituted : field.type.substitute rightSubstitution = some rightType) :
    leftType = rightType := by
  induction retained with
  | nil => simp at member
  | cons retainedType tail induction =>
      simp only [List.mem_cons] at member
      rcases member with rfl | member
      · have equality := retainedType.substitute_eq_of_arguments
          leftBound rightBound
        rw [leftSubstituted, rightSubstituted] at equality
        exact Option.some.inj equality
      · exact induction member

inductive CollectedStructConstructorScheme
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (header : Declarations.DeclarationHeader)
    (nominal : Static.NominalScheme)
    (constructor : SurfaceElaboration.StructConstructorScheme) : Prop where
  | intro
      (address : Declarations.ItemAddress)
      (surface : Surface.StructDecl)
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (retainedFields : List SurfaceElaboration.StructFieldScheme)
      (source : header.source = .item address)
      (itemFound : pack.item? address = some (.structure surface))
      (collected : CollectedNominalScheme pack catalog context header nominal)
      (parametersCollected : GenericParametersLower
        (context.forModule header.moduleId) 0 0 surface.genericParameters
        genericParameters finalType finalConst)
      (nominalParameters : nominal.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (fields : StructFieldSchemesRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        0 surface.fields retainedFields)
      (member : constructor ∈ context.structConstructors)
      (constructorDeclaration : constructor.declaration = header.declaration)
      (constructorType : constructor.sourceType = nominal.type)
      (constructorParameters : constructor.genericParameters = nominal.genericParameters)
      (constructorRequirements : constructor.requirements = nominal.requirements)
      (constructorFields : constructor.fields = retainedFields) :
      CollectedStructConstructorScheme pack catalog context header nominal constructor

/-- Collection provenance transfers retained field-type functionality to the
    compact constructor record consumed by expression elaboration. -/
theorem CollectedStructConstructorScheme.field_substitute_unique
    (collected : CollectedStructConstructorScheme pack catalog context header
      nominal constructor)
    (member : field ∈ constructor.fields)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      constructor.genericParameters typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      constructor.genericParameters typeArguments constArguments)
    (leftSubstituted : field.type.substitute leftSubstitution = some leftType)
    (rightSubstituted : field.type.substitute rightSubstitution = some rightType) :
    leftType = rightType := by
  cases collected with
  | intro address surface genericParameters retainedFields source itemFound
      nominalCollected parametersCollected nominalParameters fields
      constructorMember constructorDeclaration constructorType
      constructorParameters constructorRequirements constructorFields =>
      rw [constructorParameters, nominalParameters] at leftBound rightBound
      rw [constructorFields] at member
      exact fields.field_substitute_unique member leftBound rightBound
        leftSubstituted rightSubstituted

/-- Each enum-variant child declaration owns one symbolic constructor row.
    Payload types retain the owning enum's generic parameters. -/
inductive CollectedVariantConstructorScheme
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (parentHeader variantHeader : Declarations.DeclarationHeader)
    (nominal : Static.NominalScheme)
    (constructor : SurfaceElaboration.VariantConstructorScheme) : Prop where
  | intro
      (parent : Declarations.ItemAddress)
      (index : Nat)
      (surface : Surface.EnumDecl)
      (variant : Surface.EnumVariant)
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (retainedPayload : List Static.Ty)
      (parentSource : parentHeader.source = .item parent)
      (itemFound : pack.item? parent = some (.enumeration surface))
      (variantFound : surface.variants[index]? = some variant)
      (variantMember : variantHeader ∈ catalog.headers)
      (variantSource : variantHeader.source = .enumVariant parent index)
      (variantKind : variantHeader.kind = .enumVariant)
      (variantValid : Declarations.HeaderMatches pack variantHeader)
      (collected : CollectedNominalScheme pack catalog context parentHeader nominal)
      (parametersCollected : GenericParametersLower
        (context.forModule parentHeader.moduleId) 0 0 surface.genericParameters
        genericParameters finalType finalConst)
      (nominalParameters : nominal.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (payload : TypesRetain
        (withGenericParameters (context.forModule parentHeader.moduleId)
          genericParameters)
        variant.payload retainedPayload)
      (member : constructor ∈ context.variantConstructors)
      (constructorDeclaration : constructor.declaration = variantHeader.declaration)
      (constructorNominal : constructor.nominalDeclaration = parentHeader.declaration)
      (constructorType : constructor.sourceType = nominal.type)
      (constructorParameters : constructor.genericParameters = nominal.genericParameters)
      (constructorRequirements : constructor.requirements = nominal.requirements)
      (constructorVariant : constructor.variant = index)
      (constructorPayload : constructor.payload = retainedPayload) :
      CollectedVariantConstructorScheme pack catalog context parentHeader variantHeader
        nominal constructor

/-- A collected enum constructor exposes its child declaration occurrence and
    the declaration ID retained in the constructor metadata row. -/
theorem CollectedVariantConstructorScheme.source_declaration
    (collected : CollectedVariantConstructorScheme pack catalog context
      parentHeader variantHeader nominal constructor) :
    ∃ parent index, variantHeader.source = .enumVariant parent index ∧
      constructor.declaration = variantHeader.declaration := by
  cases collected with
  | intro parent index _surface _variant _genericParameters _retainedPayload
      _parentSource _itemFound _variantFound _variantMember variantSource
      _variantKind _variantValid _collected _parametersCollected
      _nominalParameters _payload _member constructorDeclaration
      _constructorNominal _constructorType _constructorParameters
      _constructorRequirements _constructorVariant _constructorPayload =>
      exact ⟨parent, index, variantSource, constructorDeclaration⟩

/-- A collected enum constructor's payload substitution is functional in its
    ordered receiver arguments. The proof follows payload type names back to
    the owning declaration's generic-parameter scope, so irrelevant entries in
    the two substitution maps cannot affect the result. -/
theorem CollectedVariantConstructorScheme.payload_substitute_unique
    (collected : CollectedVariantConstructorScheme pack catalog context
      parentHeader variantHeader nominal constructor)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      constructor.genericParameters typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      constructor.genericParameters typeArguments constArguments)
    (leftSubstituted : Static.substituteTypes leftSubstitution
      constructor.payload = some leftPayload)
    (rightSubstituted : Static.substituteTypes rightSubstitution
      constructor.payload = some rightPayload) :
    leftPayload = rightPayload := by
  cases collected with
  | intro parent index surface variant genericParameters retainedPayload
      collectedParentSource itemFound variantFound variantMember variantSource
      variantKind variantValid nominalCollected parametersCollected
      nominalParameters payload member constructorDeclaration constructorNominal
      constructorType constructorParameters constructorRequirements
      constructorVariant constructorPayload =>
      rw [constructorParameters, nominalParameters] at leftBound rightBound
      rw [constructorPayload] at leftSubstituted rightSubstituted
      have substitutedEquality :=
        payload.substitute_eq_of_arguments leftBound rightBound
      rw [leftSubstituted, rightSubstituted] at substitutedEquality
      exact Option.some.inj substitutedEquality

inductive StructFieldsGround
    (context : SurfaceElaboration.Context)
    (receiver : Static.GroundTy) :
    FieldId → List Surface.StructField → List Core.Ty → List FieldId → Prop where
  | nil : StructFieldsGround context receiver next [] [] []
  | cons
      (groundType : Static.GroundTy)
      (coreType : Core.Ty)
      (entry : SurfaceElaboration.FieldEntry)
      (entryMember : entry ∈ context.fields)
      (entryReceiver : entry.receiver = receiver)
      (entryName : entry.name = surfaceField.name)
      (entryId : entry.field = next)
      (entryType : entry.type = groundType)
      (type : SurfaceElaboration.TypeGrounds context surfaceField.type groundType)
      (lowered : groundType.toCore context.monomorphization = some coreType)
      (tail : StructFieldsGround context receiver (next + 1)
        surfaceTail coreTail orderTail) :
      StructFieldsGround context receiver next (surfaceField :: surfaceTail)
        (coreType :: coreTail) (next :: orderTail)

inductive MonomorphicStructLowers
    (program : Core.Program)
    (baseContext : SurfaceElaboration.Context)
    (surface : Surface.StructDecl)
    (scheme : Static.NominalScheme)
    (typeArguments : List Static.GroundTy)
    (constArguments : List Nat)
    (core : Core.StructDecl) : Prop where
  | intro
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (substitution : Static.Substitution)
      (coreTypeId : TypeId)
      (coreFields : List Core.Ty)
      (fieldOrder : List FieldId)
      (entry : SurfaceElaboration.StructEntry)
      (parametersCollected : GenericParametersLower baseContext 0 0
        surface.genericParameters genericParameters finalType finalConst)
      (schemeParameters : scheme.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (arguments : Static.NominalArgumentsBound substitution
        scheme.genericParameters typeArguments constArguments)
      (requirements : Static.RequirementsSatisfied baseContext.implementations
        substitution scheme.requirements)
      (monomorphized : (Static.GroundTy.nominal scheme.type typeArguments constArguments).toCore
        baseContext.monomorphization = some (.structure coreTypeId))
      (entryMember : entry ∈ baseContext.structures)
      (entryReceiver : entry.receiver =
        .nominal scheme.type typeArguments constArguments)
      (entryCoreType : entry.coreType = coreTypeId)
      (fields : StructFieldsGround
        (withSubstitution (withGenericParameters baseContext genericParameters) substitution)
        (.nominal scheme.type typeArguments constArguments) 0
        surface.fields coreFields fieldOrder)
      (entryOrder : entry.fieldOrder = fieldOrder)
      (definition : core = { id := coreTypeId, fields := coreFields })
      (member : core ∈ program.structures) :
      MonomorphicStructLowers program baseContext surface scheme
        typeArguments constArguments core

inductive CollectedMonomorphicStructLowers
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (program : Core.Program)
    (context : SurfaceElaboration.Context)
    (header : Declarations.DeclarationHeader)
    (scheme : Static.NominalScheme)
    (resolved : Static.NominalInstance)
    (core : Core.StructDecl) : Prop where
  | intro
      (address : Declarations.ItemAddress)
      (surface : Surface.StructDecl)
      (source : header.source = .item address)
      (itemFound : pack.item? address = some (.structure surface))
      (collected : CollectedNominalScheme pack catalog context header scheme)
      (instanceMember : resolved ∈ context.nominalInstances)
      (instanceDeclaration : resolved.declaration = header.declaration)
      (instanceSourceType : resolved.sourceType = scheme.type)
      (instanceKind : resolved.kind = .structure)
      (instanceMapped : Static.NominalInstanceMapped context.monomorphization resolved)
      (coreId : core.id = resolved.coreType)
      (lowers : MonomorphicStructLowers program (context.forModule header.moduleId)
        surface scheme
        resolved.typeArguments resolved.constArguments core) :
      CollectedMonomorphicStructLowers pack catalog program context header scheme
        resolved core

/-- Enum variants occupy a dense, declaration-local `VariantId` domain.  Each
    row is connected to the independently collected child declaration so that
    constructor lookup, payload typing, and core layout cannot disagree about
    which source variant a numeric ID denotes. -/
inductive EnumVariantsGround
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (parent : Declarations.ItemAddress)
    (context : SurfaceElaboration.Context)
    (receiver : Static.GroundTy)
    (coreType : TypeId) :
    VariantId → List Surface.EnumVariant → List (List Core.Ty) → Prop where
  | nil : EnumVariantsGround pack catalog parent context receiver coreType
      next [] []
  | cons
      (header : Declarations.DeclarationHeader)
      (entry : SurfaceElaboration.VariantEntry)
      (groundPayload : List Static.GroundTy)
      (corePayload : List Core.Ty)
      (headerMember : header ∈ catalog.headers)
      (headerSource : header.source = .enumVariant parent next)
      (headerKind : header.kind = .enumVariant)
      (headerValid : Declarations.HeaderMatches pack header)
      (entryMember : entry ∈ context.variants)
      (entryDeclaration : entry.declaration = header.declaration)
      (entryReceiver : entry.receiver = receiver)
      (entryCoreType : entry.coreType = coreType)
      (entryVariant : entry.variant = next)
      (payload : SurfaceElaboration.TypesGround context
        surfaceHead.payload groundPayload)
      (entryPayload : entry.payload = groundPayload)
      (payloadCore : Static.GroundTy.listToCore context.monomorphization
        groundPayload = some corePayload)
      (tail : EnumVariantsGround pack catalog parent context receiver coreType
        (next + 1) surfaceTail coreTail) :
      EnumVariantsGround pack catalog parent context receiver coreType next
        (surfaceHead :: surfaceTail) (corePayload :: coreTail)

inductive MonomorphicEnumLowers
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (program : Core.Program)
    (baseContext : SurfaceElaboration.Context)
    (address : Declarations.ItemAddress)
    (surface : Surface.EnumDecl)
    (scheme : Static.NominalScheme)
    (typeArguments : List Static.GroundTy)
    (constArguments : List Nat)
    (core : Core.EnumDecl) : Prop where
  | intro
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (substitution : Static.Substitution)
      (coreTypeId : TypeId)
      (coreVariants : List (List Core.Ty))
      (parametersCollected : GenericParametersLower baseContext 0 0
        surface.genericParameters genericParameters finalType finalConst)
      (schemeParameters : scheme.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (arguments : Static.NominalArgumentsBound substitution
        scheme.genericParameters typeArguments constArguments)
      (requirements : Static.RequirementsSatisfied baseContext.implementations
        substitution scheme.requirements)
      (monomorphized :
        (Static.GroundTy.nominal scheme.type typeArguments constArguments).toCore
          baseContext.monomorphization = some (.enumeration coreTypeId))
      (itemFound : pack.item? address = some (.enumeration surface))
      (variants : EnumVariantsGround pack catalog address
        (withSubstitution (withGenericParameters baseContext genericParameters)
          substitution)
        (.nominal scheme.type typeArguments constArguments) coreTypeId 0
        surface.variants coreVariants)
      (definition : core = { id := coreTypeId, variants := coreVariants })
      (member : core ∈ program.enumerations) :
      MonomorphicEnumLowers pack catalog program baseContext address surface scheme
        typeArguments constArguments core

inductive CollectedMonomorphicEnumLowers
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (program : Core.Program)
    (context : SurfaceElaboration.Context)
    (header : Declarations.DeclarationHeader)
    (scheme : Static.NominalScheme)
    (resolved : Static.NominalInstance)
    (core : Core.EnumDecl) : Prop where
  | intro
      (address : Declarations.ItemAddress)
      (surface : Surface.EnumDecl)
      (source : header.source = .item address)
      (collected : CollectedNominalScheme pack catalog context header scheme)
      (instanceMember : resolved ∈ context.nominalInstances)
      (instanceDeclaration : resolved.declaration = header.declaration)
      (instanceSourceType : resolved.sourceType = scheme.type)
      (instanceKind : resolved.kind = .enumeration)
      (instanceMapped : Static.NominalInstanceMapped context.monomorphization resolved)
      (coreId : core.id = resolved.coreType)
      (lowers : MonomorphicEnumLowers pack catalog program
        (context.forModule header.moduleId) address surface scheme
        resolved.typeArguments resolved.constArguments core) :
      CollectedMonomorphicEnumLowers pack catalog program context header scheme
        resolved core

/-- An arbitrary ABI name acquires behavior only through an explicit binding.
    Compiler-known host services additionally carry their canonical semantic
    signature, so an ABI table cannot accidentally bind (for example) `exit`
    with the parameter type of `print_i32`. -/
structure ExternalBinding where
  abi : Option String
  name : Surface.Name
  parameterTypes : List Core.Ty
  returnType : Core.Ty
  behavior : Core.ExternalBehavior
deriving DecidableEq, Repr

def ExternalBindingWellFormed (binding : ExternalBinding) : Prop :=
  match binding.behavior with
  | .host service =>
      binding.parameterTypes = service.parameterTypes ∧
        binding.returnType = service.returnType
  | .panic | .unreachable =>
      binding.parameterTypes = [] ∧ binding.returnType = .unit
  | .unavailable _ | .opaque _ => True

def SelectsExternalBinding
    (bindings : List ExternalBinding)
    (abi : Option String)
    (name : Surface.Name)
    (parameterTypes : List Core.Ty)
    (returnType : Core.Ty)
    (selected : ExternalBinding) : Prop :=
  selected ∈ bindings ∧
    selected.abi = abi ∧
    selected.name = name ∧
    selected.parameterTypes = parameterTypes ∧
    selected.returnType = returnType ∧
    ExternalBindingWellFormed selected ∧
    ∀ candidate,
      candidate ∈ bindings →
      candidate.abi = abi →
      candidate.name = name →
      candidate.parameterTypes = parameterTypes →
      candidate.returnType = returnType →
      candidate.behavior = selected.behavior

inductive CollectedExternFunctionScheme
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (header : Declarations.DeclarationHeader)
    (scheme : Static.FunctionScheme) : Prop where
  | intro
      (address : Declarations.ItemAddress)
      (surface : Surface.ExternFunction)
      (genericParameters : List SurfaceElaboration.TypeAliasParameter)
      (parameterTypes : List Static.Ty)
      (returnType : Static.Ty)
      (genericRequirements whereRequirements : List Static.TraitPattern)
      (source : header.source = .item address)
      (headerMember : header ∈ catalog.headers)
      (headerMatches : Declarations.HeaderMatches pack header)
      (itemFound : pack.item? address = some (.externFunction surface))
      (headerKind : header.kind = .externalFunction)
      (schemeMember : scheme ∈ context.functions)
      (declaration : scheme.declaration = header.declaration)
      (namesUnique : GenericParameterNamesUnique surface.genericParameters)
      (parametersCollected : GenericParametersLower
        (context.forModule header.moduleId) 0 0
        surface.genericParameters genericParameters finalType finalConst)
      (schemeParameters : scheme.genericParameters =
        genericParameters.map aliasParameterToStatic)
      (parameters : ParameterTypesRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.parameters parameterTypes)
      (schemeParameterTypes : scheme.parameterTypes = parameterTypes)
      (returned : ReturnTypeRetains
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.name surface.returnType returnType)
      (schemeReturnType : scheme.returnType = returnType)
      (genericBounds : GenericBoundsRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.genericParameters genericRequirements)
      (whereBounds : WherePredicatesRetain
        (withGenericParameters (context.forModule header.moduleId) genericParameters)
        surface.wherePredicates whereRequirements)
      (schemeRequirements : scheme.requirements =
        genericRequirements ++ whereRequirements) :
      CollectedExternFunctionScheme pack catalog context header scheme

/-- An external function uses the same declaration-occurrence provenance as
    an internal callable scheme. -/
theorem CollectedExternFunctionScheme.source_declaration
    (collected : CollectedExternFunctionScheme pack catalog context header scheme) :
    ∃ address, header.source = .item address ∧
      scheme.declaration = header.declaration := by
  cases collected with
  | intro address _surface _genericParameters _parameterTypes _returnType
      _genericRequirements _whereRequirements source _headerMember
      _headerMatches _itemFound _headerKind _schemeMember declaration
      _namesUnique _parametersCollected _schemeParameters _parameters
      _schemeParameterTypes _returned _schemeReturnType _genericBounds
      _whereBounds _schemeRequirements =>
      exact ⟨address, source, declaration⟩

theorem CollectedExternFunctionScheme.signature_substitute_unique
    (collected : CollectedExternFunctionScheme pack catalog context header scheme)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      scheme.genericParameters typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      scheme.genericParameters typeArguments constArguments)
    (leftParameters : Static.substituteTypes leftSubstitution
      scheme.parameterTypes = some leftParameterTypes)
    (rightParameters : Static.substituteTypes rightSubstitution
      scheme.parameterTypes = some rightParameterTypes)
    (leftReturn : scheme.returnType.substitute leftSubstitution =
      some leftReturnType)
    (rightReturn : scheme.returnType.substitute rightSubstitution =
      some rightReturnType) :
    leftParameterTypes = rightParameterTypes ∧
      leftReturnType = rightReturnType := by
  cases collected with
  | intro address surface genericParameters retainedParameterTypes
      retainedReturnType genericRequirements whereRequirements source
      headerMember headerMatches itemFound headerKind schemeMember declaration
      namesUnique parametersCollected schemeParameters parameters
      schemeParameterTypes returned schemeReturnType genericBounds whereBounds
      schemeRequirements =>
      rw [schemeParameters] at leftBound rightBound
      rw [schemeParameterTypes] at leftParameters rightParameters
      rw [schemeReturnType] at leftReturn rightReturn
      have parameterEquality :=
        parameters.substitute_eq_of_arguments leftBound rightBound
      have returnEquality := returned.substitute_eq_of_arguments
        leftBound rightBound
      rw [leftParameters, rightParameters] at parameterEquality
      rw [leftReturn, rightReturn] at returnEquality
      exact ⟨Option.some.inj parameterEquality,
        Option.some.inj returnEquality⟩

inductive ExternFunctionLowers
    (program : Core.Program)
    (baseContext : SurfaceElaboration.Context)
    (bindings : List ExternalBinding)
    (surface : Surface.ExternFunction)
    (scheme : Static.FunctionScheme)
    (monomorphicInstance : Static.FunctionInstance)
    (core : Core.Function) : Prop where
  | intro
      (substitution : Static.Substitution)
      (groundParameters : List Static.GroundTy)
      (coreParameters : List (VarId × Core.Ty))
      (parameterContext : SurfaceElaboration.Context)
      (nextLocal : VarId)
      (groundReturnType : Static.GroundTy)
      (coreReturnType : Core.Ty)
      (binding : ExternalBinding)
      (instantiated : Static.FunctionInstantiates baseContext.implementations
        scheme substitution monomorphicInstance)
      (declarationParameters : scheme.parameterTypes.length =
        surface.parameters.length)
      (parameters : ParametersLower { baseContext with substitution := substitution }
        none 0 surface.parameters groundParameters coreParameters parameterContext nextLocal)
      (parameterTypes : groundParameters = monomorphicInstance.parameterTypes)
      (returned : ReturnTypeGrounds { baseContext with substitution := substitution }
        surface.name surface.returnType groundReturnType)
      (selectedReturnType : groundReturnType = monomorphicInstance.returnType)
      (returnTypeCore : groundReturnType.toCore baseContext.monomorphization =
        some coreReturnType)
      (selectedBinding : SelectsExternalBinding bindings surface.abi surface.name
        (coreParameters.map Prod.snd) coreReturnType binding)
      (definition : core = {
        id := monomorphicInstance.function
        parameters := coreParameters
        returnType := coreReturnType
        body := none
        external := some binding.behavior
      })
      (target : program.target = baseContext.target)
      (member : core ∈ program.functions)
      (typed : Typing.FunctionWellTyped program core) :
      ExternFunctionLowers program baseContext bindings surface scheme
        monomorphicInstance core

inductive CollectedExternFunctionLowers
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (program : Core.Program)
    (context : SurfaceElaboration.Context)
    (bindings : List ExternalBinding)
    (header : Declarations.DeclarationHeader)
    (scheme : Static.FunctionScheme)
    (resolved : Static.FunctionInstance)
    (core : Core.Function) : Prop where
  | intro
      (address : Declarations.ItemAddress)
      (surface : Surface.ExternFunction)
      (source : header.source = .item address)
      (itemFound : pack.item? address = some (.externFunction surface))
      (schemeCollected : CollectedExternFunctionScheme pack catalog context
        header scheme)
      (instanceMember : resolved ∈ context.functionInstances)
      (instanceDeclaration : resolved.declaration = header.declaration)
      (lowers : ExternFunctionLowers program (context.forModule header.moduleId)
        bindings surface scheme resolved core) :
      CollectedExternFunctionLowers pack catalog program context bindings header
        scheme resolved core

/-- Compile-time constant expressions are deliberately smaller than ordinary
    expressions. They contain literal values, references to constants already
    admitted by dependency order, and scalar casts/operators. In particular,
    a function call is not made into a constant expression merely because one
    execution happens not to mutate the world. -/
inductive ConstantExpression : Core.Expr → Prop where
  | value : ConstantExpression (.value value)
  | constant (constantId : ConstantId) :
      ConstantExpression (.constant constantId)
  | cast
      (operand : ConstantExpression expression) :
      ConstantExpression (.cast target expression)
  | unary
      (operand : ConstantExpression expression) :
      ConstantExpression (.unary operation expression)
  | binary
      (left : ConstantExpression leftExpression)
      (right : ConstantExpression rightExpression) :
      ConstantExpression (.binary operation leftExpression rightExpression)

/-- Constant initialization is evaluated before the constant is added to the
    available program. This gives dependencies an explicit order, rejects
    self/forward cycles, restricts initializers to the compile-time expression
    language above, and requires evaluation to leave heap and world state
    unchanged. -/
inductive ConstantLowers
    (availableProgram fullProgram : Core.Program)
    (context : SurfaceElaboration.Context)
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (header : Declarations.DeclarationHeader)
    (core : Core.Constant) : Prop where
  | intro
      (address : Declarations.ItemAddress)
      (name : Surface.Name)
      (isPublic : Bool)
      (surfaceType : Surface.TypeExpr)
      (surfaceValue : Surface.Expr)
      (entry : SurfaceElaboration.ConstantEntry)
      (groundType : Static.GroundTy)
      (coreType : Core.Ty)
      (coreExpression : Core.Expr)
      (value : Core.Value)
      (fuel : Nat)
      (source : header.source = .item address)
      (headerMember : header ∈ catalog.headers)
      (headerMatches : Declarations.HeaderMatches pack header)
      (itemFound : pack.item? address =
        some (.constant name isPublic surfaceType surfaceValue))
      (headerKind : header.kind = .constant)
      (entryMember : entry ∈ context.constants)
      (entryDeclaration : entry.declaration = header.declaration)
      (notYetAvailable : availableProgram.constant? entry.constant = none)
      (type : SurfaceElaboration.TypeGrounds (context.forModule header.moduleId)
        surfaceType groundType)
      (entryType : entry.type = groundType)
      (typeCore : groundType.toCore context.monomorphization = some coreType)
      (expression : SurfaceElaboration.ExprChecks (context.forModule header.moduleId)
        surfaceValue
        groundType coreExpression)
      (constantExpression : ConstantExpression coreExpression)
      (target : availableProgram.target = context.target)
      (evaluatesPurely : Semantics.evalExpr fuel availableProgram ({} : Semantics.State)
        coreExpression = .done value {})
      (definition : core = { id := entry.constant, type := coreType, value })
      (member : core ∈ fullProgram.constants)
      (typed : Typing.ConstantWellTyped fullProgram core) :
      ConstantLowers availableProgram fullProgram context pack catalog header core

def ConstantHeaderOrderCovers
    (catalog : Declarations.Catalog)
    (order : List Declarations.DeclarationHeader) : Prop :=
  order.Pairwise (fun left right => left ≠ right) ∧
    (∀ header, header ∈ order →
      header ∈ catalog.headers ∧ header.kind = .constant) ∧
    ∀ header, header ∈ catalog.headers → header.kind = .constant →
      header ∈ order

def programWithoutConstants (program : Core.Program) : Core.Program :=
  { program with constants := [] }

def programWithAppendedConstant
    (program : Core.Program) (constant : Core.Constant) : Core.Program :=
  { program with constants := program.constants ++ [constant] }

/-- A source pack may declare constants in any file order.  `order` is a
    dependency order over the collected constant headers; each initializer is
    evaluated against exactly the constants already admitted. -/
inductive ConstantsLowerInOrder
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (fullProgram : Core.Program) :
    Core.Program → List Declarations.DeclarationHeader → Prop where
  | nil
      (complete : available.constants = fullProgram.constants) :
      ConstantsLowerInOrder pack catalog context fullProgram available []
  | cons
      (core : Core.Constant)
      (lowered : ConstantLowers available fullProgram context pack catalog header core)
      (tail : ConstantsLowerInOrder pack catalog context fullProgram
        (programWithAppendedConstant available core) headers) :
      ConstantsLowerInOrder pack catalog context fullProgram available
        (header :: headers)

def ConstantsLower
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context)
    (program : Core.Program) : Prop :=
  ∃ order,
    ConstantHeaderOrderCovers catalog order ∧
      ConstantsLowerInOrder pack catalog context program
        (programWithoutConstants program) order

def CoreProgramIdsUnique (program : Core.Program) : Prop :=
  program.functions.Pairwise (fun left right => left.id ≠ right.id) ∧
    program.structures.Pairwise (fun left right => left.id ≠ right.id) ∧
    program.enumerations.Pairwise (fun left right => left.id ≠ right.id) ∧
    program.constants.Pairwise (fun left right => left.id ≠ right.id)

/-- Completeness is bidirectional: every collected source declaration receives
    semantic metadata, and every metadata row is justified by a collected
    source declaration.  This prevents a future compiler from satisfying the
    formal interface by silently omitting a declaration or inventing one. -/
structure DeclarationCollectionComplete
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (context : SurfaceElaboration.Context) : Prop where
  functions : ∀ header, header ∈ catalog.headers → header.kind = .function →
    ∃ scheme bodyContext,
      CollectedFunctionScheme pack catalog context header scheme bodyContext
  externalFunctions : ∀ header, header ∈ catalog.headers →
    header.kind = .externalFunction →
    ∃ scheme, CollectedExternFunctionScheme pack catalog context header scheme
  functionSchemes : ∀ scheme, scheme ∈ context.functions →
    ∃ header bodyContext, header ∈ catalog.headers ∧
      (CollectedFunctionScheme pack catalog context header scheme bodyContext ∨
       CollectedExternFunctionScheme pack catalog context header scheme)
  typeAliases : ∀ header, header ∈ catalog.headers →
    header.kind = .typeAlias →
    ∃ entry, CollectedTypeAlias pack catalog context header entry
  typeAliasEntries : ∀ entry, entry ∈ context.typeAliases →
    ∃ header, header ∈ catalog.headers ∧
      CollectedTypeAlias pack catalog context header entry
  nominals : ∀ header, header ∈ catalog.headers →
    (header.kind = .structureType ∨ header.kind = .enumeration) →
    ∃ scheme, CollectedNominalScheme pack catalog context header scheme
  nominalSchemes : ∀ scheme, scheme ∈ context.nominalSchemes →
    ∃ header, header ∈ catalog.headers ∧
      CollectedNominalScheme pack catalog context header scheme
  structConstructorHeaders : ∀ header, header ∈ catalog.headers →
    header.kind = .structureType →
    ∃ nominal constructor,
      CollectedStructConstructorScheme pack catalog context header nominal constructor
  structConstructorSchemes : ∀ constructor,
    constructor ∈ context.structConstructors →
    ∃ header nominal, header ∈ catalog.headers ∧
      CollectedStructConstructorScheme pack catalog context header nominal constructor
  variantConstructorHeaders : ∀ variantHeader,
    variantHeader ∈ catalog.headers → variantHeader.kind = .enumVariant →
    ∃ parentHeader nominal constructor,
      parentHeader ∈ catalog.headers ∧
      CollectedVariantConstructorScheme pack catalog context parentHeader
        variantHeader nominal constructor
  variantConstructorSchemes : ∀ constructor,
    constructor ∈ context.variantConstructors →
    ∃ parentHeader variantHeader nominal,
      parentHeader ∈ catalog.headers ∧ variantHeader ∈ catalog.headers ∧
      CollectedVariantConstructorScheme pack catalog context parentHeader
        variantHeader nominal constructor
  traits : ∀ header, header ∈ catalog.headers → header.kind = .trait →
    ∃ scheme, CollectedTraitScheme pack catalog context header scheme
  traitSchemes : ∀ scheme, scheme ∈ context.traits →
    ∃ header, header ∈ catalog.headers ∧
      CollectedTraitScheme pack catalog context header scheme
  traitMethodHeaders : ∀ methodHeader, methodHeader ∈ catalog.headers →
    methodHeader.kind = .traitMethod →
    ∃ parentHeader trait contract,
      parentHeader ∈ catalog.headers ∧
      CollectedTraitMethodContract pack catalog context parentHeader methodHeader
        trait contract
  traitMethodContracts : ∀ contract, contract ∈ context.traitMethods →
    ∃ parentHeader methodHeader trait,
      parentHeader ∈ catalog.headers ∧ methodHeader ∈ catalog.headers ∧
      CollectedTraitMethodContract pack catalog context parentHeader methodHeader
        trait contract
  implementations : ∀ header, header ∈ catalog.headers →
    header.kind = .implementation →
    ∃ scheme, CollectedImplScheme pack catalog context header scheme ∧
      match scheme.implementedTrait with
      | none => True
      | some _ => TraitImplementationConforms pack catalog context header scheme
  implementationSchemes : ∀ scheme, scheme ∈ context.implementations →
    ∃ header, header ∈ catalog.headers ∧
      CollectedImplScheme pack catalog context header scheme
  implementationMethodHeaders : ∀ methodHeader,
    methodHeader ∈ catalog.headers →
    methodHeader.kind = .implementationMethod →
    ∃ parentHeader implementation,
      parentHeader ∈ catalog.headers ∧
      CollectedImplScheme pack catalog context parentHeader implementation ∧
      ((implementation.implementedTrait = none ∧
        ∃ scheme bodyContext, CollectedInherentMethodScheme pack catalog context
          parentHeader methodHeader implementation scheme bodyContext) ∨
       (∃ pattern contract bodyContext parameterTypes returnType,
        implementation.implementedTrait = some pattern ∧
        CollectedTraitImplementationMethodConforms pack catalog context
          parentHeader methodHeader implementation contract bodyContext
          parameterTypes returnType))
  inherentMethodSchemes : ∀ scheme, scheme ∈ context.methods →
    ∃ parentHeader methodHeader implementation bodyContext,
      parentHeader ∈ catalog.headers ∧ methodHeader ∈ catalog.headers ∧
      CollectedInherentMethodScheme pack catalog context parentHeader methodHeader
        implementation scheme bodyContext

def RowsUniqueByKey
    (rows : List α) (key : α → κ) : Prop :=
  ∀ left, left ∈ rows → ∀ right, right ∈ rows →
    key left = key right → left = right

/-- Declaration-indexed semantic tables are functions, represented as compact
    rows. Bidirectional collection proves provenance; this invariant separately
    prevents one source declaration from acquiring conflicting metadata. -/
structure DeclarationMetadataUnique
    (context : SurfaceElaboration.Context) : Prop where
  functions : RowsUniqueByKey context.functions (fun row => row.declaration)
  methods : RowsUniqueByKey context.methods (fun row => row.declaration)
  traits : RowsUniqueByKey context.traits (fun row => row.declaration)
  traitMethods : RowsUniqueByKey context.traitMethods (fun row => row.declaration)
  implementations : RowsUniqueByKey context.implementations
    (fun row => row.declaration)
  implementationIds : RowsUniqueByKey context.implementations
    (fun row => row.id)
  constants : RowsUniqueByKey context.constants (fun row => row.declaration)
  typeAliases : RowsUniqueByKey context.typeAliases (fun row => row.declaration)
  nominalSchemes : RowsUniqueByKey context.nominalSchemes
    (fun row => row.declaration)
  structConstructors : RowsUniqueByKey context.structConstructors
    (fun row => row.declaration)
  structConstructorSourceTypes : RowsUniqueByKey context.structConstructors
    (fun row => row.sourceType)
  variantConstructors : RowsUniqueByKey context.variantConstructors
    (fun row => row.declaration)

/-- Retaining one source type into a declaration scheme is functional once the
    declaration tables are known to be functional.  The proof also makes the
    specified lookup priority explicit: builtins exclude every other path
    rule, and an in-scope type parameter excludes global nominal lookup. -/
theorem TypeRetains.unique
    (metadata : DeclarationMetadataUnique context)
    (left : TypeRetains context surface leftType)
    (right : TypeRetains context surface rightType) :
    leftType = rightType := by
  apply TypeRetains.rec
    (motive_1 := fun surface retained _ =>
      ∀ other, TypeRetains context surface other → retained = other)
    (motive_2 := fun surfaces retained _ =>
      ∀ other, TypesRetain context surfaces other → retained = other)
    (motive_3 := fun surface retained _ =>
      ∀ other, ArrayLengthRetains context surface other → retained = other)
    (motive_4 := fun surface retained _ =>
      ∀ other, ConstTypeArgumentRetains context surface other →
        retained = other)
    (motive_5 := fun parameters surfaces retainedTypes retainedConstants _ =>
      ∀ otherTypes otherConstants,
        NominalArgumentsRetain context parameters surfaces otherTypes
            otherConstants →
          retainedTypes = otherTypes ∧ retainedConstants = otherConstants)
    ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ ?_ left rightType right
  · intro segments name scalar leftSingle leftFound other rightCase
    cases rightCase with
    | builtin rightSingle rightFound =>
        have nameEquality := Option.some.inj (leftSingle.symm.trans rightSingle)
        cases nameEquality
        cases Option.some.inj (leftFound.symm.trans rightFound)
        rfl
    | parameter rightSingle rightNotBuiltin rightResolved =>
        have builtin := SurfaceElaboration.builtinTypePath_eq_of_single
          leftSingle leftFound
        simp [builtin] at rightNotBuiltin
    | nominal symbol rightNotBuiltin rightNotShadowed rightResolved rightMember
        rightDeclaration rightArgumentsFound rightArguments =>
        have builtin := SurfaceElaboration.builtinTypePath_eq_of_single
          leftSingle leftFound
        simp [builtin] at rightNotBuiltin
  · intro segments name binding leftSingle leftNotBuiltin leftResolved other
      rightCase
    cases rightCase with
    | builtin rightSingle rightFound =>
        have builtin := SurfaceElaboration.builtinTypePath_eq_of_single
          rightSingle rightFound
        simp [builtin] at leftNotBuiltin
    | parameter rightSingle rightNotBuiltin rightResolved =>
        have nameEquality := Option.some.inj (leftSingle.symm.trans rightSingle)
        cases nameEquality
        cases leftResolved.unique rightResolved
        rfl
    | nominal symbol rightNotBuiltin rightNotShadowed rightResolved rightMember
        rightDeclaration rightArgumentsFound rightArguments =>
        exact (rightNotShadowed name binding leftSingle leftResolved).elim
  · intro segments scheme surfaceArguments retainedTypes retainedConstants
      leftSymbol leftNotBuiltin leftNotShadowed leftResolved leftMember
      leftDeclaration leftArgumentsFound leftArguments argumentsInduction other
      rightCase
    cases rightCase with
    | builtin rightSingle rightFound =>
        have builtin := SurfaceElaboration.builtinTypePath_eq_of_single
          rightSingle rightFound
        simp [builtin] at leftNotBuiltin
    | parameter rightSingle rightNotBuiltin rightResolved =>
        exact (leftNotShadowed _ _ rightSingle rightResolved).elim
    | @nominal _ rightScheme rightSurfaceArguments rightRetainedTypes
        rightRetainedConstants rightSymbol rightNotBuiltin rightNotShadowed
        rightResolved rightMember rightDeclaration rightArgumentsFound
        rightArguments =>
        cases leftResolved with
        | intro leftReference leftFormed leftNameResolved =>
            cases rightResolved with
            | intro rightReference rightFormed rightNameResolved =>
                have referenceEquality : leftReference = rightReference :=
                  Option.some.inj (leftFormed.symm.trans rightFormed)
                subst rightReference
                have symbolDeclarationEquality :
                    rightSymbol.declaration = leftSymbol.declaration :=
                  leftNameResolved.2 rightSymbol rightNameResolved.1 |>.2
                have schemeDeclarationEquality :
                    scheme.declaration = rightScheme.declaration :=
                  leftDeclaration.trans
                    (symbolDeclarationEquality.symm.trans
                      rightDeclaration.symm)
                have schemeEquality := metadata.nominalSchemes scheme leftMember
                  rightScheme rightMember schemeDeclarationEquality
                subst rightScheme
                have surfaceArgumentsEquality := Option.some.inj
                  (leftArgumentsFound.symm.trans rightArgumentsFound)
                subst rightSurfaceArguments
                rcases argumentsInduction _ _ rightArguments with
                  ⟨rfl, rfl⟩
                rfl
  · intro surfaceElement retainedElement surfaceLength retainedLength
      leftElement leftLength elementInduction lengthInduction other rightCase
    cases rightCase with
    | array rightElement rightLength =>
        cases elementInduction _ rightElement
        cases lengthInduction _ rightLength
        rfl
  · intro surfaceElement retainedElement leftElement elementInduction other
      rightCase
    cases rightCase with
    | slice rightElement => cases elementInduction _ rightElement; rfl
  · intro surfaceReferent retainedReferent leftReferent referentInduction
      other rightCase
    cases rightCase with
    | reference rightReferent =>
        cases referentInduction _ rightReferent
        rfl
  · intro other rightCase
    cases rightCase
    rfl
  · intro surfaceHead retainedHead surfaceTail retainedTail leftHead leftTail
      headInduction tailInduction other rightCase
    cases rightCase with
    | cons rightHead rightTail =>
        cases headInduction _ rightHead
        cases tailInduction _ rightTail
        rfl
  · intro value other rightCase
    cases rightCase
    rfl
  · intro name binding leftResolved other rightCase
    cases rightCase with
    | parameter rightResolved =>
        cases leftResolved.unique rightResolved
        rfl
  · intro segments name binding leftSingle leftResolved other rightCase
    cases rightCase with
    | parameter rightSingle rightResolved =>
        have nameEquality := Option.some.inj (leftSingle.symm.trans rightSingle)
        cases nameEquality
        cases leftResolved.unique rightResolved
        rfl
  · intro otherTypes otherConstants rightCase
    cases rightCase
    exact ⟨rfl, rfl⟩
  · intro surfaceArgument retainedArgument parameters surfaceArguments
      retainedArguments retainedConstants parameter leftArgument leftTail
      argumentInduction tailInduction otherTypes otherConstants rightCase
    cases rightCase with
    | typeParameter rightArgument rightTail =>
        cases argumentInduction _ rightArgument
        rcases tailInduction _ _ rightTail with ⟨rfl, rfl⟩
        exact ⟨rfl, rfl⟩
  · intro surfaceArgument retainedArgument parameters surfaceArguments
      retainedArguments retainedConstants parameter leftArgument leftTail
      argumentInduction tailInduction otherTypes otherConstants rightCase
    cases rightCase with
    | constParameter rightArgument rightTail =>
        cases argumentInduction _ rightArgument
        rcases tailInduction _ _ rightTail with ⟨rfl, rfl⟩
        exact ⟨rfl, rfl⟩

theorem TypesRetain.unique
    (metadata : DeclarationMetadataUnique context)
    (left : TypesRetain context surfaces leftTypes)
    (right : TypesRetain context surfaces rightTypes) :
    leftTypes = rightTypes := by
  induction surfaces generalizing leftTypes rightTypes with
  | nil => cases left; cases right; rfl
  | cons surfaceHead surfaceTail induction =>
      cases left with
      | cons leftHead leftTail =>
          cases right with
          | cons rightHead rightTail =>
              cases leftHead.unique metadata rightHead
              cases induction leftTail rightTail
              rfl

theorem ConstTypeArgumentRetains.unique
    (left : ConstTypeArgumentRetains context surface leftConstant)
    (right : ConstTypeArgumentRetains context surface rightConstant) :
    leftConstant = rightConstant := by
  cases left with
  | parameter leftSingle leftResolved =>
      cases right with
      | parameter rightSingle rightResolved =>
          have nameEquality := Option.some.inj (leftSingle.symm.trans rightSingle)
          cases nameEquality
          cases leftResolved.unique rightResolved
          rfl

/-- Explicit generic syntax fixes the ordered symbolic argument vector even
    when the two derivations use extensionally different substitution maps.
    Each source type/const argument is retained functionally, and both maps
    must bind that retained value at the declaration's parameter ID. -/
theorem GenericArgumentsRetain.orderedArguments_unique
    (metadata : DeclarationMetadataUnique context)
    (left : GenericArgumentsRetain context leftSubstitution parameters
      surfaceArguments)
    (right : GenericArgumentsRetain context rightSubstitution parameters
      surfaceArguments)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution parameters
      leftTypeArguments leftConstArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution parameters
      rightTypeArguments rightConstArguments) :
    leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments := by
  induction left generalizing rightSubstitution leftTypeArguments
      leftConstArguments rightTypeArguments rightConstArguments with
  | nil =>
      cases right
      cases leftBound
      cases rightBound
      exact ⟨rfl, rfl⟩
  | @typeParameter surfaceArgument retainedArgument tailParameters
      tailSurface parameter leftArgument leftFound leftTail induction =>
      cases right with
      | typeParameter rightArgument rightFound rightTail =>
          cases leftBound with
          | typeParameter leftBoundFound leftBoundTail =>
              cases rightBound with
              | typeParameter rightBoundFound rightBoundTail =>
                  cases TypeRetains.unique metadata leftArgument rightArgument
                  have leftHeadEquality := Option.some.inj
                    (leftFound.symm.trans leftBoundFound)
                  have rightHeadEquality := Option.some.inj
                    (rightFound.symm.trans rightBoundFound)
                  cases leftHeadEquality
                  cases rightHeadEquality
                  rcases induction rightTail leftBoundTail rightBoundTail with
                    ⟨rfl, rfl⟩
                  exact ⟨rfl, rfl⟩
  | @constParameter surfaceArgument retainedArgument tailParameters
      tailSurface parameter leftArgument leftFound leftTail induction =>
      cases right with
      | constParameter rightArgument rightFound rightTail =>
          cases leftBound with
          | constParameter leftBoundFound leftBoundTail =>
              cases rightBound with
              | constParameter rightBoundFound rightBoundTail =>
                  cases leftArgument.unique rightArgument
                  have leftHeadEquality := Option.some.inj
                    (leftFound.symm.trans leftBoundFound)
                  have rightHeadEquality := Option.some.inj
                    (rightFound.symm.trans rightBoundFound)
                  cases leftHeadEquality
                  cases rightHeadEquality
                  rcases induction rightTail leftBoundTail rightBoundTail with
                    ⟨rfl, rfl⟩
                  exact ⟨rfl, rfl⟩

theorem ExplicitGenericArgumentsRetain.orderedArguments_unique
    (metadata : DeclarationMetadataUnique context)
    (left : ExplicitGenericArgumentsRetain context path parameters
      leftSubstitution)
    (right : ExplicitGenericArgumentsRetain context path parameters
      rightSubstitution)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution parameters
      leftTypeArguments leftConstArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution parameters
      rightTypeArguments rightConstArguments) :
    leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments := by
  obtain ⟨leftHead, leftTail, leftFound, leftArguments⟩ := left
  obtain ⟨rightHead, rightTail, rightFound, rightArguments⟩ := right
  have surfaceArgumentsEquality := Option.some.inj
    (leftFound.symm.trans rightFound)
  cases surfaceArgumentsEquality
  exact leftArguments.orderedArguments_unique metadata rightArguments
    leftBound rightBound

/-- In a complete declaration table, concrete constant resolution denotes one
    metadata row. `ResolvesConstant` establishes the declaration identity;
    declaration-key uniqueness upgrades that identity to record equality. -/
theorem resolvesConstant_unique
    (metadata : DeclarationMetadataUnique context)
    (leftResolved : SurfaceElaboration.ResolvesConstant context path left)
    (rightResolved : SurfaceElaboration.ResolvesConstant context path right) :
    left = right := by
  cases leftResolved with
  | intro _leftNotShadowed leftSymbol leftNameResolved leftMember leftDeclaration =>
      cases rightResolved with
      | intro _rightNotShadowed rightSymbol rightNameResolved rightMember
          rightDeclaration =>
          cases leftNameResolved with
          | intro leftReference leftFormed leftResolved =>
              cases rightNameResolved with
              | intro rightReference rightFormed rightResolved =>
                  have referenceEquality : leftReference = rightReference :=
                    Option.some.inj (leftFormed.symm.trans rightFormed)
                  subst rightReference
                  have symbolDeclarationEquality :
                      rightSymbol.declaration = leftSymbol.declaration :=
                    leftResolved.2 rightSymbol rightResolved.1 |>.2
                  have rowDeclarationEquality :
                      left.declaration = right.declaration :=
                    leftDeclaration.trans
                      (symbolDeclarationEquality.symm.trans rightDeclaration.symm)
                  exact metadata.constants left leftMember right rightMember
                    rowDeclarationEquality

/-- In a complete declaration table, resolving one source struct path selects
    one complete constructor scheme. Name resolution fixes the declaration and
    declaration-key uniqueness fixes every retained field of the scheme. -/
theorem selectsStructConstructor_unique
    (metadata : DeclarationMetadataUnique context)
    (leftSelected : SurfaceElaboration.SelectsStructConstructor
      context path left)
    (rightSelected : SurfaceElaboration.SelectsStructConstructor
      context path right) :
    left = right := by
  rcases leftSelected with
    ⟨leftSymbol, leftResolved, leftMember, leftDeclaration, _leftUnique⟩
  rcases rightSelected with
    ⟨rightSymbol, rightResolved, rightMember, rightDeclaration, _rightUnique⟩
  cases leftResolved with
  | intro leftReference leftFormed leftNameResolved =>
      cases rightResolved with
      | intro rightReference rightFormed rightNameResolved =>
          have referenceEquality : leftReference = rightReference :=
            Option.some.inj (leftFormed.symm.trans rightFormed)
          subst rightReference
          have symbolDeclarationEquality :
              rightSymbol.declaration = leftSymbol.declaration :=
            leftNameResolved.2 rightSymbol rightNameResolved.1 |>.2
          have constructorDeclarationEquality :
              left.declaration = right.declaration :=
            leftDeclaration.trans
              (symbolDeclarationEquality.symm.trans rightDeclaration.symm)
          exact metadata.structConstructors left leftMember right rightMember
            constructorDeclarationEquality

/-- In a complete declaration table, resolving one source variant path selects
    one complete constructor record. Name resolution already forces all
    candidates to denote one declaration; declaration-key uniqueness upgrades
    that identity agreement to record equality. -/
theorem selectsVariantConstructor_unique
    (metadata : DeclarationMetadataUnique context)
    (leftSelected : SurfaceElaboration.SelectsVariantConstructor
      context path left)
    (rightSelected : SurfaceElaboration.SelectsVariantConstructor
      context path right) :
    left = right := by
  rcases leftSelected with
    ⟨_leftNotShadowed, leftSymbol, leftResolved, leftMember,
      leftDeclaration, _leftUnique⟩
  rcases rightSelected with
    ⟨_rightNotShadowed, rightSymbol, rightResolved, rightMember,
      rightDeclaration, _rightUnique⟩
  cases leftResolved with
  | intro leftReference leftFormed leftNameResolved =>
      cases rightResolved with
      | intro rightReference rightFormed rightNameResolved =>
          have referenceEquality : leftReference = rightReference :=
            Option.some.inj (leftFormed.symm.trans rightFormed)
          subst rightReference
          have symbolDeclarationEquality :
              rightSymbol.declaration = leftSymbol.declaration :=
            leftNameResolved.2 rightSymbol rightNameResolved.1 |>.2
          have constructorDeclarationEquality :
              left.declaration = right.declaration :=
            leftDeclaration.trans
              (symbolDeclarationEquality.symm.trans rightDeclaration.symm)
          exact metadata.variantConstructors left leftMember right rightMember
            constructorDeclarationEquality

/-- The symbolic wrapper adds lexical shadowing, but constructor identity is
    still inherited from the complete declaration table. -/
theorem selectsSymbolicVariantConstructor_unique
    (metadata : DeclarationMetadataUnique symbolic.globals)
    (leftSelected : SelectsSymbolicVariantConstructor symbolic path left)
    (rightSelected : SelectsSymbolicVariantConstructor symbolic path right) :
    left = right :=
  selectsVariantConstructor_unique metadata leftSelected.2 rightSelected.2

/-- Complete declaration metadata turns `SelectsImpl`'s identity-level
    ambiguity check into uniqueness of the selected implementation record. -/
theorem selectsImpl_unique
    (metadata : DeclarationMetadataUnique context)
    (leftSelected : Static.SelectsImpl context.implementations goal left)
    (rightSelected : Static.SelectsImpl context.implementations goal right) :
    left = right := by
  rcases leftSelected with ⟨leftApplies, leftUnique⟩
  rcases rightSelected with ⟨rightApplies, _rightUnique⟩
  have sameId : right.id = left.id := leftUnique right rightApplies
  cases leftApplies with
  | intro leftMember leftSubstitution leftBound leftPattern leftImplements
      leftHeader leftRequirements =>
      cases rightApplies with
      | intro rightMember rightSubstitution rightBound rightPattern rightImplements
          rightHeader rightRequirements =>
          exact metadata.implementationIds left leftMember right rightMember sameId.symm

/-- Every emitted specialization of a source function is tied to the exact
    source body that was checked once at the declaration's symbolic generic
    types. This is the provenance bridge between declaration-wide generic-body
    checking and per-specialization concrete lowering; the two witnesses cannot
    silently describe different source functions or different scheme rows. -/
theorem CollectedFunctionLowers.hasSymbolicallyTypedSource
    (lowered : CollectedFunctionLowers pack catalog program baseContext header
      scheme monomorphicInstance core) :
    ∃ address surface genericParameters substitution,
      header.source = .item address ∧
      pack.item? address = some (.function surface) ∧
      SourceWellFormed.FunctionBodyWellScoped
        (baseContext.forModule header.moduleId) surface.parameters surface.body ∧
      FunctionBodySymbolicallyTyped
        (withGenericParameters (baseContext.forModule header.moduleId)
          genericParameters)
        scheme.requirements surface.parameters scheme.parameterTypes
        scheme.returnType surface.body ∧
      Static.instantiateTypes substitution scheme.parameterTypes =
        some monomorphicInstance.parameterTypes ∧
      scheme.returnType.instantiate substitution =
        some monomorphicInstance.returnType ∧
      FunctionLowers program
        (withGenericParameters (baseContext.forModule header.moduleId)
          genericParameters)
        surface scheme monomorphicInstance core := by
  cases lowered with
  | intro address surface bodyContext source itemFound schemeCollected
      instanceMember instanceDeclaration specializes =>
      cases schemeCollected with
      | intro collectedAddress collectedSurface genericParameters parameterTypes
          returnType genericRequirements whereRequirements collectedSource
          collectedHeaderMember collectedHeaderMatches collectedItemFound
          collectedHeaderKind collectedSchemeMember collectedDeclaration
          namesUnique parametersCollected schemeParameters parameters
          schemeParameterTypes returned schemeReturnType genericBounds whereBounds
          schemeRequirements bodyScoped bodyTyped =>
          have addressEquality : address = collectedAddress := by
            have sameSource : Declarations.DeclarationOccurrence.item address =
                .item collectedAddress := source.symm.trans collectedSource
            injection sameSource
          subst collectedAddress
          have surfaceEquality : surface = collectedSurface := by
            rw [itemFound] at collectedItemFound
            injection collectedItemFound with itemEquality
            injection itemEquality
          subst collectedSurface
          obtain ⟨substitution, parameterTypesInstantiate,
            returnTypeInstantiates⟩ := specializes.instanceTypes
          exact ⟨address, surface, genericParameters, substitution, source,
            itemFound, bodyScoped, specializes.symbolic,
            parameterTypesInstantiate, returnTypeInstantiates,
            specializes.lowers⟩

structure MonomorphicArtifactsComplete
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (program : Core.Program)
    (context : SurfaceElaboration.Context)
    (externalBindings : List ExternalBinding) : Prop where
  nominalInstancesUnique : Static.NominalInstancesUnique context.nominalInstances
  functionInstanceIdsUnique : RowsUniqueByKey context.functionInstances
    (fun row => row.function)
  functionSpecializationsUnique : RowsUniqueByKey context.functionInstances
    Static.FunctionInstance.specializationKey
  methodInstanceIdsUnique : RowsUniqueByKey context.methodInstances
    (fun row => row.function)
  methodSpecializationsUnique : RowsUniqueByKey context.methodInstances
    Static.MethodInstance.specializationKey
  methodLookupCoherent : Static.MethodLookupCoherent
    context.implementations context.methods context.methodInstances
  traitImplementationMethodInstanceIdsUnique :
    RowsUniqueByKey context.traitImplementationMethodInstances
      (fun row => row.function)
  nominalInstancesMapped : ∀ resolved, resolved ∈ context.nominalInstances →
    Static.NominalInstanceMapped context.monomorphization resolved
  nominalInstancesLower : ∀ resolved, resolved ∈ context.nominalInstances →
    ∃ header scheme,
      header ∈ catalog.headers ∧ scheme ∈ context.nominalSchemes ∧
      (∃ core, CollectedMonomorphicStructLowers pack catalog program context
        header scheme resolved core) ∨
      (∃ core, CollectedMonomorphicEnumLowers pack catalog program context
        header scheme resolved core)
  functionInstancesLower : ∀ resolved, resolved ∈ context.functionInstances →
    ∃ header scheme core,
      header ∈ catalog.headers ∧ scheme ∈ context.functions ∧
      (CollectedFunctionLowers pack catalog program context header scheme resolved core ∨
       CollectedExternFunctionLowers pack catalog program context externalBindings
         header scheme resolved core)
  inherentMethodInstancesLower : ∀ resolved, resolved ∈ context.methodInstances →
    ∃ parentHeader methodHeader implementation scheme core,
      parentHeader ∈ catalog.headers ∧ methodHeader ∈ catalog.headers ∧
      scheme ∈ context.methods ∧
      CollectedInherentMethodFunctionLowers pack catalog program context
        parentHeader methodHeader implementation scheme resolved core
  traitImplementationMethodInstancesLower : ∀ resolved,
    resolved ∈ context.traitImplementationMethodInstances →
    ∃ parentHeader methodHeader implementation contract core,
      parentHeader ∈ catalog.headers ∧ methodHeader ∈ catalog.headers ∧
      TraitImplementationMethodFunctionLowers pack catalog program context
        parentHeader methodHeader implementation contract resolved core
  structuresCovered : ∀ core, core ∈ program.structures →
    ∃ header scheme resolved,
      CollectedMonomorphicStructLowers pack catalog program context
        header scheme resolved core
  enumerationsCovered : ∀ core, core ∈ program.enumerations →
    ∃ header scheme resolved,
      CollectedMonomorphicEnumLowers pack catalog program context
        header scheme resolved core
  functionsCovered : ∀ core, core ∈ program.functions →
    (∃ header scheme resolved,
      CollectedFunctionLowers pack catalog program context header scheme resolved core) ∨
    (∃ header scheme resolved,
      CollectedExternFunctionLowers pack catalog program context externalBindings
        header scheme resolved core) ∨
    (∃ parentHeader methodHeader implementation scheme resolved,
      CollectedInherentMethodFunctionLowers pack catalog program context
        parentHeader methodHeader implementation scheme resolved core) ∨
    (∃ parentHeader methodHeader implementation contract resolved,
      TraitImplementationMethodFunctionLowers pack catalog program context
        parentHeader methodHeader implementation contract resolved core)
  constantsLower : ConstantsLower pack catalog context program

/-- One nominal source type and ordered generic argument vector identify one
    emitted nominal artifact in a complete table. -/
theorem MonomorphicArtifactsComplete.nominalArtifact_unique
    (artifacts : MonomorphicArtifactsComplete pack catalog program context
      bindings)
    (leftDemand : NominalArtifactDemand context declaration sourceType kind
      typeArguments constArguments left)
    (rightDemand : NominalArtifactDemand context declaration sourceType kind
      typeArguments constArguments right) :
    left = right := by
  cases leftDemand with
  | intro leftMember _leftDeclaration leftSourceType _leftKind
      leftTypeArguments leftConstArguments _leftUnique =>
      cases rightDemand with
      | intro rightMember _rightDeclaration rightSourceType _rightKind
          rightTypeArguments rightConstArguments _rightUnique =>
          exact artifacts.nominalInstancesUnique left leftMember right rightMember
            (leftSourceType.trans rightSourceType.symm)
            (leftTypeArguments.trans rightTypeArguments.symm)
            (leftConstArguments.trans rightConstArguments.symm)

/-- One selected function declaration and ordered generic argument vector
    identify one emitted function artifact in a complete table. -/
theorem MonomorphicArtifactsComplete.functionArtifact_unique
    (artifacts : MonomorphicArtifactsComplete pack catalog program context
      bindings)
    (leftDemand : FunctionArtifactDemand context path scheme typeArguments
      constArguments left)
    (rightDemand : FunctionArtifactDemand context path scheme typeArguments
      constArguments right) :
    left = right := by
  cases leftDemand with
  | intro leftMember leftDeclaration leftTypeArguments leftConstArguments
      _leftUnique =>
      cases rightDemand with
      | intro rightMember rightDeclaration rightTypeArguments rightConstArguments
          _rightUnique =>
          apply artifacts.functionSpecializationsUnique left leftMember right
            rightMember
          simp [Static.FunctionInstance.specializationKey, leftDeclaration,
            rightDeclaration, leftTypeArguments, rightTypeArguments,
            leftConstArguments, rightConstArguments]

/-- For methods, the ground receiver joins the declaration and generic
    arguments in the artifact identity. -/
theorem MonomorphicArtifactsComplete.methodArtifact_unique
    (artifacts : MonomorphicArtifactsComplete pack catalog program context
      bindings)
    (receiverEquality : left.receiverType = right.receiverType)
    (leftDemand : MethodArtifactDemand context scheme typeArguments
      constArguments left)
    (rightDemand : MethodArtifactDemand context scheme typeArguments
      constArguments right) :
    left = right := by
  cases leftDemand with
  | intro leftMember leftDeclaration _leftName _leftReceiverMode
      leftTypeArguments leftConstArguments _leftUnique =>
      cases rightDemand with
      | intro rightMember rightDeclaration _rightName _rightReceiverMode
          rightTypeArguments rightConstArguments _rightUnique =>
          apply artifacts.methodSpecializationsUnique left leftMember right
            rightMember
          simp [Static.MethodInstance.specializationKey, leftDeclaration,
            rightDeclaration, receiverEquality, leftTypeArguments,
            rightTypeArguments, leftConstArguments, rightConstArguments]

/-- A complete artifact table cannot make one resolved call target denote two
    different function-instance records. Resolution already rejects distinct
    applicable core IDs; artifact-ID uniqueness upgrades that agreement to
    equality of the complete selected records. -/
theorem resolvesFunction_unique
    (artifacts : MonomorphicArtifactsComplete pack catalog program context bindings)
    (leftResolved : Static.ResolvesFunction context.implementations
      context.functions context.functionInstances argumentTypes leftScheme left)
    (rightResolved : Static.ResolvesFunction context.implementations
      context.functions context.functionInstances argumentTypes rightScheme right) :
    left = right := by
  rcases leftResolved with ⟨_leftSchemeMember,
    ⟨leftMember, _leftApplies⟩, leftUnique⟩
  rcases rightResolved with ⟨rightSchemeMember, rightApplies, _rightUnique⟩
  rcases rightApplies with ⟨rightMember, rightApplies⟩
  have sameFunction : right.function = left.function :=
    leftUnique rightScheme right rightSchemeMember ⟨rightMember, rightApplies⟩
  exact artifacts.functionInstanceIdsUnique
    left leftMember right rightMember sameFunction.symm

/-- Method resolution has the same identity discipline as direct calls: a
    resolved core function ID names exactly one complete method instance. -/
theorem resolvesMethod_unique
    (artifacts : MonomorphicArtifactsComplete pack catalog program context bindings)
    (leftResolved : Static.ResolvesMethod context.implementations context.methods
      context.methodInstances context.currentModule receiver name argumentTypes
      leftScheme left)
    (rightResolved : Static.ResolvesMethod context.implementations context.methods
      context.methodInstances context.currentModule receiver name argumentTypes
      rightScheme right) :
    left = right := by
  rcases leftResolved with ⟨_leftSchemeMember,
    leftApplies, _leftPreferred, leftUnique⟩
  rcases rightResolved with
    ⟨rightSchemeMember, rightApplies, rightPreferred, _rightUnique⟩
  have leftMember := leftApplies.1.1
  have rightMember := rightApplies.1.1
  have sameFunction : right.function = left.function :=
    leftUnique rightScheme right rightSchemeMember rightApplies
      rightPreferred
  exact artifacts.methodInstanceIdsUnique
    left leftMember right rightMember sameFunction.symm

structure CompleteProgramElaboration
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (imports : List Declarations.CollectedImport)
    (program : Core.Program)
    (context : SurfaceElaboration.Context)
    (externalBindings : List ExternalBinding) : Prop where
  sourcePack : Declarations.SourcePackWellFormed pack
  declarationCatalog : Declarations.CatalogWellFormed pack catalog
  importCollection : Declarations.ImportCollectionCovers pack imports
  importOrder : ∃ order, Declarations.ModuleDependencyOrderCovers pack imports order
  names : context.names = Declarations.nameEnvironment pack catalog imports
  target : program.target = context.target
  declarations : DeclarationCollectionComplete pack catalog context
  metadataUnique : DeclarationMetadataUnique context
  implementationsCoherent : Static.ImplementationsCoherent context.implementations
  artifacts : MonomorphicArtifactsComplete pack catalog program context externalBindings
  coreIds : CoreProgramIdsUnique program
  typed : Typing.ProgramWellTyped program
  layouts : Layout.ProgramHasLayouts program

/-- Every callable scheme, internal or external, inherits signature
    substitution functionality from its collected source declaration. -/
theorem CompleteProgramElaboration.functionSignatureSubstitute_unique
    (complete : CompleteProgramElaboration pack catalog imports program context
      externalBindings)
    (schemeMember : scheme ∈ context.functions)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      scheme.genericParameters typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      scheme.genericParameters typeArguments constArguments)
    (leftParameters : Static.substituteTypes leftSubstitution
      scheme.parameterTypes = some leftParameterTypes)
    (rightParameters : Static.substituteTypes rightSubstitution
      scheme.parameterTypes = some rightParameterTypes)
    (leftReturn : scheme.returnType.substitute leftSubstitution =
      some leftReturnType)
    (rightReturn : scheme.returnType.substitute rightSubstitution =
      some rightReturnType) :
    leftParameterTypes = rightParameterTypes ∧
      leftReturnType = rightReturnType := by
  obtain ⟨header, bodyContext, _headerMember, collected | collected⟩ :=
    complete.declarations.functionSchemes scheme schemeMember
  · exact collected.signature_substitute_unique leftBound rightBound
      leftParameters rightParameters leftReturn rightReturn
  · exact collected.signature_substitute_unique leftBound rightBound
      leftParameters rightParameters leftReturn rightReturn

/-- Every source-selectable method scheme comes from an inherent method
    declaration, whose receiver, argument, and return types are functional in
    the ordered generic argument vector. -/
theorem CompleteProgramElaboration.methodSignatureSubstitute_unique
    (complete : CompleteProgramElaboration pack catalog imports program context
      externalBindings)
    (schemeMember : scheme ∈ context.methods)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      scheme.genericParameters typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      scheme.genericParameters typeArguments constArguments)
    (leftReceiver : scheme.receiverType.substitute leftSubstitution =
      some leftReceiverType)
    (rightReceiver : scheme.receiverType.substitute rightSubstitution =
      some rightReceiverType)
    (leftArguments : Static.substituteTypes leftSubstitution
      scheme.argumentTypes = some leftArgumentTypes)
    (rightArguments : Static.substituteTypes rightSubstitution
      scheme.argumentTypes = some rightArgumentTypes)
    (leftReturn : scheme.returnType.substitute leftSubstitution =
      some leftReturnType)
    (rightReturn : scheme.returnType.substitute rightSubstitution =
      some rightReturnType) :
    leftReceiverType = rightReceiverType ∧
      leftArgumentTypes = rightArgumentTypes ∧
      leftReturnType = rightReturnType := by
  obtain ⟨parentHeader, methodHeader, implementation, bodyContext,
    _parentMember, _methodMember, collected⟩ :=
    complete.declarations.inherentMethodSchemes scheme schemeMember
  exact collected.signature_substitute_unique leftBound rightBound
    leftReceiver rightReceiver leftArguments rightArguments leftReturn
    rightReturn

/-- Complete-program declaration provenance exposes the retained payload proof
    needed to make a selected variant's symbolic payload substitution
    functional. -/
theorem CompleteProgramElaboration.variantPayloadSubstitute_unique
    (complete : CompleteProgramElaboration pack catalog imports program context
      externalBindings)
    (member : constructor ∈ context.variantConstructors)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      constructor.genericParameters typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      constructor.genericParameters typeArguments constArguments)
    (leftSubstituted : Static.substituteTypes leftSubstitution
      constructor.payload = some leftPayload)
    (rightSubstituted : Static.substituteTypes rightSubstitution
      constructor.payload = some rightPayload) :
    leftPayload = rightPayload := by
  obtain ⟨parentHeader, variantHeader, nominal, _parentMember, _variantMember,
    collected⟩ := complete.declarations.variantConstructorSchemes constructor member
  exact collected.payload_substitute_unique leftBound rightBound
    leftSubstituted rightSubstituted

/-- The same provenance principle for one field of a selected struct
    constructor. -/
theorem CompleteProgramElaboration.structFieldSubstitute_unique
    (complete : CompleteProgramElaboration pack catalog imports program context
      externalBindings)
    (constructorMember : constructor ∈ context.structConstructors)
    (fieldMember : field ∈ constructor.fields)
    (leftBound : Static.SymbolicArgumentsBound leftSubstitution
      constructor.genericParameters typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightSubstitution
      constructor.genericParameters typeArguments constArguments)
    (leftSubstituted : field.type.substitute leftSubstitution = some leftType)
    (rightSubstituted : field.type.substitute rightSubstitution = some rightType) :
    leftType = rightType := by
  obtain ⟨header, nominal, _headerMember, collected⟩ :=
    complete.declarations.structConstructorSchemes constructor constructorMember
  exact collected.field_substitute_unique fieldMember leftBound rightBound
    leftSubstituted rightSubstituted

/-- Equal symbolic nominal arguments select the same complete monomorphic
    artifact, even when their witnessing substitutions differ away from the
    declaration's generic parameter domain. -/
theorem CompleteProgramElaboration.nominalEvidenceArtifact_unique
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (left : NominalInstantiationEvidence outer concrete symbolic parameters
      requirements declaration sourceType kind leftInner leftTypeArguments
      leftConstArguments leftResolved)
    (right : NominalInstantiationEvidence outer concrete symbolic parameters
      requirements declaration sourceType kind rightInner rightTypeArguments
      rightConstArguments rightResolved)
    (typeArgumentsEquality : leftTypeArguments = rightTypeArguments)
    (constArgumentsEquality : leftConstArguments = rightConstArguments) :
    leftResolved = rightResolved := by
  have instantiatedTypesEquality := congrArg
    (Static.instantiateTypes outer) typeArgumentsEquality
  have instantiatedConstantsEquality := congrArg
    (Static.instantiateConstants outer) constArgumentsEquality
  have groundTypesEquality := Option.some.inj
    (left.typeArgumentsGround.symm.trans
      (instantiatedTypesEquality.trans right.typeArgumentsGround))
  have groundConstantsEquality := Option.some.inj
    (left.constArgumentsGround.symm.trans
      (instantiatedConstantsEquality.trans right.constArgumentsGround))
  cases left.artifact with
  | intro leftMember _leftDeclaration leftSourceType _leftKind
      leftTypeArguments leftConstArguments _leftUnique =>
      cases right.artifact with
      | intro rightMember _rightDeclaration rightSourceType _rightKind
          rightTypeArguments rightConstArguments _rightUnique =>
          have leftMemberGlobal :
              leftResolved ∈ symbolic.globals.nominalInstances := by
            rw [contexts.globals] at leftMember
            exact leftMember
          have rightMemberGlobal :
              rightResolved ∈ symbolic.globals.nominalInstances := by
            rw [contexts.globals] at rightMember
            exact rightMember
          exact complete.artifacts.nominalInstancesUnique
            leftResolved leftMemberGlobal rightResolved rightMemberGlobal
            (leftSourceType.trans rightSourceType.symm)
            (leftTypeArguments.trans
              (groundTypesEquality.trans rightTypeArguments.symm))
            (leftConstArguments.trans
              (groundConstantsEquality.trans rightConstArguments.symm))

/-- Contextual checking carries the finite artifact demand directly rather
    than through `NominalInstantiationEvidence`. The same complete-table key
    still makes the selected concrete row functional. -/
theorem CompleteProgramElaboration.concreteNominalArtifact_unique
    {symbolic : SymbolicBodyContext}
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (left : NominalArtifactDemand concrete declaration sourceType kind
      leftGroundTypeArguments leftGroundConstArguments leftResolved)
    (right : NominalArtifactDemand concrete declaration sourceType kind
      rightGroundTypeArguments rightGroundConstArguments rightResolved)
    (typeArgumentsEquality : leftGroundTypeArguments = rightGroundTypeArguments)
    (constArgumentsEquality :
      leftGroundConstArguments = rightGroundConstArguments) :
    leftResolved = rightResolved := by
  cases left with
  | intro leftMember _leftDeclaration leftSourceType _leftKind
      leftTypeArguments leftConstArguments _leftUnique =>
      cases right with
      | intro rightMember _rightDeclaration rightSourceType _rightKind
          rightTypeArguments rightConstArguments _rightUnique =>
          have leftMemberGlobal :
              leftResolved ∈ symbolic.globals.nominalInstances := by
            rw [contexts.globals] at leftMember
            exact leftMember
          have rightMemberGlobal :
              rightResolved ∈ symbolic.globals.nominalInstances := by
            rw [contexts.globals] at rightMember
            exact rightMember
          exact complete.artifacts.nominalInstancesUnique
            leftResolved leftMemberGlobal rightResolved rightMemberGlobal
            (leftSourceType.trans rightSourceType.symm)
            (leftTypeArguments.trans
              (typeArgumentsEquality.trans rightTypeArguments.symm))
            (leftConstArguments.trans
              (constArgumentsEquality.trans rightConstArguments.symm))

/-- Equal ground generic arguments identify one emitted function artifact in
    the complete table. This is the direct-call analogue of contextual nominal
    artifact identity; source selection has already fixed `scheme`. -/
theorem CompleteProgramElaboration.concreteFunctionArtifact_unique
    {symbolic : SymbolicBodyContext}
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (left : FunctionArtifactDemand concrete path scheme
      leftGroundTypeArguments leftGroundConstArguments leftResolved)
    (right : FunctionArtifactDemand concrete path scheme
      rightGroundTypeArguments rightGroundConstArguments rightResolved)
    (typeArgumentsEquality :
      leftGroundTypeArguments = rightGroundTypeArguments)
    (constArgumentsEquality :
      leftGroundConstArguments = rightGroundConstArguments) :
    leftResolved = rightResolved := by
  cases left with
  | intro leftMember leftDeclaration leftTypeArguments leftConstArguments
      _leftUnique =>
      cases right with
      | intro rightMember rightDeclaration rightTypeArguments
          rightConstArguments _rightUnique =>
          have leftMemberGlobal :
              leftResolved ∈ symbolic.globals.functionInstances := by
            rw [contexts.globals] at leftMember
            exact leftMember
          have rightMemberGlobal :
              rightResolved ∈ symbolic.globals.functionInstances := by
            rw [contexts.globals] at rightMember
            exact rightMember
          apply complete.artifacts.functionSpecializationsUnique
            leftResolved leftMemberGlobal rightResolved rightMemberGlobal
          simp [Static.FunctionInstance.specializationKey, leftDeclaration,
            rightDeclaration, leftTypeArguments, rightTypeArguments,
            leftConstArguments, rightConstArguments, typeArgumentsEquality,
            constArgumentsEquality]

/-- A method specialization key additionally includes its ground receiver.
    Once symbolic signature functionality aligns that receiver and the ordered
    generic arguments, the complete table identifies one emitted method row. -/
theorem CompleteProgramElaboration.concreteMethodArtifact_unique
    {symbolic : SymbolicBodyContext}
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (contexts : symbolic.Specializes outer groundEnclosingReturn concrete)
    (receiverEquality : leftResolved.receiverType = rightResolved.receiverType)
    (left : MethodArtifactDemand concrete scheme leftGroundTypeArguments
      leftGroundConstArguments leftResolved)
    (right : MethodArtifactDemand concrete scheme rightGroundTypeArguments
      rightGroundConstArguments rightResolved)
    (typeArgumentsEquality :
      leftGroundTypeArguments = rightGroundTypeArguments)
    (constArgumentsEquality :
      leftGroundConstArguments = rightGroundConstArguments) :
    leftResolved = rightResolved := by
  cases left with
  | intro leftMember leftDeclaration _leftName _leftReceiverMode
      leftTypeArguments leftConstArguments _leftUnique =>
      cases right with
      | intro rightMember rightDeclaration _rightName _rightReceiverMode
          rightTypeArguments rightConstArguments _rightUnique =>
          have leftMemberGlobal :
              leftResolved ∈ symbolic.globals.methodInstances := by
            rw [contexts.globals] at leftMember
            exact leftMember
          have rightMemberGlobal :
              rightResolved ∈ symbolic.globals.methodInstances := by
            rw [contexts.globals] at rightMember
            exact rightMember
          apply complete.artifacts.methodSpecializationsUnique
            leftResolved leftMemberGlobal rightResolved rightMemberGlobal
          simp [Static.MethodInstance.specializationKey, leftDeclaration,
            rightDeclaration, receiverEquality, leftTypeArguments,
            rightTypeArguments, leftConstArguments, rightConstArguments,
            typeArgumentsEquality, constArgumentsEquality]

/-- Within a complete program, a symbolic variant path selects one complete
    constructor record, not merely rows that agree on selected fields. -/
theorem CompleteProgramElaboration.symbolicVariantConstructor_unique
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (leftSelected : SelectsSymbolicVariantConstructor symbolic path left)
    (rightSelected : SelectsSymbolicVariantConstructor symbolic path right) :
    left = right :=
  selectsSymbolicVariantConstructor_unique complete.metadataUnique
    leftSelected rightSelected

/-- A value path cannot simultaneously denote a function and an enum-variant
    constructor. Both selections resolve the same value-namespace declaration,
    while complete collection proves that function metadata originates at an
    item occurrence and variant metadata at an enum-child occurrence. Catalog
    declaration-ID uniqueness makes those incompatible provenances collide. -/
theorem CompleteProgramElaboration.function_excludes_symbolicVariantConstructor
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (functionSelected : SourceWellFormed.SelectsFunction
      symbolic.scopeContext path scheme)
    (variantSelected : SelectsSymbolicVariantConstructor symbolic path constructor) :
    False := by
  rcases functionSelected with
    ⟨_functionNotShadowed, functionSymbol, functionResolved, functionMember,
      functionDeclaration, _functionUnique⟩
  rcases variantSelected with
    ⟨_variantNotShadowed, _globalNotShadowed, variantSymbol, variantResolved,
      variantMember, variantDeclaration, _variantUnique⟩
  have symbolDeclarationEquality :
      functionSymbol.declaration = variantSymbol.declaration :=
    functionResolved.declaration_unique variantResolved
  obtain ⟨_parentHeader, variantHeader, _nominal, _parentHeaderMember,
      variantHeaderMember, variantCollected⟩ :=
    complete.declarations.variantConstructorSchemes constructor variantMember
  obtain ⟨variantParent, variantIndex, variantSource,
      collectedVariantDeclaration⟩ := variantCollected.source_declaration
  have itemProvenanceImpossible :
      ∀ functionHeader, functionHeader ∈ catalog.headers →
        (∃ address, functionHeader.source = .item address ∧
          scheme.declaration = functionHeader.declaration) → False := by
    intro functionHeader functionHeaderMember functionProvenance
    obtain ⟨address, functionSource, collectedFunctionDeclaration⟩ :=
      functionProvenance
    have headerDeclarationEquality :
        functionHeader.declaration = variantHeader.declaration :=
      collectedFunctionDeclaration.symm.trans
        (functionDeclaration.trans
          (symbolDeclarationEquality.trans
            (variantDeclaration.symm.trans collectedVariantDeclaration)))
    have headerSourceEquality :
        functionHeader.source = variantHeader.source :=
      complete.declarationCatalog.2.1 functionHeader functionHeaderMember
        variantHeader variantHeaderMember headerDeclarationEquality
    have occurrenceContradiction :
        Declarations.DeclarationOccurrence.item address =
          .enumVariant variantParent variantIndex :=
      functionSource.symm.trans (headerSourceEquality.trans variantSource)
    cases occurrenceContradiction
  obtain ⟨functionHeader, _bodyContext, functionHeaderMember,
      functionCollected | externalCollected⟩ :=
    complete.declarations.functionSchemes scheme functionMember
  · exact itemProvenanceImpossible functionHeader functionHeaderMember
      functionCollected.source_declaration
  · exact itemProvenanceImpossible functionHeader functionHeaderMember
      externalCollected.source_declaration

/-- The four semantic categories available to a source path in call position.
    Generic-argument mode belongs to the selected category's elaboration and
    does not create another callee category. -/
inductive PathCallResolutionKind where
  | intrinsic
  | function
  | variant
  | associated
deriving DecidableEq

/-- Evidence for the category selected at one path-call occurrence. Intrinsic
    precedence is explicit for both kinds of global value; declaration
    provenance separates functions from enum constructors. -/
inductive PathCallResolvesAs
    (symbolic : SymbolicBodyContext) (path : Surface.Path) :
    PathCallResolutionKind → Prop where
  | intrinsic
      (found : SurfaceElaboration.builtinIntrinsic? path = some intrinsic) :
      PathCallResolvesAs symbolic path .intrinsic
  | function
      (selected : SourceWellFormed.SelectsFunction
        symbolic.scopeContext path scheme)
      (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none) :
      PathCallResolvesAs symbolic path .function
  | variant
      (selected : SelectsSymbolicVariantConstructor symbolic path constructor)
      (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none) :
      PathCallResolvesAs symbolic path .variant
  | associated
      (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none)
      (notFunction : ¬ ∃ scheme,
        SourceWellFormed.SelectsFunction symbolic.scopeContext path scheme)
      (notVariant : ¬ ∃ constructor,
        SelectsSymbolicVariantConstructor symbolic path constructor) :
      PathCallResolvesAs symbolic path .associated

/-- One path-call occurrence has one callee category. This theorem centralizes
    intrinsic precedence and declaration-category disjointness so recursive
    expression functionality never needs a matrix of cross-category cases. -/
theorem PathCallResolvesAs.unique
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : PathCallResolvesAs symbolic path leftKind)
    (right : PathCallResolvesAs symbolic path rightKind) :
    leftKind = rightKind := by
  cases left with
  | intrinsic leftFound =>
      cases right with
      | intrinsic rightFound => rfl
      | function _selected rightNotIntrinsic =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
            leftFound rightNotIntrinsic).elim
      | variant _selected rightNotIntrinsic =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
            leftFound rightNotIntrinsic).elim
      | associated rightNotIntrinsic _ _ =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
            leftFound rightNotIntrinsic).elim
  | function leftSelected leftNotIntrinsic =>
      cases right with
      | intrinsic rightFound =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
            rightFound leftNotIntrinsic).elim
      | function _rightSelected _rightNotIntrinsic => rfl
      | variant rightSelected _rightNotIntrinsic =>
          exact (complete.function_excludes_symbolicVariantConstructor
            leftSelected rightSelected).elim
      | associated _ rightNotFunction _ =>
          exact (rightNotFunction ⟨_, leftSelected⟩).elim
  | variant leftSelected leftNotIntrinsic =>
      cases right with
      | intrinsic rightFound =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
            rightFound leftNotIntrinsic).elim
      | function rightSelected _rightNotIntrinsic =>
          exact (complete.function_excludes_symbolicVariantConstructor
            rightSelected leftSelected).elim
      | variant _rightSelected _rightNotIntrinsic => rfl
      | associated _ _ rightNotVariant =>
          exact (rightNotVariant ⟨_, leftSelected⟩).elim
  | associated leftNotIntrinsic leftNotFunction leftNotVariant =>
      cases right with
      | intrinsic rightFound =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
            rightFound leftNotIntrinsic).elim
      | function rightSelected _ =>
          exact (leftNotFunction ⟨_, rightSelected⟩).elim
      | variant rightSelected _ =>
          exact (leftNotVariant ⟨_, rightSelected⟩).elim
      | associated _ _ _ => rfl

/-- Every exact path-call derivation exposes its semantic callee category. -/
theorem ExprInferenceDerivationSpecializes.pathCallResolution
    (derived : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      symbolicType groundType coreExpression) :
    ∃ kind, PathCallResolvesAs symbolic path kind := by
  cases derived with
  | printI32 builtin argument => exact ⟨.intrinsic, .intrinsic builtin⟩
  | assert builtin argument => exact ⟨.intrinsic, .intrinsic builtin⟩
  | i32ArrayDataPtr builtin argument => exact ⟨.intrinsic, .intrinsic builtin⟩
  | i32SliceFromRawParts builtin pointer length =>
      exact ⟨.intrinsic, .intrinsic builtin⟩
  | i32SliceDataPtr builtin slice => exact ⟨.intrinsic, .intrinsic builtin⟩
  | stringDataPtr builtin string => exact ⟨.intrinsic, .intrinsic builtin⟩
  | variantExplicit evidence payload =>
      exact ⟨.variant, .variant evidence.selected evidence.notIntrinsic⟩
  | variantInferred evidence payload =>
      exact ⟨.variant, .variant evidence.selected evidence.notIntrinsic⟩
  | variantNongeneric evidence payload =>
      exact ⟨.variant, .variant evidence.selected evidence.notIntrinsic⟩
  | directCallInferred evidence arguments =>
      exact ⟨.function, .function evidence.selected evidence.notIntrinsic⟩
  | directCallExplicit evidence arguments =>
      exact ⟨.function, .function evidence.selected evidence.notIntrinsic⟩
  | directCallNongeneric evidence arguments =>
      exact ⟨.function, .function evidence.selected evidence.notIntrinsic⟩
  | associatedCallInferred evidence arguments =>
      exact ⟨.associated, .associated evidence.notIntrinsic
        evidence.notFunction evidence.notVariant⟩
  | associatedCallContextual evidence arguments =>
      exact ⟨.associated, .associated evidence.notIntrinsic
        evidence.notFunction evidence.notVariant⟩

/-- Within a complete program, one source struct path selects one full
    constructor scheme, not merely rows agreeing on their projected fields. -/
theorem CompleteProgramElaboration.structConstructor_unique
    (complete : CompleteProgramElaboration pack catalog imports program
      context externalBindings)
    (leftSelected : SurfaceElaboration.SelectsStructConstructor context path left)
    (rightSelected : SurfaceElaboration.SelectsStructConstructor context path right) :
    left = right :=
  selectsStructConstructor_unique complete.metadataUnique leftSelected rightSelected

/-- A complete program gives symbolic field lookup one result type. The proof
    first fixes the struct constructor by source `TypeId`, then the named field,
    and finally uses collection provenance to show that equal ordered generic
    arguments substitute its retained type identically. -/
theorem CompleteProgramElaboration.symbolicFieldResult_unique
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (leftSelected : SelectsSymbolicField symbolic receiver name leftResult)
    (rightSelected : SelectsSymbolicField symbolic receiver name rightResult) :
    leftResult = rightResult := by
  rcases leftSelected with
    ⟨leftSourceType, leftTypeArguments, leftConstArguments, leftConstructor,
      leftSubstitution, leftField, leftReceiver, leftConstructorMember,
      leftConstructorType, leftArguments, leftFieldMember, leftFieldName,
      leftSubstituted, leftFieldUnique⟩
  rcases rightSelected with
    ⟨rightSourceType, rightTypeArguments, rightConstArguments, rightConstructor,
      rightSubstitution, rightField, rightReceiver, rightConstructorMember,
      rightConstructorType, rightArguments, rightFieldMember, rightFieldName,
      rightSubstituted, _rightFieldUnique⟩
  have receiverEquality := leftReceiver.symm.trans rightReceiver
  injection receiverEquality with sourceTypeEquality typeArgumentsEquality
    constArgumentsEquality
  have constructorKeyEquality :
      leftConstructor.sourceType = rightConstructor.sourceType :=
    leftConstructorType.trans
      (sourceTypeEquality.trans rightConstructorType.symm)
  subst rightTypeArguments
  subst rightConstArguments
  have constructorEquality :=
    complete.metadataUnique.structConstructorSourceTypes
      leftConstructor leftConstructorMember rightConstructor
      rightConstructorMember constructorKeyEquality
  subst rightConstructor
  have fieldEquality :=
    leftFieldUnique rightField rightFieldMember rightFieldName
  subst rightField
  obtain ⟨header, nominal, _headerMember, collected⟩ :=
    complete.declarations.structConstructorSchemes leftConstructor
      leftConstructorMember
  exact collected.field_substitute_unique leftFieldMember leftArguments
    rightArguments leftSubstituted rightSubstituted

/-- Exact inference of a value path is functional. In particular, the
    shadowing rule makes the local and constant constructors disjoint rather
    than relying on rule order. -/
theorem CompleteProgramElaboration.pathInference_unique
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.path path) leftType leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.path path) rightType rightGround rightCore) :
    leftType = rightType ∧ leftGround = rightGround ∧ leftCore = rightCore := by
  cases left with
  | «local» leftSingle leftSymbolicResolved leftConcreteResolved leftGrounds =>
      cases right with
      | «local» rightSingle rightSymbolicResolved rightConcreteResolved
          rightGrounds =>
          have nameEquality := Option.some.inj
            (leftSingle.symm.trans rightSingle)
          subst nameEquality
          cases leftSymbolicResolved.unique rightSymbolicResolved
          cases leftConcreteResolved.unique rightConcreteResolved
          exact ⟨rfl, rfl, rfl⟩
      | constant rightSymbolicSelected rightConcreteSelected =>
          exact (rightSymbolicSelected.1.excludesLocal leftSingle
            leftSymbolicResolved.scopeResolved).elim
  | constant leftSymbolicSelected leftConcreteSelected =>
      cases right with
      | «local» rightSingle rightSymbolicResolved rightConcreteResolved
          rightGrounds =>
          exact (leftSymbolicSelected.1.excludesLocal rightSingle
            rightSymbolicResolved.scopeResolved).elim
      | constant rightSymbolicSelected rightConcreteSelected =>
          cases leftSymbolicSelected.unique rightSymbolicSelected
          exact ⟨rfl, rfl, rfl⟩

/-- Default literal inference has one core value. -/
theorem ExprInferenceDerivationSpecializes.literal_unique
    {surfaceLiteral : Surface.Literal}
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.literal surfaceLiteral) leftType leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.literal surfaceLiteral) rightType rightGround rightCore) :
    leftType = rightType ∧ leftGround = rightGround ∧ leftCore = rightCore := by
  cases left with
  | literal leftLowered =>
      cases right with
      | literal rightLowered =>
          cases leftLowered.core_unique rightLowered
          exact ⟨rfl, rfl, rfl⟩

/-- Literals infer only their language-defined default scalar type. Raw-pointer
    null literals therefore exist exclusively in contextual checking rules. -/
theorem ExprInferenceDerivationSpecializes.literal_not_raw_pointer
    {literal : Surface.Literal}
    (inferred : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.literal literal) (.scalar .rawPtr)
      groundType coreExpression) : False := by
  cases literal <;> cases inferred

/-- `self` is ordinary nearest-binding lookup with a distinguished source
    spelling, so both its symbolic and concrete projections are functional. -/
theorem ExprInferenceDerivationSpecializes.selfValue_unique
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts .selfValue leftType leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts .selfValue rightType rightGround rightCore) :
    leftType = rightType ∧ leftGround = rightGround ∧ leftCore = rightCore := by
  cases left with
  | selfValue leftSymbolicResolved leftConcreteResolved leftGrounds =>
      cases right with
      | selfValue rightSymbolicResolved rightConcreteResolved rightGrounds =>
          cases leftSymbolicResolved.unique rightSymbolicResolved
          cases leftConcreteResolved.unique rightConcreteResolved
          exact ⟨rfl, rfl, rfl⟩

/-- Exact value indexing is functional once exact inference is functional for
    its base and index children. Equality of the inferred base type also makes
    the array and slice rules disjoint. -/
theorem ExprInferenceDerivationSpecializes.index_unique_of_expr
    (baseUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceBase leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceBase rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (indexUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceIndex leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceIndex rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.index surfaceBase surfaceIndex)
      leftSymbolic leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.index surfaceBase surfaceIndex)
      rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases left with
  | indexArray leftBase leftElementGrounds leftIndex leftInteger =>
      cases right with
      | indexArray rightBase rightElementGrounds rightIndex rightInteger =>
          rcases baseUnique leftBase rightBase with
            ⟨baseTypeEquality, baseGroundEquality, coreBaseEquality⟩
          injection baseTypeEquality with elementTypeEquality lengthEquality
          injection baseGroundEquality with groundElementEquality
            groundLengthEquality
          cases elementTypeEquality
          cases lengthEquality
          cases groundElementEquality
          cases groundLengthEquality
          cases coreBaseEquality
          rcases indexUnique leftIndex rightIndex with ⟨rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | indexSlice rightBase rightElementGrounds rightIndex rightInteger =>
          rcases baseUnique leftBase rightBase with ⟨baseTypeEquality, _, _⟩
          cases baseTypeEquality
  | indexSlice leftBase leftElementGrounds leftIndex leftInteger =>
      cases right with
      | indexArray rightBase rightElementGrounds rightIndex rightInteger =>
          rcases baseUnique leftBase rightBase with ⟨baseTypeEquality, _, _⟩
          cases baseTypeEquality
      | indexSlice rightBase rightElementGrounds rightIndex rightInteger =>
          rcases baseUnique leftBase rightBase with
            ⟨baseTypeEquality, baseGroundEquality, coreBaseEquality⟩
          injection baseTypeEquality with elementTypeEquality
          injection baseGroundEquality with groundElementEquality
          cases elementTypeEquality
          cases groundElementEquality
          cases coreBaseEquality
          rcases indexUnique leftIndex rightIndex with ⟨rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩

/-- Exact field inference is functional once its base expression is. The
    normalized symbolic receiver is explicitly grounded to the receiver used
    by concrete member lowering, so symbolic and concrete field selection
    cannot drift to unrelated rows. -/
theorem ExprInferenceDerivationSpecializes.field_unique_of_expr
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (baseUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceBase leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceBase rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.member surfaceBase name) leftSymbolic
      leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.member surfaceBase name) rightSymbolic
      rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases left with
  | field leftBase leftMemberBase leftMemberLowers leftReceiverGrounds
      leftSymbolicSelected leftConcreteSelected leftFieldGrounds =>
      cases right with
      | field rightBase rightMemberBase rightMemberLowers rightReceiverGrounds
          rightSymbolicSelected rightConcreteSelected rightFieldGrounds =>
          rcases baseUnique leftBase rightBase with
            ⟨sourceTypeEquality, sourceGroundEquality, sourceCoreEquality⟩
          cases sourceTypeEquality
          cases sourceGroundEquality
          cases sourceCoreEquality
          cases leftMemberBase.unique rightMemberBase
          have receiverGroundEquality := Option.some.inj
            (leftReceiverGrounds.symm.trans rightReceiverGrounds)
          cases receiverGroundEquality
          cases leftMemberLowers.core_unique rightMemberLowers
          cases complete.symbolicFieldResult_unique leftSymbolicSelected
            rightSymbolicSelected
          cases leftConcreteSelected.unique rightConcreteSelected
          exact ⟨rfl, rfl, rfl⟩

/-- Exact unary inference is functional once its operand is. The exceptional
    signed-minimum rule is disjoint from ordinary unary negation because that
    magnitude cannot elaborate as a positive operand of the same signed type. -/
theorem ExprInferenceDerivationSpecializes.unary_unique_of_expr
    (operandUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceOperand leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceOperand rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.unary op surfaceOperand) leftSymbolic
      leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.unary op surfaceOperand) rightSymbolic
      rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases left with
  | signedMinimumLiteral leftMinimum =>
      cases right with
      | signedMinimumLiteral rightMinimum =>
          cases leftMinimum.core_unique rightMinimum
          exact ⟨rfl, rfl, rfl⟩
      | unaryScalar rightOperand rightTyped =>
          cases rightOperand with
          | literal rightPositive =>
              exact (leftMinimum.not_positive_literal rightPositive).elim
  | unaryScalar leftOperand leftTyped =>
      cases right with
      | signedMinimumLiteral rightMinimum =>
          cases leftOperand with
          | literal leftPositive =>
              exact (rightMinimum.not_positive_literal leftPositive).elim
      | unaryScalar rightOperand rightTyped =>
          rcases operandUnique leftOperand rightOperand with
            ⟨inputTypeEquality, inputGroundEquality, coreOperandEquality⟩
          injection inputTypeEquality with scalarTypeEquality
          injection inputGroundEquality with groundScalarTypeEquality
          cases scalarTypeEquality
          cases groundScalarTypeEquality
          cases coreOperandEquality
          have outputTypeEquality := leftTyped.output_unique rightTyped
          injection outputTypeEquality with scalarOutputEquality
          cases scalarOutputEquality
          exact ⟨rfl, rfl, rfl⟩

/-- Two ordinary binary-operation derivations agree once their recursively
    inferred operands do. -/
private theorem binaryOperationDerivations_unique_of_expr
    (leftUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceLeft leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceLeft rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (rightUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceRight leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceRight rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (leftLeft : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surfaceLeft (.scalar leftLeftType)
      (.scalar leftLeftType) leftCoreLeft)
    (leftRight : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surfaceRight (.scalar leftRightType)
      (.scalar leftRightType) leftCoreRight)
    (leftOperation : BinaryOperationSpecializes op leftLeftType leftRightType
      leftCoreLeft leftCoreRight leftOutput leftCore)
    (rightLeft : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surfaceLeft (.scalar rightLeftType)
      (.scalar rightLeftType) rightCoreLeft)
    (rightRight : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surfaceRight (.scalar rightRightType)
      (.scalar rightRightType) rightCoreRight)
    (rightOperation : BinaryOperationSpecializes op rightLeftType rightRightType
      rightCoreLeft rightCoreRight rightOutput rightCore) :
    leftOutput = rightOutput ∧ leftCore = rightCore := by
  rcases leftUnique leftLeft rightLeft with
    ⟨leftTypeEquality, leftGroundEquality, leftCoreEquality⟩
  injection leftTypeEquality with leftScalarEquality
  injection leftGroundEquality with leftGroundScalarEquality
  cases leftScalarEquality
  cases leftGroundScalarEquality
  cases leftCoreEquality
  rcases rightUnique leftRight rightRight with
    ⟨rightTypeEquality, rightGroundEquality, rightCoreEquality⟩
  injection rightTypeEquality with rightScalarEquality
  injection rightGroundEquality with rightGroundScalarEquality
  cases rightScalarEquality
  cases rightGroundScalarEquality
  cases rightCoreEquality
  rcases leftOperation.unique rightOperation with
    ⟨outputEquality, coreEquality⟩
  exact ⟨outputEquality, coreEquality⟩

private theorem scalarInference_aligns_with_rawPointer
    (surfaceUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surface leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surface rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (scalar : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surface (.scalar scalarType)
      (.scalar scalarType) scalarCore)
    (pointer : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surface (.scalar .rawPtr) (.scalar .rawPtr)
      pointerCore) :
    scalarType = .rawPtr ∧ scalarCore = pointerCore := by
  rcases surfaceUnique scalar pointer with
    ⟨typeEquality, _groundEquality, coreEquality⟩
  injection typeEquality with scalarEquality
  exact ⟨scalarEquality, coreEquality⟩

private theorem rawPointerInference_core_unique
    (surfaceUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surface leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surface rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surface (.scalar .rawPtr) (.scalar .rawPtr)
      leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surface (.scalar .rawPtr) (.scalar .rawPtr)
      rightCore) :
    leftCore = rightCore := (surfaceUnique left right).2.2

/-- Exact binary inference is functional. Ordinary coercion modes emit one
    cast placement, contextual null-pointer literals are disjoint from ordinary
    `i32` literal inference, and the left-null and right-null rules cannot both
    apply to one occurrence. -/
theorem ExprInferenceDerivationSpecializes.binary_unique_of_expr
    (leftUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceLeft leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceLeft rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (rightUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceRight leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceRight rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.binary op surfaceLeft surfaceRight)
      leftSymbolic leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.binary op surfaceLeft surfaceRight)
      rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases left with
  | binaryExact leftLeft leftRight leftTyped =>
      cases right with
      | binaryExact rightLeft rightRight rightTyped =>
          rcases binaryOperationDerivations_unique_of_expr leftUnique rightUnique
              leftLeft leftRight (.exact leftTyped) rightLeft rightRight
              (.exact rightTyped) with ⟨rfl, coreEquality⟩
          exact ⟨rfl, rfl, coreEquality⟩
      | binaryNullPointerRight rightPointer rightNull rightTyped =>
          cases leftRight with
          | literal leftLiteral =>
              rcases scalarInference_aligns_with_rawPointer leftUnique leftLeft
                  rightPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.exact leftTyped)
                |>.incompatible_with_null_right rightTyped).elim
      | binaryNullPointerLeft rightNull rightPointer rightTyped =>
          cases leftLeft with
          | literal leftLiteral =>
              rcases scalarInference_aligns_with_rawPointer rightUnique leftRight
                  rightPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.exact leftTyped)
                |>.incompatible_with_null_left rightTyped).elim
      | binaryRightCast rightLeft rightRight rightDifferent rightNotPreferred
          rightConversion rightTyped =>
          rcases binaryOperationDerivations_unique_of_expr leftUnique rightUnique
              leftLeft leftRight (.exact leftTyped) rightLeft rightRight
              (.rightCast rightDifferent rightNotPreferred rightConversion
                rightTyped) with ⟨rfl, coreEquality⟩
          exact ⟨rfl, rfl, coreEquality⟩
      | binaryLeftCast rightLeft rightRight rightPreferred rightConversion
          rightTyped =>
          rcases binaryOperationDerivations_unique_of_expr leftUnique rightUnique
              leftLeft leftRight (.exact leftTyped) rightLeft rightRight
              (.leftCast rightPreferred rightConversion rightTyped) with
            ⟨rfl, coreEquality⟩
          exact ⟨rfl, rfl, coreEquality⟩
  | binaryNullPointerRight leftPointer leftNull leftTyped =>
      cases right with
      | binaryExact rightLeft rightRight rightTyped =>
          cases rightRight with
          | literal rightLiteral =>
              rcases scalarInference_aligns_with_rawPointer leftUnique rightLeft
                  leftPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.exact rightTyped)
                |>.incompatible_with_null_right leftTyped).elim
      | binaryNullPointerRight rightPointer rightNull rightTyped =>
          cases rawPointerInference_core_unique leftUnique leftPointer rightPointer
          cases leftNull.core_unique rightNull
          have outputEquality := leftTyped.output_unique rightTyped
          injection outputEquality with scalarEquality
          cases scalarEquality
          exact ⟨rfl, rfl, rfl⟩
      | binaryNullPointerLeft rightNull rightPointer rightTyped =>
          exact leftPointer.literal_not_raw_pointer.elim
      | binaryRightCast rightLeft rightRight rightDifferent rightNotPreferred
          rightConversion rightTyped =>
          cases rightRight with
          | literal rightLiteral =>
              rcases scalarInference_aligns_with_rawPointer leftUnique rightLeft
                  leftPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.rightCast rightDifferent
                rightNotPreferred rightConversion rightTyped)
                |>.incompatible_with_null_right leftTyped).elim
      | binaryLeftCast rightLeft rightRight rightPreferred rightConversion
          rightTyped =>
          cases rightRight with
          | literal rightLiteral =>
              rcases scalarInference_aligns_with_rawPointer leftUnique rightLeft
                  leftPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.leftCast rightPreferred
                rightConversion rightTyped)
                |>.incompatible_with_null_right leftTyped).elim
  | binaryNullPointerLeft leftNull leftPointer leftTyped =>
      cases right with
      | binaryExact rightLeft rightRight rightTyped =>
          cases rightLeft with
          | literal rightLiteral =>
              rcases scalarInference_aligns_with_rawPointer rightUnique rightRight
                  leftPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.exact rightTyped)
                |>.incompatible_with_null_left leftTyped).elim
      | binaryNullPointerRight rightPointer rightNull rightTyped =>
          exact rightPointer.literal_not_raw_pointer.elim
      | binaryNullPointerLeft rightNull rightPointer rightTyped =>
          cases leftNull.core_unique rightNull
          cases rawPointerInference_core_unique rightUnique leftPointer rightPointer
          have outputEquality := leftTyped.output_unique rightTyped
          injection outputEquality with scalarEquality
          cases scalarEquality
          exact ⟨rfl, rfl, rfl⟩
      | binaryRightCast rightLeft rightRight rightDifferent rightNotPreferred
          rightConversion rightTyped =>
          cases rightLeft with
          | literal rightLiteral =>
              rcases scalarInference_aligns_with_rawPointer rightUnique rightRight
                  leftPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.rightCast rightDifferent
                rightNotPreferred rightConversion rightTyped)
                |>.incompatible_with_null_left leftTyped).elim
      | binaryLeftCast rightLeft rightRight rightPreferred rightConversion
          rightTyped =>
          cases rightLeft with
          | literal rightLiteral =>
              rcases scalarInference_aligns_with_rawPointer rightUnique rightRight
                  leftPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.leftCast rightPreferred
                rightConversion rightTyped)
                |>.incompatible_with_null_left leftTyped).elim
  | binaryRightCast leftLeft leftRight leftDifferent leftNotPreferred
      leftConversion leftTyped =>
      cases right with
      | binaryExact rightLeft rightRight rightTyped =>
          rcases binaryOperationDerivations_unique_of_expr leftUnique rightUnique
              leftLeft leftRight (.rightCast leftDifferent leftNotPreferred
                leftConversion leftTyped) rightLeft rightRight
              (.exact rightTyped) with ⟨rfl, coreEquality⟩
          exact ⟨rfl, rfl, coreEquality⟩
      | binaryNullPointerRight rightPointer rightNull rightTyped =>
          cases leftRight with
          | literal leftLiteral =>
              rcases scalarInference_aligns_with_rawPointer leftUnique leftLeft
                  rightPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.rightCast leftDifferent
                leftNotPreferred leftConversion leftTyped)
                |>.incompatible_with_null_right rightTyped).elim
      | binaryNullPointerLeft rightNull rightPointer rightTyped =>
          cases leftLeft with
          | literal leftLiteral =>
              rcases scalarInference_aligns_with_rawPointer rightUnique leftRight
                  rightPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.rightCast leftDifferent
                leftNotPreferred leftConversion leftTyped)
                |>.incompatible_with_null_left rightTyped).elim
      | binaryRightCast rightLeft rightRight rightDifferent rightNotPreferred
          rightConversion rightTyped =>
          rcases binaryOperationDerivations_unique_of_expr leftUnique rightUnique
              leftLeft leftRight (.rightCast leftDifferent leftNotPreferred
                leftConversion leftTyped) rightLeft rightRight
              (.rightCast rightDifferent rightNotPreferred rightConversion
                rightTyped) with ⟨rfl, coreEquality⟩
          exact ⟨rfl, rfl, coreEquality⟩
      | binaryLeftCast rightLeft rightRight rightPreferred rightConversion
          rightTyped =>
          rcases binaryOperationDerivations_unique_of_expr leftUnique rightUnique
              leftLeft leftRight (.rightCast leftDifferent leftNotPreferred
                leftConversion leftTyped) rightLeft rightRight
              (.leftCast rightPreferred rightConversion rightTyped) with
            ⟨rfl, coreEquality⟩
          exact ⟨rfl, rfl, coreEquality⟩
  | binaryLeftCast leftLeft leftRight leftPreferred leftConversion leftTyped =>
      cases right with
      | binaryExact rightLeft rightRight rightTyped =>
          rcases binaryOperationDerivations_unique_of_expr leftUnique rightUnique
              leftLeft leftRight (.leftCast leftPreferred leftConversion leftTyped)
              rightLeft rightRight (.exact rightTyped) with
            ⟨rfl, coreEquality⟩
          exact ⟨rfl, rfl, coreEquality⟩
      | binaryNullPointerRight rightPointer rightNull rightTyped =>
          cases leftRight with
          | literal leftLiteral =>
              rcases scalarInference_aligns_with_rawPointer leftUnique leftLeft
                  rightPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.leftCast leftPreferred
                leftConversion leftTyped)
                |>.incompatible_with_null_right rightTyped).elim
      | binaryNullPointerLeft rightNull rightPointer rightTyped =>
          cases leftLeft with
          | literal leftLiteral =>
              rcases scalarInference_aligns_with_rawPointer rightUnique leftRight
                  rightPointer with ⟨rfl, rfl⟩
              exact ((SymbolicBinaryHasType.leftCast leftPreferred
                leftConversion leftTyped)
                |>.incompatible_with_null_left rightTyped).elim
      | binaryRightCast rightLeft rightRight rightDifferent rightNotPreferred
          rightConversion rightTyped =>
          rcases binaryOperationDerivations_unique_of_expr leftUnique rightUnique
              leftLeft leftRight (.leftCast leftPreferred leftConversion leftTyped)
              rightLeft rightRight (.rightCast rightDifferent rightNotPreferred
                rightConversion rightTyped) with ⟨rfl, coreEquality⟩
          exact ⟨rfl, rfl, coreEquality⟩
      | binaryLeftCast rightLeft rightRight rightPreferred rightConversion
          rightTyped =>
          rcases binaryOperationDerivations_unique_of_expr leftUnique rightUnique
              leftLeft leftRight (.leftCast leftPreferred leftConversion leftTyped)
              rightLeft rightRight (.leftCast rightPreferred rightConversion
                rightTyped) with ⟨rfl, coreEquality⟩
          exact ⟨rfl, rfl, coreEquality⟩

/-- Exact inference over an expression list is functional whenever exact
    inference of each element is functional. Keeping this structural list
    argument outside the generated mutual recursor avoids duplicating list
    traversal in every expression proof. -/
theorem ExprListInferenceDerivationSpecializes.unique_of_expr
    (exprUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : ExprListInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surfaces leftSymbolic leftGround leftCore)
    (right : ExprListInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surfaces rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  induction surfaces generalizing leftSymbolic leftGround leftCore
      rightSymbolic rightGround rightCore with
  | nil =>
      cases left
      cases right
      exact ⟨rfl, rfl, rfl⟩
  | cons surfaceHead surfaceTail induction =>
      cases left with
      | cons leftHead leftTail =>
          cases right with
          | cons rightHead rightTail =>
              rcases exprUnique leftHead rightHead with ⟨rfl, rfl, rfl⟩
              rcases induction leftTail rightTail with ⟨rfl, rfl, rfl⟩
              exact ⟨rfl, rfl, rfl⟩

/-- Contextual checking over an expression list inherits functionality from
    checking one expression at a fixed expected symbolic type. -/
theorem ExprListCheckingDerivationSpecializes.unique_of_expr
    (exprUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : ExprListCheckingDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surfaces expectedTypes leftGround leftCore)
    (right : ExprListCheckingDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surfaces expectedTypes rightGround rightCore) :
    leftGround = rightGround ∧ leftCore = rightCore := by
  induction surfaces generalizing expectedTypes leftGround leftCore rightGround
      rightCore with
  | nil =>
      cases left
      cases right
      exact ⟨rfl, rfl⟩
  | cons surfaceHead surfaceTail induction =>
      cases left with
      | cons leftHead leftTail =>
          cases right with
          | cons rightHead rightTail =>
              rcases exprUnique leftHead rightHead with ⟨rfl, rfl⟩
              rcases induction leftTail rightTail with ⟨rfl, rfl⟩
              exact ⟨rfl, rfl⟩

/-- Checking the same expression against arrays with one fixed element type
    determines the source length as well as the ground type and emitted Core.
    This covers both exact inference and contextual array checking, so clients
    such as `i32_array_data_ptr` do not need to choose a checking mode first. -/
theorem ExprCheckingDerivationSpecializes.array_unique_of_expr
    (inferUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surface leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surface rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (checkUnique : ∀ {expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surface expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surface expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : ExprCheckingDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surface (.array elementType leftLength)
      leftGround leftCore)
    (right : ExprCheckingDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts surface (.array elementType rightLength)
      rightGround rightCore) :
    leftLength = rightLength ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases left with
  | exact leftInferred _leftSymbolic _leftGrounds _leftConcrete =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          rcases inferUnique leftInferred rightInferred with
            ⟨typeEquality, groundEquality, coreEquality⟩
          injection typeEquality with _elementEquality lengthEquality
          exact ⟨lengthEquality, groundEquality, coreEquality⟩
      | array rightElements rightSymbolicElements rightConcreteElements
          rightElementGrounds rightElementCore =>
          cases leftInferred with
          | array leftHead leftTail leftElementCore =>
              have leftCheck :=
                (ExprInferenceDerivationSpecializes.array leftHead leftTail
                  leftElementCore).asChecking
              have rightCheck :=
                ExprCheckingDerivationSpecializes.array rightElements
                  rightSymbolicElements rightConcreteElements
                  rightElementGrounds rightElementCore
              obtain ⟨groundEquality, coreEquality⟩ :=
                checkUnique leftCheck rightCheck
              exact ⟨rfl, groundEquality, coreEquality⟩
      | structValue _selected expected _arguments _typeArgumentsGround
          _constArgumentsGround _pathArguments _requirements _artifact _fields
          _symbolicFields _concreteFields =>
          cases expected
      | variantCall _selected _notIntrinsic expected _arguments
          _typeArgumentsGround _constArgumentsGround _pathArguments
          _requirements _artifact _payload _symbolicPayload _concretePayload =>
          cases expected
  | array leftElements leftSymbolicElements leftConcreteElements
      leftElementGrounds leftElementCore =>
      cases right with
      | exact rightInferred _rightSymbolic _rightGrounds _rightConcrete =>
          cases rightInferred with
          | array rightHead rightTail rightElementCore' =>
              have leftCheck :=
                ExprCheckingDerivationSpecializes.array leftElements
                  leftSymbolicElements leftConcreteElements leftElementGrounds
                  leftElementCore
              have rightCheck :=
                (ExprInferenceDerivationSpecializes.array rightHead rightTail
                  rightElementCore').asChecking
              obtain ⟨groundEquality, coreEquality⟩ :=
                checkUnique leftCheck rightCheck
              exact ⟨rfl, groundEquality, coreEquality⟩
      | array rightElements rightSymbolicElements rightConcreteElements
          rightElementGrounds rightElementCore =>
          have groundElementEquality := Option.some.inj
            (leftElementGrounds.symm.trans rightElementGrounds)
          cases groundElementEquality
          have coreElementEquality := Option.some.inj
            (leftElementCore.symm.trans rightElementCore)
          cases coreElementEquality
          have leftCheck := ExprCheckingDerivationSpecializes.array leftElements
            leftSymbolicElements leftConcreteElements leftElementGrounds
            leftElementCore
          have rightCheck := ExprCheckingDerivationSpecializes.array rightElements
            rightSymbolicElements rightConcreteElements rightElementGrounds
            rightElementCore
          obtain ⟨groundEquality, coreEquality⟩ :=
            checkUnique leftCheck rightCheck
          exact ⟨rfl, groundEquality, coreEquality⟩
  | structValue _selected expected _arguments _typeArgumentsGround
      _constArgumentsGround _pathArguments _requirements _artifact _fields
      _symbolicFields _concreteFields =>
      cases expected
  | variantCall _selected _notIntrinsic expected _arguments
      _typeArgumentsGround _constArgumentsGround _pathArguments _requirements
      _artifact _payload _symbolicPayload _concretePayload =>
      cases expected

/-- A reserved intrinsic path-call has one exact result. The path fixes which
    intrinsic applies; ordinary functions and variants are unavailable by
    intrinsic precedence. Array-pointer calls additionally use contextual
    array functionality to recover their otherwise existential length. -/
theorem ExprInferenceDerivationSpecializes.intrinsicPathCall_unique_of_expr
    (inferUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (resolved : PathCallResolvesAs symbolic path .intrinsic)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      leftSymbolic leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.call (.path path) surfaceArguments)
      rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases resolved with
  | intrinsic found =>
      cases left with
      | printI32 leftBuiltin leftArgument =>
          cases right with
          | printI32 _rightBuiltin rightArgument =>
              obtain ⟨_groundEquality, coreEquality⟩ :=
                checkUnique leftArgument rightArgument
              exact ⟨rfl, rfl, congrArg
                (fun argument => Core.Expr.intrinsic .printI32 argument)
                coreEquality⟩
          | assert rightBuiltin _rightArgument =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | i32ArrayDataPtr rightBuiltin _rightArgument =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | i32SliceDataPtr rightBuiltin _ =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | stringDataPtr rightBuiltin _ =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | variantExplicit evidence _payload =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | variantInferred evidence _payload =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | variantNongeneric evidence _payload =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallInferred evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallExplicit evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallNongeneric evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | associatedCallInferred evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | associatedCallContextual evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
      | assert leftBuiltin leftArgument =>
          cases right with
          | printI32 rightBuiltin _rightArgument =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | assert _rightBuiltin rightArgument =>
              obtain ⟨_groundEquality, coreEquality⟩ :=
                checkUnique leftArgument rightArgument
              exact ⟨rfl, rfl, congrArg
                (fun argument => Core.Expr.intrinsic .assert argument)
                coreEquality⟩
          | i32ArrayDataPtr rightBuiltin _rightArgument =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | i32SliceDataPtr rightBuiltin _ =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | stringDataPtr rightBuiltin _ =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | variantExplicit evidence _payload =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | variantInferred evidence _payload =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | variantNongeneric evidence _payload =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallInferred evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallExplicit evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallNongeneric evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | associatedCallInferred evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | associatedCallContextual evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
      | i32ArrayDataPtr leftBuiltin leftArgument =>
          cases right with
          | printI32 rightBuiltin _rightArgument =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | assert rightBuiltin _rightArgument =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | i32ArrayDataPtr _rightBuiltin rightArgument =>
              obtain ⟨_lengthEquality, _groundEquality, coreEquality⟩ :=
                ExprCheckingDerivationSpecializes.array_unique_of_expr
                  inferUnique checkUnique leftArgument rightArgument
              exact ⟨rfl, rfl, congrArg Core.Expr.i32ArrayDataPtr coreEquality⟩
          | i32SliceDataPtr rightBuiltin _ =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | stringDataPtr rightBuiltin _ =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | variantExplicit evidence _payload =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | variantInferred evidence _payload =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | variantNongeneric evidence _payload =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallInferred evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallExplicit evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallNongeneric evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | associatedCallInferred evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | associatedCallContextual evidence _arguments =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
      | i32SliceFromRawParts leftBuiltin leftPointer leftLength =>
          cases right with
          | i32SliceFromRawParts _ rightPointer rightLength =>
              obtain ⟨_, pointerEquality⟩ := checkUnique leftPointer rightPointer
              obtain ⟨_, lengthEquality⟩ := checkUnique leftLength rightLength
              cases pointerEquality
              cases lengthEquality
              exact ⟨rfl, rfl, rfl⟩
          | variantExplicit evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | variantInferred evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | variantNongeneric evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallInferred evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallExplicit evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallNongeneric evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | associatedCallInferred evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | associatedCallContextual evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
      | i32SliceDataPtr leftBuiltin leftSlice =>
          cases right with
          | printI32 rightBuiltin _ =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | assert rightBuiltin _ =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | i32ArrayDataPtr rightBuiltin _ =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | stringDataPtr rightBuiltin _ =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | i32SliceDataPtr _ rightSlice =>
              obtain ⟨_, coreEquality⟩ := checkUnique leftSlice rightSlice
              exact ⟨rfl, rfl, congrArg Core.Expr.i32SliceDataPtr coreEquality⟩
          | variantExplicit evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | variantInferred evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | variantNongeneric evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallInferred evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallExplicit evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallNongeneric evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | associatedCallInferred evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | associatedCallContextual evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
      | stringDataPtr leftBuiltin leftString =>
          cases right with
          | printI32 rightBuiltin _ =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | assert rightBuiltin _ =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | i32ArrayDataPtr rightBuiltin _ =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | i32SliceDataPtr rightBuiltin _ =>
              cases Option.some.inj (leftBuiltin.symm.trans rightBuiltin)
          | stringDataPtr _ rightString =>
              obtain ⟨_, coreEquality⟩ := checkUnique leftString rightString
              exact ⟨rfl, rfl, congrArg Core.Expr.stringDataPtr coreEquality⟩
          | variantExplicit evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | variantInferred evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | variantNongeneric evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallInferred evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallExplicit evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | directCallNongeneric evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | associatedCallInferred evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
          | associatedCallContextual evidence _ =>
              exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none
                found evidence.notIntrinsic).elim
      | variantExplicit evidence _payload =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none found
            evidence.notIntrinsic).elim
      | variantInferred evidence _payload =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none found
            evidence.notIntrinsic).elim
      | variantNongeneric evidence _payload =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none found
            evidence.notIntrinsic).elim
      | directCallInferred evidence _arguments =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none found
            evidence.notIntrinsic).elim
      | directCallExplicit evidence _arguments =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none found
            evidence.notIntrinsic).elim
      | directCallNongeneric evidence _arguments =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none found
            evidence.notIntrinsic).elim
      | associatedCallInferred evidence _arguments =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none found
            evidence.notIntrinsic).elim
      | associatedCallContextual evidence _arguments =>
          exact (SurfaceElaboration.builtinIntrinsic_some_excludes_none found
            evidence.notIntrinsic).elim

/-- Nonempty array inference is functional once inference of its head and
    contextual checking of its tail are functional. The Core element type is
    also fixed because ground-type lowering is an ordinary function. -/
theorem ExprInferenceDerivationSpecializes.array_unique_of_expr
    (inferUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.array surfaceElements) leftSymbolic
      leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.array surfaceElements) rightSymbolic
      rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases left with
  | array leftHead leftTail leftElementCore =>
      cases right with
      | array rightHead rightTail rightElementCore =>
          rcases inferUnique leftHead rightHead with ⟨rfl, rfl, rfl⟩
          obtain ⟨_groundTailEquality, coreTailEquality⟩ :=
            ExprListCheckingDerivationSpecializes.unique_of_expr checkUnique
              leftTail rightTail
          cases coreTailEquality
          have coreElementEquality := Option.some.inj
            (leftElementCore.symm.trans rightElementCore)
          cases coreElementEquality
          exact ⟨rfl, rfl, rfl⟩

/-- Substituted argument checking has no hidden choice: substitution is a
    function, each checked head is functional, and the tail is structural. -/
theorem ExprListSubstitutedCheckingDerivationSpecializes.unique_of_expr
    (exprUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts inner surfaces
      originalTypes leftCore)
    (right : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts inner surfaces
      originalTypes rightCore) :
    leftCore = rightCore := by
  induction surfaces generalizing originalTypes leftCore rightCore with
  | nil =>
      cases left
      cases right
      rfl
  | cons surfaceHead surfaceTail induction =>
      cases left with
      | cons leftSubstituted leftHead leftTail _leftSymbolic _leftConcrete =>
          cases right with
          | cons rightSubstituted rightHead rightTail _rightSymbolic
              _rightConcrete =>
              have expectedEquality := Option.some.inj
                (leftSubstituted.symm.trans rightSubstituted)
              cases expectedEquality
              rcases exprUnique leftHead rightHead with ⟨rfl, rfl⟩
              cases induction leftTail rightTail
              rfl

theorem ExprListSubstitutedCheckingDerivationSpecializes.substitutedTypes
    (derivation : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts inner surfaces
      originalTypes cores) :
    ∃ expectedTypes,
      Static.substituteTypes inner originalTypes = some expectedTypes := by
  induction originalTypes generalizing surfaces cores with
  | nil =>
      cases derivation
      exact ⟨[], rfl⟩
  | cons originalHead originalTail induction =>
      cases derivation with
      | cons substituted head tail _tailSymbolic _tailConcrete =>
          rename_i expectedHead surfaceHead groundHead coreHead surfaceTail
            coreTail
          obtain ⟨tailTypes, tailSubstituted⟩ := induction tail
          exact ⟨expectedHead :: tailTypes, by
            simp [Static.substituteTypes, substituted, tailSubstituted]⟩

/-- Substituted list checking depends only on the substituted expected-type
    list, not on unrelated entries in the two substitution maps. -/
theorem ExprListSubstitutedCheckingDerivationSpecializes.unique_of_expr_and_substitution
    (exprUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner surfaces
      originalTypes leftCore)
    (right : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner surfaces
      originalTypes rightCore)
    (substitutionsAgree : Static.substituteTypes leftInner originalTypes =
      Static.substituteTypes rightInner originalTypes) :
    leftCore = rightCore := by
  induction originalTypes generalizing surfaces leftCore rightCore with
  | nil =>
      cases left
      cases right
      rfl
  | cons originalHead originalTail induction =>
      cases left with
      | cons leftSubstituted leftHead leftTail _leftSymbolic _leftConcrete =>
          cases right with
          | cons rightSubstituted rightHead rightTail _rightSymbolic
              _rightConcrete =>
              rename_i leftExpectedHead surfaceHead leftGroundHead leftCoreHead
                surfaceTail leftCoreTail rightExpectedHead rightGroundHead
                rightCoreHead rightCoreTail
              obtain ⟨leftTailTypes, leftTailSubstituted⟩ :=
                leftTail.substitutedTypes
              obtain ⟨rightTailTypes, rightTailSubstituted⟩ :=
                rightTail.substitutedTypes
              have expectedListsEquality :
                  leftExpectedHead :: leftTailTypes =
                    rightExpectedHead :: rightTailTypes := by
                have sameSome : some (leftExpectedHead :: leftTailTypes) =
                    some (rightExpectedHead :: rightTailTypes) := by
                  simpa [Static.substituteTypes, leftSubstituted,
                    rightSubstituted, leftTailSubstituted,
                    rightTailSubstituted] using substitutionsAgree
                exact Option.some.inj sameSome
              injection expectedListsEquality with headEquality tailEquality
              cases headEquality
              cases tailEquality
              rcases exprUnique leftHead rightHead with ⟨rfl, rfl⟩
              have tailSubstitutionsAgree :
                  Static.substituteTypes leftInner originalTail =
                    Static.substituteTypes rightInner originalTail :=
                leftTailSubstituted.trans rightTailSubstituted.symm
              cases induction leftTail rightTail tailSubstitutionsAgree
              rfl

/-- Named struct-field checking is functional once expression checking is:
    first-match field removal and retained-type substitution are themselves
    functions. -/
theorem StructFieldsCheckingDerivationSpecializes.unique_of_expr
    (exprUnique : ∀ {name surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      (name, surfaceExpr) ∈ surfaceFields →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts inner fields
      surfaceFields leftCore)
    (right : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts inner fields
      surfaceFields rightCore) :
    leftCore = rightCore := by
  induction fields generalizing surfaceFields leftCore rightCore with
  | nil =>
      cases left
      cases right
      rfl
  | cons field fieldTail induction =>
      cases left with
      | cons leftRemoved leftSubstituted leftValue leftTail _leftSymbolic
          _leftConcrete =>
          cases right with
          | cons rightRemoved rightSubstituted rightValue rightTail
              _rightSymbolic _rightConcrete =>
              rcases leftRemoved.unique rightRemoved with ⟨rfl, rfl⟩
              have expectedEquality := Option.some.inj
                (leftSubstituted.symm.trans rightSubstituted)
              cases expectedEquality
              rcases exprUnique leftRemoved.selected_mem leftValue rightValue with
                ⟨rfl, rfl⟩
              cases induction (fun member =>
                  exprUnique (leftRemoved.remainder_subset _ member))
                leftTail rightTail
              rfl

/-- Struct-field checking remains functional across two substitution maps that
    bind the same ordered constructor arguments. Complete declaration
    provenance ensures every retained field type substitutes identically. -/
theorem StructFieldsCheckingDerivationSpecializes.unique_of_expr_and_arguments
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (exprUnique : ∀ {name surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      (name, surfaceExpr) ∈ surfaceFields →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (constructorMember : constructor ∈ symbolic.globals.structConstructors)
    (fieldsBelong : ∀ field, field ∈ fields → field ∈ constructor.fields)
    (leftBound : Static.SymbolicArgumentsBound leftInner
      constructor.genericParameters typeArguments constArguments)
    (rightBound : Static.SymbolicArgumentsBound rightInner
      constructor.genericParameters typeArguments constArguments)
    (left : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner fields
      surfaceFields leftCore)
    (right : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner fields
      surfaceFields rightCore) :
    leftCore = rightCore := by
  induction fields generalizing surfaceFields leftCore rightCore with
  | nil =>
      cases left
      cases right
      rfl
  | cons field fieldTail induction =>
      cases left with
      | cons leftRemoved leftSubstituted leftValue leftTail _leftSymbolic
          _leftConcrete =>
          cases right with
          | cons rightRemoved rightSubstituted rightValue rightTail
              _rightSymbolic _rightConcrete =>
              rcases leftRemoved.unique rightRemoved with ⟨rfl, rfl⟩
              have expectedEquality :=
                complete.structFieldSubstitute_unique constructorMember
                  (fieldsBelong field (by simp)) leftBound rightBound
                  leftSubstituted rightSubstituted
              cases expectedEquality
              rcases exprUnique leftRemoved.selected_mem leftValue rightValue with
                ⟨rfl, rfl⟩
              have tailBelongs : ∀ candidate,
                  candidate ∈ fieldTail → candidate ∈ constructor.fields := by
                intro candidate member
                exact fieldsBelong candidate (by simp [member])
              cases induction (fun member =>
                  exprUnique (leftRemoved.remainder_subset _ member)) tailBelongs
                leftTail rightTail
              rfl

/-- Named struct-field inference likewise reduces to functional first-match
    removal, functional expression inference, and the structural tail. -/
theorem StructFieldsInferenceDerivationSpecializes.unique_of_expr
    (exprUnique : ∀ {name surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      (name, surfaceExpr) ∈ surfaceFields →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner fields
      surfaceFields leftCore)
    (right : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner fields
      surfaceFields rightCore) :
    leftCore = rightCore := by
  induction fields generalizing surfaceFields leftCore rightCore with
  | nil =>
      cases left
      cases right
      rfl
  | cons field fieldTail induction =>
      cases left with
      | cons leftRemoved leftValue leftMatched leftTail _leftSymbolic
          _leftConcrete =>
          cases right with
          | cons rightRemoved rightValue rightMatched rightTail _rightSymbolic
              _rightConcrete =>
              rcases leftRemoved.unique rightRemoved with ⟨rfl, rfl⟩
              rcases exprUnique leftRemoved.selected_mem leftValue rightValue with
                ⟨rfl, rfl, rfl⟩
              cases induction (fun member =>
                  exprUnique (leftRemoved.remainder_subset _ member))
                leftTail rightTail
              rfl

/-- Field inference and contextual field checking emit the same Core values
    when their constructor substitutions bind the same ordered arguments. The
    inferred match is converted to an exact check only after declaration
    provenance proves that its observed type is the contextual field type. -/
theorem StructFieldsInferenceDerivationSpecializes.core_unique_of_expr_and_checked
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (exprUnique : ∀ {name surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      (name, surfaceExpr) ∈ surfaceFields →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (constructorMember : constructor ∈ symbolic.globals.structConstructors)
    (fieldsBelong : ∀ field, field ∈ fields → field ∈ constructor.fields)
    (inferredBound : Static.SymbolicArgumentsBound inferredInner
      constructor.genericParameters typeArguments constArguments)
    (checkedBound : Static.SymbolicArgumentsBound checkedInner
      constructor.genericParameters typeArguments constArguments)
    (inferred : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts inferredInner fields
      surfaceFields inferredCore)
    (checked : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts checkedInner fields
      surfaceFields checkedCore) :
    inferredCore = checkedCore := by
  induction fields generalizing surfaceFields inferredCore checkedCore with
  | nil =>
      cases inferred
      cases checked
      rfl
  | cons field fieldTail induction =>
      cases inferred with
      | cons inferredRemoved inferredValue inferredMatched inferredTail
          _inferredSymbolic _inferredConcrete =>
          cases checked with
          | cons checkedRemoved checkedSubstituted checkedValue checkedTail
              _checkedSymbolic _checkedConcrete =>
              rcases inferredRemoved.unique checkedRemoved with ⟨rfl, rfl⟩
              have expectedEquality :=
                complete.structFieldSubstitute_unique constructorMember
                  (fieldsBelong field (by simp)) inferredBound checkedBound
                  inferredMatched.substitutes checkedSubstituted
              cases expectedEquality
              rcases exprUnique inferredRemoved.selected_mem
                  inferredValue.asChecking checkedValue with ⟨rfl, rfl⟩
              have tailBelongs : ∀ candidate,
                  candidate ∈ fieldTail → candidate ∈ constructor.fields := by
                intro candidate member
                exact fieldsBelong candidate (by simp [member])
              cases induction
                (fun member => exprUnique
                  (inferredRemoved.remainder_subset _ member))
                tailBelongs inferredTail checkedTail
              rfl

/-- Two inferred field traversals expose matching derivations for the same
    declared field occurrence. This is the struct analogue of aligned list
    matching: named-field removal and recursive expression functionality first
    align the observed field type, after which the two substitutions can be
    compared on that occurrence. -/
theorem StructFieldsInferenceDerivationSpecializes.aligned_member_of_expr
    (exprUnique : ∀ {name surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      (name, surfaceExpr) ∈ surfaceFields →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner fields
      surfaceFields leftCore)
    (right : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner fields
      surfaceFields rightCore)
    (member : field ∈ fields) :
    ∃ actualType,
      Static.TySymbolicallyMatches leftInner field.type actualType ∧
      Static.TySymbolicallyMatches rightInner field.type actualType := by
  induction fields generalizing surfaceFields leftCore rightCore field with
  | nil => simp at member
  | cons fieldHead fieldTail induction =>
      cases left with
      | cons leftRemoved leftValue leftMatched leftTail _leftSymbolic
          _leftConcrete =>
          cases right with
          | cons rightRemoved rightValue rightMatched rightTail _rightSymbolic
              _rightConcrete =>
              rcases leftRemoved.unique rightRemoved with ⟨rfl, rfl⟩
              rcases exprUnique leftRemoved.selected_mem leftValue rightValue with
                ⟨rfl, rfl, rfl⟩
              simp only [List.mem_cons] at member
              rcases member with rfl | member
              · exact ⟨_, leftMatched, rightMatched⟩
              · exact induction
                  (fun selected =>
                    exprUnique (leftRemoved.remainder_subset _ selected))
                  leftTail rightTail member

/-- Field-driven inference fixes the ordered constructor arguments whenever
    the constructor's occurrence condition covers every generic parameter. -/
theorem StructFieldsInferenceDerivationSpecializes.orderedArguments_unique
    (exprUnique : ∀ {name surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      (name, surfaceExpr) ∈ surfaceFields →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (determined : SurfaceElaboration.TypesDetermineGenericParameters
      (fields.map fun field => field.type) parameters)
    (left : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner fields
      surfaceFields leftCore)
    (right : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner fields
      surfaceFields rightCore)
    (leftBound : Static.SymbolicArgumentsBound leftInner parameters
      leftTypeArguments leftConstArguments)
    (rightBound : Static.SymbolicArgumentsBound rightInner parameters
      rightTypeArguments rightConstArguments) :
    leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments := by
  apply leftBound.orderedArguments_unique_of_agreement rightBound
  · intro parameter parameterMember
    obtain ⟨pattern, patternMember, mentioned⟩ :=
      determined (.typeParameter parameter) parameterMember
    obtain ⟨field, fieldMember, fieldTypeEquality⟩ :=
      List.mem_map.mp patternMember
    cases fieldTypeEquality
    obtain ⟨_, leftMatched, rightMatched⟩ :=
      left.aligned_member_of_expr exprUnique right fieldMember
    exact mentioned.substitution_agrees leftMatched rightMatched
  · intro parameter parameterMember
    obtain ⟨pattern, patternMember, mentioned⟩ :=
      determined (.constParameter parameter) parameterMember
    obtain ⟨field, fieldMember, fieldTypeEquality⟩ :=
      List.mem_map.mp patternMember
    cases fieldTypeEquality
    obtain ⟨_, leftMatched, rightMatched⟩ :=
      left.aligned_member_of_expr exprUnique right fieldMember
    exact mentioned.substitution_agrees leftMatched rightMatched

/-- A generic struct occurrence inferred from its fields has one exact result:
    constructor identity, ordered symbolic arguments, monomorphic artifact, and
    emitted field expressions are all functional. -/
theorem StructInferenceEvidence.results_unique_of_fields
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (exprUnique : ∀ {name surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      (name, surfaceExpr) ∈ surfaceFields →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : StructInferenceEvidence outer concrete symbolic path leftConstructor
      leftInner leftTypeArguments leftConstArguments leftResolved)
    (right : StructInferenceEvidence outer concrete symbolic path rightConstructor
      rightInner rightTypeArguments rightConstArguments rightResolved)
    (leftFields : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner
      leftConstructor.fields surfaceFields leftCoreFields)
    (rightFields : StructFieldsInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner
      rightConstructor.fields surfaceFields rightCoreFields) :
    leftConstructor = rightConstructor ∧
      leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments ∧
      leftResolved = rightResolved ∧ leftCoreFields = rightCoreFields := by
  have constructorEquality :=
    complete.structConstructor_unique left.selected right.selected
  cases constructorEquality
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    leftFields.orderedArguments_unique exprUnique left.determined rightFields
      left.nominal.arguments right.nominal.arguments
  have artifactEquality := complete.nominalEvidenceArtifact_unique contexts
    left.nominal right.nominal typeArgumentsEquality constArgumentsEquality
  have fieldsEquality := leftFields.unique_of_expr exprUnique rightFields
  exact ⟨rfl, typeArgumentsEquality, constArgumentsEquality,
    artifactEquality, fieldsEquality⟩

/-- Explicit struct arguments are fixed by their source syntax; complete
    field provenance then makes checking functional across the two finite
    substitution witnesses. -/
theorem StructExplicitEvidence.results_unique_of_fields
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (checkUnique : ∀ {name surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      (name, surfaceExpr) ∈ surfaceFields →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : StructExplicitEvidence outer concrete symbolic path leftConstructor
      leftInner leftTypeArguments leftConstArguments leftResolved)
    (right : StructExplicitEvidence outer concrete symbolic path rightConstructor
      rightInner rightTypeArguments rightConstArguments rightResolved)
    (leftFields : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner
      leftConstructor.fields surfaceFields leftCoreFields)
    (rightFields : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner
      rightConstructor.fields surfaceFields rightCoreFields) :
    leftConstructor = rightConstructor ∧
      leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments ∧
      leftResolved = rightResolved ∧ leftCoreFields = rightCoreFields := by
  have constructorEquality :=
    complete.structConstructor_unique left.selected right.selected
  cases constructorEquality
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    left.explicitArguments.orderedArguments_unique complete.metadataUnique
      right.explicitArguments left.nominal.arguments right.nominal.arguments
  cases typeArgumentsEquality
  cases constArgumentsEquality
  have artifactEquality := complete.nominalEvidenceArtifact_unique contexts
    left.nominal right.nominal rfl rfl
  have fieldsEquality :=
    leftFields.unique_of_expr_and_arguments complete checkUnique
      left.selected.member (fun _ member => member) left.nominal.arguments
      right.nominal.arguments rightFields
  exact ⟨rfl, rfl, rfl,
    artifactEquality, fieldsEquality⟩

/-- A nongeneric struct has empty ordered arguments by construction, but its
    two substitution witnesses may still differ outside the empty domain. -/
theorem StructNongenericEvidence.results_unique_of_fields
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (checkUnique : ∀ {name surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      (name, surfaceExpr) ∈ surfaceFields →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : StructNongenericEvidence outer concrete symbolic path leftConstructor
      leftInner leftResolved)
    (right : StructNongenericEvidence outer concrete symbolic path rightConstructor
      rightInner rightResolved)
    (leftFields : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner
      leftConstructor.fields surfaceFields leftCoreFields)
    (rightFields : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner
      rightConstructor.fields surfaceFields rightCoreFields) :
    leftConstructor = rightConstructor ∧ leftResolved = rightResolved ∧
      leftCoreFields = rightCoreFields := by
  have constructorEquality :=
    complete.structConstructor_unique left.selected right.selected
  cases constructorEquality
  have artifactEquality := complete.nominalEvidenceArtifact_unique contexts
    left.nominal right.nominal rfl rfl
  have fieldsEquality :=
    leftFields.unique_of_expr_and_arguments complete checkUnique
      left.selected.member (fun _ member => member) left.nominal.arguments
      right.nominal.arguments rightFields
  exact ⟨rfl, artifactEquality, fieldsEquality⟩

/-- All three struct-construction modes are mutually disjoint and internally
    functional. Explicit syntax cannot also be implicit, while inferred and
    nongeneric modes disagree on whether the selected constructor has generic
    parameters. -/
theorem ExprInferenceDerivationSpecializes.structValue_unique_of_expr
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (inferUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.structValue path surfaceFields)
      leftSymbolic leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.structValue path surfaceFields)
      rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases left with
  | structExplicit leftEvidence leftFields =>
      cases right with
      | structExplicit rightEvidence rightFields =>
          rcases leftEvidence.results_unique_of_fields complete
              (fun _member => checkUnique)
              rightEvidence leftFields rightFields with
            ⟨rfl, rfl, rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | structInferred rightEvidence rightFields =>
          exact (leftEvidence.explicitArguments.excludesNoGenericArguments
            rightEvidence.implicitArguments).elim
      | structNongeneric rightEvidence rightFields =>
          exact (leftEvidence.explicitArguments.excludesNoGenericArguments
            rightEvidence.implicitArguments).elim
  | structInferred leftEvidence leftFields =>
      cases right with
      | structExplicit rightEvidence rightFields =>
          exact (rightEvidence.explicitArguments.excludesNoGenericArguments
            leftEvidence.implicitArguments).elim
      | structInferred rightEvidence rightFields =>
          rcases leftEvidence.results_unique_of_fields complete
              (fun _member => inferUnique)
              rightEvidence leftFields rightFields with
            ⟨rfl, rfl, rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | structNongeneric rightEvidence rightFields =>
          have constructorEquality := complete.structConstructor_unique
            leftEvidence.selected rightEvidence.selected
          cases constructorEquality
          exact (leftEvidence.generic rightEvidence.nongeneric).elim
  | structNongeneric leftEvidence leftFields =>
      cases right with
      | structExplicit rightEvidence rightFields =>
          exact (rightEvidence.explicitArguments.excludesNoGenericArguments
            leftEvidence.implicitArguments).elim
      | structInferred rightEvidence rightFields =>
          have constructorEquality := complete.structConstructor_unique
            leftEvidence.selected rightEvidence.selected
          cases constructorEquality
          exact (rightEvidence.generic leftEvidence.nongeneric).elim
      | structNongeneric rightEvidence rightFields =>
          rcases leftEvidence.results_unique_of_fields complete
              (fun _member => checkUnique)
              rightEvidence leftFields rightFields with ⟨rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩

/-- Payload-driven enum construction has the same functionality property. The
    recursive payload derivation first fixes the observed types; occurrence
    coverage then fixes the generic arguments and therefore the artifact. -/
theorem VariantInferenceEvidence.results_unique_of_payload
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (exprUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : VariantInferenceEvidence outer concrete symbolic path leftConstructor
      leftInner leftObservedTypes leftTypeArguments leftConstArguments
      leftResolved)
    (right : VariantInferenceEvidence outer concrete symbolic path rightConstructor
      rightInner rightObservedTypes rightTypeArguments rightConstArguments
      rightResolved)
    (leftPayload : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      leftObservedTypes leftGroundPayload leftCoreArguments)
    (rightPayload : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      rightObservedTypes rightGroundPayload rightCoreArguments) :
    leftConstructor = rightConstructor ∧
      leftObservedTypes = rightObservedTypes ∧
      leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments ∧
      leftResolved = rightResolved ∧
      leftGroundPayload = rightGroundPayload ∧
      leftCoreArguments = rightCoreArguments := by
  have constructorEquality :=
    complete.symbolicVariantConstructor_unique left.selected right.selected
  cases constructorEquality
  obtain ⟨observedTypesEquality, groundPayloadEquality, coreArgumentsEquality⟩ :=
    ExprListInferenceDerivationSpecializes.unique_of_expr exprUnique
      leftPayload rightPayload
  have typeMatchesRight : Static.TypesSymbolicallyMatch rightInner
      leftConstructor.payload leftObservedTypes := by
    rw [observedTypesEquality]
    exact right.typeMatches
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    SurfaceElaboration.symbolicArgumentsBound_orderedArguments_unique_of_determined
      left.determined left.typeMatches typeMatchesRight
      left.nominal.arguments right.nominal.arguments
  have artifactEquality := complete.nominalEvidenceArtifact_unique contexts
    left.nominal right.nominal typeArgumentsEquality constArgumentsEquality
  exact ⟨rfl, observedTypesEquality, typeArgumentsEquality,
    constArgumentsEquality, artifactEquality, groundPayloadEquality,
    coreArgumentsEquality⟩

theorem VariantExplicitEvidence.results_unique_of_payload
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : VariantExplicitEvidence outer concrete symbolic path leftConstructor
      leftInner leftTypeArguments leftConstArguments leftResolved)
    (right : VariantExplicitEvidence outer concrete symbolic path rightConstructor
      rightInner rightTypeArguments rightConstArguments rightResolved)
    (leftPayload : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner surfaceArguments
      leftConstructor.payload leftCoreArguments)
    (rightPayload : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner surfaceArguments
      rightConstructor.payload rightCoreArguments) :
    leftConstructor = rightConstructor ∧
      leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments ∧
      leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have constructorEquality :=
    complete.symbolicVariantConstructor_unique left.selected right.selected
  cases constructorEquality
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    left.explicitArguments.orderedArguments_unique complete.metadataUnique
      right.explicitArguments left.nominal.arguments right.nominal.arguments
  cases typeArgumentsEquality
  cases constArgumentsEquality
  obtain ⟨leftExpectedTypes, leftSubstituted⟩ := leftPayload.substitutedTypes
  obtain ⟨rightExpectedTypes, rightSubstituted⟩ :=
    rightPayload.substitutedTypes
  have expectedTypesEquality := complete.variantPayloadSubstitute_unique
    left.selected.2.member left.nominal.arguments right.nominal.arguments
    leftSubstituted rightSubstituted
  have substitutionsAgree : Static.substituteTypes leftInner
      leftConstructor.payload =
      Static.substituteTypes rightInner leftConstructor.payload := by
    rw [leftSubstituted, rightSubstituted, expectedTypesEquality]
  have artifactEquality := complete.nominalEvidenceArtifact_unique contexts
    left.nominal right.nominal rfl rfl
  have payloadEquality :=
    leftPayload.unique_of_expr_and_substitution checkUnique rightPayload
      substitutionsAgree
  exact ⟨rfl, rfl, rfl, artifactEquality, payloadEquality⟩

theorem VariantNongenericEvidence.results_unique_of_payload
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : VariantNongenericEvidence outer concrete symbolic path leftConstructor
      leftInner leftResolved)
    (right : VariantNongenericEvidence outer concrete symbolic path rightConstructor
      rightInner rightResolved)
    (leftPayload : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner surfaceArguments
      leftConstructor.payload leftCoreArguments)
    (rightPayload : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner surfaceArguments
      rightConstructor.payload rightCoreArguments) :
    leftConstructor = rightConstructor ∧ leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have constructorEquality :=
    complete.symbolicVariantConstructor_unique left.selected right.selected
  cases constructorEquality
  obtain ⟨leftExpectedTypes, leftSubstituted⟩ := leftPayload.substitutedTypes
  obtain ⟨rightExpectedTypes, rightSubstituted⟩ :=
    rightPayload.substitutedTypes
  have expectedTypesEquality := complete.variantPayloadSubstitute_unique
    left.selected.2.member left.nominal.arguments right.nominal.arguments
    leftSubstituted rightSubstituted
  have substitutionsAgree : Static.substituteTypes leftInner
      leftConstructor.payload =
      Static.substituteTypes rightInner leftConstructor.payload := by
    rw [leftSubstituted, rightSubstituted, expectedTypesEquality]
  have artifactEquality := complete.nominalEvidenceArtifact_unique contexts
    left.nominal right.nominal rfl rfl
  have payloadEquality :=
    leftPayload.unique_of_expr_and_substitution checkUnique rightPayload
      substitutionsAgree
  exact ⟨rfl, artifactEquality, payloadEquality⟩

theorem VariantExplicitEvidence.excludesInference
    (explicit : VariantExplicitEvidence outer concrete symbolic path
      explicitConstructor explicitInner explicitTypes explicitConstants
      explicitResolved)
    (inferred : VariantInferenceEvidence outer concrete symbolic path
      inferredConstructor inferredInner observedTypes inferredTypes
      inferredConstants inferredResolved) : False :=
  explicit.explicitArguments.excludesNoGenericArguments
    inferred.implicitArguments

theorem VariantExplicitEvidence.excludesNongeneric
    (explicit : VariantExplicitEvidence outer concrete symbolic path
      explicitConstructor explicitInner explicitTypes explicitConstants
      explicitResolved)
    (nongeneric : VariantNongenericEvidence outer concrete symbolic path
      nongenericConstructor nongenericInner nongenericResolved) : False :=
  explicit.explicitArguments.excludesNoGenericArguments
    nongeneric.implicitArguments

theorem VariantInferenceEvidence.excludesNongeneric
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (inferred : VariantInferenceEvidence outer concrete symbolic path
      inferredConstructor inferredInner observedTypes inferredTypes
      inferredConstants inferredResolved)
    (nongeneric : VariantNongenericEvidence outer concrete symbolic path
      nongenericConstructor nongenericInner nongenericResolved) : False := by
  have constructorEquality := complete.symbolicVariantConstructor_unique
    inferred.selected nongeneric.selected
  cases constructorEquality
  exact inferred.generic nongeneric.nongeneric

/-- Two applications of the contextual struct rule to the same expected type
    select the same constructor arguments, artifact, and emitted fields. -/
theorem contextualStructResults_unique
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (checkUnique : ∀ {name surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      (name, surfaceExpr) ∈ surfaceFields →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (leftSelected : SurfaceElaboration.SelectsStructConstructor
      symbolic.globals path leftConstructor)
    (rightSelected : SurfaceElaboration.SelectsStructConstructor
      symbolic.globals path rightConstructor)
    (leftExpected : expectedType = Static.Ty.nominal leftConstructor.sourceType
      leftTypeArguments leftConstArguments)
    (rightExpected : expectedType = Static.Ty.nominal rightConstructor.sourceType
      rightTypeArguments rightConstArguments)
    (leftArguments : Static.SymbolicArgumentsBound leftInner
      leftConstructor.genericParameters leftTypeArguments leftConstArguments)
    (rightArguments : Static.SymbolicArgumentsBound rightInner
      rightConstructor.genericParameters rightTypeArguments rightConstArguments)
    (leftTypeArgumentsGround : Static.instantiateTypes outer leftTypeArguments =
      some leftGroundTypeArguments)
    (rightTypeArgumentsGround : Static.instantiateTypes outer rightTypeArguments =
      some rightGroundTypeArguments)
    (leftConstArgumentsGround : Static.instantiateConstants outer
      leftConstArguments = some leftGroundConstArguments)
    (rightConstArgumentsGround : Static.instantiateConstants outer
      rightConstArguments = some rightGroundConstArguments)
    (leftArtifact : NominalArtifactDemand concrete leftConstructor.declaration
      leftConstructor.sourceType .structure leftGroundTypeArguments
      leftGroundConstArguments leftResolved)
    (rightArtifact : NominalArtifactDemand concrete rightConstructor.declaration
      rightConstructor.sourceType .structure rightGroundTypeArguments
      rightGroundConstArguments rightResolved)
    (leftFields : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner
      leftConstructor.fields surfaceFields leftCoreFields)
    (rightFields : StructFieldsCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner
      rightConstructor.fields surfaceFields rightCoreFields) :
    leftConstructor = rightConstructor ∧
      leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments ∧
      leftResolved = rightResolved ∧ leftCoreFields = rightCoreFields := by
  have constructorEquality := complete.structConstructor_unique
    leftSelected rightSelected
  cases constructorEquality
  have expectedEquality := leftExpected.symm.trans rightExpected
  injection expectedEquality with sourceTypeEquality typeArgumentsEquality
    constArgumentsEquality
  cases sourceTypeEquality
  cases typeArgumentsEquality
  cases constArgumentsEquality
  have groundTypeArgumentsEquality := Option.some.inj
    (leftTypeArgumentsGround.symm.trans rightTypeArgumentsGround)
  have groundConstArgumentsEquality := Option.some.inj
    (leftConstArgumentsGround.symm.trans rightConstArgumentsGround)
  have artifactEquality := complete.concreteNominalArtifact_unique contexts
    leftArtifact rightArtifact groundTypeArgumentsEquality
    groundConstArgumentsEquality
  have fieldsEquality :=
    leftFields.unique_of_expr_and_arguments complete checkUnique
      leftSelected.member (fun _ member => member) leftArguments rightArguments
      rightFields
  exact ⟨rfl, rfl, rfl, artifactEquality, fieldsEquality⟩

/-- The contextual variant rule obeys the same expected-type identity key. -/
theorem contextualVariantResults_unique
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (leftSelected : SelectsSymbolicVariantConstructor symbolic path leftConstructor)
    (rightSelected : SelectsSymbolicVariantConstructor symbolic path rightConstructor)
    (leftExpected : expectedType = Static.Ty.nominal leftConstructor.sourceType
      leftTypeArguments leftConstArguments)
    (rightExpected : expectedType = Static.Ty.nominal rightConstructor.sourceType
      rightTypeArguments rightConstArguments)
    (leftArguments : Static.SymbolicArgumentsBound leftInner
      leftConstructor.genericParameters leftTypeArguments leftConstArguments)
    (rightArguments : Static.SymbolicArgumentsBound rightInner
      rightConstructor.genericParameters rightTypeArguments rightConstArguments)
    (leftTypeArgumentsGround : Static.instantiateTypes outer leftTypeArguments =
      some leftGroundTypeArguments)
    (rightTypeArgumentsGround : Static.instantiateTypes outer rightTypeArguments =
      some rightGroundTypeArguments)
    (leftConstArgumentsGround : Static.instantiateConstants outer
      leftConstArguments = some leftGroundConstArguments)
    (rightConstArgumentsGround : Static.instantiateConstants outer
      rightConstArguments = some rightGroundConstArguments)
    (leftArtifact : NominalArtifactDemand concrete
      leftConstructor.nominalDeclaration leftConstructor.sourceType .enumeration
      leftGroundTypeArguments leftGroundConstArguments leftResolved)
    (rightArtifact : NominalArtifactDemand concrete
      rightConstructor.nominalDeclaration rightConstructor.sourceType .enumeration
      rightGroundTypeArguments rightGroundConstArguments rightResolved)
    (leftPayload : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts leftInner surfaceArguments
      leftConstructor.payload leftCoreArguments)
    (rightPayload : ExprListSubstitutedCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts rightInner surfaceArguments
      rightConstructor.payload rightCoreArguments) :
    leftConstructor = rightConstructor ∧
      leftTypeArguments = rightTypeArguments ∧
      leftConstArguments = rightConstArguments ∧
      leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have constructorEquality := complete.symbolicVariantConstructor_unique
    leftSelected rightSelected
  cases constructorEquality
  have expectedEquality := leftExpected.symm.trans rightExpected
  injection expectedEquality with sourceTypeEquality typeArgumentsEquality
    constArgumentsEquality
  cases sourceTypeEquality
  cases typeArgumentsEquality
  cases constArgumentsEquality
  have groundTypeArgumentsEquality := Option.some.inj
    (leftTypeArgumentsGround.symm.trans rightTypeArgumentsGround)
  have groundConstArgumentsEquality := Option.some.inj
    (leftConstArgumentsGround.symm.trans rightConstArgumentsGround)
  have artifactEquality := complete.concreteNominalArtifact_unique contexts
    leftArtifact rightArtifact groundTypeArgumentsEquality
    groundConstArgumentsEquality
  obtain ⟨leftExpectedTypes, leftSubstituted⟩ := leftPayload.substitutedTypes
  obtain ⟨rightExpectedTypes, rightSubstituted⟩ :=
    rightPayload.substitutedTypes
  have expectedTypesEquality := complete.variantPayloadSubstitute_unique
    leftSelected.2.member leftArguments rightArguments leftSubstituted
    rightSubstituted
  have substitutionsAgree : Static.substituteTypes leftInner
      leftConstructor.payload =
      Static.substituteTypes rightInner leftConstructor.payload := by
    rw [leftSubstituted, rightSubstituted, expectedTypesEquality]
  have payloadEquality :=
    leftPayload.unique_of_expr_and_substitution checkUnique rightPayload
      substitutionsAgree
  exact ⟨rfl, rfl, rfl, artifactEquality, payloadEquality⟩

/-- Inferred direct calls are functional once inference of their argument list
    is functional. Source selection fixes the scheme, occurrence coverage
    fixes its ordered generic arguments, declaration provenance fixes the
    instantiated signature, and the complete artifact table fixes the emitted
    function row. -/
theorem DirectCallInferenceEvidence.results_unique_of_arguments
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (inferUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : DirectCallInferenceEvidence outer concrete symbolic path
      leftObservedTypes leftReturnType leftScheme leftInner leftResolved)
    (right : DirectCallInferenceEvidence outer concrete symbolic path
      rightObservedTypes rightReturnType rightScheme rightInner rightResolved)
    (leftArguments : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      leftObservedTypes leftResolved.parameterTypes leftCoreArguments)
    (rightArguments : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      rightObservedTypes rightResolved.parameterTypes rightCoreArguments) :
    leftScheme = rightScheme ∧ leftObservedTypes = rightObservedTypes ∧
      leftReturnType = rightReturnType ∧ leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have schemeEquality := left.selected.unique right.selected
  cases schemeEquality
  obtain ⟨observedTypesEquality, _parameterGroundsEquality,
      coreArgumentsEquality⟩ :=
    ExprListInferenceDerivationSpecializes.unique_of_expr inferUnique
      leftArguments rightArguments
  cases observedTypesEquality
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    SurfaceElaboration.symbolicArgumentsBound_orderedArguments_unique_of_determined
      left.determined left.argumentMatches right.argumentMatches
      left.genericArguments right.genericArguments
  have rightGenericArguments : Static.SymbolicArgumentsBound rightInner
      leftScheme.genericParameters left.symbolicTypeArguments
      left.symbolicConstArguments := by
    rw [typeArgumentsEquality, constArgumentsEquality]
    exact right.genericArguments
  obtain ⟨_parameterTypesEquality, returnTypeEquality⟩ :=
    complete.functionSignatureSubstitute_unique left.selected.member
      left.genericArguments rightGenericArguments
      left.argumentMatches.substitutes right.argumentMatches.substitutes
      left.returnSubstitute right.returnSubstitute
  cases returnTypeEquality
  have groundTypeArgumentsEquality := Option.some.inj
    (left.typeArgumentsGround.symm.trans
      ((congrArg (Static.instantiateTypes outer) typeArgumentsEquality).trans
        right.typeArgumentsGround))
  have groundConstArgumentsEquality := Option.some.inj
    (left.constArgumentsGround.symm.trans
      ((congrArg (Static.instantiateConstants outer)
        constArgumentsEquality).trans right.constArgumentsGround))
  have artifactEquality := complete.concreteFunctionArtifact_unique contexts
    left.artifact right.artifact groundTypeArgumentsEquality
    groundConstArgumentsEquality
  cases artifactEquality
  exact ⟨rfl, rfl, rfl, rfl, coreArgumentsEquality⟩

/-- Explicit direct calls observe the source generic argument list exactly, so
    retained-argument functionality replaces occurrence-based inference. -/
theorem DirectCallExplicitEvidence.results_unique_of_arguments
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : DirectCallExplicitEvidence outer concrete symbolic path
      leftParameterTypes leftReturnType leftScheme leftInner leftResolved)
    (right : DirectCallExplicitEvidence outer concrete symbolic path
      rightParameterTypes rightReturnType rightScheme rightInner rightResolved)
    (leftArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      leftParameterTypes leftResolved.parameterTypes leftCoreArguments)
    (rightArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      rightParameterTypes rightResolved.parameterTypes rightCoreArguments) :
    leftScheme = rightScheme ∧ leftParameterTypes = rightParameterTypes ∧
      leftReturnType = rightReturnType ∧ leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have schemeEquality := left.selected.unique right.selected
  cases schemeEquality
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    left.explicitArguments.orderedArguments_unique complete.metadataUnique
      right.explicitArguments left.genericArguments right.genericArguments
  have rightGenericArguments : Static.SymbolicArgumentsBound rightInner
      leftScheme.genericParameters left.symbolicTypeArguments
      left.symbolicConstArguments := by
    rw [typeArgumentsEquality, constArgumentsEquality]
    exact right.genericArguments
  obtain ⟨parameterTypesEquality, returnTypeEquality⟩ :=
    complete.functionSignatureSubstitute_unique left.selected.member
      left.genericArguments rightGenericArguments left.parametersSubstitute
      right.parametersSubstitute left.returnSubstitute right.returnSubstitute
  cases parameterTypesEquality
  cases returnTypeEquality
  have groundTypeArgumentsEquality := Option.some.inj
    (left.typeArgumentsGround.symm.trans
      ((congrArg (Static.instantiateTypes outer) typeArgumentsEquality).trans
        right.typeArgumentsGround))
  have groundConstArgumentsEquality := Option.some.inj
    (left.constArgumentsGround.symm.trans
      ((congrArg (Static.instantiateConstants outer)
        constArgumentsEquality).trans right.constArgumentsGround))
  have artifactEquality := complete.concreteFunctionArtifact_unique contexts
    left.artifact right.artifact groundTypeArgumentsEquality
    groundConstArgumentsEquality
  cases artifactEquality
  obtain ⟨_parameterGroundsEquality, coreArgumentsEquality⟩ :=
    ExprListCheckingDerivationSpecializes.unique_of_expr checkUnique
      leftArguments rightArguments
  exact ⟨rfl, rfl, rfl, rfl, coreArgumentsEquality⟩

/-- Nongeneric direct calls have the empty specialization key, leaving only
    source-scheme selection, complete artifact identity, and recursive
    argument checking to determine their result. -/
theorem DirectCallNongenericEvidence.results_unique_of_arguments
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : DirectCallNongenericEvidence outer concrete symbolic path
      leftScheme leftResolved)
    (right : DirectCallNongenericEvidence outer concrete symbolic path
      rightScheme rightResolved)
    (leftArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      leftScheme.parameterTypes leftResolved.parameterTypes leftCoreArguments)
    (rightArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      rightScheme.parameterTypes rightResolved.parameterTypes rightCoreArguments) :
    leftScheme = rightScheme ∧ leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have schemeEquality := left.selected.unique right.selected
  cases schemeEquality
  have artifactEquality := complete.concreteFunctionArtifact_unique contexts
    left.artifact right.artifact rfl rfl
  cases artifactEquality
  obtain ⟨_parameterGroundsEquality, coreArgumentsEquality⟩ :=
    ExprListCheckingDerivationSpecializes.unique_of_expr checkUnique
      leftArguments rightArguments
  exact ⟨rfl, rfl, coreArgumentsEquality⟩

theorem DirectCallExplicitEvidence.excludesInference
    (explicit : DirectCallExplicitEvidence outer concrete symbolic path
      explicitParameterTypes explicitReturnType explicitScheme explicitInner
      explicitResolved)
    (inferred : DirectCallInferenceEvidence outer concrete symbolic path
      inferredObservedTypes inferredReturnType inferredScheme inferredInner
      inferredResolved) : False :=
  explicit.explicitArguments.excludesNoGenericArguments
    inferred.implicitArguments

theorem DirectCallExplicitEvidence.excludesNongeneric
    (explicit : DirectCallExplicitEvidence outer concrete symbolic path
      explicitParameterTypes explicitReturnType explicitScheme explicitInner
      explicitResolved)
    (nongeneric : DirectCallNongenericEvidence outer concrete symbolic path
      nongenericScheme nongenericResolved) : False :=
  explicit.explicitArguments.excludesNoGenericArguments
    nongeneric.implicitArguments

theorem DirectCallInferenceEvidence.excludesNongeneric
    (inferred : DirectCallInferenceEvidence outer concrete symbolic path
      inferredObservedTypes inferredReturnType inferredScheme inferredInner
      inferredResolved)
    (nongeneric : DirectCallNongenericEvidence outer concrete symbolic path
      nongenericScheme nongenericResolved) : False := by
  have schemeEquality := inferred.selected.unique nongeneric.selected
  cases schemeEquality
  exact inferred.generic nongeneric.nongeneric

/-- Substitution of the source-visible parameter vector of an associated
    function is functional once declaration provenance has fixed substitution
    of the retained receiver and ordinary parameter vector.  The proof covers
    both receiverless functions and explicit typed receivers; `self` and
    `&self` cannot occur in associated-call syntax. -/
theorem associatedArgumentSubstitute_unique
    {scheme : Static.MethodScheme}
    {leftSubstitution rightSubstitution : Static.SymbolicSubstitution}
    {leftSourceParameterTypes rightSourceParameterTypes : List Static.Ty}
    {leftReceiverType rightReceiverType : Static.Ty}
    {leftStoredArgumentTypes rightStoredArgumentTypes : List Static.Ty}
    {leftAssociatedArgumentTypes rightAssociatedArgumentTypes : List Static.Ty}
    (leftParameters : scheme.associatedArgumentTypes? =
      some leftSourceParameterTypes)
    (rightParameters : scheme.associatedArgumentTypes? =
      some rightSourceParameterTypes)
    (leftReceiver : scheme.receiverType.substitute leftSubstitution =
      some leftReceiverType)
    (rightReceiver : scheme.receiverType.substitute rightSubstitution =
      some rightReceiverType)
    (leftStored : Static.substituteTypes leftSubstitution scheme.argumentTypes =
      some leftStoredArgumentTypes)
    (rightStored : Static.substituteTypes rightSubstitution scheme.argumentTypes =
      some rightStoredArgumentTypes)
    (leftAssociated : Static.substituteTypes leftSubstitution
      leftSourceParameterTypes = some leftAssociatedArgumentTypes)
    (rightAssociated : Static.substituteTypes rightSubstitution
      rightSourceParameterTypes = some rightAssociatedArgumentTypes)
    (receiverEquality : leftReceiverType = rightReceiverType)
    (storedEquality : leftStoredArgumentTypes = rightStoredArgumentTypes) :
    leftAssociatedArgumentTypes = rightAssociatedArgumentTypes := by
  cases receiverEquality
  cases storedEquality
  have sourceParametersEquality := Option.some.inj
    (leftParameters.symm.trans rightParameters)
  cases sourceParametersEquality
  cases mode : scheme.receiverMode with
  | none =>
      have sourceShape : scheme.argumentTypes = leftSourceParameterTypes := by
        simpa [Static.MethodScheme.associatedArgumentTypes?, mode] using
          leftParameters
      cases sourceShape
      have leftResult : leftStoredArgumentTypes =
          leftAssociatedArgumentTypes :=
        Option.some.inj (leftStored.symm.trans leftAssociated)
      have rightResult : leftStoredArgumentTypes =
          rightAssociatedArgumentTypes :=
        Option.some.inj (rightStored.symm.trans rightAssociated)
      exact leftResult.symm.trans rightResult
  | explicit =>
      have sourceShape : scheme.receiverType :: scheme.argumentTypes =
          leftSourceParameterTypes := by
        simpa [Static.MethodScheme.associatedArgumentTypes?, mode] using
          leftParameters
      cases sourceShape
      have leftResult : leftReceiverType :: leftStoredArgumentTypes =
          leftAssociatedArgumentTypes := by
        simpa [Static.substituteTypes, leftReceiver, leftStored] using
          leftAssociated
      have rightResult : leftReceiverType :: leftStoredArgumentTypes =
          rightAssociatedArgumentTypes := by
        simpa [Static.substituteTypes, rightReceiver, rightStored] using
          rightAssociated
      exact leftResult.symm.trans rightResult
  | value =>
      simp [Static.MethodScheme.associatedArgumentTypes?, mode] at leftParameters
  | reference =>
      simp [Static.MethodScheme.associatedArgumentTypes?, mode] at leftParameters

/-- Two inferred associated-call occurrences select one symbolic result, one
    monomorphic method artifact, and one emitted argument vector. -/
theorem AssociatedCallInferenceEvidence.results_unique_of_arguments
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (argumentsUnique : ∀ {leftSymbolic leftGround leftCore rightSymbolic
        rightGround rightCore},
      ExprListInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments leftSymbolic leftGround leftCore →
        ExprListInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : AssociatedCallInferenceEvidence outer concrete symbolic path
      leftOwnerPath leftName leftReceiverType leftSourceParameterTypes
      leftObservedTypes leftGroundArgumentTypes leftReturnType leftScheme
      leftInner leftResolved)
    (right : AssociatedCallInferenceEvidence outer concrete symbolic path
      rightOwnerPath rightName rightReceiverType rightSourceParameterTypes
      rightObservedTypes rightGroundArgumentTypes rightReturnType rightScheme
      rightInner rightResolved)
    (leftArguments : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      leftObservedTypes leftGroundArgumentTypes leftCoreArguments)
    (rightArguments : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      rightObservedTypes rightGroundArgumentTypes rightCoreArguments) :
    leftReturnType = rightReturnType ∧ leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have splitEquality := Option.some.inj (left.split.symm.trans right.split)
  injection splitEquality with ownerPathEquality nameEquality
  cases ownerPathEquality
  cases nameEquality
  have receiverTypeEquality := TypeRetains.unique complete.metadataUnique
    left.owner right.owner
  cases receiverTypeEquality
  obtain ⟨observedTypesEquality, groundArgumentTypesEquality,
      coreArgumentsEquality⟩ := argumentsUnique leftArguments rightArguments
  cases observedTypesEquality
  cases groundArgumentTypesEquality
  have declarationEquality := left.unique rightScheme right.schemeMember
    ⟨rightInner, right.schemeName, right.receiverMatch,
      right.genericArguments.parametersBound, right.requirements.symbolic⟩
    right.symbolicPreferred
  have schemeEquality := complete.metadataUnique.methods leftScheme
    left.schemeMember rightScheme right.schemeMember declarationEquality.symm
  cases schemeEquality
  have sourceParameterTypesEquality := Option.some.inj
    (left.associatedParameters.symm.trans right.associatedParameters)
  cases sourceParameterTypesEquality
  have orderedArgumentsEquality :
      left.symbolicTypeArguments = right.symbolicTypeArguments ∧
        left.symbolicConstArguments = right.symbolicConstArguments := by
    cases mode : leftScheme.receiverMode with
    | none =>
        have sourceShape : leftScheme.argumentTypes =
            leftSourceParameterTypes := by
          simpa [Static.MethodScheme.associatedArgumentTypes?, mode] using
            left.associatedParameters
        cases sourceShape
        exact
          SurfaceElaboration.symbolicArgumentsBound_orderedArguments_unique_of_determined
            left.determined (.cons left.receiverMatch left.argumentMatches)
            (.cons right.receiverMatch right.argumentMatches)
            left.genericArguments right.genericArguments
    | explicit =>
        have sourceShape : leftScheme.receiverType :: leftScheme.argumentTypes =
            leftSourceParameterTypes := by
          simpa [Static.MethodScheme.associatedArgumentTypes?, mode] using
            left.associatedParameters
        cases sourceShape
        exact
          SurfaceElaboration.symbolicArgumentsBound_orderedArguments_unique_of_determined
            left.determined left.argumentMatches right.argumentMatches
            left.genericArguments right.genericArguments
    | value =>
        have impossible := left.associatedParameters
        simp [Static.MethodScheme.associatedArgumentTypes?, mode] at impossible
    | reference =>
        have impossible := left.associatedParameters
        simp [Static.MethodScheme.associatedArgumentTypes?, mode] at impossible
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    orderedArgumentsEquality
  have rightGenericArguments : Static.SymbolicArgumentsBound rightInner
      leftScheme.genericParameters left.symbolicTypeArguments
      left.symbolicConstArguments := by
    rw [typeArgumentsEquality, constArgumentsEquality]
    exact right.genericArguments
  obtain ⟨_receiverTypeEquality, _storedArgumentTypesEquality,
      returnTypeEquality⟩ :=
    complete.methodSignatureSubstitute_unique left.schemeMember
      left.genericArguments rightGenericArguments
      left.receiverMatch.substitutes right.receiverMatch.substitutes
      left.storedArgumentsSubstitute right.storedArgumentsSubstitute
      left.returnSubstitute right.returnSubstitute
  cases returnTypeEquality
  have resolvedReceiverEquality : leftResolved.receiverType =
      rightResolved.receiverType :=
    Option.some.inj (left.ownerGrounds.symm.trans right.ownerGrounds)
  have groundTypeArgumentsEquality := Option.some.inj
    (left.typeArgumentsGround.symm.trans
      ((congrArg (Static.instantiateTypes outer) typeArgumentsEquality).trans
        right.typeArgumentsGround))
  have groundConstArgumentsEquality := Option.some.inj
    (left.constArgumentsGround.symm.trans
      ((congrArg (Static.instantiateConstants outer)
        constArgumentsEquality).trans right.constArgumentsGround))
  have resolvedEquality := complete.concreteMethodArtifact_unique contexts
    resolvedReceiverEquality left.artifact right.artifact
    groundTypeArgumentsEquality groundConstArgumentsEquality
  cases resolvedEquality
  exact ⟨rfl, rfl, coreArgumentsEquality⟩

/-- Two contextual associated-call occurrences agree after the owner type fixes
    the declaration and its complete source-visible parameter signature. -/
theorem AssociatedCallContextualEvidence.results_unique_of_arguments
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (argumentsUnique : ∀ {expectedTypes leftGround leftCore rightGround
        rightCore},
      ExprListCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments expectedTypes leftGround leftCore →
        ExprListCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments expectedTypes rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : AssociatedCallContextualEvidence outer concrete symbolic path
      leftOwnerPath leftName leftReceiverType leftSourceParameterTypes
      leftExpectedArgumentTypes leftGroundArgumentTypes leftReturnType leftScheme
      leftInner leftResolved)
    (right : AssociatedCallContextualEvidence outer concrete symbolic path
      rightOwnerPath rightName rightReceiverType rightSourceParameterTypes
      rightExpectedArgumentTypes rightGroundArgumentTypes rightReturnType rightScheme
      rightInner rightResolved)
    (leftArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      leftExpectedArgumentTypes leftGroundArgumentTypes leftCoreArguments)
    (rightArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      rightExpectedArgumentTypes rightGroundArgumentTypes rightCoreArguments) :
    leftReturnType = rightReturnType ∧ leftResolved = rightResolved ∧
      leftCoreArguments = rightCoreArguments := by
  have splitEquality := Option.some.inj (left.split.symm.trans right.split)
  injection splitEquality with ownerPathEquality nameEquality
  cases ownerPathEquality
  cases nameEquality
  have receiverTypeEquality := TypeRetains.unique complete.metadataUnique
    left.owner right.owner
  cases receiverTypeEquality
  have declarationEquality := left.unique rightScheme right.schemeMember
    ⟨rightInner, right.schemeName, right.receiverMatch,
      right.genericArguments.parametersBound, right.requirements.symbolic⟩
    right.symbolicPreferred
  have schemeEquality := complete.metadataUnique.methods leftScheme
    left.schemeMember rightScheme right.schemeMember declarationEquality.symm
  cases schemeEquality
  have sourceParameterTypesEquality := Option.some.inj
    (left.associatedParameters.symm.trans right.associatedParameters)
  cases sourceParameterTypesEquality
  have leftMatches : Static.TypesSymbolicallyMatch leftInner
      [leftScheme.receiverType] [leftReceiverType] :=
    .cons left.receiverMatch .nil
  have rightMatches : Static.TypesSymbolicallyMatch rightInner
      [leftScheme.receiverType] [leftReceiverType] :=
    .cons right.receiverMatch .nil
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    SurfaceElaboration.symbolicArgumentsBound_orderedArguments_unique_of_determined
      left.determined leftMatches rightMatches left.genericArguments
      right.genericArguments
  have rightGenericArguments : Static.SymbolicArgumentsBound rightInner
      leftScheme.genericParameters left.symbolicTypeArguments
      left.symbolicConstArguments := by
    rw [typeArgumentsEquality, constArgumentsEquality]
    exact right.genericArguments
  obtain ⟨receiverSubstituteEquality, storedArgumentsEquality,
      returnTypeEquality⟩ :=
    complete.methodSignatureSubstitute_unique left.schemeMember
      left.genericArguments rightGenericArguments
      left.receiverMatch.substitutes right.receiverMatch.substitutes
      left.storedArgumentsSubstitute right.storedArgumentsSubstitute
      left.returnSubstitute right.returnSubstitute
  have expectedArgumentTypesEquality := associatedArgumentSubstitute_unique
    left.associatedParameters right.associatedParameters
    left.receiverMatch.substitutes right.receiverMatch.substitutes
    left.storedArgumentsSubstitute right.storedArgumentsSubstitute
    left.argumentsSubstitute right.argumentsSubstitute
    receiverSubstituteEquality storedArgumentsEquality
  cases expectedArgumentTypesEquality
  cases returnTypeEquality
  obtain ⟨groundArgumentTypesEquality, coreArgumentsEquality⟩ :=
    argumentsUnique leftArguments rightArguments
  cases groundArgumentTypesEquality
  have resolvedReceiverEquality : leftResolved.receiverType =
      rightResolved.receiverType :=
    Option.some.inj (left.ownerGrounds.symm.trans right.ownerGrounds)
  have groundTypeArgumentsEquality := Option.some.inj
    (left.typeArgumentsGround.symm.trans
      ((congrArg (Static.instantiateTypes outer) typeArgumentsEquality).trans
        right.typeArgumentsGround))
  have groundConstArgumentsEquality := Option.some.inj
    (left.constArgumentsGround.symm.trans
      ((congrArg (Static.instantiateConstants outer)
        constArgumentsEquality).trans right.constArgumentsGround))
  have resolvedEquality := complete.concreteMethodArtifact_unique contexts
    resolvedReceiverEquality left.artifact right.artifact
    groundTypeArgumentsEquality groundConstArgumentsEquality
  cases resolvedEquality
  exact ⟨rfl, rfl, coreArgumentsEquality⟩

/-- If both associated-call rules apply, receiver-only determination in the
    contextual rule fixes the inferred rule's generic arguments as well. -/
theorem AssociatedCallInferenceEvidence.results_unique_of_contextual
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (argumentsUnique : ∀ {expectedTypes leftGround leftCore rightGround
        rightCore},
      ExprListCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments expectedTypes leftGround leftCore →
        ExprListCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments expectedTypes rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (inferred : AssociatedCallInferenceEvidence outer concrete symbolic path
      inferredOwnerPath inferredName inferredReceiverType
      inferredSourceParameterTypes observedTypes inferredGroundArgumentTypes
      inferredReturnType inferredScheme inferredInner inferredResolved)
    (contextual : AssociatedCallContextualEvidence outer concrete symbolic path
      contextualOwnerPath contextualName contextualReceiverType
      contextualSourceParameterTypes expectedTypes contextualGroundArgumentTypes
      contextualReturnType contextualScheme contextualInner contextualResolved)
    (inferredArguments : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      observedTypes inferredGroundArgumentTypes inferredCoreArguments)
    (contextualArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      expectedTypes contextualGroundArgumentTypes contextualCoreArguments) :
    inferredReturnType = contextualReturnType ∧
      inferredResolved = contextualResolved ∧
      inferredCoreArguments = contextualCoreArguments := by
  have splitEquality := Option.some.inj
    (inferred.split.symm.trans contextual.split)
  injection splitEquality with ownerPathEquality nameEquality
  cases ownerPathEquality
  cases nameEquality
  have receiverTypeEquality := TypeRetains.unique complete.metadataUnique
    inferred.owner contextual.owner
  cases receiverTypeEquality
  have declarationEquality := contextual.unique inferredScheme
    inferred.schemeMember
    ⟨inferredInner, inferred.schemeName, inferred.receiverMatch,
      inferred.genericArguments.parametersBound, inferred.requirements.symbolic⟩
    inferred.symbolicPreferred
  have schemeEquality := complete.metadataUnique.methods inferredScheme
    inferred.schemeMember contextualScheme contextual.schemeMember
    declarationEquality
  cases schemeEquality
  have sourceParameterTypesEquality := Option.some.inj
    (inferred.associatedParameters.symm.trans contextual.associatedParameters)
  cases sourceParameterTypesEquality
  have inferredMatches : Static.TypesSymbolicallyMatch inferredInner
      [inferredScheme.receiverType] [inferredReceiverType] :=
    .cons inferred.receiverMatch .nil
  have contextualMatches : Static.TypesSymbolicallyMatch contextualInner
      [inferredScheme.receiverType] [inferredReceiverType] :=
    .cons contextual.receiverMatch .nil
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    SurfaceElaboration.symbolicArgumentsBound_orderedArguments_unique_of_determined
      contextual.determined inferredMatches contextualMatches
      inferred.genericArguments contextual.genericArguments
  have contextualGenericArguments : Static.SymbolicArgumentsBound contextualInner
      inferredScheme.genericParameters inferred.symbolicTypeArguments
      inferred.symbolicConstArguments := by
    rw [typeArgumentsEquality, constArgumentsEquality]
    exact contextual.genericArguments
  obtain ⟨receiverSubstituteEquality, storedArgumentsEquality,
      returnTypeEquality⟩ :=
    complete.methodSignatureSubstitute_unique inferred.schemeMember
      inferred.genericArguments contextualGenericArguments
      inferred.receiverMatch.substitutes contextual.receiverMatch.substitutes
      inferred.storedArgumentsSubstitute contextual.storedArgumentsSubstitute
      inferred.returnSubstitute contextual.returnSubstitute
  have argumentTypesEquality := associatedArgumentSubstitute_unique
    inferred.associatedParameters contextual.associatedParameters
    inferred.receiverMatch.substitutes contextual.receiverMatch.substitutes
    inferred.storedArgumentsSubstitute contextual.storedArgumentsSubstitute
    inferred.argumentMatches.substitutes contextual.argumentsSubstitute
    receiverSubstituteEquality storedArgumentsEquality
  cases argumentTypesEquality
  cases returnTypeEquality
  obtain ⟨groundArgumentTypesEquality, coreArgumentsEquality⟩ :=
    argumentsUnique inferredArguments.asChecking contextualArguments
  cases groundArgumentTypesEquality
  have resolvedReceiverEquality : inferredResolved.receiverType =
      contextualResolved.receiverType :=
    Option.some.inj (inferred.ownerGrounds.symm.trans contextual.ownerGrounds)
  have groundTypeArgumentsEquality := Option.some.inj
    (inferred.typeArgumentsGround.symm.trans
      ((congrArg (Static.instantiateTypes outer) typeArgumentsEquality).trans
        contextual.typeArgumentsGround))
  have groundConstArgumentsEquality := Option.some.inj
    (inferred.constArgumentsGround.symm.trans
      ((congrArg (Static.instantiateConstants outer)
        constArgumentsEquality).trans contextual.constArgumentsGround))
  have resolvedEquality := complete.concreteMethodArtifact_unique contexts
    resolvedReceiverEquality inferred.artifact contextual.artifact
    groundTypeArgumentsEquality groundConstArgumentsEquality
  cases resolvedEquality
  exact ⟨rfl, rfl, coreArgumentsEquality⟩

/-- Inferred method calls are functional once their receiver and argument
    expressions are. Ground receiver/name lookup coherence fixes the selected
    scheme; receiver/argument occurrence coverage then fixes its symbolic
    generic arguments and declaration provenance fixes the return type. -/
theorem MethodCallInferenceEvidence.results_unique_of_children
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (receiverUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceReceiver leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceReceiver rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (argumentsUnique : ∀ {leftSymbolic leftGround leftCore rightSymbolic
        rightGround rightCore},
      ExprListInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments leftSymbolic leftGround leftCore →
        ExprListInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : MethodCallInferenceEvidence outer concrete symbolic
      leftReceiverType name leftObservedTypes leftReturnType leftScheme
      leftInner leftResolved)
    (right : MethodCallInferenceEvidence outer concrete symbolic
      rightReceiverType name rightObservedTypes rightReturnType rightScheme
      rightInner rightResolved)
    (leftReceiver : ExprInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceReceiver
      leftSourceReceiver leftSourceGround leftSourceCore)
    (rightReceiver : ExprInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceReceiver
      rightSourceReceiver rightSourceGround rightSourceCore)
    (leftMemberBase : SymbolicMemberBase leftSourceReceiver leftReceiverType)
    (rightMemberBase : SymbolicMemberBase rightSourceReceiver rightReceiverType)
    (leftMemberLowers : Elaboration.MemberBaseLowers concrete.monomorphization
      leftSourceGround leftSourceCore leftResolved.receiverType leftReceiverCore)
    (rightMemberLowers : Elaboration.MemberBaseLowers concrete.monomorphization
      rightSourceGround rightSourceCore rightResolved.receiverType rightReceiverCore)
    (leftArguments : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      leftObservedTypes leftResolved.argumentTypes leftCoreArguments)
    (rightArguments : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      rightObservedTypes rightResolved.argumentTypes rightCoreArguments)
    (leftReceiverArgument : Elaboration.ReceiverArgumentLowers
      concrete.monomorphization leftResolved.receiverMode
      leftResolved.receiverType leftReceiverCore leftReceiverArgumentCore)
    (rightReceiverArgument : Elaboration.ReceiverArgumentLowers
      concrete.monomorphization rightResolved.receiverMode
      rightResolved.receiverType rightReceiverCore rightReceiverArgumentCore) :
    leftReturnType = rightReturnType ∧ leftResolved = rightResolved ∧
      leftReceiverArgumentCore = rightReceiverArgumentCore ∧
      leftCoreArguments = rightCoreArguments := by
  rcases receiverUnique leftReceiver rightReceiver with
    ⟨sourceTypeEquality, sourceGroundEquality, sourceCoreEquality⟩
  cases sourceTypeEquality
  cases sourceGroundEquality
  cases sourceCoreEquality
  have receiverTypeEquality := leftMemberBase.unique rightMemberBase
  cases receiverTypeEquality
  obtain ⟨observedTypesEquality, resolvedArgumentsEquality,
      coreArgumentsEquality⟩ :=
    argumentsUnique leftArguments rightArguments
  cases observedTypesEquality
  have resolvedReceiverEquality :
      leftResolved.receiverType = rightResolved.receiverType :=
    Option.some.inj (left.receiverGrounds.symm.trans right.receiverGrounds)
  have leftResolves := left.artifact.resolvesMethod contexts left.schemeMember
    left.schemeName left.memberMode left.genericArguments left.typeArgumentsGround
    left.constArgumentsGround left.requirements left.receiverMatch.substitutes
    left.receiverGrounds left.argumentMatches.substitutes left.argumentGrounds
    left.returnSubstitute left.returnGrounds rfl rfl rfl left.groundPreferred
    left.coherent
  have rightResolves := right.artifact.resolvesMethod contexts right.schemeMember
    right.schemeName right.memberMode right.genericArguments right.typeArgumentsGround
    right.constArgumentsGround right.requirements right.receiverMatch.substitutes
    right.receiverGrounds right.argumentMatches.substitutes right.argumentGrounds
    right.returnSubstitute right.returnGrounds rfl rfl rfl right.groundPreferred
    right.coherent
  rw [← resolvedReceiverEquality, ← resolvedArgumentsEquality] at rightResolves
  have sameFunction := leftResolves.2.2.2 rightScheme rightResolved
    rightResolves.1 rightResolves.2.1 rightResolves.2.2.1
  have leftMemberGlobal : leftResolved ∈
      symbolic.globals.methodInstances := by
    have member := leftResolves.2.1.1.1
    rw [contexts.globals] at member
    exact member
  have rightMemberGlobal : rightResolved ∈
      symbolic.globals.methodInstances := by
    have member := rightResolves.2.1.1.1
    rw [contexts.globals] at member
    exact member
  have resolvedEquality := complete.artifacts.methodInstanceIdsUnique
    leftResolved leftMemberGlobal rightResolved rightMemberGlobal
      sameFunction.symm
  have schemeEquality := left.coherent concrete.currentModule
    leftResolved.receiverType name leftScheme leftResolves.1
    ⟨leftResolved.argumentTypes, leftResolved, leftResolves.2.1.1⟩
    leftResolves.2.2.1 rightScheme rightResolves.1
    ⟨leftResolved.argumentTypes, rightResolved, rightResolves.2.1.1⟩
    rightResolves.2.2.1
  cases schemeEquality
  have leftMatches : Static.TypesSymbolicallyMatch leftInner
      (leftScheme.receiverType :: leftScheme.argumentTypes)
      (leftReceiverType :: leftObservedTypes) :=
    .cons left.receiverMatch left.argumentMatches
  have rightMatches : Static.TypesSymbolicallyMatch rightInner
      (leftScheme.receiverType :: leftScheme.argumentTypes)
      (leftReceiverType :: leftObservedTypes) :=
    .cons right.receiverMatch right.argumentMatches
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    SurfaceElaboration.symbolicArgumentsBound_orderedArguments_unique_of_determined
      left.determined leftMatches rightMatches left.genericArguments
      right.genericArguments
  have rightGenericArguments : Static.SymbolicArgumentsBound rightInner
      leftScheme.genericParameters left.symbolicTypeArguments
      left.symbolicConstArguments := by
    rw [typeArgumentsEquality, constArgumentsEquality]
    exact right.genericArguments
  obtain ⟨_receiverTypeEquality, _argumentTypesEquality,
      returnTypeEquality⟩ :=
    complete.methodSignatureSubstitute_unique left.schemeMember
      left.genericArguments rightGenericArguments left.receiverMatch.substitutes
      right.receiverMatch.substitutes left.argumentMatches.substitutes
      right.argumentMatches.substitutes left.returnSubstitute
      right.returnSubstitute
  cases returnTypeEquality
  cases resolvedEquality
  have receiverCoreEquality :=
    leftMemberLowers.core_unique rightMemberLowers
  cases receiverCoreEquality
  have receiverArgumentEquality :=
    leftReceiverArgument.unique rightReceiverArgument
  exact ⟨rfl, rfl, receiverArgumentEquality, coreArgumentsEquality⟩

/-- Contextual method calls can infer generic arguments only from the receiver.
    That restriction fixes the symbolic signature before recursively checking
    arguments, so two contextual derivations select the same artifact and Core
    call. -/
theorem MethodCallContextualEvidence.results_unique_of_children
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (receiverUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceReceiver leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceReceiver rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (argumentsUnique : ∀ {expectedTypes leftGround leftCore rightGround
        rightCore},
      ExprListCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments expectedTypes leftGround leftCore →
        ExprListCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments expectedTypes rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : MethodCallContextualEvidence outer concrete symbolic
      leftReceiverType name leftExpectedTypes leftReturnType leftScheme
      leftInner leftResolved)
    (right : MethodCallContextualEvidence outer concrete symbolic
      rightReceiverType name rightExpectedTypes rightReturnType rightScheme
      rightInner rightResolved)
    (leftReceiver : ExprInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceReceiver
      leftSourceReceiver leftSourceGround leftSourceCore)
    (rightReceiver : ExprInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceReceiver
      rightSourceReceiver rightSourceGround rightSourceCore)
    (leftMemberBase : SymbolicMemberBase leftSourceReceiver leftReceiverType)
    (rightMemberBase : SymbolicMemberBase rightSourceReceiver rightReceiverType)
    (leftMemberLowers : Elaboration.MemberBaseLowers concrete.monomorphization
      leftSourceGround leftSourceCore leftResolved.receiverType leftReceiverCore)
    (rightMemberLowers : Elaboration.MemberBaseLowers concrete.monomorphization
      rightSourceGround rightSourceCore rightResolved.receiverType rightReceiverCore)
    (leftArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      leftExpectedTypes leftResolved.argumentTypes leftCoreArguments)
    (rightArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      rightExpectedTypes rightResolved.argumentTypes rightCoreArguments)
    (leftReceiverArgument : Elaboration.ReceiverArgumentLowers
      concrete.monomorphization leftResolved.receiverMode
      leftResolved.receiverType leftReceiverCore leftReceiverArgumentCore)
    (rightReceiverArgument : Elaboration.ReceiverArgumentLowers
      concrete.monomorphization rightResolved.receiverMode
      rightResolved.receiverType rightReceiverCore rightReceiverArgumentCore) :
    leftReturnType = rightReturnType ∧ leftResolved = rightResolved ∧
      leftReceiverArgumentCore = rightReceiverArgumentCore ∧
      leftCoreArguments = rightCoreArguments := by
  rcases receiverUnique leftReceiver rightReceiver with
    ⟨sourceTypeEquality, sourceGroundEquality, sourceCoreEquality⟩
  cases sourceTypeEquality
  cases sourceGroundEquality
  cases sourceCoreEquality
  have receiverTypeEquality := leftMemberBase.unique rightMemberBase
  cases receiverTypeEquality
  have declarationEquality := left.unique rightScheme right.schemeMember
    ⟨rightInner, right.schemeName, right.receiverMatch,
      right.genericArguments.parametersBound, right.requirements.symbolic⟩
    right.symbolicPreferred
  have schemeEquality := complete.metadataUnique.methods leftScheme
    left.schemeMember rightScheme right.schemeMember declarationEquality.symm
  cases schemeEquality
  have leftMatches : Static.TypesSymbolicallyMatch leftInner
      [leftScheme.receiverType] [leftReceiverType] :=
    .cons left.receiverMatch .nil
  have rightMatches : Static.TypesSymbolicallyMatch rightInner
      [leftScheme.receiverType] [leftReceiverType] :=
    .cons right.receiverMatch .nil
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    SurfaceElaboration.symbolicArgumentsBound_orderedArguments_unique_of_determined
      left.determined leftMatches rightMatches left.genericArguments
      right.genericArguments
  have rightGenericArguments : Static.SymbolicArgumentsBound rightInner
      leftScheme.genericParameters left.symbolicTypeArguments
      left.symbolicConstArguments := by
    rw [typeArgumentsEquality, constArgumentsEquality]
    exact right.genericArguments
  obtain ⟨_receiverTypeEquality, expectedTypesEquality, returnTypeEquality⟩ :=
    complete.methodSignatureSubstitute_unique left.schemeMember
      left.genericArguments rightGenericArguments left.receiverMatch.substitutes
      right.receiverMatch.substitutes left.argumentsSubstitute
      right.argumentsSubstitute left.returnSubstitute right.returnSubstitute
  cases expectedTypesEquality
  cases returnTypeEquality
  have resolvedReceiverEquality :
      leftResolved.receiverType = rightResolved.receiverType :=
    Option.some.inj (left.receiverGrounds.symm.trans right.receiverGrounds)
  have groundTypeArgumentsEquality := Option.some.inj
    (left.typeArgumentsGround.symm.trans
      ((congrArg (Static.instantiateTypes outer) typeArgumentsEquality).trans
        right.typeArgumentsGround))
  have groundConstArgumentsEquality := Option.some.inj
    (left.constArgumentsGround.symm.trans
      ((congrArg (Static.instantiateConstants outer)
        constArgumentsEquality).trans right.constArgumentsGround))
  have resolvedEquality := complete.concreteMethodArtifact_unique contexts
    resolvedReceiverEquality left.artifact right.artifact
    groundTypeArgumentsEquality groundConstArgumentsEquality
  cases resolvedEquality
  obtain ⟨_argumentGroundsEquality, coreArgumentsEquality⟩ :=
    argumentsUnique leftArguments rightArguments
  have receiverCoreEquality :=
    leftMemberLowers.core_unique rightMemberLowers
  cases receiverCoreEquality
  have receiverArgumentEquality :=
    leftReceiverArgument.unique rightReceiverArgument
  exact ⟨rfl, rfl, receiverArgumentEquality, coreArgumentsEquality⟩

/-- The inferred and contextual method rules agree whenever both apply. A
    contextual rule may infer generics only from the receiver, so its binding
    also agrees with the inferred rule; the inferred argument traversal can
    then be viewed as exact contextual checking at that shared signature. -/
theorem MethodCallInferenceEvidence.results_unique_of_contextual
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (receiverUnique : ∀ {leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceReceiver leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceReceiver rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (argumentsUnique : ∀ {expectedTypes leftGround leftCore rightGround
        rightCore},
      ExprListCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments expectedTypes leftGround leftCore →
        ExprListCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceArguments expectedTypes rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (inferred : MethodCallInferenceEvidence outer concrete symbolic
      inferredReceiverType name observedTypes inferredReturnType inferredScheme
      inferredInner inferredResolved)
    (contextual : MethodCallContextualEvidence outer concrete symbolic
      contextualReceiverType name expectedTypes contextualReturnType
      contextualScheme contextualInner contextualResolved)
    (inferredReceiver : ExprInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceReceiver
      inferredSourceReceiver inferredSourceGround inferredSourceCore)
    (contextualReceiver : ExprInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceReceiver
      contextualSourceReceiver contextualSourceGround contextualSourceCore)
    (inferredMemberBase : SymbolicMemberBase inferredSourceReceiver
      inferredReceiverType)
    (contextualMemberBase : SymbolicMemberBase contextualSourceReceiver
      contextualReceiverType)
    (inferredMemberLowers : Elaboration.MemberBaseLowers
      concrete.monomorphization inferredSourceGround inferredSourceCore
      inferredResolved.receiverType inferredReceiverCore)
    (contextualMemberLowers : Elaboration.MemberBaseLowers
      concrete.monomorphization contextualSourceGround contextualSourceCore
      contextualResolved.receiverType contextualReceiverCore)
    (inferredArguments : ExprListInferenceDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      observedTypes inferredResolved.argumentTypes inferredCoreArguments)
    (contextualArguments : ExprListCheckingDerivationSpecializes outer
      groundEnclosingReturn symbolic concrete contexts surfaceArguments
      expectedTypes contextualResolved.argumentTypes contextualCoreArguments)
    (inferredReceiverArgument : Elaboration.ReceiverArgumentLowers
      concrete.monomorphization inferredResolved.receiverMode
      inferredResolved.receiverType inferredReceiverCore
      inferredReceiverArgumentCore)
    (contextualReceiverArgument : Elaboration.ReceiverArgumentLowers
      concrete.monomorphization contextualResolved.receiverMode
      contextualResolved.receiverType contextualReceiverCore
      contextualReceiverArgumentCore) :
    inferredReturnType = contextualReturnType ∧
      inferredResolved = contextualResolved ∧
      inferredReceiverArgumentCore = contextualReceiverArgumentCore ∧
      inferredCoreArguments = contextualCoreArguments := by
  rcases receiverUnique inferredReceiver contextualReceiver with
    ⟨sourceTypeEquality, sourceGroundEquality, sourceCoreEquality⟩
  cases sourceTypeEquality
  cases sourceGroundEquality
  cases sourceCoreEquality
  have receiverTypeEquality :=
    inferredMemberBase.unique contextualMemberBase
  cases receiverTypeEquality
  have declarationEquality := contextual.unique inferredScheme
    inferred.schemeMember
    ⟨inferredInner, inferred.schemeName, inferred.receiverMatch,
      inferred.genericArguments.parametersBound, inferred.requirements.symbolic⟩
    inferred.symbolicPreferred
  have schemeEquality := complete.metadataUnique.methods inferredScheme
    inferred.schemeMember contextualScheme contextual.schemeMember
    declarationEquality
  cases schemeEquality
  have inferredMatches : Static.TypesSymbolicallyMatch inferredInner
      [inferredScheme.receiverType] [inferredReceiverType] :=
    .cons inferred.receiverMatch .nil
  have contextualMatches : Static.TypesSymbolicallyMatch contextualInner
      [inferredScheme.receiverType] [inferredReceiverType] :=
    .cons contextual.receiverMatch .nil
  obtain ⟨typeArgumentsEquality, constArgumentsEquality⟩ :=
    SurfaceElaboration.symbolicArgumentsBound_orderedArguments_unique_of_determined
      contextual.determined inferredMatches contextualMatches
      inferred.genericArguments contextual.genericArguments
  have contextualGenericArguments : Static.SymbolicArgumentsBound
      contextualInner inferredScheme.genericParameters
      inferred.symbolicTypeArguments inferred.symbolicConstArguments := by
    rw [typeArgumentsEquality, constArgumentsEquality]
    exact contextual.genericArguments
  obtain ⟨_receiverTypeEquality, argumentTypesEquality, returnTypeEquality⟩ :=
    complete.methodSignatureSubstitute_unique inferred.schemeMember
      inferred.genericArguments contextualGenericArguments
      inferred.receiverMatch.substitutes contextual.receiverMatch.substitutes
      inferred.argumentMatches.substitutes contextual.argumentsSubstitute
      inferred.returnSubstitute contextual.returnSubstitute
  cases argumentTypesEquality
  cases returnTypeEquality
  have resolvedReceiverEquality :
      inferredResolved.receiverType = contextualResolved.receiverType :=
    Option.some.inj
      (inferred.receiverGrounds.symm.trans contextual.receiverGrounds)
  have groundTypeArgumentsEquality := Option.some.inj
    (inferred.typeArgumentsGround.symm.trans
      ((congrArg (Static.instantiateTypes outer) typeArgumentsEquality).trans
        contextual.typeArgumentsGround))
  have groundConstArgumentsEquality := Option.some.inj
    (inferred.constArgumentsGround.symm.trans
      ((congrArg (Static.instantiateConstants outer)
        constArgumentsEquality).trans contextual.constArgumentsGround))
  have resolvedEquality := complete.concreteMethodArtifact_unique contexts
    resolvedReceiverEquality inferred.artifact contextual.artifact
    groundTypeArgumentsEquality groundConstArgumentsEquality
  cases resolvedEquality
  obtain ⟨_argumentGroundsEquality, coreArgumentsEquality⟩ :=
    argumentsUnique inferredArguments.asChecking contextualArguments
  have receiverCoreEquality :=
    inferredMemberLowers.core_unique contextualMemberLowers
  cases receiverCoreEquality
  have receiverArgumentEquality :=
    inferredReceiverArgument.unique contextualReceiverArgument
  exact ⟨rfl, rfl, receiverArgumentEquality, coreArgumentsEquality⟩

/-- Match-arm traversal is functional once pattern specialization and body
    checking are. Pattern functionality aligns the exact binding rows before
    the body theorem is invoked under the extended contexts. -/
theorem MatchArmsDerivationSpecializes.unique_of_expr
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (patternUnique : ∀ {nextCase surfacePattern symbolicType groundType
        leftPattern leftSymbolicBindings leftConcreteBindings leftFinal
        rightPattern rightSymbolicBindings rightConcreteBindings rightFinal},
      PatternDerivationSpecializes outer groundEnclosingReturn symbolic concrete
          contexts nextCase surfacePattern symbolicType groundType leftPattern
          leftSymbolicBindings leftConcreteBindings leftFinal →
        PatternDerivationSpecializes outer groundEnclosingReturn symbolic concrete
          contexts nextCase surfacePattern symbolicType groundType rightPattern
          rightSymbolicBindings rightConcreteBindings rightFinal →
        leftPattern = rightPattern ∧
          leftSymbolicBindings = rightSymbolicBindings ∧
          leftConcreteBindings = rightConcreteBindings ∧
          leftFinal = rightFinal)
    (exprUnique : ∀ {bodySymbolic : SymbolicBodyContext}
        {bodyConcrete : SurfaceElaboration.Context}
        {bodyContexts : bodySymbolic.Specializes outer groundEnclosingReturn
          bodyConcrete}
        {surfaceExpr expected leftGround leftCore rightGround rightCore},
      CompleteProgramElaboration pack catalog imports program
          bodySymbolic.globals externalBindings →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn
          bodySymbolic bodyConcrete bodyContexts surfaceExpr expected leftGround
          leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn
          bodySymbolic bodyConcrete bodyContexts surfaceExpr expected rightGround
          rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : MatchArmsDerivationSpecializes outer groundEnclosingReturn symbolic
      concrete contexts next symbolicScrutinee symbolicResult groundScrutinee
      groundResult surfaceArms leftCore)
    (right : MatchArmsDerivationSpecializes outer groundEnclosingReturn symbolic
      concrete contexts next symbolicScrutinee symbolicResult groundScrutinee
      groundResult surfaceArms rightCore) :
    leftCore = rightCore := by
  induction surfaceArms generalizing leftCore rightCore with
  | nil =>
      cases left
      cases right
      rfl
  | cons surfaceArm surfaceTail induction =>
      cases left with
      | @cons symbolicCase concreteCase contextsCase nextCase surfacePatternCase
          symbolicScrutineeCase groundScrutineeCase corePatternCase
          symbolicBindingsCase concreteBindingsCase patternFinalCase
          surfaceBodyCase symbolicResultCase groundResultCase coreBodyCase
          surfaceTailCase coreTailCase leftPattern leftBody leftTail =>
          cases right with
          | cons rightPattern rightBody rightTail =>
              rcases patternUnique leftPattern rightPattern with
                ⟨corePatternEquality, symbolicBindingsEquality,
                  concreteBindingsEquality, finalEquality⟩
              cases corePatternEquality
              cases symbolicBindingsEquality
              cases concreteBindingsEquality
              cases finalEquality
              have bodyContextsEquality : leftPattern.boundContexts =
                  rightPattern.boundContexts := Subsingleton.elim _ _
              cases bodyContextsEquality
              have bodyComplete : CompleteProgramElaboration pack catalog imports
                  program (symbolic.bindMany symbolicBindingsCase).globals
                  externalBindings :=
                by
                  simpa [SymbolicBodyContext.bindMany_eq] using complete
              obtain ⟨_groundBodyEquality, coreBodyEquality⟩ := exprUnique
                  (bodySymbolic := symbolic.bindMany symbolicBindingsCase)
                  (bodyConcrete := concrete.bindLocals concreteBindingsCase)
                  (bodyContexts := leftPattern.boundContexts)
                  bodyComplete leftBody rightBody
              cases coreBodyEquality
              cases induction leftTail rightTail
              rfl

/-- Recursive place specialization is functional assuming expression
    inference is functional for index expressions. This proof recurses only
    over the strictly smaller emitted base place, so it need not join the large
    generated mutual recursor. -/
private def placeDepth : Core.Place → Nat
  | .local _ => 0
  | .field base _ => placeDepth base + 1
  | .index base _ => placeDepth base + 1

theorem PlaceDerivationSpecializes.unique_of_expr
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (exprUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (left : PlaceDerivationSpecializes outer groundEnclosingReturn symbolic
      concrete contexts surface leftSymbolic leftGround leftCore)
    (right : PlaceDerivationSpecializes outer groundEnclosingReturn symbolic
      concrete contexts surface rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases left with
  | «local» leftSingle leftSymbolicResolved leftConcreteResolved
      leftTypeGrounds =>
      cases right with
      | «local» rightSingle rightSymbolicResolved rightConcreteResolved
          rightTypeGrounds =>
          have nameEquality := Option.some.inj
            (leftSingle.symm.trans rightSingle)
          cases nameEquality
          cases leftSymbolicResolved.unique rightSymbolicResolved
          cases leftConcreteResolved.unique rightConcreteResolved
          exact ⟨rfl, rfl, rfl⟩
  | selfValue leftSymbolicResolved leftConcreteResolved leftTypeGrounds =>
      cases right with
      | selfValue rightSymbolicResolved rightConcreteResolved rightTypeGrounds =>
          cases leftSymbolicResolved.unique rightSymbolicResolved
          cases leftConcreteResolved.unique rightConcreteResolved
          exact ⟨rfl, rfl, rfl⟩
  | field leftBase leftSymbolicSelected leftConcreteSelected leftFieldGrounds =>
      cases right with
      | field rightBase rightSymbolicSelected rightConcreteSelected
          rightFieldGrounds =>
          rcases PlaceDerivationSpecializes.unique_of_expr complete exprUnique
              leftBase rightBase with
            ⟨receiverTypeEquality, groundReceiverEquality, coreBaseEquality⟩
          cases receiverTypeEquality
          cases groundReceiverEquality
          cases coreBaseEquality
          cases complete.symbolicFieldResult_unique leftSymbolicSelected
            rightSymbolicSelected
          cases leftConcreteSelected.unique rightConcreteSelected
          exact ⟨rfl, rfl, rfl⟩
  | indexArray leftBase leftElementGrounds leftLengthGrounds leftIndex
      leftInteger =>
      cases right with
      | indexArray rightBase rightElementGrounds rightLengthGrounds rightIndex
          rightInteger =>
          rcases PlaceDerivationSpecializes.unique_of_expr complete exprUnique
              leftBase rightBase with
            ⟨baseTypeEquality, baseGroundEquality, coreBaseEquality⟩
          injection baseTypeEquality with elementTypeEquality lengthEquality
          injection baseGroundEquality with groundElementEquality
            groundLengthEquality
          cases elementTypeEquality
          cases lengthEquality
          cases groundElementEquality
          cases groundLengthEquality
          cases coreBaseEquality
          rcases exprUnique leftIndex rightIndex with ⟨rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
      | indexSlice rightBase rightElementGrounds rightIndex rightInteger =>
          rcases PlaceDerivationSpecializes.unique_of_expr complete exprUnique
              leftBase rightBase with ⟨baseTypeEquality, _, _⟩
          cases baseTypeEquality
  | indexSlice leftBase leftElementGrounds leftIndex leftInteger =>
      cases right with
      | indexArray rightBase rightElementGrounds rightLengthGrounds rightIndex
          rightInteger =>
          rcases PlaceDerivationSpecializes.unique_of_expr complete exprUnique
              leftBase rightBase with ⟨baseTypeEquality, _, _⟩
          cases baseTypeEquality
      | indexSlice rightBase rightElementGrounds rightIndex rightInteger =>
          rcases PlaceDerivationSpecializes.unique_of_expr complete exprUnique
              leftBase rightBase with
            ⟨baseTypeEquality, baseGroundEquality, coreBaseEquality⟩
          injection baseTypeEquality with elementTypeEquality
          injection baseGroundEquality with groundElementEquality
          cases elementTypeEquality
          cases groundElementEquality
          cases coreBaseEquality
          rcases exprUnique leftIndex rightIndex with ⟨rfl, rfl, rfl⟩
          exact ⟨rfl, rfl, rfl⟩
termination_by placeDepth leftCore
decreasing_by
  all_goals
    subst leftCore
    simp [placeDepth]

/-- Assignment inference is functional once place inference and contextual value
    checking are functional. The assignment operator never contributes a hidden
    result choice: every successful assignment has unit type and emits the Core
    place and value selected by those two child judgments. -/
theorem ExprInferenceDerivationSpecializes.assign_unique_of_expr
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (inferUnique : ∀ {surfaceExpr leftSymbolic leftGround leftCore
        rightSymbolic rightGround rightCore},
      ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr leftSymbolic leftGround leftCore →
        ExprInferenceDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr rightSymbolic rightGround rightCore →
        leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
          leftCore = rightCore)
    (checkUnique : ∀ {surfaceExpr expected leftGround leftCore
        rightGround rightCore},
      ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected leftGround leftCore →
        ExprCheckingDerivationSpecializes outer groundEnclosingReturn symbolic
          concrete contexts surfaceExpr expected rightGround rightCore →
        leftGround = rightGround ∧ leftCore = rightCore)
    (left : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.assign op surfacePlace surfaceValue)
      leftSymbolic leftGround leftCore)
    (right : ExprInferenceDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts (.assign op surfacePlace surfaceValue)
      rightSymbolic rightGround rightCore) :
    leftSymbolic = rightSymbolic ∧ leftGround = rightGround ∧
      leftCore = rightCore := by
  cases left with
  | assign leftPlace leftValue leftCoreGrounds leftTyped =>
      cases right with
      | assign rightPlace rightValue rightCoreGrounds rightTyped =>
          rcases PlaceDerivationSpecializes.unique_of_expr complete inferUnique
              leftPlace rightPlace with ⟨rfl, rfl, rfl⟩
          obtain ⟨_groundValueEquality, coreValueEquality⟩ :=
            checkUnique leftValue rightValue
          cases coreValueEquality
          exact ⟨rfl, rfl, rfl⟩

/-- In a complete program, recursive exact pattern specialization is a
    function. One source pattern, symbolic type, context, substitution, and
    incoming local-ID supply determine the ground type, emitted core pattern,
    both binding tables, and outgoing supply. -/
theorem CompleteProgramElaboration.patternSpecialization_unique
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : PatternDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surface symbolicType groundTypeLeft
      coreLeft symbolicBindingsLeft concreteBindingsLeft finalLeft)
    (right : PatternDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surface symbolicType groundTypeRight
      coreRight symbolicBindingsRight concreteBindingsRight finalRight) :
    groundTypeLeft = groundTypeRight ∧ coreLeft = coreRight ∧
      symbolicBindingsLeft = symbolicBindingsRight ∧
      concreteBindingsLeft = concreteBindingsRight ∧ finalLeft = finalRight := by
  refine PatternDerivationSpecializes.rec
    (motive_1 := fun symbolic concreteCase contextsCase next surface symbolicType
        groundLeft coreLeft symbolicBindingsLeft concreteBindingsLeft finalLeft _ =>
      CompleteProgramElaboration pack catalog imports program symbolic.globals
          externalBindings →
        ∀ groundRight coreRight symbolicBindingsRight concreteBindingsRight
            finalRight,
          PatternDerivationSpecializes outer groundEnclosingReturn symbolic
              concreteCase contextsCase next surface symbolicType groundRight coreRight
              symbolicBindingsRight concreteBindingsRight finalRight →
            groundLeft = groundRight ∧ coreLeft = coreRight ∧
              symbolicBindingsLeft = symbolicBindingsRight ∧
              concreteBindingsLeft = concreteBindingsRight ∧
              finalLeft = finalRight)
    (motive_2 := fun symbolic concreteCase contextsCase next surfaces symbolicTypes
        groundLeft coreLeft symbolicBindingsLeft concreteBindingsLeft finalLeft _ =>
      CompleteProgramElaboration pack catalog imports program symbolic.globals
          externalBindings →
        ∀ groundRight coreRight symbolicBindingsRight concreteBindingsRight
            finalRight,
          PatternListDerivationSpecializes outer groundEnclosingReturn symbolic
              concreteCase contextsCase next surfaces symbolicTypes groundRight coreRight
              symbolicBindingsRight concreteBindingsRight finalRight →
            groundLeft = groundRight ∧ coreLeft = coreRight ∧
              symbolicBindingsLeft = symbolicBindingsRight ∧
              concreteBindingsLeft = concreteBindingsRight ∧
              finalLeft = finalRight)
    ?_ ?_ ?_ ?_ ?_ ?_ ?_ left complete _ _ _ _ _ right
  · intro groundType symbolicCase concreteCase contextsCase nextCase symbolicType
      leftGrounds completeCase groundRight coreRight symbolicBindingsRight
      concreteBindingsRight finalRight rightCase
    cases rightCase with
    | wildcard rightGrounds =>
        have groundEquality := Option.some.inj
          (leftGrounds.symm.trans rightGrounds)
        subst groundRight
        exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  · intro path name groundType concreteCase nextCase symbolicCase contextsCase
      symbolicType leftSingle leftNotVariant leftGrounds leftBounded completeCase
      groundRight coreRight symbolicBindingsRight concreteBindingsRight finalRight
      rightCase
    cases rightCase with
    | bind rightSingle rightNotVariant rightGrounds rightBounded =>
        have nameEquality := Option.some.inj
          (leftSingle.symm.trans rightSingle)
        cases nameEquality
        have groundEquality := Option.some.inj
          (leftGrounds.symm.trans rightGrounds)
        subst groundRight
        exact ⟨rfl, rfl, rfl, rfl, rfl⟩
    | variant rightReceiver rightSelected rightArguments
        rightTypeArgumentsGround rightConstArgumentsGround
        rightPayloadSubstitute rightPayload rightArtifact rightBounded =>
        obtain ⟨symbol, resolved, _member, _declaration, _unique⟩ :=
          rightSelected.2.2
        exact (leftNotVariant symbol resolved).elim
  · intro text scalar value symbolicCase concreteCase contextsCase nextCase
      leftLowered completeCase groundRight coreRight symbolicBindingsRight
      concreteBindingsRight finalRight rightCase
    cases rightCase with
    | integer rightLowered =>
        cases leftLowered.core_unique rightLowered
        exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  · intro symbolicCase concreteCase contextsCase nextCase value completeCase
      groundRight coreRight symbolicBindingsRight concreteBindingsRight finalRight
      rightCase
    cases rightCase
    exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  · intro symbolicType symbolicCase path constructor inner symbolicTypeArguments
      symbolicConstArguments groundTypeArguments groundConstArguments
      expectedPayload concreteCase contextsCase nextCase surfacePayload
      groundPayload corePayload symbolicBindings concreteBindings final entry
      leftReceiver leftSelected leftArguments leftTypeArgumentsGround
      leftConstArgumentsGround leftPayloadSubstitute leftPayload leftArtifact
      leftBounded payloadInduction completeCase groundRight coreRight
      symbolicBindingsRight concreteBindingsRight finalRight rightCase
    cases rightCase with
    | bind rightSingle rightNotVariant rightGrounds rightBounded =>
        obtain ⟨symbol, resolved, _member, _declaration, _unique⟩ :=
          leftSelected.2.2
        exact (rightNotVariant symbol resolved).elim
    | variant rightReceiver rightSelected rightArguments
        rightTypeArgumentsGround rightConstArgumentsGround
        rightPayloadSubstitute rightPayload rightArtifact rightBounded =>
        cases completeCase.symbolicVariantConstructor_unique
          leftSelected rightSelected
        have receiverEquality := leftReceiver.symm.trans rightReceiver
        injection receiverEquality with sourceTypeEquality
          symbolicTypeArgumentsEquality symbolicConstArgumentsEquality
        cases sourceTypeEquality
        cases symbolicTypeArgumentsEquality
        cases symbolicConstArgumentsEquality
        obtain ⟨symbol, resolved, constructorMember, declaration, unique⟩ :=
          leftSelected.2.2
        have expectedPayloadEquality :=
          completeCase.variantPayloadSubstitute_unique constructorMember
            leftArguments rightArguments leftPayloadSubstitute
            rightPayloadSubstitute
        cases expectedPayloadEquality
        rcases payloadInduction completeCase _ _ _ _ _ rightPayload with
          ⟨rfl, rfl, rfl, rfl, rfl⟩
        have typeArgumentsEquality := Option.some.inj
          (leftTypeArgumentsGround.symm.trans rightTypeArgumentsGround)
        have constArgumentsEquality := Option.some.inj
          (leftConstArgumentsGround.symm.trans rightConstArgumentsGround)
        cases typeArgumentsEquality
        cases constArgumentsEquality
        obtain ⟨coreTypeEquality, variantEquality, _payloadEquality⟩ :=
          leftArtifact.agrees rightArtifact
        exact ⟨rfl, by simp [coreTypeEquality, variantEquality],
          rfl, rfl, rfl⟩
  · intro symbolicCase concreteCase contextsCase nextCase completeCase
      groundRight coreRight symbolicBindingsRight concreteBindingsRight finalRight
      rightCase
    cases rightCase
    exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  · intro symbolicCase concreteCase contextsCase nextCase surfaceHead symbolicHead
      groundHead coreHead symbolicHeadBindings concreteHeadBindings middle
      surfaceTail symbolicTail groundTail coreTail symbolicTailBindings
      concreteTailBindings final leftHead leftTail leftDistinct headInduction
      tailInduction completeCase groundRight coreRight symbolicBindingsRight
      concreteBindingsRight finalRight rightCase
    cases rightCase with
    | cons rightHead rightTail rightDistinct =>
        rcases headInduction completeCase _ _ _ _ _ rightHead with
          ⟨rfl, rfl, rfl, rfl, rfl⟩
        rcases tailInduction completeCase _ _ _ _ _ rightTail with
          ⟨rfl, rfl, rfl, rfl, rfl⟩
        exact ⟨rfl, rfl, rfl, rfl, rfl⟩

/-- The corresponding functionality theorem for recursive pattern lists. -/
theorem CompleteProgramElaboration.patternListSpecialization_unique
    (complete : CompleteProgramElaboration pack catalog imports program
      symbolic.globals externalBindings)
    (left : PatternListDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surfaces symbolicTypes groundTypesLeft
      coresLeft symbolicBindingsLeft concreteBindingsLeft finalLeft)
    (right : PatternListDerivationSpecializes outer groundEnclosingReturn
      symbolic concrete contexts next surfaces symbolicTypes groundTypesRight
      coresRight symbolicBindingsRight concreteBindingsRight finalRight) :
    groundTypesLeft = groundTypesRight ∧ coresLeft = coresRight ∧
      symbolicBindingsLeft = symbolicBindingsRight ∧
      concreteBindingsLeft = concreteBindingsRight ∧ finalLeft = finalRight := by
  refine PatternListDerivationSpecializes.rec
    (motive_1 := fun symbolic concreteCase contextsCase next surface symbolicType
        groundLeft coreLeft symbolicBindingsLeft concreteBindingsLeft finalLeft _ =>
      CompleteProgramElaboration pack catalog imports program symbolic.globals
          externalBindings →
        ∀ groundRight coreRight symbolicBindingsRight concreteBindingsRight
            finalRight,
          PatternDerivationSpecializes outer groundEnclosingReturn symbolic
              concreteCase contextsCase next surface symbolicType groundRight coreRight
              symbolicBindingsRight concreteBindingsRight finalRight →
            groundLeft = groundRight ∧ coreLeft = coreRight ∧
              symbolicBindingsLeft = symbolicBindingsRight ∧
              concreteBindingsLeft = concreteBindingsRight ∧
              finalLeft = finalRight)
    (motive_2 := fun symbolic concreteCase contextsCase next surfaces symbolicTypes
        groundLeft coreLeft symbolicBindingsLeft concreteBindingsLeft finalLeft _ =>
      CompleteProgramElaboration pack catalog imports program symbolic.globals
          externalBindings →
        ∀ groundRight coreRight symbolicBindingsRight concreteBindingsRight
            finalRight,
          PatternListDerivationSpecializes outer groundEnclosingReturn symbolic
              concreteCase contextsCase next surfaces symbolicTypes groundRight coreRight
              symbolicBindingsRight concreteBindingsRight finalRight →
            groundLeft = groundRight ∧ coreLeft = coreRight ∧
              symbolicBindingsLeft = symbolicBindingsRight ∧
              concreteBindingsLeft = concreteBindingsRight ∧
              finalLeft = finalRight)
    ?_ ?_ ?_ ?_ ?_ ?_ ?_ left complete _ _ _ _ _ right
  · intro groundType symbolicCase concreteCase contextsCase nextCase symbolicType
      leftGrounds completeCase groundRight coreRight symbolicBindingsRight
      concreteBindingsRight finalRight rightCase
    cases rightCase with
    | wildcard rightGrounds =>
        have groundEquality := Option.some.inj
          (leftGrounds.symm.trans rightGrounds)
        subst groundRight
        exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  · intro path name groundType concreteCase nextCase symbolicCase contextsCase
      symbolicType leftSingle leftNotVariant leftGrounds leftBounded completeCase
      groundRight coreRight symbolicBindingsRight concreteBindingsRight finalRight
      rightCase
    cases rightCase with
    | bind rightSingle rightNotVariant rightGrounds rightBounded =>
        have nameEquality := Option.some.inj
          (leftSingle.symm.trans rightSingle)
        cases nameEquality
        have groundEquality := Option.some.inj
          (leftGrounds.symm.trans rightGrounds)
        subst groundRight
        exact ⟨rfl, rfl, rfl, rfl, rfl⟩
    | variant rightReceiver rightSelected rightArguments
        rightTypeArgumentsGround rightConstArgumentsGround
        rightPayloadSubstitute rightPayload rightArtifact rightBounded =>
        obtain ⟨symbol, resolved, _member, _declaration, _unique⟩ :=
          rightSelected.2.2
        exact (leftNotVariant symbol resolved).elim
  · intro text scalar value symbolicCase concreteCase contextsCase nextCase
      leftLowered completeCase groundRight coreRight symbolicBindingsRight
      concreteBindingsRight finalRight rightCase
    cases rightCase with
    | integer rightLowered =>
        cases leftLowered.core_unique rightLowered
        exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  · intro symbolicCase concreteCase contextsCase nextCase value completeCase
      groundRight coreRight symbolicBindingsRight concreteBindingsRight finalRight
      rightCase
    cases rightCase
    exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  · intro symbolicType symbolicCase path constructor inner symbolicTypeArguments
      symbolicConstArguments groundTypeArguments groundConstArguments
      expectedPayload concreteCase contextsCase nextCase surfacePayload
      groundPayload corePayload symbolicBindings concreteBindings final entry
      leftReceiver leftSelected leftArguments leftTypeArgumentsGround
      leftConstArgumentsGround leftPayloadSubstitute leftPayload leftArtifact
      leftBounded payloadInduction completeCase groundRight coreRight
      symbolicBindingsRight concreteBindingsRight finalRight rightCase
    cases rightCase with
    | bind rightSingle rightNotVariant rightGrounds rightBounded =>
        obtain ⟨symbol, resolved, _member, _declaration, _unique⟩ :=
          leftSelected.2.2
        exact (rightNotVariant symbol resolved).elim
    | variant rightReceiver rightSelected rightArguments
        rightTypeArgumentsGround rightConstArgumentsGround
        rightPayloadSubstitute rightPayload rightArtifact rightBounded =>
        cases completeCase.symbolicVariantConstructor_unique
          leftSelected rightSelected
        have receiverEquality := leftReceiver.symm.trans rightReceiver
        injection receiverEquality with sourceTypeEquality
          symbolicTypeArgumentsEquality symbolicConstArgumentsEquality
        cases sourceTypeEquality
        cases symbolicTypeArgumentsEquality
        cases symbolicConstArgumentsEquality
        obtain ⟨symbol, resolved, constructorMember, declaration, unique⟩ :=
          leftSelected.2.2
        have expectedPayloadEquality :=
          completeCase.variantPayloadSubstitute_unique constructorMember
            leftArguments rightArguments leftPayloadSubstitute
            rightPayloadSubstitute
        cases expectedPayloadEquality
        rcases payloadInduction completeCase _ _ _ _ _ rightPayload with
          ⟨rfl, rfl, rfl, rfl, rfl⟩
        have typeArgumentsEquality := Option.some.inj
          (leftTypeArgumentsGround.symm.trans rightTypeArgumentsGround)
        have constArgumentsEquality := Option.some.inj
          (leftConstArgumentsGround.symm.trans rightConstArgumentsGround)
        cases typeArgumentsEquality
        cases constArgumentsEquality
        obtain ⟨coreTypeEquality, variantEquality, _payloadEquality⟩ :=
          leftArtifact.agrees rightArtifact
        exact ⟨rfl, by simp [coreTypeEquality, variantEquality],
          rfl, rfl, rfl⟩
  · intro symbolicCase concreteCase contextsCase nextCase completeCase
      groundRight coreRight symbolicBindingsRight concreteBindingsRight finalRight
      rightCase
    cases rightCase
    exact ⟨rfl, rfl, rfl, rfl, rfl⟩
  · intro symbolicCase concreteCase contextsCase nextCase surfaceHead symbolicHead
      groundHead coreHead symbolicHeadBindings concreteHeadBindings middle
      surfaceTail symbolicTail groundTail coreTail symbolicTailBindings
      concreteTailBindings final leftHead leftTail leftDistinct headInduction
      tailInduction completeCase groundRight coreRight symbolicBindingsRight
      concreteBindingsRight finalRight rightCase
    cases rightCase with
    | cons rightHead rightTail rightDistinct =>
        rcases headInduction completeCase _ _ _ _ _ rightHead with
          ⟨rfl, rfl, rfl, rfl, rfl⟩
        rcases tailInduction completeCase _ _ _ _ _ rightTail with
          ⟨rfl, rfl, rfl, rfl, rfl⟩
        exact ⟨rfl, rfl, rfl, rfl, rfl⟩

def SelectsEntrypointHeader
    (catalog : Declarations.Catalog)
    (selected : Declarations.DeclarationHeader) : Prop :=
  selected ∈ catalog.headers ∧
    selected.kind = .function ∧
    selected.name = some "main" ∧
    ∀ candidate,
      candidate ∈ catalog.headers →
      candidate.kind = .function →
      candidate.name = some "main" →
      candidate.declaration = selected.declaration

inductive EntrypointLowers
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (program : Core.Program)
    (context : SurfaceElaboration.Context)
    (executable : Execution.Executable) : Prop where
  | intro
      (header : Declarations.DeclarationHeader)
      (scheme : Static.FunctionScheme)
      (resolved : Static.FunctionInstance)
      (core : Core.Function)
      (selected : SelectsEntrypointHeader catalog header)
      (lowered : CollectedFunctionLowers pack catalog program context header scheme
        resolved core)
      (noParameters : core.parameters = [])
      (returnType : Execution.EntrypointReturnType core.returnType)
      (executableProgram : executable.program = program)
      (executableEntrypoint : executable.entrypoint = core.id)
      (wellFormed : Execution.ExecutableWellFormed executable) :
      EntrypointLowers pack catalog program context executable

structure CompleteExecutableElaboration
    (pack : Declarations.SourcePack)
    (catalog : Declarations.Catalog)
    (imports : List Declarations.CollectedImport)
    (program : Core.Program)
    (context : SurfaceElaboration.Context)
    (externalBindings : List ExternalBinding)
    (executable : Execution.Executable) : Prop where
  programElaboration : CompleteProgramElaboration pack catalog imports program
    context externalBindings
  entrypoint : EntrypointLowers pack catalog program context executable

end Lanius.ProgramElaboration
