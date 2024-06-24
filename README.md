# Inspiration

This docker image was inspired by fantastic [OpenSSH image](https://docs.linuxserver.io/images/docker-openssh-server/) created by [LinuxServer.io](https://docs.linuxserver.io/). Unfortunately, that image was based on Alpine linux, which makes it hard to use tools that heavily rely on *glibc*. Because I was creating a test and educational image to run multiple bioinformatics tools, many of which plainly refuse to run on Alpine linux, I had to make an effort and try to replicate the functionality using Ubuntu image.

I tried to replicate the interface of [LinuxServer.io](https://docs.linuxserver.io/) image, but due to limited time and resources, it may not be 100% compatible. If you notice any incompatibility or incorrect behaviour, please, raise an issue or make a PR.

**WARNING:** This image was created only for testing and educational purposes. There was little considerations given to the security of the image. So, if you are going to run sensitive applications, please, make sure you extensively test the security and reliability of the image. The authors do not guarantee and cannot be help liable for any loss from use of this repository.

# Environment variables

The server is set via setting environment variables and docker secrets. Some variables do not have default value. In this case, it will have example instead of default value in brackets `[]`.

| <VARIABLE>=<default> | Description |
|------|------|
| PUID=1000 | for UserID - see below for explanation |
| PGID=1000 | for GroupID - see below for explanation |
| TZ=Etc/UTC | specify a timezone to use, see this [list](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones#List). |
| SSH_PORT=2222 | Port where SSH server is expecting the connection. |
| PUBLIC_KEY=[yourpublickey] | Optional ssh public key, which will automatically be added to authorized_keys. |
| PUBLIC_KEY_FILE=[/path/to/file] | Optionally specify a file containing the public key (works with docker secrets). |
| PUBLIC_KEY_DIR=[/path/to/directory/containing/_only_/pubkeys] | Optionally specify a directory containing the public keys (works with docker secrets). |
| PUBLIC_KEY_URL=[https://github.com/username.keys] | Optionally specify a URL containing the public key. |
| SUDO_ACCESS=false | Set to true to allow linuxserver.io, the ssh user, sudo access. Without USER_PASSWORD set, this will allow passwordless sudo access. |
| PASSWORD_ACCESS=false | Set to true to allow user/password ssh access. You will want to set USER_PASSWORD or USER_PASSWORD_FILE as well. |
| USER_PASSWORD=[password] | Optionally set a sudo password for linuxserver.io, the ssh user. If this or USER_PASSWORD_FILE are not set but SUDO_ACCESS is set to true, the user will have passwordless sudo access. |
| USER_PASSWORD_FILE=[/path/to/file] | Optionally specify a file that contains the password. This setting supersedes the USER_PASSWORD option (works with docker secrets). |
| KEY_PASS=false | If true, and at least `PUBLIC_KEY` variable is set and at least one `USER_PASSWORD` is set, then both key and password are required to authentificate. |
| USER_NAME=[user] | Optionally specify a user name (Default:linuxserver.io) |

# Environment variables from files (Docker secrets)

You can set any environment variable from a file by using a special prepend FILE__.

As an example:
```
-e FILE__MYVAR=/run/secrets/mysecretvariable
```

Will set the environment variable `MYVAR` based on the contents of the `/run/secrets/mysecretvariable` file.

# Home directory

Home directory can be mounted into the container at `/home/${USER_NAME}`. If this is not done, an empty directory will be created.

# Custom Scripts¶

This image support for a user's custom scripts to run at startup. In every container, simply create a new folder located at `/custom-cont-init.d` and add any scripts you want. These scripts can contain logic for installing packages, copying over custom files to other locations, or installing plugins.

You will need to mount it like any other volume if you wish to make use of it. e.g. -v /home/foo/appdata/my-custom-files:/custom-cont-init.d if using the Docker CLI or

```yaml
services:
  bar:
    volumes:
      - /home/foo/appdata/my-custom-files:/custom-cont-init.d:ro
```

if using compose. Where possible, to improve security, we recommend mounting them read-only (:ro) so that container processes cannot write to the location.

# Custom Services¶

There might also be a need to run an additional service in a container alongside what we already package. Similarly to the custom scripts, just create a new directory at /custom-services.d. The files in this directory should be named after the service they will be running. Similar to with custom scripts you will need to mount this folder like any other volume if you wish to make use of it. e.g. -v /home/foo/appdata/my-custom-services:/custom-services.d if using the Docker CLI or

```yaml
services:
  bar:
    volumes:
      - /home/foo/appdata/my-custom-services:/custom-services.d:ro
```

if using compose. Where possible, to improve security, we recommend mounting them read-only (:ro) so that container processes cannot write to the location.

Running cron is simple, for instance. In Dockerfile add the following (can be expanded to run several cron jobs or add file instead of writing it):

```bash
RUN echo "*/1 * * * * /root/cron_job.sh > /proc/1/fd/1 2> /proc/1/fd/1" >> /tmp/crontab_root

RUN crontab -u root /tmp/crontab_root

RUN rm /tmp/crontab_root
```

Please, note the trick `> /proc/1/fd/1 2> /proc/1/fd/1`. It is passing all output from both STDOUT and STDERR to the STDOUT of the process 1, which means that it will be recorded in the docker container output. You can choose other logging methods if you wish.

After that, drop the following script in /custom-services.d/cron.sh and it will run automatically in the container:

```bash
#!/usr/bin/with-contenv bash

/usr/sbin/crond -f
```

With this example, you will most likely need to have cron installed via a custom script using the technique in the previous section, and will need to populate the crontab.

# Usage

First of all, build the image:
```bash
git clone https://github.com/pigrenok/openssh-docker.git
cd openssh-docker
docker build --rm -t openssh-docker:latest .
```

Now the easiest option to run the container is to use docker compose. An example `docker-compose.yml` is included in this repository. It comes together with `.env` file, which allows you to set specific variables and use them in docker compose definition. In this example, it is `USER_NAME` which is used to define username and mount external home directory for persistence. There are other ways to pass variables to `docker compose`

After you set up your `docker-compose.yml` and your variables in `.env`, just run
```bash
docker compose up
```

And you can connect to your SSH server on port 2222 (or whichever you forwarded in `docker-compose.yml`).