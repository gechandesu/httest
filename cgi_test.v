module main

fn test_cgi_output_parse_status() {
	r := parse_cgi_output('Status: 201\n\nHello!')!
	assert r.status_code == 201
}

fn test_cgi_output_parse_location() {
	r := parse_cgi_output('Location: /path\n\nHello!')!
	assert r.status_code == 302
	assert r.header.get(.location)? == '/path'
}

fn test_cgi_output_parse_custom_header() {
	r := parse_cgi_output('Some-Header: Zz\n\nHello!')!
	assert r.header.get_custom('Some-Header')? == 'Zz'
}

fn test_cgi_output_parse_custom_header_invalid() {
	r := parse_cgi_output('Some-Header:\n\nHello!')!
	assert r.header.get_custom('Some-Header') == none
}
