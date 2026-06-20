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

import flag
import os

fn main() {
	mut pref, no_matches := flag.to_struct[Preferences](os.args,
		style: .go_flag
		skip:  1
	) or {
		eprintln('E: cmdline parsing error: ${err}')
		exit(1)
	}

	help := flag.to_doc[Preferences](
		style:   .v
		options: flag.DocOptions{
			compact: true
		}
	)!

	if pref.help {
		println(help_header)
		println(help)
		println(help_footer)
		exit(0)
	}

	if pref.version {
		println(version)
		exit(0)
	}

	if no_matches.len == 1 {
		pref.listen_addr = no_matches.first()
	}

	if pref.ipv4_only && pref.ipv6_only {
		eprintln('E: cannot use both -ipv4 and -ipv6')
		exit(1)
	}

	log := setup_logger(pref) or {
		eprintln('E: ${err}')
		exit(1)
	}

	request_handler := setup_request_handler(pref, log) or {
		eprintln('E: ${err}')
		exit(1)
	}

	mut server := setup_server(pref, request_handler, log) or {
		eprintln('E: ${err}')
		exit(1)
	}

	signal_handler := fn [mut server, log] (sig os.Signal) {
		log.info().message('Exiting due signal').add('signal', 'SIG' + sig.str().to_upper_ascii()).send()
		server.stop()
		server.close()
		log.close()
		exit(0)
	}

	os.signal_opt(.int, signal_handler)!
	os.signal_opt(.term, signal_handler)!

	server.listen_and_serve()
}
