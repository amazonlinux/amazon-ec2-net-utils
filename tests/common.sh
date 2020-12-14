#!/bin/bash

if [ -z "$PARAMS" ]; then
    echo "Provide a test configuration file path in the PARAMS variable" >&2
    exit 1
fi

if [ ! -f "$PARAMS" ]; then
    echo "Parameter file $PARAMS does not exit." >&2
    exit 1
fi

. "$PARAMS"
