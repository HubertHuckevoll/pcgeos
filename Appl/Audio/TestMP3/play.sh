#!/bin/bash
play -r 44100 -e signed-integer -b 16 -c 2 -L -t raw $1
