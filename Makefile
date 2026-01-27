BINARY_NAME=fasttrack
VERSION=$(shell cat VERSION)
ZIG_FLAGS=-Doptimize=ReleaseSafe

test:
	zig test src/main.zig

lint:
	zig fmt --check .

clean:
	rm -rf zig-out .zig-cache

