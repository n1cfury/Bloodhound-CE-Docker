# bloodhound-kali

Helper scripts for standing up BloodHound on a Kali Linux VM for lab and AD enumeration work.....definitely vibecode "for science"....but hey it's been working for me for awhile now ¯\_(ツ)_/¯ 

| Script | What it does |
|---|---|
| `bh_setup.sh` | Installs **Neo4j 4.4 natively** for **BloodHound Legacy**, then imports a Neo4j `.dump` |
| `bh_start.sh` | Starts **BloodHound CE** with Docker Compose |

> ⚠️ **These two scripts target different BloodHound stacks and conflict with each other.**
> `bh_setup.sh` removes any Docker BloodHound/Neo4j containers and runs `docker compose down -v`, which **deletes CE volumes and their data**. It then binds native Neo4j to ports 7474 and 7687. CE's Neo4j container needs those same ports.
> Use only one stack at a time. See [Switching between stacks](#switching-between-stacks).

---

## Requirements

- Kali Linux (Debian-based; other Debian or Ubuntu systems will probably work)
- `sudo` or root access
- Docker with the Compose plugin (for `bh_start.sh`)
- Internet access to `debian.neo4j.com` (for `bh_setup.sh`)
- Java 11. `bh_setup.sh` installs it with `openjdk-11-jre`. Check that it is still available in your Kali repos:
  ```bash
  apt-cache policy openjdk-11-jre
  ```

---

## Directory layout

Both scripts expect to run from `~/bloodhound`. Change `WORK_DIR` or `BH_DIR` at the top of each script to match your system.

```
~/bloodhound/
├── bh_setup.sh
├── bh_start.sh
├── docker-compose.yml    # BloodHound CE compose file (for bh_start.sh)
├── <your-data>.dump      # Neo4j 4.4 dump (for bh_setup.sh)
└── bh_setup.log          # created by bh_setup.sh
```

---

## Option A: BloodHound Legacy + native Neo4j (`bh_setup.sh`)

Loads an existing Neo4j 4.4 database dump, such as a prepared lab dataset, into a native Neo4j install.

```bash
cp <your-data>.dump ~/bloodhound/
sudo bash bh_setup.sh
```

The script runs these steps in order:

1. Finds the first `*.dump` file in the working directory. It exits if it finds none.
2. Stops and removes Docker containers that publish ports 7474 or 7687.
3. Removes stopped containers whose names match `bloodhound` or `neo4j`.
4. If a `docker-compose.yml` file exists, runs `docker compose down -v`. **This removes volumes.**
5. Installs Java 11 and Neo4j 4.4 from the official Neo4j apt repo, unless Neo4j is already installed.
6. Sets the initial Neo4j password.
7. Runs `neo4j-admin load --force` to import the dump into the `neo4j` database. **This overwrites any existing data in that database.**
8. Enables and starts the `neo4j` service, waits up to 30 seconds for it to respond, and reports the node count.

After setup, connect the BloodHound Legacy GUI with these settings:

| | |
|---|---|
| Neo4j Browser | http://localhost:7474 |
| Bolt URI | `bolt://localhost:7687` |
| Username | `neo4j` |
| Password | `BloodHound1337` (default, set in `NEO4J_PASSWORD`) |

> 🔑 **Change the default password** before using the script on anything other than an isolated lab VM.

If the node count shows `0` or `unknown`, run this in the Neo4j Browser to check:
```cypher
MATCH (n) RETURN count(n)
```

---

## Option B: BloodHound CE in Docker (`bh_start.sh`)

Starts the BloodHound CE stack from `docker-compose.yml`.

```bash
bash bh_start.sh
```

The script runs `docker-compose up -d`, waits 5 seconds, and prints the container status.

- **UI:** http://localhost:8080. The script prints `http://bloodhound:8080`, which only works if you have a hosts entry for `bloodhound`.
- **First launch:** retrieve the generated admin password with this command:
  ```bash
  sudo docker-compose logs | grep -i initialpassword
  ```

> Get the official CE compose file from the [BloodHound CE repo](https://github.com/SpecterOps/BloodHound).

---

## Switching between stacks

**From Legacy (native) to CE (Docker):**
```bash
sudo systemctl stop neo4j
sudo systemctl disable neo4j   # optional; keeps Neo4j from taking the ports at boot
bash bh_start.sh
```

**From CE (Docker) to Legacy (native):**
```bash
sudo docker compose down       # leave off -v to keep CE data
sudo systemctl start neo4j
```

Running `bh_setup.sh` again **destroys CE data**, because it runs `down -v`. To keep CE data, stop the stack by hand before running the script, or remove the `down -v` block from it.

---

## Troubleshooting

| Symptom | Check |
|---|---|
| Neo4j doesn't start | `journalctl -u neo4j -n 50` |
| Port already in use | `sudo ss -tlnp \| grep -E '7474\|7687\|8080'` |
| Dump fails to load | Make sure the dump was created with Neo4j 4.x. Dumps from 5.x will not load into 4.4. Details are in `bh_setup.log`. |
| `apt-key` warnings | `apt-key` is deprecated on current Debian and Kali. The install still works, but the script should move to a `signed-by` keyring. |

---

## Disclaimer

For authorized testing and lab use only.
