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
import net.urllib
import os

fn build_cgi_env(req http.Request, script_path string) map[string]string {
	mut env := map[string]string{}

	mut path := req.url
	mut query := ''
	if qidx := path.index('?') {
		query = path[qidx + 1..]
		path = path[..qidx]
	}

	host := req.header.get_custom('host', exact: false) or { 'localhost' }
	host_name, port_str := urllib.split_host_port(host)
	server_port := if port_str != '' { port_str } else { default_listen_port.str() }

	remote_addr := req.header.get_custom('remote-addr', exact: false) or { '' }
	content_type := req.header.get_custom('content-type', exact: false) or { '' }

	env['GATEWAY_INTERFACE'] = 'CGI/1.1'
	env['SERVER_SOFTWARE'] = '${name}/${version}'
	env['SERVER_NAME'] = host_name
	env['SERVER_PROTOCOL'] = 'HTTP/${req.version.str()}'
	env['SERVER_PORT'] = server_port
	env['REQUEST_METHOD'] = req.method.str()
	env['SCRIPT_FILENAME'] = os.real_path(script_path)
	env['SCRIPT_NAME'] = '/${os.base(script_path)}'
	env['PATH_INFO'] = path
	env['PATH_TRANSLATED'] = ''
	env['QUERY_STRING'] = query
	env['REMOTE_ADDR'] = remote_addr
	env['REMOTE_HOST'] = remote_addr
	env['CONTENT_LENGTH'] = req.data.len.str()
	if content_type != '' {
		env['CONTENT_TYPE'] = content_type
	}

	auth := req.header.get_custom('authorization', exact: false) or { '' }
	if auth != '' {
		env['HTTP_AUTHORIZATION'] = auth
		if auth.to_lower().starts_with('basic ') {
			env['AUTH_TYPE'] = 'Basic'
		}
	}

	for header_key in req.header.keys() {
		header_value := req.header.get_custom(header_key, exact: false) or { continue }
		env[header_key.replace('-', '_').to_upper_ascii()] = header_value
	}

	return env
}

fn run_cgi_script(script_path string, req http.Request) !http.Response {
	if !os.exists(script_path) {
		return error('CGI script not found: ${script_path}')
	}

	env := build_cgi_env(req, script_path)
	mut proc := os.new_process(script_path)
	proc.set_environment(env)
	proc.set_work_folder(os.dir(script_path))
	proc.set_redirect_stdio()
	proc.run()

	if req.data.len > 0 {
		proc.stdin_write(req.data)
	}
	if proc.stdio_fd[0] >= 0 {
		os.fd_close(proc.stdio_fd[0])
	}

	output := proc.stdout_slurp()
	stderr := proc.stderr_slurp()
	proc.wait()
	exit_code := proc.code
	proc.close()

	if exit_code != 0 {
		return error('CGI script exited with code ${exit_code}: ${stderr.trim_space_right()}')
	}

	return parse_cgi_output(output)
}

fn parse_cgi_output(output string) !http.Response {
	mut status_code := 200
	mut headers := map[string]string{}
	mut body := output

	mut header_sep := '\r\n\r\n'
	if !output.contains(header_sep) {
		header_sep = '\n\n'
	}

	if sep_idx := output.index(header_sep) {
		header_block := output[..sep_idx]
		body = output[sep_idx + header_sep.len..]

		for line in header_block.split_into_lines() {
			if line == '' {
				continue
			}
			mut key, mut value := line.split_once(':') or { continue }
			key = key.trim_space()
			value = value.trim_space()
			if key == '' || value == '' {
				continue // skip invalid headers
			}
			match key.to_lower() {
				'status' {
					parts := value.split(' ')
					if parts.len == 0 {
						return error('empty status header')
					}
					status_code = parts[0].int()
				}
				'location' {
					headers['Location'] = value
					status_code = 302
				}
				else {
					headers[key] = value
				}
			}
		}
	}

	return http.Response{
		status_code: status_code
		body:        body
		header:      http.new_custom_header_from_map(headers) or { http.Header{} }
	}
}
