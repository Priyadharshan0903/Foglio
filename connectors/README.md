# Foglio agent connector

Foglio includes a local MCP stdio server for Codex, Claude Code, and Claude Desktop. The helper forwards requests to the running app through a private Unix socket. The app uses its live Store, Markdown editor data, and selected calendar source; the helper never writes your library files independently. No HTTP port, API key, hosted service, or npm dependency is needed.

## Start using it

1. Install or open the updated **Foglio 0.5.0** app.
2. In **Settings → Agent connections**, turn on **Allow connections**. Access starts with reading only.
3. Turn on **Allow changes** when you want agents to add or edit content.
4. Use the **Copy setup** button beside **Codex**, **Claude Code**, or **Claude Desktop**. The button briefly shows **Copied** to confirm. These copy configuration for the app you are currently running; changing your theme or normal app settings is not required.

Keep Foglio open while using the connector. Turning access off closes the endpoint and revokes pending requests. Permissions apply to all connected local agents. Local processes belonging to your macOS user can use the endpoint; this is not an authentication boundary between applications on the same account.

## Codex

Run the command copied from Foglio Settings. For an app installed in your personal Applications folder:

```sh
codex mcp add foglio -- "$HOME/Applications/Foglio.app/Contents/MacOS/FoglioMCP"
```

The command registers the stdio server with Codex. Use `codex mcp list` to check registration, then start a new agent session so the tools are discovered. For a project-specific configuration, adapt [codex.toml.example](codex.toml.example) with the absolute path to the app. These examples are not installed into your agent configuration automatically.

