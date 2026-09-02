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

import net.http
import os
import rand
import strconv
import structlog
import time

fn setup_request_handler(pref Preferences, log structlog.StructuredLog) !HTTPRequestHandler {
	mut handler := HTTPRequestHandler{
		log: log
	}
	handler.request_id_header = pref.request_id_header
	handler.response_code = pref.respond
	handler.response_body = pref.respond_body
	for header in pref.respond_header {
		// vfmt off
		header_key, header_value := header.split_once(':') or { '', '' }
		// vfmt on
		if header_key != '' {
			handler.response_headers[header_key] = header_value
		}
	}
	if pref.respond_file != '' {
		handler.response_body = os.read_file(pref.respond_file)!
	}
	if pref.cgi_script != '' {
		if !os.is_file(pref.cgi_script) {
			return error('CGI script not found: ${pref.cgi_script}')
		}
		handler.cgi_script = os.real_path(pref.cgi_script)
	}
	if pref.response_delay != '' {
		mut delay_str := pref.response_delay
		mut delay_unit := time.millisecond
		mut delay_lo := i64(0)
		mut delay_hi := i64(0)
		match true {
			delay_str.ends_with('ms') {
				delay_str = delay_str.all_before('ms')
			}
			delay_str.ends_with('s') {
				delay_unit = time.second
				delay_str = delay_str.all_before('s')
			}
			delay_str.ends_with('m') {
				delay_unit = time.minute
				delay_str = delay_str.all_before('m')
			}
			else {}
		}

		// vfmt off
		lo_str, hi_str := delay_str.split_once('-') or { delay_str, '' }
		// vfmt on
		delay_lo = strconv.parse_int(lo_str, 10, 64) or { 0 }
		delay_hi = strconv.parse_int(hi_str, 10, 64) or { 0 }
		handler.response_delay = fn [delay_lo, delay_hi, delay_unit] () time.Duration {
			if delay_lo == 0 && delay_hi == 0 {
				return 0
			}
			if delay_lo >= 0 && delay_hi > 0 {
				return rand.i64_in_range(delay_lo, delay_hi) or { 0 } * delay_unit
			}
			if delay_lo > 0 && delay_hi == 0 {
				return delay_lo * delay_unit
			}
			return 0
		}
	}
	log_fields := pref.log_fields.split(',')
	for log_field in log_fields {
		field_name := log_field.trim_left('+-')
		mut field := LogField.zero()
		if field_name !in ['default', 'all'] {
			field = LogField.from(field_name) or { continue }
		}
		to_del := if log_field.starts_with('-') { true } else { false }
		if to_del {
			if field_name == 'all' {
				handler.log_fields.clear_all()
				continue
			}
			if field_name == 'default' {
				for f in default_log_fields_list {
					handler.log_fields.clear(f)
				}
				continue
			}
			handler.log_fields.clear(field)
		} else {
			if field_name == 'all' {
				handler.log_fields.set_all()
				continue
			}
			if field_name == 'default' {
				handler.log_fields = default_log_fields
				continue
			}
			handler.log_fields.set(field)
		}
	}
	return handler
}

const default_log_fields = LogField.id | .protocol | .method | .path | .status | .recv | .sent | .elapsed

const default_log_fields_list = [
	LogField.id,
	.protocol,
	.method,
	.path,
	.status,
	.recv,
	.sent,
	.elapsed,
]

@[flag]
enum LogField {
	id
	protocol
	method
	path
	status
	recv
	sent
	elapsed
	remote
	user_agent
	headers
	body
}

struct HTTPRequestHandler {
mut:
	log        structlog.StructuredLog
	log_fields LogField = default_log_fields

	request_id_header string
	response_code     int
	response_headers  map[string]string
	response_body     string
	response_delay    ?DelayFn
	cgi_script        string
}

type DelayFn = fn() time.Duration

fn (mut handler HTTPRequestHandler) handle(req http.Request) http.Response {
	started_at := time.now()
	mut request_id := rand.uuid_v4()

	handler.log.debug().add('id', request_id).add('protocol', req.version.str()).message('Start processing request').send()

	if handler.request_id_header != '' {
		handler.log.trace().add('id', request_id).message('Read request ID from header').add('header', handler.request_id_header).send()
		new_id := req.header.get_custom(handler.request_id_header, exact: false) or { request_id }
		handler.log.trace().add('id', request_id).message('New request ID').add('new_id', new_id).send()
		request_id = new_id
	}

	mut response := http.Response{
		body: handler.response_body
		status_code: handler.response_code
		header: http.new_custom_header_from_map(handler.response_headers) or { http.Header{} }
	}

	defer {
		elapsed := time.now() - started_at
		lf := handler.log_fields
		mut f := []structlog.Field{cap: 11}
		// vfmt off
		if lf.has(.id)         { f << structlog.Field{name: 'id', value: request_id} }
		if lf.has(.protocol)   { f << structlog.Field{name: 'protocol', value: req.version.str()} }
		if lf.has(.method)     { f << structlog.Field{name: 'method', value: req.method.str()} }
		if lf.has(.path)       { f << structlog.Field{name: 'path', value: req.url} }
		if lf.has(.status)     { f << structlog.Field{name: 'status', value: response.status_code} }
		if lf.has(.recv)       { f << structlog.Field{name: 'recv', value: req.data.len} }
		if lf.has(.sent)       { f << structlog.Field{name: 'sent', value: response.body.len} }
		if lf.has(.elapsed)    { f << structlog.Field{name: 'elapsed', value: elapsed.str()} }
		if lf.has(.remote)     { f << structlog.Field{name: 'remote', value: req.header.get_custom('remote-addr', exact: false) or { '' } } }
		if lf.has(.user_agent) { f << structlog.Field{name: 'user_agent', value: req.header.get_custom('user-agent', exact: false) or { '' }} }
		if lf.has(.headers)    { f << structlog.Field{name: 'headers', value: req.header.str().split_into_lines().join('; ')} }
		if lf.has(.body)       { f << structlog.Field{name: 'body', value: req.data.trim_space_right()} }
		// vfmt on
		handler.log.info().append(...f).send()
	}

	if handler.cgi_script != '' {
		handler.log.trace().message('Starting CGI-script').add('script', handler.cgi_script).send()
		response = run_cgi_script(handler.cgi_script, req) or {
			handler.log.error().add('id', request_id).message('CGI script failed').add('error', err.msg()).send()
			// vfmt off
			http.Response{
				status_code: 502
				body:        'CGI script error: ${err.msg()}\n'
				header:      http.new_custom_header_from_map({
					'Content-Type': 'text/plain'
				}) or { http.Header{} }
			}
			// vfmt on
		}
	}

	if handler.response_delay != none {
		delay := handler.response_delay()
		handler.log.trace().message('Emulate slow response').add('delay', delay.str()).send()
		time.sleep(delay)
	}

	return response
}
