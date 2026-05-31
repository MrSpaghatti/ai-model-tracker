import std/[json, options]

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
    provider*: string
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
    dataPolicyLevel*: string
    dataPolicyNotes*: string
    dataPolicySource*: string

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
    data_policy_level*: string
    data_policy_notes*: string
    data_policy_source*: string

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
    changes*: JsonChangesSummary
    provider_stats*: seq[JsonProviderStats]

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

  LocalMetaFieldConfidence* = object
    source*: string
    confidence*: string
    notes*: string

  JsonLocalModel* = object
    id*: string
    name*: string
    size*: string
    ctx_window*: int
    quant*: string
    vram_fp16*: string
    vram_fp8*: string
    vram_4bit*: string
    best_for*: seq[string]
    notes*: string
    metadata*: JsonNode

  JsonLocalRoot* = object
    version*: int
    generated_at*: string
    models*: seq[JsonLocalModel]

  JsonPriceChange* = object
    model_id*: string
    provider*: string
    old_prompt_price*: float
    new_prompt_price*: float
    old_completion_price*: float
    new_completion_price*: float
    prompt_delta_pct*: float
    completion_delta_pct*: float

  JsonChangesSummary* = object
    new_models*: seq[string]
    removed_models*: seq[string]
    price_changes*: seq[JsonPriceChange]
    biggest_movers*: seq[JsonPriceChange]

  JsonProviderStats* = object
    provider*: string
    total_models*: int
    free_models*: int
    paid_models*: int
    moderated_models*: int
    moderation_coverage_pct*: float
    avg_prompt_price*: string
    avg_completion_price*: string
