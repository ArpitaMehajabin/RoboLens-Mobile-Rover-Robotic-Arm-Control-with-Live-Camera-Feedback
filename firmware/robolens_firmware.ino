/*
  RoboLens — Combined Arduino Mega Firmware
  - 6-DOF arm servo control (S1..S6) with PER-JOINT angle limits
  - Non-blocking, speed-adjustable arm movement (SLOW/MEDIUM/FAST)
  - Chassis movement via 2x BTS7960 (4-wheel, 2-motor)
  - 3x Ultrasonic obstacle sensors (front, left, right)
  - Safety watchdog (auto-stop chassis if no command from Pi)
  - Obstacle-based forward-drive block
  - Adjustable chassis speed presets (SLOW / MEDIUM / FAST)
  - Adjustable arm speed presets (SLOW / MEDIUM / FAST)

  Serial: 115200 baud, line-based text commands from Raspberry Pi

  Protocol (unchanged from before, PLUS new ASPD command):
    "S1 90"        -> move joint S1 toward 90 degrees (respects per-joint limit + arm speed)
    "M F"          -> move chassis forward
    "M STOP"       -> stop chassis
    "ESTOP"        -> emergency stop everything
    "SPD SLOW"     -> set CHASSIS speed preset
    "ASPD SLOW"    -> set ARM speed preset (NEW)
*/

#include <Servo.h>

// ================= ARM SERVOS =================
// Index mapping: 0=S1(Gripper) 1=S2(Wrist Roll) 2=S3(Wrist Pitch)
//                3=S4(Elbow)   4=S5(Shoulder)   5=S6(Base)
Servo armServos[6];
const int servoPins[6] = {22, 23, 24, 25, 26, 27};

// Per-joint max angle (min is always 0). Matches the Flutter app sliders.
const int servoMaxAngle[6] = {120, 240, 240, 180, 180, 240};

// Pulse width range used for ALL joints (supports servos rated up to ~270°).
// Angle is linearly mapped to this pulse range based on that joint's max angle.
const int SERVO_MIN_US = 500;
const int SERVO_MAX_US = 2500;

int currentAngle[6] = {90, 90, 90, 90, 90, 90};
int targetAngle[6]  = {90, 90, 90, 90, 90, 90};
unsigned long lastArmStepTime[6] = {0, 0, 0, 0, 0, 0};

// Arm speed presets: milliseconds between each 1-degree step.
// Bigger delay = slower, smoother movement.
unsigned long armStepInterval = 12; // default MEDIUM
const unsigned long ARM_STEP_SLOW   = 25;
const unsigned long ARM_STEP_MEDIUM = 12;
const unsigned long ARM_STEP_FAST   = 4;

// ================= ULTRASONIC =================
#define TRIG_FRONT 28
#define ECHO_FRONT 29
#define TRIG_LEFT  30
#define ECHO_LEFT  31
#define TRIG_RIGHT 32
#define ECHO_RIGHT 33
#define SAFE_DISTANCE 30   // cm — obstacle threshold

long distFront = 999, distLeft = 999, distRight = 999;
unsigned long lastSensorRead = 0;
const unsigned long SENSOR_INTERVAL = 300; // ms

// ================= MOTORS (BTS7960) =================
#define LEFT_RPWM  5
#define LEFT_LPWM  6
#define LEFT_R_EN  7
#define LEFT_L_EN  8
#define RIGHT_RPWM 9
#define RIGHT_LPWM 10
#define RIGHT_R_EN 11
#define RIGHT_L_EN 12

// ================= CHASSIS SPEED PRESETS =================
int driveSpeed = 90;   // default MEDIUM
int turnSpeed  = 100;
const int SPEED_SLOW_DRIVE   = 60,  SPEED_SLOW_TURN   = 70;
const int SPEED_MEDIUM_DRIVE = 90,  SPEED_MEDIUM_TURN = 100;
const int SPEED_FAST_DRIVE   = 140, SPEED_FAST_TURN   = 160;

// ================= STATE =================
String currentDirection = "STOP"; // F, B, L, R, STOP

// ================= SAFETY WATCHDOG =================
unsigned long lastCommandTime = 0;
const unsigned long WATCHDOG_TIMEOUT = 2000; // ms — no command => auto-stop chassis

