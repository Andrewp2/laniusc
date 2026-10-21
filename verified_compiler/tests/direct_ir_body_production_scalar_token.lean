import verified_compiler.tests.direct_ir_body_production_scalar_domain

namespace IRBodyProductionScalar

open Lanius Lanius.Core Lanius.Semantics IRBodyProductionInputs

theorem DecimalSpelling.nonempty (spelled : DecimalSpelling bytes magnitude) : 0 < bytes.length := by
  cases spelled <;> simp only [List.length_append, List.length_cons, List.length_nil] <;> omega

/-- The existing scanner input retains original descriptor capacities and token storage.
    Its selected words and token row come from original native evidence, not query runs. -/
def OriginalToken.integerInput
    (token : OriginalToken input state index text integerToken)
    (spelled : DecimalSpelling (ascii text) magnitude) : IRIntegerLoweringProof.Input state := {
  address := token.sourceAddress
  capacity := token.sourceCapacity
  count := input.sourceLength
  capacityBound := token.sourceBound
  start := token.origin
  length := text.toList.length
  bytes := fun offset => (ascii text)[offset]?.getD 0
  fits := token.sourceFits
  inside := token.span
  nonempty := by simpa only [ascii, List.length_map] using spelled.nonempty
  reads := token.words
  tokenAddress := token.address
  tokenCapacity := token.length
  tokenCount := input.tokenCount
  tokenBound := token.bound
  tokenStorage := input.tokenStorage
  tokenIndex := index
  tokenFits := token.tokensFit
  tokenInside := token.inside
  tokenRead := by
    change readRawSliceIndex extractedProgram state tokenType token.address token.length index =
      .ok (tokenRow integerToken (Int.ofNat token.origin) (Int.ofNat (token.origin + text.toList.length)))
    have read := token.toNativeToken.read (state := state)
    simpa only [tokenRow, token.kindMatches, token.startMatches, token.finishMatches] using read }

theorem OriginalToken.integerTokens
    (token : OriginalToken input state index text integerToken)
    (spelled : DecimalSpelling (ascii text) magnitude) :
    (token.integerInput spelled).tokens = input.tokensValue := by
  simp only [OriginalToken.integerInput, IRIntegerLoweringProof.Input.tokens, Inputs.tokensValue]
  rw [token.descriptor]
  rfl

def bodyContextSuffix (input : Inputs) (workspace : Workspace) (locals : Value) : List Value :=
  match bodyContext input workspace locals with
  | .structure _ fields => fields.drop 4
  | _ => []

/-- Reuse the actual context's unused suffix; the selected source and token
    descriptors retain their independently specified capacities and storage. -/
theorem OriginalToken.integerContext
    (token : OriginalToken input state index text integerToken)
    (spelled : DecimalSpelling (ascii text) magnitude) (workspace : Workspace) (locals : Value) :
    IRLiteralLoweringProof.integerContext (token.integerInput spelled) (bodyContextSuffix input workspace locals) =
      bodyContext input workspace locals := by
  unfold IRLiteralLoweringProof.integerContext
  rw [token.integerTokens spelled]
  dsimp only [OriginalToken.integerInput]
  rw [← token.source]
  rfl

#print axioms DecimalSpelling.nonempty
#print axioms OriginalToken.integerTokens
#print axioms OriginalToken.integerContext

end IRBodyProductionScalar
