#!/bin/sh
sudo amazon-linux-extras install epel
sudo yum install -y nginx
sudo service nginx start