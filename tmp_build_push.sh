#!/bin/bash
set -e
cd /mnt/c/FFApi/my_fastapi_project
TAG='20260606150810'
echo "[$(date +%FT%T)] TAG=$TAG start login"
echo 'BSXX8AsGDU3hdrKDSYTmwvW7giL1wrfcEYOO7OCMW52QWdP6AvmXJQQJ99CFACE1PydEqg7NAAACAZCRBEbY' | sudo docker login zapieappapiacrx.azurecr.io --username zapieappapiacrx --password-stdin
echo "[$(date +%FT%T)] start build"
sudo docker build -t zapieappapiacrx.azurecr.io/zapieapp-api:$TAG -t zapieappapiacrx.azurecr.io/zapieapp-api:latest .
echo "[$(date +%FT%T)] build done"
sudo docker push zapieappapiacrx.azurecr.io/zapieapp-api:$TAG
sudo docker push zapieappapiacrx.azurecr.io/zapieapp-api:latest
echo "[$(date +%FT%T)] push done"
