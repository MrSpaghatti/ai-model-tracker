import std/os
import puppy

const
  OpenRouterModelsUrl = "https://openrouter.ai/api/v1/models"
  RegistryPath* = "data/registry.json"

proc fetchRegistryJson*(): string =
  var lastError = ""
  for attempt in 0..3:
    try:
      return fetch(
        OpenRouterModelsUrl,
        headers = @[
          Header(key: "Accept", value: "application/json"),
          Header(key: "HTTP-Referer", value: "https://github.com/spag/ai-model-tracker"),
          Header(key: "X-Title", value: "ai-model-tracker")
        ]
      )
    except PuppyError as exc:
      lastError = exc.msg
      if attempt < 3:
        sleep(300 * (attempt + 1))
  raise newException(CatchableError, "Unable to fetch OpenRouter model registry: " & lastError)

proc writeRawRegistry*(rawJson: string) =
  try:
    createDir(parentDir(RegistryPath))
    writeFile(RegistryPath, rawJson)
  except CatchableError as exc:
    raise newException(CatchableError, "Unable to write raw registry JSON: " & exc.msg)
