import std/[algorithm, json, math, options, os, sequtils, strutils, tables, times]

import fetcher
import formatter
import json_mapper
import parser
import types
import validator

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
- [🛣️ Roadmap](ROADMAP.md) — Backlog grouped by data quality, ranking quality, UX, and ops reliability

## 📈 Raw Data

Historical JSON snapshots are stored in the `data/` directory.
"""
  PriceEpsilon = 1e-12

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

proc pricesEqual(a, b: float): bool =
  abs(a - b) < PriceEpsilon

proc buildProviderStats(rows: seq[ModelRow]): seq[JsonProviderStats] =
  type ProviderAccumulator = object
    totalModels: int
    freeModels: int
    paidModels: int
    moderatedModels: int
    promptTotal: float
    completionTotal: float
    pricedCount: int

  var acc = initTable[string, ProviderAccumulator]()
  for row in rows:
    let provider = row.provider
    if provider.len == 0:
      continue
    var item = acc.getOrDefault(provider)
    inc(item.totalModels)
    if row.isFree: inc(item.freeModels) else: inc(item.paidModels)
    if row.isModerated: inc(item.moderatedModels)
    if row.promptPrice.classify != fcNaN and row.completionPrice.classify != fcNaN:
      item.promptTotal += row.promptPrice
      item.completionTotal += row.completionPrice
      inc(item.pricedCount)
    acc[provider] = item

  for provider, item in acc.pairs:
    let moderationCoverage =
      if item.totalModels == 0: 0.0
      else: (item.moderatedModels.float / item.totalModels.float) * 100.0
    let avgPrompt =
      if item.pricedCount == 0: ""
      else: formatFloat(item.promptTotal / item.pricedCount.float, ffDecimal, 12)
    let avgCompletion =
      if item.pricedCount == 0: ""
      else: formatFloat(item.completionTotal / item.pricedCount.float, ffDecimal, 12)

    result.add(JsonProviderStats(
      provider: provider,
      total_models: item.totalModels,
      free_models: item.freeModels,
      paid_models: item.paidModels,
      moderated_models: item.moderatedModels,
      moderation_coverage_pct: moderationCoverage,
      avg_prompt_price: avgPrompt,
      avg_completion_price: avgCompletion
    ))

  result.sort(proc(a, b: JsonProviderStats): int =
    if a.total_models > b.total_models: return -1
    if a.total_models < b.total_models: return 1
    cmp(a.provider, b.provider)
  )

proc buildChangeSummary(rows: seq[ModelRow], historyEntries: seq[JsonHistoryEntry]): JsonChangesSummary =
  var latestClosed = initTable[string, JsonHistoryEntry]()
  var latestOpen = initTable[string, JsonHistoryEntry]()
  var latestAny = initTable[string, JsonHistoryEntry]()
  for entry in historyEntries:
    let existingAny = latestAny.getOrDefault(entry.model_id)
    if existingAny.model_id.len == 0 or existingAny.from_date < entry.from_date:
      latestAny[entry.model_id] = entry

    if entry.to_date.isNone:
      let existing = latestOpen.getOrDefault(entry.model_id)
      if existing.model_id.len == 0 or existing.from_date < entry.from_date:
        latestOpen[entry.model_id] = entry
    else:
      let existing = latestClosed.getOrDefault(entry.model_id)
      if existing.model_id.len == 0 or existing.from_date < entry.from_date:
        latestClosed[entry.model_id] = entry

  var currentById = initTable[string, ModelRow]()
  for row in rows:
    currentById[row.id] = row
    if not latestOpen.hasKey(row.id):
      result.new_models.add(row.id)

    var hasPrev = false
    var prev: JsonHistoryEntry
    if latestClosed.hasKey(row.id):
      prev = latestClosed[row.id]
      hasPrev = true
    elif latestOpen.hasKey(row.id):
      prev = latestOpen[row.id]
      hasPrev = true

    if hasPrev:
      if not pricesEqual(prev.prompt_price, row.promptPrice) or
         not pricesEqual(prev.completion_price, row.completionPrice):
        let promptDelta =
          if abs(prev.prompt_price) < PriceEpsilon: 0.0
          else: ((row.promptPrice - prev.prompt_price) / prev.prompt_price) * 100.0
        let completionDelta =
          if abs(prev.completion_price) < PriceEpsilon: 0.0
          else: ((row.completionPrice - prev.completion_price) / prev.completion_price) * 100.0
        result.price_changes.add(JsonPriceChange(
          model_id: row.id,
          provider: row.provider,
          old_prompt_price: prev.prompt_price,
          new_prompt_price: row.promptPrice,
          old_completion_price: prev.completion_price,
          new_completion_price: row.completionPrice,
          prompt_delta_pct: promptDelta,
          completion_delta_pct: completionDelta
        ))

  for modelId, entry in latestAny.pairs:
    if not currentById.hasKey(modelId) and entry.to_date.isSome:
      result.removed_models.add(modelId)

  var movers = result.price_changes
  movers.sort(proc(a, b: JsonPriceChange): int =
    let am = max(abs(a.prompt_delta_pct), abs(a.completion_delta_pct))
    let bm = max(abs(b.prompt_delta_pct), abs(b.completion_delta_pct))
    if am > bm: return -1
    if am < bm: return 1
    cmp(a.model_id, b.model_id)
  )
  let capped = min(5, movers.len)
  if capped > 0:
    result.biggest_movers = movers[0 ..< capped]

proc writeJsonCurrent(rows: seq[ModelRow], historyEntries: seq[JsonHistoryEntry]) =
  createDir("docs/data")

  let generatedAt = utc_iso_timestamp()
  let models = rows.mapIt(toJsonModel(it))
  let root = JsonCurrentRoot(
    version: 1,
    generated_at: generatedAt,
    models: models,
    changes: buildChangeSummary(rows, historyEntries),
    provider_stats: buildProviderStats(rows)
  )

  try:
    writeFile("docs/data/current.json", pretty(%*root))
  except CatchableError as exc:
    raise newException(CatchableError, "Unable to write docs/data/current.json: " & exc.msg)

const HistoryJsonPath = "docs/data/history.json"

proc parseHistoryEntry(node: JsonNode): JsonHistoryEntry =
  result.model_id = node["model_id"].getStr
  result.from_date = node["from_date"].getStr
  if node.hasKey("to_date") and node["to_date"].kind != JNull:
    result.to_date = some(node["to_date"].getStr)
  else:
    result.to_date = none(string)
  result.prompt_price = node["prompt_price"].getFloat
  result.completion_price = node["completion_price"].getFloat

proc writeJsonHistoryIncremental(rows: seq[ModelRow]): seq[JsonHistoryEntry] =
  if not fileExists(HistoryJsonPath):
    stderr.writeLine("Warning: " & HistoryJsonPath &
      " does not exist; skipping incremental history update (run backfill_history first).")
    return @[]

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
  validateHistoryEntries(newEntries)
  result = newEntries

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
    validateCurrentRows(rows)
    let historyEntries = writeJsonHistoryIncremental(rows)
    writeReadme("")
    writeJsonCurrent(rows, historyEntries)
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
