import Lanius.TypedIR.Surface.Builtin
import Lanius.TypedIR.Surface.Labels
import Lean.Elab.Quotation
import Lean.Elab.Term
import Lean.Elab.MutualDef
import Lean.Meta.Reduce
import Lean.Parser.Do

namespace Lanius.TypedIR.Surface
open Lean Lean.Elab Lean.Elab.Term Lean.Meta
open Lean.Parser.Term
open Labels

scoped syntax:75 "+" term:75 : term
declare_syntax_cat namedAssignOp
syntax "+=" : namedAssignOp
syntax "-=" : namedAssignOp
syntax "*=" : namedAssignOp
syntax "/=" : namedAssignOp
syntax "%=" : namedAssignOp
syntax "^=" : namedAssignOp
syntax "<<=" : namedAssignOp
syntax ">>=" : namedAssignOp
syntax "&=" : namedAssignOp
syntax "|=" : namedAssignOp
scoped syntax (name := namedStore) term:arg namedAssignOp term : doElem
scoped syntax (name := namedUninitialized) "let " ident " : " term : doElem
declare_syntax_cat sourceParameter
syntax ident " := " term : sourceParameter

/-- Labels resolve source names; only the Core data is stored in the body. -/
private structure Node where
  label : Lean.Expr
  core : Lean.Expr
deriving Inhabited

private structure Binding where
  label : Lean.Expr
  id : Lean.Expr

private structure Context where
  ids : Array Nat
  result : Lean.Expr
  locals : List (Name × Binding) := []
  labelScope : LocalContext

private abbrev BuildM := ReaderT Context (StateT Nat TermElabM)

private def sourceType (input : Syntax) : BuildM Lean.Expr := do
  withLCtx (← read).labelScope (← getLocalInstances) (elabType input)

