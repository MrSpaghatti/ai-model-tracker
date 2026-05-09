import std/[algorithm, json, math, strformat, strutils]

import types

proc getString(node: JsonNode; key: string): string =
  if key notin node or node[key].kind == JNull:
    return ""

  node[key].getStr()

proc getInt(node: JsonNode; key: string): int =
  if key notin node or node[key].kind == JNull:
    return 0

  node[key].getInt()

proc getStringSeq(node: JsonNode; key: string): seq[string] =
  if key notin node or node[key].kind != JArray:
    return @[]

  for item in node[key].items:
    if item.kind == JString:
      result.add(item.getStr())

proc parsePrice(value, fieldName, modelId: string): float =
  if value.len == 0:
    return 0.0

  try:
    result = parseFloat(value)
    if result == -1.0:
      # -1 means variable/unknown pricing (router/meta models like openrouter/auto)
      return NaN
  except ValueError as exc:
    raise newException(
      ValueError,
      fmt"Invalid {fieldName} price for model '{modelId}': {value}. {exc.msg}"
    )

proc collectModalities(model: OpenRouterModel): seq[string] =
  for modality in model.architecture.input_modalities:
    if modality.len == 0:
      continue

    let normalized = modality.toLowerAscii()
    if normalized notin result:
      result.add(normalized)

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
    if averagePrice <= 0.0 or averagePrice.classify == fcNaN:
      if averagePrice.classify == fcNaN:
        NegInf
      else:
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
    isFree: promptPrice == 0.0 and completionPrice == 0.0,
    isModerated: model.top_provider.is_moderated,
    modalities: collectModalities(model)
  )

proc toOpenRouterModel(node: JsonNode): OpenRouterModel =
  let pricingNode =
    if "pricing" in node and node["pricing"].kind == JObject:
      node["pricing"]
    else:
      newJObject()

  let architectureNode =
    if "architecture" in node and node["architecture"].kind == JObject:
      node["architecture"]
    else:
      newJObject()

  let topProviderNode =
    if "top_provider" in node and node["top_provider"].kind == JObject:
      node["top_provider"]
    else:
      newJObject()

  result = OpenRouterModel(
    id: node.getString("id"),
    name: node.getString("name"),
    context_length: node.getInt("context_length"),
    pricing: Pricing(
      prompt: pricingNode.getString("prompt"),
      completion: pricingNode.getString("completion"),
      request: pricingNode.getString("request"),
      image: pricingNode.getString("image"),
      audio: pricingNode.getString("audio"),
      web_search: pricingNode.getString("web_search"),
      internal_reasoning: pricingNode.getString("internal_reasoning")
    ),
    architecture: Architecture(
      modality: architectureNode.getString("modality"),
      input_modalities: architectureNode.getStringSeq("input_modalities"),
      output_modalities: architectureNode.getStringSeq("output_modalities"),
      tokenizer: architectureNode.getString("tokenizer"),
      instruct_type: architectureNode.getString("instruct_type")
    ),
    top_provider: TopProvider(
      context_length: topProviderNode.getInt("context_length"),
      max_completion_tokens: topProviderNode.getInt("max_completion_tokens"),
      is_moderated: topProviderNode.hasKey("is_moderated") and topProviderNode["is_moderated"].kind == JBool and topProviderNode["is_moderated"].getBool()
    ),
    hugging_face_id: node.getString("hugging_face_id")
  )

proc parseModels*(rawJson: string): seq[ModelRow] =
  let payload = parseJson(rawJson)

  if "data" notin payload or payload["data"].kind != JArray:
    raise newException(CatchableError, "Unable to parse OpenRouter model registry: missing data array")

  for modelNode in payload["data"].items:
    if modelNode.kind == JObject:
      result.add modelNode.toOpenRouterModel().toModelRow()

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
