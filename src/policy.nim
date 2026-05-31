import std/[strutils, tables]

type
  DataPolicy* = object
    level*: string
    notes*: string
    source*: string

proc providerPolicies(): Table[string, DataPolicy] =
  result = initTable[string, DataPolicy]()
  result["openai"] = DataPolicy(level: "restricted", notes: "API data is generally not used for training by default for business usage, with exceptions for abuse and opt-in paths.", source: "https://openai.com/policies/how-your-data-is-used-to-improve-model-performance/")
  result["anthropic"] = DataPolicy(level: "restricted", notes: "Commercial API traffic is generally not used for training without permission.", source: "https://www.anthropic.com/legal/commercial-terms")
  result["google"] = DataPolicy(level: "mixed", notes: "Policy varies by product tier and account controls; verify workload-specific terms before use.", source: "https://cloud.google.com/terms/data-processing-addendum")
  result["meta-llama"] = DataPolicy(level: "unknown", notes: "Open weights availability does not imply hosted inference data handling guarantees.", source: "https://ai.meta.com/llama/")
  result["mistralai"] = DataPolicy(level: "restricted", notes: "Enterprise and API data handling policies indicate limited reuse with security controls.", source: "https://mistral.ai/terms/")
  result["qwen"] = DataPolicy(level: "unknown", notes: "Hosted inference and open-weight usage policies differ; check provider agreement.", source: "https://qwen.ai/")
  result["x-ai"] = DataPolicy(level: "unknown", notes: "Public policy details are limited; treat as unknown for sensitive workloads.", source: "https://x.ai/legal")
  result["deepseek"] = DataPolicy(level: "unknown", notes: "Data retention/training terms vary by deployment and are not consistently explicit.", source: "https://platform.deepseek.com/")
  result["cohere"] = DataPolicy(level: "restricted", notes: "Enterprise-focused terms indicate controlled data handling and limited model improvement use.", source: "https://cohere.com/terms-of-use")
  result["nvidia"] = DataPolicy(level: "restricted", notes: "Enterprise AI services typically provide DPA-backed processing controls.", source: "https://www.nvidia.com/en-us/agreements/")

proc inferPolicyFromModelId(modelId: string): DataPolicy =
  let lowered = modelId.toLowerAscii()
  if lowered.endsWith(":free"):
    return DataPolicy(
      level: "community",
      notes: "Free/community endpoints often have weaker contractual guarantees; avoid sensitive data.",
      source: "https://openrouter.ai/docs"
    )
  DataPolicy(
    level: "unknown",
    notes: "No explicit provider policy mapping found. Review the provider’s legal terms.",
    source: "https://openrouter.ai/models"
  )

proc getDataPolicy*(provider, modelId: string): DataPolicy =
  let policies = providerPolicies()
  if policies.hasKey(provider):
    return policies[provider]
  inferPolicyFromModelId(modelId)
