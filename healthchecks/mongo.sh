#!/bin/bash
set -eo pipefail

db="${MONGO_INITDB_DATABASE:-votes}"

# Force a round trip over the wire (test "external" connectibility) rather than
# trusting that the process has started.
if mongosh --quiet --host 127.0.0.1 --eval "db.getSiblingDB('${db}').runCommand({ ping: 1 }).ok" | grep -q '^1$'; then
	exit 0
fi

exit 1
