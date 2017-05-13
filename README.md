# DisplayBacklight

DisplayBacklight is an Ambilight-clone made with an Arduino controlled by a macOS machine.

[![DisplayBacklight - macOS Arduino Ambilight](http://img.youtube.com/vi/Sy3Wgt9CKz4/0.jpg)](http://www.youtube.com/watch?v=Sy3Wgt9CKz4 "DisplayBacklight - macOS Arduino Ambilight")

## Hardware

The software currently only supports driving RGB-LEDs with the colors from the edge of a screen, so you have to place an RGB LED strip on the outer edges of your computer monitors. Multiple screens are supported using a single LED strip for all of them.

You need an LED strip with individually addressable LEDs like the popular [WS2812 RGB LED strips](https://www.sparkfun.com/products/12025). The data line is connected to pin 2 of the Arduino. The [Adafruit Neo-Pixel library](https://github.com/adafruit/Adafruit_NeoPixel) is used to control the LEDs.

[![Ambilight Photo](http://xythobuz.de/img/ambilight-1_small.jpg)](http://xythobuz.de/img/ambilight-1.jpg)
[![Ambilight Photo](http://xythobuz.de/img/ambilight-2_small.jpg)](http://xythobuz.de/img/ambilight-2.jpg)

## Protocol

The color data is transmitted using the serial port and the USB-UART converter built into most Arduinos. Communication happens at 115200bps, the LED count is hardcoded in both firmware and host software. First, a magic string, also hardcoded, is sent, followed by 3 bytes containing Red, Green and Blue, for each LED. When the last byte has been received the whole strip is refreshed at once.

## Software

The macOS host software is opening the connection to the serial port, grabbing a screenshot, processing the edges to calculate each LED color and finally sending it to the device.

[![Ambilight Screenshot](http://xythobuz.de/img/ambilight-3.png)](http://xythobuz.de/img/ambilight-3.png)

## License

DisplayBacklight itself is made by Thomas Buck <xythobuz@xythobuz.de> and released under a BSD 2-Clause License. See the accompanying COPYING file.

