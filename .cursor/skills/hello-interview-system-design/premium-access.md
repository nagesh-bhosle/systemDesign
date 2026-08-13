# Sharing Hello Interview premium content with the agent

The agent cannot see your Chrome profile, cookies, or logged-in tabs. Cursor’s Agent browser (when present) is a **separate** Chromium instance.

## Safe methods (best first)

1. Paste the page or section into chat.
2. Save Markdown/HTML/PDF into the workspace (e.g. `gopuff-demo/hello-interview-notes.md`) and `@` that file. Summarize in your own words when possible; do not commit scraped copyrighted dumps if you can avoid it.
3. Attach screenshots or a PDF.
4. Sign in **inside Cursor’s Agent browser**, then ask the agent to read that tab.
5. `@path/to/notes.md` in chat.

## Do not

- Export Chrome cookies or session tokens into chat or git.
- Assume “I am logged in in Chrome” grants the agent access.

Public Hello Interview problem pages can be fetched directly. Paywalled follow-ups need one of the methods above.
