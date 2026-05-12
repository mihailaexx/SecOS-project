**Final --- Config Files**

Secure Containerised Payment Service (Go + Podman)

*All files and commands you need, in the order you need them*

Target: Fedora 38 (per Vagrantfile) with shellinaboxd on :4200, SELinux disabled. The application source lives in `~/payment/` (the repo from `dvalyayevkbtu/payment` --- `main.go`, `go.mod`, `go.sum`, `README.md`).

# Task framing

1. **Role** --- one privileged operator `payadm` (member of `wheel`) who manages the container, the backup, the audit subsystem and the firewall through sudo aliases.
2. **Image** --- build the Go payment service as a hardened multi-stage container image: a `golang:1.24.2` builder stage produces a static binary, the runtime stage is a minimal `alpine` with a non-root user and only the binary inside.
3. **Service** --- run the image under systemd with cgroup limits, full capability drop, read-only rootfs + tmpfs for `/tmp`, `no-new-privileges`, restart on failure, persistent across boot.
4. **Backups** --- once a day, snapshot the payment service journal (the only durable record this in-memory app has) into `/var/backups/payment/`, rotate after 7 days. Cron is scheduled in **root's crontab** (`crontab -e`), not in `/etc/cron.d/`.
5. **Audit** --- raise an alert when anyone tries to modify the backup script, root's crontab, or the systemd unit file. Also record every execution of the backup script.
6. **Firewall** --- single nftables ruleset that allows :22, :4200 and :8080, drops everything else, keeps established connections alive.

The deployment runbook at the end is the order you should apply these steps; doing it out of order will either lock you out of SSH or leave the unit failing to start.

# 1. Create the operator user

`payadm` is the only human who needs sudo on this box. Put them in `wheel` (so they survive any future `pam_wheel` tightening) and give them a real shell.

    sudo useradd -m -s /bin/bash -G wheel payadm
    echo 'payadm:ChangeMe-Pay-123!' | sudo chpasswd
    sudo passwd -e payadm   # force password change on first login

Verify:

    id payadm                # uid, gid, groups (wheel)
    sudo -lU payadm          # initially: only what wheel grants

The fine-grained rules come in §3.

# 2. Containerfile --- hardened multi-stage Go build

Two stages. The builder uses `golang:1.24.2` exactly as the project's README requests, runs `go mod download` once for layer caching, then produces a fully static, stripped binary (`CGO_ENABLED=0`, `-trimpath`, `-ldflags="-s -w"`). The runtime stage is `alpine:3.20` with a dedicated UID/GID 10001 user so the container never has anything resembling root inside.

The runtime image deliberately contains no shell tooling beyond what alpine ships, no source code, no Go toolchain, no module cache --- exactly the surface area a payment service needs and nothing more. Combined with the unit's `--read-only` and `--cap-drop=ALL` in §4, even an RCE in the Go handlers cannot persist state or escalate.

**`~/payment/Containerfile`** *0644 payadm:payadm*

    # syntax=docker/dockerfile:1.6
    
    # ---------- Stage 1: build ------------------------------------------------
    FROM docker.io/library/golang:1.24.2-alpine AS build
    
    WORKDIR /src
    
    # Module cache layer (only re-runs when go.mod / go.sum change)
    COPY go.mod go.sum ./
    RUN go mod download
    
    # Source layer
    COPY . .
    
    # Static, stripped, reproducible binary
    ENV CGO_ENABLED=0 GOOS=linux GOARCH=amd64
    RUN go build -trimpath -ldflags="-s -w" -o /out/payment .
    
    # ---------- Stage 2: runtime ---------------------------------------------
    FROM docker.io/library/alpine:3.20
    
    # Non-root account for the service
    RUN addgroup -S -g 10001 payment \
     && adduser  -S -u 10001 -G payment -h /home/payment -s /sbin/nologin payment
    
    # Only the binary --- no shell scripts, no sources, no go tooling
    COPY --from=build --chown=payment:payment /out/payment /usr/local/bin/payment
    
    USER 10001:10001
    WORKDIR /home/payment
    EXPOSE 8080
    
    ENTRYPOINT ["/usr/local/bin/payment"]

