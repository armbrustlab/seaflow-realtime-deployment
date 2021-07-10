executable_downloader
=========

Download and install an executable file.

To use this role, include it in another role and pass it variables described in
`meta/argument_specs.yml`. For example,

```
- name: Import executable_downloader role
  import_role:
    name: executable_downloader
  vars:
    execdl_name: "{{ name }}"
    execdl_checksum: "{{ checksum }}"
    execdl_version: "{{ version }}"
    execdl_version_success_string: "{{ version_success_string }}"
    execdl_version_cmd: "{{ version_cmd }}"
    execdl_url: "{{ url }}"
    execdl_extracted_exec: "{{ extracted_exec }}"
```
