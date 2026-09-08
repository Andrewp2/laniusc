import Lanius.Extraction.Source.Statement
import Lanius.Extraction.BufferCopy.CanonicalizeSource
import Lanius.Extraction.BufferCopy.RecognizeSource
import Lanius.Core.Equality

namespace Lanius.Extraction.Frontend

open Lanius.Core Lanius.Extraction.Source

/-- The source-level lexer invocation and result-count binding. The remaining
body contains the status/storage guards and subsequent frontend stages. -/
structure LexerPrefix where
  sourceId : Lanius.VarId
  sourceLengthId : Lanius.VarId
  rawId : Lanius.VarId
  rawLengthId : Lanius.VarId
  lexedId : Lanius.VarId
  countId : Lanius.VarId
  resultType : Lanius.TypeId
  lexerId : Lanius.FunctionId
  countFunction : Lanius.FunctionId
  rest : Stmt

def LexerPrefix.arguments (region : LexerPrefix) : List Expr :=
  [.local region.sourceId, .local region.sourceLengthId, .local region.rawId,
    .binary .divide (.local region.rawLengthId) (.value (.signed .i32 3))]

def LexerPrefix.body (region : LexerPrefix) : Stmt :=
  .letLocal region.lexedId (.structure region.resultType) (.call region.lexerId region.arguments)
    (.letLocal region.countId (.scalar (.signed .i32))
      (.call region.countFunction [.local region.lexedId]) region.rest)

def checkLexerPrefix? : (statement : Stmt) → Option (CheckedStatement LexerPrefix.body statement)
  | .letLocal lexedId (.structure resultType)
      (.call lexerId [.local sourceId, .local sourceLengthId, .local rawId,
        .binary .divide (.local rawLengthId) (.value (.signed .i32 3))])
      (.letLocal countId (.scalar (.signed .i32)) (.call countFunction [.local resultId]) rest) =>
    if matched : resultId = lexedId ∧ countId ≠ lexedId then
      some ⟨⟨sourceId, sourceLengthId, rawId, rawLengthId, lexedId, countId,
        resultType, lexerId, countFunction, rest⟩, by rcases matched with ⟨rfl, _⟩; rfl⟩
    else none
  | _ => none

def findLexerPrefix? := findStatement? LexerPrefix.body checkLexerPrefix?

structure AfterLexer where
  lexedId : Lanius.VarId
  countId : Lanius.VarId
  capacityId : Lanius.VarId
  statusFunction : Lanius.FunctionId
  successId : Lanius.ConstantId
  lexicalFailure : Stmt
  storageFailure : Stmt
  rest : Stmt

def AfterLexer.statusCondition (region : AfterLexer) : Expr :=
  .binary .notEqual (.call region.statusFunction [.local region.lexedId]) (.constant region.successId)

def capacityCondition (countId capacityId : Lanius.VarId) : Expr :=
  .unary .logicalNot (.binary .lessEqual (.local countId)
    (.binary .divide (.local capacityId) (.value (.signed .i32 3))))

def AfterLexer.body (region : AfterLexer) : Stmt :=
  .sequence (.ifThenElse region.statusCondition region.lexicalFailure .skip)
    (.sequence (.ifThenElse (capacityCondition region.countId region.capacityId) region.storageFailure .skip)
      region.rest)

/-- Match both guards together in order, including their empty success branches.
The failure branches are retained unchanged for the later failure contract. -/
def checkAfterLexer? : (statement : Stmt) → Option (CheckedStatement AfterLexer.body statement)
  | .sequence (.ifThenElse (.binary .notEqual (.call statusFunction [.local lexedId]) (.constant successId))
      lexicalFailure .skip)
      (.sequence (.ifThenElse (.unary .logicalNot (.binary .lessEqual (.local countId)
        (.binary .divide (.local capacityId) (.value (.signed .i32 3))))) storageFailure .skip) rest) =>
    some ⟨⟨lexedId, countId, capacityId, statusFunction, successId, lexicalFailure, storageFailure, rest⟩, rfl⟩
  | _ => none

