# Table width fixture

這份檔案用來驗證 table 在視窗寬度下是否會「過窄」或能至少撐滿容器。

（前置長內容）為了驗證 `--screenshot-scroll-to` 確實會捲動到下方目標，這裡刻意放一段較長的前文。

Lorem ipsum dolor sit amet, consectetur adipiscing elit.
Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.
Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.

Lorem ipsum dolor sit amet, consectetur adipiscing elit.
Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.
Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.
Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.

## 表格範例（短內容應該接近撐滿）

| 欄位 A | 欄位 B | 欄位 C |
| --- | --- | --- |
| 1 | 2 | 3 |
| a | b | c |

## 表格範例（長內容應可水平捲動/不應每字換行）

SCROLLTARGETTABLE

| 欄位 | 內容 |
| --- | --- |
| long | 這是一段比較長的文字，用來測試表格欄位在內容變長時的行為；應該允許換行或水平捲動，但不應縮成極窄。 |
| url | https://example.com/some/really/long/path/that/should/not/collapse/the/table/completely |

後文段落：確保內容足夠長，方便測試 scroll-to。
