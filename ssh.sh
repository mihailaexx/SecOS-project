#!/bin/bash
# Reset ssh keys for project machines

ssh-keygen -f '/home/user/.ssh/known_hosts' -R '192.168.56.10' && ssh-keygen -f '/home/user/.ssh/known_hosts' -R '192.168.56.11' && ssh-keygen -f \
   '/home/user/.ssh/known_hosts' -R '192.168.56.12' && ssh-keygen -f '/home/user/.ssh/known_hosts' -R '192.168.56.20' && ssh-keygen -f \
   '/home/user/.ssh/known_hosts' -R '192.168.56.50' && ssh-keygen -f '/home/user/.ssh/known_hosts' -R '192.168.56.60'