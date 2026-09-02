/*  This file is part of httest.

	httest is free software: you can redistribute it and/or modify it under the
	terms of the GNU General Public License as published by the Free Software
	Foundation, either version 3 of the License, or (at your option) any later
	version.

	httest is distributed in the hope that it will be useful, but WITHOUT ANY
	WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
	FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License along with
	httest. If not, see <https://www.gnu.org/licenses/>.
*/
module main

const name = 'httest'
const version = $d('version', '0.0.0')

const default_listen_port = u16(9000)
const default_listen_addr_v4 = [4]u8{}
const default_listen_addr_v6 = [16]u8{}

// vfmt off
struct Preferences {
mut:
	help              bool     @[xdoc: 'print this help message and exit.']
	version           bool     @[xdoc: 'print version info and exit.']
	listen_addr       string   @[ignore]
	ipv4_only         bool     @[long: 'ipv4'; xdoc: 'enable IPv4-only mode.']
	ipv6_only         bool     @[long: 'ipv6'; xdoc: 'enable IPv6-only mode.']
	backlog           int = 128      @[xdoc: 'max number of parallel connections on socket, defaults to 128.']
	http2             bool     @[long: 'http2'; xdoc: 'enable HTTP/2.0 with HTTP/1.1 fallback.']
	cert              string   @[xdoc: 'TLS certificate path.']
	cert_key          string   @[xdoc: 'TLS certificate private key path.']
	log_level         string = 'info'   @[xdoc: 'log level, one of: none, fatal, error, warn, info, debug, trace.']
	log_output        string = 'stderr'   @[xdoc: 'where to write logs: stdout, stderr (default) or filepath.']
	log_fields        string   @[short: 'F'; xdoc: 'See Log fields control below.']
	request_id_header string   @[xdoc: 'read request ID from header.']
	respond           int = 200      @[xdoc: 'response HTTP status code, 200 by default.']
	respond_header    []string @[short: 'H'; xdoc: "response header as 'key: value' pair."]
	respond_body      string   @[xdoc: 'response body as string.']
	respond_file      string   @[xdoc: 'read response body from file.']
	response_delay    string   @[xdoc: 'response delay e.g 1s, 3m, 100-900ms, 300 (in milliseconds by default).']
	cgi_script        string   @[xdoc: 'path to CGI script to execute for each request. All static -respond* options is ignored.']
}

const help_header = 'Usage: ${name} [OPTION]... [ADDR]

ADDR may be an IPv4 or IPv6 address, :PORT, domain name or UNIX socket path.'

const help_footer = '
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
    httest -F -default,+id,method,path,status,elapsed'
// vfmt on
