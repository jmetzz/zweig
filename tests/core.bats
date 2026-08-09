#!/usr/bin/env bats

# Load the zg script
source "$(dirname "$0")/../modules/loader.sh"

@test "zg help command should work" {
    run zg help
    [ "$status" -eq 0 ]
}
