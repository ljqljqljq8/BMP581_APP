#include <Wire.h>
#include <bluefruit.h>
#include <rtos.h>
#include "DFRobot_BMP58X.h"

const uint8_t BMP581_ADDR = 0x47;
const uint8_t FUEL_GAUGE_ADDR = 0x36;
const uint8_t FUEL_GAUGE_VCELL_REG = 0x02;
const uint8_t FUEL_GAUGE_SOC_REG = 0x04;
const unsigned long SAMPLE_INTERVAL_MS = 50;  // Strict 20 Hz in sampling task
const uint8_t WARMUP_DISCARD_SAMPLES = 5;
const uint8_t MAX_CONSECUTIVE_INVALID_SAMPLES = 3;
const float MIN_VALID_PRESSURE_PA = 30000.0f;
const float MAX_VALID_PRESSURE_PA = 125000.0f;

const bool AUTO_START_STREAM = false;
const bool ENABLE_BLE_OUTPUT = true;

const size_t SAMPLE_BUFFER_DEPTH = 64;
const size_t BLE_MAX_BATCH_SAMPLES = 5;
const size_t BLE_TEXT_PAYLOAD_LIMIT = 20;
const uint32_t BLE_BATCH_FLUSH_TIMEOUT_MS = 250;
const uint32_t STATS_PRINT_INTERVAL_MS = 1000;

struct PressureSample {
  uint32_t tickMs;
  int32_t pressurePa;
};

DFRobot_BMP58X_I2C bmp58x(&Wire, BMP581_ADDR);
BLEUart bleuart;

SemaphoreHandle_t sensorMutex = NULL;

volatile bool isBmpReady = false;
volatile bool isSendingData = false;
volatile bool requestSensorReset = false;
volatile bool requestIICCheck = false;
volatile bool requestBatteryQuery = false;

PressureSample sampleBuffer[SAMPLE_BUFFER_DEPTH];
volatile uint16_t sampleHead = 0;
volatile uint16_t sampleTail = 0;
volatile uint16_t sampleCount = 0;

volatile uint8_t warmupSamplesRemaining = 0;
volatile uint8_t invalidSampleCount = 0;

volatile uint32_t producedSamplesTotal = 0;
volatile uint32_t droppedSamplesTotal = 0;
volatile uint32_t invalidSamplesTotal = 0;
volatile uint32_t sampleTaskRunsTotal = 0;
volatile uint32_t lastSampleTickMs = 0;
volatile uint32_t lastSampleIntervalMs = 0;
volatile uint32_t lastReadDurationUs = 0;
volatile int32_t lastPressurePa = 0;

uint32_t sentPacketsTotal = 0;
uint32_t sentValuesTotal = 0;
uint32_t lastBleDurationUs = 0;
uint32_t lastStatsPrintMs = 0;
uint32_t lastProducedReport = 0;
uint32_t lastDroppedReport = 0;
uint32_t lastInvalidReport = 0;
uint32_t lastPacketsReport = 0;
uint32_t lastValuesReport = 0;

bool isValidPressure(float pressure) {
  if (isnan(pressure)) {
    return false;
  }
  if (pressure < MIN_VALID_PRESSURE_PA || pressure > MAX_VALID_PRESSURE_PA) {
    return false;
  }
  return true;
}

bool streamActive() {
  return AUTO_START_STREAM || (Bluefruit.connected() && isSendingData);
}

void clearSampleBuffer() {
  taskENTER_CRITICAL();
  sampleHead = 0;
  sampleTail = 0;
  sampleCount = 0;
  taskEXIT_CRITICAL();
}

size_t queuedSampleCount() {
  taskENTER_CRITICAL();
  size_t count = sampleCount;
  taskEXIT_CRITICAL();
  return count;
}

void pushSample(const PressureSample &sample) {
  taskENTER_CRITICAL();

  if (sampleCount >= SAMPLE_BUFFER_DEPTH) {
    sampleTail = (sampleTail + 1) % SAMPLE_BUFFER_DEPTH;
    sampleCount--;
    droppedSamplesTotal++;
  }

  sampleBuffer[sampleHead] = sample;
  sampleHead = (sampleHead + 1) % SAMPLE_BUFFER_DEPTH;
  sampleCount++;

  taskEXIT_CRITICAL();
}

