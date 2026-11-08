import std/[algorithm, json, math, options, os, sequtils, strutils, tables, times]

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

> Automatically updated every 12 hours by a local cron on raven.

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

proc parseHistoryPrice(node: JsonNode): float =
  ## Nim serialises NaN as the *string* "nan" (JSON has no NaN literal), and
  ## getFloat() answers its 0.0 default for a string. A round-tripped
  ## variable-price model therefore came back as "free", which never compared
  ## equal to the registry's NaN and made the generator record a fresh price
  ## change on every single run. Read the sentinel back as NaN.
  if node.kind == JString and node.getStr == "nan": NaN
  elif node.kind == JNull: NaN
  else: node.getFloat

proc parseHistoryEntry(node: JsonNode): JsonHistoryEntry =
  result.model_id = node["model_id"].getStr
  result.from_date = node["from_date"].getStr
  if node.hasKey("to_date") and node["to_date"].kind != JNull:
    result.to_date = some(node["to_date"].getStr)
  else:
    result.to_date = none(string)
  result.prompt_price = parseHistoryPrice(node["prompt_price"])
  result.completion_price = parseHistoryPrice(node["completion_price"])

proc pricesEqual(a, b: float): bool =
  ## NaN means "no fixed per-token price" (openrouter/auto and friends). Two NaNs
  ## are the same non-price, but `abs(NaN - NaN) < eps` is false, so without this
  ## those models looked like they changed price on every run.
  if classify(a) == fcNan or classify(b) == fcNan:
    return classify(a) == classify(b)
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

const ChangesJsonPath = "docs/data/changes.json"
const ChangeWindowDays = 30

proc parseIso(s: string): DateTime =
  parse(s, "yyyy-MM-dd'T'HH:mm:ss'Z'", utc())

proc isFiniteFloat(x: float): bool =
  ## Some registry entries price themselves as the string "nan" (openrouter/auto
  ## and friends, whose cost is variable). Nim's json module serialises a NaN as
  ## the *string* "nan", which would put a non-number in a numeric field, so
  ## those models are skipped rather than emitted.
  classify(x) notin {fcNan, fcInf, fcNegInf}

proc startOfUtcDay(d: DateTime): DateTime =
  dateTime(d.year, d.month, d.monthday, 0, 0, 0, zone = utc())

proc writePriceChanges(rows: seq[ModelRow]) =
  ## Precompute the 30-day price delta for every model.
  ##
  ## The pages used to derive this in the browser, which meant downloading
  ## history.json (1.7 MB, ~108 KB gzipped) on every page load just to render one
  ## column. Emitting the answer here keeps the payload small and puts the
  ## definition of "the price 30 days ago" in exactly one place.
  ##
  ## History entries record price *changes*, so the price in effect on a past
  ## date is the last entry whose from_date precedes it — not the nearest one.
  if not fileExists(HistoryJsonPath):
    stderr.writeLine("Warning: " & HistoryJsonPath & " missing; skipping changes.json.")
    return

  var entries: seq[JsonHistoryEntry] = @[]
  try:
    let parsed = parseJson(readFile(HistoryJsonPath))
    if parsed.hasKey("entries"):
      for node in parsed["entries"].elems:
        entries.add(parseHistoryEntry(node))
  except CatchableError as exc:
    stderr.writeLine("Warning: could not read " & HistoryJsonPath & ": " & exc.msg)
    return

  var byModel = initTable[string, seq[JsonHistoryEntry]]()
  for e in entries:
    byModel.mgetOrPut(e.model_id, @[]).add(e)
  for id in byModel.keys:
    byModel[id].sort(proc(a, b: JsonHistoryEntry): int = cmp(a.from_date, b.from_date))

  # Compare against whole UTC days, not the run's clock time. Measuring from
  # `now` moved the reported "vs <date>" by a day depending on when the generator
  # happened to run, and could pick a different base entry between two runs on
  # the same day.
  let now = getTime().utc
  let today = startOfUtcDay(now)
  let cutoff = today - initDuration(days = ChangeWindowDays)

  var changes = newJObject()
  for row in rows:
    if not byModel.hasKey(row.id): continue
    let hist = byModel[row.id]
    if hist.len == 0: continue

    var baseIdx = -1
    for i, e in hist:
      let ts = parseIso(e.from_date)
      if ts <= cutoff: baseIdx = i
      else: break

    var spanDays = ChangeWindowDays
    if baseIdx < 0:
      # Younger than the window: compare against the oldest entry we have and
      # report the shorter span rather than pretending the window is full.
      baseIdx = 0
      spanDays = int((today - startOfUtcDay(parseIso(hist[0].from_date))).inDays)
      if spanDays < 1: continue

    let base = hist[baseIdx]
    let fromP = base.prompt_price * 1e6
    let fromC = base.completion_price * 1e6
    let toP = row.promptPrice * 1e6
    let toC = row.completionPrice * 1e6
    if not isFiniteFloat(fromP) or not isFiniteFloat(fromC) or
       not isFiniteFloat(toP) or not isFiniteFloat(toC):
      continue

    var node = newJObject()
    # pct is null when the old price was $0: a ratio from zero does not exist,
    # so the UI says "now free"/"new" instead of inventing a number.
    if fromP > 0: node["pct"] = %(((toP - fromP) / fromP) * 100)
    else: node["pct"] = newJNull()
    if fromC > 0: node["pctCompletion"] = %(((toC - fromC) / fromC) * 100)
    else: node["pctCompletion"] = newJNull()
    node["from"] = %fromP
    node["to"] = %toP
    node["fromCompletion"] = %fromC
    node["toCompletion"] = %toC
    node["spanDays"] = %spanDays
    node["compareDate"] = %(today - initDuration(days = spanDays)).format("yyyy-MM-dd")
    node["fromDate"] = %base.from_date
    changes[row.id] = node

  let root = %*{
    "version": 1,
    "generated_at": now.utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
    "window_days": ChangeWindowDays,
    "changes": changes
  }
  try:
    writeFile(ChangesJsonPath, pretty(root))
  except CatchableError as exc:
    stderr.writeLine("Warning: could not write " & ChangesJsonPath & ": " & exc.msg)

