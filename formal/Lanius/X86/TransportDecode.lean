import Lanius.X86.Transport
import Lanius.Execution

namespace Lanius.X86.Transport

open Lanius Lanius.Core

/-! A total parser for the canonical transport words.  Every parser returns the
    unconsumed suffix, so the outer decoder can reject truncation and trailing
    words.  The parser is deliberately separate from the encoder; the final
    `check` is the small canonicality boundary used by callers that need an
    `Executable`. -/

def nat? (word : Int) : Option Nat :=
  if word < 0 then none else some word.toNat

def byte? (word : Int) : Option UInt8 :=
  if 0 ≤ word ∧ word < 256 then some (UInt8.ofNat word.toNat) else none

def word32? (word : Int) : Option Nat :=
  if -2147483648 ≤ word ∧ word < 2147483648 then
    if word < 0 then some (word + 4294967296).toNat else some word.toNat
  else none

def takeWords : Nat → List Int → Option (List Int × List Int)
  | 0, words => some ([], words)
  | n + 1, word :: words => do
      let (taken, rest) ← takeWords n words
      return (word :: taken, rest)
  | _, [] => none

def unary? : Int → Option UnaryOp
  | 0 => some .positive | 1 => some .logicalNot | 2 => some .negate | _ => none

def binary? : Int → Option BinaryOp
  | 0 => some .logicalAnd | 1 => some .logicalOr | 2 => some .equal
  | 3 => some .notEqual | 4 => some .less | 5 => some .lessEqual
  | 6 => some .greater | 7 => some .greaterEqual | 8 => some .add
  | 9 => some .subtract | 10 => some .multiply | 11 => some .divide
  | 12 => some .remainder | 13 => some .bitAnd | 14 => some .bitOr
  | 15 => some .bitXor | 16 => some .shiftLeft | 17 => some .shiftRight
  | _ => none

def assign? : Int → Option AssignOp
  | 0 => some .set | 1 => some .add | 2 => some .subtract
  | 3 => some .multiply | 4 => some .divide | 5 => some .remainder
  | 6 => some .bitXor | 7 => some .shiftLeft | 8 => some .shiftRight
  | 9 => some .bitAnd | 10 => some .bitOr | _ => none

def type? : Int → Option Ty
  | 1 => some (.scalar (.signed .i32))
  | 2 => some (.scalar .bool)
  | 3 => some (.scalar (.unsigned .usize))
  | 4 => some (.scalar .rawPtr)
  | 5 => some (.scalar .string)
  | 6 => some (.slice (.scalar (.signed .i32)))
  | tag =>
      if 1073741824 ≤ tag ∧ tag < 2147483632 then
        some (.slice (.structure (tag - 1073741824).toNat))
      else if 16 ≤ tag ∧ tag < 1073741824 then
        some (.structure (tag - 16).toNat)
      else none

def resultType? (tag : Int) : Option Ty :=
  if tag = 0 then some .unit else type? tag

/-- Nominal wire tags carry an ID, while declaration layouts carry the kind.
    Resolve the kind once after parsing those layouts rather than guessing at
    each occurrence of the type tag. -/
def resolveNominalTy (enumerations : List EnumDecl) : Ty → Ty
  | .structure id =>
      if enumerations.any (fun declaration => declaration.id == id) then
        .enumeration id
      else .structure id
  | .slice element => .slice (resolveNominalTy enumerations element)
  | .array element length => .array (resolveNominalTy enumerations element) length
  | .reference referent => .reference (resolveNominalTy enumerations referent)
  | type => type

