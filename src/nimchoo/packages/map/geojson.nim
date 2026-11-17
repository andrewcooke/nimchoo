## GeoJSON for the providers of frames (`frames.nim`): a file of features.  What the features are is the providers' business.

import std/strutils

{.push raises: [].}

func featureCollection*(features: seq[string]): string =
  ## The whole file from its features (each a GeoJSON Feature, as text): valid JSON, a feature to a line, in the order given.
  "{\"type\":\"FeatureCollection\",\"features\":[\n" & features.join(",\n") & "\n]}\n"
