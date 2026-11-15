# AI search prototype (macOS)

Catalog has separate **Search** and **AI search** modes. Describe a mood, reference
movie, runtime, language, or year; follow up in the same conversation. Suggestions
open real movie details and use the existing playback and playlist flows. iOS and
ordinary search are unchanged.

## Configuration

Add `GROQ_API_KEY` to `services/streaming/.env` or the backend's secret environment,
then restart the service. Keep the key on the server, never in an xcconfig, app,
GitHub commit, or client request. No new npm dependency is required.

The Mac app uses `AI_SEARCH_SERVICE_URL`, which defaults to `PLAYBACK_SERVICE_URL`.
For a local prototype, override only the former in `apps/macos/Config/Local.xcconfig`:

```xcconfig
AI_SEARCH_SERVICE_URL = http:/$()/127.0.0.1:8791
```

Run the backend locally with `PORT=8791 HOST=127.0.0.1 npm start`. Loopback-only
development follows the existing service's local authentication policy. Public
hosting requires the existing Firebase Admin setup and verifies Firebase ID tokens
for `POST /v1/ai/search`. Installing the app alone does not deploy the new endpoint
to OCI; deploy this backend version and configure its key before wider testing.

## Retrieval and limits

The only model is Groq-hosted `openai/gpt-oss-20b`. One request interprets intent;
bounded YTS lookups fetch candidates; a second request ranks those candidates.
Clarification uses one model request. Returned IDs must exist in the retrieved
catalogue, and runtime/year/language/genre constraints are checked in code.
Previous result IDs are resolved again to support references such as “the second
one.” Posters, movie URLs and playback identifiers come from YTS, never the model.

This is bounded retrieval, not a semantic index of every catalogue title. It can
miss suitable films. Mood matching and generated reasons can be imperfect; genre
exclusions are tags, not guarantees about violence or other content. No-match,
missing configuration, provider failures and free-tier throttling have explicit
UI states instead of invented recommendations or an alternate provider.

Use a Groq **Free** account. The app cannot control provider billing/account settings.
There is no model/provider fallback. Additional in-memory admission limits are 30
turns per UTC day across the process, 10 per authenticated user, five seconds between
a user's turns, and two active searches. These intentionally conservative prototype
limits reset on server restart and are not a persistent billing control. Groq can
throttle sooner. Provider bodies are bounded to 2 MiB; catalogue caching is limited
to 60 entries / 16 MiB with a one-hour TTL. There is no embedding database or local LLM.

## Privacy and local state

Only the last eight conversation messages, numbered previous suggestions, and
retrieved movie metadata go to Groq. Firebase credentials and user IDs do not.
“Hide watched” sends up to 500 completed movie IDs to Mirror's backend for exclusion;
that ID list is not included in model prompts. Watch history itself is not uploaded
to Groq. Suggestions, messages, and generated explanations are untrusted data.

The last 20 messages are saved locally per account/profile under
`Application Support/MirrorAIChats`, with hashed filenames, owner-only permissions
and backup exclusion. They are not saved in Firestore. New chat clears that local
conversation. Chat files are not encrypted; normal Mac account access applies.
Cancellation/profile changes discard late responses, and retry preserves the prompt.

## Validation

`npm test` includes deterministic provider/catalogue fixtures covering grounded IDs,
constraints, cache reuse, quotas, missing keys, malformed input and provider throttling.
`AISearchTests` covers account/profile chat persistence, retry, late cancellation, and
authenticated HTTP/error handling. Neither suite requires a real Groq key. Live testing
should be limited to a few turns to conserve the free quota.
