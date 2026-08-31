# Visual design contract

## Requirement

The edge rail must reproduce the design and interaction shown in
[Vinz's side-notch post](https://x.com/hivinz_/status/2093651446927626294) with high visual and
motion fidelity. A conventional sidebar, detached tooltip, generic SwiftUI panel, or merely similar
color palette does not satisfy this requirement.

The menu-bar panel uses the information hierarchy in
[DHH's usage-panel post](https://x.com/dhh/status/2090005543112851862) as a direction, not an exact
visual-copy requirement. It adds multiple accounts and keeps one provider active at a time.

## Reference hierarchy

1. The 20.5-second side-notch video is authoritative for runtime scale, pointer interaction, rail
   expansion, provider selection, attached-panel movement, and dismissal.
2. The 2000 x 2000 side-notch image is authoritative for the black shell, organic edge silhouette,
   ring treatment, spacing, type hierarchy, and progress bars.
3. The creator's later image with the bottom arc and circular settings control is authoritative for
   that refinement.
4. The DHH image is authoritative only for the menu-bar information hierarchy: provider tabs,
   account identity, limit labels, full-width progress bars, and reset countdowns.

The promotional side-notch images use perspective, rotation, wallpaper, and presentation shadows.
Those effects are not application chrome. If the image conflicts with the running video, the video
wins for runtime geometry.

## Edge-rail states

### Mini handle

- A small black vertical pill peeks from the selected edge.
- It contains no percentage or provider icon.
- Activating it grows the rail from the edge instead of opening a detached window.

### Rail

- The rail is pure black and flush with the screen edge.
- Its top and bottom use the reference's convex-to-concave organic contour.
- A standard rounded rectangle fails the design.
- The initial fixture uses the same three provider rows and reference percentages.
- Each row contains a dark circular track, thin bright usage arc, centered provider mark, and white
  percentage.
- The reference accents are orange-red for Claude, green for OpenAI, and neon yellow for Cursor.

### Provider detail

- The detail panel opens to the left of the active ring.
- A black triangular connector joins the panel and rail without a gap.
- The panel uses the reference's compact title, muted labels, reset text, narrow progress tracks,
  and provider-colored fills.
- Moving between providers repositions and morphs one persistent panel. It must not look like
  unrelated popovers opening and closing.

### Settings entry

- The bottom control uses the later reference's black circular button and curved rail connection.
- Its negative space is part of the silhouette.
- The settings content opens in a normal macOS window.

## Menu-bar panel

The menu-bar panel keeps the dark, information-dense character of the DHH reference while using
native macOS behavior.

- Provider tabs appear first.
- One provider is active at a time.
- An account switcher appears directly below the provider identity.
- The selected account's plan and freshness remain visible.
- Quota rows use full-width tracks, right-aligned percentages, and reset countdowns.
- An All accounts view lists the selected provider's accounts without averaging percentages.
- The panel must work without the edge rail.

## Fidelity workflow

Build with fixed simulated data before adding provider adapters:

1. Capture clean frames for the mini handle, full rail, and every provider-detail state.
2. Implement static silhouettes in the video's native coordinate system.
3. Overlay implementation captures with matching video frames.
4. Correct geometry, spacing, type, stroke, and color differences.
5. Implement motion and compare frame sequences for reveal, switching, refresh, and dismissal.
6. Record the application at the same desktop scale and review it beside the source video.
7. Repeat at Retina scale and on a second display size.
8. Get explicit visual approval before connecting live provider data.

Image overlays and perceptual diffs provide diagnostic evidence. A numerical threshold cannot
override an obvious silhouette, typography, or motion mismatch.

## Acceptance matrix

| Surface | Evidence | Pass condition |
| --- | --- | --- |
| Mini handle | Matched screenshot | Position, thickness, height, radius, and edge attachment are visually equivalent. |
| Full rail | Matched screenshot | Outer contour, row spacing, rings, percentages, and bottom treatment reproduce the reference. |
| Claude detail | Matched screenshot | Panel size, connector, quota rows, reset labels, and orange-red progress match. |
| OpenAI detail | Matched screenshot | Panel relocation and green treatment match without layout drift. |
| Cursor detail | Matched screenshot | Compact layout and neon-yellow treatment match. |
| Rail reveal | Side-by-side recording | Origin, duration, easing, and silhouette change feel equivalent. |
| Provider switch | Frame sequence | Connector, panel position, size morph, and content transition remain continuous. |
| Dismissal | Side-by-side recording | Panel and rail return to mini mode with the same spatial logic. |
| Settings arc | Matched screenshot | Circular control, curved attachment, and negative space reproduce the later image. |
| Menu-bar panel | Running application | Provider and account switching remain compact, legible, and native. |

## Quality boundary

The reference Figma measurements and source assets are not available. The project can promise
perceptual and behavioral parity, verified against the supplied media, but cannot claim identical
unpublished control points or motion values. Derive unknown values from runtime frames and record
them as project tokens instead of substituting convenient platform defaults.

Provider marks and the reference artwork remain their owners' assets. Review licenses and product
identity before public distribution. This does not lower the private prototype's fidelity target.
