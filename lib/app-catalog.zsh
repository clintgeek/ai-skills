#!/usr/bin/env zsh
# Shared app catalog for machine-setup.
# Sourced by skills/machine-setup/scripts/machine-wizard.zsh.
#
# Add an app by adding its id to APPS and filling the arrays below.
# Leave an OS command/package empty if the app is not available there.
# Linux installs are built from APP_PACKAGE_LINUX and APP_PACKAGE_APT unless
# APP_INSTALL_LINUX provides a raw/distro-specific override (e.g. oh-my-zsh).
#
# ROLES vs CATEGORIES -- these are two different axes and used to be conflated
# in one APP_TAGS list, which made `--role dev` and `--categories dev` mean the
# same thing while `--role admin` and `--role general` matched nothing at all.
#
#   APP_ROLES[app]  what the machine is FOR. One or more of:
#                   dev, design, data, writing, gaming, admin, general
#   APP_TAGS[app]   what KIND of app it is. One or more of:
#                   cli, terminal, browser, productivity, security, media,
#                   dev-tools, cloud, communication
#                   plus the special tag `base`, meaning "always install".
#
# Every role listed in VALID_ROLES (machine-wizard.zsh) must appear on at least
# one app here, or that role silently selects nothing but `base`. The
# machine_setup_test.zsh suite asserts exactly that.

APPS=(
  git
  jq
  fzf
  ripgrep
  fd
  htop
  btop
  tmux
  zsh
  oh-my-zsh
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
  figma
  imagemagick
  python
  duckdb
  obsidian
  pandoc
  steam
  discord
)

typeset -A APP_NAME APP_TAGS APP_ROLES

# --- always-on base layer -------------------------------------------------
APP_NAME[git]="Git";                    APP_TAGS[git]="cli,base,dev-tools";        APP_ROLES[git]="dev,admin,data,design,writing"
APP_NAME[jq]="jq";                      APP_TAGS[jq]="cli,base";                   APP_ROLES[jq]="dev,admin,data"
APP_NAME[fzf]="fzf";                    APP_TAGS[fzf]="cli,base";                  APP_ROLES[fzf]="dev,admin"
APP_NAME[ripgrep]="ripgrep";            APP_TAGS[ripgrep]="cli,base";              APP_ROLES[ripgrep]="dev,admin,data"
APP_NAME[fd]="fd";                      APP_TAGS[fd]="cli,base";                   APP_ROLES[fd]="dev,admin"
APP_NAME[htop]="htop";                  APP_TAGS[htop]="cli,base";                 APP_ROLES[htop]="admin,dev"
APP_NAME[btop]="btop";                  APP_TAGS[btop]="cli,base";                 APP_ROLES[btop]="admin"
APP_NAME[tmux]="tmux";                  APP_TAGS[tmux]="cli,base,terminal";        APP_ROLES[tmux]="dev,admin"
APP_NAME[zsh]="zsh";                    APP_TAGS[zsh]="cli,base,terminal";         APP_ROLES[zsh]="dev,admin,general"
APP_NAME[oh-my-zsh]="Oh My Zsh";        APP_TAGS[oh-my-zsh]="cli,base,terminal";   APP_ROLES[oh-my-zsh]="dev,admin,general"

# --- terminal / desktop ---------------------------------------------------
APP_NAME[iterm2]="iTerm2";              APP_TAGS[iterm2]="terminal";               APP_ROLES[iterm2]="dev,admin"
APP_NAME[raycast]="Raycast";            APP_TAGS[raycast]="productivity";          APP_ROLES[raycast]="general,dev,design,writing"
APP_NAME[1password]="1Password";        APP_TAGS[1password]="security";            APP_ROLES[1password]="general,dev,admin"
APP_NAME[rectangle]="Rectangle";        APP_TAGS[rectangle]="productivity";        APP_ROLES[rectangle]="general,dev,design"

# --- browsers -------------------------------------------------------------
APP_NAME[arc]="Arc Browser";            APP_TAGS[arc]="browser";                   APP_ROLES[arc]="general,design"
APP_NAME[firefox]="Firefox";            APP_TAGS[firefox]="browser";               APP_ROLES[firefox]="general,dev,design"

# --- dev ------------------------------------------------------------------
APP_NAME[visual-studio-code]="Visual Studio Code"; APP_TAGS[visual-studio-code]="dev-tools"; APP_ROLES[visual-studio-code]="dev,data,writing"
APP_NAME[cursor]="Cursor";              APP_TAGS[cursor]="dev-tools";              APP_ROLES[cursor]="dev,data"
APP_NAME[docker]="Docker";              APP_TAGS[docker]="dev-tools,cloud";        APP_ROLES[docker]="dev,admin,data"
APP_NAME[postman]="Postman";            APP_TAGS[postman]="dev-tools";             APP_ROLES[postman]="dev"

# --- communication --------------------------------------------------------
APP_NAME[slack]="Slack";                APP_TAGS[slack]="communication";           APP_ROLES[slack]="general,dev,design,writing"
APP_NAME[zoom]="Zoom";                  APP_TAGS[zoom]="communication";            APP_ROLES[zoom]="general,dev,design,writing"
APP_NAME[discord]="Discord";            APP_TAGS[discord]="communication";         APP_ROLES[discord]="gaming,general"

# --- writing / notes ------------------------------------------------------
APP_NAME[notion]="Notion";              APP_TAGS[notion]="productivity";           APP_ROLES[notion]="general,writing,design"
APP_NAME[obsidian]="Obsidian";          APP_TAGS[obsidian]="productivity";         APP_ROLES[obsidian]="writing"
APP_NAME[pandoc]="Pandoc";              APP_TAGS[pandoc]="cli";                    APP_ROLES[pandoc]="writing,data"

