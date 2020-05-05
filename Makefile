.PHONY: all clean serve

# This is not very robust, but often works on macOS. Set IPV4 in env to override
IPV4 ?= $(shell ifconfig | grep "inet " | grep -Fv 127.0.0.1 | cut -f2 -d" " | head -n1)

all:
	mkdir -p build
	linuxkit build -disable-content-trust -dir build bmtune-docker.yml

clean:
	rm -rf build

serve:
	# Attempt to replace localhost with ipv4 address for ipxe script
	cat boot.ipxe | sed 's/127.0.0.1/${IPV4}/g' > build/boot.ipxe
	# Serve image and boot script as http://${IPV4}:8080/[...]
	cd build && \
		linuxkit serve
