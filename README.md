# seaflow-realtime-deployment

## Requirements

* Ansible 2.10+
* Public key SSH access with an admin sudo account on an Ubuntu 20.04 server that you wish to configure.

Since Ansible is a Python tool, the easiest way to install it is in a Python virtual environemnt. For example, using `pyenv` with the `pyenv-virtualenv` module

```shell
pyenv virtualenv ansible
pyenv activate ansible
pip install -U setuptools wheel pip  # standard new venv stuff
pip install ansible passlib  # passlib needed on MacOS for password hashing

# Now install galaxy collections
(cd ansible && ansible-galaxy install -r requirements.yml)
```

## Test usage

```shell
# Install vagrant Virtualbox guest additions plugin
vagrant plugin install vagrant-vbguest

# Bring up vagrant testing VMs
vagrant up

# Provision the source test VM
ansible-playbook -i ansible/inventories/vagrant.yml  -l source ansible/playbook-source.yml

# Provision the sink test VM
ansible-playbook -i ansible/inventories/vagrant.yml  -l sink ansible/playbook-sink.yml

# Manually Load consul state
vagrant ssh sink
vagrant@sink:~$ jq '[ .[] | .value = (.value | @base64) ]' < consul_state/test.json | consul kv import -

# Capture the consul state and convert values to strings
consul kv export | jq '[ .[] | .value = (.value | @base64d) ]' > consul_state/consul_state.backup.json

# Turn on analysis
vagrant@sink:~$ consul kv put cruise/onoff on
```

## Create consul JSON state file

Add entries for nomad jobs.
Search for "{{ key " in nomad job files to find the required keys.
Create a JSON file that looks like this

```json
[
  {
    "key": "cruise/name",
    "flags": 0,
    "value": "Intrepid-9"
  },
  {
    "key": "cruise/start",
    "flags": 0,
    "value": "2020-12-16T00:00:00Z"
  }
]
```

For the popcycle Sqlite3 database, add it as a base64 encoded gzip string.
Use this shell snippet to construct the correct JSON object for the database data.
The base64 string should be around 30K in size for one set of gates.

```shell
printf "{\n    \"key\": \"appconfig/seaflow-analysis/dbgz\",\n    \"value\": \"$(gzip -c HOT325.base.db | base64 -w 0)\"\n}\n"
```
