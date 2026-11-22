BINARY_NAME=fasttrack
VERSION=$(shell cat VERSION)

.PHONY: all test lint clean build bump

all: build test

test:
	zig test src/main.zig

lint:
	zig fmt --check .

clean:
	rm -rf zig-out .zig-cache

build:
	zig build-exe src/main.zig -O ReleaseSmall -fstrip -femit-bin=$(BINARY_NAME)

# Bump version (make bump VERSION=v0.2.3)
bump:
	echo $(VERSION) > VERSION