// ================= SETUP =================
void setup() {
  Serial.begin(115200);

  for (int i = 0; i < 6; i++) {
    armServos[i].attach(servoPins[i], SERVO_MIN_US, SERVO_MAX_US);
    writeArmAngle(i, currentAngle[i]);
  }

  pinMode(TRIG_FRONT, OUTPUT); pinMode(ECHO_FRONT, INPUT);
  pinMode(TRIG_LEFT, OUTPUT);  pinMode(ECHO_LEFT, INPUT);
  pinMode(TRIG_RIGHT, OUTPUT); pinMode(ECHO_RIGHT, INPUT);

  pinMode(LEFT_R_EN, OUTPUT);  digitalWrite(LEFT_R_EN, HIGH);
  pinMode(LEFT_L_EN, OUTPUT);  digitalWrite(LEFT_L_EN, HIGH);
  pinMode(RIGHT_R_EN, OUTPUT); digitalWrite(RIGHT_R_EN, HIGH);
  pinMode(RIGHT_L_EN, OUTPUT); digitalWrite(RIGHT_L_EN, HIGH);
  stopMotors();

  lastCommandTime = millis();
  Serial.println("ROBOLENS READY");
}

// ================= LOOP =================
void loop() {
  // 1) Read incoming command
  if (Serial.available() > 0) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    if (cmd.length() > 0) {
      lastCommandTime = millis(); // any valid command resets watchdog
      processCommand(cmd);
    }
  }

  // 2) Non-blocking arm servo movement (runs every loop, doesn't block sensors/serial)
  updateArmServos();

  // 3) Periodic sensor read + broadcast to Pi
  if (millis() - lastSensorRead > SENSOR_INTERVAL) {
    lastSensorRead = millis();
    distFront = getDistance(TRIG_FRONT, ECHO_FRONT);
    distLeft  = getDistance(TRIG_LEFT,  ECHO_LEFT);
    distRight = getDistance(TRIG_RIGHT, ECHO_RIGHT);

    Serial.print("DIST ");
    Serial.print(distFront); Serial.print(",");
    Serial.print(distLeft);  Serial.print(",");
    Serial.println(distRight);

    // Obstacle safety: block/interrupt forward drive only
    if (currentDirection == "F" && distFront > 0 && distFront < SAFE_DISTANCE) {
      stopMotors();
      currentDirection = "STOP";
      Serial.println("OBSTACLE FRONT");
    }
  }

  // 4) Safety watchdog — no command from Pi => stop chassis
  if (currentDirection != "STOP" && millis() - lastCommandTime > WATCHDOG_TIMEOUT) {
    stopMotors();
    currentDirection = "STOP";
    Serial.println("WATCHDOG STOP");
  }
}

// ================= ARM SERVO MOVEMENT (non-blocking) =================
void writeArmAngle(int idx, int angle) {
  int us = map(angle, 0, servoMaxAngle[idx], SERVO_MIN_US, SERVO_MAX_US);
  us = constrain(us, SERVO_MIN_US, SERVO_MAX_US);
  armServos[idx].writeMicroseconds(us);
}

void updateArmServos() {
  unsigned long now = millis();
  for (int i = 0; i < 6; i++) {
    if (currentAngle[i] == targetAngle[i]) continue;
    if (now - lastArmStepTime[i] < armStepInterval) continue;

    currentAngle[i] += (targetAngle[i] > currentAngle[i]) ? 1 : -1;
    writeArmAngle(i, currentAngle[i]);
    lastArmStepTime[i] = now;
  }
}

