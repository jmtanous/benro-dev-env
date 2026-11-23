# Benro development environment

A separate source repository for shared Benro development tooling. Project source,
versioned application packages and MMT integrations live in their own repositories.
Public source: https://github.com/jmtanous/benro-dev-env.
Application packages and MMT releases remain in their existing repositories.

## Workspace

Place this checkout at `~/Work/benro/dev-env`, with applications under the sibling
`projects/` directory. Run `./benro-dev <init|build|test|vm|sdk|provision> <project> [arguments]`
from any directory. `init` creates a separate Git repository, an ARM C starter, build/test
entrypoints and a unique VM port profile. Replace the starter with the new
application and adjust its own build/test commands.
It does not create a remote, claim hardware support or add the project to MMT.

## Shared virtual machine launcher

`./benro-dev vm alpaca-pilot-port start` and
`./benro-dev vm alpaca-pilot-rust start` use scripts/vm.sh through project-local
wrappers. Their benro-project.json profiles declare container name and localhost
SSH/web/API/WebSocket ports. run-vm.py rejects duplicate ports or names across
workspace projects. Wrappers also support BENRO_DEV_ENV for a nonstandard checkout.

VM state and artifacts remain in ignored project-local directories so /project
Docker mounts and qcow2 backing paths remain valid. Do not move those files behind
host-absolute symlinks. Stop a VM before snapshot/restore; restore preserves the
previous disk. Guest network forwarding is restricted to localhost.

## New project workflow

```
./benro-dev init example
./benro-dev sdk example fetch
./benro-dev sdk example prepare
./benro-dev test example
./benro-dev provision example
./benro-dev vm example start
./benro-dev vm example ssh 'uname -m'
./benro-dev vm example stop
```

`fetch` verifies pinned public Debian SDK packages. `prepare` extracts them without
running package installation scripts. The starter compiles for ARM EABI soft-float
and checks GLIBC <= 2.24 before running in QEMU userspace. This is a smoke test,
not application or physical hardware acceptance.

The shared Dockerfile defines the host tool image. Docker and Python 3.12+ are
required on the host. The first SDK/build command builds the tool image if it is
absent; subsequent tool executions are offline. Provisioning creates a fresh
Debian ARM VM from a pinned base image and installs development packages. It
needs network access; subsequent VM startup restricts guest network access and
exposes ports only on localhost. Each project owns its writable disk and fresh
SSH key. Never copy another project's state. Completed bases are not rebuilt
implicitly. Guest Debian/kernel versions differ from the target; applications
must separately validate against the target userspace and hardware.

`BENRO_WORKSPACE` selects a different workspace; `BENRO_DEV_ENV` lets generated
wrappers locate this shared checkout outside the standard sibling layout.

## MMT integration workflow

A new application gets its own source repository and a dedicated integration in
an MMT app release. Compatible later versions only need immutable package releases
and catalog entries. There is no universal project service protocol.

## Local validation

A fresh starter was initialized, compiled against the public SDK (GLIBC 2.4),
run under QEMU, provisioned into a separate ARM VM, booted and accessed over SSH.
It executed its own binary and had no inherited simulator. Five profile/initializer
tests pass, including occupied host ports and refusal to overwrite a project.
The VM shut down cleanly without affecting the existing Python lab.
See VALIDATION.json. Hardware acceptance is outside these checks.

## Publication boundary

Publish source, recipes and tests only. Never add VM images, captured firmware,
SDK archives, device configuration, SSH keys, signing material or build outputs.
Preserve upstream notices for reused recipes. Only the reviewed source, recipes and tests are published.
