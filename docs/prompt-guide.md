# Freefield prompt guide

Summary of the October 2026 research on how to write prompts for each family of image models Freefield uses (through OpenRouter or Google), and how it was applied to each tool's internal instructions. The main sources are each provider's official guides and their OpenRouter documentation. The full list is at the end.

## Common principles

The same prompt goes to every model, so these rules apply to all of them:

1. **Name each image by its role**, in the order it is sent ("Image 1 is the scene. Image 2 is the product."). Count only the images that actually fit the model, because each one accepts a different maximum. From then on always say "the product from Image 2", never "it".
2. **Start with an image verb:** "Generate…", "Using Image 1, change only…", "Edit Image 1: add…". Without one, Gemini sometimes answers with text instead of an image.
3. **Edits in three parts, in this order:**
   - **Action:** a single change on a clear target.
   - **Preserve:** face, framing, angle, light and colors.
   - **Integrate:** light, perspective and grain.

   Never start with "keep everything": Grok barely changes the image if that is the first thing it reads.
4. **Describe what should be there.** "An empty street" instead of "no cars". Long lists of "don'ts" are ignored or even draw the forbidden thing. One short exclusion at the end is fine ("No other text.").
5. **No filler words.** "8K", "masterpiece", "ultra-detailed", "stunning" and "award-winning" improve nothing and make FLUX and Grok worse.
6. **Connected prose, not tags**, in this order: purpose → subject (materials, quantities) → action → location → shot and angle → style → light (source, direction, quality) → exact text → constraints. FLUX and Grok give more weight to what comes first.
7. **Text in the image in straight quotes**, "exactly once, verbatim", stating style and position, and closing with "No other text."
8. **Masks and sketches:**
   - the clean image goes as Image 1 and the marked one as Image 2;
   - state that the mark only indicates the area or is an instruction;
   - ask for no red residue or strokes to remain.
9. **Identity and product by attributes.** For a person: face, facial structure, skin tone, hairstyle and hair color. For a product: shape, proportions, label, logo and colors. Never describe the product in a way that contradicts the photo.
10. **Realism through what a real camera records:** skin texture with pores, worn materials, natural directional light and subtle grain. Lens or aperture are understood as "aesthetic", not exact optics.
11. **Variations through parallel 1-image calls**, not by asking for "4 variants" in the prompt. Gemini, FLUX, Seedream 5.0 Pro/Flash and Grok generate only 1 per call.
12. **Instructions in English; rendered text stays in its original language, in quotes.** Freefield's translator never touches quoted text, "Image N" references, hex codes or units.

## By model family

### Google Nano Banana (2.5 Flash, Pro, 2, 2.1, Lite)
- One narrative paragraph of 60 to 200 words, in the order from point 6.
- To compose several images: one role sentence per image, then the relationship between them, then the final scene. For pasted objects, ask to "re-render it to match the scene's light, do not paste it flat".
- Positions relative to the frame ("in the bottom-left corner"), because it confuses left and right.
- For long text or text in other languages, Pro at 2K or 4K works best.
- **Avoid:**
  - asking for several images in one call;
  - exceeding its reference limits (2.5 Flash accepts 3);
  - extreme aspect ratios on Pro and 2.5;
  - trusting masks blindly: it sometimes leaves ink behind.

### OpenAI GPT Image (2, 2.5 Sunburst and Flare)
- State the use first: ad, editorial photo, poster…
- Phrase composition as an edit: "Edit Image 1: add the X from Image 2…". For precision: "change only X" plus the list of what is preserved.
- Medium quality by default; high when there is quoted text or close-up faces.
- On 2.5: "with no extra punctuation; add no other signage". It tends to add a trailing period or signs nobody asked for.
- **Avoid:**
  - asking for a transparent background on gpt-image-2: only 2.5 supports it;
  - promising identical pixels: the right way is to composite in the app.
- gpt-image-1 retires on October 23, 2026. Freefield already uses its successor.

### ByteDance Seedream (4.5, 5.0 Pro, Flash and Lite)
- Start with format and purpose ("Design a … for …"), then a flowing paragraph.
- For edits: "[Add/Remove/Replace] [precise target] …, keeping [pose] unchanged".
- Official multi-image syntax: "Replace the subject in Image 1 with the subject from Image 2", "Dress the character in Image 1 with the outfit from Image 2".
- Seedream already rewrites the prompt on its own, so avoid over-expanding it. Ideally 40 to 150 words, and up to 3,500 characters in Freefield.
- **Avoid:**
  - 5.0 Lite for product photos or realistic portraits;
  - more than 10 references on 5.0 Pro/Flash.

### Black Forest Labs FLUX 3 and FLUX.2
- Short prompts: the most important part goes first and the model expands on its own. Typically 30 to 80 words.
- Tie each hex color to an object ("the sofa in green, hex #2E3B32"). On FLUX.2, describe the photo as real: pores, wrinkles, worn fabric.
- **Avoid:**
  - negative prompts, seed, guidance or unknown fields: FLUX 3 rejects them;
  - using FLUX.2 to change faces or text.
- **Limit:** FLUX.2 accepts about 1,800 characters and FLUX 3 about 2,000.

### Recraft (V4.1, Utility, Vector, V4 Styles)
- **Two modes:**
  - **Explore:** short prompt, almost untouched.
  - **Precise:** logo or poster structure with 5 to 7 constraints.
