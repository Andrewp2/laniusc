import Lanius.Semantics.Capacity.Execution.Scalars
import Lanius.Semantics.Capacity.Execution.Aggregates
import Lanius.Semantics.Capacity.Execution.Call
import Lanius.Semantics.Capacity.Execution.Mutation

namespace Lanius.Semantics.Capacity.Execution
open Lanius.Core

theorem expression (valid : config.Valid) (checked : Fragment.Checked program allowed)
    (step : Step fuel config allowed program) (ready : Ready config before)
    (supported : Fragment.expression allowed input = true)
    (evaluated : evalExpr (fuel + 1) program before input = .done result after) :
    evalExpr (fuel + 1) program (state config before) input = .done (value config result) (state config after) ∧
      Ready config after ∧ closed config result = true := by
  cases input <;> simp only [Fragment.expression, Bool.and_eq_true, Bool.false_eq_true] at supported
  case value entry =>
    cases evaluated
    exact ⟨by rw [plain_fixed config _ supported]; rfl, ready, plain_closed config _ supported⟩
  case «local» => exact localExpression valid ready evaluated
  case cast => exact castExpression step ready supported evaluated
  case unary => exact unaryExpression step ready supported evaluated
  case binary => exact binaryExpression step ready supported.1 supported.2 evaluated
  case array => exact arrayExpression step ready supported evaluated
  case structValue => exact structExpression step ready supported evaluated
  case enumValue => exact enumExpression step ready supported evaluated
  case field => exact fieldExpression step ready supported evaluated
  case index => exact indexExpression step ready supported.1 supported.2 evaluated
  case assign => exact assignmentExpression step ready supported.1 supported.2 evaluated
  case constant => exact constant checked ready evaluated
  case call => exact call valid step checked ready supported.1 supported.2 evaluated
  case stringDataPtr => exact stringExpression step ready supported evaluated
  case i32SliceFromRawParts => exact rawSliceExpression valid step ready supported.1 supported.2 evaluated

end Lanius.Semantics.Capacity.Execution
