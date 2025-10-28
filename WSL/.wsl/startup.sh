#!/bin/bash

set -e

# This command executes upon wsl startup. It must be configured in the /etc/wsl.conf file on the distribution, like this:
#
# [boot]
# command="<path to script>/.wsl/startup.sh"

# Windows paths are not available in this script, so they are defined here.
WSL_EXE="/mnt/c/Windows/System32/wsl.exe"
CMD_EXE="/mnt/c/Windows/System32/cmd.exe"

# Provide the ability to source an .env file to override the default values and provide additional logic.
# NOTE: This sourced file must have LF line endings, not CRLF, or the mount command will fail.
if [[ -f "$(dirname "$0")/startup.env" ]]; then
  # shellcheck disable=SC1091
  . "$(dirname "$0")/startup.env"
fi

# Set WSL_WORKSPACE_FILE to a default value if not already set in the .env file.
if [[ -z "${WSL_WORKSPACE_FILE}" ]]; then
  # The windows path to the workspace vhdx file. Default is %userprofile%\.wsl\workspace.vhdx.
  WSL_WORKSPACE_FILE=$($CMD_EXE /c "echo %userprofile%\.wsl\workspaces.vhdx")
  # Remove the trailing newline character from the Windows path.
  WSL_WORKSPACE_FILE="${WSL_WORKSPACE_FILE::-1}"
fi

if [[ ! -d /mnt/wsl/workspaces ]]; then
  $WSL_EXE --mount --name workspaces --vhd "${WSL_WORKSPACE_FILE}"
fi

if [[ -d /mnt/wsl/workspaces ]] && [[ ! -d /workspaces ]]; then
  ln -s /mnt/wsl/workspaces /workspaces
fi
