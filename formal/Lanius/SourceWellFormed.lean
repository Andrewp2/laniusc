import Lanius.SurfaceElaboration

namespace Lanius.SourceWellFormed

open Lanius

/-- Declaration-body validation uses source names rather than monomorphic local
    IDs. Bindings are ordered from innermost to outermost so shadowing remains
    explicit. -/
structure Context where
  globals : SurfaceElaboration.Context
  locals : List Surface.Name := []

def Context.bind (context : Context) (name : Surface.Name) : Context :=
  { context with locals := name :: context.locals }

def Context.bindMany (context : Context) (names : List Surface.Name) : Context :=
  names.foldr (fun name result => result.bind name) context

inductive ResolvesLocal : List Surface.Name → Surface.Name → Prop where
  | head : ResolvesLocal (name :: outer) name
  | tail
      (different : head ≠ name)
      (resolved : ResolvesLocal outer name) :
      ResolvesLocal (head :: outer) name

theorem resolvesLocalMember
    (resolved : ResolvesLocal locals name) : name ∈ locals := by
  induction resolved with
  | head => simp
  | tail different resolved inductionHypothesis => simp [inductionHypothesis]

def NoLocalNamed (locals : List Surface.Name) (name : Surface.Name) : Prop :=
  ∀ candidate, candidate ∈ locals → candidate ≠ name

def GlobalPathNotShadowed (context : Context) (path : Surface.Path) : Prop :=
  match SurfaceElaboration.unqualifiedPathName? path with
  | some name => NoLocalNamed context.locals name
  | none => True

/-- An unqualified path already resolved as a lexical local cannot also pass
    the global-value shadowing guard. -/
theorem GlobalPathNotShadowed.excludesLocal
    (notShadowed : GlobalPathNotShadowed context path)
    (single : SurfaceElaboration.singleNamePath? path = some name)
    (resolved : ResolvesLocal context.locals name) : False := by
  unfold GlobalPathNotShadowed at notShadowed
  rw [SurfaceElaboration.singleNamePath_unqualified single] at notShadowed
  exact notShadowed name (resolvesLocalMember resolved) rfl

def SelectsConstant
    (context : Context) (path : Surface.Path)
    (selected : SurfaceElaboration.ConstantEntry) : Prop :=
  GlobalPathNotShadowed context path ∧ ∃ symbol,
    SurfaceElaboration.ResolvesGlobal context.globals .value path symbol ∧
    selected ∈ context.globals.constants ∧
    selected.declaration = symbol.declaration ∧
    ∀ candidate,
      candidate ∈ context.globals.constants →
      candidate.declaration = symbol.declaration → candidate = selected

/-- Name resolution fixes the declaration and the constant table's agreement
    clause fixes its unique metadata row. -/
theorem SelectsConstant.unique
    (leftSelected : SelectsConstant context path left)
    (rightSelected : SelectsConstant context path right) :
    left = right := by
  rcases leftSelected with
    ⟨_leftNotShadowed, leftSymbol, leftResolved, leftMember,
      leftDeclaration, leftUnique⟩
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
          have declarationEquality :
              rightSymbol.declaration = leftSymbol.declaration :=
            leftNameResolved.2 rightSymbol rightNameResolved.1 |>.2
          exact (leftUnique right rightMember
            (rightDeclaration.trans declarationEquality)).symm

def SelectsFunction
    (context : Context) (path : Surface.Path)
    (selected : Static.FunctionScheme) : Prop :=
  GlobalPathNotShadowed context path ∧ ∃ symbol,
    SurfaceElaboration.ResolvesGlobal context.globals .value path symbol ∧
    selected ∈ context.globals.functions ∧
    selected.declaration = symbol.declaration ∧
    ∀ candidate,
      candidate ∈ context.globals.functions →
      candidate.declaration = symbol.declaration → candidate = selected

/-- Callable path selection is functional for the same reason as constant
    selection: name resolution fixes a declaration and the table's agreement
    clause fixes its scheme row. -/
theorem SelectsFunction.unique
    (leftSelected : SelectsFunction context path left)
    (rightSelected : SelectsFunction context path right) :
    left = right := by
  rcases leftSelected with
    ⟨_leftNotShadowed, leftSymbol, leftResolved, leftMember,
      leftDeclaration, leftUnique⟩
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
          have declarationEquality :
              rightSymbol.declaration = leftSymbol.declaration :=
            leftNameResolved.2 rightSymbol rightNameResolved.1 |>.2
          exact (leftUnique right rightMember
            (rightDeclaration.trans declarationEquality)).symm

theorem SelectsFunction.member
    (selected : SelectsFunction context path scheme) :
    scheme ∈ context.globals.functions := by
  obtain ⟨_notShadowed, _symbol, _resolved, member, _declaration, _unique⟩ :=
    selected
  exact member

inductive ResolvesValuePath (context : Context) : Surface.Path → Prop where
  | local
      (single : SurfaceElaboration.singleNamePath? path = some name)
      (resolved : ResolvesLocal context.locals name) :
      ResolvesValuePath context path
  | constant (selected : SelectsConstant context path entry) :
      ResolvesValuePath context path

