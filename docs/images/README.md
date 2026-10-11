# README screenshots

These are native SwiftUI snapshots from the opt-in test preview renderers. They use fictional notes and tasks, temporary libraries, and isolated preferences. The agent connection state is an example; no agent server is started by that preview.

| Image | Renderer | Content |
| --- | --- | --- |
| `tasks-board.png` | `Tests/FoglioTests/TaskPreviews.swift` | Ember board with ticket IDs, a custom In review status, priorities, projects, labels, estimates, subtasks, and blockers. |
| `notes-editor.png` | `Tests/FoglioTests/LandingAssets.swift` | Notes editor with a fictional studio-launch checklist. |
| `task-editor.png` | `Tests/FoglioTests/LandingAssets.swift` | Shared rich editor with task properties and a saved ticket ID. |
| `agent-connections.png` | `Tests/FoglioTests/SettingsPreviews.swift` | Agent settings with access switches and setup buttons. |

From the repository root, regenerate the source previews:

```sh
FOGLIO_LANDING_ASSETS=website/assets/originals/app \
FOGLIO_TASK_PREVIEWS=/tmp/foglio-documentation-tasks \
FOGLIO_SETTINGS_PREVIEWS=/tmp/foglio-documentation-settings \
swift run --disable-sandbox FoglioTests
```

Copy the curated renders into their README and website locations:

```sh
cp /tmp/foglio-documentation-tasks/board-ember.png website/assets/originals/app/tasks-ember.png
cp /tmp/foglio-documentation-settings/agents-ember.png website/assets/originals/app/connectors-ember.png
cp website/assets/originals/app/tasks-ember.png docs/images/tasks-board.png
cp website/assets/originals/app/notes-ember.png docs/images/notes-editor.png
cp website/assets/originals/app/editor-ember.png docs/images/task-editor.png
cp website/assets/originals/app/connectors-ember.png docs/images/agent-connections.png
```

For the website, convert each source PNG to its matching `website/assets/images/*.webp` with `cwebp -q 92`. Preserve aspect ratios and keep descriptive alt text. The PNGs here are committed so GitHub can display the README without relying on attachment URLs or a running website.
