#!/bin/bash

set -e

#$1 should be passed as an existing directory name
if [ -z $1 ]
then
	echo "missing cmd line param"
	exit 1
fi

if [ ! -d python_files/$1 ]
then
	echo "python_files directory missing"
	exit 1
fi

mkdir -p build/$1
#in case previous run aborted
rm -rf build/$1/*
cp python_files/$1/*.py build/$1/
pip install --target build/$1/ -r python_files/$1/requirements.txt
cd build/$1
zip -r ../../lambda-deployment-pkg-$1.zip .
cd ../../
rm -rf build/$1