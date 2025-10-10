#!/bin/bash

# ============================================================================
#
#              Vim/Neovim Quick Reference (vim_quick_reference.sh)
#
# ============================================================================
#
#  Purpose:
#  --------
#  A quick command reference for common Vim/Neovim operations. It can be run
#  anytime you forget a command or need to look something up quickly.
#
#  Tutorial Goal:
#  --------------
#  This script serves as a simple, accessible "cheat sheet" directly on the
#  command line. It is not a substitute for learning Vim properly but acts as
#  a helpful memory aid during day-to-day use, reinforcing the commands needed
#  for efficient terminal-based editing.
#
#  Prerequisites:
#  --------------
#  - None.
#
#  Workflow:
#  ---------
#  Run this script directly from your terminal (`./vim_quick_reference.sh`) to
#  display the reference guide.
#
# ============================================================================

readonly SCRIPT_VERSION="1.1.0"
readonly LAST_UPDATED="2025-10-10"
readonly TESTED_ON="Ubuntu 20.04"

cat << 'EOF'
╔════════════════════════════════════════════════════════════════════════════╗
║                      VIM/NEOVIM QUICK REFERENCE                            ║
╚════════════════════════════════════════════════════════════════════════════╝

📚 LEARNING RESOURCES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  vimtutor              Interactive 20-minute tutorial (run in terminal)
  https://www.openvim.com/      Interactive browser tutorial
  https://vim.rtorr.com/         Quick command cheatsheet
  https://neovim.io/doc/         Official Neovim documentation

💾 BASIC FILE OPERATIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  :w                    Write (save) file
  :w filename           Save as a new filename
  :q                    Quit (will warn if unsaved changes)
  :q!                   Quit without saving (force quit, discards changes)
  :wq                   Write and quit (two commands combined)
  :x                    Same as :wq (save and exit if changes were made)
  ZZ                    Same as :x (normal mode shortcut)
  ZQ                    Same as :q! (quit without saving)

🧭 NAVIGATION (NORMAL MODE)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  h j k l               Left, Down, Up, Right (basic movement)
  w                     Jump forward to start of next word
  b                     Jump backward to start of previous word
  0                     Jump to start of line
  ^                     Jump to first non-blank character of line
  $                     Jump to end of line
  gg                    Jump to first line of file
  G                     Jump to last line of file
  42G                   Jump to line 42 (replace 42 with any line number)
  Ctrl+u                Scroll up half a screen
  Ctrl+d                Scroll down half a screen
  Ctrl+b                Scroll up one full screen (back)
  Ctrl+f                Scroll down one full screen (forward)
  %                     Jump to matching bracket/parenthesis

🔍 SEARCHING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /pattern              Search forward for pattern
  ?pattern              Search backward for pattern
  n                     Jump to next search result
  N                     Jump to previous search result
  * Search forward for word under cursor
  #                     Search backward for word under cursor
  :noh                  Clear search highlighting

✂️  EDITING (INSERT MODE)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  i                     Enter insert mode at cursor
  I                     Enter insert mode at start of line
  a                     Enter insert mode after cursor
  A                     Enter insert mode at end of line
  o                     Open new line below and enter insert mode
  O                     Open new line above and enter insert mode
  Esc                   Exit insert mode (return to normal mode)

✂️  DELETING/CUTTING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  x                     Delete character under cursor
  X                     Delete character before cursor
  dd                    Delete (cut) entire line
  D                     Delete from cursor to end of line
  dw                    Delete (cut) word
  d$                    Delete from cursor to end of line
  d0                    Delete from cursor to start of line
  dG                    Delete from cursor to end of file
  dgg                   Delete from cursor to start of file

📋 COPYING (YANKING) AND PASTING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  yy                    Yank (copy) entire line
  yw                    Yank word
  y$                    Yank from cursor to end of line
  p                     Paste after cursor/below line
  P                     Paste before cursor/above line

  TUTORIAL: In Vim, "yank" means "copy". Think of it as yanking text out of
            the file. It goes into a clipboard (called a register). When you
            "delete" with dd or dw, it's actually cut - the text goes into
            the same clipboard and can be pasted with p.

