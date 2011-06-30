#!/bin/bash

echo "Setting permissions, installing pre-reqs"
sudo apt-get install -y screen
sudo chmod 777 /var/run/screen
sudo apt-get install -y sendemail
sudo apt-get install -y libnet-ssleay-perl
sudo apt-get install -y libio-socket-ssl-perl
echo "All done. Be sure to set your settings in start_miner_x";

