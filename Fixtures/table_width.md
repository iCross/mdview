# Table width fixture

This file verifies whether tables become "too narrow" under window resizing, and whether they can at least fill the container reasonably.

(Long preface) To verify that `--screenshot-scroll-to` truly scrolls to the target below, we intentionally include a long preface here.

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

## Table example (short content should nearly fill)

| Column A | Column B | Column C |
| --- | --- | --- |
| 1 | 2 | 3 |
| a | b | c |

## Table example (long content should wrap/scroll horizontally; should not wrap per character)

SCROLLTARGETTABLE

| Column | Content |
| --- | --- |
| long | This is a longer piece of text used to test how table cells behave when content grows; wrapping or horizontal scrolling is fine, but it should not collapse into an extremely narrow layout. |
| url | https://example.com/some/really/long/path/that/should/not/collapse/the/table/completely |

Postface: ensure the content is long enough to make scroll-to tests meaningful.
