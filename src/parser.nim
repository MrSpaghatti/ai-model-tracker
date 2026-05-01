import std/[algorithm, math, sequtils, strformat, strutils]
import jsony

type
  Pricing* = object
    prompt*: string
    completion*: string
    request*: string

  Architecture* = object
    input_modalities*: seq[string]
    output_modalities*: seq[string]

  OpenRouterModel* = object
    id*: string
    name*: string
    context_length*: int
    pricing*: Pricing
    architecture*: Architecture
    hugging_face_id*: string

  OpenRouterResponse* = object
    data*: seq[OpenRouterModel]

  ModelRow* = object
    id*: string
    name*: string
    contextLength*: int
    promptPrice*: float
    completionPrice*: float
    requestPrice*: float
    hasRequestPrice*: bool
    averagePrice*: float
    contextPerCent*: float
    isFree*: bool
    huggingFaceId*: string
    inputModalities*: seq[string]
    outputModalities*: seq[string]
    estimatedParams*: float

proc parsePrice(value, fieldName, modelId: string): float =
  if value.len == 0:
    return 0.0

  try:
    result = parseFloat(value)
    if result == -1.0:
      return 0.0
  except ValueError as exc:
    raise newException(
      ValueError,
      fmt"Invalid {fieldName} price for model '{modelId}': {value}. {exc.msg}"
    )

proc extractParamsBillions(text: string): float =
  ## Extracts a parameter count in billions from model IDs/names
  ## e.g. "llama-3.1-8b" → 8.0, "qwen3-235b-a22b" → 235.0
  var i = 0
  while i < text.len:
    if text[i].isDigit():
      let numStart = i
      while i < text.len and (text[i].isDigit() or text[i] == '.'):
        inc i
      if i < text.len and (text[i] == 'b' or text[i] == 'B'):
        let after = i + 1
        if after >= text.len or (not text[after].isAlphaAscii() and text[after] != '.'):
          try:
            let parsed = parseFloat(text[numStart ..< i])
            if parsed >= 0.5 and parsed <= 2000.0:
              return parsed
          except ValueError:
            discard
      # no match; skip to next character after the digits
    else:
      inc i

proc toModelRow(model: OpenRouterModel): ModelRow =
  let promptPrice = parsePrice(model.pricing.prompt, "prompt", model.id)
  let completionPrice = parsePrice(model.pricing.completion, "completion", model.id)
  let hasRequestPrice = model.pricing.request.len > 0
  let requestPrice =
    if hasRequestPrice:
      parsePrice(model.pricing.request, "request", model.id)
    else:
      0.0
  let averagePrice = (promptPrice + completionPrice) / 2.0
  let contextPerCent =
    if averagePrice <= 0.0:
      Inf
    else:
      model.context_length.float / (averagePrice * 100.0)

  result = ModelRow(
    id: model.id,
    name: model.name,
    contextLength: model.context_length,
    promptPrice: promptPrice,
    completionPrice: completionPrice,
    requestPrice: requestPrice,
    hasRequestPrice: hasRequestPrice,
    averagePrice: averagePrice,
    contextPerCent: contextPerCent,
    isFree: model.id.endsWith(":free"),
    huggingFaceId: model.hugging_face_id,
    inputModalities: model.architecture.input_modalities,
    outputModalities: model.architecture.output_modalities,
    estimatedParams: extractParamsBillions(model.id & " " & model.name)
  )

proc formatWholeNumber(value: int): string =
  let digits = $value
  var groups: seq[string]
  var index = digits.len

  while index > 3:
    groups.insert(digits[index - 3 ..< index], 0)
    index -= 3

  groups.insert(digits[0 ..< index], 0)
  result = groups.join(",")

proc formatLargeFloat(value: float): string =
  if classify(value) in {fcInf, fcNegInf}:
    return "∞"

  if value >= 1_000_000_000_000.0:
    return formatFloat(value, ffScientific, 2)

  let rounded = value.round.int
  result = formatWholeNumber(rounded)

proc formatUsdPerMillion*(price: float): string =
  "$" & formatFloat(price * 1_000_000.0, ffDecimal, 4)

