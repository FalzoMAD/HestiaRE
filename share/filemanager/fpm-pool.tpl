; File manager per-customer FPM pool (#419). Rendered to
; /etc/php/<ver>/fpm/pool.d/fm-%user%.conf by h-add-user-filemanager, on the
; CUSTOMER php-fpm (version = multiphp_default_version), NOT the panel pool.
; Runs as the customer, so the kernel UID is the file-access boundary — the app
; itself needs no isolation logic. The listen socket's mere existence is what
; fm-auth.php treats as "file manager enabled for this user".
[fm-%user%]
listen = /run/hestia/fm/%user%.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

user = %user%
group = %user%

pm = ondemand
pm.max_children = 4
pm.process_idle_timeout = 10s
pm.max_requests = 500

; FM app errors are otherwise hard to find (the app runs as the customer). Route the
; worker output to the php-fpm log tagged [pool fm-%user%] — no extra file, no perms.
catch_workers_output = yes
php_admin_flag[log_errors] = on

; open_basedir = read-only shared app code + the customer's own home (nothing else).
; A path-traversal in the app therefore cannot leave files the customer already owns.
php_admin_value[open_basedir] = /usr/share/filemanager/fm:/home/%user%
php_admin_value[session.save_path] = /home/%user%/tmp
php_admin_value[upload_tmp_dir] = /home/%user%/tmp
php_admin_value[sys_temp_dir] = /home/%user%/tmp
security.limit_extensions = .php

; The shared code is one read-only copy for all customers, so the per-customer root
; cannot live in the app file — the pool hands it over and the app reads getenv('FM_ROOT').
env[FM_ROOT] = /home/%user%
env[PATH] = /usr/local/bin:/usr/bin:/bin