const HeartbeatJsonPath = "docs/data/heartbeat.json"
const HeartbeatMaxRuns = 1000

proc writeHeartbeat(modelCount: int) =
  ## Append this run to the heartbeat log.
  ##
  ## history.json records when *prices changed*, which cannot distinguish "the
  ## price held steady" from "nothing was collecting data" — the Aug-Nov outage
  ## drew as a flat line. This log records when the generator actually finished,
  ## so the chart can shade the periods nobody was watching.
  ##
  ## Written at the very end of main(), so a run that crashes or is killed
  ## leaves no record: absence of a heartbeat is the signal.
  let now = getTime().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

  var runs: seq[JsonNode] = @[]
  if fileExists(HeartbeatJsonPath):
    try:
      let parsed = parseJson(readFile(HeartbeatJsonPath))
      if parsed.hasKey("runs"):
        for node in parsed["runs"].elems:
          runs.add(node)
    except CatchableError:
      # A corrupt heartbeat must never block a data refresh; start a new log.
      stderr.writeLine("Warning: could not read " & HeartbeatJsonPath & "; starting a fresh log.")

  runs.add(%*{"at": now, "models": modelCount})
  if runs.len > HeartbeatMaxRuns:
    runs = runs[runs.len - HeartbeatMaxRuns .. ^1]

  try:
    writeFile(HeartbeatJsonPath, pretty(%*{"version": 1, "runs": runs}))
  except CatchableError as exc:
    stderr.writeLine("Warning: could not write " & HeartbeatJsonPath & ": " & exc.msg)

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
    writePriceChanges(rows)
    writeOutputFile(FreeModelsOutputPath, generateFreeModelsPage(rows), "FREE_MODELS.md")
    writeOutputFile(PaidModelsOutputPath, generatePaidModelsPage(rows), "PAID_MODELS.md")
    writeOutputFile(LocalModelsOutputPath, generateLocalModelsTable(), "LOCAL_MODELS.md")
    createDir("docs/data")
    writeFile("docs/data/local-models.json", generateLocalModelsJson())
    writeOutputFile(CategoriesOutputPath, generateCategoryPages(rows), "CATEGORIES.md")

    # Last, so it only records runs that actually completed.
    writeHeartbeat(rows.len)

    stdout.writeLine("Generated README.md, FREE_MODELS.md, PAID_MODELS.md, LOCAL_MODELS.md, CATEGORIES.md, and local-models.json for " & $rows.len & " models.")
  except CatchableError as exc:
    stderr.writeLine("Error: " & exc.msg)
    quit(QuitFailure)

when isMainModule:
  main()
