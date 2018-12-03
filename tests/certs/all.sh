#!/bin/sh

CWD=$(PWD)
cd $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

./rootA.sh
./rootB.sh
./serverA.sh
./serverB.sh
./clientA.sh
./clientB.sh

cd $CWD