private def ctor (name : Name) (arguments : Array Lean.Expr := #[]) : Lean.Expr :=
  mkAppN (mkConst name) arguments

private def list (type : Name) (values : Array Lean.Expr) : Lean.Expr :=
  values.foldr (fun value tail => mkApp3 (mkConst ``List.cons [0]) (mkConst type) value tail)
    (mkApp (mkConst ``List.nil [0]) (mkConst type))

private def typeLabel : TermElabM Lean.Expr := mkFreshExprMVar (mkSort 1)

-- Only IDs of declarations currently being elaborated. Header locals use
-- Lean's name resolver; bodies remain ordinary data.
private initialize functionIds : EnvExtension (NameMap Nat) ← registerEnvExtension (pure {})

private def functionId (target parameters result : Lean.Expr) : TermElabM Lean.Expr := do
  if let some fvar := target.fvarId? then
    if let some name := (← getLCtx).auxDeclToFullName.get? fvar then
      if let some id := (functionIds.getState (← getEnv)).find? (privateToUserName name) then
        return mkNatLit id
  whnf (ctor ``Core.Function.id #[ctor ``Function.core #[parameters, result, target]])

/-- Build resolved constants once, without a second value table or typing proof. -/
scoped elab "constant" "(" idKey:ident ":=" id:term ")" value:term : term <= expected => do
  unless idKey.getId == `id do throwUnsupportedSyntax
  let expected ← whnf expected
  unless expected.isAppOfArity ``Constant 1 do throwError "constant label required"
  let label := expected.getAppArgs[0]!
  let type ← coreType label
  let scalar := type.getAppArgs[0]?.getD type
  let signed (value : Int) : TermElabM Lean.Expr := do
    unless type.isAppOfArity ``Core.Ty.scalar 1 && scalar.isAppOfArity ``Core.ScalarTy.signed 1 do
      throwError "signed constant label required"
    return ctor ``Core.Value.signed #[scalar.getAppArgs[0]!, mkIntLit value]
  let literal ← match value with
    | `(true) => pure (ctor ``Core.Value.boolean #[ctor ``Bool.true])
    | `(false) => pure (ctor ``Core.Value.boolean #[ctor ``Bool.false])
    | `($text:str) => pure (ctor ``Core.Value.string #[mkStrLit text.getString])
    | `(- $number:num) => signed (-Int.ofNat number.getNat)
    | `($number:num) =>
        if type.isAppOfArity ``Core.Ty.scalar 1 && scalar.isAppOfArity ``Core.ScalarTy.unsigned 1 then
          pure (ctor ``Core.Value.unsigned #[scalar.getAppArgs[0]!, mkNatLit number.getNat])
        else if type.isAppOfArity ``Core.Ty.scalar 1 && scalar.isConstOf ``Core.ScalarTy.rawPtr then
          pure (ctor ``Core.Value.pointer #[mkNatLit number.getNat])
        else signed (Int.ofNat number.getNat)
    | _ => throwErrorAt value "resolved constant literal required"
  let id ← elabTermEnsuringType id (some (ctor ``Nat))
  return ctor ``Constant.mk #[label, ctor ``Core.Constant.mk #[id, type, literal]]

private def nextId : BuildM Lean.Expr := do
  let cursor ← get
  let some id := (← read).ids[cursor]? | throwError "missing resolved binding ID"
  set (cursor + 1)
  return mkNatLit id

private def withBinding (name : Name) (binding : Binding) (action : BuildM α) : BuildM α :=
  withReader (fun ctx => { ctx with locals := (name, binding) :: ctx.locals }) action

private def recordFields (owner : Lean.Expr) : TermElabM (Array (Name × Lean.Expr)) := do
  let (owner, info) ← nominal owner
  let [constructor] := info.ctors | throwError "record label required"
  constructorFields owner (← getConstInfoCtor constructor)

private def field (owner : Lean.Expr) (name : Name) : TermElabM (Lean.Expr × Lean.Expr) := do
  let fields ← recordFields owner
  for (fieldName, label) in fields, index in [:fields.size] do
    if fieldName == name then return (label, mkNatLit index)
  throwError "unknown source field {name} in {owner}"

private def sliceElement (label : Lean.Expr) : TermElabM Lean.Expr := do
  let label ← whnf label
  unless label.isAppOfArity ``Slice 1 do throwError "slice label required"
  return label.getAppArgs[0]!

private def binding (input : Syntax) : BuildM Binding := do
  if let some (_, value) := (← read).locals.find? (·.1 == input.getId) then return value
  let value ← elabTerm input none
  let type ← whnf (← inferType value)
  unless type.isAppOfArity ``Var 1 do throwErrorAt input "variable reference required"
  let label := type.getAppArgs[0]!
  return ⟨label, ← whnf (ctor ``Var.id #[label, value])⟩

private def unwrap (value : Lean.Expr) : TermElabM Node := do
  let type ← whnf (← inferType value)
  unless type.isAppOfArity ``Expr 1 do throwError "source expression required"
  let label := type.getAppArgs[0]!
  return ⟨label, ← whnf (ctor ``Expr.core #[label, value])⟩

private def atom (input : Syntax) : BuildM Node := do
  if let some (_, value) := (← read).locals.find? (·.1 == input.getId) then
    return ⟨value.label, ctor ``Core.Expr.local #[value.id]⟩
  withLCtx (← read).labelScope (← getLocalInstances) do
    let value ← elabTerm input none
    let type ← whnf (← inferType value)
    if type.isAppOfArity ``Var 1 then
      let label := type.getAppArgs[0]!
      return ⟨label, ctor ``Core.Expr.local #[← whnf (ctor ``Var.id #[label, value])]⟩
    if type.isAppOfArity ``Constant 1 then
      let label := type.getAppArgs[0]!
      return ⟨label, ctor ``Core.Expr.constant #[← whnf (ctor ``Constant.id #[label, value])]⟩
    unwrap (← mkAppM ``Expr.atom #[value])

private def resolveVariant (owner : Lean.Expr) (name : Name) : TermElabM Lean.Expr := do
  let (owner, info) ← nominal owner
  -- Reserved Lean auxiliary names are escaped by the printer with this prefix.
  let some constructor := info.ctors.find? (fun candidate =>
    candidate.getString! == name.toString ||
      candidate.getString! == "constructor:" ++ name.toString)
    | throwError "unknown source constructor {name} in {owner}"
  let constructor ← getConstInfoCtor constructor
  let fields ← constructorFields owner constructor
  let payload ← mkListLit (mkSort 1) (fields.map (·.2)).toList
  return ctor ``Variant.mk #[owner, payload,
    ← nominalId owner ``Core.Ty.enumeration, mkNatLit constructor.cidx]

private def variantParts (value : Lean.Expr) :
    TermElabM (Lean.Expr × Lean.Expr × Lean.Expr × Lean.Expr) := do
  let type ← whnf (← inferType value)
  unless type.isAppOfArity ``Variant 2 do throwError "constructor reference required"
  let owner := type.getAppArgs[0]!
  let payload := type.getAppArgs[1]!
  return (owner, payload, ← whnf (ctor ``Variant.typeId #[owner, payload, value]),
    ← whnf (ctor ``Variant.ordinal #[owner, payload, value]))

private def payloadLabels (types : Lean.Expr) : TermElabM (Array Lean.Expr) := do
  let mut types := types
  let mut labels := #[]
  repeat
    types ← whnf types
    if types.isAppOfArity ``List.nil 1 then return labels
    unless types.isAppOfArity ``List.cons 3 do throwError "resolved type-label list required"
    labels := labels.push types.getAppArgs[1]!
    types := types.getAppArgs[2]!

private def binary? (input : TSyntax `term) :
    Option (Name × Bool × TSyntax `term × TSyntax `term) :=
  match input with
  | `($left:term + $right:term) => some (``Core.BinaryOp.add, false, left, right)
  | `($left:term - $right:term) => some (``Core.BinaryOp.subtract, false, left, right)
  | `($left:term * $right:term) => some (``Core.BinaryOp.multiply, false, left, right)
  | `($left:term / $right:term) => some (``Core.BinaryOp.divide, false, left, right)
  | `($left:term % $right:term) => some (``Core.BinaryOp.remainder, false, left, right)
  | `($left:term &&& $right:term) => some (``Core.BinaryOp.bitAnd, false, left, right)
  | `($left:term ||| $right:term) => some (``Core.BinaryOp.bitOr, false, left, right)
  | `($left:term ^^^ $right:term) => some (``Core.BinaryOp.bitXor, false, left, right)
  | `($left:term <<< $right:term) => some (``Core.BinaryOp.shiftLeft, false, left, right)
  | `($left:term >>> $right:term) => some (``Core.BinaryOp.shiftRight, false, left, right)
  | `($left:term == $right:term) => some (``Core.BinaryOp.equal, true, left, right)
  | `($left:term != $right:term) => some (``Core.BinaryOp.notEqual, true, left, right)
  | `($left:term < $right:term) => some (``Core.BinaryOp.less, true, left, right)
  | `($left:term <= $right:term) => some (``Core.BinaryOp.lessEqual, true, left, right)
  | `($left:term > $right:term) => some (``Core.BinaryOp.greater, true, left, right)
  | `($left:term >= $right:term) => some (``Core.BinaryOp.greaterEqual, true, left, right)
  | `($left:term && $right:term) => some (``Core.BinaryOp.logicalAnd, true, left, right)
  | `($left:term || $right:term) => some (``Core.BinaryOp.logicalOr, true, left, right)
  | _ => none

private def assignOp (input : TSyntax `namedAssignOp) : Option Name :=
  match input with
  | `(namedAssignOp| +=) => some ``Core.AssignOp.add
  | `(namedAssignOp| -=) => some ``Core.AssignOp.subtract
  | `(namedAssignOp| *=) => some ``Core.AssignOp.multiply
  | `(namedAssignOp| /=) => some ``Core.AssignOp.divide
  | `(namedAssignOp| %=) => some ``Core.AssignOp.remainder
  | `(namedAssignOp| ^=) => some ``Core.AssignOp.bitXor
  | `(namedAssignOp| <<=) => some ``Core.AssignOp.shiftLeft
  | `(namedAssignOp| >>=) => some ``Core.AssignOp.shiftRight
  | `(namedAssignOp| &=) => some ``Core.AssignOp.bitAnd
  | `(namedAssignOp| |=) => some ``Core.AssignOp.bitOr
  | _ => none

private def assignment? (input : Syntax) :
    Option (Name × TSyntax `term × TSyntax `term) :=
  match input with
  | `(doElem| $target:term $operation:namedAssignOp $value:term) =>
      (assignOp operation).map (·, target, value)
  | `(doReassign| $target:ident := $value:term) =>
      some (``Core.AssignOp.set, ⟨target.raw⟩, value)
  | `(doReassign| $target:term := $value:term) =>
      some (``Core.AssignOp.set, target, value)
  | _ => none

private def primitive (name : Name) (values : Array Node) (expected? : Option Lean.Expr) :
    TermElabM Node := do
  let cores := values.map (·.core)
  let unary (result : Lean.Expr) (operation : Name) : TermElabM Node := do
    unless cores.size == 1 do throwError "unary primitive requires one operand"
    return ⟨result, ctor operation cores⟩
  let binary (result : Lean.Expr) (operation : Name) : TermElabM Node := do
    unless cores.size == 2 do throwError "binary primitive requires two operands"
    return ⟨result, ctor operation cores⟩
  match name.getString! with
  | "toI32" | "toUsize" =>
      unless cores.size == 1 do throwError "cast requires one operand"
      let signed := name.getString! == "toI32"
      let scalar := if signed then ctor ``Core.ScalarTy.signed #[ctor ``Core.SignedIntTy.i32]
        else ctor ``Core.ScalarTy.unsigned #[ctor ``Core.UnsignedIntTy.usize]
      return ⟨ctor (if signed then ``I32 else ``Usize),
        ctor ``Core.Expr.cast #[scalar, cores[0]!]⟩
  | "i32SliceFromRawParts" =>
      binary (ctor ``Slice #[ctor ``I32]) ``Core.Expr.i32SliceFromRawParts
  | "typedSliceFromRawParts" =>
      unless cores.size == 2 do throwError "slice construction requires two operands"
      let some label := expected? | throwError "typed slice construction requires its result label"
      let element ← sliceElement label
      return ⟨label, ctor ``Core.Expr.typedSliceFromRawParts #[← coreType element, cores[0]!, cores[1]!]⟩
  | "i32SliceDataPtr" => unary (ctor ``RawPtr) ``Core.Expr.i32SliceDataPtr
  | "stringDataPtr" => unary (ctor ``RawPtr) ``Core.Expr.stringDataPtr
  | "pointerAdd" | "pointerSubtract" =>
      unless cores.size == 2 do throwError "pointer arithmetic requires two operands"
      let operation := if name.getString! == "pointerAdd" then ``Core.BinaryOp.add else ``Core.BinaryOp.subtract
      return ⟨ctor ``RawPtr, ctor ``Core.Expr.binary #[ctor operation, cores[0]!, cores[1]!]⟩
  | _ => throwError "unknown source primitive {name}"

mutual
  private partial def expression (input : TSyntax `term)
      (expected? : Option Lean.Expr := none) : BuildM Node := withRef input do
    if let some (operation, boolean, left, right) := binary? input then
      let left ← expression left
      let right ← expression right
      return ⟨if boolean then ctor ``Bool else left.label,
        ctor ``Core.Expr.binary #[ctor operation, left.core, right.core]⟩
    match input with
    | `(true) => return ⟨ctor ``Bool, ctor ``Core.Expr.value #[ctor ``Core.Value.boolean #[ctor ``Bool.true]]⟩
    | `(false) => return ⟨ctor ``Bool, ctor ``Core.Expr.value #[ctor ``Core.Value.boolean #[ctor ``Bool.false]]⟩
    | `($value:str) => return ⟨ctor ``String, ctor ``Core.Expr.value #[ctor ``Core.Value.string #[mkStrLit value.getString]]⟩
    | `($value:num) => return ⟨ctor ``I32, ctor ``Core.Expr.value #[ctor ``Core.Value.signed
        #[ctor ``Core.SignedIntTy.i32, ctor ``Int.ofNat #[mkNatLit value.getNat]]]⟩
    | `(($value:num : $type:term)) =>
        let label ← sourceType type
        let dictionary ← synthInstance (ctor ``NaturalLiteral #[label])
        return ⟨label, ctor ``Core.Expr.value #[← reduce (ctor ``NaturalLiteral.value #[label, dictionary, mkNatLit value.getNat])]⟩
    | `(($value:term : $type:term)) =>
        expression value (some (← sourceType type))
    | `(($value:term)) => expression value expected?
    | `({ $fields:structInstField,* : $owner:term }) =>
        let owner ← sourceType owner
        let mut supplied : NameMap (TSyntax `term) := {}
        for field in fields.getElems do
          let `(structInstField| $name:ident := $value:term) := field | throwUnsupportedSyntax
          if supplied.contains name.getId then throwErrorAt name "duplicate source field {name.getId}"
          supplied := supplied.insert name.getId value
        let mut values := #[]
        -- Lanius lowers initializers in declaration order. Preserve that
        -- order (including effects), while using names to select each value.
        for (name, label) in ← recordFields owner do
          let some value := supplied.find? name | throwError "missing source field {name}"
          supplied := supplied.erase name
          values := values.push (← expression value (some label)).core
        unless supplied.isEmpty do throwError "unknown source field in record construction"
        return ⟨owner, ctor ``Core.Expr.structValue
          #[← nominalId owner ``Core.Ty.structure, list ``Core.Expr values]⟩
    | `(+ $value:term) => unary ``Core.UnaryOp.positive value false
    | `(- $value:num) =>
        -- Lanius lowers the signed-minimum spelling as one literal; its
        -- positive magnitude is not an intermediate i32 expression.
        if value.getNat == 2147483648 then
          return ⟨ctor ``I32, ctor ``Core.Expr.value #[ctor ``Core.Value.signed
            #[ctor ``Core.SignedIntTy.i32, mkIntLit (-2147483648)]]⟩
        unary ``Core.UnaryOp.negate value false
    | `(- $value:term) => unary ``Core.UnaryOp.negate value false
    | `(!$value:term) => unary ``Core.UnaryOp.logicalNot value true
    | `($base:term[$index:term]) =>
        let base ← expression base
        let index ← expression index
        return ⟨← sliceElement base.label, ctor ``Core.Expr.index #[base.core, index.core]⟩
    | `($base:term.$name:ident) =>
        let base ← expression base
        let (label, index) ← field base.label name.getId
        return ⟨label, ctor ``Core.Expr.field #[base.core, index]⟩
    | `($name:ident) => atom name
    | `(match $discriminant:matchDiscr with $arms:matchAlt*) =>
        let `(matchDiscr| $scrutinee:term) := discriminant | throwUnsupportedSyntax
        let scrutinee ← expression scrutinee
        let mut values := #[]
        let mut label? := expected?
        for arm in arms do
          let (pattern, body) ← matchArm arm scrutinee.label label?
          if label?.isNone then label? := some body.label
          values := values.push (mkApp4 (mkConst ``Prod.mk [0, 0]) (ctor ``Core.Pattern) (ctor ``Core.Expr) pattern body.core)
        let some label := label? | throwError "match requires at least one arm"
        let pairType := mkApp2 (mkConst ``Prod [0, 0]) (ctor ``Core.Pattern) (ctor ``Core.Expr)
        return ⟨label, ctor ``Core.Expr.matchValue #[scrutinee.core, ← mkListLit pairType values.toList]⟩
    | `($callee:ident ()) => application callee #[] expected?
    | `(.$name:ident $payload:term*) => constructor name payload expected?
    | `(.$name:ident) => constructor name #[] expected?
    | `($callee:ident $payload:term*) => application callee payload expected?
    | _ =>
        let label ← match expected? with | some label => pure label | none => typeLabel
        unwrap (← elabTermEnsuringType input (some (ctor ``Expr #[label])))

  private partial def unary (operation : Name) (input : TSyntax `term)
      (boolean : Bool) : BuildM Node := do
    let value ← expression input
    return ⟨if boolean then ctor ``Bool else value.label, ctor ``Core.Expr.unary #[ctor operation, value.core]⟩

  private partial def application (callee : TSyntax `ident)
      (arguments : Array (TSyntax `term)) (expected? : Option Lean.Expr) : BuildM Node := do
    -- Resolve primitive names without instantiating their Lean implicit
    -- arguments: their source labels below already determine the Core data.
    let target ← match ← resolveId? callee (withInfo := true) with
      | some target => pure target
      | none => elabTerm callee none
    let values ← arguments.mapM fun argument => expression argument
    if let some name := target.getAppFn.constName? then
      if name.getPrefix == `Lanius.TypedIR.Surface.Builtin then
        return ← primitive name values expected?
    let type ← whnf (← inferType target)
    let values := list ``Core.Expr (values.map (·.core))
    if type.isAppOfArity ``Function 2 then
      let parameters := type.getAppArgs[0]!
      let result := type.getAppArgs[1]!
      return ⟨result, ctor ``Core.Expr.call #[← functionId target parameters result, values]⟩
    if type.isAppOfArity ``Variant 2 then
      let (owner, _, id, ordinal) ← variantParts target
      return ⟨owner, ctor ``Core.Expr.enumValue #[id, ordinal, values]⟩
    unwrap (← mkAppM ``Expr.apply #[target, ctor ``Args.mk #[values]])

  private partial def constructor (name : TSyntax `ident)
      (arguments : Array (TSyntax `term)) (expected? : Option Lean.Expr) : BuildM Node := do
    let some owner := expected? | throwErrorAt name "constructor requires an owner label"
    let (_, _, id, ordinal) ← variantParts (← resolveVariant owner name.getId)
    let values ← arguments.mapM fun argument => return (← expression argument).core
    return ⟨owner, ctor ``Core.Expr.enumValue #[id, ordinal, list ``Core.Expr values]⟩

  private partial def place (input : TSyntax `term) : BuildM Node := withRef input do
    match input with
    | `(($value:term)) => place value
    | `($base:term.$name:ident) =>
        let base ← place base
        let (label, index) ← field base.label name.getId
        return ⟨label, ctor ``Core.Place.field #[base.core, index]⟩
    | `($base:term[$index:term]) =>
        let base ← place base
        let index ← expression index
        return ⟨← sliceElement base.label, ctor ``Core.Place.index #[base.core, index.core]⟩
    | `($name:ident) =>
        let value ← binding name
        return ⟨value.label, ctor ``Core.Place.local #[value.id]⟩
    | _ => throwUnsupportedSyntax

  private partial def matchArm (input : TSyntax ``matchAlt)
      (owner : Lean.Expr) (expected? : Option Lean.Expr) : BuildM (Lean.Expr × Node) := do
    let `(matchAltExpr| | $pattern:term => $body:term) := input.raw | throwUnsupportedSyntax
    match pattern with
    | `(_) => return (ctor ``Core.Pattern.wildcard, ← expression body expected?)
    | `(.$name:ident $bindings:ident*) =>
        variantArm (← resolveVariant owner name.getId) bindings body expected?
    | `(.$name:ident) =>
        variantArm (← resolveVariant owner name.getId) #[] body expected?
    | `($name:ident $bindings:ident*) =>
        variantArm (← elabTerm name none) bindings body expected?
    | `($name:ident) =>
        variantArm (← elabTerm name none) #[] body expected?
    | _ => throwUnsupportedSyntax

  private partial def variantArm (target : Lean.Expr) (bindings : Array (TSyntax `ident))
      (body : TSyntax `term) (expected? : Option Lean.Expr) : BuildM (Lean.Expr × Node) := do
    let (_, types, id, ordinal) ← variantParts target
    let labels ← payloadLabels types
    unless labels.size == bindings.size do throwError "constructor binding count does not match its payload"
    let mut locals := (← read).locals
    let mut patterns := #[]
    for name in bindings, label in labels do
      let bindingId ← nextId
      patterns := patterns.push (ctor ``Core.Pattern.bind #[bindingId])
      locals := (name.getId, ⟨label, bindingId⟩) :: locals
    let body ← withReader (fun ctx => { ctx with locals }) (expression body expected?)
    return (ctor ``Core.Pattern.enumVariant #[id, ordinal, list ``Core.Pattern patterns], body)
end

private partial def statements (elements : List DoElem) : BuildM Lean.Expr := do
  let sequence (current : Lean.Expr) (rest : List DoElem) : BuildM Lean.Expr := do
    if rest.isEmpty then return current
    return ctor ``Core.Stmt.sequence #[current, ← statements rest]
  match elements with
  | [] => return ctor ``Core.Stmt.skip
  | element :: rest => withRef element do
      if let some (operation, target, value) := assignment? element.raw then
        let target ← place target
        let value ← expression value (some target.label)
        return ← sequence (ctor ``Core.Stmt.expression
          #[ctor ``Core.Expr.assign #[ctor operation, target.core, value.core]]) rest
      match element.raw with
      | `(doNested| do $body) =>
          sequence (← statements (getDoElems body).toList) rest
      | `(doWhile| while $condition:doIfCond do $body) =>
          let `(doIfCond|$condition) := condition | throwUnsupportedSyntax
          let condition ← expression condition
          let body ← statements (getDoElems body).toList
          sequence (ctor ``Core.Stmt.whileLoop #[condition.core, body]) rest
      | `(doElem| skip) => sequence (ctor ``Core.Stmt.skip) rest
      | `(doIf| if $condition:doIfCond then $thenSeq else $elseSeq) =>
          let `(doIfCond|$condition) := condition | throwUnsupportedSyntax
          let condition ← expression condition
          let yes ← statements (getDoElems thenSeq).toList
          let no ← statements (getDoElems elseSeq).toList
          sequence (ctor ``Core.Stmt.ifThenElse #[condition.core, yes, no]) rest
      | `(doReturn| return) =>
          unless rest.isEmpty do throwUnsupportedSyntax
          return ctor ``Core.Stmt.returnValue #[mkApp (mkConst ``Option.none [0]) (ctor ``Core.Expr)]
      | `(doReturn| return $value:term) =>
          unless rest.isEmpty do throwUnsupportedSyntax
          let value ← expression value (some (← read).result)
          return ctor ``Core.Stmt.returnValue #[mkApp2 (mkConst ``Option.some [0]) (ctor ``Core.Expr) value.core]
      | `(doLet| let $name:ident : $type:term := $initializer:term) =>
          let id ← nextId
          let label ← sourceType type
          let initializer ← expression initializer (some label)
          let body ← withBinding name.getId ⟨label, id⟩ (statements rest)
          return ctor ``Core.Stmt.letLocal #[id, ← coreType label, initializer.core, body]
      | `(doElem| let $name:ident : $type:term) =>
          let id ← nextId
          let label ← sourceType type
          let body ← withBinding name.getId ⟨label, id⟩ (statements rest)
          return ctor ``Core.Stmt.letUninitialized #[id, ← coreType label, body]
      | `(doExpr| $value:term) =>
          sequence (ctor ``Core.Stmt.expression #[(← expression value).core]) rest
      | _ => throwUnsupportedSyntax

/-- Source notation constructs ordinary Core data directly. It resolves names
    and binds the IDs already chosen by Lanius; it does not check Lanius typing
    or manufacture proofs. The kernel checks the resulting Lean definition. -/
scoped elab "function" "(" idKey:ident ":=" id:term "," nameKey:ident ":=" name:term ","
    argumentsKey:ident ":=" "[" arguments:sourceParameter,* "]" ","
    bindingsKey:ident ":=" "[" ids:num,* "]"
    ")" "do" body:doSeq : term <= expected => do
  unless idKey.getId == `id && nameKey.getId == `name
      && argumentsKey.getId == `arguments && bindingsKey.getId == `bindings do
    throwUnsupportedSyntax
  let expected ← whnf expected
  unless expected.isAppOfArity ``Function 2 do throwError "function signature required"
  let parameters := expected.getAppArgs[0]!
  let result := expected.getAppArgs[1]!
  let id ← elabTermEnsuringType id (some (ctor ``Nat))
  let name ← elabTermEnsuringType name (some (ctor ``String))
  -- The signature supplies labels once. Parameter names and resolved IDs go
  -- straight into the notation context and Core declaration, without a Vars
  -- value or a second set of Lean let bindings for the same parameters.
  let labels ← payloadLabels parameters
  let arguments := arguments.getElems
  unless arguments.size == labels.size do throwError "parameter count does not match the signature"
  let mut locals := []
  let mut parameterData := #[]
  let parameterType := mkApp2 (mkConst ``Prod [0, 0]) (ctor ``Nat) (ctor ``Core.Ty)
  for argument in arguments, label in labels do
    let `(sourceParameter| $name:ident := $value:term) := argument | throwUnsupportedSyntax
    let id ← match value.raw.isNatLit? with
      | some value => pure (mkNatLit value)
      | none => elabTermEnsuringType value (some (ctor ``Nat))
    locals := (name.getId, ⟨label, id⟩) :: locals
    parameterData := parameterData.push <| mkApp4 (mkConst ``Prod.mk [0, 0])
      (ctor ``Nat) (ctor ``Core.Ty) id (← coreType label)
  let ids ← ids.getElems.mapM fun id =>
    match id.raw.isNatLit? with
    | some value => pure value
    | none => throwErrorAt id "resolved binding ID must be a natural literal"
  let mut labelScope ← getLCtx
  -- Ordinary type/constant names cannot refer to these function declarations.
  -- Keep captured Lean locals, but avoid scanning every forward function when
  -- resolving each label or constant. Callee resolution retains the full scope.
  let sourceIds := functionIds.getState (← getEnv)
  let forwardNames := labelScope.auxDeclToFullName.toList
  if labelScope.decls.size == forwardNames.length &&
      forwardNames.all (fun (_, name) => sourceIds.contains (privateToUserName name)) then
    labelScope := {}
  else
    for (fvar, name) in forwardNames do
      if sourceIds.contains (privateToUserName name) then
        labelScope := labelScope.erase fvar
  let (body, consumed) ← ((statements (getDoElems body).toList).run { ids, result, locals, labelScope }).run 0
  unless consumed == ids.size do throwError "unused resolved binding IDs"
  let parameterList ← mkListLit parameterType parameterData.toList
  let declaration := ctor ``Core.Function.mk #[id, parameterList, ← coreType result,
    mkApp2 (mkConst ``Option.some [0]) (ctor ``Core.Stmt) body,
    mkApp (mkConst ``Option.none [0]) (ctor ``Core.ExternalBehavior)]
  return ctor ``Function.mk #[parameters, result, name, declaration]

/-- Declare each source function once, including forward and recursive calls.
    The temporary index contains header IDs only, never bodies or typing facts. -/
scoped syntax (name := functionDeclarations) "mutual" &"functions" ppLine
    (Lean.Parser.Command.declaration ppLine)+ "end" : command

-- Closed source-function data needs local header names, but no Lean
-- recursive closure conversion. Reuse ordinary nonrecursive declaration
-- admission, including kernel checking, compilation, docs, and attributes.
private partial def elabClosedFunctions (views : Array DefView) : TermElabM Bool := do
  -- Let Lean manage section parameters, module export policy, and attributed
  -- declarations. The generated closed definitions need none of these steps.
  if (← getEnv).header.isModule then return false
  unless (← getLCtx).decls.isEmpty do return false
  unless views.all (fun view => view.kind == .def && view.binders.getNumArgs == 0 &&
      view.type?.isSome && view.deriving?.isNone && view.modifiers.attrs.isEmpty &&
      !view.modifiers.isUnsafe && !view.modifiers.isNoncomputable &&
      !view.modifiers.isPartial && !view.modifiers.isMeta && !view.modifiers.isNonrec &&
      !view.modifiers.isProtected) do
    return false
  let .ok (some headers) state ← Term.observing <| withoutErrToSorry do
      let mut headers : Array (DefView × ExpandDeclIdResult × Lean.Expr) := #[]
      for view in views do
        let name ← Term.expandDeclId (← getCurrNamespace) (← getLevelNames) view.declId view.modifiers
        unless name.levelNames.isEmpty do return none
        let type ← withRef view.headerRef <| withDeclName name.declName <| elabType view.type?.get!
        synthesizeSyntheticMVarsNoPostponing
        let type ← instantiateMVars type
        unless type.isAppOfArity ``Function 2 && !type.hasMVar && !type.hasFVar &&
            !type.hasSorry do return none
        headers := headers.push (view, name, type)
      return some headers
    | return false
  state.restore (restoreInfo := true)
  let saved ← Term.saveState
  let accepted ← withHeaders headers.toList do
    let mut definitions := #[]
    for (view, name, type) in headers do
      let `(Parser.Command.declVal| := $body:term) := view.value | throwUnsupportedSyntax
      let value ← withRef view.ref <| withDeclName name.declName do
        let value ← elabTermEnsuringType body (some type)
        synthesizeSyntheticMVarsNoPostponing
        instantiateMVars value
      if value.hasFVar || value.hasMVar || value.hasSorry then
        return false
      definitions := definitions.push ({
        ref := view.declId, kind := .def, levelParams := [], modifiers := view.modifiers,
        declName := name.declName, binders := view.binders, type, value,
        termination := default : PreDefinition })
    let shared ← shareCommonPreDefs definitions
    for definition in shared do
      addAndCompileNonRec (← getLCtx, ← getLocalInstances) definition
    for (view, name, _) in headers do
      addDeclarationRangesForBuiltin name.declName view.modifiers.stx view.ref
    return true
  unless accepted do saved.restore (restoreInfo := true)
  return accepted
where
  withHeaders (headers : List (DefView × ExpandDeclIdResult × Lean.Expr))
      (action : TermElabM Bool) : TermElabM Bool :=
    match headers with
    | [] => action
    | (view, name, type) :: rest =>
        withAuxDecl name.shortName type name.declName fun fvar => do
          addLocalVarInfo view.declId fvar
          withHeaders rest action

@[command_elab functionDeclarations] def elabFunctionDeclarations : Command.CommandElab := fun stx => do
  let declarations : Array (TSyntax `command) := stx[2].getArgs.map fun declaration => ⟨declaration⟩
  let previous := functionIds.getState (← getEnv)
  let mut ids := previous
  let mut views := #[]
  for declaration in declarations do
    unless declaration.raw.isOfKind ``Lean.Parser.Command.declaration do
      throwErrorAt declaration "expected a source function definition"
    let modifiers ← Lean.Elab.elabModifiers ⟨declaration.raw[0]⟩
    let view ← Command.mkDefView modifiers declaration.raw[1]
    views := views.push view
    let `(Parser.Command.declVal| := $body:term) := view.value
      | throwErrorAt declaration "expected a source function definition"
    let id ← match body with
      | `(function ($_:ident := $id:num, $_:ident := $_:term,
          $_:ident := [$_:sourceParameter,*], $_:ident := [$_:num,*]) do $_) => pure id.getNat
      | `($callee:ident (id := $id:num) (name := $_:term)
          (arguments := $_:term) (behavior := $_:term)) => do
          let target ← Command.liftTermElabM <| resolveId? callee
          unless target.any (·.isConstOf ``Function.external) do
            throwErrorAt callee "expected Function.external"
          pure id.getNat
      | _ => throwErrorAt body "expected a function with a resolved numeric ID"
    let name ← Command.liftTermElabM do
      return (← Term.expandDeclId (← getCurrNamespace) (← getLevelNames)
        view.declId modifiers).declName
    ids := ids.insert (privateToUserName name) id
  modifyEnv (functionIds.setState · ids)
  try
    unless ← Command.runTermElabM (fun _ => elabClosedFunctions views) do
      Command.elabCommand (← `(mutual $declarations:command* end))
  finally
    modifyEnv (functionIds.setState · previous)

end Lanius.TypedIR.Surface
