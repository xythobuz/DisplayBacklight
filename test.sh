#!/bin/bash

# The serialHelper115200 file is my own SerialHelper Utility compiled
# with 115200 baud. Get it from here:
# https://github.com/xythobuz/SerialHelper

DATA_FILE=led_data_file

if [ $# -ne 3 ]; then
    echo "Usage: three hex bytes for color"
    echo "$0 rr gg bb"
    exit
fi

PORTFILE=`ls /dev/tty.usbmodem* | head -n 1`
echo "Using $PORTFILE as serial port..."

echo "Preparing data to send..."
echo -n "xythobuzRGBled" > $DATA_FILE
for i in {1..20}; do
    echo -n -e "\x$1\x$2\x$3" >> $DATA_FILE
done

echo "Opening serial port..."
./serialHelper115200 -rw $PORTFILE > serial_output.txt 2>&1 &
TERM_PID=$!
echo "PID is $TERM_PID"

echo "Waiting for Arduino to be ready..."
sleep 3

echo "Sending data..."
cat $DATA_FILE > $PORTFILE

echo "Waiting for data to appear..."
sleep 1

echo "Closing serial port..."
kill $TERM_PID

echo "Deleting created data file..."
rm -rf $DATA_FILE

