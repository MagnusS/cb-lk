# cb-lk

This repository contains an experimental LinuxKit configuration for running
benchmarks on bare metal with as little noise as possible. The image is
immutable and everything is running directly from memory.

When booted, the image will first check that at least one core is isolated with
the `isolcpus=` boot option and adjust various kernel parameters to avoid
scheduling work on the isolated core. The isolated core is also configured to
run at a fixed clock frequency and power saving is disabled (see
[`bmtune`](https://github.com/MagnusS/bmtune.git) for more details).

A Docker daemon is started and exposed on port 2375. An external client can use
this port to launch containers and run benchmarks. Note that this port is
currently *unprotected* -- outside a lab environment Docker should be
configured to require a TLS certificate.

The image will also start an SSH server that can be used to start benchmarks
outside Docker or investigate issues.

## Running benchmarks

Benchmarks can be run as Docker containers, but have to be pinned to the
isolated core using the `--cpuset-cpus` parameter. To execute an image that's
available on Docker hub (or is already built locally), use:

```
$ docker -H [benchmark node ip] run --cpuset-cpus [isolated core] \
	[image-name] [command]
```

To avoid adding `-H` to every command, the benchmarking server can be added as a context:

```
$ docker context add lk-server tcp://[ip-address]:2375
$ docker context use lk-server
$ docker ps
[...]
```

`stress-ng` can be useful to verify that the server produces stable results.
Here's an example running 1000 CPU tests on core 1. The stress test should take
approximately the same time to run each time it is executed. See also the [stress-ng
man page](http://manpages.ubuntu.com/manpages/bionic/man1/stress-ng.1.html) for more stress tests.

```
$ docker run --cpuset-cpus 1 -it --rm alpine sh -c "apk -U add stress-ng; stress-ng --metrics --cpu 1 --cpu-ops 1000"
[...]
stress-ng: info:  [1] defaulting to a 86400 second (1 day, 0.00 secs) run per stressor
stress-ng: info:  [1] dispatching hogs: 1 cpu
stress-ng: info:  [1] successful run completed in 7.34s
stress-ng: info:  [1] stressor       bogo ops real time  usr time  sys time   bogo ops/s   bogo ops/s
stress-ng: info:  [1]                           (secs)    (secs)    (secs)   (real time) (usr+sys time)
stress-ng: info:  [1] cpu                1000      7.33      7.32      0.00       136.35       136.61
$
```

#### Storage

If you need storage for IO benchmarks Docker can set up a `tmpfs` mount for the
container by including the `--tmpfs` parameter. To add a 3 GB partition in
`/data` use `--tmpfs /data:rw,noexec,nosuid,size=3G`.

#### SSH

It's possible to SSH to the machine. By default, the key that was
available in `~/.ssh/id_rsa.pub` is added to `authorized_hosts` for the `root`
user. `taskset` should then be used to run the benchmark on the isolated CPU
core.


## Building and deploying

Building the image requires [LinuxKit](https://github.com/linuxkit/linuxkit) and [Docker](https://docker.com).

The image can be built with `make` or `linuxkit build [...]`. If built with
`make` the image will be stored in `./build`. 

During build, the SSH key in `~/.ssh/id_rsa.pub` will be added to authenticate
a `root` user. If this is incorrect, update the image configuration to include
the right key or just remove the key reference.

### Running as a VM

The image should ideally run directly on hardware to avoid inconsistent
results, but for testing it can be useful to run it as a VM. LinuxKit provides
a `linuxkit run` command that will attempt to use an available hypervisor to
boot the VM (see LinuxKit docs for more information).

To run as a VM (after a successful `make`):

`linuxkit run ./build/bmtune-docker`

Check the boot output to find the IP acquired by the VM.

### Network booting

The image can be network booted directly on hardware using IPXE. This is
convenient, as LinuxKit provides a `serve` subcommand that can be used to serve
a newly built image from a development machine to a bare metal host over HTTP.
It requires that you have IPXE set up in your network, or that have access to
configure it. This section will briefly cover each step.

To configure IPXE see [this guide](https://ipxe.org/howto/chainloading). I
rebuilt `undionly.ipxe` to include an embedded script that loads the next step
from an HTTP server in a permanent locaction in my network (see "Breaking the
loop with an embedded script"). I configured my network card to use legacy
network boot to avoid having to configure UEFI boot.

With IPXE working, you can create a boot script on the development machine that
will be hosted with the LinuxKit image. For example something like:

```
#!ipxe
dhcp
set base http://192.168.1.123:8080
set name minimal

kernel ${base}/${name}-kernel page_poison=1 ip=dhcp nomodeset ro serial isolcpus=2 nohz_full=2 rcu_nocbs=2 rcu_nocb_poll 
initrd ${base}/${name}-initrd.img
```

Replace `set base` and `set name` with the IP of your dev machine hosting the
image and the name of the LinuxKit image.

You can use `linuxkit serve` to serve both the boot script and the
kernel/initrd over HTTP. It defaults to sharing `./`, so you may have to copy
the boot script to your build directory and run the command from there.

To get IPXE to load your boot script, you can either configure it to point
directly to your machine (e.g. using the embedded script in `undionly.ipxe` or
DHCP) or redirect via a script that's located in a more permanent location.

```
chain http://198.168.1.123:8080/boot.ipxe
```

Replace 192.168.1.123 with the correct dev machine IP and `boot.ipxe` with the
name of the boot script above.

If you're redirecting from a permanent HTTP server, you may may also want to
set up [a custom menu](https://wiki.fogproject.org/wiki/index.php/Advanced_Boot_Menu_Configuration_options#Examples_Basic_Menu).


