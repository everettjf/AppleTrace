# AppleTrace Control Protocol v1

AppleTrace uses the same control model in an embedded, non-jailbroken app and
in the future `appletraced` jailbreak daemon. The protocol controls tracing; it
does not expose shell execution, arbitrary memory access, or arbitrary dylib
loading.

## Transport and authentication

- Embedded mode listens on loopback by default.
- Every HTTP and WebSocket request carries either
  `Authorization: Bearer <token>` or `X-AppleTrace-Token: <token>`.
- The default token is 128 random bits encoded as lowercase hexadecimal.
- LAN binding is opt-in and should be paired with a device-local approval flow
  before it is exposed by a host app.

## HTTP API

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/v1/status` | Agent, capture, hook, and buffer status |
| `POST` | `/api/v1/capture/start` | Enable recording |
| `POST` | `/api/v1/capture/stop` | Disable recording and synchronously flush |
| `POST` | `/api/v1/filters` | Replace class-prefix allow/deny filters |
| `GET` | `/api/v1/artifacts` | List trace fragments |
| `GET` | `/api/v1/artifacts/{name}` | Download one trace fragment |

Filter request example:

```json
{
  "allowClassPrefixes": ["MyApp", "Checkout"],
  "denyClassPrefixes": ["UIKit"]
}
```

Artifact names are restricted to one path component and are resolved only
inside `APTGetTraceDirectory()`.

## WebSocket

`GET /api/v1/stream` with a WebSocket upgrade returns an initial status frame.
Protocol v1 intentionally does not stream every method call: full-rate events
remain in AppleTrace's binary batching path. Later revisions may add bounded
metric updates and binary trace batches without changing the HTTP resources.

## Versioning

Status responses contain `protocolVersion`. Additive fields do not change the
version. Removing fields, changing their meaning, or changing the frame format
requires a new protocol version.
