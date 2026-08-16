# Third-Party Notices

FlowLocal bundles or downloads the following third-party software and models.

## Swift packages

| Package | Version | License | Source |
|---|---|---|---|
| GRDB.swift | 7.11.1 | MIT | https://github.com/groue/GRDB.swift |
| FluidAudio | 0.15.5 | Apache-2.0 | https://github.com/FluidInference/FluidAudio |
| WhisperKit (argmax-oss-swift) | 1.0.0 | MIT | https://github.com/argmaxinc/WhisperKit |
| MLX Swift LM | 3.31.4 | MIT | https://github.com/ml-explore/mlx-swift-lm |
| MLX Swift | 0.31.6 | MIT | https://github.com/ml-explore/mlx-swift |
| swift-huggingface | 0.9.0 | Apache-2.0 | https://github.com/huggingface/swift-huggingface |
| swift-transformers | 1.3.3 | Apache-2.0 | https://github.com/huggingface/swift-transformers |

Exact pins for every package (including transitive) are recorded in `Package.resolved`.

## Models (downloaded on user request only)

| Model | License | Attribution |
|---|---|---|
| Apple on-device speech assets | Apple system software | Managed and downloaded by macOS |
| NVIDIA Parakeet TDT 0.6B v3 (CoreML, FluidInference/parakeet-tdt-0.6b-v3-coreml) | **CC BY 4.0** | © NVIDIA Corporation. Converted to Core ML by FluidInference. This product uses the Parakeet TDT v3 model under the Creative Commons Attribution 4.0 license: https://creativecommons.org/licenses/by/4.0/ |
| OpenAI Whisper large-v3 turbo (CoreML, argmaxinc/whisperkit-coreml) | MIT | © OpenAI. CoreML conversion by Argmax. |
| Qwen instruct models (MLX 4-bit quantizations, mlx-community) | Apache-2.0 | © Alibaba Cloud / Qwen team. MLX quantization by the mlx-community. |

All inference runs locally on this Mac. No third-party service receives audio,
transcripts, or context. Model files are fetched from Hugging Face over HTTPS
only when the user initiates an install.
