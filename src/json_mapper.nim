import std/[math, strutils, times]
import types

proc formatPriceForJson(price: float): string =
  if price.classify == fcNaN:
    return ""
  formatFloat(price, ffDecimal, 12)

proc utcIsoTimestamp*(): string =
  now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc toJsonModel*(row: ModelRow): JsonModel =
  let provider =
    if row.provider.len > 0:
      row.provider
    elif "/" in row.id:
      row.id.split("/")[0]
    else:
      ""

  result = JsonModel(
    id: row.id,
    name: row.name,
    provider: provider,
    context_length: row.contextLength,
    pricing: Pricing(
      prompt: formatPriceForJson(row.promptPrice),
      completion: formatPriceForJson(row.completionPrice),
      request:
        if row.hasRequestPrice:
          formatPriceForJson(row.requestPrice)
        else:
          "",
      image: "",
      audio: "",
      web_search: "",
      internal_reasoning: ""
    ),
    created_at: utcIsoTimestamp(),
    is_free: row.isFree,
    is_moderated: row.isModerated,
    modalities: row.modalities,
    data_policy_level: row.dataPolicyLevel,
    data_policy_notes: row.dataPolicyNotes,
    data_policy_source: row.dataPolicySource
  )