def resolveNominalStmt (enumerations : List EnumDecl) : Stmt → Stmt
  | .sequence first second =>
      .sequence (resolveNominalStmt enumerations first)
        (resolveNominalStmt enumerations second)
  | .letLocal id type initializer body =>
      .letLocal id (resolveNominalTy enumerations type) initializer
        (resolveNominalStmt enumerations body)
  | .letUninitialized id type body =>
      .letUninitialized id (resolveNominalTy enumerations type)
        (resolveNominalStmt enumerations body)
  | .ifThenElse condition thenBranch elseBranch =>
      .ifThenElse condition (resolveNominalStmt enumerations thenBranch)
        (resolveNominalStmt enumerations elseBranch)
  | .whileLoop condition body =>
      .whileLoop condition (resolveNominalStmt enumerations body)
  | .forValues id iterable body =>
      .forValues id iterable (resolveNominalStmt enumerations body)
  | .forRange id start stop inclusive body =>
      .forRange id start stop inclusive (resolveNominalStmt enumerations body)
  | statement => statement

def resolveNominalProgram (program : Program) : Program :=
  let enumerations := program.enumerations
  { program with
    structures := program.structures.map fun declaration =>
      { declaration with fields := declaration.fields.map (resolveNominalTy enumerations) }
    enumerations := enumerations.map fun declaration =>
      { declaration with variants :=
          declaration.variants.map (fun fields => fields.map (resolveNominalTy enumerations)) }
    constants := program.constants.map fun constant =>
      { constant with type := resolveNominalTy enumerations constant.type }
    functions := program.functions.map fun function =>
      { function with
        parameters := function.parameters.map fun (id, type) =>
          (id, resolveNominalTy enumerations type)
        returnType := resolveNominalTy enumerations function.returnType
        body := function.body.map (resolveNominalStmt enumerations) } }

def scalar? : Int → Option ScalarTy
  | 1 => some (.signed .i32) | 3 => some (.unsigned .usize) | _ => none

def service? : Int → Option HostService
  | 1 => some .alloc | 2 => some .openRead | 3 => some .close
  | 4 => some .read | 5 => some .writeStdout | 6 => some .writeByte
  | 7 => some .argc | 8 => some .argLen | 9 => some .argRead | _ => none

def bytes? (words : List Int) : Option (String × List Int) := do
  let (length, words) ← match words with | length :: words => some (length, words) | [] => none
  let length ← nat? length
  let (raw, words) ← takeWords length words
  let bytes ← raw.mapM byte?
  let value ← String.fromUTF8? ⟨bytes.toArray⟩
  return (value, words)

def unsigned? (words : List Int) : Option (Nat × List Int) := do
  let (low, words) ← match words with | x :: xs => some (x, xs) | [] => none
  let (high, words) ← match words with | x :: xs => some (x, xs) | [] => none
  let low ← word32? low
  let high ← word32? high
  return (low + 4294967296 * high, words)

def get : List Int → Option (Int × List Int)
  | word :: words => some (word, words) | [] => none

def getNat (words : List Int) : Option (Nat × List Int) := do
  let (word, rest) ← get words; let word ← nat? word; return (word, rest)

def structId? (tag : Int) : Option TypeId :=
  if 16 ≤ tag ∧ tag < 1073741824 then some (tag - 16).toNat else none

def mkConstant (id : ConstantId) (type : Ty) (value : Value) (rest : List Int) :
    Option (Constant × List Int) := some ({
      id := id
      type := type
      value := value }, rest)