🎯 VISUAL MODE (SELECTING TEXT)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  v                     Enter visual mode (select characters)
  V                     Enter visual line mode (select entire lines)
  Ctrl+v                Enter visual block mode (select columns)
  
  After entering visual mode, use movement keys (h/j/k/l) to expand selection:
  y                     Yank (copy) selected text
  d                     Delete (cut) selected text
  >                     Indent selected text
  <                     Unindent selected text
  
  SPECIAL: Select all and copy:
  ggVGy                 gg (top of file) + V (visual line) + G (end of file) + y (yank)

↩️  UNDO AND REDO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  u                     Undo last change
  Ctrl+r                Redo (undo the undo)
  U                     Undo all changes on current line

🔄 FIND AND REPLACE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  :s/old/new/           Replace first occurrence on current line
  :s/old/new/g          Replace all occurrences on current line
  :%s/old/new/g         Replace all occurrences in entire file
  :%s/old/new/gc        Replace all, but ask for confirmation each time

  EXAMPLE: To change all "foo" to "bar" in the file:
           :%s/foo/bar/g

📁 FILE BROWSER (NVIM-TREE)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Ctrl+n                Toggle file tree sidebar
  
  While in nvim-tree:
  Enter                 Open file/folder
  a                     Create new file/folder
  d                     Delete file/folder
  r                     Rename file/folder
  x                     Cut file/folder
  c                     Copy file/folder
  p                     Paste
  R                     Refresh tree

🔭 FUZZY FINDER (TELESCOPE)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Space ff              Find files by name
  Space fg              Find text in files (grep)
  Space fb              Find in open buffers
  Space fh              Search help documentation

  While in Telescope:
  Ctrl+j / Down         Move down in results
  Ctrl+k / Up           Move up in results
  Enter                 Open selected item
  Esc                   Close Telescope

🔧 LSP (LANGUAGE SERVER) COMMANDS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  gd                    Go to definition
  K                     Show hover documentation
  Space rn              Rename symbol (changes all references)
  Space ca              Show code actions (fixes/suggestions)
  gr                    Show all references
  Space f               Format document
  Space xx              Toggle diagnostic list (all errors/warnings)

🪟 WINDOWS AND TABS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  :split                Split window horizontally
  :vsplit               Split window vertically
  Ctrl+w h/j/k/l        Navigate between splits (left/down/up/right)
  Ctrl+w w              Cycle through windows
  Ctrl+w q              Close current window
  Ctrl+w =              Make all windows equal size

  :tabnew               Open new tab
  :tabn                 Next tab
  :tabp                 Previous tab
  gt                    Next tab (normal mode)
  gT                    Previous tab (normal mode)

❓ GETTING HELP
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  :help topic           Show help for a topic
  :help :w              Show help for the :w command
  :help dd              Show help for the dd command
  :checkhealth          Check Neovim setup and plugin status
  Space fh              Search help interactively (using Telescope)

🚨 COMMON MISTAKES AND HOW TO FIX THEM
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  "I can't type anything!"
    → You're in normal mode. Press 'i' to enter insert mode.

  "I can't save, it just types :w on screen!"
    → Press Esc first to exit insert mode, then type :w

  "I accidentally recorded a macro!"
    → Press 'q' to stop recording. To avoid this, don't press 'q' in normal mode.

  "Everything is highlighted and I can't edit!"
    → You're in visual mode. Press Esc to return to normal mode.

  "My file has [No Name] and won't save!"
    → Use :w filename to give it a name first.

  "I want to quit but it says 'No write since last change'!"
    → Either save first with :w, or force quit without saving using :q!

💡 TIPS FOR BEGINNERS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  1. Always know your mode:
     - Normal mode: For navigation and commands (press Esc to get here)
     - Insert mode: For typing text (press 'i' to get here)
     - Visual mode: For selecting text (press 'v' to get here)

  2. Esc is your friend - when in doubt, press Esc to return to normal mode

  3. Start with these basics:
     - i (enter insert mode)
     - Esc (return to normal mode)
     - :w (save)
     - :q (quit)
     - :wq (save and quit)

  4. Learn one new command per day - don't try to memorize everything at once

  5. Use 'vimtutor' - it's the best way to learn. Just type 'vimtutor' in your
     terminal and spend 20 minutes going through it.

╔════════════════════════════════════════════════════════════════════════════╗
║  Remember: Vim has a learning curve, but it's worth it. Be patient with    ║
║  yourself and practice regularly. Soon these commands will be muscle       ║
║  memory and you'll be editing faster than ever before.                     ║
╚════════════════════════════════════════════════════════════════════════════╝
EOF
