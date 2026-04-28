#!/bin/bash

echo "Status,Name,Version,Architecture,Description" > output.csv
dpkg-query -W -f='${db:Status-Status},${Package},${Version},${Architecture},"${Description}"\n' | \
sed ':a;N;$!ba;s/\n / /g' >> output.csv
