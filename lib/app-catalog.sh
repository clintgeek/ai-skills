#!/usr/bin/env zsh
# Shared app catalog for machine-setup.
# Sourced by machine-setup/scripts/machine-wizard.zsh.
#
# Add an app by adding its id to APPS and filling the associative arrays below.
# Leave an OS command/package empty if the app is not available there.
# Linux installs are built from APP_PACKAGE_LINUX and APP_PACKAGE_APT unless
# APP_INSTALL_LINUX provides a raw/distro-specific override (e.g. oh-my-zsh).

APPS=(
  git
  jq
  fzf
  ripgrep
  fd
  htop
  iterm2
  raycast
  1password
  arc
  firefox
  visual-studio-code
  cursor
  docker
  postman
  slack
  zoom
  notion
  rectangle
  tmux
  zsh
  oh-my-zsh
  btop
)

typeset -A APP_NAME APP_TAGS
APP_NAME[git]="Git"
APP_TAGS[git]="dev,cli,base"

APP_NAME[jq]="jq"
APP_TAGS[jq]="cli,base"

APP_NAME[fzf]="fzf"
APP_TAGS[fzf]="cli,base"

APP_NAME[ripgrep]="ripgrep"
APP_TAGS[ripgrep]="cli,base"

APP_NAME[fd]="fd"
APP_TAGS[fd]="cli,base"

APP_NAME[htop]="htop"
APP_TAGS[htop]="cli,base"

APP_NAME[iterm2]="iTerm2"
APP_TAGS[iterm2]="terminal"

APP_NAME[raycast]="Raycast"
APP_TAGS[raycast]="productivity"

APP_NAME[1password]="1Password"
APP_TAGS[1password]="security"

APP_NAME[arc]="Arc Browser"
APP_TAGS[arc]="browser"

APP_NAME[firefox]="Firefox"
APP_TAGS[firefox]="browser"

APP_NAME[visual-studio-code]="Visual Studio Code"
APP_TAGS[visual-studio-code]="dev,dev-tools"

APP_NAME[cursor]="Cursor"
APP_TAGS[cursor]="dev,dev-tools"

APP_NAME[docker]="Docker"
APP_TAGS[docker]="dev,dev-tools"

APP_NAME[postman]="Postman"
APP_TAGS[postman]="dev,dev-tools"

APP_NAME[slack]="Slack"
APP_TAGS[slack]="communication"

APP_NAME[zoom]="Zoom"
APP_TAGS[zoom]="communication"

APP_NAME[notion]="Notion"
APP_TAGS[notion]="productivity"

APP_NAME[rectangle]="Rectangle"
APP_TAGS[rectangle]="productivity"

APP_NAME[tmux]="tmux"
APP_TAGS[tmux]="cli,base"

APP_NAME[zsh]="zsh"
APP_TAGS[zsh]="cli,base"

APP_NAME[oh-my-zsh]="Oh My Zsh"
APP_TAGS[oh-my-zsh]="cli,base"

APP_NAME[btop]="btop"
APP_TAGS[btop]="cli,base"

typeset -A APP_PACKAGE_LINUX APP_PACKAGE_APT APP_INSTALL_MAC APP_INSTALL_LINUX APP_INSTALL_WINDOWS

APP_INSTALL_MAC[git]="brew install git"
APP_PACKAGE_LINUX[git]="git"
APP_INSTALL_WINDOWS[git]="winget install --id Git.Git --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[jq]="brew install jq"
APP_PACKAGE_LINUX[jq]="jq"
APP_INSTALL_WINDOWS[jq]="winget install --id jqlang.jq --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[fzf]="brew install fzf"
APP_PACKAGE_LINUX[fzf]="fzf"
APP_INSTALL_WINDOWS[fzf]=""

APP_INSTALL_MAC[ripgrep]="brew install ripgrep"
APP_PACKAGE_LINUX[ripgrep]="ripgrep"
APP_INSTALL_WINDOWS[ripgrep]="winget install --id BurntSushi.ripgrep.MSVC --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[fd]="brew install fd"
APP_PACKAGE_LINUX[fd]="fd"
APP_PACKAGE_APT[fd]="fd-find"
APP_INSTALL_WINDOWS[fd]="winget install --id sharkdp.fd --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[htop]="brew install htop"
APP_PACKAGE_LINUX[htop]="htop"
APP_INSTALL_WINDOWS[htop]=""

APP_INSTALL_MAC[iterm2]="brew install --cask iterm2"
APP_PACKAGE_LINUX[iterm2]=""
APP_INSTALL_WINDOWS[iterm2]=""

APP_INSTALL_MAC[raycast]="brew install --cask raycast"
APP_PACKAGE_LINUX[raycast]=""
APP_INSTALL_WINDOWS[raycast]=""

APP_INSTALL_MAC[1password]="brew install --cask 1password"
APP_PACKAGE_LINUX[1password]=""
APP_INSTALL_WINDOWS[1password]=""

APP_INSTALL_MAC[arc]="brew install --cask arc"
APP_PACKAGE_LINUX[arc]=""
APP_INSTALL_WINDOWS[arc]=""

APP_INSTALL_MAC[firefox]="brew install --cask firefox"
APP_PACKAGE_LINUX[firefox]="firefox"
APP_INSTALL_WINDOWS[firefox]="winget install --id Mozilla.Firefox --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[visual-studio-code]="brew install --cask visual-studio-code"
APP_INSTALL_LINUX[visual-studio-code]="sudo snap install code --classic"
APP_INSTALL_WINDOWS[visual-studio-code]="winget install --id Microsoft.VisualStudioCode --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[cursor]="brew install --cask cursor"
APP_PACKAGE_LINUX[cursor]=""
APP_INSTALL_WINDOWS[cursor]=""

APP_INSTALL_MAC[docker]="brew install --cask docker"
APP_PACKAGE_LINUX[docker]="docker"
APP_PACKAGE_APT[docker]="docker.io"
APP_INSTALL_WINDOWS[docker]="winget install --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[postman]="brew install --cask postman"
APP_PACKAGE_LINUX[postman]=""
APP_INSTALL_WINDOWS[postman]=""

APP_INSTALL_MAC[slack]="brew install --cask slack"
APP_PACKAGE_LINUX[slack]=""
APP_INSTALL_WINDOWS[slack]=""

APP_INSTALL_MAC[zoom]="brew install --cask zoom"
APP_PACKAGE_LINUX[zoom]=""
APP_INSTALL_WINDOWS[zoom]=""

APP_INSTALL_MAC[notion]="brew install --cask notion"
APP_PACKAGE_LINUX[notion]=""
APP_INSTALL_WINDOWS[notion]=""

APP_INSTALL_MAC[rectangle]="brew install --cask rectangle"
APP_PACKAGE_LINUX[rectangle]=""
APP_INSTALL_WINDOWS[rectangle]=""

APP_INSTALL_MAC[tmux]="brew install tmux"
APP_PACKAGE_LINUX[tmux]="tmux"
APP_INSTALL_WINDOWS[tmux]=""

APP_INSTALL_MAC[zsh]="brew install zsh"
APP_PACKAGE_LINUX[zsh]="zsh"
APP_INSTALL_WINDOWS[zsh]=""

APP_INSTALL_MAC[oh-my-zsh]='RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
APP_INSTALL_LINUX[oh-my-zsh]='RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
APP_INSTALL_WINDOWS[oh-my-zsh]=""

APP_INSTALL_MAC[btop]="brew install btop"
APP_PACKAGE_LINUX[btop]="btop"
APP_INSTALL_WINDOWS[btop]=""