Build the image (run as `payadm`):

    cd ~/payment
    podman build -t localhost/payment:1.0.0 -f Containerfile .

Sanity-check the result before wiring it into systemd:

    podman images localhost/payment                  # tag 1.0.0 present
    podman inspect localhost/payment:1.0.0 \
        --format '{{.Config.User}}  {{.Config.ExposedPorts}}'
    # expect:  10001:10001  map[8080/tcp:{}]
    
    # smoke run --- foreground, host network, ctrl-c to stop
    podman run --rm --network host localhost/payment:1.0.0 &
    sleep 1
    curl -i -X POST http://127.0.0.1:8080/payment \
         -H 'Content-Type: application/json' \
         -d '{"reference":"smoke-1","volume":"10.00","currency":"USD"}'
    curl -s    http://127.0.0.1:8080/payment/smoke-1 | head
    pkill -f /usr/local/bin/payment

# 3. /etc/sudoers.d/payment --- one operator, command aliases

Drop-in file (never edit `/etc/sudoers` directly). Uses `User_Alias`, `Cmnd_Alias`, `Runas_Alias` exactly the way Lecture 3 expects. `payadm` ends up with everything they need to run the service, inspect the container, trigger a backup, read audit logs, and reload the firewall --- and nothing else. Validate before you save with `visudo -c -f /etc/sudoers.d/payment`.

**`/etc/sudoers.d/payment`** *0440 root:root --- edit with: `sudo visudo -f /etc/sudoers.d/payment`*

    #
    # Final --- payment service operator
    # One human role: payadm
    #
    
    ##
    ## User aliases
    ##
    User_Alias   PAYADMINS = payadm
    
    ##
    ## Runas alias --- what identity the commands run as
    ##
    Runas_Alias  OPS_RUNAS = root
    
    ##
    ## Command aliases --- one per logical function
    ##
    
    # Lifecycle of the payment unit and its journal
    Cmnd_Alias   SVC_PAY  = /usr/bin/systemctl start   payment.service, \
                            /usr/bin/systemctl stop    payment.service, \
                            /usr/bin/systemctl restart payment.service, \
                            /usr/bin/systemctl reload  payment.service, \
                            /usr/bin/systemctl status  payment.service, \
                            /usr/bin/journalctl -u payment.service *
    
    # Read-only podman introspection (no run, no rm, no exec into root)
    Cmnd_Alias   PODMAN   = /usr/bin/podman ps,    /usr/bin/podman ps -a, \
                            /usr/bin/podman logs   payment, \
                            /usr/bin/podman inspect payment, \
                            /usr/bin/podman top    payment, \
                            /usr/bin/podman stats --no-stream payment
    
    # Manual backup trigger
    Cmnd_Alias   PAY_BAK  = /usr/local/bin/payment-backup.sh
    
    # Audit subsystem --- read-only views
    Cmnd_Alias   PAY_AUD  = /usr/sbin/auditctl -l, \
                            /usr/sbin/ausearch *,  \
                            /usr/sbin/aureport *
    
    # Firewall --- inspect and reload only (rules live in §7)
    Cmnd_Alias   PAY_FW   = /usr/sbin/nft list ruleset, \
                            /usr/bin/systemctl reload  nftables.service, \
                            /usr/bin/systemctl restart nftables.service, \
                            /usr/bin/systemctl status  nftables.service
    
    ##
    ## Rules --- one user, every alias, no password
    ##
    PAYADMINS ALL=(OPS_RUNAS) NOPASSWD: SVC_PAY, PODMAN, PAY_BAK, PAY_AUD, PAY_FW
    
    ##
    ## Hardening defaults
    ##
    Defaults  env_reset
    Defaults  secure_path = "/sbin:/bin:/usr/sbin:/usr/bin"
    Defaults !visiblepw
    Defaults  always_set_home
    Defaults  use_pty
    Defaults  log_input, log_output
    Defaults  iolog_dir   = "/var/log/sudo-io"

