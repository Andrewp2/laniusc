import Lanius.Compiler.Parser.Envelope.Check
import Lanius.Extraction.VerifiedFrontend.Parser.Soundness

namespace Lanius.Extraction.ParserRecognize
open Lanius.Compiler.Parser

/-- The resource checker consumes grammar, tokens, and a finite candidate;
its success excludes capacity failure in the actual source call. -/
theorem RecognizerCallExecution.success_of_envelope
    (execution : RecognizerCallExecution grammarLayout grammar words tokens
      workspaceLayout workspaceValues grammarCell tokensCell workspaceCell before afterArguments arguments)
    (recognized : RecognizesInput grammar tokens)
    (certificate : Envelope.Checked grammar tokens workspaceLayout.capacity) :
    parseResultStatus? execution.outcome.resultValue = some 0 :=
  execution.success_of_closed_bound recognized (Envelope.check_closed certificate.closed)
    (Envelope.chartSound certificate.items) (by simpa using certificate.fits)

end Lanius.Extraction.ParserRecognize
