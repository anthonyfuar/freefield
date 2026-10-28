# API providers and models (October 2026 review)

We reviewed which providers give access to the models in Freefield's selection and which models each one offers. **Decision: Freefield uses only OpenRouter and Google Gemini**, and the user picks the default provider in Settings.

## Providers reviewed

| Provider | Models from the selection it offers | Advantages | Why it is not integrated |
|---|---|---|---|
| **OpenRouter** (integrated, recommended) | 21 of 21 in the selection | A single key, capabilities read live, reports the real cost of each image | — |
| **Google Gemini** (integrated) | The Nano Banana family (5 models) | Free key in Google AI Studio | — |
| Replicate | 28 official models; adds GPT Image 1.5, Seedream 4.0, Flux Kontext Max, Ideogram 4.5, Z-Image, WAN 2.2 and Topaz Upscale | Synchronous response of up to 60 s | User's decision: only OpenRouter or Gemini. It also does not report the cost of each image. |
| fal.ai | All of them, including Kling O1, Seedream 5.0 Flash and Topaz Generative | The broadest catalog | User's decision. Also, each model has its own parameters and results expire within minutes. |
| Direct APIs (OpenAI, xAI, Black Forest Labs, BytePlus, Ideogram, DashScope, Kling, Recraft, Topaz) | Only each company's own models | Source pricing | A different key and protocol per company. Some require enabling each model per region or add a watermark by default. |

That is why the models that are **not** on OpenRouter are unavailable: GPT Image 1.5, Seedream 4.0, Flux Kontext Max, Ideogram 4.5, Kling O1, Z-Image, WAN 2.2 and the Topaz upscalers.

## Freefield models on each integrated provider

| Model | OpenRouter | Google |
|---|---|---|
| Nano Banana 2.1 | `google/gemini-nano-banana-2.1` | `gemini-nano-banana-2.1` |
| Nano Banana Pro | `google/gemini-3-pro-image` | `gemini-3-pro-image` |
| Nano Banana 2 | `google/gemini-3.1-flash-image` | `gemini-3.1-flash-image` |
| Nano Banana 2 Lite | `google/gemini-3.1-flash-lite-image` | `gemini-3.1-flash-lite-image` |
| Nano Banana | `google/gemini-2.5-flash-image` | `gemini-2.5-flash-image` |
| GPT Image 2.5 Sunburst / Flare | `openai/gpt-image-2.5-sunburst` / `-flare` | — |
| GPT Image 2 | `openai/gpt-image-2` | — |
| GPT Image | `openai/gpt-image-1` | — |
| Seedream 5.0 Pro / Flash / Lite | `bytedance-seed/seedream-5-0-pro` / `-flash` / `-lite` | — |
| Seedream 4.5 | `bytedance-seed/seedream-4.5` | — |
| FLUX 3 Image | `black-forest-labs/flux-3-image` | — |
| FLUX.2 Pro / Flex / Max | `black-forest-labs/flux.2-pro` / `-flex` / `-max` | — |
| Recraft V4.1 / Utility / Vector | `recraft/recraft-v4.1` / `-utility` / `-vector` | — |
| Recraft V4 Styles | `recraft/recraft-v4-styles` | — |
| Grok Imagine 2.0 | `x-ai/grok-imagine-image-2.0` | — |
| Grok Imagine | `x-ai/grok-imagine-image-quality` | — |

## Which models from the selection each provider offers

The full selection has 32 models with an API. This table gives each model's identifier on each reviewed provider; "—" means that provider does not offer it. Freefield uses the OpenRouter and Google columns.

**Verified on 2026-10-21** against live public sources, without generating images:

| Source | Result |
|---|---|
| OpenRouter catalog (`/api/v1/images/models`) | 22 of 22 identifiers present |
| fal.ai catalog (`/v1/models`) | All 58 endpoints, all active |
| Replicate model pages | All 29 models exist |
| Gemini model documentation | All 5 Google identifiers appear |
| OpenAI deprecations page | gpt-image-1 retires on 2026-10-23 and gpt-image-1.5 on 2026-12-01 |
| Public documentation of the direct APIs | All 21 identifiers appear: BytePlus model list (5), Black Forest Labs OpenAPI (5), Recraft model pages (3), xAI (2), Ideogram (1), Kling (1), Alibaba DashScope (2) and Topaz (2) |

