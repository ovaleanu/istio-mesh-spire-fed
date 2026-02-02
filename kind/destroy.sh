#!/bin/bash

set -euo pipefail
trap 'echo "Error on line $LINENO" >&2' ERR

kind delete clusters foo-cluster bar-cluster
