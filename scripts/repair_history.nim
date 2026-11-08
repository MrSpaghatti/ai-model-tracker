## One-shot repair for docs/data/history.json.
##
## The original backfill (scripts/backfill_history.nim) walked `git log` output,
## which is newest-first, and set each entry's to_date to snapshots[i + 1] — the
## *previous* observation. Every interval in the file therefore pointed backwards
## in time: 6,274 of 7,814 closed entries had to_date < from_date. It also emitted
## an entry for every observation whether or not the price had changed, so most
## models carried long runs of identical back-to-back entries.
##
## This rewrites the file under the model the incremental generator uses: one
## entry per price interval, with
##
##   * runs of equal prices collapsed to the first observation of the run, but
##     ONLY when the observations are consecutive runs — a model that vanished and
##     came back at the same price is two intervals, not one;
##   * to_date = the first run at which the model was no longer at that price,
##     which is the next interval when the price changed and the first absence
##     when the model left the registry;
##   * to_date = null only for the final interval of a model still in the
##     registry.
##
## Requires the run grid: every run that observed anything left its timestamp in
## the file, so the set of all from_date values is the list of runs. That is what
## makes "the first run after this one" recoverable without a separate log.
##
## Idempotent: correct data round-trips unchanged.

import std/[algorithm, json, math, options, os, sequtils, sets, strutils, tables, times]

const HistoryPath = "docs/data/history.json"
const CurrentPath = "docs/data/current.json"
const PriceEpsilon = 1e-12

type
  Observation = object
    fromDate: string
    promptPrice: float
    completionPrice: float

  Interval = object
    start: string      # first observation of this price
    lastSeen: string   # last observation still at this price
    promptPrice: float
    completionPrice: float

proc toEpoch(s: string): int64 =
  parse(s, "yyyy-MM-dd'T'HH:mm:ss'Z'", utc()).toTime.toUnix

proc isoUtc(epoch: int64): string =
  fromUnix(epoch).utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc pricesEqual(a, b: float): bool =
  ## NaN means "no fixed per-token price" (openrouter/auto and friends). Two NaNs
  ## are the same non-price, but `abs(NaN - NaN) < eps` is false.
  if classify(a) == fcNan or classify(b) == fcNan:
    return classify(a) == classify(b)
  abs(a - b) < PriceEpsilon

proc readPrice(node: JsonNode): float =
  ## NaN is serialised as the *string* "nan" (JSON has no NaN literal) and
  ## getFloat() answers 0.0 for a string — reading it naively would relabel a
  ## variable-price model as free.
  if node.kind == JString and node.getStr == "nan": NaN
  elif node.kind == JNull: NaN
  else: node.getFloat

proc main() =
  let hist = parseJson(readFile(HistoryPath))
  let cur = parseJson(readFile(CurrentPath))

  var present = initHashSet[string]()
  for m in cur["models"].elems:
    present.incl m["id"].getStr

  var byModel = initTable[string, seq[Observation]]()
  var runSet = initHashSet[int64]()
  for node in hist["entries"].elems:
    let o = Observation(
      fromDate: node["from_date"].getStr,
      promptPrice: readPrice(node["prompt_price"]),
      completionPrice: readPrice(node["completion_price"]),
    )
    byModel.mgetOrPut(node["model_id"].getStr, @[]).add(o)
    runSet.incl toEpoch(o.fromDate)

  let runTimes = toSeq(runSet).sorted
  var runIndex = initTable[int64, int]()
  for i, r in runTimes: runIndex[r] = i

  let before = hist["entries"].elems.len

  var repaired: seq[JsonNode] = @[]
  var collapsed = 0
  var gapKept = 0
  var leaked = 0
  var openCount = 0
  var inverted = 0

  for id in byModel.keys:
    var obs = byModel[id]
    obs.sort(proc(a, b: Observation): int = cmp(a.fromDate, b.fromDate))

    var intervals: seq[Interval] = @[]
    for o in obs:
      var merged = false
      if intervals.len > 0:
        let prev = intervals[^1]
        let contiguous =
          runIndex.hasKey(toEpoch(prev.lastSeen)) and
          runIndex.hasKey(toEpoch(o.fromDate)) and
          runIndex[toEpoch(o.fromDate)] == runIndex[toEpoch(prev.lastSeen)] + 1
        if pricesEqual(prev.promptPrice, o.promptPrice) and
           pricesEqual(prev.completionPrice, o.completionPrice):
          if contiguous:
            # Same price, seen at the very next run: one continuous interval.
            intervals[^1].lastSeen = o.fromDate
            merged = true
          else:
            # Same price, but the registry did not list it in between: the model
            # left and came back, so these are two intervals, not one.
            inc gapKept
      if not merged:
        intervals.add(Interval(
          start: o.fromDate,
          lastSeen: o.fromDate,
          promptPrice: o.promptPrice,
          completionPrice: o.completionPrice,
        ))
    collapsed += obs.len - intervals.len

    for i in 0 ..< intervals.len:
      let isLast = i == intervals.len - 1
      var toDate = none(string)

      if isLast and present.contains(id):
        inc openCount                  # still listed: the interval stays open
      else:
        # The interval ends at the first run that no longer saw this price: the
        # next interval when the price changed, the first absence when the model
        # left the registry.
        let boundary = toEpoch(intervals[i].lastSeen)
        for r in runTimes:
          if r > boundary:
            toDate = some(isoUtc(r))
            break
        if toDate.isNone: inc leaked

      let fromStr = intervals[i].start
      if toDate.isSome and toDate.get <= fromStr: inc inverted

      repaired.add(%*{
        "model_id": id,
        "from_date": fromStr,
        "to_date": (if toDate.isSome: %toDate.get else: newJNull()),
        "prompt_price": intervals[i].promptPrice,
        "completion_price": intervals[i].completionPrice,
      })

  # Newest first, matching the order the file has always used.
  repaired.sort(proc(a, b: JsonNode): int =
    let c = cmp(b["from_date"].getStr, a["from_date"].getStr)
    if c != 0: c else: cmp(a["model_id"].getStr, b["model_id"].getStr))

  if inverted > 0:
    stderr.writeLine("Refusing to write: " & $inverted & " non-positive intervals remain.")
    quit(QuitFailure)

  writeFile(HistoryPath, pretty(%*{
    "version": 1,
    "generated_at": getTime().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
    "entries": repaired,
  }))

  echo "entries: ", before, " -> ", repaired.len, " (", collapsed, " duplicate observations collapsed)"
  echo "models: ", byModel.len, " | runs seen: ", runTimes.len
  echo "open intervals: ", openCount, " (registry has ", present.len, ")"
  echo "gap-separated same-price returns kept: ", gapKept
  echo "intervals with no run to close at: ", leaked
  echo "inverted intervals: ", inverted

when isMainModule:
  main()
