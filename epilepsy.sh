#!/bin/bash

# The serialHelper115200 file is my own SerialHelper Utility compiled
# with 115200 baud. Get it from here:
# https://github.com/xythobuz/SerialHelper

DATA_FILE=led_data_file

if [ $# -ne 6 ]; then
    echo "Usage: two times three hex bytes for color"
    echo "$0 r1 g1 b1 r2 g2 b2"
    exit
fi

PORTFILE=`ls /dev/tty.wchusbserial* | head -n 1`
echo "Using $PORTFILE as serial port..."

echo "WARNING: This is toggling the LEDs very fast between your two colors!"
echo "The name epilepsy is no joke. Be careful."
read -p "Press ENTER to continue..."

echo "Opening serial port..."
serialHelper115200 -rw $PORTFILE >/dev/null 2>/dev/null &
TERM_PID=$!
echo "PID is $TERM_PID"

echo "Waiting for Arduino to be ready..."
sleep 3

echo

for i in `seq 1 20`; do

    echo "Preparing data to send..."
    echo -n "xythobuzRGBled" > $DATA_FILE
    for i in {1..156}; do
        echo -n -e "\x$1\x$2\x$3" >> $DATA_FILE
    done

    echo "Sending data..."
    cat $DATA_FILE > $PORTFILE

    echo "Waiting for data to appear..."
    sleep 0.05

    echo

    echo "Preparing data to send..."
    echo -n "xythobuzRGBled" > $DATA_FILE
    for i in {1..156}; do
        echo -n -e "\x$4\x$5\x$6" >> $DATA_FILE
    done

    echo "Sending data..."
    cat $DATA_FILE > $PORTFILE

    echo "Waiting for data to appear..."
    sleep 0.05

    echo
done

echo "Preparing data to send..."
echo -n "xythobuzRGBled" > $DATA_FILE
for i in {1..156}; do
    echo -n -e "\x00\x00\x00" >> $DATA_FILE
done

echo "Sending data..."
cat $DATA_FILE > $PORTFILE

echo "Waiting for data to appear..."
sleep 0.1

echo "Closing serial port..."
kill $TERM_PID

echo "Deleting created data file..."
rm -rf $DATA_FILE

