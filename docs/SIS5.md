```bash
ansible-playbook scripts/logs/logs-audit.yml -e key=identity -e host=bastion-01 -e since='1 day ago'
ansible-playbook scripts/logs/logs-db.yml -e pattern='ERROR' -e since='1 day ago'
ansible-playbook scripts/logs/logs-idp.yml -e pattern='SRCH' -e since='1 day ago'
ansible-playbook scripts/logs/logs-ssh.yml -e pattern='vagrant' -e since='1 day ago'
```

```bash
# Events from a specific user
ansible target -m shell -a 'ausearch --start today --uid postgres'
```

```bash
# Failed login report fleet-wide
ansible all -m shell -a 'aureport -l --failed --start today'
```

```bash
# List currently loaded rules per host
ansible all -m shell -a 'auditctl -l'
```
