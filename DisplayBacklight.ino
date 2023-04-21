/*
 * RGB LED UART controller
 * 
 * This simple sketch controls an RGB LED strand via data received over UART.
 * The protocol works as follows:
 * 
 * A single 'frame' that can be displayed, on our N LED strand, is defined as:
 *     uint8_t data[N * 3] = { r0, g0, b0, r1, g1, b1, r2, g2, b2, ... };
 * With consecutive 24-bit RGB pixels.
 * This is simply transferred, as is, from the PC to the Arduino. To distinguish
 * between start and end of different frames, a magic string is used, defined below.
 * Hopefully it won't appear in the data stream... :)
 */

#include <FastLED.h>

#ifdef __AVR__
  #include <avr/power.h>
#endif

#define DEBUG

#ifdef DEBUG
#define debugPrint(x) Serial.print(x)
#define debugPrintln(x) Serial.println(x)
#else
#define debugPrint(x)
#define debugPrintln(x)
#endif

#define LED_PIN 13
#define LED_COUNT 20
#define BAUDRATE 115200
#define MAGIC "xythobuzRGBled"

// Optional auto-turn-off after no data received
//#define TURN_OFF_TIMEOUT 60000l // in ms

CRGB leds[LED_COUNT];

void setup() {
    Serial.begin(BAUDRATE);
    FastLED.addLeds<WS2812B, LED_PIN, RBG>(leds, LED_COUNT);
    FastLED.show(); // Initialize all pixels to 'off'

    debugPrintln("RGB LED controller ready!");
    debugPrint("Config: ");
    debugPrint(LED_COUNT);
    debugPrintln(" LEDs...");
    debugPrint("Magic-Word: \"");
    debugPrint(MAGIC);
    debugPrintln("\"");

    // Blink LED as init message
    leds[0] = CRGB(32, 32, 32);
    FastLED.show();
    delay(100);
    leds[0] = CRGB(0, 0, 0);
    FastLED.show();
}

#define WAIT_FOR_START 0
#define RECEIVING_START 1
#define RECEIVING_DATA 2

uint8_t state = WAIT_FOR_START;
uint8_t startPos = 0;
uint16_t dataPos = 0;
uint8_t frame[LED_COUNT * 3];

#ifdef TURN_OFF_TIMEOUT
unsigned long lastTime = millis();
#endif

static void setNewFrame() {
  for (uint16_t i = 0; i < LED_COUNT; i++) {
    leds[i] = CRGB(frame[i * 3], frame[(i * 3) + 1], frame[(i * 3) + 2]);
  }
  FastLED.show();
}

void loop() {
  if (!Serial.available()) {
#ifdef TURN_OFF_TIMEOUT
    if ((millis() - lastTime) >= TURN_OFF_TIMEOUT) {
      for (int i = 0; i < (LED_COUNT * 3); i++) {
        frame[i] = 0;
      }
      setNewFrame();
    }
#endif
    return;
  }

#ifdef TURN_OFF_TIMEOUT
  lastTime = millis();
#endif

  uint8_t c;
  Serial.readBytes(&c, 1);
  if (state == WAIT_FOR_START) {
    if (c == MAGIC[0]) {
      state = RECEIVING_START;
      startPos = 1;
      debugPrintln("f");
    } else {
      debugPrintln("");
    }
  } else if (state == RECEIVING_START) {
    if (startPos < strlen(MAGIC)) {
      if (c == MAGIC[startPos]) {
        startPos++;
        debugPrintln("g");
        if (startPos >= strlen(MAGIC)) {
          state = RECEIVING_DATA;
          dataPos = 0;
          debugPrintln("w");
        }
      } else {
        state = WAIT_FOR_START;
        debugPrintln("x");
      }
    } else {
      // Should not happen
      state = RECEIVING_START;
      debugPrintln("s");
    }
  } else if (state == RECEIVING_DATA) {
    frame[dataPos++] = c;
    if (dataPos >= (LED_COUNT * 3)) {
      debugPrintln("d");
      setNewFrame();
      state = WAIT_FOR_START;
    }
  }
}
