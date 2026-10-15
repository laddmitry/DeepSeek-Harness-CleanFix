# Состав и лицензии

| Компонент | Версия/назначение | Лицензия |
|---|---|---|
| Изменённые исходники Harness | upstream 0.2.0-rc.2, clean-win11-20261015 | MIT; LICENSE и THIRD_PARTY_NOTICES в корне |
| Собранный runtime | полный closure для Web/headless/SDK/ACP, Windows x64 | лицензии пакетов сохранены внутри Runtime |
| Node | 24.21.0 Windows x64 | [Node.txt](../../deploy/licenses/Node.txt), включая third-party notices |
| PowerShell | 7.6.6 Windows x64 | [MIT](../../deploy/licenses/PowerShell-LICENSE.txt), [third-party](../../deploy/licenses/PowerShell-ThirdPartyNotices.txt) |
| Ollama | 0.35.1, CPU subset exe/lib | [MIT](../../deploy/licenses/Ollama-LICENSE.txt); лицензии lib сохранены |
| Qwen3:0.6b | GGUF Q4_K_M, model blob 522640096 bytes | [Apache 2.0](../../deploy/licenses/Qwen3-LICENSE.txt); исходный license blob сохранён в Models |

Точные SHA-256 шести assets и каждой из 33 частей находятся в [payload/manifest.json](../../payload/manifest.json). Установщик проверяет части и собранные файлы перед исполнением. Windows ISO, лицензия Windows, установленные профили, пароли и диски VM не включены.

Источники лицензий: [Ollama](https://github.com/ollama/ollama/blob/main/LICENSE), [Qwen3-0.6B](https://huggingface.co/Qwen/Qwen3-0.6B/blob/main/LICENSE). Лицензия модели извлечена из поставляемого Ollama license layer с проверкой digest. Передача прав на товарные знаки и представление сборки официальным релизом DeepSeek не заявляются.

Для обычной установки сборка из исходников не нужна. Для разработки используйте package.json, pnpm-lock.yaml и документацию исходного проекта; обычная online-сборка требует pinned dependency toolchain. Публичная поставка проверяет готовый архив и исходные входы отдельно, не заявляя побайтовой воспроизводимости native-компиляции на произвольной машине.