mutual
  def parseExpr : Nat → List Int → Option (Expr × List Int)
    | 0, _ => none
    | fuel + 1, word :: words => match word with
      | 0 => do let (value, rest) ← parseValue words; return (.value value, rest)
      | 1 => do let (id, rest) ← getNat words; return (.local id, rest)
      | 2 => do let (tag, rest) ← get words; let target ← scalar? tag; let (x, rest) ← parseExpr fuel rest; return (.cast target x, rest)
      | 3 => do let (tag, rest) ← get words; let op ← unary? tag; let (x, rest) ← parseExpr fuel rest; return (.unary op x, rest)
      | 4 => do let (tag, rest) ← get words; let op ← binary? tag; let (x, rest) ← parseExpr fuel rest; let (y, rest) ← parseExpr fuel rest; return (.binary op x y, rest)
      | 7 => do let (x, rest) ← parseExpr fuel words; let (y, rest) ← parseExpr fuel rest; return (.index x y, rest)
      | 8 => do let (tag, rest) ← get words; let id ← structId? tag; let (n, rest) ← getNat rest; let (xs, rest) ← parseExprs fuel n rest; return (.structValue id xs, rest)
      | 9 => do let (field, rest) ← getNat words; let (x, rest) ← parseExpr fuel rest; return (.field x field, rest)
      | 12 => do let (tag, rest) ← get words; let op ← assign? tag; let (p, rest) ← parsePlace fuel rest; let (x, rest) ← parseExpr fuel rest; return (.assign op p x, rest)
      | 13 => do let (id, rest) ← getNat words; return (.constant id, rest)
      | 14 => do let (fn, rest) ← getNat words; let (n, rest) ← getNat rest; let (xs, rest) ← parseExprs fuel n rest; return (.call fn xs, rest)
      | 15 => do let (x, rest) ← parseExpr fuel words; let (y, rest) ← parseExpr fuel rest; return (.i32SliceFromRawParts x y, rest)
      | 16 => do let (x, rest) ← parseExpr fuel words; return (.i32SliceDataPtr x, rest)
      | 17 => do let (x, rest) ← parseExpr fuel words; return (.stringDataPtr x, rest)
      | 22 => do
          let (kind, rest) ← get words
          let (id, rest) ← getNat rest
          let element ← match kind with
            | 0 => some (.structure id)
            | 1 => some (.enumeration id)
            | 2 => if id = 0 then some (.scalar (.signed .i32)) else none
            | _ => none
          let (pointer, rest) ← parseExpr fuel rest
          let (length, rest) ← parseExpr fuel rest
          return (.typedSliceFromRawParts element pointer length, rest)
      | _ => none
    | _, [] => none

  def parseValue : List Int → Option (Value × List Int)
    | tag :: words => match tag with
      | 1 => do let (value, rest) ← get words; return (.signed .i32 value, rest)
      | 2 => do let (value, rest) ← get words; if value = 0 then return (.boolean false, rest) else if value = 1 then return (.boolean true, rest) else none
      | 3 => do let (value, rest) ← unsigned? words; return (.unsigned .usize value, rest)
      | 4 => match words with | 0 :: 0 :: rest => some (.pointer 0, rest) | _ => none
      | 5 => do let (value, rest) ← bytes? words; return (.string value, rest)
      | _ => none
    | [] => none

  def parsePlace : Nat → List Int → Option (Place × List Int)
    | 0, _ => none
    | fuel + 1, word :: words => match word with
      | 0 => do let (id, rest) ← getNat words; return (.local id, rest)
      | 1 => do let (field, rest) ← getNat words; let (base, rest) ← parsePlace fuel rest; return (.field base field, rest)
      | 2 => do let (base, rest) ← parsePlace fuel words; let (index, rest) ← parseExpr fuel rest; return (.index base index, rest)
      | _ => none
    | _, [] => none

  def parseStmt : Nat → List Int → Option (Stmt × List Int)
    | 0, _ => none
    | fuel + 1, word :: words => match word with
      | 0 => some (.skip, words)
      | 1 => do let (expression, rest) ← parseExpr fuel words; return (.expression expression, rest)
      | 2 => do let (x, rest) ← parseStmt fuel words; let (y, rest) ← parseStmt fuel rest; return (.sequence x y, rest)
      | 3 => do let (id, rest) ← getNat words; let (tag, rest) ← get rest; let type ← type? tag; let (x, rest) ← parseExpr fuel rest; let (body, rest) ← parseStmt fuel rest; return (.letLocal id type x body, rest)
      | 4 => do let (id, rest) ← getNat words; let (tag, rest) ← get rest; let type ← type? tag; let (body, rest) ← parseStmt fuel rest; return (.letUninitialized id type body, rest)
      | 5 => do let (c, rest) ← parseExpr fuel words; let (x, rest) ← parseStmt fuel rest; let (y, rest) ← parseStmt fuel rest; return (.ifThenElse c x y, rest)
      | 6 => do let (c, rest) ← parseExpr fuel words; let (body, rest) ← parseStmt fuel rest; return (.whileLoop c body, rest)
      | 10 => do
          let (present, rest) ← get words
          if present = 0 then return (.returnValue none, rest)
          else if present = 1 then
            let (x, rest) ← parseExpr fuel rest
            return (.returnValue (some x), rest)
          else none
      | 11 => some (.breakLoop, words)
      | 12 => some (.continueLoop, words)
      | _ => none
    | _, [] => none

  def parseExprs : Nat → Nat → List Int → Option (List Expr × List Int)
    | _, 0, words => some ([], words)
    | 0, _, _ => none
    | fuel + 1, count + 1, words => do
        let (head, rest) ← parseExpr fuel words; let (tail, rest) ← parseExprs fuel count rest; return (head :: tail, rest)

  def parseTypes : Nat → List Int → Option (List Ty × List Int)
    | 0, words => some ([], words)
    | count + 1, words => do
        let (tag, rest) ← get words; let type ← type? tag; let (tail, rest) ← parseTypes count rest; return (type :: tail, rest)

  def parseParams : Nat → Nat → List Int → Option (List (VarId × Ty) × List Int)
    | _, 0, words => some ([], words)
    | 0, _, _ => none
    | fuel + 1, count + 1, words => do
        let (id, rest) ← getNat words; let (tag, rest) ← get rest; let type ← type? tag; let (tail, rest) ← parseParams fuel count rest; return ((id, type) :: tail, rest)

  def parseVariants : Nat → List Int → Option (List (List Ty) × List Int)
    | 0, words => some ([], words)
    | count + 1, words => do
        let (fieldCount, words) ← getNat words
        let (fields, words) ← parseTypes fieldCount words
        let (tail, words) ← parseVariants count words
        return (fields :: tail, words)

  def parseTypeLayout : List Int → Option (Sum StructDecl EnumDecl × List Int)
    | length :: words => do
        let length ← nat? length
        let (layout, rest) ← takeWords length words
        let id :: kind :: count :: fields := layout | none
        let id ← nat? id
        let count ← nat? count
        match kind with
        | 0 => do
            let (fields, leftover) ← parseTypes count fields
            if ¬ leftover.isEmpty then none else
              return (.inl { id := id, fields := fields }, rest)
        | 1 => do
            let (variants, leftover) ← parseVariants count fields
            if ¬ leftover.isEmpty then none else
              return (.inr { id := id, variants := variants }, rest)
        | _ => none
    | _ => none

  def parseTypeLayouts : Nat → Nat → List Int →
      Option ((List StructDecl × List EnumDecl) × List Int)
    | _, 0, words => some (([], []), words)
    | 0, _, _ => none
    | fuel + 1, count + 1, words => do
        let (head, rest) ← parseTypeLayout words
        let ((structures, enumerations), rest) ← parseTypeLayouts fuel count rest
        match head with
        | .inl declaration => return ((declaration :: structures, enumerations), rest)
        | .inr declaration => return ((structures, declaration :: enumerations), rest)

  def parseConstant : List Int → Option (Constant × List Int)
    | id :: tag :: words => do
        let id ← nat? id
        match tag with
        | 1 => do
            let (value, rest) ← get words
            let (zero, rest) ← get rest
            if zero ≠ 0 then none else
              mkConstant id (.scalar (.signed .i32)) (.signed .i32 value) rest
        | 2 => do
            let (value, rest) ← get words
            let (zero, rest) ← get rest
            if zero ≠ 0 then none else if value = 0 then
              mkConstant id (.scalar .bool) (.boolean false) rest
            else if value = 1 then
              mkConstant id (.scalar .bool) (.boolean true) rest
            else none
        | 3 => do
            let (value, rest) ← unsigned? words
            mkConstant id (.scalar (.unsigned .usize)) (.unsigned .usize value) rest
        | 4 => match words with
            | 0 :: 0 :: rest =>
                mkConstant id (.scalar .rawPtr) (.pointer 0) rest
            | _ => none
        | 5 => do
            let (value, rest) ← bytes? words
            mkConstant id (.scalar .string) (.string value) rest
        | _ => none
    | _ => none

  def parseConstants : Nat → Nat → List Int → Option (List Constant × List Int)
    | _, 0, words => some ([], words)
    | 0, _, _ => none
    | fuel + 1, count + 1, words => do
        let (head, rest) ← parseConstant words
        let (tail, rest) ← parseConstants fuel count rest
        return (head :: tail, rest)

  def parseFunction : Nat → List Int → Option (Function × List Int)
    | 0, _ => none
    | fuel + 1, kind :: target :: id :: result :: parameterCount :: bodyLength :: words => do
        if target ≠ 64 then none else
        let id ← nat? id
        let result ← resultType? result
        let parameterCount ← nat? parameterCount
        let bodyLength ← nat? bodyLength
        let (parameters, words) ← parseParams fuel parameterCount words
        let (bodyWords, rest) ← takeWords bodyLength words
        match kind with
        | 1 => do
            let (body, leftover) ← parseStmt fuel bodyWords
            if ¬ leftover.isEmpty then none else do
              let function : Function := {
                id := id
                parameters := parameters
                returnType := result
                body := some body }
              return (function, rest)
        | 2 => do
            if bodyLength ≠ 1 then none
            let serviceWord ← bodyWords.head?
            let service ← service? serviceWord
            if parameters.map Prod.snd ≠ service.parameterTypes ∨ result ≠ service.returnType then none
            let function : Function := {
              id := id
              parameters := parameters
              returnType := result
              body := none
              external := some (.host service) }
            return (function, rest)
        | _ => none
    | _, _ => none

  def parseFunctions : Nat → Nat → List Int → Option (List Function × List Int)
    | _, 0, words => some ([], words)
    | 0, _, _ => none
    | fuel + 1, count + 1, length :: words => do
        let length ← nat? length
        let (chunk, rest) ← takeWords length words
        let (head, leftover) ← parseFunction fuel chunk
        if ¬ leftover.isEmpty then none else
          let (tail, rest) ← parseFunctions fuel count rest
          return (head :: tail, rest)
    | _, _, _ => none

  def parseProgram : Nat → List Int → Option ((FunctionId × Program) × List Int)
    | 0, _ => none
    | fuel + 1, version :: target :: entry :: typeCount :: constantCount :: functionCount :: words => do
        if version ≠ 3 ∨ target ≠ 64 then none else
        let entry ← nat? entry
        let typeCount ← nat? typeCount
        let constantCount ← nat? constantCount
        let functionCount ← nat? functionCount
        let ((structures, enumerations), words) ← parseTypeLayouts fuel typeCount words
        let (constants, words) ← parseConstants fuel constantCount words
        let (functions, words) ← parseFunctions fuel functionCount words
        let program : Program := {
          target := Target.x86_64
          structures := structures
          enumerations := enumerations
          constants := constants
          functions := functions }
        return ((entry, resolveNominalProgram program), words)
    | _, _ => none

end

def decodeProgram (words : List Int) : Option (FunctionId × Program) := do
  let ((entry, program), rest) ← parseProgram (words.length + 1) words
  if rest.isEmpty then some (entry, program) else none

def decodeExecutable (words : List Int) : Option Lanius.Execution.Executable := do
  let (entry, program) ← decodeProgram words
  if encodeProgram entry program = some words then
    some {
      entrypoint := entry
      program := program }
  else none

theorem decodeExecutable_sound {words : List Int} {executable : Lanius.Execution.Executable}
    (h : decodeExecutable words = some executable) :
    encodeProgram executable.entrypoint executable.program = some words := by
  unfold decodeExecutable at h
  cases hd : decodeProgram words with
  | none => simp [hd] at h
  | some x =>
    simp [hd] at h
    rcases h with ⟨canonical, rfl⟩
    exact canonical

end Lanius.X86.Transport
