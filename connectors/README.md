# Foglio agent connector

Foglio includes a local MCP stdio server for Codex, Claude Code, and Claude Desktop. The helper forwards requests to the running app through a private Unix socket. The app uses its live Store, Markdown editor data, and selected calendar source; the helper never writes your library files independently. No HTTP port, API key, hosted service, or npm dependency is needed.

## Start using it

1. Install or open the updated **Foglio 0.4.0** app.
2. In **Settings → Agent connections**, turn on **Allow agents to connect**. Access starts with reading only.
3. Turn on **Allow agents to make changes** when you want agents to add or edit content.
4. Use **Copy Codex setup** or **Copy Claude config**. These copy configuration for the app you are currently running; changing your theme or normal app settings is not required.

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

Use `claude mcp list` or `/mcp` in Claude Code to check the connection. Source: [Claude Code MCP documentation](https://code.claude.com/docs/en/mcp).

## Claude Desktop

Merge the JSON copied from Foglio Settings into your existing `mcpServers` object in Claude Desktop's configuration; preserve any other servers. [claude-desktop.json.example](claude-desktop.json.example) shows the structure. Use an absolute executable path, not a literal `~` or `$HOME`, in JSON. Restart Claude Desktop after editing the configuration.

Source: [MCP local-server setup guide](https://modelcontextprotocol.io/docs/develop/connect-local-servers).

## Available tools

| Area | Tools |
| --- | --- |
| Connection | `foglio_status` |
| Tasks | `task_lists`, `task_list_create`, `tasks_list`, `task_get`, `task_create`, `task_update`, `task_move` |
| Notes | `note_folders`, `note_folder_create`, `notes_list`, `note_get`, `note_create`, `note_update`, `note_move` |
| Calendar | `calendar_list`, `calendar_events`, `calendar_event_get`, `calendar_event_create`, `calendar_event_update`, `calendar_event_move` |
| Meeting workflow | `meeting_note_create`, `meeting_task_create` |

Notes and task descriptions accept Markdown, including headings, numbered lists, checklists, code, and tables. Tools read and write the editor's document content; they do not simulate clicks or typing.

Task **lists** such as Priority or Studio are independent from the board **status**: `backlog`, `todo`, `in_progress`, or `done`. `task_move` can change either or both. Completing a task uses the app's existing activity-log preference.

Example requests:

```json
{"name":"task_create","arguments":{"title":"Review the release","description":"- [ ] Check the DMG\n- [ ] Review notes","status":"backlog"}}
{"name":"notes_list","arguments":{"query":"release","limit":20}}
{"name":"calendar_events","arguments":{"start":"2026-10-10T00:00:00+05:30","end":"2026-10-17T00:00:00+05:30"}}
```

For edits and moves, read the item first and pass its exact `revision` back with its `id`. A newer human or agent change produces `conflict`; get the item again and merge your intended edit into its latest content. Task mutations return `resource_busy` while that task's editor is open, protecting its unsaved draft. Names and titles must be non-empty single-line values. List tools accept `limit` (1–200, default 50) and `offset`, and return `next_offset` or null. Notes lists include summaries; use `note_get` for the full document. Trash is excluded.

Calendar queries use the configured source and leave the app's visible week unchanged. Times are ISO 8601 with a timezone; queries are limited to 92 days. For feed/file events outside the visible week, pass a `date` from `calendar_events` to event-get or meeting tools. Feed credentials and imported file paths are not returned.

Calendar writes require the macOS Calendar source, existing full Calendar access granted through the app, and a writable calendar selected by its `calendar_id` from `calendar_list`. This version creates and edits personal, non-recurring timed events. Invited meetings, recurring events, all-day events, and read-only calendars are not editable through the connector. It does not manage attendees or send invitations. URL and `.ics` sources support event reading, meeting notes, and follow-up tasks.

There are no deletion, arbitrary-file, shell-execution, or calendar-account configuration tools. The app's access switches control writes; standard MCP annotations also distinguish read tools from mutations for the agent client.

## Build and verify

The ordinary `scripts/bundle.sh` and `scripts/dmg.sh` include `FoglioMCP` inside the app and sign it along with the bundle. To build and check from the repository root in a restricted runner:

```sh
swift build --disable-sandbox --product FoglioMCP
swift run --disable-sandbox FoglioTests
```

The app test suite checks schemas and lifecycle, real Unix socket delivery, permissions, Markdown round trips, task moves, conflicts, human drafts, disk errors, permission revocation, the actual ICS backend, and a real stdio subprocess calling the live app service. All data fixtures use isolated temporary stores and preferences; tests do not create events in personal calendars.

`FoglioMCP --socket /absolute/path/agent.sock` targets a custom development instance. It does not load a standalone store or automatically start the app. MCP messages are newline-delimited JSON-RPC on stdout; diagnostics use stderr, as required by the [MCP stdio specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports).

If the app is closed or access is off, tool calls report `app_unavailable`. If the app is connected with reading only, edits report `read_only`. A `save_failed` result means disk persistence could not be confirmed; an edit may remain visible in the app's memory, so check storage access before retrying. Transport messages are limited to 4 MiB, and new Markdown bodies are limited to 256 KiB.
