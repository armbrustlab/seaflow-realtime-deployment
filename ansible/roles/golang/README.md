golang
=========

Install the Go programming language.

Role Variables
--------------

* `download_dir`: Top level directory where downloaded apps archives will be stored and built.
* `install_dir`: Top level directory where diamond should be installed. e.g. `/opt` or `/usr/local`.
* `go_version`: Version number for go used for downloads and install.
* `go_checksum`: Checksum string for program archive file.
