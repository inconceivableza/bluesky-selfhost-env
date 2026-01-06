#!/bin/bash

# basic check for http response to HEAD command when wget and curl aren't available but bash /dev/tcp is

host=$1
port=${2:-80}
path=${3:-/}

# Open a file descriptor (e.g., 3) for the TCP connection
exec 3<>/dev/tcp/"$host"/"$port"

# Send an HTTP HEAD request (gets headers only, no body)
echo -e "HEAD $path HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n" >&3

# Read the first line of the response to get the status line
read -r response <&3

# Close the file descriptor
exec 3>&-

# Extract and print the status code (the second field in the status line)
response_code=$(echo "$response" | awk '{print $2}')
echo $response_code
[ "$response_code" == 200 ] && exit 0
exit 1

