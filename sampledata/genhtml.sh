CATAPULT="../catapult/"

python ../merge.py -d ./
${CATAPULT}tracing/bin/trace2html trace.json --output=trace.html && open trace.html