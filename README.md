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

| Component | Spec |
|---|---|
| Processing | Raspberry Pi 4 (8GB) |
| Controller | Arduino Mega 2560 |
| Arm | 6-DOF (Hiwonder LeArm AI) |
| Chassis | Metal crawler tank + BTS7960 x2 |
| Camera | Logitech C270 |
| Sensors | 3x ultrasonic (front/left/right) |
| Power | 4500mAh 3S 11.1V LiPo + powerbank (Pi) |

## Repo Structure

```
/app          — Flutter mobile app (control_screen.dart, settings_screen.dart, main.dart)
/pi           — pi_server.py (WebSocket bridge + serial + camera)
/firmware     — robolens_firmware.ino (Arduino Mega)
```

## Setup

### 0. Clone the Repository
```bash
git clone https://github.com/<your-username>/robolens.git
cd robolens
```

### 1. Arduino
Upload `firmware/robolens_firmware.ino` to the Arduino Mega 2560 via Arduino IDE (`Servo` library required, built-in). Confirm `ROBOLENS READY` on Serial Monitor (115200 baud).

### 2. Raspberry Pi
```bash
sudo apt update && sudo apt install python3-pip mjpg-streamer -y
pip install websockets pyserial --break-system-packages
```
Set `SERIAL_PORT` in `pi_server.py` to match your Arduino's device (`ls /dev/tty*`, usually `/dev/ttyACM0` or `ttyACM1`).

Start the camera stream:
```bash
mjpg_streamer -i "input_uvc.so -d /dev/video0 -r 640x480 -f 15" \
              -o "output_http.so -p 8080 -w /usr/share/mjpg-streamer/www"
```

Run the server:
```bash
python3 pi_server.py
```
(Set up both as `systemd` services for auto-start on boot.)

Ensure `avahi-daemon` is running so the app can find the Pi at `robolens.local`.

### 3. Flutter App
```bash
flutter pub get
flutter run
```
On first launch, enter the Pi's IP or `robolens.local` on the Connect screen.

## Usage

1. Power on the robot and connect your phone to the same network as the Pi.
2. Open the app → Connect screen → enter robot IP → Connect.
3. Control screen: drag sliders for the arm, hold D-pad buttons to move the chassis, tap STOP for emergency stop.
4. Settings screen: adjust arm/chassis speed, toggle alerts.

## Safety Notes

- Forward movement auto-blocks if an obstacle is within 30cm.
- Chassis auto-stops if no command is received for 2 seconds (disconnect protection).
- Arm has fixed link lengths — reposition the chassis if an object is out of reach.


```
