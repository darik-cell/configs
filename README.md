# configs

Переносимый комплект моих конфигов для Ubuntu 24.04:

- Neovim;
- Kitty;
- локальный Markdown viewer `mdview`;
- `.ideavimrc` (не устанавливается автоматически).

В Git лежит только то, что нельзя просто скачать заново: конфиги, plugin
lockfile, скрипт `mdview` и bootstrap-скрипты. Архивов Nvim, Kitty, шрифтов,
плагинов, LSP и Tree-sitter parsers в репозитории нет.

## Быстрая установка на новом host

Внимание: команда ниже намеренно удаляет старые пользовательские конфиги и
runtime-каталоги Nvim/Kitty. Она не удаляет проекты, SSH-ключи, Git-настройки
или системные пакеты.

```bash
git clone https://github.com/darik-cell/configs.git ~/configs
cd ~/configs
./install.sh --check
./install.sh
```

Скрипт сначала покажет точный список удаляемых путей и попросит подтверждение.
Для автономного запуска после проверки host:

```bash
./install.sh --yes
```

Если не хватает Ubuntu-пакетов, скрипт ничего не удалит, а напечатает готовую
`apt-get` команду. Подробный сценарий для агента: [AGENT_INSTALL.md](AGENT_INSTALL.md).

Повторная проверка:

```bash
cd ~/configs
./verify.sh
```
