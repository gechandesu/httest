# httest

A configurable HTTP test server written in V. Use it to mock backends, inspect
requests, simulate delays and errors, or run CGI scripts during integration testing.

## Build from source

Install the [V compiler](https://github.com/vlang/v#installing-v-from-source), then run:

```
v install
v .
```

The binary is written to the current directory as `httest`. Pre-built binaries
can be found on the [releases](https://github.com/gechandesu/httest/releases/latest) page.

## Docker

httest is available in Docker. The image is OS-less and pretty small, only about ~3 MiB.

Pull the image:

```
docker pull ghcr.io/gechandesu/httest:latest
```

See help:

```
docker run --rm ghcr.io/gechandesu/httest --help
```

Run httest on any address on 8080 port:

```
docker run --rm --network host ghcr.io/gechandesu/httest :8080
```

## Usage

```
httest [OPTION]... [ADDR]
```

`ADDR` is optional. It may be an IPv4/IPv6 address, port, hostname, or UNIX
socket path. When omitted, the server listens on port 9000 on all interfaces.

Run httest on default port on any address:

```
httest
```

Listen on TCP 8080 on any address:

```
httest :8080
```

Listen on `localhost` domain (will be resolved to the IP address) on default port:

```
httest localhost
```

Listen on UNIX domain socket:

```
httest /tmp/test.sock
```

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

## HTTP/2 support

Run cleartext HTTP/2.0 (h2c prior knowledge) with HTTP/1.1 fallback:

```
httest -http2
curl -i --http2-prior-knowledge http://127.0.0.1:9000
```

Run HTTPS with HTTP/2.0 enabled (see also HTTP support below):

```
httest -http2 -cert ./cert.pem -cert-key ./key.pem :9443
curl -i https://127.0.0.1:9443
```

Without `-http2` option, httest serves HTTP/1.1 only. Cleartext HTTP/2 uses
prior knowledge.

## HTTPS support

There is an example of using a self-signed certificate.

1. Create CA certificate:

```
openssl genrsa -out root_ca.key 4096
openssl req -x509 -new -sha256 \
  -key root_ca.key \
  -out root_ca.crt \
  -days 3650 \
  -subj "/C=EN/O=Example/OU=Security/CN=Example Root CA" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:1" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier=hash"
```

2. Create server certificate:

```
openssl genrsa -out server.key 4096
openssl req -new \
  -key server.key \
  -out server.csr \
  -sha256 \
  -subj "/C=EN/O=Example/OU=IT/CN=example.local" \
  -addext "subjectAltName=DNS:example.local,DNS:localhost,IP:127.0.0.1"
cat > server-ext.cnf <<'EOF'
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:example.local, DNS:localhost, IP:127.0.0.1
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF
openssl x509 -req \
  -in server.csr \
  -CA root_ca.crt \
  -CAkey root_ca.key \
  -CAcreateserial \
  -out server.crt \
  -days 825 \
  -sha256 \
  -extfile server-ext.cnf
```
</details>

3. Run httest with server certificate:

```
httest -cert server.crt -cert-key server.key
```

4. Connect to server via HTTPS using CA certificate:

```
curl -i --cacert root_ca.crt https://localhost:9000
```

## Logging

Each processed request is logged as a structured line. Default fields:

`id`, `protocol`, `method`, `path`, `status`, `recv`, `sent`, `elapsed`

Use `-F` to add or remove fields. Enable logging the request body and headers:

```
httest -F +headers,body
```

Enable all available log fields:

```
httest -F +all
```

See Synopsis above or `httest -help` for details.

## Synopsis

```
Usage: httest [OPTION]... [ADDR]

ADDR may be an IPv4 or IPv6 address, :PORT, domain name or UNIX socket path.

Options:
  -help                     print this help message and exit.
  -version                  print version info and exit.
  -ipv4                     enable IPv4-only mode.
  -ipv6                     enable IPv6-only mode.
  -backlog <int>            max number of parallel connections on socket,
                            defaults to 128.
  -http2                    enable HTTP/2.0 with HTTP/1.1 fallback.
  -cert <string>            TLS certificate path.
  -cert-key <string>        TLS certificate private key path.
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
                            All static -respond* options is ignored.

Log fields control:
  Below are listed all available log fields in the order they appear in the
  logs. Fields marked by * are non-defaults.

    id          auto-generated or passed through -request-id-header request ID.
    protocol    used HTTP version.
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
  multiple fields separated by commas. `-` prefix disables the log field.
  There is also two special values `all` and `default` (for default set).
  Examples:

    httest -F +headers,body,-id
    httest -F +all
    httest -F -default,+id,method,path,status,elapsed
```

## License

SPDX identifier: `GPL-3.0-or-later`.
