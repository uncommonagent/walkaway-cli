#!/usr/bin/env bash
# Data operator stub (WALKAWAY_DATA_OPERATOR) for the detection / re-pull suites: records the call, decides nothing.
echo "$*" >> "${WALKAWAY_HOME}/operator-calls.log"
