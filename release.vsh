#!/usr/bin/env v

import build
import os
import releasekit as rk

const docker_image = os.getenv_opt('DOCKER_IMAGE') or { 'httest-builder' }
const docker_file = 'Dockerfile.cross'

const manifest = rk.manifest()
const version = if envver := os.getenv_opt('VERSION') { envver } else { manifest.version }

const common = rk.Build{
	name:    manifest.name
	version: version
	vflags:  ['-prod', '-d', 'version=' + version]
	cflags:  ['-static', '-s']
}

const targets = {
	'linux/amd64':   rk.Build{
		...common
		os:   'linux'
		arch: 'amd64'
		cc:   'x86_64-linux-gnu-gcc'
	}
	'linux/arm64':   rk.Build{
		...common
		os:   'linux'
		arch: 'arm64'
		cc:   'aarch64-linux-gnu-gcc'
	}
	'linux/arm32':   rk.Build{
		...common
		os:   'linux'
		arch: 'arm32'
		cc:   'arm-linux-gnueabihf-gcc'
	}
	'linux/riscv64': rk.Build{
		...common
		os:   'linux'
		arch: 'riscv64'
		cc:   'riscv64-linux-gnu-gcc'
	}
	'windows/amd64': rk.Build{
		...common
		os:   'windows'
		arch: 'amd64'
		cc:   'x86_64-w64-mingw32-gcc'
	}
}

mut ctx := build.context(default: 'all')

ctx.task(
	name: 'docker-image'
	help: 'Build Docker image with cross-compilation environment'
	run:  || rk.run_or_fail('docker', 'build', '-t', docker_image + ':latest', '.', '-f',
		docker_file)!
)

for target_name, target in targets {
	ctx.task(
		name: target_name
		help: 'Build app for ${target_name.to_upper_ascii()}'
		run:  fn [target] (_ build.Task) ! {
			mut args := ['run', '--rm', '-v', '.:/workspace', '-w', '/workspace']
			args << docker_image
			args << 'v'
			args << target.build_args()
			rk.run_or_fail('docker', ...args)!
			checksum := rk.checksum(target.artifact_name(), .sha256)!
			os.write_file(target.artifact_name() + '.sha256', checksum)!
		}
	)
}

ctx.task(
	name: 'all'
	help: 'Build app for all targets'
	run:  || true

	depends: targets.keys()
)

ctx.run()
