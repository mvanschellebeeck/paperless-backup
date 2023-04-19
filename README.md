# paperless-backup


### systemd Unit file
```shell
[Unit]
Description=Backup paperless data daily

[Service]
ExecStart=/root/paperless/backup-paperless.sh
```

### systemd Timer file
```shell
[Unit]
Description=paperless-backup service timer

[Timer]
OnCalendar=*-*-* 03:00:00
Unit=paperless-backup.service

[Install]
WantedBy=multi-user.target
```