size_t peekSamples(PressureSample *dest, size_t maxCount) {
  taskENTER_CRITICAL();

  size_t count = sampleCount;
  if (count > maxCount) {
    count = maxCount;
  }

  for (size_t i = 0; i < count; i++) {
    dest[i] = sampleBuffer[(sampleTail + i) % SAMPLE_BUFFER_DEPTH];
  }

  taskEXIT_CRITICAL();
  return count;
}

void popSamples(size_t count) {
  taskENTER_CRITICAL();

  if (count > sampleCount) {
    count = sampleCount;
  }

  sampleTail = (sampleTail + count) % SAMPLE_BUFFER_DEPTH;
  sampleCount -= count;

  taskEXIT_CRITICAL();
}

void configureSensor() {
  bmp58x.setMeasureMode(bmp58x.eSleep);
  bmp58x.setODR(bmp58x.eOdr20Hz);
  bmp58x.setOSR(bmp58x.eOverSampling8, bmp58x.eOverSampling16);
  bmp58x.configIIR(bmp58x.eFilter1, bmp58x.eFilter3);
  bmp58x.setMeasureMode(bmp58x.eNormal);
}

bool initSensorLocked() {
  unsigned long startMs = millis();
  Serial.println("Starting BMP581 init...");

  if (!bmp58x.begin()) {
    isBmpReady = false;
    Serial.println("BMP581 init failed");
    return false;
  }

  configureSensor();
  delay(60);

  isBmpReady = true;
  warmupSamplesRemaining = WARMUP_DISCARD_SAMPLES;
  invalidSampleCount = 0;
  clearSampleBuffer();
  lastSampleTickMs = 0;

  Serial.print("BMP581 init OK (0x47), took ");
  Serial.print(millis() - startMs);
  Serial.println(" ms");
  return true;
}

bool initSensor() {
  if (sensorMutex == NULL) {
    return initSensorLocked();
  }

  if (xSemaphoreTake(sensorMutex, portMAX_DELAY) != pdTRUE) {
    return false;
  }

  bool ok = initSensorLocked();
  xSemaphoreGive(sensorMutex);
  return ok;
}

void startAdv() {
  Bluefruit.Advertising.stop();
  Bluefruit.ScanResponse.clearData();
  Bluefruit.Advertising.clearData();

  Bluefruit.Advertising.addFlags(BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE);
  Bluefruit.Advertising.addTxPower();
  Bluefruit.Advertising.addService(bleuart);
  Bluefruit.ScanResponse.addName();
  Bluefruit.Advertising.restartOnDisconnect(true);
  Bluefruit.Advertising.setInterval(32, 244);
  Bluefruit.Advertising.setFastTimeout(30);
  Bluefruit.Advertising.start(0);
}

bool readI2CRegister16(uint8_t address, uint8_t reg, uint16_t *value) {
  Wire.beginTransmission(address);
  Wire.write(reg);

  if (Wire.endTransmission(false) != 0) {
    return false;
  }

  if (Wire.requestFrom((int)address, 2) != 2) {
    return false;
  }

  uint8_t msb = Wire.read();
  uint8_t lsb = Wire.read();
  *value = ((uint16_t)msb << 8) | lsb;
  return true;
}

bool readBatteryGauge(float *levelPercent, float *voltageV) {
  uint16_t rawVCell = 0;
  uint16_t rawSOC = 0;

  if (!readI2CRegister16(FUEL_GAUGE_ADDR, FUEL_GAUGE_VCELL_REG, &rawVCell)) {
    return false;
  }

  if (!readI2CRegister16(FUEL_GAUGE_ADDR, FUEL_GAUGE_SOC_REG, &rawSOC)) {
    return false;
  }

  float measuredVoltage = (float)rawVCell * 78.125f / 1000000.0f;
  float measuredSOC = (float)(rawSOC >> 8) + ((float)(rawSOC & 0xFF) / 256.0f);

  if (rawVCell == 0 || rawSOC == 0 || isnan(measuredVoltage) || isnan(measuredSOC)) {
    return false;
  }

  if (measuredVoltage < 2.5f || measuredVoltage > 5.0f) {
    return false;
  }

  if (measuredSOC < 0.0f) {
    measuredSOC = 0.0f;
  } else if (measuredSOC > 100.0f) {
    measuredSOC = 100.0f;
  }

  *levelPercent = measuredSOC;
  *voltageV = measuredVoltage;
  return true;
}