# --- design ---------------------------------------------------------------
APP_NAME[figma]="Figma";                APP_TAGS[figma]="media";                   APP_ROLES[figma]="design"
APP_NAME[imagemagick]="ImageMagick";    APP_TAGS[imagemagick]="cli,media";         APP_ROLES[imagemagick]="design,data"

# --- data -----------------------------------------------------------------
APP_NAME[python]="Python";              APP_TAGS[python]="cli,dev-tools";          APP_ROLES[python]="data,dev"
APP_NAME[duckdb]="DuckDB";              APP_TAGS[duckdb]="cli";                    APP_ROLES[duckdb]="data"

# --- gaming ---------------------------------------------------------------
APP_NAME[steam]="Steam";                APP_TAGS[steam]="media";                   APP_ROLES[steam]="gaming"

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
# Debian/Ubuntu ship it as fd-find; Fedora also calls it fd-find.
APP_PACKAGE_APT[fd]="fd-find"
APP_INSTALL_WINDOWS[fd]="winget install --id sharkdp.fd --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[htop]="brew install htop"
APP_PACKAGE_LINUX[htop]="htop"
APP_INSTALL_WINDOWS[htop]=""

APP_INSTALL_MAC[btop]="brew install btop"
APP_PACKAGE_LINUX[btop]="btop"
APP_INSTALL_WINDOWS[btop]=""

APP_INSTALL_MAC[tmux]="brew install tmux"
APP_PACKAGE_LINUX[tmux]="tmux"
APP_INSTALL_WINDOWS[tmux]=""

APP_INSTALL_MAC[zsh]="brew install zsh"
APP_PACKAGE_LINUX[zsh]="zsh"
APP_INSTALL_WINDOWS[zsh]=""

APP_INSTALL_MAC[oh-my-zsh]='RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
APP_INSTALL_LINUX[oh-my-zsh]='RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
APP_INSTALL_WINDOWS[oh-my-zsh]=""

APP_INSTALL_MAC[iterm2]="brew install --cask iterm2"
APP_PACKAGE_LINUX[iterm2]=""
APP_INSTALL_WINDOWS[iterm2]=""

APP_INSTALL_MAC[raycast]="brew install --cask raycast"
APP_PACKAGE_LINUX[raycast]=""
APP_INSTALL_WINDOWS[raycast]=""

APP_INSTALL_MAC[1password]="brew install --cask 1password"
APP_PACKAGE_LINUX[1password]=""
APP_INSTALL_WINDOWS[1password]="winget install --id AgileBits.1Password --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[rectangle]="brew install --cask rectangle"
APP_PACKAGE_LINUX[rectangle]=""
APP_INSTALL_WINDOWS[rectangle]=""

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
APP_INSTALL_WINDOWS[cursor]="winget install --id Anysphere.Cursor --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[docker]="brew install --cask docker"
APP_PACKAGE_LINUX[docker]="docker"
APP_PACKAGE_APT[docker]="docker.io"
APP_INSTALL_WINDOWS[docker]="winget install --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[postman]="brew install --cask postman"
APP_PACKAGE_LINUX[postman]=""
APP_INSTALL_WINDOWS[postman]="winget install --id Postman.Postman --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[slack]="brew install --cask slack"
APP_PACKAGE_LINUX[slack]=""
APP_INSTALL_WINDOWS[slack]="winget install --id SlackTechnologies.Slack --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[zoom]="brew install --cask zoom"
APP_PACKAGE_LINUX[zoom]=""
APP_INSTALL_WINDOWS[zoom]="winget install --id Zoom.Zoom --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[discord]="brew install --cask discord"
APP_PACKAGE_LINUX[discord]=""
APP_INSTALL_WINDOWS[discord]="winget install --id Discord.Discord --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[notion]="brew install --cask notion"
APP_PACKAGE_LINUX[notion]=""
APP_INSTALL_WINDOWS[notion]="winget install --id Notion.Notion --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[obsidian]="brew install --cask obsidian"
APP_PACKAGE_LINUX[obsidian]=""
APP_INSTALL_WINDOWS[obsidian]="winget install --id Obsidian.Obsidian --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[pandoc]="brew install pandoc"
APP_PACKAGE_LINUX[pandoc]="pandoc"
APP_INSTALL_WINDOWS[pandoc]="winget install --id JohnMacFarlane.Pandoc --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[figma]="brew install --cask figma"
APP_PACKAGE_LINUX[figma]=""
APP_INSTALL_WINDOWS[figma]="winget install --id Figma.Figma --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[imagemagick]="brew install imagemagick"
APP_PACKAGE_LINUX[imagemagick]="imagemagick"
APP_INSTALL_WINDOWS[imagemagick]="winget install --id ImageMagick.ImageMagick --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[python]="brew install python"
APP_PACKAGE_LINUX[python]="python3"
APP_INSTALL_WINDOWS[python]="winget install --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[duckdb]="brew install duckdb"
APP_PACKAGE_LINUX[duckdb]=""
APP_INSTALL_WINDOWS[duckdb]="winget install --id DuckDB.cli --accept-package-agreements --accept-source-agreements"

APP_INSTALL_MAC[steam]="brew install --cask steam"
APP_PACKAGE_LINUX[steam]="steam"
APP_INSTALL_WINDOWS[steam]="winget install --id Valve.Steam --accept-package-agreements --accept-source-agreements"
