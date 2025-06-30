#!/bin/bash

service supervisor start &> /dev/null

/entrypoint.sh
