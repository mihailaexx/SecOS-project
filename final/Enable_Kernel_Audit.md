# Enable kernel audit (syscall) on Fedora

The watch and `execve` rules in `Final_Payment_Config_Files.md` only fire if the kernel boots with `audit=1`. One line --- then reboot:

    sudo grubby --update-kernel=ALL --args="audit=1" && sudo reboot

After the reboot, verify:

    cat /proc/cmdline | grep -o 'audit=1'      # audit=1
    cat /proc/sys/kernel/audit_enabled         # 1
    sudo auditctl -s | grep enabled            # enabled 1

Then re-trigger to confirm SYSCALL events flow:

    sudo touch /usr/local/bin/payment-backup.sh
    sudo ausearch -k PAY_BAK_SCRIPT -ts recent | tail
