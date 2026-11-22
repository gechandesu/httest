module main

import encoding.base64
import encoding.protobuf
import json2 as json
import math

const trace_id = [u8(0x4b), 0xf9, 0x2f, 0x35, 0x77, 0xb3, 0x4d, 0xa6, 0xa3, 0xce, 0x92, 0x9d, 0x0e,
	0x0e, 0x47, 0x36]
const server_span_id = [u8(0x00), 0xf0, 0x67, 0xaa, 0x0b, 0xa9, 0x02, 0xb7]
const client_span_id = [u8(0x00), 0xf0, 0x67, 0xaa, 0x0b, 0xa9, 0x02, 0xb8]
const root_parent_id = [u8(0x00), 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77]
const start_nano = u64(1_735_689_600_000_000_000)
const end_nano = u64(1_735_689_600_001_500_000)

fn test_empty_message() {
	got := decode_protobuf([]u8{})!
	assert got.as_map().len == 0
}

fn test_repeated_field_becomes_array() {
	mut packer := protobuf.new_packer()
	packer.write_string(1, 'a')!
	packer.write_string(1, 'b')!
	values := field_(decode_protobuf(packer.bytes())!, '1').as_array()
	assert values.len == 2
	assert values[0].str() == 'a'
	assert values[1].str() == 'b'
}

fn test_truncated_input_is_an_error() {
	if _ := decode_protobuf([u8(0x0a), 0x05, 0x61]) {
		assert false
	} else {
		assert err is protobuf.UnexpectedEofError
	}
}

fn test_group_is_an_error() {
	if _ := decode_protobuf([u8(0x0b)]) {
		assert false
	} else {
		assert err is protobuf.GroupUnsupportedError
	}
}

fn test_fixed64_timestamp_stays_integer() {
	mut packer := protobuf.new_packer()
	packer.write_fixed64(1, start_nano)
	assert field_(decode_protobuf(packer.bytes())!, '1').u64() == start_nano
}

fn test_fixed64_double_stays_float() {
	mut packer := protobuf.new_packer()
	packer.write_double(1, 10.239)
	assert math.abs(field_(decode_protobuf(packer.bytes())!, '1').f64() - 10.239) < 1e-9
}

fn test_negative_varint_is_signed() {
	mut packer := protobuf.new_packer()
	packer.write_int64(1, -2)
	assert field_(decode_protobuf(packer.bytes())!, '1').i64() == -2
}

fn test_empty_length_delimited_is_empty_string() {
	mut packer := protobuf.new_packer()
	packer.write_string(1, '')!
	assert field_(decode_protobuf(packer.bytes())!, '1').str() == ''
}

fn test_otlp_export_trace_service_request() {
	got := decode_protobuf(export_trace_request()!)!
	dump(got.str())
	resource_spans := field_(got, '1')
	assert field_(resource_spans, '3').str() == 'https://opentelemetry.io/schemas/1.21.0'

	service := field_(field_(resource_spans, '1'), '1')
	assert field_(service, '1').str() == 'service.name'
	assert field_(field_(service, '2'), '1').str() == 'checkout'

	scope_spans := field_(resource_spans, '2')
	scope := field_(scope_spans, '1')
	assert field_(scope, '1').str() == 'io.opentelemetry.checkout'
	assert field_(scope, '2').str() == '1.2.0'

	spans := field_(scope_spans, '2').as_array()
	assert spans.len == 2
	assert_span(spans[0], server_span_id, root_parent_id)
	assert_span(spans[1], client_span_id, server_span_id)
}

fn assert_span(span json.Any, span_id []u8, parent []u8) {
	assert field_(span, '1').str() == base64.encode(trace_id)
	assert field_(span, '2').str() == base64.encode(span_id)
	assert field_(span, '4').str() == base64.encode(parent)
	assert field_(span, '5').str() == 'GET /api/checkout'
	assert field_(span, '6').i64() == 2
	assert field_(span, '7').u64() == start_nano
	assert field_(span, '8').u64() == end_nano
	attrs := field_(span, '9').as_array()
	assert attrs.len == 2
	assert field_(attrs[0], '1').str() == 'http.request.method'
	assert field_(field_(attrs[0], '2'), '1').str() == 'GET'
	assert field_(attrs[1], '1').str() == 'com.example.score'
	assert math.abs(field_(field_(attrs[1], '2'), '4').f64() - 10.239) < 1e-9
	assert field_(field_(span, '15'), '3').i64() == 1
	assert field_(span, '16').u64() == 0x101
}

fn field_(obj json.Any, key string) json.Any {
	return obj.as_map()[key] or { panic('missing field_ ${key} in ${obj.json_str()}') }
}

fn export_trace_request() ![]u8 {
	service_name := any_string('checkout')!
	service_attr := key_value('service.name', service_name)!
	mut resource := protobuf.new_packer()
	resource.write_message(1, service_attr)

	mut scope := protobuf.new_packer()
	scope.write_string(1, 'io.opentelemetry.checkout')!
	scope.write_string(2, '1.2.0')!

	server := span(server_span_id, root_parent_id)!
	client := span(client_span_id, server_span_id)!
	mut scope_spans := protobuf.new_packer()
	scope_spans.write_message(1, scope.bytes())
	scope_spans.write_message(2, server)
	scope_spans.write_message(2, client)

	mut resource_spans := protobuf.new_packer()
	resource_spans.write_message(1, resource.bytes())
	resource_spans.write_message(2, scope_spans.bytes())
	resource_spans.write_string(3, 'https://opentelemetry.io/schemas/1.21.0')!

	mut request := protobuf.new_packer()
	request.write_message(1, resource_spans.bytes())
	return request.bytes().clone()
}

fn span(span_id []u8, parent []u8) ![]u8 {
	method := any_string('GET')!
	method_attr := key_value('http.request.method', method)!
	score := any_double(10.239)
	score_attr := key_value('com.example.score', score)!
	mut packer := protobuf.new_packer()
	packer.write_bytes(1, trace_id)
	packer.write_bytes(2, span_id)
	packer.write_bytes(4, parent)
	packer.write_string(5, 'GET /api/checkout')!
	packer.write_enum(6, 2)
	packer.write_fixed64(7, start_nano)
	packer.write_fixed64(8, end_nano)
	packer.write_message(9, method_attr)
	packer.write_message(9, score_attr)
	packer.write_message(15, status_ok())
	packer.write_fixed32(16, u32(0x101))
	return packer.bytes().clone()
}

fn any_string(value string) ![]u8 {
	mut packer := protobuf.new_packer()
	packer.write_string(1, value)!
	return packer.bytes().clone()
}

fn any_double(value f64) []u8 {
	mut packer := protobuf.new_packer()
	packer.write_double(4, value)
	return packer.bytes().clone()
}

fn key_value(key string, value []u8) ![]u8 {
	mut packer := protobuf.new_packer()
	packer.write_string(1, key)!
	packer.write_message(2, value)
	return packer.bytes().clone()
}

fn status_ok() []u8 {
	mut packer := protobuf.new_packer()
	packer.write_enum(3, 1)
	return packer.bytes().clone()
}
