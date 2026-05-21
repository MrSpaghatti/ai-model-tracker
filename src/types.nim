import std/options

type
  Pricing* = object
    prompt*: string
    completion*: string
    request*: string
    image*: string
    audio*: string
    web_search*: string
    internal_reasoning*: string

  Architecture* = object
    modality*: string
    input_modalities*: seq[string]
    output_modalities*: seq[string]
    tokenizer*: string
    instruct_type*: string

  TopProvider* = object
    context_length*: int
    max_completion_tokens*: int
    is_moderated*: bool

  OpenRouterModel* = object
    id*: string
    name*: string
    context_length*: int
    pricing*: Pricing
    architecture*: Architecture
    top_provider*: TopProvider
    hugging_face_id*: string

  OpenRouterResponse* = object
    data*: seq[OpenRouterModel]

  ModelRow* = object
    id*: string
    name*: string
    contextLength*: int
    promptPrice*: float
    completionPrice*: float
    requestPrice*: float
    hasRequestPrice*: bool
    averagePrice*: float
    contextPerCent*: float
    isFree*: bool
    isModerated*: bool
    modalities*: seq[string]

  JsonModel* = object
    id*: string
    name*: string
    provider*: string
    context_length*: int
    pricing*: Pricing
    created_at*: string
    is_free*: bool
    is_moderated*: bool
    modalities*: seq[string]

  JsonHistoryEntry* = object
    model_id*: string
    from_date*: string
    to_date*: Option[string]
    prompt_price*: float
    completion_price*: float

  JsonCurrentRoot* = object
    version*: int
    generated_at*: string
    models*: seq[JsonModel]

  JsonHistoryRoot* = object
    version*: int
    generated_at*: string
    entries*: seq[JsonHistoryEntry]

  LocalModelMeta* = object
    hfId*: string
    name*: string
    size*: string
    bestFor*: string
    notes*: string