proc formatRequestPrice(price: float, hasRequestPrice: bool): string =
  if not hasRequestPrice:
    return "-"

  "$" & formatFloat(price, ffDecimal, 6)

proc escapeMarkdownCell(value: string): string =
  value.replace("|", "\\|").replace("\n", " ")

proc parseModels*(rawJson: string): seq[ModelRow] =
  let payload = rawJson.fromJson(OpenRouterResponse)

  for model in payload.data:
    result.add model.toModelRow()

  result.sort(proc (left, right: ModelRow): int =
    if left.contextPerCent > right.contextPerCent:
      return -1
    if left.contextPerCent < right.contextPerCent:
      return 1

    if left.averagePrice < right.averagePrice:
      return -1
    if left.averagePrice > right.averagePrice:
      return 1

    cmp(left.id, right.id)
  )

proc generateMarkdownTable*(rows: seq[ModelRow]): string =
  result = "| Model ID | Name | Context | Prompt ($/1M) | Completion ($/1M) | Request ($/req) | Context per Cent |\n"
  result.add "| --- | --- | ---: | ---: | ---: | ---: | ---: |\n"

  for row in rows:
    result.add fmt"| {escapeMarkdownCell(row.id)} | {escapeMarkdownCell(row.name)} | {formatWholeNumber(row.contextLength)} | {formatUsdPerMillion(row.promptPrice)} | {formatUsdPerMillion(row.completionPrice)} | {formatRequestPrice(row.requestPrice, row.hasRequestPrice)} | {formatLargeFloat(row.contextPerCent)} |" & "\n"

proc formatParamCount(params: float): string =
  if params <= 0.0:
    return "?"
  if params < 1.0:
    return formatFloat(params * 1000.0, ffDecimal, 0) & "M"
  result = formatFloat(params, ffDecimal, 1) & "B"

proc formatVramEstimate(params: float): string =
  if params <= 0.0:
    return "?"
  let gb = params * 2.0
  if gb < 1.0:
    return formatFloat(gb * 1024.0, ffDecimal, 0) & "MB"
  result = "~" & formatFloat(gb, ffDecimal, 0) & "GB"

proc localModelRow(row: ModelRow): string =
  let hfLink =
    if row.huggingFaceId.len > 0:
      "[" & escapeMarkdownCell(row.huggingFaceId) & "](https://huggingface.co/" & row.huggingFaceId & ")"
    else:
      "-"
  fmt"| {escapeMarkdownCell(row.id)} | {escapeMarkdownCell(row.name)} | {hfLink} | {formatWholeNumber(row.contextLength)} | {formatParamCount(row.estimatedParams)} | {formatVramEstimate(row.estimatedParams)} |" & "\n"

proc localTableHeader(): string =
  "| Model ID | Name | HuggingFace | Context | Est. Params | Est. VRAM (fp16) |\n" &
  "| --- | --- | --- | ---: | ---: | ---: |\n"

proc generateLocalModelsTable*(rows: seq[ModelRow]): string =
  let localRows = rows
    .filterIt(it.huggingFaceId.len > 0)
    .sortedByIt(-it.contextLength)

  result = localTableHeader()
  for row in localRows:
    result.add localModelRow(row)

proc generateVramTable*(rows: seq[ModelRow], vramGb: int): string =
  let eligible = rows
    .filterIt(it.huggingFaceId.len > 0 and it.estimatedParams > 0.0 and
              it.estimatedParams * 2.0 <= vramGb.float)
    .sortedByIt(-it.contextLength)

  let topFive = if eligible.len > 5: eligible[0 ..< 5] else: eligible

  if topFive.len == 0:
    return "*No models with a known parameter count fit in " & $vramGb & "GB VRAM (fp16).*\n"

  result = localTableHeader()
  for row in topFive:
    result.add localModelRow(row)

proc generateModalityTable*(rows: seq[ModelRow], modality, direction: string): string =
  let filtered =
    if direction == "input":
      rows.filterIt(modality in it.inputModalities)
    else:
      rows.filterIt(modality in it.outputModalities)

  generateMarkdownTable(filtered)
