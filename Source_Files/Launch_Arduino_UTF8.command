#!/bin/zsh
set -e

launchctl setenv LANG C.UTF-8
launchctl setenv LC_ALL C.UTF-8

open -a "/Applications/Arduino IDE.app" "/Users/linjingqi/Projects/Ear/Air_Pressure/Source_Files/JingqiBMP581/JingqiBMP581.ino"