- Utility suits catalog work; Vector suits SVG.
- **Avoid:**
  - masks, sketches, inpaint or "Image 1/Image 2" compositions: it accepts at most 1 reference;
  - more than about 8 to 10 words of text.

### xAI Grok Imagine 2.0
- First a sentence with the subject, its form, its medium and the location. Then: details and focal point → art direction → light (with "bright, readable exposure") → subject and background colors separately → composition. 4 to 6 sentences in total.
- For edits, 1 to 3 imperative changes, then "Keep the same subject, angle, crop…".
- **Avoid:**
  - lists of "don'ts";
  - words that get drawn as defects ("crushed shadows", "dust", "scratches");
  - repeating texture words.
- **Limit:** about 1,000 characters in total, which is why Freefield's edit wrappers stay under about 450.
- grok-imagine-image-quality retires on November 2, 2026. Freefield already uses 2.0.

## What changed in Freefield

**Tool recipes (`Recipes.swift`):**
- Create, Storyboard, Edit, Inpaint, Draw to Edit, Upscale, Relight, Angles, Orbit, Edit Text, Expand, Background, Product, Face Swap, Character Swap, Outfit Swap and Place Product carry the image legend, the opening verb and the three-part structure.
- The character's image count is the real one, after trimming to the model's maximum.

**Quick styles (`AppCatalog.swift`):**
- Input legend.
- A different identity line for realistic and stylized results.
- Realism suffixes phrased positively.
- 15 templates rewritten with exact quoted text, no invented lettering and concrete scenes.

**Palettes (`StylePresets.swift`):** each color has a role (dominant, secondary, accents) instead of a list of codes.

**Assistant, translator and descriptions (`AppModel+Generate.swift`):**
- **Assistant:** writes 40 to 90 words in the recommended order, with no filler and respecting quotes and names.
- **Translator:** protects quotes, "Image N", hex and units, and uses standard photography terms.
- **Moodboard:** described in 45 words or fewer.

**Storyboard and photo session (`AppModel+Sequences.swift`):**
- **Storyboard:** each shot stands on its own, with the character always named the same way and no dialogue, and shot 1 serves as an anchor without being copied.
- **Photo Session:** reads like a real phone photo.

**Limits:** each field computes its cap from the full prompt that is actually sent.

**Tests:**
- The 15 rewritten styles regenerated their example.
- Edit, Edit Text, Inpaint, Place Product with zones, Face Swap and translation with quoted text were tested with real generations.

## Main sources

- OpenRouter: [image generation](https://openrouter.ai/docs/guides/overview/multimodal/image-generation) and the `api/v1/images/models` catalog with each model's endpoints.
- Google: [Gemini API, image generation](https://ai.google.dev/gemini-api/docs/image-generation), [DeepMind prompt guide](https://deepmind.google/models/gemini-image/prompt-guide/), [Vertex AI, best practices](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/multimodal/gemini-image-generation-best-practices) and [limitations](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/multimodal/gemini-image-generation-limitations), [Nano Banana Pro prompting guide](https://dev.to/googleai/nano-banana-pro-prompting-guide-strategies-1h9n), [getting the most out of Nano Banana 2](https://dev.to/googleai/getting-the-most-out-of-nano-banana-2-502k) and the Gemini 3 Pro Image and 3.1 Flash Image model cards.
- OpenAI: [image prompting guide](https://developers.openai.com/api/docs/guides/image-prompting), [image generation](https://developers.openai.com/api/docs/guides/image-generation) and [image model prompting cookbook](https://developers.openai.com/cookbook/examples/multimodal/image-gen-models-prompting-guide).
- ByteDance: [Seedream 4.0/5.0 prompt guide](https://docs.byteplus.com/en/docs/ModelArk/seedream-4-0-5-0-prompt-guide), [5.0 Pro editing guide](https://docs.byteplus.com/en/docs/ModelArk/seedream-5-0-pro-editing-guide) and [image API](https://docs.byteplus.com/en/docs/ModelArk/image-generation-api).
- Black Forest Labs: [FLUX 3](https://docs.bfl.ml/flux_3/flux3_image_overview.md), [FLUX.2 prompting guide](https://docs.bfl.ai/guides/prompting_guide_flux2), [multi-reference editing](https://docs.bfl.ml/guides/prompting_editing_multi_reference.md), [photorealism](https://docs.bfl.ml/guides/usecases_t2i_photorealistic.md) and [hex colors](https://docs.bfl.ml/guides/usecases_t2i_hex_color_prompting.md).
- Recraft: [prompting with Recraft V4](https://www.recraft.ai/docs/prompt-engineering-guide/prompting-with-recraft-v4) and [Recraft V4.1](https://www.recraft.ai/docs/recraft-models/recraft-v4-1).
- xAI: [Grok Imagine prompting guide](https://docs.x.ai/developers/model-capabilities/images/prompting-guide), [multi-image editing](https://docs.x.ai/developers/model-capabilities/images/multi-image-editing) and [November 2 migration](https://docs.x.ai/developers/migration/imagine-image-quality-nov-2).
- Comparisons: [Artificial Analysis image arena](https://artificialanalysis.ai/text-to-image/arena/leaderboard-image) and [LMArena changelog](https://arena.ai/company/leaderboard-changelog/).
