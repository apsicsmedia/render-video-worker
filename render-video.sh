#!/bin/bash
set -e
shopt -s nullglob

# === CONFIG ===
DURATION=5
FPS=25
WIDTH=1280
HEIGHT=720
FONT="Roboto"  # fallback to Arial if Roboto isn’t installed

# === PAYLOAD LOAD ===
if [