inductive ResolvesCallablePath (context : Context) : Surface.Path → Prop where
  | intrinsic
      (found : SurfaceElaboration.builtinIntrinsic? path = some intrinsic) :
      ResolvesCallablePath context path
  | function (selected : SelectsFunction context path scheme) :
      ResolvesCallablePath context path
  | variant
      (selected : SurfaceElaboration.SelectsVariantConstructor
        context.globals path constructor)
      (notIntrinsic : SurfaceElaboration.builtinIntrinsic? path = none) :
      ResolvesCallablePath context path

def PatternBindingsDistinct (bindings : List Surface.Name) : Prop :=
  bindings.Pairwise (· ≠ ·)

mutual
  inductive ExprWellScoped : Context → Surface.Expr → Prop where
    | literal : ExprWellScoped context (.literal literal)
    | path (resolved : ResolvesValuePath context path) :
        ExprWellScoped context (.path path)
    | selfValue (resolved : ResolvesLocal context.locals "self") :
        ExprWellScoped context .selfValue
    | array (elements : ExprsWellScoped context surfaceElements) :
        ExprWellScoped context (.array surfaceElements)
    | structValue
        (selected : SurfaceElaboration.SelectsStructConstructor
          context.globals path constructor)
        (fields : NamedExprsWellScoped context surfaceFields) :
        ExprWellScoped context (.structValue path surfaceFields)
    | unary (operand : ExprWellScoped context surfaceOperand) :
        ExprWellScoped context (.unary op surfaceOperand)
    | binary
        (left : ExprWellScoped context surfaceLeft)
        (right : ExprWellScoped context surfaceRight) :
        ExprWellScoped context (.binary op surfaceLeft surfaceRight)
    | assign
        (place : ExprWellScoped context surfacePlace)
        (value : ExprWellScoped context surfaceValue) :
        ExprWellScoped context (.assign op surfacePlace surfaceValue)
    | directCall
        (callee : ResolvesCallablePath context path)
        (arguments : ExprsWellScoped context surfaceArguments) :
        ExprWellScoped context (.call (.path path) surfaceArguments)
    | methodCall
        (receiver : ExprWellScoped context surfaceReceiver)
        (arguments : ExprsWellScoped context surfaceArguments) :
        ExprWellScoped context
          (.call (.member surfaceReceiver name) surfaceArguments)
    | index
        (base : ExprWellScoped context surfaceBase)
        (index : ExprWellScoped context surfaceIndex) :
        ExprWellScoped context (.index surfaceBase surfaceIndex)
    | member (base : ExprWellScoped context surfaceBase) :
        ExprWellScoped context (.member surfaceBase name)
    | matchValue
        (scrutinee : ExprWellScoped context surfaceScrutinee)
        (arms : MatchArmsWellScoped context surfaceArms) :
        ExprWellScoped context (.matchValue surfaceScrutinee surfaceArms)

  inductive ExprsWellScoped : Context → List Surface.Expr → Prop where
    | nil : ExprsWellScoped context []
    | cons
        (head : ExprWellScoped context surfaceHead)
        (tail : ExprsWellScoped context surfaceTail) :
        ExprsWellScoped context (surfaceHead :: surfaceTail)

  inductive NamedExprsWellScoped :
      Context → List (Surface.Name × Surface.Expr) → Prop where
    | nil : NamedExprsWellScoped context []
    | cons
        (value : ExprWellScoped context surfaceValue)
        (tail : NamedExprsWellScoped context surfaceTail) :
        NamedExprsWellScoped context
          ((name, surfaceValue) :: surfaceTail)

  inductive PatternWellScoped :
      Context → Surface.Pattern → List Surface.Name → Prop where
    | wildcard : PatternWellScoped context .wildcard []
    | bind
        (single : SurfaceElaboration.singleNamePath? path = some name)
        (notConstructor : SurfaceElaboration.NoGlobalValueResolution
          context.globals path) :
        PatternWellScoped context (.path path []) [name]
    | integer : PatternWellScoped context (.integer text) []
    | boolean : PatternWellScoped context (.boolean value) []
    | variant
        (selected : SurfaceElaboration.SelectsVariantConstructor
          context.globals path constructor)
        (payload : PatternsWellScoped context surfacePayload bindings)
        (distinct : PatternBindingsDistinct bindings) :
        PatternWellScoped context (.path path surfacePayload) bindings

  inductive PatternsWellScoped :
      Context → List Surface.Pattern → List Surface.Name → Prop where
    | nil : PatternsWellScoped context [] []
    | cons
        (head : PatternWellScoped context surfaceHead headBindings)
        (tail : PatternsWellScoped context surfaceTail tailBindings)
        (distinct : PatternBindingsDistinct (headBindings ++ tailBindings)) :
        PatternsWellScoped context (surfaceHead :: surfaceTail)
          (headBindings ++ tailBindings)

  inductive MatchArmsWellScoped :
      Context → List (Surface.Pattern × Surface.Expr) → Prop where
    | nil : MatchArmsWellScoped context []
    | cons
        (pattern : PatternWellScoped context surfacePattern bindings)
        (distinct : PatternBindingsDistinct bindings)
        (body : ExprWellScoped (context.bindMany bindings) surfaceBody)
        (tail : MatchArmsWellScoped context surfaceTail) :
        MatchArmsWellScoped context
          ((surfacePattern, surfaceBody) :: surfaceTail)
