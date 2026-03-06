# Standard API error response

All API error responses (JSON) across ForgeAI services use this shape:

```json
{
  "error": {
    "code": "string",
    "message": "string",
    "correlation_id": "string"
  }
}
```

## Fields

| Field | Type | Description |
|-------|------|-------------|
| `error.code` | string | Machine-readable identifier. Use for branching in clients. |
| `error.message` | string | Human-readable description of the error. |
| `error.correlation_id` | string | Request trace id. May be empty string when no id was provided. Correlates with logs (e.g. grep by this id across services). |

## Recommended codes by HTTP status

| HTTP status | Recommended code |
|-------------|------------------|
| 400 | `invalid_request` |
| 401 | `unauthorized` |
| 404 | `not_found` |
| 422 | `validation_error` |
| 429 | `rate_limit_exceeded` |
| 500 | `internal_error` |
| 502 | `bad_gateway` |
| 503 | `service_unavailable` |

Services may use these codes when returning the standard shape. Other codes are allowed if needed.

## Breaking change for clients

Previously some services returned a single `error` string. Clients that parse error payloads must now use:

- `error.message` for the human-readable text
- `error.code` for machine-readable handling
- `error.correlation_id` for log correlation

See [docs/contracts/](.) for per-service endpoint contracts; all document that errors follow this schema.
