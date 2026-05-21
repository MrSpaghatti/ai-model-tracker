import std/[json, math, options, os, sequtils, strutils, tables, times]

import fetcher
import formatter
import parser
import types

const
  ReadmeTemplatePath = "templates/README.md"
  ReadmeOutputPath = "README.md"
  FreeModelsOutputPath = "FREE_MODELS.md"
  PaidModelsOutputPath = "PAID_MODELS.md"
  LocalModelsOutputPath = "LOCAL_MODELS.md"
  CategoriesOutputPath = "CATEGORIES.md"
  ReadmeContentPlaceholder = "{{README_CONTENT}}"
  DefaultReadmeTemplate = """# AI Model Price & Context Tracker

> Automatically updated every 12 hours via GitHub Actions.

## 📊 Pages

- [🆓 Free Models](FREE_MODELS.md) — All models with zero pricing, sorted by context length
- [💳 Paid Models](PAID_MODELS.md) — All paid models, sorted by context/cent efficiency
- [🏆 Category Picks](CATEGORIES.md) — Top-5 models for coding, vision, value, VRAM tiers, and more
- [💻 Local Models](LOCAL_MODELS.md) — Curated self-hosted model recommendations with VRAM estimates

## 📈 Raw Data

Historical JSON snapshots are stored in the `data/` directory.
"""

proc loadReadmeTemplate(): string =
  try:
    if fileExists(ReadmeTemplatePath):
      return readFile(ReadmeTemplatePath)

    if fileExists(ReadmeOutputPath):
      let existingReadme = readFile(ReadmeOutputPath)
      if ReadmeContentPlaceholder in existingReadme:
        return existingReadme

    result = DefaultReadmeTemplate
  except CatchableError as exc:
    raise newException(CatchableError, "Unable to load README template: " & exc.msg)

proc writeOutputFile(path, content, label: string) =
  try:
    writeFile(path, content)
  except CatchableError as exc:
    raise newException(CatchableError, "Unable to write " & label & ": " & exc.msg)

proc toJsonModel(row: ModelRow): JsonModel =
  let providerParts = row.id.split("/")
  let provider =
    if providerParts.len > 0:
      providerParts[0]
    else:
      ""

  result = JsonModel(
    id: row.id,
    name: row.name,
    provider: provider,
    context_length: row.contextLength,
    pricing: Pricing(
      prompt: $row.promptPrice,
      completion: $row.completionPrice,
      request: if row.hasRequestPrice: $row.requestPrice else: ""
    ),
    created_at: getTime().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
    is_free: row.isFree,
    is_moderated: row.isModerated,
    modalities: row.modalities
  )

proc writeJsonCurrent(rows: seq[ModelRow]) =
  createDir("docs/data")

  let generatedAt = getTime().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  let models = rows.mapIt(toJsonModel(it))
  let root = JsonCurrentRoot(version: 1, generated_at: generatedAt, models: models)

  try:
    writeFile("docs/data/current.json", pretty(%*root))
  except CatchableError as exc:
    raise newException(CatchableError, "Unable to write docs/data/current.json: " & exc.msg)

const HistoryJsonPath = "docs/data/history.json"
const PriceEpsilon = 1e-12

proc parseHistoryEntry(node: JsonNode): JsonHistoryEntry =
  result.model_id = node["model_id"].getStr
  result.from_date = node["from_date"].getStr
  if node.hasKey("to_date") and node["to_date"].kind != JNull:
    result.to_date = some(node["to_date"].getStr)
  else:
    result.to_date = none(string)
  result.prompt_price = node["prompt_price"].getFloat
  result.completion_price = node["completion_price"].getFloat

proc pricesEqual(a, b: float): bool =
  abs(a - b) < PriceEpsilon

