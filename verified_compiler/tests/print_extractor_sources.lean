import Lanius.Extraction.CurrentSourceClosure

def main (_args : List String) : IO UInt32 := do
  for source in Lanius.Extraction.CurrentSourceClosure.extractorSources do
    IO.println source.path
  return 0
