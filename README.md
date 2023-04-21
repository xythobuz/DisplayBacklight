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

## Configuration

At first you must know LED, that you LED strip and Arduino work properly together. If that's confirmed you can step further.
Configure `DisplayBacklight.ino`:

- set your `LED_PIN 2`
- and your LED count `# define LED_COUNT 156`
- change your Chipset in `FastLED.addLeds<WS2812B, LED_PIN, RBG>(leds, LED_COUNT);` Your models can be found here: <https://github.com/FastLED/FastLED/#supported-led-chipsets>
- If you use RGBW-Leds you have to adpot your code a bit. But that's quite easy: <https://github.com/sosiskus/FastLED-with-RGBW-leds>

### Test your Arduino

There is a script added to test the setup between Mac and Arduino:
Run `./serialHelper115200 FF 00 00` which should be red `00 FF 00` should be green and `00 00 FF` should be blue.

### Comfigure and Compile MacOS app

You have to setup a few parameters for the MacOS app:

- Screen Sizes
- Your alignment and amount of LEDs
- you will find everything well documented it in the `AppDelegate`

Depending on your type of Arduino you may have to change the `/dev/cu.usbmodem********` in the `AppDelegate` file.

MacOS App set:

- `LED_COUNT` sum of your LEDs (must correspond in Arduino)
- `struct DisplayAssignment displays` which monitors you are using
- `RETINA_DIVIDER` if your RETINA_DIVIDER is not set correclty nothing will be output.(HowTo in Debug section)
- `struct LEDStrand strands[]`
- `DISPLAY_DELAY`
- `AVERAGE_PIXEL_SKIP`

## Debug

To debug the MacOS app, there are different flags to enable:
enable `DEBUG_TEXT` or `DEBUG_DATA`
Enable `DEBUG_SIZES` to compare if your Screencapture size matches the screensize. Retina displays count pixel differently. it could be 2 or 3 times higher than the screenpixel. Adjust via `RETINA_DIVIDER`

### No output

Only if you had compared Arduino is working and you've setup correctly your AppDelegate you can
enable `DEBUG_SIZES` to save the screenshots in `~/Documents` folder. `CMD+i` for screensize.

## License

DisplayBacklight itself is made by Thomas Buck <xythobuz@xythobuz.de> and released under a BSD 2-Clause License. See the accompanying COPYING file.