proc writeJsonHistoryIncremental(rows: seq[ModelRow]) =
  if not fileExists(HistoryJsonPath):
    stderr.writeLine("Warning: " & HistoryJsonPath &
      " does not exist; skipping incremental history update (run backfill_history first).")
    return

  let now = getTime().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

  var existingEntries: seq[JsonHistoryEntry] = @[]
  try:
    let raw = readFile(HistoryJsonPath)
    let parsed = parseJson(raw)
    if parsed.hasKey("entries"):
      for node in parsed["entries"].elems:
        existingEntries.add(parseHistoryEntry(node))
  except CatchableError as exc:
    raise newException(CatchableError,
      "Unable to read " & HistoryJsonPath & ": " & exc.msg)

  # Index last (most recent) entry per model id
  var lastIndex = initTable[string, int]()
  for i, entry in existingEntries:
    if entry.to_date.isNone:
      lastIndex[entry.model_id] = i
    else:
      # Track latest by from_date if no open entry exists
      if not lastIndex.hasKey(entry.model_id) or
         existingEntries[lastIndex[entry.model_id]].from_date < entry.from_date:
        lastIndex[entry.model_id] = i

  var newEntries: seq[JsonHistoryEntry] = existingEntries
  var currentIds = initTable[string, bool]()

  for row in rows:
    currentIds[row.id] = true

    if lastIndex.hasKey(row.id):
      let idx = lastIndex[row.id]
      let last = newEntries[idx]
      if last.to_date.isNone:
        if pricesEqual(last.prompt_price, row.promptPrice) and
           pricesEqual(last.completion_price, row.completionPrice):
          # No change; leave open entry as-is
          continue
        # Price changed: close previous open entry at `now`, open new entry.
        newEntries[idx].to_date = some(now)
        newEntries.add(JsonHistoryEntry(
          model_id: row.id,
          from_date: now,
          to_date: none(string),
          prompt_price: row.promptPrice,
          completion_price: row.completionPrice,
        ))
      else:
        # Model reappeared after being closed; open new entry
        newEntries.add(JsonHistoryEntry(
          model_id: row.id,
          from_date: now,
          to_date: none(string),
          prompt_price: row.promptPrice,
          completion_price: row.completionPrice,
        ))
    else:
      # Brand new model
      newEntries.add(JsonHistoryEntry(
        model_id: row.id,
        from_date: now,
        to_date: none(string),
        prompt_price: row.promptPrice,
        completion_price: row.completionPrice,
      ))

  # Close entries for models that disappeared from the API.
  for modelId, idx in lastIndex.pairs:
    if not currentIds.hasKey(modelId):
      if newEntries[idx].to_date.isNone:
        newEntries[idx].to_date = some(now)

  let root = JsonHistoryRoot(version: 1, generated_at: now, entries: newEntries)

  try:
    writeFile(HistoryJsonPath, pretty(%*root))
  except CatchableError as exc:
    raise newException(CatchableError,
      "Unable to write " & HistoryJsonPath & ": " & exc.msg)

proc writeReadme(content: string) =
  let readmeTemplate = loadReadmeTemplate()

  if ReadmeContentPlaceholder in readmeTemplate:
    writeOutputFile(
      ReadmeOutputPath,
      readmeTemplate.replace(ReadmeContentPlaceholder, content),
      "README.md"
    )
    return

  # Template is the complete README (no placeholder needed)
  writeOutputFile(ReadmeOutputPath, readmeTemplate, "README.md")

proc main() =
  try:
    let rawJson = fetchRegistryJson()
    writeRawRegistry(rawJson)

    let rows = parseModels(rawJson)
    writeReadme("")
    writeJsonCurrent(rows)
    writeJsonHistoryIncremental(rows)
    writeOutputFile(FreeModelsOutputPath, generateFreeModelsPage(rows), "FREE_MODELS.md")
    writeOutputFile(PaidModelsOutputPath, generatePaidModelsPage(rows), "PAID_MODELS.md")
    writeOutputFile(LocalModelsOutputPath, generateLocalModelsTable(), "LOCAL_MODELS.md")
    createDir("docs/data")
    writeFile("docs/data/local-models.json", generateLocalModelsJson())
    writeOutputFile(CategoriesOutputPath, generateCategoryPages(rows), "CATEGORIES.md")

    stdout.writeLine("Generated README.md, FREE_MODELS.md, PAID_MODELS.md, LOCAL_MODELS.md, CATEGORIES.md, and local-models.json for " & $rows.len & " models.")
  except CatchableError as exc:
    stderr.writeLine("Error: " & exc.msg)
    quit(QuitFailure)

when isMainModule:
  main()
