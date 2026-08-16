# RoboLens — Mobile Rover & Robotic Arm Control with Live Camera Feedback

RoboLens is a WiFi-controlled remote robotic manipulation system built for hazardous-environment tasks. It combines a mobile tank chassis, a 6-DOF robotic arm, and live video streaming — all controlled from a custom Flutter mobile app over a local network, with push-notification alerts for critical safety events.

## Overview

The system allows an operator to remotely drive a rover, manipulate objects with a 6-DOF arm, and watch a live camera feed, all from a smartphone. Safety is built in at the hardware level with obstacle detection and a connection watchdog, so the robot stops itself if a command stream is interrupted or an obstacle is detected.

## Features

- Real-time chassis control with a 4-directional D-pad and continuous "heartbeat" signaling
- 6-DOF robotic arm control with independent sliders per joint, each respecting its real mechanical range (0°–120° up to 0°–240°)
- Adjustable movement speed (Slow/Medium/Fast) for both chassis and arm
- Live camera streaming (MJPEG) displayed directly in the app
- Obstacle detection — front ultrasonic sensor blocks forward movement within 30cm
- Safety watchdog — chassis auto-stops if no command is received for 2 seconds
- Emergency stop for immediate full stop
- Push notifications (Firebase Cloud Messaging) for obstacle detection, connection loss, and emergency stop, even when the app is closed
- Fully local network operation — no internet/cloud dependency for control, works over a phone hotspot

## System Architecture

Flutter App <---WebSocket---> Raspberry Pi 4 <---Serial---> Arduino Mega 2560, which drives Servos / Motors / Sensors. The Raspberry Pi also serves an MJPEG Camera Stream and sends alerts through Firebase Cloud Messaging to the Phone Notification Tray.

The Flutter app connects to the Raspberry Pi over WebSocket and sends JSON commands. The Pi (pi_server.py) translates these into text commands relayed to the Arduino Mega over serial, which drives the servos/motors and enforces safety logic directly in firmware. A Logitech webcam connected to the Pi is streamed live via mjpg-streamer. The Pi also sends Firebase push notifications for critical events, independent of the WebSocket connection.

## Hardware Components

| Component | Details |
|---|---|
| Processing | Raspberry Pi 4 (8GB) |
| Controller | Arduino Mega 2560 |
| Arm | 6-DOF robotic arm (Hiwonder LeArm AI) |
| Chassis | Metal crawler tank chassis + 2x BTS7960 motor drivers (4-wheel, 2-motor) |
| Camera | Logitech Webcam C270 |
| Sensors | 3x Ultrasonic sensors (Front / Left / Right) |
| Power | 4500mAh 3S 11.1V LiPo (chassis/arm) + power bank (Raspberry Pi) |

## Repository Structure

- lib/ — Flutter app source code
  - main.dart — Splash screen, Connect screen, Firebase init
  - control_screen.dart — Arm sliders, chassis D-pad, camera feed, alerts
  - settings_screen.dart — Connection info, speed presets, alert toggle
- android/, ios/, web/... — Flutter platform folders
- assets/icon/ — App icon and branding assets
- pi_server/
  - pi_server.py — WebSocket server + serial bridge + FCM push
  - robolens-server.service — systemd service for auto-start on boot
- firmware/
  - robolens_firmware.ino — Arduino Mega firmware
- README.md

## Software Stack

- App: Flutter (Dart) — web_socket_channel, flutter_mjpeg, firebase_core, firebase_messaging, shared_preferences
- Server: Python 3 — websockets, pyserial, firebase-admin
- Firmware: Arduino (C++) — Servo.h
- Notifications: Firebase Cloud Messaging (topic-based, no auth/database required)

## Setup & Running

### 1. Arduino
Open firmware/robolens_firmware.ino in the Arduino IDE, select Arduino Mega 2560, and upload.

### 2. Raspberry Pi
Run the following commands:

cd pi_server
python3 -m venv venv
source venv/bin/activate
pip install websockets pyserial firebase-admin

Place your own Firebase service account key here as firebase-service-account.json (not included in this repo), then run:

python3 pi_server.py

To run automatically on boot:

sudo cp robolens-server.service /etc/systemd/system/
sudo systemctl enable robolens-server.service
sudo systemctl start robolens-server.service

### 3. Flutter App
Run the following commands:

flutter pub get
flutter run --release

On first launch, connect the app to the Pi's IP address shown on the Connect screen. The Pi and phone must be on the same local network (e.g. phone hotspot).

### Firebase Setup (for push notifications)
This repo does not include google-services.json or firebase-service-account.json, since these are project-specific credentials.

1. Create a Firebase project and register an Android app with package name com.example.robolens_app.
2. Download google-services.json and place it at android/app/google-services.json.
3. Generate a service account key (Project Settings → Service Accounts) and save it as pi_server/firebase-service-account.json on the Pi.

Without these files, the app and server still function normally — push notifications are simply disabled.

## Safety Design

- Obstacle detection: forward movement blocks automatically under 30cm.
- Connection watchdog: chassis auto-stops if no command arrives for 2 seconds.
- Emergency stop: immediately halts all motor and arm movement.
- Fail-safe Firebase: if Firebase init fails, robot control is unaffected — only notifications are disabled.
