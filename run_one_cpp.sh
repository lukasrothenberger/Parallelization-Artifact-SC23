#!/bin/bash

# download inputs
wget -N -P inputs https://userweb.cs.txstate.edu/~burtscher/research/ECLgraph/internet.egr --no-check-certificate

# run the test cases
python scripts/run_one_cpp_codes.py 0 16
