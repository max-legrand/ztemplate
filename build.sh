#!/bin/bash
set -e
zig build;
./zig-out/bin/ztemplate $@
