# Local Model Recommendations

> Static reference page for popular self-hosted models. VRAM estimates are approximate and assume standard inference setups; quantization, KV cache, batching, and context length can move these numbers significantly.

| Model | Size | VRAM (FP16) | VRAM (4-bit) | Best For | Notes |
| --- | --- | ---: | ---: | --- | --- |
| Llama 3.2 | 1B | 4 GB | 2 GB | Light chat, assistants | Great for edge devices and cheap VPS GPUs. |
| Llama 3.2 | 3B | 6 GB | 3 GB | General chat, summarization | Comfortable on consumer 6 GB cards with 4-bit quantization. |
| Llama 3.1 | 8B | 16 GB | 8 GB | Balanced general-purpose use | One of the easiest strong 8B-class local models to run. |
| Qwen2.5 | 7B | 14 GB | 8 GB | General chat, multilingual work | Strong instruction following for the footprint. |
| Qwen2.5 | 14B | 28 GB | 16 GB | Higher-quality reasoning | Needs a roomier GPU for comfortable generation. |
| Qwen2.5 | 32B | 64 GB | 24 GB | Premium local reasoning | Great fit for 24 GB cards when quantized. |
| Qwen2.5 | 72B | 144 GB | 48 GB | Large-model quality | Multi-GPU or very large cards recommended. |
| Mistral | 7B | 14 GB | 8 GB | General chat, instruction tuning | Still a solid baseline for local inference. |
| Gemma 2 | 9B | 18 GB | 8 GB | Chat, analysis | Efficient option for consumer GPUs. |
| Gemma 2 | 27B | 54 GB | 20 GB | Long-form quality | Good target for 24 GB-class systems with quantization. |
| DeepSeek Coder V2 Lite | 16B | 32 GB | 12 GB | Coding | Local coding specialist with good IDE-assistant potential. |
| Phi-3 Mini | 3.8B | 8 GB | 4 GB | Tiny assistants, local apps | Fits low-end GPUs and laptops with eGPU setups. |
| Phi-3 Small | 7B | 14 GB | 6 GB | Compact reasoning | Good step-up from mini models. |
| Phi-3 Medium | 14B | 28 GB | 8 GB | Reasoning, analysis | Can squeeze onto 8 GB only with aggressive quantization/offload. |
| Neural Chat | 7B | 14 GB | 8 GB | Friendly assistant chat | Optimized for dialogue quality. |
| Zephyr | 7B | 14 GB | 8 GB | Instruction following | Popular open instruct baseline. |
| StarCoder2 | 3B | 6 GB | 4 GB | Lightweight coding | Good for autocomplete and small coding tasks. |
| StarCoder2 | 7B | 14 GB | 8 GB | Coding | Better completion quality on standard developer GPUs. |
| StarCoder2 | 15B | 30 GB | 12 GB | Higher-end coding | Best on 12 GB+ cards with quantization. |
| CodeLlama | 7B | 14 GB | 8 GB | Coding | Reliable local coding baseline. |
| CodeLlama | 13B | 26 GB | 12 GB | Coding, refactoring | Good sweet spot for 12 GB GPUs. |
| CodeLlama | 34B | 68 GB | 24 GB | Heavy coding workloads | Strong option for 24 GB workstations. |
| Mixtral | 8x7B | 90 GB | 48 GB | Reasoning, agent workflows | MoE model with very strong quality but big memory needs. |
| Command R | 35B | 70 GB | 48 GB | RAG, tool use | Excellent for retrieval-heavy local assistants. |
| Yi | 34B | 68 GB | 24 GB | Long-form writing, analysis | High-quality large open model family. |
| SOLAR | 10.7B | 22 GB | 8 GB | General chat, summarization | Great performance for modest 4-bit VRAM budgets. |