/-- Global symbols vary with checked module linking. Local IDs describe the
actual extract_syntax scopes and are authenticated by the complete matcher. -/
structure TokenizationSymbols where
  lexer : Lanius.FunctionId
  count : Lanius.FunctionId
  status : Lanius.FunctionId
  canonicalize : Lanius.FunctionId
  resultType : Lanius.TypeId
  success : Lanius.ConstantId

def tokenCopy (symbols : TokenizationSymbols) (rest : Stmt) : BufferCopy.Canonicalization :=
  ⟨⟨4, 6, 19, 18, .plain, .triple⟩, 0, symbols.canonicalize, 20, rest⟩

def tokenGuards (symbols : TokenizationSymbols) (lexicalFailure storageFailure rest : Stmt) : AfterLexer :=
  ⟨17, 18, 7, symbols.status, symbols.success, lexicalFailure, storageFailure, (tokenCopy symbols rest).body⟩

def tokenizationBody (symbols : TokenizationSymbols) (lexicalFailure storageFailure rest : Stmt) : Stmt :=
  (LexerPrefix.mk 0 1 4 5 17 18 symbols.resultType symbols.lexer symbols.count
    (tokenGuards symbols lexicalFailure storageFailure rest).body).body

structure Tokenization where
  symbols : TokenizationSymbols
  lexicalFailure : Stmt
  storageFailure : Stmt
  rest : Stmt

def Tokenization.body (region : Tokenization) : Stmt :=
  tokenizationBody region.symbols region.lexicalFailure region.storageFailure region.rest

/-- Authenticate the whole contiguous prefix through canonicalization. The
status and capacity guards must precede the copy, using these exact locals. -/
def checkTokenization? (statement : Stmt) : Option (CheckedStatement Tokenization.body statement) := do
  let lexing ← checkLexerPrefix? statement
  let guards ← checkAfterLexer? lexing.locals.rest
  let copying ← BufferCopy.checkCanonicalization? guards.locals.rest
  let symbols : TokenizationSymbols := ⟨lexing.locals.lexerId, lexing.locals.countFunction,
    guards.locals.statusFunction, copying.locals.functionId, lexing.locals.resultType, guards.locals.successId⟩
  let region : Tokenization := ⟨symbols, guards.locals.lexicalFailure, guards.locals.storageFailure, copying.locals.rest⟩
  let equal ← Equality.statement? statement region.body
  pure ⟨region, equal.equal⟩

def findTokenization? := findStatement? Tokenization.body checkTokenization?

/-- Unlike canonical storage, kind storage uses one word per token. -/
def kindsCapacityCondition : Expr :=
  .unary .logicalNot (.binary .lessEqual (.local 20) (.local 9))

def recognitionRegion (functionId resultType : Nat) (rest : Stmt) : BufferCopy.Recognition :=
  ⟨⟨6, 8, 21, 20, .triple, .plain⟩, 2, 3, 10, 11, functionId, 22, .structure resultType, rest⟩

def recognitionBody (functionId resultType : Nat) (storageFailure rest : Stmt) : Stmt :=
  .sequence (.ifThenElse kindsCapacityCondition storageFailure .skip)
    (recognitionRegion functionId resultType rest).body

structure RecognitionStage where
  functionId : Lanius.FunctionId
  resultType : Lanius.TypeId
  storageFailure : Stmt
  rest : Stmt

def RecognitionStage.body (stage : RecognitionStage) : Stmt :=
  recognitionBody stage.functionId stage.resultType stage.storageFailure stage.rest

/-- Authenticate the immediate continuation of canonicalization, not merely
an independently located copy loop. Keep the original failure and parse tails. -/
def checkRecognitionStage? (statement : Stmt) : Option (CheckedStatement RecognitionStage.body statement) := do
  let .sequence (.ifThenElse _ storageFailure .skip) following := statement | none
  let copying ← BufferCopy.checkRecognition? following
  let .structure resultType := copying.locals.resultType | none
  let stage : RecognitionStage := ⟨copying.locals.functionId, resultType, storageFailure, copying.locals.rest⟩
  let equal ← Equality.statement? statement stage.body
  pure ⟨stage, equal.equal⟩

end Lanius.Extraction.Frontend
