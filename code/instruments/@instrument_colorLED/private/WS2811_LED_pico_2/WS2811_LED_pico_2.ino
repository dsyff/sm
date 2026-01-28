#include <Adafruit_NeoPixel.h>
#include <ctype.h>

// Command set (case-insensitive, leading/trailing whitespace ignored):
// *IDN?            -> "RPI,PICO2,WS2811,1.0\r\n"
// COLOR r,g,b      -> set color, r/g/b 0..255 (spaces/commas allowed)
// OFF              -> set color to 0,0,0
// GET              -> "COLOR r,g,b\r\n"
// HELP             -> brief command list
//
// Memory strategy: fixed-size buffers only, no dynamic allocation in loop().

#define LED_PIN 2
#define LED_COUNT 1
#define WS2811_800KHZ 1  // set to 1 if your WS2811 expects 800 kHz

#if WS2811_800KHZ
  #define LED_KHZ NEO_KHZ800
#else
  #define LED_KHZ NEO_KHZ400
#endif

static Adafruit_NeoPixel strip(LED_COUNT, LED_PIN, NEO_GRB + LED_KHZ);

static char lineBuf[96];
static uint8_t lineIdx = 0;
static bool lineOverflow = false;

static uint8_t curR = 0;
static uint8_t curG = 0;
static uint8_t curB = 0;

static void applyColor(uint8_t r, uint8_t g, uint8_t b) {
  if (r == curR && g == curG && b == curB) {
    return;
  }
  curR = r;
  curG = g;
  curB = b;
  strip.setPixelColor(0, r, g, b);
  strip.show();
}

static void respondErr() {
  Serial.print("ERR\r\n");
}

static void respondOk() {
  Serial.print("OK\r\n");
}

static void processLine(char *line) {
  char *start = line;
  while (*start != '\0' && isspace(static_cast<unsigned char>(*start))) {
    start++;
  }
  char *end = start + strlen(start);
  while (end > start && isspace(static_cast<unsigned char>(end[-1]))) {
    end[-1] = '\0';
    end--;
  }
  if (*start == '\0') {
    return; // empty line
  }

  for (char *p = start; *p != '\0'; ++p) {
    if (*p >= 'a' && *p <= 'z') {
      *p = static_cast<char>(*p - 'a' + 'A');
    }
  }

  if (strcmp(start, "*IDN?") == 0) {
    Serial.print("RPI,PICO2,WS2811,1.0\r\n");
    return;
  }

  if (strcmp(start, "OFF") == 0) {
    applyColor(0, 0, 0);
    respondOk();
    return;
  }

  if (strcmp(start, "GET") == 0) {
    Serial.print("COLOR ");
    Serial.print(curR);
    Serial.print(",");
    Serial.print(curG);
    Serial.print(",");
    Serial.print(curB);
    Serial.print("\r\n");
    return;
  }

  if (strcmp(start, "HELP") == 0) {
    Serial.print("CMDS: *IDN?, COLOR r,g,b, OFF, GET, HELP\r\n");
    return;
  }

  if (strncmp(start, "COLOR", 5) == 0 && (start[5] == '\0' || isspace(static_cast<unsigned char>(start[5])))) {
    char *p = start + 5;
    while (isspace(static_cast<unsigned char>(*p))) {
      p++;
    }
    if (*p == '\0') {
      respondErr();
      return;
    }

    long vals[3];
    for (int i = 0; i < 3; ++i) {
      char *numEnd = nullptr;
      vals[i] = strtol(p, &numEnd, 10);
      if (numEnd == p) {
        respondErr();
        return;
      }
      if (vals[i] < 0 || vals[i] > 255) {
        respondErr();
        return;
      }
      p = numEnd;
      if (i < 2) {
        char *sepStart = p;
        while (*p == ',' || isspace(static_cast<unsigned char>(*p))) {
          p++;
        }
        if (p == sepStart || *p == '\0') {
          respondErr();
          return;
        }
      } else {
        while (isspace(static_cast<unsigned char>(*p))) {
          p++;
        }
        if (*p != '\0') {
          respondErr();
          return;
        }
      }
    }

    applyColor(static_cast<uint8_t>(vals[0]),
               static_cast<uint8_t>(vals[1]),
               static_cast<uint8_t>(vals[2]));
    respondOk();
    return;
  }

  respondErr();
}

void setup() {
  Serial.begin(115200);
  unsigned long start = millis();
  while (!Serial && (millis() - start < 2000)) {
    delay(10);
  }

  strip.begin();
  strip.clear();
  strip.show();
  curR = 0;
  curG = 0;
  curB = 0;
}

void loop() {
  while (Serial.available() > 0) {
    char c = static_cast<char>(Serial.read());
    if (c == '\r') {
      continue;
    }
    if (c == '\n') {
      if (lineOverflow) {
        lineOverflow = false;
        lineIdx = 0;
        respondErr();
      } else if (lineIdx > 0) {
        lineBuf[lineIdx] = '\0';
        processLine(lineBuf);
        lineIdx = 0;
      } else {
        lineIdx = 0;
      }
      continue;
    }

    if (!lineOverflow) {
      if (lineIdx < (sizeof(lineBuf) - 1)) {
        lineBuf[lineIdx++] = c;
      } else {
        lineOverflow = true;
      }
    }
  }
}