Install and verify:

    sudo install -o root -g root -m 0440 /tmp/payment.sudoers /etc/sudoers.d/payment
    sudo visudo -c                       # all sudoers files OK
    sudo -lU payadm                      # SVC_PAY / PODMAN / PAY_BAK / PAY_AUD / PAY_FW visible
    sudo -u payadm sudo systemctl status payment.service   # works without a password

# 4. /etc/systemd/system/payment.service --- hardened container unit

Runs the image we built in §2 under rootful podman with every podman-level hardening flag the assignment calls for. The host networking pattern matches Quiz 4 (it's the firewall in §7 that controls reachability), but everything else is locked down: full cgroup limits, read-only rootfs with a small tmpfs at `/tmp`, all capabilities dropped, `no-new-privileges`, and a hard-pinned non-root UID/GID 10001 (overrides the image, defence in depth).

The unit deliberately does **not** pull from a remote registry --- the image is local, built from your reviewed source.

**`/etc/systemd/system/payment.service`** *0644 root:root*

    [Unit]
    Description=Payment service (hardened podman container)
    Documentation=https://github.com/dvalyayevkbtu/payment
    Wants=network-online.target
    After=network-online.target
    
    [Service]
    Type=simple
    Restart=on-failure
    RestartSec=5s
    TimeoutStartSec=120
    TimeoutStopSec=60
    
    # Clean up any stale container left over from a previous run
    ExecStartPre=-/usr/bin/podman rm -f payment
    
    ExecStart=/usr/bin/podman run \
        --name=payment \
        --rm \
        --network host \
        --memory=128m --memory-swap=128m \
        --cpus=0.5 \
        --pids-limit=64 \
        --read-only \
        --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m \
        --cap-drop=ALL \
        --security-opt=no-new-privileges \
        --user=10001:10001 \
        -e PAYMENT_PORT=8080 \
        localhost/payment:1.0.0
    
    ExecStop=/usr/bin/podman stop --time=30 payment
    
    [Install]
    WantedBy=multi-user.target

Activate it:

    sudo install -o root -g root -m 0644 /tmp/payment.service /etc/systemd/system/payment.service
    sudo systemctl daemon-reload
    sudo systemctl enable --now payment.service
    sudo systemctl status payment.service       # Active: active (running)
    
    # Verify the hardening is actually in effect
    podman inspect payment --format \
      '{{.HostConfig.ReadonlyRootfs}} {{.HostConfig.Memory}} {{.HostConfig.NanoCpus}}'
    # expect:  true 134217728 500000000
    
    podman inspect payment --format '{{.HostConfig.CapDrop}}'   # [ALL]
    podman inspect payment --format '{{.HostConfig.SecurityOpt}}' # [no-new-privileges]
    podman inspect payment --format '{{.Config.User}}'          # 10001:10001
    
    ss -tlnp | grep 8080                        # listening on 0.0.0.0:8080

Functional smoke test from the host:

    curl -i -X POST http://127.0.0.1:8080/payment \
         -H 'Content-Type: application/json' \
         -d '{"reference":"unit-1","volume":"99.99","currency":"USD"}'
    sleep 6   # let the goroutine in main.go fulfill it
    curl -s   http://127.0.0.1:8080/payment/unit-1 | head

# 5. /usr/local/bin/payment-backup.sh --- daily journal snapshot

The payment service is in-memory --- the only thing worth backing up is its journal (every CREATED/FULFILLED line that `logrus` emitted). We export it in journalctl's portable `export` format, gzip it, rotate after 7 days, and use `flock` so two cron ticks cannot race. Every run drops a one-line summary into journald via `logger`, which gives you a quick `journalctl -t payment-backup` audit trail on top of the audit rule in §7.

**`/usr/local/bin/payment-backup.sh`** *0750 root:root*

    #!/usr/bin/env bash
    # Final --- daily payment service journal backup
    set -euo pipefail
    
    BACKUP_DIR="/var/backups/payment"
    DATE="$(date +%Y%m%d_%H%M%S)"
    FILE="${BACKUP_DIR}/payment_${DATE}.journal.gz"
    LOCK="/run/payment-backup.lock"
    
    # Single instance only
    exec 9>"${LOCK}"
    flock -n 9 || { echo "Another payment backup is already running; aborting." >&2; exit 1; }
    
    # Make sure the destination exists with the right perms even after reboot
    install -d -o root -g root -m 0750 "${BACKUP_DIR}"
    
    # Last 24h of the payment unit's journal, portable export format
    journalctl -u payment.service --since "24 hours ago" -o export \
        | gzip -9 > "${FILE}"
    
    chown root:root "${FILE}"
    chmod 0640 "${FILE}"
    
    # Rotation: keep last 7 days
    find "${BACKUP_DIR}" -type f -name 'payment_*.journal.gz' -mtime +7 -delete
    
    logger -t payment-backup "OK: $(basename "${FILE}") size=$(du -h "${FILE}" | cut -f1)"

Install and smoke-test:

    sudo install -o root -g root -m 0750 /tmp/payment-backup.sh /usr/local/bin/payment-backup.sh
    sudo install -d -o root -g root -m 0750 /var/backups/payment
    
    sudo /usr/local/bin/payment-backup.sh                  # produces today's snapshot
    ls -l /var/backups/payment/payment_*.journal.gz        # exists, mode 0640
    sudo zcat /var/backups/payment/payment_*.journal.gz | head

# 6. crontab --- schedule via root's crontab

The assignment requires the schedule to live in **root's crontab** (`crontab -e`), not in a `/etc/cron.d/` drop-in. That's why the audit rule in §7 watches `/var/spool/cron/root` rather than a file under `/etc/cron.d/`.

Open root's crontab (creates `/var/spool/cron/root` if it does not exist):

    sudo crontab -e

Add exactly these four lines (the header makes future readers' lives easier; everything except the schedule line is optional, but `MAILTO=""` silences cron's local mail spool):

    # Final --- payment service backups
    SHELL=/bin/bash
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    MAILTO=""
    # m  h  dom mon dow   command
      30 2  *   *   *     /usr/local/bin/payment-backup.sh >> /var/log/payment-backup.log 2>&1

Save and verify:

    sudo crontab -l                                # the four lines come back
    sudo ls -l /var/spool/cron/root                # owned root:root, mode 0600
    sudo systemctl status crond                    # Active: active (running)
    sudo journalctl -u crond -n 20 | grep RELOAD   # cron picked the new crontab up

If `crond` is not installed/enabled yet:

    sudo dnf install -y cronie
    sudo systemctl enable --now crond

# 7. /etc/audit/rules.d/payment.rules --- audit watches

The exam wording is "raise an alert if somebody tries to modify the backup script or the schedule". Three watches plus one syscall rule cover the chain end-to-end: the script itself, root's crontab (where §6 put the schedule), and the systemd unit; plus an `execve` rule that records every actual run of the script with full PID/UID/AUID context.

After dropping the file, load it with `augenrules --load` so the rules survive a reboot.

**`/etc/audit/rules.d/payment.rules`** *0640 root:root*

    ## Final --- audit the payment backup chain
    
    # Backup script itself
    -w /usr/local/bin/payment-backup.sh -p wa -k PAY_BAK_SCRIPT
    
    # Root's crontab (the only place the schedule lives, per §6)
    -w /var/spool/cron/root            -p wa -k PAY_BAK_CRON
    
    # The systemd unit that runs the container
    -w /etc/systemd/system/payment.service -p wa -k PAY_UNIT
    
    # Record every execution of the backup script
    -a always,exit -F arch=b64 -F path=/usr/local/bin/payment-backup.sh \
                   -F perm=x   -k PAY_BAK_EXEC

Apply and verify:

    sudo install -o root -g root -m 0640 /tmp/payment.rules \
        /etc/audit/rules.d/payment.rules
    sudo augenrules --load
    sudo auditctl -l | grep PAY_                  # all four rules listed
    
    # Trigger an alert
    sudo touch /usr/local/bin/payment-backup.sh
    sudo ausearch -k PAY_BAK_SCRIPT | tail -20    # SYSCALL event visible
    
    # Trigger the execve rule
    sudo /usr/local/bin/payment-backup.sh
    sudo ausearch -k PAY_BAK_EXEC | tail -20

If `auditd` is not installed/enabled yet:

    sudo dnf install -y audit
    sudo systemctl enable --now auditd

# 8. /etc/sysconfig/nftables.conf --- the firewall

A single inet table named `filter` with three small named chains feeding the `input` hook. The `inbound_established` chain is jumped to first so your live SSH session survives every reload --- forgetting that line is the classic way to lock yourself out of the VM. Only :22, :4200 and :8080 are allowed in; everything else is logged (rate-limited so the log cannot blow up) and dropped.

**`/etc/sysconfig/nftables.conf`** *0600 root:root --- loaded by nftables.service*

    #!/usr/sbin/nft -f
    # Final firewall --- Fedora 38
    # Loaded automatically by systemctl start nftables.service.
    
    flush ruleset
    
    table inet filter {
    
        # ---- helpers --------------------------------------------------------
    
        chain inbound_established {
            ct state vmap {
                established : accept,
                related     : accept,
                invalid     : drop
            }
        }
    
        chain inbound_loopback {
            iif "lo" accept
        }
    
        chain inbound_public {
            tcp dport 4200 accept    # shellinaboxd web terminal
            tcp dport 22   accept    # SSH
            tcp dport 8080 accept    # payment service
        }
    
        # ---- hooks ----------------------------------------------------------
    
        chain input {
            type filter hook input priority filter; policy drop;
    
            # 1. Keep existing connections alive (critical, must be first)
            jump inbound_established
    
            # 2. Loopback is always allowed
            jump inbound_loopback
    
            # 3. Application + management ports
            jump inbound_public
    
            # 4. Log + drop anything else, rate-limited
            log prefix "[nft drop in] " level info limit rate 5/minute counter drop
        }
    
        chain forward {
            type filter hook forward priority filter; policy drop;
        }
    
        chain output {
            type filter hook output priority filter; policy accept;
        }
    }

Activate:

    sudo install -o root -g root -m 0600 /tmp/nftables.conf /etc/sysconfig/nftables.conf
    sudo nft -c -f /etc/sysconfig/nftables.conf       # syntax check first
    sudo systemctl enable --now nftables.service
    sudo nft list ruleset                             # final ruleset

Smoke tests:

    # From inside the VM --- existing connections survived
    ss -tnH | head
    
    # From your host machine, against the VM's IP
    nc -zv <vm-ip> 22 4200 8080      # all three should connect
    nc -zv <vm-ip> 80                # must FAIL (drop)

If `nftables` is not installed yet:

    sudo dnf install -y nftables

# Deployment runbook --- the order to apply

Doing it out of order can lock you out (firewall first, no SSH rule) or leave the unit failing to start (service before image is built).

1. `sudo useradd -m -s /bin/bash -G wheel payadm && sudo passwd payadm` --- §1
2. `cd ~/payment && podman build -t localhost/payment:1.0.0 -f Containerfile .` --- §2
3. drop `/etc/sudoers.d/payment`, then `sudo visudo -c` --- §3
4. drop `/etc/systemd/system/payment.service`, then `sudo systemctl daemon-reload && sudo systemctl enable --now payment.service` --- §4
5. drop `/usr/local/bin/payment-backup.sh` and create `/var/backups/payment/`, then run it once by hand --- §5
6. `sudo crontab -e` and add the schedule --- §6
7. drop `/etc/audit/rules.d/payment.rules`, then `sudo augenrules --load` --- §7
8. drop `/etc/sysconfig/nftables.conf`, `sudo nft -c -f` to syntax-check, then `sudo systemctl enable --now nftables.service` --- §8
9. run the verification checklist below; every line should succeed.

# Verification checklist

Run these as root from the VM. If any fail, fix them before declaring the lab done.

**Role**

    id payadm                                  # member of wheel
    sudo -lU payadm                            # SVC_PAY, PODMAN, PAY_BAK, PAY_AUD, PAY_FW

**Image**

    podman images localhost/payment            # tag 1.0.0 present
    podman inspect localhost/payment:1.0.0 \
        --format '{{.Config.User}}'            # 10001:10001

**Service hardening**

    systemctl is-enabled payment.service       # enabled
    systemctl is-active  payment.service       # active
    podman inspect payment --format '{{.HostConfig.ReadonlyRootfs}}'      # true
    podman inspect payment --format '{{.HostConfig.CapDrop}}'             # [ALL]
    podman inspect payment --format '{{.HostConfig.SecurityOpt}}'         # [no-new-privileges]
    podman inspect payment --format '{{.HostConfig.Memory}} {{.HostConfig.NanoCpus}}'
    # 134217728 500000000   (=128 MiB, 0.5 CPU)
    ss -tlnp | grep 8080                       # 0.0.0.0:8080

**Functional smoke**

    curl -i -X POST http://127.0.0.1:8080/payment \
         -H 'Content-Type: application/json' \
         -d '{"reference":"vc-1","volume":"1.00","currency":"USD"}'
    sleep 6
    curl -s http://127.0.0.1:8080/payment/vc-1 | head     # FULFILLED

**Backups + cron**

    sudo /usr/local/bin/payment-backup.sh
    ls -l /var/backups/payment/payment_*.journal.gz       # exists, mode 0640
    sudo crontab -l | grep payment-backup                 # the schedule line

**Audit**

    sudo auditctl -l | grep PAY_                          # 4 rules
    sudo touch /usr/local/bin/payment-backup.sh
    sudo ausearch -k PAY_BAK_SCRIPT | tail -5             # event visible

**Firewall**

    sudo nft list ruleset | head -30
    # from your host:
    nc -zv <vm-ip> 22 4200 8080                           # all three open
    nc -zv <vm-ip> 80                                     # fails (dropped)

# Common pitfalls to avoid

- Editing `/etc/sudoers` directly instead of dropping a file in `/etc/sudoers.d/` --- possible loss of marks even if it works.
- Forgetting the `ct state established,related accept` jump at the top of `input` --- your SSH session dies the moment you reload the ruleset.
- Putting the schedule in `/etc/cron.d/` instead of root's crontab --- the assignment names `crontab` specifically, and the audit watch in §7 looks at `/var/spool/cron/root`.
- Loading audit rules with `auditctl -w …` only and not persisting them in `/etc/audit/rules.d/` --- they vanish on next boot.
- Leaving the runtime image based on `golang:1.24.2` --- you ship the entire Go toolchain, the module cache and a shell into production. Multi-stage with an `alpine` (or `scratch`) final stage is the whole point.
- Forgetting `--read-only`, `--cap-drop=ALL` or `--security-opt=no-new-privileges` on the `podman run` --- the container is no harder to break out of than a `docker run` from 2014.
- Skipping `--user=10001:10001` on the unit and trusting only the `USER` directive in the Containerfile --- a malicious image rebuild could silently flip back to root; pinning at the unit level is defence in depth.
- Skipping `systemctl enable` for `payment.service`, `nftables.service` or `crond` --- works now, dies on next boot.