// ================= COMMAND PARSER =================
void processCommand(String cmd) {
  cmd.toUpperCase();

  if (cmd == "ESTOP") {
    stopMotors();
    currentDirection = "STOP";
    Serial.println("EMERGENCY STOPPED");
    return;
  }

  if (cmd.startsWith("ASPD ")) {
    String level = cmd.substring(5);
    if (level == "SLOW")        armStepInterval = ARM_STEP_SLOW;
    else if (level == "MEDIUM") armStepInterval = ARM_STEP_MEDIUM;
    else if (level == "FAST")   armStepInterval = ARM_STEP_FAST;
    Serial.print("ARM SPEED SET "); Serial.println(level);
    return;
  }

  if (cmd.startsWith("SPD ")) {
    String level = cmd.substring(4);
    if (level == "SLOW")   { driveSpeed = SPEED_SLOW_DRIVE;   turnSpeed = SPEED_SLOW_TURN;   }
    else if (level == "MEDIUM") { driveSpeed = SPEED_MEDIUM_DRIVE; turnSpeed = SPEED_MEDIUM_TURN; }
    else if (level == "FAST")   { driveSpeed = SPEED_FAST_DRIVE;   turnSpeed = SPEED_FAST_TURN;   }
    Serial.print("SPEED SET "); Serial.println(level);
    return;
  }

  if (cmd.startsWith("M ")) {
    String dir = cmd.substring(2);
    handleMove(dir);
    return;
  }

  // Arm servo command: "S1 45"
  int spaceIndex = cmd.indexOf(' ');
  if (spaceIndex > 0) {
    String servoID = cmd.substring(0, spaceIndex);
    int angle = cmd.substring(spaceIndex + 1).toInt();
    moveServo(servoID, angle);
    return;
  }

  Serial.println("ERROR: unknown command");
}

void moveServo(String id, int angle) {
  int idx = -1;
  if (id == "S1") idx = 0;
  else if (id == "S2") idx = 1;
  else if (id == "S3") idx = 2;
  else if (id == "S4") idx = 3;
  else if (id == "S5") idx = 4;
  else if (id == "S6") idx = 5;

  if (idx == -1) {
    Serial.println("ERROR: invalid servo ID");
    return;
  }

  if (angle < 0 || angle > servoMaxAngle[idx]) {
    Serial.print("ERROR: angle out of range for ");
    Serial.print(id);
    Serial.print(" (max ");
    Serial.print(servoMaxAngle[idx]);
    Serial.println(")");
    return;
  }

  targetAngle[idx] = angle;
  Serial.print(id); Serial.print(" TARGET "); Serial.println(angle);
}

void handleMove(String dir) {
  if (dir == "F") {
    // Obstacle check before allowing forward
    if (distFront > 0 && distFront < SAFE_DISTANCE) {
      Serial.println("OBSTACLE FRONT - BLOCKED");
      stopMotors();
      currentDirection = "STOP";
      return;
    }
    driveForward();
    currentDirection = "F";
  } else if (dir == "B") {
    driveBackward();
    currentDirection = "B";
  } else if (dir == "L") {
    turnLeft();
    currentDirection = "L";
  } else if (dir == "R") {
    turnRight();
    currentDirection = "R";
  } else { // STOP
    stopMotors();
    currentDirection = "STOP";
  }
}

// ================= MOTOR FUNCTIONS =================
void driveForward() {
  analogWrite(LEFT_RPWM, driveSpeed);
  analogWrite(LEFT_LPWM, 0);
  analogWrite(RIGHT_RPWM, driveSpeed - 5);
  analogWrite(RIGHT_LPWM, 0);
}

void driveBackward() {
  analogWrite(LEFT_RPWM, 0);
  analogWrite(LEFT_LPWM, driveSpeed);
  analogWrite(RIGHT_RPWM, 0);
  analogWrite(RIGHT_LPWM, driveSpeed - 5);
}

void turnLeft() {
  analogWrite(LEFT_RPWM, 0);
  analogWrite(LEFT_LPWM, turnSpeed);
  analogWrite(RIGHT_RPWM, turnSpeed);
  analogWrite(RIGHT_LPWM, 0);
}

void turnRight() {
  analogWrite(LEFT_RPWM, turnSpeed);
  analogWrite(LEFT_LPWM, 0);
  analogWrite(RIGHT_RPWM, 0);
  analogWrite(RIGHT_LPWM, turnSpeed);
}

void stopMotors() {
  analogWrite(LEFT_RPWM, 0);
  analogWrite(LEFT_LPWM, 0);
  analogWrite(RIGHT_RPWM, 0);
  analogWrite(RIGHT_LPWM, 0);
}

// ================= SENSOR =================
long getDistance(int trig, int echo) {
  digitalWrite(trig, LOW); delayMicroseconds(2);
  digitalWrite(trig, HIGH); delayMicroseconds(10);
  digitalWrite(trig, LOW);
  long duration = pulseIn(echo, HIGH, 12000);
  if (duration == 0) return 999;
  return duration * 0.034 / 2;
}