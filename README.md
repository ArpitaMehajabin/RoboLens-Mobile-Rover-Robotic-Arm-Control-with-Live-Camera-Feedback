# RoboLens: Mobile Rover & Robotic Arm Control With Live Camera Feedback

![Flutter](https://img.shields.io/badge/Flutter-blue?logo=flutter&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.x-3776AB?logo=python&logoColor=white)
![Arduino](https://img.shields.io/badge/Arduino-Mega%202560-00979D?logo=arduino&logoColor=white)
![Hardware](https://img.shields.io/badge/Hardware-Raspberry%20Pi%204-C51A4A?logo=raspberrypi&logoColor=white)

This repository contains the mobile app, server, and firmware for **RoboLens** — a WiFi-controlled rover with a 6-DOF robotic arm, built for remote manipulation tasks. The rover is fully operated over a **local network**, with no internet or cloud dependency for core control.

The system uses a **Flutter app** as the control interface, a **Raspberry Pi 4** as a WebSocket bridge and camera server, and an **Arduino Mega 2560** for real-time servo, motor, and sensor control.

## ✨ Key Features

- **Robotic Arm Control:** 6-DOF arm with per-joint angle limits, controlled live via sliders.
- **Chassis Control:** Tank-style 4-wheel drive, controlled via an on-screen D-pad.
- **Live Camera Feed:** Real-time MJPEG stream with a distance overlay from the ultrasonic sensors.
- **Safety Systems:**
  - Obstacle detection — blocks forward movement automatically.
  - Connection watchdog — auto-stops the chassis if the app disconnects.
  - Emergency stop — instantly halts all motion.
- **Push Alerts:** Optional Firebase notifications for safety events, even when the app is closed.

## 🛠️ Hardware Setup

- **Processing:** Raspberry Pi 4 (8GB RAM), WebSocket bridge + camera server.
- **Controller:** Arduino Mega 2560, real-time hardware control.
- **Vision:** Logitech C270 webcam.
- **Chassis:** Metal crawler tank + 2× BTS7960 motor drivers.
- **Robotic Arm:** Hiwonder LeArm AI, 6-DOF.
- **Sensors:** 3× ultrasonic sensors (front / left / right).
- **Power:** 4500mAh 3S 11.1V LiPo (motors + servos) + separate power bank (Raspberry Pi).

## 📦 Project Structure

```text
RoboLens-Mobile-Rover-Robotic-Arm-Control-with-Live-Camera-Feedback/
├── lib/           # Flutter app source (screens, main.dart)
├── assets/        # App icon and image assets
├── android/       # Flutter Android platform files
├── ios/           # Flutter iOS platform files
├── pi_server/     # Raspberry Pi WebSocket bridge + camera server
├── firmware/      # Arduino Mega firmware
└── demo/          # Demo media / screenshots
```

## 🚀 Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/<your-username>/RoboLens-Mobile-Rover-Robotic-Arm-Control-with-Live-Camera-Feedback.git
cd RoboLens-Mobile-Rover-Robotic-Arm-Control-with-Live-Camera-Feedback
```

### 2. Arduino Setup

Open `firmware/robolens_firmware.ino` in the Arduino IDE and upload it to the **Arduino Mega 2560**. The `Servo` library is built in.

After uploading, open the Serial Monitor at **115200 baud** and confirm:

```text
ROBOLENS READY
```

### 3. Raspberry Pi Setup

Install dependencies:

```bash
sudo apt update
sudo apt install python3-pip mjpg-streamer -y
pip install websockets pyserial --break-system-packages
```

Find your Arduino's serial device and set it in `pi_server/pi_server.py`:

```bash
ls /dev/tty*
```
```python
SERIAL_PORT = "/dev/ttyACM0"
```

Start the camera stream (adjust the device/resolution if needed):

```bash
mjpg_streamer -i "input_uvc.so -d /dev/video0 -r 640x480 -f 15" \
              -o "output_http.so -p 8080 -w /usr/share/mjpg-streamer/www"
```

Start the server:

```bash
cd pi_server
python3 pi_server.py
```

### 4. Flutter App Setup

From the repo root:

```bash
flutter pub get
flutter run
```

On first launch, open the **Connect** screen and enter the Raspberry Pi's IP address, or use `robolens.local`.
