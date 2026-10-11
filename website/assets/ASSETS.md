# Landing-page assets

Visual direction: tactile ivory paper, warm amber light, and deep charcoal. Copy stays in semantic HTML so it remains readable, selectable, responsive, and available to assistive technology.

| Asset | Source | Use and animation |
| --- | --- | --- |
| `images/paper-landscape.webp` | Built-in `image_gen`; untouched PNG in `originals/paper-landscape.png` | Wide hero background. Dark upper/center negative space supports the headline; lower folds frame the product. Slow vertical parallax with a small overscan prevents exposed edges. |
| `images/paper-sculpture.webp` | Built-in `image_gen`; transparent PNG in `originals/paper-sculpture.png` | Independent foreground layer for the editor and download sections. Preserve alpha, use `object-fit: contain`, gentle floating/rotation, and enough margin for the paper tips. |
| `images/notes-*.webp` | Native SwiftUI renders, eight actual app themes | Hero, writing preview, and theme switcher. Keep their original aspect ratio. Crossfade screenshots rather than distorting or recoloring the UI. |
| `images/tasks-ember.webp` | Native SwiftUI render | Task-board story. Uses the actual board with ticket IDs, structured task properties, and a custom In review status, with fictional studio tasks. |
| `images/editor-ember.webp` | Native SwiftUI render | Shared rich-editor story: actual formatting toolbar, checklist, quote, and table. |
| `images/connectors-ember.webp` | Native SwiftUI render from `SettingsPreviews.swift` | Agent connection showcase. Example reading-only state, access switches, and setup buttons; no live agent connection is started by the preview. |
| `images/app-icon.png` | Selected Refined Margin icon from `scripts/make-icon.swift` | Navigation, footer, and favicon. Warm ivory, charcoal strokes, and an amber dot; matches the selected icon concept. |
| `fonts/Geist.ttf`, `fonts/GeistMono.ttf` | Existing bundled fonts | Self-hosted variable fonts. License included as `fonts/OFL.txt`. |

The generation method was the **built-in image generation tool**, not the API/CLI fallback. Exact final prompts are preserved in [prompts.json](prompts.json); these include composition, palette, material, negative-space, transparency, and no-text constraints.

Generated artwork is decorative (`alt=""`, hidden from accessibility). Native previews have descriptive alt text and captions identifying example content. The calendar illustration is built in HTML/CSS, uses illustrative meetings, and is labeled accordingly. No stock photography or invented product screenshots are used.

Motion limits: subtle transforms only; no scroll interception, forced cursor effects, autoplay video, flashing, or full-page loading screen. Respect `prefers-reduced-motion` and avoid hover-only interactions on touch devices. Keep typography and controls outside the raster images.
