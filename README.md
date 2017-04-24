# Sentry-GLib

[Sentry](https://sentry.io/) client for GLib ecosystem

This client is designed to integrate in various aspect of GLib such as GError, logging and more!

## Features

 - all of the core attributes via GObject properties
 - capture `GError`
 - capture logs with `GLogFunc` and `GLogWriterFunc`
 - stacktrace via libunwind
 
## Usage

To create a new client:

```vala
var client = new Sentry.Client ("<dsn>");

client.tags = {"foo=bar"};
```

To capture arbitrary messages:

```vala
client.capture_message ("test", "foo=bar");
```

`GLib.Error`:

```vala
client.capture_error (new IOError.FAILED ("foo"));
```

Logs:

```vala
Log.set_handler (client.capture_log);
```

Structured logs:

```vala
Log.set_writer_func (client.capture_structured_log);
```

Contextual data:

```vala
client
    .with_context (new Sentry.HttpContext ("http://localhost/"))
    .capture_message ("foo");
```

It's perfectly usable via C:

```c
SentryClient client = sentry_client_new ("<dsn>");

gchar** tags = {"foo=bar", NULL};
sentry_capture_message (client, "test", tags);

g_log_set_handler (NULL,
                   G_LOG_LEVEL_WARNING | G_LOG_LEVEL_CRITICAL | G_LOG_LEVEL_ERROR | G_LOG_FATAL,
                   sentry_client_capture_log, 
                   client);

g_log_set_writer_func (sentry_client_capture_structured_log, 
                       client);
```
