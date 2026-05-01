import std/[os, strutils]
import puppy

import parser

const
  OpenRouterModelsUrl = "https://openrouter.ai/api/v1/models"
  RegistryPath = "data/registry.json"
  ReadmeTemplatePath = "templates/README.md"
  ReadmeOutputPath = "README.md"
  ModelTablePlaceholder = "{{MODEL_TABLE}}"
  DefaultReadmeTemplate = """# AI Model Price Tracker

{{MODEL_TABLE}}
"""

proc fetchRegistryJson(): string =
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

proc writeRawRegistry(rawJson: string) =
  try:
    createDir(parentDir(RegistryPath))
    writeFile(RegistryPath, rawJson)
  except CatchableError as exc:
    raise newException(CatchableError, "Unable to write raw registry JSON: " & exc.msg)

proc loadReadmeTemplate(): string =
  try:
    if fileExists(ReadmeTemplatePath):
      return readFile(ReadmeTemplatePath)

    if fileExists(ReadmeOutputPath):
      let existingReadme = readFile(ReadmeOutputPath)
      if ModelTablePlaceholder in existingReadme:
        return existingReadme

    result = DefaultReadmeTemplate
  except CatchableError as exc:
    raise newException(CatchableError, "Unable to load README template: " & exc.msg)

proc writeReadme(tableMarkdown: string) =
  let readmeTemplate = loadReadmeTemplate()

  if ModelTablePlaceholder notin readmeTemplate:
    raise newException(CatchableError, "README template is missing the {{MODEL_TABLE}} placeholder")

  try:
    writeFile(ReadmeOutputPath, readmeTemplate.replace(ModelTablePlaceholder, tableMarkdown))
  except CatchableError as exc:
    raise newException(CatchableError, "Unable to write README.md: " & exc.msg)

proc main() =
  try:
    let rawJson = fetchRegistryJson()
    writeRawRegistry(rawJson)

    let rows = parseModels(rawJson)
    let markdownTable = generateMarkdownTable(rows)
    writeReadme(markdownTable)

    stdout.writeLine("Generated README.md for " & $rows.len & " models.")
  except CatchableError as exc:
    stderr.writeLine("Error: " & exc.msg)
    quit(QuitFailure)

when isMainModule:
  main()
