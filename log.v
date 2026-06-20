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

import os
import io
import structlog
import term

fn setup_logger(pref Preferences) !structlog.StructuredLog {
	mut log_colors := true
	log_output := match pref.log_output {
		'stdout' {
			log_colors = term.can_show_color_on_stdout()
			io.Writer(os.stdout())
		}
		'stderr' {
			log_colors = term.can_show_color_on_stderr()
			io.Writer(os.stderr())
		}
		else {
			log_colors = false
			file := os.open_file(pref.log_output, 'a+') or {
				eprintln('E: could not open log file ${pref.log_output}: ${err}')
				exit(1)
			}
			io.Writer(file)
		}
	}

	return structlog.new(
		level:   structlog.Level.from(pref.log_level)!
		handler: structlog.TextHandler{
			color:  log_colors
			writer: log_output
		}
	)
}