void runI2CCheck() {
  if (xSemaphoreTake(sensorMutex, portMAX_DELAY) != pdTRUE) {
    return;
  }

  Serial.println("I2C scan...");

  uint8_t error = 0;
  int nDevices = 0;
  bool foundBMP581 = false;
  bool foundFuelGauge = false;

  for (uint8_t address = 1; address < 127; address++) {
    Wire.beginTransmission(address);
    error = Wire.endTransmission();

    if (error == 0) {
      char buf[16];
      snprintf(buf, sizeof(buf), "IIC:0x%02X\n", address);
      Serial.print(buf);
      if (Bluefruit.connected() && bleuart.notifyEnabled()) {
        bleuart.write((const uint8_t *)buf, strlen(buf));
      }

      if (address == BMP581_ADDR) {
        foundBMP581 = true;
      }
      if (address == FUEL_GAUGE_ADDR) {
        foundFuelGauge = true;
      }
      nDevices++;
      delay(20);
    }
  }

  if (Bluefruit.connected() && bleuart.notifyEnabled()) {
    if (nDevices == 0) {
      bleuart.write((const uint8_t *)"IIC:NONE\n", 9);
    } else if (foundBMP581) {
      bleuart.write((const uint8_t *)"BMP:OK\n", 7);
    } else {
      bleuart.write((const uint8_t *)"BMP:ERR\n", 8);
    }

    if (foundFuelGauge) {
      bleuart.write((const uint8_t *)"FG:OK\n", 6);
    } else {
      bleuart.write((const uint8_t *)"FG:ERR\n", 7);
    }
  }

  Serial.println(foundBMP581 ? "BMP:OK" : "BMP:ERR");
  Serial.println(foundFuelGauge ? "FG:OK" : "FG:ERR");
  xSemaphoreGive(sensorMutex);
}

void runBatteryQuery() {
  if (xSemaphoreTake(sensorMutex, portMAX_DELAY) != pdTRUE) {
    return;
  }

  float levelPercent = 0.0f;
  float voltageV = 0.0f;
  bool ok = readBatteryGauge(&levelPercent, &voltageV);
  xSemaphoreGive(sensorMutex);

  char buffer[32];

  if (ok) {
    uint16_t percentTenths = (uint16_t)(levelPercent * 10.0f + 0.5f);
    uint32_t millivolts = (uint32_t)(voltageV * 1000.0f + 0.5f);

    snprintf(
      buffer,
      sizeof(buffer),
      "BAT:%u.%u,%lu.%03lu\n",
      percentTenths / 10,
      percentTenths % 10,
      millivolts / 1000,
      millivolts % 1000
    );
  } else {
    snprintf(buffer, sizeof(buffer), "BAT:ERR\n");
  }

  Serial.print(buffer);

  if (Bluefruit.connected() && bleuart.notifyEnabled()) {
    bleuart.write((const uint8_t *)buffer, strlen(buffer));
  }
}

void connect_callback(uint16_t conn_handle) {
  char central_name[32] = {0};
  BLEConnection *connection = Bluefruit.Connection(conn_handle);
  connection->getPeerName(central_name, sizeof(central_name));

  Serial.print("Connected: ");
  Serial.println(central_name);

  isSendingData = AUTO_START_STREAM;
  requestSensorReset = true;
  clearSampleBuffer();
}

void disconnect_callback(uint16_t conn_handle, uint8_t reason) {
  (void)conn_handle;
  (void)reason;

  Serial.println("Disconnected, advertising again...");
  isSendingData = false;
  clearSampleBuffer();
}

