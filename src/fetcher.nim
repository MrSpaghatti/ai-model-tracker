import std/os
import puppy

const
  OpenRouterModelsUrl = "https://openrouter.ai/api/v1/models"
  RegistryPath* = "data/registry.json"

proc fetchRegistryJson*(): string =
  try:
    result = fetch(
      OpenRouterModelsUrl,
      headers = @[
        Header(key: "Accept", value: "application/json"),
        Header(key: "HTTP-Referer", value: "https://github.com/spag/ai-model-tracker"),
        Header(key: "X-Title", value: "ai-model-tracker")
      ]
    )
  except PuppyError as exc:
    raise newException(CatchableError, "Unable to fetch OpenRouter model registry: " & exc.msg)

proc writeRawRegistry*(rawJson: string) =
  try:
    createDir(parentDir(RegistryPath))
    writeFile(RegistryPath, rawJson)
  except CatchableError as exc:
    raise newException(CatchableError, "Unable to write raw registry JSON: " & exc.msg)
