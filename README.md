# Move Mail Message

*Copyright 2026 Caleb Evans*  
*Released under the MIT license*

Move Mail Message is an [Alfred][alfred] workflow that enables you to quickly move one or more messages in the Apple Mail app to a different folder. You can search and filter down to the destination folder of your choice with just a few keystrokes.

[alfred]: https://www.alfredapp.com/

## Installation

To download the workflow, simply click one of the download links below.

[Download Move Mail Message][workflow-download-alfred5]

[workflow-download-alfred5]: https://github.com/caleb531/move-mail-message/raw/main/Move%20Mail%20Message.alfredworkflow

### Command Line Tools

If you are installing the workflow for the first time, you may be prompted to
install Apple's Command Line Tools. These developer tools are required
for the workflow to function, and fortunately, they have a much smaller size
footprint than full-blown Xcode.

<img src="screenshot-clt-installer.png" alt="Prompt to install Apple's Command Line Tools" width="461" />

## Usage

To use:

1. Select one or more messages in the Mail app; they must all be from the same account
2. Press <kbd>cmd-shift-m</kbd> to spawn the workflow; from here, you can filter to the desired destination folder
3. When you action the selected folder in Alfred, it will move all messages

Please note that this workflow requires accessibility permissions because it is the only reliable way to move messages from a scripting context.
