FROM opensuse/leap:15.5

ARG TARGETARCH

# Create non-priviledged user.
RUN useradd --create-home --no-log-init --shell /bin/bash suse

# Update DNF package lists.
RUN zypper update --no-confirm

# Install Bash, Curl, and Sudo.  
RUN zypper install --no-confirm bash curl sudo

# Create sudo group.
RUN groupadd sudo

# Add standard user to sudoers group.
RUN usermod --append --groups sudo suse

# Allow sudo commands with no password.
RUN printf "%%sudo ALL=(ALL) NOPASSWD:ALL\n" >> /etc/sudoers

# Fix current sudo bug for containers.
# https://github.com/sudo-project/sudo/issues/42
RUN echo "Set disable_coredump false" >> /etc/sudo.conf

ENV HOME=/home/suse USER=suse
USER suse

# Install Bootware.
COPY bootware.sh /usr/local/bin/bootware

# Install dependencies for Bootware.
RUN bootware setup

# Create bootware project directory.
RUN mkdir $HOME/bootware
WORKDIR $HOME/bootware

# Copy bootware project files.
COPY --chown="${USER}" ansible_collections/ ./ansible_collections/
COPY --chown="${USER}" ansible.cfg playbook.yaml ./

ARG skip
ARG tags
ARG test

# VSCode, when run inside of a container, will falsely warn the user about the
# issues of running inside of the WSL and force a yes or no prompt.
ENV DONT_PROMPT_WSL_INSTALL='true'

# Run Bootware bootstrapping.
RUN bootware bootstrap --dev --no-passwd \
    --retries 3 ${skip:+--skip $skip} --tags ${tags:-desktop,extras}

# Copy bootware test files for testing.
COPY --chown="${USER}" tests/ ./tests/

# Set Bash as default shell.
SHELL ["/bin/bash", "-c"]

# Test installed binaries for roles.
#
# Flags:
#   -n: Check if the string has nonzero length.
RUN if [[ -n "$test" ]]; then \
        source "${HOME}/.bashrc"; \
        if [[ ! -x "$(command -v node)" ]]; then \
            sudo zypper install --no-confirm nodejs-default; \
        fi; \
        node tests/integration/roles.spec.js --arch "${TARGETARCH}" ${skip:+--skip $skip} ${tags:+--tags $tags} "suse"; \
    fi
