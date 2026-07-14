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

import netaddr
import netio
import net
import net.http
import net.urllib
import os
import structlog

enum IpVersion {
	both
	ipv4
	ipv6
}

fn setup_server(pref Preferences, rh HTTPRequestHandler, log structlog.StructuredLog) !http.Server {
	mut ip_ver := IpVersion.both
	if pref.ipv4_only {
		ip_ver = .ipv4
	}
	if pref.ipv6_only {
		ip_ver = .ipv6
	}
	addrs := resolve_addrs(pref.listen_addr, ip_ver)!
	socket := new_socket(addrs, ip_ver, pref.backlog)!
	tcp_socket := net.tcp_socket_from_handle_raw(socket.fd)
	listener := net.TcpListener{
		sock: tcp_socket
	}
	on_running := fn [log] (mut s http.Server) {
		log.info().message('Listening on ${s.addr}...').send()
	}
	server := http.Server{
		listener:   listener
		handler:    rh
		on_running: on_running

		show_startup_message: false
	}
	return server
}

fn new_socket(addrs []netio.SocketAddr, ip_ver IpVersion, backlog int) !netio.Socket {
	mut socket := netio.Socket{}
	mut success := false
	for socket_addr in addrs {
		socket = netio.Socket.new(socket_addr.family(), netio.sock_stream, 0) or { continue }
		socket.set_option(netio.sol_socket, netio.so_reuseaddr, 1)!
		if socket_addr.family() != netio.af_unix {
			socket.set_option(netio.ipproto_tcp, netio.tcp_nodelay, 1)!
			$if linux {
				socket.set_option(netio.ipproto_tcp, netio.tcp_quickack, 1)!
			}
		}
		if socket_addr.family() == netio.af_inet6 {
			socket.set_option(netio.ipproto_ipv6, netio.ipv6_v6only, ip_ver == .ipv6)!
		}
		socket.bind(socket_addr) or {
			socket.close() or {}
			continue
		}
		success = true
	}
	if !success {
		return error('no valid address to bind')
	}
	socket.listen(backlog)!
	return socket
}

fn resolve_addrs(raw_addr string, ip_ver IpVersion) ![]netio.SocketAddr {
	mut addr := raw_addr
	mut listen_port := u16(0)

	if os.is_abs_path(addr) {
		return [netio.SocketAddr.new_unix(addr)!]
	}

	host_str, port_str := urllib.split_host_port(addr)

	if port_str != '' {
		listen_port = port_str.u16()
	}

	if listen_port == 0 {
		listen_port = default_listen_port
	}

	if host_str == '' {
		if ip_ver == .ipv4 {
			return [netio.SocketAddr.new_ipv4(default_listen_addr_v4, listen_port)]
		} else {
			return [netio.SocketAddr.new_ipv6(default_listen_addr_v6, listen_port)]
		}
	} else {
		if ip_addr := netaddr.Ipv4Addr.from_string(host_str) {
			return [netio.SocketAddr.new_ipv4(ip_addr.u8_array_fixed(), listen_port)]
		}
		if ip_addr := netaddr.Ipv6Addr.from_string(host_str) {
			return [
				netio.SocketAddr.new_ipv6(ip_addr.u8_array_fixed(), listen_port,
					scope_id: netio.find_network_interface(ip_addr.zone_id or { '' }) or {
						netio.NetworkInterfaceId{}
					}.index
				),
			]
		}
		// If address in not IPv4 or IPv6 string try to resolve it as a domain name...
		addrs := netio.addr_info(
			node:     host_str
			service:  listen_port.str()
			family:   if ip_ver == .ipv4 {
				netio.af_inet
			} else if ip_ver == .ipv6 {
				netio.af_inet6
			} else {
				netio.af_unspec
			}
			socktype: netio.sock_stream
			flags:    netio.ai_addrconfig
		)!
		return addrs.map(fn (elem netio.AddrInfo) netio.SocketAddr {
			return elem.addr
		})
	}
	return []
}