void rx_callback(uint16_t conn_handle) {
  (void)conn_handle;

  String cmd;
  while (bleuart.available()) {
    cmd += (char)bleuart.read();
  }
  cmd.trim();
  cmd.toUpperCase();

  if (cmd == "S") {
    clearSampleBuffer();
    isSendingData = true;
    Serial.print("Received S, notifyEnabled=");
    Serial.println(bleuart.notifyEnabled() ? "YES" : "NO");
  } else if (cmd == "P") {
    isSendingData = false;
    clearSampleBuffer();
    Serial.println("Received P (pause)");
  } else if (cmd == "C") {
    requestIICCheck = true;
    Serial.println("Received C (check)");
  } else if (cmd == "BAT") {
    requestBatteryQuery = true;
    Serial.println("Received BAT (battery)");
  }
}

size_t buildPacket(char *packet, size_t packetSize, const PressureSample *samples, size_t availableSamples, size_t *usedSamples) {
  *usedSamples = 0;

  if (availableSamples == 0 || packetSize < 8) {
    return 0;
  }

  size_t maxTry = availableSamples;
  if (maxTry > BLE_MAX_BATCH_SAMPLES) {
    maxTry = BLE_MAX_BATCH_SAMPLES;
  }

  for (size_t count = maxTry; count > 0; count--) {
    int written = snprintf(packet, packetSize, "B:%ld", (long)samples[0].pressurePa);
    if (written <= 0 || (size_t)written >= packetSize) {
      continue;
    }

    bool ok = (size_t)written < BLE_TEXT_PAYLOAD_LIMIT;

    for (size_t i = 1; i < count && ok; i++) {
      long delta = (long)(samples[i].pressurePa - samples[0].pressurePa);
      int needed = snprintf(
        packet + written,
        packetSize - written,
        (i == 1) ? ";%ld" : ",%ld",
        delta
      );

      if (needed <= 0 || (size_t)(written + needed) >= packetSize || (size_t)(written + needed) >= BLE_TEXT_PAYLOAD_LIMIT) {
        ok = false;
        break;
      }

      written += needed;
    }

    if (!ok) {
      continue;
    }

    if ((size_t)(written + 1) >= packetSize || (size_t)(written + 1) > BLE_TEXT_PAYLOAD_LIMIT) {
      continue;
    }

    packet[written++] = '\n';
    packet[written] = '\0';

    *usedSamples = count;
    return (size_t)written;
  }

  return 0;
}

void printStats() {
  unsigned long nowMs = millis();
  if (nowMs - lastStatsPrintMs < STATS_PRINT_INTERVAL_MS) {
    return;
  }

  uint32_t produced = producedSamplesTotal;
  uint32_t dropped = droppedSamplesTotal;
  uint32_t invalid = invalidSamplesTotal;
  uint32_t sampleRuns = sampleTaskRunsTotal;
  uint32_t lastInterval = lastSampleIntervalMs;
  uint32_t lastReadUs = lastReadDurationUs;
  int32_t pressurePa = lastPressurePa;
  uint32_t packets = sentPacketsTotal;
  uint32_t values = sentValuesTotal;
  size_t queued = queuedSampleCount();
  uint32_t producedDelta = produced - lastProducedReport;
  uint32_t droppedDelta = dropped - lastDroppedReport;
  uint32_t invalidDelta = invalid - lastInvalidReport;
  uint32_t packetsDelta = packets - lastPacketsReport;
  uint32_t valuesDelta = values - lastValuesReport;

  if (!streamActive() && queued == 0 &&
      producedDelta == 0 && droppedDelta == 0 &&
      invalidDelta == 0 && packetsDelta == 0 &&
      valuesDelta == 0) {
    return;
  }

  lastStatsPrintMs = nowMs;

  Serial.print("STAT produced=");
  Serial.print(producedDelta);
  Serial.print("/s dropped=");
  Serial.print(droppedDelta);
  Serial.print("/s invalid=");
  Serial.print(invalidDelta);
  Serial.print("/s packets=");
  Serial.print(packetsDelta);
  Serial.print("/s values=");
  Serial.print(valuesDelta);
  Serial.print("/s queued=");
  Serial.print(queued);
  Serial.print(" last_dt=");
  Serial.print(lastInterval);
  Serial.print("ms read_us=");
  Serial.print(lastReadUs);
  Serial.print(" last_ble_us=");
  Serial.print(lastBleDurationUs);
  Serial.print(" pressure=");
  Serial.print(pressurePa);
  Serial.print(" sample_runs=");
  Serial.println(sampleRuns);

  lastProducedReport = produced;
  lastDroppedReport = dropped;
  lastInvalidReport = invalid;
  lastPacketsReport = packets;
  lastValuesReport = values;
}

