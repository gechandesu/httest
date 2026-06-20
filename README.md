# httest

A configurable HTTP test server written in V. Use it to mock backends, inspect
requests, simulate delays and errors, or run CGI scripts during integration testing.

## Build

Install the [V compiler](https://github.com/vlang/v#installing-v-from-source), then run:

```
v .
```

The binary is written to the current directory as `httest`.

## Usage

```bash
httest [OPTION]... [ADDR]
```

`ADDR` is optional. It may be an IPv4/IPv6 address, hostname, or UNIX socket path.
When omitted, the server listens on port 9000 on all interfaces.

### Examples

Return a fixed response:

```
httest -respond 201 -respond-body 'created' -H 'X-Custom: yes'
```

Serve a file as the response body:

```
httest -respond-file ./fixture.json -H 'Content-Type: application/json'
```

Simulate a slow backend:

```
httest -response-delay 2s # constant 2 second delay
httest -response-delay 400-700 # random delay in milliseconds in range
```

Run a CGI script for every request:

```
chmod +x examples/hello.cgi
httest -cgi-script examples/hello.cgi
```

Then:

```
curl 'http://127.0.0.1:9000/test?name=world' -d 'payload'
```

## Synopsis

```
Usage: httest [OPTION]... [ADDR]

ADDR may be an IPv4 or IPv6 IP-address, domain name or UNIX-socket path.

Options:
  -help                     print this help message and exit.
  -version                  print version info and exit.
  -ipv4                     enable IPv4-only mode.
  -ipv6                     enable IPv6-only mode.
  -backlog <int>            max number of parallel connections on socket,
                            defaults to 128.
  -log-level <string>       log level, one of: none, fatal, error, warn,
                            info, debug, trace.
  -log-output <string>      where to write logs: stdout, stderr (default) or
                            filepath.
  -F, -log-fields <string>  See Log fields control below.
  -request-id-header <string>
                            read request ID from header.
  -respond <int>            response HTTP status code, 200 by default.
  -H, -respond-header <string> (allowed multiple times)
                            response header as 'key: value' pair.
  -respond-body <string>    response body as string.
  -respond-file <string>    read response body from file.
  -response-delay <string>  response delay e.g 1s, 3m, 100-900ms, 300 (in
                            milliseconds by default).
  -cgi-script <string>      path to CGI script to execute for each request.

Log fields control:

Below are listed all available log fields in the order they appear in the logs.
Fields marked by * are non-defaults.

  id          auto-generated or passed through -request-id-header request ID.
  method      used HTTP method.
  path        request path.
  status      HTTP response status code as integer.
  recv        size of request body in bytes.
  sent        size of response body in bytes.
  elapsed     request processing time excluding HTTP parsing time.
  remote*     remote address from Remote-Addr header.
  user_agent* request User-Agent header value.
  headers*    all request headers separated by `;`.
  body*       request body text as is.

You can add or remove fields from the HTTP request log using the -log-fields
(-F) option. To add a field, specify its name without a prefix or with a `+`
prefix. For example `-F +body` enables request body logging. You can list
multiple fields separated by commas. `-` prefix disables the log field. There
is also two special values `all` and `default` (for default set). Examples:
  httest -F +headers,body,-id
  httest -F +all
  httest -F -default,+id,method,path,status,elapsed
```

## CGI support

With `-cgi-script`, `httest` runs the given executable once per HTTP request.

The server:

1. Builds a [CGI/1.1](https://datatracker.ietf.org/doc/html/rfc3875) environment from the request (`REQUEST_METHOD`, `QUERY_STRING`, `PATH_INFO`, `CONTENT_*`, `HTTP_*`, and related variables).
2. Writes the request body to the script's standard input.
3. Reads the script's standard output and parses CGI-style headers (if present) followed by the response body.
4. Returns 502 Bad Gateway if the script is missing, exits with a non-zero status, or fails to run.

The script must be executable (typically with a shebang line). Example:

```bash
#!/usr/bin/env python3
import os
print("Content-Type: text/plain")
print()
print(os.environ["REQUEST_METHOD"], os.environ["PATH_INFO"])
```

Supported CGI response headers include:

- `Status: 404 Not Found` — sets the HTTP status code
- `Content-Type: ...` — response content type
- `Location: ...` — redirect (status 302)

If the script prints no header block, the entire output is returned as the body
with status 200.

## Logging

Each processed request is logged as a structured line. Default fields:

`id`, `method`, `path`, `status`, `recv`, `sent`, `elapsed`

Use `-F` to add or remove fields. Enable logging the request body and headers:

```
httest -F +headers,body
```

Enable all available log fields:

```
httest -F +all
```

See Synopsis above or `httest -help` for details.

## License

SPDX identifier: `GPL-3.0-or-later`.
