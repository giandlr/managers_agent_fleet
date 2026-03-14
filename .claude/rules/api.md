---
globs: ["backend/routes/**", "backend/api/**", "supabase/functions/**"]
---

## Response Envelope

Wrap API responses in `{"status": "ok|error", "data": ..., "meta": {"request_id": "..."}}`. Paginated responses add `"pagination": {"cursor": "...", "has_more": bool, "total": int}` to meta.

## Input Validation

- Validate request bodies with Pydantic models
- Add type annotations with constraints (gt=0, max_length, regex) to path/query params
- Validate MIME type and size for file uploads before processing
- Derive user identity from JWT — never trust client-supplied IDs

## Pagination

- Cursor-based pagination for list endpoints. Default: 20, max: 100.
- Return `has_more` and `cursor` in pagination meta.
- Sort by `created_at` descending unless specified otherwise.

## HTTP Status Codes

200 read/update, 201 creation (+Location header), 204 deletion, 400 validation, 401 unauthenticated, 403 unauthorized, 404 not found (also for "no access" — prevent enumeration), 409 conflict, 422 semantic error, 429 rate limited (+Retry-After), 500 internal (generic message only).

## Error Handling

- Wrap route handlers with FastAPI exception handlers
- Generate correlation ID (uuid4) at middleware level, attach to logs and responses
- Log full exception server-side with structured logging
- Return only correlation ID + generic message to client

## Rate Limiting

- Apply at middleware level with `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` headers
- Stricter limits on auth endpoints (login, register, reset)