void sampleTaskLoop() {
  TickType_t lastWake = xTaskGetTickCount();

  for (;;) {
    vTaskDelayUntil(&lastWake, ms2tick(SAMPLE_INTERVAL_MS));
    sampleTaskRunsTotal++;

    if (requestSensorReset) {
      initSensor();
      requestSensorReset = false;
      continue;
    }

    if (!isBmpReady || !streamActive()) {
      continue;
    }

    if (xSemaphoreTake(sensorMutex, ms2tick(2)) != pdTRUE) {
      continue;
    }

    uint32_t tickMs = millis();
    if (lastSampleTickMs != 0) {
      lastSampleIntervalMs = tickMs - lastSampleTickMs;
    }
    lastSampleTickMs = tickMs;

    uint32_t readStartUs = micros();
    float pressure = bmp58x.readPressPa();
    lastReadDurationUs = micros() - readStartUs;
    xSemaphoreGive(sensorMutex);

    if (warmupSamplesRemaining > 0) {
      warmupSamplesRemaining--;
      continue;
    }

    if (!isValidPressure(pressure)) {
      invalidSampleCount++;
      invalidSamplesTotal++;

      if (invalidSampleCount >= MAX_CONSECUTIVE_INVALID_SAMPLES) {
        requestSensorReset = true;
      }
      continue;
    }

    invalidSampleCount = 0;

    PressureSample sample = {tickMs, (int32_t)pressure};
    lastPressurePa = sample.pressurePa;
    producedSamplesTotal++;
    pushSample(sample);
  }
}

void setup() {
  Serial.begin(115200);
  delay(2000);
  Serial.println("System starting...");

  sensorMutex = xSemaphoreCreateMutex();

  pinMode(D4, INPUT_PULLUP);
  pinMode(D5, INPUT_PULLUP);
  Wire.begin();
  Wire.setClock(100000);

  initSensor();

  Bluefruit.configPrphBandwidth(BANDWIDTH_MAX);
  Bluefruit.begin();
  Bluefruit.setTxPower(4);
  Bluefruit.setName("JingQiBMP");
  Bluefruit.Periph.setConnInterval(12, 24);
  Bluefruit.Periph.setConnectCallback(connect_callback);
  Bluefruit.Periph.setDisconnectCallback(disconnect_callback);

  bleuart.begin();
  bleuart.setRxCallback(rx_callback);

  startAdv();
  Serial.println("BLE advertising as JingQiBMP");

  Scheduler.startLoop(sampleTaskLoop, 2048, TASK_PRIO_NORMAL, "sample");
}

void loop() {
  if (requestIICCheck && Bluefruit.connected()) {
    requestIICCheck = false;
    runI2CCheck();
  }

  if (requestBatteryQuery && Bluefruit.connected()) {
    requestBatteryQuery = false;
    runBatteryQuery();
  }

  if (ENABLE_BLE_OUTPUT && streamActive() && bleuart.notifyEnabled()) {
    PressureSample samples[BLE_MAX_BATCH_SAMPLES];
    size_t available = peekSamples(samples, BLE_MAX_BATCH_SAMPLES);

    if (available > 0) {
      uint32_t oldestAgeMs = millis() - samples[0].tickMs;
      if (available < BLE_MAX_BATCH_SAMPLES && oldestAgeMs < BLE_BATCH_FLUSH_TIMEOUT_MS) {
        printStats();
        delay(1);
        return;
      }

      char packet[32];
      size_t usedSamples = 0;
      size_t packetLen = buildPacket(packet, sizeof(packet), samples, available, &usedSamples);

      if (packetLen > 0) {
        unsigned long bleStartUs = micros();
        size_t written = bleuart.write((const uint8_t *)packet, packetLen);
        lastBleDurationUs = micros() - bleStartUs;

        if (written == packetLen) {
          popSamples(usedSamples);
          sentPacketsTotal++;
          sentValuesTotal += usedSamples;
        }
      }
    }
  }

  printStats();
  delay(1);
}
