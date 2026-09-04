# Runtime secrets

Create the two password files before starting the Compose project. Keep the
directory searchable only by its owner; the files themselves must be readable
inside the non-root application and database containers.

```sh
install -d -m 0700 secrets
openssl rand -base64 36 > secrets/mysql_root_password
openssl rand -base64 36 > secrets/phorge_db_password
chmod 0444 secrets/mysql_root_password secrets/phorge_db_password
podman-compose up --build --detach
```

The Percona image consumes these values only when it initializes a new
`mysql-data` volume. Replacing either file later does not rotate a password in
an existing database.
