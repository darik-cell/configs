# configs

Личные конфиги для:

- `nvim`
- `kitty`
- `IdeaVim`
- `mdview`

Структура репозитория повторяет расположение файлов в домашней директории:

- `.config/nvim`
- `.config/kitty`
- `.ideavimrc`
- `bin/mdview`

Пример подключения:

```bash
ln -sfn ~/configs/.config/nvim ~/.config/nvim
ln -sfn ~/configs/.config/kitty ~/.config/kitty
ln -sfn ~/configs/.ideavimrc ~/.ideavimrc
ln -sfn ~/configs/bin/mdview ~/bin/mdview
python3 -m pip install --user -r ~/configs/requirements/mdview.txt
```