end

inductive RangeBoundWellScoped (context : Context) :
    Surface.RangeBound → Prop where
  | integer : RangeBoundWellScoped context (.integer text)
  | postfix
      (formed : Surface.RangeBoundPostfix surfaceExpression)
      (expression : ExprWellScoped context surfaceExpression) :
      RangeBoundWellScoped context (.postfix surfaceExpression)

inductive OptionalRangeBoundWellScoped (context : Context) :
    Option Surface.RangeBound → Prop where
  | none : OptionalRangeBoundWellScoped context none
  | some (bound : RangeBoundWellScoped context surfaceBound) :
      OptionalRangeBoundWellScoped context (some surfaceBound)

inductive ForIterableWellScoped (context : Context) :
    Surface.ForIterable → Prop where
  | path (expression : ExprWellScoped context (.path path)) :
      ForIterableWellScoped context (.path path)
  | range
      (start : OptionalRangeBoundWellScoped context surfaceStart)
      (stop : OptionalRangeBoundWellScoped context surfaceStop) :
      ForIterableWellScoped context (.range kind surfaceStart surfaceStop)

mutual
  inductive StmtsWellScoped :
      Context → Bool → List Surface.Stmt → Prop where
    | nil : StmtsWellScoped context inLoop []
    | expression
        (head : ExprWellScoped context surfaceExpression)
        (tail : StmtsWellScoped context inLoop surfaceTail) :
        StmtsWellScoped context inLoop
          (.expression surfaceExpression :: surfaceTail)
    | letLocal
        (initializer : OptionalExprWellScoped context surfaceInitializer)
        (tail : StmtsWellScoped (context.bind name) inLoop surfaceTail) :
        StmtsWellScoped context inLoop
          (.letLocal name surfaceType surfaceInitializer :: surfaceTail)
    | returnValue
        (value : OptionalExprWellScoped context surfaceValue)
        (tail : StmtsWellScoped context inLoop surfaceTail) :
        StmtsWellScoped context inLoop
          (.returnValue surfaceValue :: surfaceTail)
    | ifThenElse
        (condition : ExprWellScoped context surfaceCondition)
        (thenBody : StmtsWellScoped context inLoop surfaceThen)
        (elseBody : StmtsWellScoped context inLoop surfaceElse)
        (tail : StmtsWellScoped context inLoop surfaceTail) :
        StmtsWellScoped context inLoop
          (.ifThenElse surfaceCondition surfaceThen surfaceElse :: surfaceTail)
    | whileLoop
        (condition : ExprWellScoped context surfaceCondition)
        (body : StmtsWellScoped context true surfaceBody)
        (tail : StmtsWellScoped context inLoop surfaceTail) :
        StmtsWellScoped context inLoop
          (.whileLoop surfaceCondition surfaceBody :: surfaceTail)
    | forLoop
        (iterable : ForIterableWellScoped context surfaceIterable)
        (body : StmtsWellScoped (context.bind name) true surfaceBody)
        (tail : StmtsWellScoped context inLoop surfaceTail) :
        StmtsWellScoped context inLoop
          (.forLoop name surfaceIterable surfaceBody :: surfaceTail)
    | breakLoop
        (inside : inLoop = true)
        (tail : StmtsWellScoped context inLoop surfaceTail) :
        StmtsWellScoped context inLoop (.breakLoop :: surfaceTail)
    | continueLoop
        (inside : inLoop = true)
        (tail : StmtsWellScoped context inLoop surfaceTail) :
        StmtsWellScoped context inLoop (.continueLoop :: surfaceTail)
    | block
        (body : StmtsWellScoped context inLoop surfaceBody)
        (tail : StmtsWellScoped context inLoop surfaceTail) :
        StmtsWellScoped context inLoop (.block surfaceBody :: surfaceTail)

  inductive OptionalExprWellScoped :
      Context → Option Surface.Expr → Prop where
    | none : OptionalExprWellScoped context none
    | some (expression : ExprWellScoped context surfaceExpression) :
        OptionalExprWellScoped context (some surfaceExpression)
end

def parameterName : Surface.Parameter → Surface.Name
  | .named name _ => name
  | .selfValue _ | .selfReference => "self"

def ParameterNamesUnique (parameters : List Surface.Parameter) : Prop :=
  (parameters.map parameterName).Pairwise (· ≠ ·)

def FunctionBodyWellScoped
    (globals : SurfaceElaboration.Context)
    (parameters : List Surface.Parameter) (body : List Surface.Stmt) : Prop :=
  ParameterNamesUnique parameters ∧
    StmtsWellScoped {
      globals
      locals := parameters.map parameterName
    } false body

end Lanius.SourceWellFormed
