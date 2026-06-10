# Local Model Recommendations

> Data sourced from HuggingFace model configs. Models updated May 2026. VRAM estimates include weights, KV cache, and activation overhead. Actual usage varies.

| Model | Size | Ctx Window | Quant | VRAM (FP16) | VRAM (FP8) | VRAM (4-bit) | Best For | Notes |
| --- | --- | ---: | --- | ---: | ---: | ---: | --- | --- |
| Gemma 4 E2B | 2.3B | 131,072 | FP16, FP8, 4-bit | 7 GB | 4 GB | 3 GB | Edge devices, phones, audio AI | 2.3B active params, native audio + vision, Apache 2.0. Runs on phones. |
| Gemma 4 E4B | 4.5B | 131,072 | FP16, FP8, 4-bit | 13 GB | 8 GB | 5 GB | Small GPU, multimodal chat | 4.5B active, vision + audio + video. Great for 8 GB GPUs. |
| Phi-4 Mini | 3.8B | 4,096 | FP16, FP8, 4-bit | 11 GB | 7 GB | 4 GB | Tiny coding assistants, local apps | MIT license, 128K context, punches above its weight on coding. |
| Llama 3.2 | 3B | 131,072 | FP16, FP8, 4-bit | 9 GB | 5 GB | 4 GB | Light chat, summarization | Solid small model with 128K context. Great for cheap VPS GPUs. |
| Mistral | 7B | 4,096 | FP16, FP8, 4-bit | 19 GB | 11 GB | 7 GB | General chat, instruction tuning | Reliable 7B baseline, 32K context, Apache 2.0. |
| Llama 3.1 | 8B | 131,072 | FP16, FP8, 4-bit | 22 GB | 13 GB | 8 GB | Balanced general-purpose use | One of the strongest 8B-class models. 128K context. |
| Qwen2.5 | 7B | 4,096 | FP16, FP8, 4-bit | 19 GB | 11 GB | 7 GB | Multilingual chat, high-quality output | Battle-tested 7B with excellent instruction following. |
| DeepSeek Coder V2 Lite | 16B | 4,096 | FP16, FP8, 4-bit | 43 GB | 24 GB | 15 GB | Coding | Strong coding specialist, fits 12 GB cards with quantization. |
| SOLAR | 10.7B | 4,096 | FP16, FP8, 4-bit | 29 GB | 17 GB | 10 GB | General chat, summarization | Great quality-per-VRAM at 10.7B. Fits 8 GB with 4-bit. |
| Phi-3 Medium | 14B | 4,096 | FP16, FP8, 4-bit | 37 GB | 21 GB | 13 GB | Reasoning, analysis | Solid 14B option, squeezes onto 8 GB with aggressive quantization. |
| Gemma 4 26B MoE | 26B | 262,144 | FP16, FP8, 4-bit | 69 GB | 39 GB | 24 GB | Premium efficiency, reasoning | 3.8B active / 26B total MoE. ~97% of 31B quality, 256K context. |
| Gemma 4 31B | 31B | 262,144 | FP16, FP8, 4-bit | 82 GB | 46 GB | 28 GB | Best overall, math, coding, vision | #3 on LMArena. 89% AIME, 80% LiveCodeBench. Apache 2.0. Needs 24 GB at Q4. |
| Qwen2.5 | 14B | 4,096 | FP16, FP8, 4-bit | 37 GB | 21 GB | 13 GB | Higher-quality reasoning | Comfortable on 16 GB cards. Strong multilingual support. |
| Qwen2.5 | 32B | 4,096 | FP16, FP8, 4-bit | 84 GB | 47 GB | 29 GB | Premium local reasoning | Great fit for 24 GB cards with 4-bit quantization. |
| CodeLlama | 34B | 16,384 | FP16, FP8, 4-bit | 89 GB | 50 GB | 31 GB | Heavy coding workloads | Dedicated coding model. Strong option for 24 GB workstations. |
| Qwen2.5 | 72B | 4,096 | FP16, FP8, 4-bit | 188 GB | 105 GB | 64 GB | Large-model quality | Multi-GPU or very large cards recommended. Top-tier output. |
| Mixtral | 8x7B | 4,096 | FP16, FP8, 4-bit | 147 GB | 82 GB | 50 GB | Reasoning, agent workflows | MoE with very strong quality but 90 GB+ at FP16. Needs multi-GPU. |
| Command R | 35B | 131,072 | FP16, FP8, 4-bit | 92 GB | 52 GB | 32 GB | RAG, tool use | Excellent retrieval quality. Optimized for RAG pipelines. |
| DeepSeek R1 Distill | 8B | 131,072 | FP16, FP8, 4-bit | 22 GB | 13 GB | 8 GB | Reasoning tasks | Distilled reasoning model. Fits 8 GB GPUs with quantization. |
| Mistral Small 3.1 | 24B | 131,072 | FP16, FP8, 4-bit | 63 GB | 36 GB | 22 GB | Fast inference, quality output | Apache 2.0, 128K context. ~35 tok/s on RTX 4090 at Q4. |
| Yi | 34B | 4,096 | FP16, FP8, 4-bit | 89 GB | 50 GB | 31 GB | Long-form writing, analysis | High-quality 34B open model. Suitable for 24 GB with quantization. |
