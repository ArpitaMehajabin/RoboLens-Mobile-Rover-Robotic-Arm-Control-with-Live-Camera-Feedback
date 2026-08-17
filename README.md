```markdown
# RoboLens

**Remote Robotic Manipulation System** — a WiFi-controlled robot with a 6-DOF arm and tank chassis, operated from a mobile app over a local network. 
## Features

- 6-DOF robotic arm control with per-joint angle limits
- Tank-style chassis movement
- Live camera feed with real-time obstacle distance overlay
- Safety: obstacle detection, connection watchdog auto-stop, emergency stop
- Optional push notifications for safety events (Firebase)

## Architecture

```
Flutter App  ──WebSocket──▶  Raspberry Pi 4  ──Serial(USB)──▶  Arduino Mega  ──▶  Servos / Motors
                 (8765)         (bridge)                        (firmware)         Ultrasonic x3
                                    │
                            mjpg-streamer (8080)
                                    │
                                 Camera ◀── Logitech C270
```

All communication runs over a local WiFi network (e.g. a phone hotspot) — no internet dependency for control.

## Hardware

| Part | Spec |
|---|---|
| Processing | Raspberry Pi 4 (8GB) |
| Controller | Arduino Mega 2560 |
| Arm | 6-DOF (Hiwonder LeArm AI) |
| Chassis | Metal crawler tank + BTS7960 x2 |
| Camera | Logitech C270 |
| Sensors | 3x ultrasonic |
| Power | 4500mAh 3S 11.1V LiPo + separate powerbank for Pi |

## Setup

**Clone:**
```bash
git clone https://github.com/<your-username>/robolens.git
cd robolens
```

**Arduino:**
Upload `firmware/robolens_firmware.ino` (Arduino IDE, `Servo` library is built-in). Check Serial Monitor (115200 baud) for `ROBOLENS READY`.

**Raspberry Pi:**
```bash
sudo apt update && sudo apt install python3-pip mjpg-streamer -y
pip install websockets pyserial --break-system-packages
```
Set `SERIAL_PORT` in `pi_server.py` to match your device (`ls /dev/tty*`).

Start camera:
```bash
mjpg_streamer -i "input_uvc.so -d /dev/video0 -r 640x480 -f 15" \
              -o "output_http.so -p 8080 -w /usr/share/mjpg-streamer/www"
```

Run server:
```bash
python3 pi_server.py
```

**App:**
```bash
flutter pub get
flutter run
```
Enter the Pi's IP (or `robolens.local`) on the Connect screen.

## Usage
1. Connect phone to the same network as the Pi.
2. Open app → Connect → enter robot IP.
3. Control screen: sliders for arm, D-pad for chassis, STOP for emergency stop.

## Safety
- Forward movement blocks if obstacle is within 30cm.
- Chassis auto-stops if no command received for 2 seconds.
- Arm has fixed reach — reposition chassis if object is out of range.