| Model | OpenRouter | Google | fal.ai (text to image · edit) | Replicate | OpenAI | Other direct API |
|---|---|---|---|---|---|---|
| Nano Banana 2.1 | `google/gemini-nano-banana-2.1` | `gemini-nano-banana-2.1` | `google/nano-banana-2.1` · `google/nano-banana-2.1/edit` | `google/nano-banana-2.1` | — | — |
| Nano Banana Pro | `google/gemini-3-pro-image` | `gemini-3-pro-image` | `fal-ai/nano-banana-pro` · `/edit` | `google/nano-banana-pro` | — | — |
| Nano Banana 2 | `google/gemini-3.1-flash-image` | `gemini-3.1-flash-image` | `fal-ai/nano-banana-2` · `/edit` | `google/nano-banana-2` | — | — |
| Nano Banana 2 Lite | `google/gemini-3.1-flash-lite-image` | `gemini-3.1-flash-lite-image` | `google/nano-banana-2-lite` · `google/nano-banana-lite/edit` | `google/nano-banana-2-lite` | — | — |
| Nano Banana | `google/gemini-2.5-flash-image` | `gemini-2.5-flash-image` | `fal-ai/nano-banana` · `/edit` | `google/nano-banana` | — | — |
| GPT Image 2.5 Sunburst | `openai/gpt-image-2.5-sunburst` | — | `openai/gpt-image-2.5/sunburst/text-to-image` · `…/sunburst/edit` | `openai/gpt-image-2.5-sunburst` | `gpt-image-2.5-sunburst` | — |
| GPT Image 2.5 Flare | `openai/gpt-image-2.5-flare` | — | `openai/gpt-image-2.5/flare/text-to-image` · `…/flare/edit` | `openai/gpt-image-2.5-flare` | `gpt-image-2.5-flare` | — |
| GPT Image 2 | `openai/gpt-image-2` | — | `openai/gpt-image-2` · `/edit` | `openai/gpt-image-2` | `gpt-image-2` | — |
| GPT Image 1.5 | — | — | `fal-ai/gpt-image-1.5` · `/edit` | `openai/gpt-image-1.5` | `gpt-image-1.5` (retires 2026-12-01) | — |
| GPT Image | `openai/gpt-image-1` | — | `fal-ai/gpt-image-1/text-to-image` · `fal-ai/gpt-image-1/edit-image` | `openai/gpt-image-1` (requires an OpenAI key) | `gpt-image-1` (OpenAI retires it on 2026-10-23) | — |
| Seedream 5.0 Pro | `bytedance-seed/seedream-5-0-pro` | — | `bytedance/seedream/v5/pro/text-to-image` · `…/v5/pro/edit` | `bytedance/seedream-5-pro` | — | BytePlus `dola-seedream-5-0-pro-260628` |
| Seedream 5.0 Flash | `bytedance-seed/seedream-5-0-flash` | — | `bytedance/seedream/v5/flash/text-to-image` · `…/v5/flash/edit` | — | — | BytePlus `dola-seedream-5-0-flash-260915` |
| Seedream 5.0 Lite | `bytedance-seed/seedream-5-0-lite` | — | `bytedance/seedream/v5/lite/text-to-image` · `…/v5/lite/edit` | `bytedance/seedream-5-lite` | — | BytePlus `seedream-5-0-260128` |
| Seedream 4.5 | `bytedance-seed/seedream-4.5` | — | `fal-ai/bytedance/seedream/v4.5/text-to-image` · `…/v4.5/edit` | `bytedance/seedream-4.5` | — | BytePlus `seedream-4-5-251128` |
| Seedream 4.0 | — | — | `fal-ai/bytedance/seedream/v4/text-to-image` · `…/v4/edit` | `bytedance/seedream-4` | — | BytePlus `seedream-4-0-250828` |
| FLUX 3 Image | `black-forest-labs/flux-3-image` | — | `blackforestlabs/flux-3/text-to-image` · `…/flux-3/edit-image` | `black-forest-labs/flux-3-image` (not `flux-3`, which is video) | — | BFL `POST /v1/flux-3-image` |
| FLUX.2 Pro | `black-forest-labs/flux.2-pro` | — | `fal-ai/flux-2-pro` · `/edit` | `black-forest-labs/flux-2-pro` | — | BFL `/v1/flux-2-pro` |
| FLUX.2 Flex | `black-forest-labs/flux.2-flex` | — | `fal-ai/flux-2-flex` · `/edit` | `black-forest-labs/flux-2-flex` | — | BFL `/v1/flux-2-flex` |
| FLUX.2 Max | `black-forest-labs/flux.2-max` | — | `fal-ai/flux-2-max` · `/edit` | `black-forest-labs/flux-2-max` | — | BFL `/v1/flux-2-max` |
| Flux Kontext Max | — | — | `fal-ai/flux-pro/kontext/max/text-to-image` · `fal-ai/flux-pro/kontext/max` (1 image), `…/max/multi` | `black-forest-labs/flux-kontext-max` | — | BFL `/v1/flux-kontext-max` |
| Recraft V4.1 | `recraft/recraft-v4.1` | — | `fal-ai/recraft/v4.1/text-to-image` · — | `recraft-ai/recraft-v4.1` (text to image only) | — | Recraft `recraftv4_1` (supports editing) |
| Recraft V4.1 Utility | `recraft/recraft-v4.1-utility` | — | `fal-ai/recraft/v4.1/utility/text-to-image` · — | `recraft-ai/recraft-v4.1-utility` | — | Recraft `recraftv4_1_utility` |
| Recraft V4 Styles | `recraft/recraft-v4-styles` | — | `recraft/v4/style/text-to-image` (style references, not editing) | `recraft-ai/recraft-v4-styles` | — | Recraft `recraftv4_styles` |
| Grok Imagine | `x-ai/grok-imagine-image-quality` (quality mode) | — | `xai/grok-imagine-image` · `/edit` | `xai/grok-imagine-image` | — | xAI `grok-imagine-image` |
| Grok Imagine 2.0 | `x-ai/grok-imagine-image-2.0` | — | `xai/grok-imagine-image/v2.0/text-to-image` · `…/v2.0/edit` | `xai/grok-imagine-image-2` | — | xAI `grok-imagine-image-2.0` |
| Ideogram 4.5 | — | — | `ideogram/v4.5` · `ideogram/v4.5/edit` | `ideogram-ai/ideogram-4-5` (+ `ideogram-4-5-precise-edit`) | — | Ideogram `POST /v2/image/generate/ideogram-4-5` |
| Kling O1 (image) | — | — | `fal-ai/kling-image/o1` (**requires reference images**) | — | — | Kling `kling-image-o1` at `POST /v1/images/omni-image` |
| Z-Image | — | — | `fal-ai/z-image/turbo` · `…/turbo/image-to-image` | `prunaai/z-image-turbo` | — | DashScope `z-image-turbo` |
| WAN 2.2 (image) | — | — | `fal-ai/wan/v2.2-a14b/text-to-image` · `…/v2.2-a14b/image-to-image` | `prunaai/wan-2.2-image` | — | DashScope `wan2.2-t2i-flash` |
| Topaz Standard | — | — | `topaz/upscale/image/precision` | `topazlabs/image-upscale` | — | Topaz `POST /image/v1/enhance/async` |
| Topaz Generative | — | — | `topaz/upscale/image/generative` | — | — | Topaz `POST /image/v1/enhance-gen/async` |
| Bytedance Image Upscale | — | — | `fal-ai/seedvr/upscale/image` (ByteDance's SeedVR2; not confirmed to be the same model) | `zsxkib/seedvr2` (community version of the same SeedVR2) | — | — (not on BytePlus) |

## Findings from real tests

- **Seedream 4.5:** requires at least 3.7 MP (2K) even though the catalog advertises 1K. Freefield automatically retries at the next resolution.
- **Nano Banana 2.1:** in October 2026 it frequently returns Google's "quota exceeded" through OpenRouter, so it is not the default model for any tool.
- **Seedream for Storyboard:** when chaining frames off the first one, Seedream 4.5 tends to repeat the anchor frame; Nano Banana 2 keeps the character and changes the scene. That is why Storyboard uses Nano Banana 2.
- **Seedream 5.0 Flash:** sometimes invents a watermark in the corner of a product photo. The app recipes explicitly ask for no watermarks.
