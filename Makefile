BINARY_NAME=fasttrack
VERSION=$(shell cat VERSION)
ZIG_FLAGS=-Doptimize=ReleaseSafe

all: build test

test:
	zig test src/main.zig

lint:
	zig fmt --check .

clean:
	rm -rf zig-out .zig-cache

build:
	 zig build-exe src/main.zig -O ReleaseSmall -fstrip -femit-bin=fasttrack 

bump:
	echo $(VERSION) > VERSION