#!/bin/bash

path=$1

if [ -z $path ];then
  echo "usage: sh go.sh <path to appletracedata directory>"
  exit
fi

basepath=$(cd `dirname $0`; pwd)
echo $basepath

echo "begin"

echo "executing python merge.py -d $path"
python $basepath/merge.py -d $path

if [ -d "catapult" ]; then
    echo "executing catapult/tracing/bin/trace2html $path/trace.json --output=$path/trace.html"
    python $basepath/catapult/tracing/bin/trace2html $path/trace.json --output=$path/trace.html

    echo "opening $path/trace.html"
    open $path/trace.html
else
    echo "Open chrome://tracing in Chrome Browser, and drop $path/trace.json in."
fi

echo ""
echo "Enjoy :)"
