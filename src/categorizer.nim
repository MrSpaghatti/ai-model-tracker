import std/[algorithm, math, strutils, tables]

import types

proc hasModality(row: ModelRow; target: string): bool =
  for modality in row.modalities:
    if modality.toLowerAscii() == target.toLowerAscii():
      return true

  false

proc sortRows(rows: var seq[ModelRow]) =
  rows.sort(proc (left, right: ModelRow): int =
    if left.contextPerCent > right.contextPerCent:
      return -1
    if left.contextPerCent < right.contextPerCent:
      return 1

    if left.averagePrice < right.averagePrice:
      return -1
    if left.averagePrice > right.averagePrice:
      return 1

    if left.contextLength > right.contextLength:
      return -1
    if left.contextLength < right.contextLength:
      return 1

    cmp(left.id, right.id)
  )

proc parseNumberToken(value: string; startIndex: int): tuple[number: float, nextIndex: int] =
  var index = startIndex

  while index < value.len and (value[index].isDigit or value[index] == '.'):
    inc(index)

  result.number = parseFloat(value[startIndex ..< index])
  result.nextIndex = index

proc inferParameterBillions(row: ModelRow): float =
  let haystack = (row.id & " " & row.name).toLowerAscii()
  var index = 0

  while index < haystack.len:
    if not haystack[index].isDigit:
      inc(index)
      continue

    let firstToken = parseNumberToken(haystack, index)
    var probe = firstToken.nextIndex

    if probe < haystack.len and haystack[probe] == 'x':
      inc(probe)

      if probe < haystack.len and haystack[probe].isDigit:
        let secondToken = parseNumberToken(haystack, probe)

        if secondToken.nextIndex < haystack.len and haystack[secondToken.nextIndex] == 'b':
          result = max(result, firstToken.number * secondToken.number)
          index = secondToken.nextIndex + 1
          continue

    if probe < haystack.len and haystack[probe] == 'b':
      result = max(result, firstToken.number)
      index = probe + 1
      continue

    index = firstToken.nextIndex

proc estimatedFourBitVramGb(row: ModelRow): int =
  let parameterBillions = inferParameterBillions(row)

  if parameterBillions <= 0.0:
    return high(int)

  int(ceil(parameterBillions * 0.75))

proc splitFreeVsPaid*(rows: seq[ModelRow]): tuple[freeRows: seq[ModelRow], paidRows: seq[ModelRow]] =
  for row in rows:
    if row.isFree:
      result.freeRows.add(row)
    else:
      result.paidRows.add(row)

proc getTopModelsByVram*(rows: seq[ModelRow]; vramGb: int): seq[ModelRow] =
  for row in rows:
    if row.isFree:
      continue

    if estimatedFourBitVramGb(row) <= vramGb:
      result.add(row)

  sortRows(result)

proc getBestModelsForTask*(rows: seq[ModelRow]; task: string): seq[ModelRow] =
  let taskName = task.toLowerAscii()

  proc taskTagScore(searchable: string; row: ModelRow): float =
    case taskName
    of "coding":
      if searchable.contains("code") or searchable.contains("coder") or searchable.contains("codex") or
         searchable.contains("codestral") or searchable.contains("devstral"):
        return 1.0
      return 0.0
    of "vision":
      if row.hasModality("image") or searchable.contains("vision") or searchable.contains("vl"):
        return 1.0
      return 0.0
    of "encoding":
      if searchable.contains("embed") or searchable.contains("embedding") or searchable.contains("encoder") or
         searchable.contains("encode") or searchable.contains("retrieval") or searchable.contains("rerank"):
        return 1.0
      return 0.0
    of "tts":
      if row.hasModality("audio") or searchable.contains("tts") or searchable.contains("speech") or
         searchable.contains("voice") or searchable.contains("lyria") or searchable.contains("audio"):
        return 1.0
      return 0.0
    else:
      if searchable.contains(taskName):
        return 1.0
      return 0.0

  proc taskScore(row: ModelRow): float =
    let searchable = (row.id & " " & row.name).toLowerAscii()
    let tagScore = taskTagScore(searchable, row)
    if tagScore <= 0.0:
      return -1.0

    let contextComponent = min(1.0, ln(max(1.0, row.contextLength.float)) / ln(1_048_576.0))
    let valueComponent =
      if row.contextPerCent.classify in {fcNaN, fcNegInf}:
        0.0
      elif row.contextPerCent.classify == fcInf:
        1.0
      else:
        min(1.0, ln(max(1.0, row.contextPerCent)) / ln(1_000_000.0))
    let moderationComponent = if row.isModerated: 1.0 else: 0.0
    let priceComponent =
      if row.averagePrice.classify in {fcNaN, fcNegInf}:
        0.0
      elif row.averagePrice <= 0.0:
        1.0
      else:
        max(0.0, 1.0 - min(1.0, row.averagePrice * 2000.0))

    (0.35 * tagScore) + (0.25 * valueComponent) + (0.2 * contextComponent) +
      (0.1 * moderationComponent) + (0.1 * priceComponent)

  var scored: seq[(ModelRow, float)] = @[]
  for row in rows:
    let score = taskScore(row)
    if score >= 0.0:
      scored.add((row, score))

  scored.sort(proc(a, b: (ModelRow, float)): int =
    if a[1] > b[1]:
      return -1
    if a[1] < b[1]:
      return 1
    if a[0].contextPerCent > b[0].contextPerCent:
      return -1
    if a[0].contextPerCent < b[0].contextPerCent:
      return 1
    cmp(a[0].id, b[0].id)
  )

  for item in scored:
    result.add(item[0])

proc categorizeByModality*(rows: seq[ModelRow]): Table[string, seq[ModelRow]] =
  for row in rows:
    if row.modalities.len == 0:
      result.mgetOrPut("text", @[]).add(row)
      continue

    for modality in row.modalities:
      result.mgetOrPut(modality, @[]).add(row)
