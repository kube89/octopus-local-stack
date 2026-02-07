FROM octopusdeploy/tentacle:latest

USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends xxd \
 && rm -rf /var/lib/apt/lists/*

RUN id -u octopus >/dev/null 2>&1 || useradd -m -s /bin/bash octopus
RUN echo "octopus ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/octopus \
 && chmod 0440 /etc/sudoers.d/octopus

RUN mkdir -p /home/Octopus /etc/octopus \
 && chown -R octopus:octopus /home/Octopus /etc/octopus

USER octopus