Source: [Official OpenAI MCP documentation](https://developers.openai.com/codex/mcp).

## Claude Code

```sh
claude mcp add --transport stdio --scope user foglio -- "$HOME/Applications/Foglio.app/Contents/MacOS/FoglioMCP"
```

This is the command **Copy Claude Code setup** produces. User scope makes Foglio available in every project, both in the `claude` CLI and in the Code tab of the Claude desktop app, since they share the same configuration. Use `claude mcp list` or `/mcp` in Claude Code to check the connection. Source: [Claude Code MCP documentation](https://code.claude.com/docs/en/mcp).

## Claude Desktop

Merge the JSON copied from Foglio Settings into your existing `mcpServers` object in Claude Desktop's configuration; preserve any other servers. [claude-desktop.json.example](claude-desktop.json.example) shows the structure. Use an absolute executable path, not a literal `~` or `$HOME`, in JSON. Restart Claude Desktop after editing the configuration.

Source: [MCP local-server setup guide](https://modelcontextprotocol.io/docs/develop/connect-local-servers).

## Available tools

Foglio exposes **26 tools**. The complete per-tool description and read/write inventory is also in the [main README](../README.md#all-26-connector-tools).

| Area | Tools |
| --- | --- |
| Connection | `foglio_status` |
| Workflow | `task_statuses`, `task_status_create`, `task_status_update` |
| Tasks | `task_lists`, `task_list_create`, `tasks_list`, `task_get`, `task_create`, `task_update`, `task_move` |
| Notes | `note_folders`, `note_folder_create`, `notes_list`, `note_get`, `note_create`, `note_update`, `note_move` |
| Calendar | `calendar_list`, `calendar_events`, `calendar_event_get`, `calendar_event_create`, `calendar_event_update`, `calendar_event_move` |
| Meeting workflow | `meeting_note_create`, `meeting_task_create` |

Notes and task descriptions accept Markdown, including headings, numbered lists, checklists, code, and tables. Tools read and write the editor's document content; they do not simulate clicks or typing.

Task **lists** such as Priority or Studio are independent from the board **status**. Call `task_statuses` for the ordered statuses and their stable IDs. Built-in IDs stay `backlog`, `todo`, `in_progress`, and `done`, even if renamed. Create custom statuses with `task_status_create`; rename or reorder them with `task_status_update`, using the latest workspace revision returned by `task_statuses`. Categories (`backlog`, `todo`, `in_progress`, `done`) determine completion semantics; status names and positions can change while IDs stay stable. Names must be unique (case-insensitive), single-line, and 1–80 characters; the app supports up to 20 statuses. In the app, use **Tasks → … → Manage statuses**.

Every saved task has an immutable ticket ID such as **FOG-42**, independent of its title and UUID. Existing tasks receive IDs on the first launch of 0.5.0 without rewriting their content. Numbers persist across restarts and are not reused when a task is deleted. `task_get`, `task_update`, and `task_move` accept either the UUID or ticket ID.

`task_create` and `task_update` accept structured `priority` (0 none, 1 urgent, 2 high, 3 normal, 4 low), `project`, `assignee`, `labels`, `due_date`, and `estimate` (1–100 points). Assignee is a local name, without accounts or notifications. Clear project/assignee/due date with an empty string, labels with `[]`, and estimate with `0`. Due dates use ISO 8601 date-times with a timezone. `tasks_list` can filter by status ID, list, project, and priority; search also matches ticket IDs, labels, projects, and assignees.

Set `parent_id` to a UUID or ticket ID to make a subtask; an empty string removes its parent. Set `blocked_by` to an array of task UUIDs/ticket IDs; `[]` clears dependencies. Missing tasks, self-links, and circular parent/dependency chains are rejected. Responses include `parent_id`, `subtask_ids`, `blocked_by`, and a computed `is_blocked`. Completing a blocker clears that indicator; it does not automatically move the dependent task. A task's revision covers its own stored fields, so changes to children/blockers require a fresh read to see computed relation state.

`task_move` can change list and/or any custom status. Completing a task uses the app's existing activity-log preference.

Example requests:

```json
{"name":"task_create","arguments":{"title":"Review the release","description":"- [ ] Check the DMG\n- [ ] Review notes","status":"backlog","priority":2,"project":"Foglio","labels":["Release"]}}
{"name":"notes_list","arguments":{"query":"release","limit":20}}
{"name":"calendar_events","arguments":{"start":"2026-10-10T00:00:00+05:30","end":"2026-10-17T00:00:00+05:30"}}
```

For edits and moves, read the item first and pass its exact `revision` back with its `id`. A newer human or agent change produces `conflict`; get the item again and merge your intended edit into its latest content. Task mutations return `resource_busy` while that task's editor is open, protecting its unsaved draft. Names and titles must be non-empty single-line values. List tools accept `limit` (1–200, default 50) and `offset`, and return `next_offset` or null. Notes lists include summaries; use `note_get` for the full document. Trash is excluded.

Calendar queries use the configured source and leave the app's visible week unchanged. Times are ISO 8601 with a timezone; queries are limited to 92 days. For feed/file events outside the visible week, pass a `date` from `calendar_events` to event-get or meeting tools. Feed credentials and imported file paths are not returned.

Calendar writes require the macOS Calendar source, existing full Calendar access granted through the app, and a writable calendar selected by its `calendar_id` from `calendar_list`. This version creates and edits personal, non-recurring timed events. Invited meetings, recurring events, all-day events, and read-only calendars are not editable through the connector. It does not manage attendees or send invitations. URL and `.ics` sources support event reading, meeting notes, and follow-up tasks.

There are no deletion, arbitrary-file, shell-execution, or calendar-account configuration tools. The app's access switches control writes; standard MCP annotations also distinguish read tools from mutations for the agent client.

## Custom workflow example

1. `task_status_create` with `{"name":"In review","category":"in_progress"}`.
2. Use its returned `id` in `task_move`, along with a task's current `revision`.
3. To rename, call `task_statuses` and pass that status's current `revision` to `task_status_update` with `{"id":"<status-id>","revision":"<revision>","name":"Review","position":2}`.
4. Start a new agent session or reconnect the MCP server after updating Foglio so it discovers the new tools. The executable path and access switches stay the same.

## Build and verify

The ordinary `scripts/bundle.sh` and `scripts/dmg.sh` include `FoglioMCP` inside the app and sign it along with the bundle. To build and check from the repository root in a restricted runner:

```sh
swift build --disable-sandbox --product FoglioMCP
swift run --disable-sandbox FoglioTests
```

The app test suite checks schemas and lifecycle, real Unix socket delivery, permissions, Markdown round trips, task moves, conflicts, human drafts, disk errors, permission revocation, the actual ICS backend, and a real stdio subprocess calling the live app service. All data fixtures use isolated temporary stores and preferences; tests do not create events in personal calendars.

`FoglioMCP --socket /absolute/path/agent.sock` targets a custom development instance. It does not load a standalone store or automatically start the app. MCP messages are newline-delimited JSON-RPC on stdout; diagnostics use stderr, as required by the [MCP stdio specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports).

If the app is closed or access is off, tool calls report `app_unavailable`. If the app is connected with reading only, edits report `read_only`. A `save_failed` result means disk persistence could not be confirmed; an edit may remain visible in the app's memory, so check storage access before retrying. Transport messages are limited to 4 MiB, and new Markdown bodies are limited to 256 KiB.
