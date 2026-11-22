module main

import encoding.base64
import encoding.protobuf
import encoding.utf8.validate
import json2 as json
import math

// decode_protobuf decodes arbitrary protobuf wire data into a JSON value.
//
// Object keys are field numbers. A field seen once is that value; a field seen
// more than once is an array, in wire order. A varint is a `u64`, or an `i64`
// when bit 63 is set. `fixed32` and `fixed64` stay integers unless the bits are
// a normal IEEE float with a modest exponent (unbiased `[-40, 40]` and
// `[-100, 100]`). A length-delimited value is an empty string when the payload
// is empty, a string when it is printable UTF-8, a nested object when it parses
// as a message, and standard base64 otherwise. Groups and truncated input are
// errors.
fn decode_protobuf(data []u8) !json.Any {
	mut unpacker := protobuf.new_unpacker(data, protobuf.DecodeOpts{})
	return read_message(mut unpacker)
}

fn read_message(mut unpacker protobuf.Unpacker) !json.Any {
	mut fields := map[string][]json.Any{}
	for !unpacker.eof() {
		number, wire_type := unpacker.read_tag()!
		value := read_field(mut unpacker, number, wire_type)!
		key := number.str()
		mut got := fields[key] or { []json.Any{} }
		got << value
		fields[key] = got
	}
	mut obj := map[string]json.Any{}
	for key, values in fields {
		if values.len == 1 {
			obj[key] = values[0]
		} else {
			obj[key] = json.Any(values)
		}
	}
	return json.Any(obj)
}

fn read_field(mut unpacker protobuf.Unpacker, number int, wire_type protobuf.WireType) !json.Any {
	match wire_type {
		.varint {
			return varint_value(unpacker.read_varint()!)
		}
		.fixed64 {
			return fixed64_value(unpacker.read_fixed64()!)
		}
		.fixed32 {
			return fixed32_value(unpacker.read_fixed32()!)
		}
		.length_delimited {
			return read_length_delimited(mut unpacker)
		}
		.start_group, .end_group {
			unpacker.skip_field(number, wire_type)!
			return error('protobuf: group field ${number} is not supported')
		}
	}
}

fn read_length_delimited(mut unpacker protobuf.Unpacker) !json.Any {
	at := unpacker.offset()
	payload := unpacker.read_len_delimited()!
	if payload.len == 0 {
		return ''
	}
	if is_text(payload) {
		return payload.bytestr()
	}
	if looks_like_message(payload) {
		unpacker.seek(at)
		mut sub := unpacker.sub()!
		sub.enter()!
		return read_message(mut sub)
	}
	return base64.encode(payload)
}

// is_text reports whether `data` can be shown as a JSON string: valid UTF-8,
// with no NUL, DEL, or other control byte besides tab, LF, and CR.
fn is_text(data []u8) bool {
	if !validate.utf8_data(data.data, data.len) {
		return false
	}
	for b in data {
		if b < 0x20 && b != 0x09 && b != 0x0a && b != 0x0d {
			return false
		}
		if b == 0x7f {
			return false
		}
	}
	return true
}

// looks_like_message reports whether `data` is one complete protobuf message.
// A group or a truncated field makes it not a message, so the caller can keep
// the bytes as base64 instead.
fn looks_like_message(data []u8) bool {
	mut unpacker := protobuf.new_unpacker(data, protobuf.DecodeOpts{})
	mut count := 0
	for !unpacker.eof() {
		number, wire_type := unpacker.read_tag() or { return false }
		unpacker.skip_field(number, wire_type) or { return false }
		count++
	}
	return count > 0
}

fn varint_value(value u64) json.Any {
	if value & (u64(1) << 63) != 0 {
		return i64(value)
	}
	return value
}

// fixed64_value keeps a nanosecond timestamp as an integer. A normal double
// such as an OTLP attribute has its exponent near zero; a fixed64 counter does not.
fn fixed64_value(bits u64) json.Any {
	exp := int((bits >> 52) & 0x7ff)
	if exp != 0 && exp != 0x7ff {
		unbiased := exp - 1023
		if unbiased >= -100 && unbiased <= 100 {
			return math.f64_from_bits(bits)
		}
	}
	return bits
}

// fixed32_value is fixed64_value for 32-bit fields. Span flags are a small
// integer whose exponent is zero, so they stay integers.
fn fixed32_value(bits u32) json.Any {
	exp := int((bits >> 23) & 0xff)
	if exp != 0 && exp != 0xff {
		unbiased := exp - 127
		if unbiased >= -40 && unbiased <= 40 {
			return math.f32_from_bits(bits)
		}
	}
	return bits
}
